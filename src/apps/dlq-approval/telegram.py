"""Cliente mínimo de la API de Telegram (sin dependencias). El token se lee de SSM, nunca de variables de entorno."""

import json
import os
import urllib.request

import boto3

_ssm = boto3.client("ssm")
_cache: dict[str, str] = {}


def secret(param_name: str) -> str:
    """Lee un parámetro SecureString de SSM y lo cachea mientras viva el entorno de ejecución."""
    if param_name not in _cache:
        _cache[param_name] = _ssm.get_parameter(Name=param_name, WithDecryption=True)["Parameter"]["Value"]
    return _cache[param_name]


def _call(method: str, payload: dict) -> dict:
    token = secret(os.environ["TELEGRAM_TOKEN_PARAM"])
    request = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/{method}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=10) as response:  # noqa: S310 - URL fija de Telegram
        return json.loads(response.read())


def send_message(chat_id: str, text: str, buttons: list[list[tuple[str, str]]] | None = None) -> int:
    """Envía un mensaje HTML. buttons = filas de (texto, callback_data); callback_data admite 64 bytes."""
    payload: dict = {"chat_id": chat_id, "text": text, "parse_mode": "HTML"}
    if buttons:
        payload["reply_markup"] = {
            "inline_keyboard": [[{"text": t, "callback_data": d} for t, d in row] for row in buttons]
        }
    return _call("sendMessage", payload)["result"]["message_id"]


def answer_callback(callback_query_id: str, text: str) -> None:
    """Cierra el "cargando" del botón en el chat."""
    _call("answerCallbackQuery", {"callback_query_id": callback_query_id, "text": text})


def replace_message(chat_id: str, message_id: int, text: str) -> None:
    """Reemplaza el texto del mensaje y quita los botones."""
    _call("editMessageText", {"chat_id": chat_id, "message_id": message_id, "text": text, "parse_mode": "HTML"})
