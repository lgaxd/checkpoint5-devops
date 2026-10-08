#!/usr/bin/env bash
# Configuração e funções compartilhadas por todas as etapas do deploy. Usar com `source`.
#
# Carrega o .env, define os nomes dos recursos e oferece helpers de log, validação e
# diagnóstico. Cada etapa (01-*.sh ... 10-*.sh) chama `step_begin` no início.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------- .env e variáveis
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.env"
  set +a
fi

RM="${RM:-561413}"
LOCATION="${LOCATION:-southcentralus}"
SQL_LOCATION="${SQL_LOCATION:-$LOCATION}"
RESOURCE_GROUP="${RESOURCE_GROUP:-${RM}-dimdim-rg}"
SQL_SERVER_NAME="${SQL_SERVER_NAME:-sql-server-dimdim-${RM}}"
SQL_DATABASE_NAME="${SQL_DATABASE_NAME:-db-dimdim}"
APP_SERVICE_PLAN="${APP_SERVICE_PLAN:-${RM}-dimdim-plan}"
WEB_APP_NAME="${WEB_APP_NAME:-${RM}-dimdim-webapp}"
APP_INSIGHTS_NAME="${APP_INSIGHTS_NAME:-${RM}-dimdim-insights}"
SQLCMD="${SQLCMD:-sqlcmd}"

AGENT_VERSION="3.7.9"
APP_PORT=8080
APP_URL="https://${WEB_APP_NAME}.azurewebsites.net"
ZIP_FILE="$PROJECT_ROOT/target/dimdim-appservice.zip"
DATABASE_URL="jdbc:sqlserver://${SQL_SERVER_NAME}.database.windows.net:1433;database=${SQL_DATABASE_NAME};encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30"

# O az CLI não deve pedir confirmação interativa para instalar extensões (ex.: application-insights).
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=yes_without_prompt
export AZURE_EXTENSION_RUN_AFTER_DYNAMIC_INSTALL=true

# ---------------------------------------------------------------- log de cada etapa
# step_begin "<título>": imprime o cabeçalho, grava a saída em logs/<etapa>-<data>.log
# e, ao terminar, imprime duração e resultado.
step_begin() {
  STEP_FILE="$(basename "$0" .sh)"
  mkdir -p "$PROJECT_ROOT/logs"
  STEP_LOG="$PROJECT_ROOT/logs/${STEP_FILE}-$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee -a "$STEP_LOG") 2>&1
  STEP_T0=$SECONDS
  trap step_finish EXIT
  echo
  echo "================================================================"
  echo " Etapa ${STEP_FILE%%-*}: $1"
  echo "================================================================"
}

# Aceita o código de saída como $1 quando chamado de um trap encadeado.
step_finish() {
  local rc=${1:-$?} d=$((SECONDS - STEP_T0))
  trap - EXIT
  echo
  if (( rc == 0 )); then
    echo "==> Etapa ${STEP_FILE%%-*} concluída em $((d / 60))m$((d % 60))s | log: logs/$(basename "$STEP_LOG")"
  else
    echo "==> Etapa ${STEP_FILE%%-*} FALHOU (código $rc) após $((d / 60))m$((d % 60))s | log: logs/$(basename "$STEP_LOG")" >&2
  fi
  exit "$rc"
}

# ---------------------------------------------------------------- helpers
die() {
  echo "ERRO: $*" >&2
  exit 1
}

require_env() {
  local v
  for v in "$@"; do
    [[ -n "${!v:-}" ]] || die "Defina $v no ambiente ou em .env (veja .env.example)."
  done
}

require_tools() {
  local t missing=()
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  (( ${#missing[@]} == 0 )) || die "Ferramentas ausentes: ${missing[*]}."
}

require_login() {
  if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
    az account set --subscription "$AZURE_SUBSCRIPTION_ID"
  fi
  az account show --output none >/dev/null 2>&1 || die "Sem login no Azure. Execute 'az login'."
}

# Retorna 0 se $1 é um IPv4 válido (4 octetos 0-255).
is_ipv4() {
  local ip="$1" octet
  local -a parts
  [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  IFS=. read -r -a parts <<< "$ip"
  for octet in "${parts[@]}"; do
    (( 10#$octet <= 255 )) || return 1
  done
}

# 189.12.34.56 -> 189.12.x.x
mask_ip() {
  local a b
  IFS=. read -r a b _ _ <<< "$1"
  printf '%s.%s.x.x' "$a" "$b"
}

# Filtro de stdin: mascara os dois últimos octetos de qualquer IPv4.
mask_ips() {
  sed -E 's/\b([0-9]{1,3})\.([0-9]{1,3})\.[0-9]{1,3}\.[0-9]{1,3}\b/\1.\2.x.x/g'
}

# Usa CLIENT_IP do .env ou detecta o IPv4 público desta máquina.
resolve_client_ip() {
  local src="informado em CLIENT_IP"
  if [[ -z "${CLIENT_IP:-}" ]]; then
    src="detectado automaticamente"
    CLIENT_IP="$(curl -4 -fsS --max-time 10 https://api.ipify.org || true)"
  fi
  [[ -n "$CLIENT_IP" ]] || die "Não foi possível detectar o IP público. Defina CLIENT_IP no .env."
  is_ipv4 "$CLIENT_IP" || die "CLIENT_IP inválido (esperado um IPv4 explícito)."
  echo "IP do cliente ($src): $(mask_ip "$CLIENT_IP")"
}

norm_loc() { printf '%s' "$1" | tr -d ' ' | tr '[:upper:]' '[:lower:]'; }

provider_state() {
  az provider show --namespace "$1" --query registrationState --output tsv 2>/dev/null || echo "Unknown"
}

# Escapa um valor para uso como string JSON.
json_value() {
  local escaped="$1"
  escaped="${escaped//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  escaped="${escaped//$'\n'/\\n}"
  escaped="${escaped//$'\r'/\\r}"
  escaped="${escaped//$'\t'/\\t}"
  printf '"%s"' "$escaped"
}

# Coleta logs do App Service quando o deploy ou a validação falham.
diagnose_app() {
  echo >&2
  echo "================ Diagnóstico do App Service ================" >&2
  az webapp log config --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" --docker-container-logging filesystem --output none >&2 || true
  echo "Estado do app: $(az webapp show --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" --query state --output tsv 2>&1 || true)" >&2
  echo "Log ao vivo (60s):" >&2
  { timeout 60 az webapp log tail --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" 2>&1 || true; } | mask_ips >&2
  cat >&2 <<'CAUSES'

Causas prováveis:
  - Porta: o app precisa escutar em 8080 (WEBSITES_PORT=8080 e -Dserver.port=8080).
  - Banco: firewall do SQL, banco Offline, DATABASE_URL incorreta.
  - Credenciais: DATABASE_USERNAME/DATABASE_PASSWORD do usuário contido, ou JWT_SECRET ausente/curto.
  - Memória/JVM: a primeira inicialização no B1 é lenta; veja o log acima.
CAUSES
}
