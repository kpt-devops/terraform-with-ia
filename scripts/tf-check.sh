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
# Caché de providers compartida: sin ella cada init copia el provider AWS (~700 MB) en cada carpeta.
# MAY_BREAK_DEPENDENCY_LOCK_FILE: los .terraform.lock.hcl no se versionan, así que sin esto
# Terraform ignora la caché en el primer init.
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
export TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true
mkdir -p "$TF_PLUGIN_CACHE_DIR"
fail() { echo "[tf-check] $1" >&2; exit 2; }

terraform fmt -check -recursive "$SRC" >/dev/null || fail "fmt: ejecuta terraform fmt -recursive src"
for DIR in "$SRC"/deployments/*/; do
  DIR="${DIR%/}"
  # Data dir propio: si tf.sh ya inicializó el backend S3 en .terraform/, init -backend=false
  # lo reutiliza y pide credenciales. Este queda dentro de .terraform/ (ignorado por git).
  export TF_DATA_DIR="$PWD/$DIR/.terraform/check"
  terraform -chdir="$DIR" init -backend=false -input=false >/dev/null || fail "$DIR: init falló"
  terraform -chdir="$DIR" validate -no-color 1>&2 || fail "$DIR: validate (argumento o tipo inválido)"
  tflint --chdir="$DIR" --config="$PWD/$SRC/.tflint.hcl" --call-module-type=local --format=compact 1>&2 || fail "$DIR: tflint"
done
# Tests nativos (terraform test) de cada módulo con carpeta tests/: offline, con mock_provider.
for TESTS in "$SRC"/modules/*/*/tests/; do
  [ -d "$TESTS" ] || continue
  DIR="${TESTS%/tests/}"
  export TF_DATA_DIR="$PWD/$DIR/.terraform/check"
  terraform -chdir="$DIR" init -backend=false -input=false >/dev/null || fail "$DIR: init falló"
  terraform -chdir="$DIR" test -no-color 1>&2 || fail "$DIR: terraform test falló"
done
unset TF_DATA_DIR
LOG_LEVEL=ERROR checkov -d "$SRC" --framework terraform --download-external-modules true --quiet --compact 1>&2 || fail "checkov: hallazgo de seguridad"
exit 0
