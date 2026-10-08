#!/usr/bin/env bash
# Etapa 99 — Teardown: exclui o Resource Group e TODOS os seus recursos e dados.
# Execute somente depois de gravar o vídeo e salvar as evidências.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require_login

echo "ATENÇÃO: todos os recursos e dados do Resource Group '$RESOURCE_GROUP' serão excluídos."
read -r -p "Digite o nome exato do Resource Group para confirmar: " CONFIRMATION
if [[ "$CONFIRMATION" != "$RESOURCE_GROUP" ]]; then
  echo "Confirmação não corresponde. Nenhum recurso foi removido."
  exit 0
fi

az group delete --name "$RESOURCE_GROUP" --yes --no-wait
echo "Exclusão iniciada para '$RESOURCE_GROUP'."
