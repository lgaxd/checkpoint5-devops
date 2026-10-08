#!/usr/bin/env bash
# Etapa 05 — App Service: plano Linux B1 e Web App com runtime Java 21 (somente HTTPS).
#
# ATENÇÃO: o plano é criado em UMA única tentativa. Criar e apagar planos em loop na
# mesma região pode fazer a Azure bloquear a capacidade da região por tempo prolongado.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
step_begin "App Service Plan (Linux B1) e Web App (Java 21)"
require_login

echo "-- App Service Plan '$APP_SERVICE_PLAN'"
if az appservice plan show --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_PLAN" --output none >/dev/null 2>&1; then
  echo "Já existe: reutilizado."
else
  echo "Criando (B1 Linux) em $LOCATION: uma única tentativa, sem retry..."
  az appservice plan create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_SERVICE_PLAN" \
    --location "$LOCATION" \
    --is-linux \
    --sku B1 \
    --output none \
    || die "O Azure recusou a criação do plano (mensagem acima). Não repita em loop; troque LOCATION ou aguarde."
  echo "Criado."
fi

echo "-- Web App '$WEB_APP_NAME'"
if az webapp show --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" --output none >/dev/null 2>&1; then
  echo "Já existe: reutilizado."
else
  az webapp create \
    --resource-group "$RESOURCE_GROUP" \
    --plan "$APP_SERVICE_PLAN" \
    --name "$WEB_APP_NAME" \
    --runtime "JAVA:21-java21" \
    --https-only true \
    --output none
  echo "Criado."
fi
az webapp show --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" \
  --query '{webapp:name, estado:state, regiao:location, url:defaultHostName}' --output table
