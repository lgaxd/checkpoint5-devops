#!/usr/bin/env bash
# Etapa 02 — Registra os resource providers usados e cria o Resource Group.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
step_begin "Resource providers e Resource Group"
require_login

echo "-- Resource providers"
for p in Microsoft.Web Microsoft.Sql Microsoft.Insights Microsoft.OperationalInsights; do
  if [[ "$(provider_state "$p")" == "Registered" ]]; then
    echo "$p: Registered"
  else
    echo "$p: registrando (aguarda a conclusão)..."
    az provider register --namespace "$p" --wait --output none
    echo "$p: $(provider_state "$p")"
  fi
done

echo "-- Resource Group '$RESOURCE_GROUP'"
if az group show --name "$RESOURCE_GROUP" --output none >/dev/null 2>&1; then
  echo "Já existe: reutilizado."
else
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
  echo "Criado em $LOCATION."
fi
az group show --name "$RESOURCE_GROUP" --query '{nome:name, regiao:location, estado:properties.provisioningState}' --output table
