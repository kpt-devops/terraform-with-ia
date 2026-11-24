"""Consumidor de la cola de pedidos (demo 2: DLQ con aprobación).

Reporta los fallos por mensaje (ReportBatchItemFailures): solo se reintentan los mensajes que
fallaron y, tras maxReceiveCount intentos, SQS los mueve a la DLQ.

Cada error se registra con el messageId. SQS conserva ese id al mover el mensaje a la DLQ, así
que después se puede cruzar cada mensaje de la DLQ con su error en Logs Insights.

SIMULATE_BUG=true hace fallar todos los pedidos: sirve para llenar la DLQ en la demo.
"""

import json
import logging
import os

# Con log_format = JSON, el nivel lo define la configuración de logs de Lambda (no se fija aquí).
logger = logging.getLogger()

SIMULATE_BUG = os.environ.get("SIMULATE_BUG", "false").lower() == "true"


def process(order: dict) -> None:
    if SIMULATE_BUG:
        raise RuntimeError("SIMULATE_BUG activo: el consumidor rechaza todos los pedidos")
    amount = order["amount"]  # KeyError si el pedido no trae monto
    if amount <= 0:
        raise ValueError(f"monto inválido: {amount}")
    logger.info("Pedido procesado", extra={"orderId": order.get("id"), "amount": amount})


def handler(event, context):
    failures = []
    for record in event["Records"]:
        try:
            process(json.loads(record["body"]))
        except Exception as exc:  # noqa: BLE001 - cualquier error del pedido va a la DLQ, no rompe el lote
            logger.error(
                "Fallo al procesar el mensaje",
                extra={
                    "messageId": record["messageId"],
                    "errorType": type(exc).__name__,
                    "errorMessage": str(exc)[:300],
                    "receiveCount": int(record["attributes"]["ApproximateReceiveCount"]),
                },
            )
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}
