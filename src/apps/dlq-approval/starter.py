"""Starter: EventBridge -> esta función -> función durable (asíncrona, por alias, con nombre).

EventBridge no puede enviar DurableExecutionName. Esta función lo arma a partir del id del evento:
si EventBridge o Lambda reintentan el mismo evento, Lambda devuelve la ejecución existente en lugar
de crear otra (idempotencia).
"""

import json
import os
import re

import boto3
from botocore.exceptions import ClientError

_lambda = boto3.client("lambda")

DURABLE_FUNCTION_ARN = os.environ["DURABLE_FUNCTION_ARN"]  # ARN del alias: la ejecución queda atada a esa versión
QUEUE_NAME = os.environ["QUEUE_NAME"]


def execution_name(event: dict) -> str:
    # DurableExecutionName: 1-64 caracteres, letras, números, - y _
    return re.sub(r"[^A-Za-z0-9_-]", "-", f"dlq-{QUEUE_NAME}-{event['id']}")[:64]


def handler(event, context):
    name = execution_name(event)
    try:
        _lambda.invoke(
            FunctionName=DURABLE_FUNCTION_ARN,
            InvocationType="Event",
            DurableExecutionName=name,
            Payload=json.dumps(event).encode(),
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] != "DurableExecutionAlreadyStartedException":
            raise
        print(json.dumps({"execution": name, "status": "already-started"}))
        return {"execution": name, "status": "already-started"}
    print(json.dumps({"execution": name, "status": "started"}))
    return {"execution": name, "status": "started"}
