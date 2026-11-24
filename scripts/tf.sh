#!/usr/bin/env bash
# Único punto de entrada para Terraform: el entorno decide workspace, cuenta y región.
#   scripts/tf.sh <dev|prod> <deployment> <comando> [args...]
#   ej: scripts/tf.sh dev sqs-orders plan
# Valores por entorno: scripts/env/<entorno>.env (no versionado; ver example.env)
# o variables ya exportadas (CI): AWS_PROFILE, TF_VAR_region, TF_VAR_account_id,
# TF_STATE_BUCKET y TF_STATE_REGION (región del bucket; por defecto TF_VAR_region).
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
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  skip() { echo "::notice title=$PROJECT::$1; se omite '$CMD'." >&2; exit 0; }

  terraform workspace list | sed 's/^[* ]*//' | grep -qx "$ENV" \
    || skip "no está desplegado en $ENV (no hay workspace)"

  # Sin config en SSM, utils/environment falla al leerla: el deployment no está configurado aquí.
  PARAM="/terraform-with-ia/$ENV/$PROJECT"
  if ! out=$(aws ssm get-parameter --name "$PARAM" --query Parameter.Name --output text 2>&1); then
    [[ "$out" == *ParameterNotFound* ]] || { echo "$out" >&2; exit 1; }
    skip "no está configurado en $ENV (falta $PARAM en SSM)"
  fi

  # Deployments de los que este lee recursos con data sources (archivo depends-on, uno por línea).
  # Si alguno no tiene recursos en su state de este entorno (p. ej. una demo apagada), el plan
  # fallaría al buscarlos; se omite con aviso.
  if [ -f "$DIR/depends-on" ]; then
    while read -r dep; do
      dep="${dep%%#*}"; dep="${dep//[[:space:]]/}"
      [ -n "$dep" ] || continue
      key="env:/$ENV/deployments/$dep/terraform.tfstate"
      n=$(aws s3 cp "s3://$TF_STATE_BUCKET/$key" - --region "${TF_STATE_REGION:-$TF_VAR_region}" 2>/dev/null \
            | jq '[.resources[]? | select(.mode == "managed")] | length' 2>/dev/null || true)
      [ "${n:-0}" -gt 0 ] || skip "depende de '$dep', que no está desplegado en $ENV"
    done < "$DIR/depends-on"
  fi
fi
terraform workspace select -or-create "$ENV" >/dev/null
echo "[tf] deployment=$PROJECT entorno=$ENV workspace=$(terraform workspace show) perfil=${AWS_PROFILE:-<default>}" >&2
exec terraform "$CMD" "$@"
