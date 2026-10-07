#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_SETTINGS_FILE=""
STAGING_DIR=""

cleanup_deploy_files() {
  if [[ -n "$APP_SETTINGS_FILE" && -f "$APP_SETTINGS_FILE" ]]; then
    rm -f -- "$APP_SETTINGS_FILE"
  fi
  if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
    rm -rf -- "$STAGING_DIR"
  fi
}
trap cleanup_deploy_files EXIT

if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.env"
  set +a
fi

RM="${RM:-561413}"
LOCATION="${LOCATION:-brazilsouth}"
RESOURCE_GROUP="${RESOURCE_GROUP:-${RM}-dimdim-rg}"
SQL_SERVER_NAME="${SQL_SERVER_NAME:-sql-server-dimdim-${RM}}"
SQL_DATABASE_NAME="${SQL_DATABASE_NAME:-db-dimdim}"
APP_SERVICE_PLAN="${APP_SERVICE_PLAN:-${RM}-dimdim-plan}"
WEB_APP_NAME="${WEB_APP_NAME:-${RM}-dimdim-webapp}"
APP_INSIGHTS_NAME="${APP_INSIGHTS_NAME:-${RM}-dimdim-insights}"

: "${SQL_ADMIN_USERNAME:?Defina SQL_ADMIN_USERNAME no ambiente ou em .env}"
: "${SQL_ADMIN_PASSWORD:?Defina SQL_ADMIN_PASSWORD no ambiente ou em .env}"
: "${DATABASE_USERNAME:?Defina DATABASE_USERNAME no ambiente ou em .env}"
: "${DATABASE_PASSWORD:?Defina DATABASE_PASSWORD no ambiente ou em .env}"
: "${JWT_SECRET:?Defina JWT_SECRET no ambiente ou em .env}"
if [[ -z "${CLIENT_IP:-}" ]]; then
  echo "Defina CLIENT_IP com o IPv4 público exato desta máquina para inicializar o Azure SQL." >&2
  echo "O firewall não será aberto para uma faixa universal." >&2
  exit 1
fi

if [[ ! "$SQL_SERVER_NAME" =~ ^[a-z0-9]{1,63}$ ]]; then
  echo "SQL_SERVER_NAME deve conter somente letras minúsculas e números (1-63 caracteres)." >&2
  exit 1
fi
if [[ ! "$WEB_APP_NAME" =~ ^[A-Za-z0-9-]{2,60}$ ]]; then
  echo "WEB_APP_NAME deve conter somente letras, números e hífens (2-60 caracteres)." >&2
  exit 1
