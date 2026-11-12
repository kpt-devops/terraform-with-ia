#!/usr/bin/env bash
# Único punto de entrada para Terraform: el entorno decide workspace, cuenta y región.
#   scripts/tf.sh <dev|prod> <deployment> <comando> [args...]
#   ej: scripts/tf.sh dev sqs-orders plan
# Valores por entorno: scripts/env/<entorno>.env (no versionado; ver example.env)
# o variables ya exportadas (CI): AWS_PROFILE, TF_VAR_region, TF_VAR_account_id.
set -euo pipefail

ENVS="dev prod"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
usage() { echo "uso: $0 <dev|prod> <deployment> <comando> [args...]" >&2; exit 1; }

[ $# -ge 3 ] || usage
ENV="$1"; PROJECT="$2"; CMD="$3"; shift 3

[[ " $ENVS " == *" $ENV "* ]] || { echo "entorno inválido: $ENV (válidos: $ENVS)" >&2; exit 1; }
DIR="$ROOT/src/deployments/$PROJECT"
[ -d "$DIR" ] || { echo "deployment no existe: src/deployments/$PROJECT" >&2; ls "$ROOT/src/deployments" >&2; exit 1; }

# El agente prepara PRs; aplicar cambios es decisión humana.
case "$CMD" in
  apply|destroy|import|state|taint|untaint|force-unlock)
    if [ -n "${CLAUDECODE:-}" ]; then
      echo "bloqueado: '$CMD' no se ejecuta desde el agente. Córrelo tú en tu terminal." >&2
      exit 2
    fi ;;
esac

ENV_FILE="$ROOT/scripts/env/$ENV.env"
if [ -f "$ENV_FILE" ]; then
  set -a; . "$ENV_FILE"; set +a
fi
: "${TF_VAR_region:?define TF_VAR_region en scripts/env/$ENV.env o en el entorno}"
export TF_VAR_account_id="${TF_VAR_account_id:-}"

cd "$DIR"
terraform init -input=false ${TF_INIT_ARGS:-} >/dev/null
terraform workspace select -or-create "$ENV" >/dev/null
echo "[tf] deployment=$PROJECT entorno=$ENV workspace=$(terraform workspace show) perfil=${AWS_PROFILE:-<default>}" >&2
exec terraform "$CMD" "$@"
