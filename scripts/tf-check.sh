#!/usr/bin/env bash
# Hook de validación: exit 2 devuelve stderr al agente como feedback.
# No necesita credenciales: valida cada deployment de src/deployments sin backend.
set -uo pipefail

# Si lo invoca el hook, solo validar cuando se editó un archivo Terraform.
if [ ! -t 0 ]; then
  input="$(cat)"
  if [ -n "$input" ] && ! printf '%s' "$input" | grep -qE '\.tf(vars)?"'; then
    exit 0
  fi
fi

SRC="src"
fail() { echo "[tf-check] $1" >&2; exit 2; }

terraform fmt -check -recursive "$SRC" >/dev/null || fail "fmt: ejecuta terraform fmt -recursive src"
for DIR in "$SRC"/deployments/*/; do
  DIR="${DIR%/}"
  terraform -chdir="$DIR" init -backend=false -input=false >/dev/null || fail "$DIR: init falló"
  terraform -chdir="$DIR" validate -no-color 1>&2 || fail "$DIR: validate (argumento o tipo inválido)"
  tflint --chdir="$DIR" --config="$PWD/$SRC/.tflint.hcl" --call-module-type=local --format=compact 1>&2 || fail "$DIR: tflint"
done
checkov -d "$SRC" --framework terraform --download-external-modules true --quiet --compact 1>&2 || fail "checkov: hallazgo de seguridad"
exit 0
