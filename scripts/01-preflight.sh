#!/usr/bin/env bash
# Etapa 01 — Preflight (somente leitura; não cria nada no Azure).
# Confere variáveis do .env, ferramentas locais, login no Azure CLI, IP público,
# disponibilidade da região para App Service B1 Linux e Azure SQL Basic.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
step_begin "Preflight: ferramentas, login, variáveis e região"

echo "Região do App Service: $LOCATION | Região do SQL: $SQL_LOCATION"

echo "-- Variáveis obrigatórias"
require_env SQL_ADMIN_USERNAME SQL_ADMIN_PASSWORD DATABASE_USERNAME DATABASE_PASSWORD JWT_SECRET
[[ "$DATABASE_USERNAME" != "$SQL_ADMIN_USERNAME" ]] || die "DATABASE_USERNAME deve ser diferente de SQL_ADMIN_USERNAME."
(( ${#JWT_SECRET} >= 32 )) || die "JWT_SECRET deve ter pelo menos 32 caracteres (gere com: openssl rand -base64 32)."
[[ "$SQL_SERVER_NAME" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || die "SQL_SERVER_NAME: 1-63 caracteres minúsculos, números e hífens."
[[ "$WEB_APP_NAME" =~ ^[A-Za-z0-9-]{2,60}$ ]] || die "WEB_APP_NAME: somente letras, números e hífens (2-60)."
echo "Variáveis OK (valores não são exibidos)."

echo "-- Ferramentas"
require_tools az curl zip timeout "$SQLCMD"
command -v java >/dev/null 2>&1 || [[ -x "${JAVA_HOME:-/nonexistent}/bin/java" ]] || die "JDK 21 não encontrado."
echo "Ferramentas OK: az, java, curl, zip, timeout, sqlcmd."

echo "-- Login no Azure"
require_login
echo "Subscription ativa: $(az account show --query name --output tsv)"

echo "-- IP público (para a regra temporária do firewall SQL)"
resolve_client_ip

echo "-- Região '$LOCATION' para App Service B1 Linux"
if [[ "$(provider_state Microsoft.Web)" == "Registered" ]]; then
  regions="$(az appservice list-locations --sku B1 --linux-workers-enabled --query '[].name' --output tsv | tr -d ' \r' | tr '[:upper:]' '[:lower:]')"
  grep -qx "$(norm_loc "$LOCATION")" <<< "$regions" \
    || die "LOCATION='$LOCATION' não oferece App Service B1 Linux nesta subscription."
  echo "OK."
else
  echo "AVISO: provider Microsoft.Web ainda não registrado; será registrado na etapa 02."
fi

echo "-- Edição Basic do Azure SQL em '$SQL_LOCATION'"
if [[ "$(provider_state Microsoft.Sql)" == "Registered" ]]; then
  [[ "$(az sql db list-editions -l "$SQL_LOCATION" --available --query "[?name=='Basic'].name | [0]" --output tsv)" == "Basic" ]] \
    || die "Azure SQL Basic indisponível em '$SQL_LOCATION'. Defina SQL_LOCATION com outra região."
  echo "OK."
else
  echo "AVISO: provider Microsoft.Sql ainda não registrado; será registrado na etapa 02."
fi

echo
echo "Preflight concluído. Nada foi criado no Azure."
