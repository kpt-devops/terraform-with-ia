"""Webhook de Telegram (Function URL pública): recibe el clic y completa el callback de la ejecución durable.

Controles:
- Valida el secret token que Telegram envía en cada llamada (X-Telegram-Bot-Api-Secret-Token).
- Solo acepta clics del chat autorizado.
- La referencia del botón se borra al usarla (DeleteItem atómico): un segundo clic no hace nada.
"""

import base64
import hmac
import html
import json
import os

import boto3
from botocore.exceptions import ClientError

import telegram

_dynamodb = boto3.client("dynamodb")
_lambda = boto3.client("lambda")

CHAT_ID = os.environ["TELEGRAM_CHAT_ID"]
REFS_TABLE = os.environ["REFS_TABLE"]
WEBHOOK_SECRET_PARAM = os.environ["WEBHOOK_SECRET_PARAM"]

OK = {"statusCode": 200, "body": "ok"}


def _body(event: dict) -> dict:
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode()
    return json.loads(raw)


def handler(event, context):
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    received = headers.get("x-telegram-bot-api-secret-token", "")
    if not hmac.compare_digest(received, telegram.secret(WEBHOOK_SECRET_PARAM)):
        return {"statusCode": 401, "body": "unauthorized"}

    query = _body(event).get("callback_query")
    if not query:
        return OK  # solo interesan los clics en botones

    chat_id = str(query["message"]["chat"]["id"])
    if chat_id != CHAT_ID:
        telegram.answer_callback(query["id"], "No autorizado")
        return OK

    action, _, ref = (query.get("data") or "").partition(":")
    item = _dynamodb.delete_item(
        TableName=REFS_TABLE, Key={"ref": {"S": ref}}, ReturnValues="ALL_OLD"
    ).get("Attributes")
    if not item:
        telegram.answer_callback(query["id"], "Esta solicitud ya fue respondida o venció")
        return OK

    approved = action == "ok"
    user = query["from"].get("username") or query["from"].get("first_name", "alguien")
    try:
        _lambda.send_durable_execution_callback_success(
            CallbackId=item["callback_id"]["S"],
            Result=json.dumps({"approved": approved, "by": user}).encode(),
        )
    except ClientError as exc:
        print(json.dumps({"callback_error": exc.response["Error"]["Code"]}))
        telegram.answer_callback(query["id"], "La ejecución ya no está esperando (venció o terminó)")
        return OK

    verdict = f"✅ Aprobado por {html.escape(user)}: reprocesando…" if approved else f"⏸ En espera ({html.escape(user)}). No se reprocesó nada."
    telegram.answer_callback(query["id"], "Reprocesando" if approved else "En espera")
    telegram.replace_message(chat_id, query["message"]["message_id"], f"{html.escape(query['message'].get('text', ''))}\n\n{verdict}")
    return OK
