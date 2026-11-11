#!/usr/bin/env bash
# Hook de validación: exit 2 devuelve stderr al agente como feedback.
set -uo pipefail

# Si lo invoca el hook, solo validar cuando se editó un archivo Terraform.
if [ ! -t 0 ]; then
  input="$(cat)"
  if [ -n "$input" ] && ! printf '%s' "$input" | grep -qE '\.tf(vars)?"'; then
    exit 0
  fi
fi

DIR="${TF_DIR:-envs/dev}"
fail() { echo "[tf-check] $1" >&2; exit 2; }

terraform fmt -check -recursive >/dev/null || fail "fmt: ejecuta terraform fmt -recursive"
terraform -chdir="$DIR" init -backend=false -input=false >/dev/null || fail "init falló"
terraform -chdir="$DIR" validate -no-color 1>&2 || fail "validate: argumento o tipo inválido"
tflint --chdir="$DIR" --format=compact 1>&2 || fail "tflint: revisa las reglas"
checkov -d . --framework terraform --quiet --compact 1>&2 || fail "checkov: hallazgo de seguridad"
exit 0
