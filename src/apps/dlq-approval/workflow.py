"""Función durable: revisa la DLQ, pide aprobación por Telegram y reprocesa solo si alguien aprueba.

Fase 1 de la demo: aprobación + redrive completo. Las fases siguientes agregan el diagnóstico
(trigger y logs) y el redrive canario.

Reglas de durable functions que este código respeta:
- Todo lo que toca el exterior (SQS, DynamoDB, Telegram) va dentro de un step: en el replay,
  los steps terminados devuelven su resultado guardado y no se vuelven a ejecutar.
- Fuera de los steps no hay nada aleatorio ni dependiente de la hora.
"""

import html
import os
import secrets
import time

import boto3
from aws_durable_execution_sdk_python import CallbackTimeoutError, DurableContext, durable_execution
from aws_durable_execution_sdk_python.config import Duration, WaitForCallbackConfig

import telegram

_sqs = boto3.client("sqs")
_dynamodb = boto3.client("dynamodb")

DLQ_URL = os.environ["DLQ_URL"]
DLQ_ARN = os.environ["DLQ_ARN"]
QUEUE_NAME = os.environ["QUEUE_NAME"]
CHAT_ID = os.environ["TELEGRAM_CHAT_ID"]
REFS_TABLE = os.environ["REFS_TABLE"]
APPROVAL_TIMEOUT_HOURS = int(os.environ.get("APPROVAL_TIMEOUT_HOURS", "24"))
POLL_SECONDS = 30
MAX_POLLS = 40  # 20 minutos de seguimiento del redrive como máximo
FINAL_STATES = ("COMPLETED", "FAILED", "CANCELLED")


# ---------- Acciones (cada una corre dentro de un step) ----------

def inspect_dlq() -> dict:
    attrs = _sqs.get_queue_attributes(
        QueueUrl=DLQ_URL,
        AttributeNames=["ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible"],
    )["Attributes"]
    return {
        "visible": int(attrs["ApproximateNumberOfMessages"]),
        "in_flight": int(attrs["ApproximateNumberOfMessagesNotVisible"]),
    }


def request_approval(info: dict, callback_id: str) -> None:
    # callback_data de Telegram admite 64 bytes y el callback_id llega a 1024:
    # el botón lleva una referencia corta que el webhook resuelve en DynamoDB (con TTL).
    ref = secrets.token_urlsafe(9)
    expires = int(time.time()) + (APPROVAL_TIMEOUT_HOURS + 1) * 3600
    _dynamodb.put_item(
        TableName=REFS_TABLE,
        Item={"ref": {"S": ref}, "callback_id": {"S": callback_id}, "expires_at": {"N": str(expires)}},
    )
    text = (
        f"🔴 <b>DLQ de {html.escape(QUEUE_NAME)}</b>: {info['visible']} mensajes\n\n"
        "¿Ya está corregida la causa? <b>Reprocesar</b> los devuelve a la cola original.\n"
        f"Sin respuesta en {APPROVAL_TIMEOUT_HOURS} h no se toca nada."
    )
    telegram.send_message(CHAT_ID, text, [[("✅ Reprocesar", f"ok:{ref}"), ("⏸ Esperar", f"no:{ref}")]])


def start_redrive() -> str:
    # Sin DestinationArn: SQS devuelve cada mensaje a la cola de la que vino.
    return _sqs.start_message_move_task(SourceArn=DLQ_ARN)["TaskHandle"]


def redrive_status() -> dict:
    task = _sqs.list_message_move_tasks(SourceArn=DLQ_ARN, MaxResults=1)["Results"][0]
    return {
        "status": task["Status"],
        "moved": task.get("ApproximateNumberOfMessagesMoved", 0),
        "to_move": task.get("ApproximateNumberOfMessagesToMove"),
        "reason": task.get("FailureReason"),
    }


def notify(text: str) -> None:
    telegram.send_message(CHAT_ID, text)


def summary(status: dict, approved_by: str) -> str:
    name = html.escape(QUEUE_NAME)
    if status.get("status") == "COMPLETED":
        return f"✅ DLQ de {name}: {status['moved']} mensajes devueltos a la cola (aprobó {html.escape(approved_by)})."
    if status.get("status") in FINAL_STATES:
        reason = html.escape(status.get("reason") or "sin detalle")
        return f"⚠️ DLQ de {name}: el redrive terminó en {status['status']} ({reason}). Movidos: {status['moved']}."
    return f"⏳ DLQ de {name}: el redrive sigue en curso ({status.get('moved', 0)} movidos). Revísalo en la consola de SQS."


# ---------- Flujo durable ----------

@durable_execution
def handler(event, context: DurableContext):
    info = context.step(lambda _: inspect_dlq(), name="inspect")
    if info["visible"] == 0:
        return {"status": "empty"}

    try:
        decision = context.wait_for_callback(
            lambda callback_id, _ctx: request_approval(info, callback_id),
            name="approval",
            config=WaitForCallbackConfig(timeout=Duration.from_hours(APPROVAL_TIMEOUT_HOURS)),
        )
    except CallbackTimeoutError:
        context.step(
            lambda _: notify(f"⏰ DLQ de {html.escape(QUEUE_NAME)}: nadie respondió en {APPROVAL_TIMEOUT_HOURS} h. No se reprocesó nada."),
            name="notify-timeout",
        )
        return {"status": "timeout"}

    if not decision or not decision.get("approved"):
        return {"status": "on-hold", "by": (decision or {}).get("by")}

    context.step(lambda _: start_redrive(), name="redrive")

    status: dict = {}
    for i in range(MAX_POLLS):
        context.wait(Duration.from_seconds(POLL_SECONDS), name=f"wait-{i}")  # la espera no cobra cómputo
        status = context.step(lambda _: redrive_status(), name=f"status-{i}")
        if status["status"] in FINAL_STATES:
            break

    context.step(lambda _: notify(summary(status, decision.get("by", "?"))), name="notify-result")
    return {"status": status.get("status"), "moved": status.get("moved")}
