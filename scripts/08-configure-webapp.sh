#!/usr/bin/env bash
# Etapa 08 — Configura o Web App: App Settings (conexão com o banco, JWT, Application
# Insights, porta 80, perfil azure), Always On e comando de inicialização da JVM com o agente.
# Os segredos ficam somente nos App Settings do Azure, nunca no código.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
step_begin "Configuração do Web App (App Settings e inicialização)"
require_env DATABASE_USERNAME DATABASE_PASSWORD JWT_SECRET
require_login

STARTUP_FILE="java -XX:TieredStopAtLevel=1 -XX:+UseSerialGC -javaagent:/home/site/wwwroot/applicationinsights-agent.jar -Dserver.port=${APP_PORT} -jar /home/site/wwwroot/app.jar"

echo "-- Connection string do Application Insights (lida do recurso, não exibida)"
AI_CONN="$(az monitor app-insights component show --resource-group "$RESOURCE_GROUP" --app "$APP_INSIGHTS_NAME" --query connectionString --output tsv)"
[[ -n "$AI_CONN" ]] || die "Application Insights sem connection string. Rode a etapa 06."

echo "-- App Settings"
SETTINGS_FILE="$(mktemp "${TMPDIR:-/tmp}/dimdim-appsettings.XXXXXX.json")"
trap 'rc=$?; rm -f "$SETTINGS_FILE"; step_finish "$rc"' EXIT
{
  printf '{\n  "DATABASE_URL": ';                          json_value "$DATABASE_URL"
  printf ',\n  "DATABASE_USERNAME": ';                     json_value "$DATABASE_USERNAME"
  printf ',\n  "DATABASE_PASSWORD": ';                     json_value "$DATABASE_PASSWORD"
  printf ',\n  "JWT_SECRET": ';                            json_value "$JWT_SECRET"
  printf ',\n  "JWT_EXPIRATION": ';                        json_value "${JWT_EXPIRATION:-86400000}"
  printf ',\n  "APPLICATIONINSIGHTS_CONNECTION_STRING": '; json_value "$AI_CONN"
  printf ',\n  "APPLICATIONINSIGHTS_ROLE_NAME": ';         json_value "dimdim"
  printf ',\n  "WEBSITES_PORT": ';                         json_value "$APP_PORT"
  printf ',\n  "WEBSITES_CONTAINER_START_TIME_LIMIT": ';   json_value "600"
  printf ',\n  "SPRING_PROFILES_ACTIVE": ';                json_value "azure"
  printf '\n}\n'
} > "$SETTINGS_FILE"
az webapp config appsettings set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEB_APP_NAME" \
  --settings "@$SETTINGS_FILE" \
  --output none
echo "Aplicados (somente os nomes são exibidos):"
az webapp config appsettings list --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" --query '[].name' --output tsv | sed 's/^/    /'

echo "-- Always On e comando de inicialização (porta $APP_PORT, agente Application Insights)"
az webapp config set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEB_APP_NAME" \
  --always-on true \
  --startup-file "$STARTUP_FILE" \
  --output none
echo "Startup: $STARTUP_FILE"