fi
if [[ ! "$CLIENT_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "CLIENT_IP deve ser um endereço IPv4 explícito." >&2
  exit 1
fi
IFS=. read -r IP_OCTET_1 IP_OCTET_2 IP_OCTET_3 IP_OCTET_4 <<< "$CLIENT_IP"
for ip_octet in "$IP_OCTET_1" "$IP_OCTET_2" "$IP_OCTET_3" "$IP_OCTET_4"; do
  if (( 10#$ip_octet > 255 )); then
    echo "CLIENT_IP contém um octeto fora do intervalo IPv4." >&2
    exit 1
  fi
done

if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "$AZURE_SUBSCRIPTION_ID"
fi
if ! az account show --output none >/dev/null 2>&1; then
  echo "Faça login com 'az login' e selecione a subscription antes de continuar." >&2
  exit 1
fi
if ! command -v zip >/dev/null 2>&1; then
  echo "O comando zip é necessário para montar o pacote do App Service." >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "O comando curl é necessário para baixar o agente oficial do Application Insights." >&2
  exit 1
fi

echo "Criando ou atualizando recursos do DimDim na subscription $(az account show --query id -o tsv)..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
for provider in Microsoft.Sql Microsoft.Insights Microsoft.OperationalInsights; do
  state="$(az provider show --namespace "$provider" --query registrationState --output tsv 2>/dev/null || true)"
  if [[ "$state" != "Registered" ]]; then
    az provider register --namespace "$provider" --output none
    for _ in {1..30}; do
      state="$(az provider show --namespace "$provider" --query registrationState --output tsv 2>/dev/null || true)"
      [[ "$state" == "Registered" ]] && break
      sleep 5
    done
  fi
done

if ! az sql server show --resource-group "$RESOURCE_GROUP" --name "$SQL_SERVER_NAME" --output none >/dev/null 2>&1; then
  az sql server create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$SQL_SERVER_NAME" \
    --location "$LOCATION" \
    --admin-user "$SQL_ADMIN_USERNAME" \
    --admin-password "$SQL_ADMIN_PASSWORD" \
    --enable-public-network true \
    --no-wait \
    --output none 2>/dev/null
  echo "Aguardando o SQL Server ficar pronto..."
  for _ in {1..60}; do
    state="$(az sql server show --resource-group "$RESOURCE_GROUP" --name "$SQL_SERVER_NAME" --query state --output tsv 2>/dev/null || true)"
    [[ "$state" == "Ready" ]] && break
    sleep 5
  done
  if [[ "$state" != "Ready" ]]; then echo "SQL Server não ficou pronto em 5 min." >&2; exit 1; fi
fi

ensure_firewall_rule() {
  local rule_name="$1"
  local start_ip="$2"
  local end_ip="$3"
  if az sql server firewall-rule show \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SQL_SERVER_NAME" \
    --name "$rule_name" \
    --output none >/dev/null 2>&1; then
    az sql server firewall-rule update \
      --resource-group "$RESOURCE_GROUP" \
      --server "$SQL_SERVER_NAME" \
      --name "$rule_name" \
      --start-ip-address "$start_ip" \
      --end-ip-address "$end_ip" \
      --output none
  else
    az sql server firewall-rule create \
      --resource-group "$RESOURCE_GROUP" \
      --server "$SQL_SERVER_NAME" \
      --name "$rule_name" \
      --start-ip-address "$start_ip" \
      --end-ip-address "$end_ip" \
      --output none
  fi
}

# Azure SQL's 0.0.0.0-to-0.0.0.0 special rule allows Azure-hosted services only.
ensure_firewall_rule AllowAzureServices 0.0.0.0 0.0.0.0
ensure_firewall_rule AllowTemporaryClientIP "$CLIENT_IP" "$CLIENT_IP"
echo "Regra temporária AllowTemporaryClientIP criada para $CLIENT_IP."

if ! az sql db show --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" --name "$SQL_DATABASE_NAME" --output none >/dev/null 2>&1; then
  az sql db create \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SQL_SERVER_NAME" \
    --name "$SQL_DATABASE_NAME" \
    --service-objective Basic \
    --backup-storage-redundancy Local \
    --output none
fi

if ! az appservice plan show --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_PLAN" --output none >/dev/null 2>&1; then
  az appservice plan create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_SERVICE_PLAN" \
    --location "$LOCATION" \
    --is-linux \
    --sku B1 \
    --output none || {
      echo "Criação do plano limitada (throttling) pelo Azure; tentando de novo em 60s..."
      for _ in 1 2 3 4 5; do
        sleep 60
        az appservice plan create --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_PLAN" --location "$LOCATION" --is-linux --sku B1 --output none && break
      done
      az appservice plan show --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_PLAN" --output none
    }
fi

if ! az webapp show --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" --output none >/dev/null 2>&1; then
  az webapp create \
    --resource-group "$RESOURCE_GROUP" \
    --plan "$APP_SERVICE_PLAN" \
    --name "$WEB_APP_NAME" \
    --runtime "JAVA:21-java21" \
    --https-only true \
    --output none
fi

echo "Inicializando o schema e o usuário restrito do Azure SQL..."
bash "$SCRIPT_DIR/azure-sql-init.sh"

if ! az monitor app-insights component show --resource-group "$RESOURCE_GROUP" --app "$APP_INSIGHTS_NAME" --output none >/dev/null 2>&1; then
  az monitor app-insights component create \
    --resource-group "$RESOURCE_GROUP" \
    --app "$APP_INSIGHTS_NAME" \
    --location "$LOCATION" \
    --application-type web \
    --kind web \
    --output none
fi
APP_INSIGHTS_CONNECTION_STRING="$(
  az monitor app-insights component show \
    --resource-group "$RESOURCE_GROUP" \
    --app "$APP_INSIGHTS_NAME" \
    --query connectionString \
    --output tsv
)"

DATABASE_URL="jdbc:sqlserver://${SQL_SERVER_NAME}.database.windows.net:1433;database=${SQL_DATABASE_NAME};encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30"
json_value() {
  local escaped="$1"
  escaped="${escaped//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  escaped="${escaped//$'\n'/\\n}"
  escaped="${escaped//$'\r'/\\r}"
  escaped="${escaped//$'\t'/\\t}"
  printf '"%s"' "$escaped"
}
APP_SETTINGS_FILE="$(mktemp "${TMPDIR:-/tmp}/dimdim-appsettings.XXXXXX.json")"
{
  printf '{\n  "DATABASE_URL": '
  json_value "$DATABASE_URL"
  printf ',\n  "DATABASE_USERNAME": '
  json_value "$DATABASE_USERNAME"
  printf ',\n  "DATABASE_PASSWORD": '
  json_value "$DATABASE_PASSWORD"
  printf ',\n  "JWT_SECRET": '
  json_value "$JWT_SECRET"
  printf ',\n  "JWT_EXPIRATION": '
  json_value "${JWT_EXPIRATION:-86400000}"
  printf ',\n  "APPLICATIONINSIGHTS_CONNECTION_STRING": '
  json_value "$APP_INSIGHTS_CONNECTION_STRING"
  printf ',\n  "APPLICATIONINSIGHTS_ROLE_NAME": '
  json_value "dimdim"
  printf ',\n  "WEBSITES_CONTAINER_START_TIME_LIMIT": '
  json_value "600"
  printf ',\n  "SPRING_PROFILES_ACTIVE": '
  json_value "azure"
  printf '\n}\n'
} > "$APP_SETTINGS_FILE"
az webapp config appsettings set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEB_APP_NAME" \
  --settings "@$APP_SETTINGS_FILE" \
  --output none
rm -f "$APP_SETTINGS_FILE"
APP_SETTINGS_FILE=""

echo "Executando testes e empacotando o JAR..."
bash "$PROJECT_ROOT/mvnw" --batch-mode clean test package
APP_JAR="$PROJECT_ROOT/target/dimdim.jar"
if [[ ! -f "$APP_JAR" ]]; then
  echo "O build terminou sem gerar $APP_JAR." >&2
  exit 1
fi

AGENT_VERSION="3.7.9"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dimdim-deploy.XXXXXX")"
cp "$APP_JAR" "$STAGING_DIR/app.jar"
curl --fail --silent --show-error --location \
  "https://github.com/microsoft/ApplicationInsights-Java/releases/download/${AGENT_VERSION}/applicationinsights-agent-${AGENT_VERSION}.jar" \
  --output "$STAGING_DIR/applicationinsights-agent.jar"
(
  cd "$STAGING_DIR"
  zip -q "$PROJECT_ROOT/target/dimdim-appservice.zip" app.jar applicationinsights-agent.jar
)

az webapp config set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEB_APP_NAME" \
  --startup-file "java -javaagent:/home/site/wwwroot/applicationinsights-agent.jar -jar /home/site/wwwroot/app.jar" \
  --output none

echo "Enviando o pacote para o Azure App Service com az webapp deploy..."
az webapp deploy \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEB_APP_NAME" \
  --src-path "$PROJECT_ROOT/target/dimdim-appservice.zip" \
  --type zip \
  --async true \
  --track-status false

APP_URL="https://${WEB_APP_NAME}.azurewebsites.net"
echo "Aguardando o App Service responder em $APP_URL (a primeira inicialização do Java no plano B1 pode levar vários minutos)..."
for attempt in {1..90}; do
  if BASE_URL="$APP_URL" "$SCRIPT_DIR/validate.sh"; then
    echo "Deploy e smoke test concluídos: $APP_URL"
    echo "Swagger UI: $APP_URL/swagger"
    exit 0
  fi
  sleep 10
done

echo "O deploy foi enviado, mas a aplicação não passou no smoke test dentro de ~15 minutos." >&2
echo "Consulte o log do App Service e verifique DATABASE_URL/credenciais de banco." >&2
exit 1
