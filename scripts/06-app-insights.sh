#!/usr/bin/env bash
# Etapa 06 — Application Insights: recurso de telemetria (requests, dependências, logs,
# métricas e exceções) que recebe os dados do agente Java do Web App.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
step_begin "Application Insights"
require_login

if az monitor app-insights component show --resource-group "$RESOURCE_GROUP" --app "$APP_INSIGHTS_NAME" --output none >/dev/null 2>&1; then
  echo "Application Insights '$APP_INSIGHTS_NAME' já existe: reutilizado."
else
  echo "Criando Application Insights '$APP_INSIGHTS_NAME' em $LOCATION..."
  az monitor app-insights component create \
    --resource-group "$RESOURCE_GROUP" \
    --app "$APP_INSIGHTS_NAME" \
    --location "$LOCATION" \
    --application-type web \
    --kind web \
    --output none
  echo "Criado."
fi
az monitor app-insights component show --resource-group "$RESOURCE_GROUP" --app "$APP_INSIGHTS_NAME" \
  --query '{insights:name, regiao:location, estado:provisioningState}' --output table
echo "A connection string não é exibida; ela é lida e aplicada aos App Settings na etapa 08."
