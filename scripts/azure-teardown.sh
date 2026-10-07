#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.env"
  set +a
fi

RM="${RM:-561413}"
RESOURCE_GROUP="${RESOURCE_GROUP:-${RM}-dimdim-rg}"

if ! az account show --output none >/dev/null 2>&1; then
  echo "Faça login com 'az login' antes do teardown." >&2
  exit 1
fi

echo "ATENÇÃO: todos os recursos e dados do Resource Group '$RESOURCE_GROUP' serão excluídos."
read -r -p "Digite o nome exato do Resource Group para confirmar: " CONFIRMATION
if [[ "$CONFIRMATION" != "$RESOURCE_GROUP" ]]; then
  echo "Confirmação não corresponde. Nenhum recurso foi removido."
  exit 0
fi

az group delete --name "$RESOURCE_GROUP" --yes --no-wait
echo "Exclusão iniciada para '$RESOURCE_GROUP'."
