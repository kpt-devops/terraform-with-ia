#!/usr/bin/env bash
# Sube la config de un deployment a SSM Parameter Store: /terraform-with-ia/<entorno>/<deployment>
#   scripts/config-push.sh <dev|prod> <deployment>
# Lee src/deployments/<deployment>/config.<entorno>.json (no versionado; parte de config.example.json).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -eq 2 ] || { echo "uso: $0 <dev|prod> <deployment>" >&2; exit 1; }
ENV="$1"; PROJECT="$2"
FILE="$ROOT/src/deployments/$PROJECT/config.$ENV.json"
[ -f "$FILE" ] || { echo "falta $FILE (copia config.example.json)" >&2; exit 1; }
ENV_FILE="$ROOT/scripts/env/$ENV.env"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }
python3 -m json.tool "$FILE" >/dev/null || { echo "JSON inválido: $FILE" >&2; exit 1; }
aws ssm put-parameter --name "/terraform-with-ia/$ENV/$PROJECT" --type SecureString \
  --value "file://$FILE" --overwrite --region "${TF_VAR_region:?}" >/dev/null
echo "ok: /terraform-with-ia/$ENV/$PROJECT"
