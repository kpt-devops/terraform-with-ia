#!/usr/bin/env bash
# Uso: ./demos/cost-explainer/scripts/invoke-sample.sh [replay|uso|sin-evidencia]
#   replay         -> analiza la anomalía real más reciente de la cuenta (últimos 90 días)
#   uso            -> evento simulado de Lambda; la evidencia sale de tus datos reales
#   sin-evidencia  -> evento simulado sin respaldo en los datos; el agente debe admitirlo
set -euo pipefail
MODE="${1:-replay}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# Entorno: ENV=prod ./invoke-sample.sh ...  (por defecto dev). Toma perfil y región de scripts/env/<entorno>.env
ENV="${ENV:-dev}"
if [ -f "$ROOT/scripts/env/$ENV.env" ]; then set -a; . "$ROOT/scripts/env/$ENV.env"; set +a; fi
export AWS_REGION="${TF_VAR_region:-${AWS_REGION:-us-east-1}}"
FN="$("$ROOT/scripts/tf.sh" "$ENV" finops-cost-explainer output -raw lambda_name)"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
EVENT="$(mktemp)"

python3 - "$MODE" "$ACCOUNT" > "$EVENT" <<'PY'
import datetime as dt, json, sys
mode, account = sys.argv[1], sys.argv[2]
if mode == "replay":
    print(json.dumps({"replay_last": True}))
    sys.exit()
today = dt.date.today()
start, end = today - dt.timedelta(days=2), today - dt.timedelta(days=1)
samples = {
    "uso": ("AWS Lambda", "USE1-Lambda-GB-Second", 42.5, 180),
    "sin-evidencia": ("Amazon Elastic Compute Cloud - Compute", "USE1-BoxUsage:t3.medium", 12.0, 35),
}
service, usage_type, impact, pct = samples[mode]
message = {
    "accountId": account,
    "anomalyId": f"demo-{mode}-{today:%Y%m%d}",
    "anomalyStartDate": f"{start}T00:00:00Z",
    "anomalyEndDate": f"{end}T00:00:00Z",
    "impact": {"totalImpact": impact, "totalImpactPercentage": pct},
    "rootCauses": [{"service": service, "region": "us-east-1",
                    "usageType": usage_type, "linkedAccount": account}],
}
print(json.dumps({"Records": [{"Sns": {"Message": json.dumps(message)}}]}))
PY

aws lambda invoke --function-name "$FN" --cli-binary-format raw-in-base64-out \
  --payload "file://$EVENT" "$EVENT.out" >/dev/null
python3 -m json.tool "$EVENT.out"
