#!/usr/bin/env bash
# Etapa 03 — Azure SQL (PaaS): SQL Server lógico, regras de firewall e database Basic.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
step_begin "Azure SQL Server, firewall e database"
require_env SQL_ADMIN_USERNAME SQL_ADMIN_PASSWORD
require_login
resolve_client_ip

echo "-- SQL Server '$SQL_SERVER_NAME'"
if az sql server show --resource-group "$RESOURCE_GROUP" --name "$SQL_SERVER_NAME" --output none >/dev/null 2>&1; then
  echo "Já existe: reutilizado."
else
  echo "Criando em $SQL_LOCATION (leva alguns minutos)..."
  az sql server create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$SQL_SERVER_NAME" \
    --location "$SQL_LOCATION" \
    --admin-user "$SQL_ADMIN_USERNAME" \
    --admin-password "$SQL_ADMIN_PASSWORD" \
    --enable-public-network true \
    --output none
  echo "Criado."
fi

# ensure_firewall_rule <nome> <ip_inicial> <ip_final>: cria ou atualiza a regra.
ensure_firewall_rule() {
  local action="create"
  if az sql server firewall-rule show --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" --name "$1" --output none >/dev/null 2>&1; then
    action="update"
  fi
  az sql server firewall-rule "$action" \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SQL_SERVER_NAME" \
    --name "$1" \
    --start-ip-address "$2" \
    --end-ip-address "$3" \
    --output none
}

echo "-- Regras de firewall"
# 0.0.0.0 é o valor especial que libera apenas serviços hospedados no Azure (o App Service).
ensure_firewall_rule AllowAzureServices 0.0.0.0 0.0.0.0
echo "AllowAzureServices (0.0.0.0): somente serviços Azure."
# IP exato desta máquina, para a etapa 04 aplicar o DDL com sqlcmd.
ensure_firewall_rule AllowTemporaryClientIP "$CLIENT_IP" "$CLIENT_IP"
echo "AllowTemporaryClientIP ($(mask_ip "$CLIENT_IP")): somente esta máquina."

echo "-- Database '$SQL_DATABASE_NAME' (Basic)"
if az sql db show --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" --name "$SQL_DATABASE_NAME" --output none >/dev/null 2>&1; then
  echo "Já existe: reutilizado."
else
  echo "Criando (leva alguns minutos)..."
  az sql db create \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SQL_SERVER_NAME" \
    --name "$SQL_DATABASE_NAME" \
    --service-objective Basic \
    --backup-storage-redundancy Local \
    --output none
  echo "Criado."
fi
az sql db show --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" --name "$SQL_DATABASE_NAME" \
  --query '{database:name, status:status, sku:currentServiceObjectiveName, regiao:location}' --output table
