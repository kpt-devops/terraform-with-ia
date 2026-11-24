#!/usr/bin/env bash
# Envía pedidos de prueba a la cola orders-<entorno>.
#   demos/dlq-approval/scripts/send-orders.sh <dev|prod> <cantidad> [validos|sin-monto]
# "sin-monto" genera pedidos sin el campo amount: el consumidor falla (KeyError) y, tras
# maxReceiveCount intentos, SQS los mueve a la DLQ.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
[ $# -ge 2 ] || { echo "uso: $0 <dev|prod> <cantidad> [validos|sin-monto]" >&2; exit 1; }
ENV="$1"; COUNT="$2"; KIND="${3:-validos}"
ENV_FILE="$ROOT/scripts/env/$ENV.env"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }
REGION="${TF_VAR_region:?define TF_VAR_region en scripts/env/$ENV.env}"
URL=$(aws sqs get-queue-url --queue-name "orders-$ENV" --region "$REGION" --query QueueUrl --output text)

for ((i = 1; i <= COUNT; i++)); do
  if [ "$KIND" = "sin-monto" ]; then
    BODY="{\"id\":\"demo-$i\",\"currency\":\"USD\"}"
  else
    BODY="{\"id\":\"demo-$i\",\"amount\":$((i * 10)),\"currency\":\"USD\"}"
  fi
  aws sqs send-message --queue-url "$URL" --message-body "$BODY" --region "$REGION" >/dev/null
done
echo "ok: $COUNT pedidos ($KIND) enviados a orders-$ENV"
