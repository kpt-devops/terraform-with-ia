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
# Un bucket de state por cuenta: dev y prod viven en cuentas distintas.
: "${TF_STATE_BUCKET:?define TF_STATE_BUCKET en scripts/env/$ENV.env o en el entorno}"

cd "$DIR"
# -reconfigure: al cambiar de entorno cambia el bucket; nunca migra state entre cuentas.
terraform init -input=false -reconfigure \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="region=${TF_STATE_REGION:-$TF_VAR_region}" \
  ${TF_INIT_ARGS:-} >/dev/null
# En CI el rol de plan es de solo lectura: no puede crear el state de un workspace nuevo. Si el
# deployment aún no está desplegado en este entorno, se omite con un aviso (el primer apply es manual).
if [ -n "${GITHUB_ACTIONS:-}" ] && ! terraform workspace list | sed 's/^[* ]*//' | grep -qx "$ENV"; then
  echo "::notice title=$PROJECT::no está desplegado en $ENV (no hay workspace); se omite '$CMD'." >&2
  exit 0
fi
terraform workspace select -or-create "$ENV" >/dev/null
echo "[tf] deployment=$PROJECT entorno=$ENV workspace=$(terraform workspace show) perfil=${AWS_PROFILE:-<default>}" >&2
exec terraform "$CMD" "$@"
