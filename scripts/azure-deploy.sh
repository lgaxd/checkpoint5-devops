#!/usr/bin/env bash
# Deploy do DimDim no Azure (App Service Linux Java SE 21 + Azure SQL + Application Insights).
#
# Modos:
#   (sem argumentos)  fluxo completo
#   --preflight-only  somente checagens de leitura; não cria nada
#   --infra-only      cria/reutiliza a infraestrutura e inicializa o SQL (sem build/deploy)
#   --app-only        assume infra existente; build, app settings, deploy e validação
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib-common.sh
source "$SCRIPT_DIR/lib-common.sh"

usage() {
  cat <<'USAGE'
Uso: bash scripts/azure-deploy.sh [--preflight-only | --infra-only | --app-only]

  (sem argumentos)  fluxo completo
  --preflight-only  somente checagens de leitura (não cria nada)
  --infra-only      cria/reutiliza infra e inicializa o SQL (sem build/deploy)
  --app-only        build, app settings, deploy síncrono e validação (infra já existente)
USAGE
}

MODE="full"
if [[ $# -gt 1 ]]; then usage >&2; exit 2; fi
case "${1:-}" in
  "") ;;
  --preflight-only) MODE="preflight-only" ;;
  --infra-only) MODE="infra-only" ;;
  --app-only) MODE="app-only" ;;
  -h|--help) usage; exit 0 ;;
  *) echo "Argumento desconhecido: $1" >&2; usage >&2; exit 2 ;;
esac

# ---------------------------------------------------------------- .env e variáveis
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.env"
  set +a
fi

RM="${RM:-561413}"
LOCATION="${LOCATION:-eastus2}"
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
DATABASE_URL="jdbc:sqlserver://${SQL_SERVER_NAME}.database.windows.net:1433;database=${SQL_DATABASE_NAME};encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30"
STARTUP_FILE="java -XX:TieredStopAtLevel=1 -XX:+UseSerialGC -javaagent:/home/site/wwwroot/applicationinsights-agent.jar -Dserver.port=${APP_PORT} -jar /home/site/wwwroot/app.jar"

# O az CLI não deve pedir confirmação interativa para instalar extensões (ex.: application-insights).
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=yes_without_prompt
export AZURE_EXTENSION_RUN_AFTER_DYNAMIC_INSTALL=true

# ---------------------------------------------------------------- log e etapas
mkdir -p "$PROJECT_ROOT/logs"
LOG_FILE="$PROJECT_ROOT/logs/deploy-${MODE}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

case "$MODE" in
  full) TOTAL_STEPS=9 ;;
  preflight-only) TOTAL_STEPS=1 ;;
  infra-only) TOTAL_STEPS=5 ;;
  app-only) TOTAL_STEPS=5 ;;
esac
STEP_N=0
STEP_NAME=""
STEP_T0=0
TIMINGS=()
SCRIPT_T0=$SECONDS

BUILD_PID=""
AI_PID=""
AI_OUT=""
APP_SETTINGS_FILE=""
STAGING_DIR=""
SQL_WAIT_OUT=""
BUILD_LOG="$PROJECT_ROOT/target/build.log"
ZIP_FILE="$PROJECT_ROOT/target/dimdim-appservice.zip"
WAIT_RC=0
PREFLIGHT_DEFER_WEB=0
PREFLIGHT_DEFER_SQL=0

fmt_secs() { printf '%dm%02ds' $(($1 / 60)) $(($1 % 60)); }

step_end() {
  if [[ -n "$STEP_NAME" ]]; then
    local d=$((SECONDS - STEP_T0))
    echo "    -> etapa concluída em $(fmt_secs "$d")"
    TIMINGS+=("[$STEP_N/$TOTAL_STEPS] $STEP_NAME: $(fmt_secs "$d")")
    STEP_NAME=""
  fi
}

step() {
  step_end
  STEP_N=$((STEP_N + 1))
  STEP_NAME="$1"
  STEP_T0=$SECONDS
  echo
  echo "[$STEP_N/$TOTAL_STEPS] $1"
}

die() {
  echo "ERRO: $*" >&2
  exit 1
}

kill_bg() {
  local pid="$1"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
  fi
}

on_exit() {
  local rc=$?
  trap - EXIT
  kill_bg "$BUILD_PID"
  kill_bg "$AI_PID"
  [[ -n "$APP_SETTINGS_FILE" ]] && rm -f -- "$APP_SETTINGS_FILE"
  [[ -n "$AI_OUT" ]] && rm -f -- "$AI_OUT"
  [[ -n "$SQL_WAIT_OUT" ]] && rm -f -- "$SQL_WAIT_OUT"
  [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]] && rm -rf -- "$STAGING_DIR"
  if [[ -n "$STEP_NAME" ]]; then
    echo "    -> etapa FALHOU após $(fmt_secs $((SECONDS - STEP_T0)))" >&2
    TIMINGS+=("[$STEP_N/$TOTAL_STEPS] $STEP_NAME: FALHOU após $(fmt_secs $((SECONDS - STEP_T0)))")
  fi
  echo
  echo "================ Resumo (modo: $MODE) ================"
  local t
  for t in "${TIMINGS[@]+"${TIMINGS[@]}"}"; do echo "  $t"; done
  echo "  Tempo total: $(fmt_secs $((SECONDS - SCRIPT_T0)))"
  echo "  Log: ${LOG_FILE#"$PROJECT_ROOT"/}"
  if (( rc == 0 )); then echo "  Resultado: SUCESSO"; else echo "  Resultado: FALHA (código $rc)"; fi
  exit "$rc"
}
trap on_exit EXIT

# ---------------------------------------------------------------- helpers
norm_loc() { printf '%s' "$1" | tr -d ' ' | tr '[:upper:]' '[:lower:]'; }

provider_state() {
  az provider show --namespace "$1" --query registrationState --output tsv 2>/dev/null || echo "Unknown"
}

# wait_bg <pid> <rótulo> <limite_s> [função_de_status]
# Aguarda um processo em background com limite de tempo; imprime estado a cada iteração.
# Resultado em WAIT_RC (0 = ok, 124 = estourou o limite, demais = exit code do processo).
wait_bg() {
  local pid="$1" label="$2" limit="$3" status_fn="${4:-}" t0=$SECONDS last_print=-10
  WAIT_RC=0
  while kill -0 "$pid" 2>/dev/null; do
    if (( SECONDS - t0 >= limit )); then
      echo "Tempo limite de ${limit}s excedido aguardando: $label" >&2
      kill_bg "$pid"
      WAIT_RC=124
      wait "$pid" 2>/dev/null || true
      return 0
    fi
    if (( SECONDS - t0 - last_print >= 10 )); then
      last_print=$((SECONDS - t0))
      if [[ -n "$status_fn" ]]; then
        echo "    $label: $("$status_fn") (decorrido $((SECONDS - t0))s)"
      else
        echo "    $label: em andamento (decorrido $((SECONDS - t0))s)"
      fi
    fi
    sleep 2
  done
  if wait "$pid"; then WAIT_RC=0; else WAIT_RC=$?; fi
}

# ---------------------------------------------------------------- checagens locais
require_env() {
  local v
  for v in "$@"; do
    [[ -n "${!v:-}" ]] || die "Defina $v no ambiente ou em .env (veja .env.example)."
  done
}

check_env_and_names() {
  require_env DATABASE_USERNAME DATABASE_PASSWORD
  [[ "$MODE" == "app-only" ]] || require_env SQL_ADMIN_USERNAME SQL_ADMIN_PASSWORD
  [[ "$MODE" == "infra-only" ]] || require_env JWT_SECRET
  [[ "$SQL_SERVER_NAME" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || die "SQL_SERVER_NAME deve ter 1-63 caracteres: letras minúsculas, números e hífens (sem hífen no início/fim)."
  [[ "$WEB_APP_NAME" =~ ^[A-Za-z0-9-]{2,60}$ ]] || die "WEB_APP_NAME deve conter somente letras, números e hífens (2-60 caracteres)."
}

check_tools() {
  local missing=() t
  for t in az zip curl timeout; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  if [[ "$MODE" != "app-only" ]] && ! command -v "$SQLCMD" >/dev/null 2>&1; then
    missing+=("sqlcmd")
  fi
  if [[ "$MODE" == "full" || "$MODE" == "app-only" || "$MODE" == "preflight-only" ]]; then
    if ! command -v java >/dev/null 2>&1 && [[ ! -x "${JAVA_HOME:-/nonexistent}/bin/java" ]]; then
      missing+=("java (JDK 21)")
    fi
  fi
  if (( ${#missing[@]} > 0 )); then
    die "Ferramentas ausentes: ${missing[*]}. Instale-as e execute novamente."
  fi
  echo "Ferramentas OK: az, zip, curl, timeout$([[ "$MODE" == "app-only" ]] || echo ", sqlcmd")."
}

check_login() {
  if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
    az account set --subscription "$AZURE_SUBSCRIPTION_ID"
  fi
  local sub_name
  if ! sub_name="$(az account show --query name --output tsv 2>/dev/null)"; then
    die "Sem login no Azure. Execute 'az login' e selecione a subscription antes de continuar."
  fi
  echo "Login OK. Subscription: $sub_name"
}

resolve_client_ip() {
  local src="informado em CLIENT_IP"
  if [[ -z "${CLIENT_IP:-}" ]]; then
    src="detectado automaticamente"
    CLIENT_IP="$(curl -4 -fsS --max-time 10 https://api.ipify.org || true)"
  fi
  if [[ -z "$CLIENT_IP" ]]; then
    die "Não foi possível detectar o IP público. Defina CLIENT_IP=<seu IPv4 público> no .env (o firewall nunca é aberto para uma faixa ampla)."
  fi
  is_ipv4 "$CLIENT_IP" || die "CLIENT_IP inválido (esperado um IPv4 explícito)."
  export CLIENT_IP
  echo "IP do cliente ($src): $(mask_ip "$CLIENT_IP")"
}

# ---------------------------------------------------------------- build em background
start_build() {
  echo "Iniciando build Maven em segundo plano (testes rodam uma única vez); log: target/build.log"
  # 'clean' manual: o goal clean apagaria target/build.log enquanto ele está aberto.
  rm -rf "$PROJECT_ROOT/target"
  mkdir -p "$PROJECT_ROOT/target"
  (cd "$PROJECT_ROOT" && exec bash ./mvnw --batch-mode package) > "$BUILD_LOG" 2>&1 &
  BUILD_PID=$!
  echo "    build PID $BUILD_PID"
}

build_status() {
  local last
  last="$(tail -n 1 "$BUILD_LOG" 2>/dev/null | cut -c1-110 || true)"
  printf 'build rodando | %s' "${last:-...}"
}

await_build() {
  wait_bg "$BUILD_PID" "build Maven" 900 build_status
  BUILD_PID=""
  if (( WAIT_RC != 0 )); then
    echo "O build/testes falharam (código $WAIT_RC). Últimas 60 linhas de target/build.log:" >&2
    tail -n 60 "$BUILD_LOG" >&2 || true
    exit 1
  fi
  echo "Resultado dos testes (target/build.log):"
  grep -E 'Tests run:' "$BUILD_LOG" | sed 's/^/    /' || true
  [[ -f "$PROJECT_ROOT/target/dimdim.jar" ]] || die "O build terminou sem gerar target/dimdim.jar."
}

# ---------------------------------------------------------------- preflight (somente leitura)
check_web_region() {
  local out line found=0 want
  want="$(norm_loc "$LOCATION")"
  out="$(az appservice list-locations --sku B1 --linux-workers-enabled --query '[].name' --output tsv)" \
    || die "Falha ao consultar as regiões do App Service (erro acima)."
  while IFS= read -r line; do
    [[ -n "$line" && "$(norm_loc "$line")" == "$want" ]] && found=1
  done <<< "$out"
  if (( found == 0 )); then
    echo "Regiões com App Service B1 Linux disponíveis:" >&2
    while IFS= read -r line; do norm_loc "$line"; echo; done <<< "$out" | paste -sd' ' - >&2
    die "LOCATION='$LOCATION' não oferece App Service B1 Linux para esta subscription. Troque LOCATION no .env."
  fi
  echo "Região OK para App Service B1 Linux: $LOCATION"
}

check_sql_basic() {
  local out
  out="$(az sql db list-editions -l "$SQL_LOCATION" --available --query "[?name=='Basic'].name | [0]" --output tsv)" \
    || die "Falha ao consultar as edições do Azure SQL em $SQL_LOCATION (erro acima)."
  [[ "$out" == "Basic" ]] || die "A edição Basic do Azure SQL não está disponível em SQL_LOCATION='$SQL_LOCATION'. Defina SQL_LOCATION com outra região no .env."
  echo "Edição Basic do Azure SQL disponível em $SQL_LOCATION."
}

preflight_checks() {
  local ws sq rg_loc plan_loc
  ws="$(provider_state Microsoft.Web)"
  sq="$(provider_state Microsoft.Sql)"
  if [[ "$ws" == "Registered" ]]; then
    check_web_region
  else
    PREFLIGHT_DEFER_WEB=1
    echo "AVISO: Microsoft.Web está '$ws'; a região do App Service será verificada após o registro do provider."
  fi
  if [[ "$sq" == "Registered" ]]; then
    check_sql_basic
  else
    PREFLIGHT_DEFER_SQL=1
    echo "AVISO: Microsoft.Sql está '$sq'; a edição Basic será verificada após o registro do provider."
  fi

  if rg_loc="$(az group show --name "$RESOURCE_GROUP" --query location --output tsv 2>/dev/null)"; then
    echo "Resource group '$RESOURCE_GROUP' já existe em '$rg_loc': será reutilizado."
    if [[ "$(norm_loc "$rg_loc")" != "$(norm_loc "$LOCATION")" ]]; then
      echo "    (a região do RG não impede criar recursos em '$LOCATION')"
    fi
  else
    echo "Resource group '$RESOURCE_GROUP' não existe: será criado em '$LOCATION'."
  fi
  if plan_loc="$(az appservice plan show --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_PLAN" --query location --output tsv 2>/dev/null)"; then
    echo "Plano '$APP_SERVICE_PLAN' já existe em '$plan_loc': será reutilizado (nenhuma criação de plano)."
  else
    echo "Plano '$APP_SERVICE_PLAN' não existe: será feita UMA única tentativa de criação."
  fi
  if az webapp show --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" --output none >/dev/null 2>&1; then
    echo "Web App '$WEB_APP_NAME' já existe: será reutilizado."
  fi
  if az sql server show --resource-group "$RESOURCE_GROUP" --name "$SQL_SERVER_NAME" --output none >/dev/null 2>&1; then
    echo "SQL Server '$SQL_SERVER_NAME' já existe: será reutilizado."
  fi
}

check_app_only_prereqs() {
  local missing=()
  az group show --name "$RESOURCE_GROUP" --output none >/dev/null 2>&1 || missing+=("resource group $RESOURCE_GROUP")
  az webapp show --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" --output none >/dev/null 2>&1 || missing+=("web app $WEB_APP_NAME")
  az sql db show --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" --name "$SQL_DATABASE_NAME" --output none >/dev/null 2>&1 || missing+=("banco $SQL_SERVER_NAME/$SQL_DATABASE_NAME")
  az monitor app-insights component show --resource-group "$RESOURCE_GROUP" --app "$APP_INSIGHTS_NAME" --output none >/dev/null 2>&1 || missing+=("Application Insights $APP_INSIGHTS_NAME")
  if (( ${#missing[@]} > 0 )); then
    echo "Infraestrutura ausente:" >&2
    printf '    - %s\n' "${missing[@]}" >&2
    die "Execute primeiro: bash scripts/azure-deploy.sh --infra-only"
  fi
  echo "Infraestrutura existente confirmada (RG, Web App, banco, Application Insights)."
}

# ---------------------------------------------------------------- infraestrutura
register_providers() {
  local providers=(Microsoft.Sql Microsoft.Insights Microsoft.OperationalInsights Microsoft.Web)
  local p state pending=() t0=$SECONDS
  for p in "${providers[@]}"; do
    state="$(provider_state "$p")"
    echo "    $p: $state"
    if [[ "$state" != "Registered" ]]; then
      az provider register --namespace "$p" --output none
      pending+=("$p")
    fi
  done
  while (( ${#pending[@]} > 0 )); do
    if (( SECONDS - t0 >= 300 )); then
      die "Providers não ficaram Registered em 300s: ${pending[*]}"
    fi
    sleep 5
    local still=()
    for p in "${pending[@]}"; do
      state="$(provider_state "$p")"
      echo "    aguardando registro de $p: $state ($((SECONDS - t0))s)"
      [[ "$state" == "Registered" ]] || still+=("$p")
    done
    pending=("${still[@]+"${still[@]}"}")
  done
}

start_app_insights() {
  AI_OUT="$(mktemp "${TMPDIR:-/tmp}/dimdim-ai.XXXXXX")"
  (
    if az monitor app-insights component show --resource-group "$RESOURCE_GROUP" --app "$APP_INSIGHTS_NAME" --output none >/dev/null 2>&1; then
      echo "Application Insights '$APP_INSIGHTS_NAME' já existe: reutilizado."
    else
      timeout 600 az monitor app-insights component create \
        --resource-group "$RESOURCE_GROUP" \
        --app "$APP_INSIGHTS_NAME" \
        --location "$LOCATION" \
        --application-type web \
        --kind web \
        --output none
      echo "Application Insights '$APP_INSIGHTS_NAME' criado."
    fi
  ) > "$AI_OUT" 2>&1 &
  AI_PID=$!
  echo "    Application Insights em segundo plano (PID $AI_PID)"
}

create_sql_server() {
  if az sql server show --resource-group "$RESOURCE_GROUP" --name "$SQL_SERVER_NAME" --output none >/dev/null 2>&1; then
    echo "SQL Server '$SQL_SERVER_NAME' já existe: reutilizado."
    return 0
  fi
  echo "Criando SQL Server '$SQL_SERVER_NAME' em $SQL_LOCATION (--no-wait; provisiona em paralelo)..."
  az sql server create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$SQL_SERVER_NAME" \
    --location "$SQL_LOCATION" \
    --admin-user "$SQL_ADMIN_USERNAME" \
    --admin-password "$SQL_ADMIN_PASSWORD" \
    --enable-public-network true \
    --no-wait \
    --output none
}

create_plan_and_webapp() {
  if az appservice plan show --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_PLAN" --output none >/dev/null 2>&1; then
    echo "Plano '$APP_SERVICE_PLAN' já existe: reutilizado."
  else
    echo "Criando plano '$APP_SERVICE_PLAN' (B1 Linux) em $LOCATION: UMA única tentativa, sem retry."
    if ! az appservice plan create \
      --resource-group "$RESOURCE_GROUP" \
      --name "$APP_SERVICE_PLAN" \
      --location "$LOCATION" \
      --is-linux \
      --sku B1 \
      --output none; then
      echo >&2
      echo "ERRO: o Azure recusou a criação do plano (mensagem integral acima)." >&2
      echo "Não tente novamente em loop; troque LOCATION ou aguarde o bloqueio expirar." >&2
      exit 1
    fi
  fi

  if az webapp show --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" --output none >/dev/null 2>&1; then
    echo "Web App '$WEB_APP_NAME' já existe: reutilizado."
  else
    echo "Criando Web App '$WEB_APP_NAME' (JAVA:21-java21)..."
    az webapp create \
      --resource-group "$RESOURCE_GROUP" \
      --plan "$APP_SERVICE_PLAN" \
      --name "$WEB_APP_NAME" \
      --runtime "JAVA:21-java21" \
      --https-only true \
      --output none
  fi
}

sql_server_state() {
  az sql server show --resource-group "$RESOURCE_GROUP" --name "$SQL_SERVER_NAME" --query state --output tsv 2>/dev/null || echo "consultando..."
}

diagnose_sql_server() {
  echo "--- Diagnóstico do SQL Server ---" >&2
  az sql server show --resource-group "$RESOURCE_GROUP" --name "$SQL_SERVER_NAME" --query '{state:state, location:location}' --output json >&2 || true
  echo "Falhas recentes no Activity Log do resource group (última hora):" >&2
  az monitor activity-log list --resource-group "$RESOURCE_GROUP" --offset 1h \
    --query "[?status.value=='Failed'].{operacao:operationName.value, mensagem:properties.statusMessage}" --output json >&2 || true
}

await_sql_server() {
  SQL_WAIT_OUT="$(mktemp "${TMPDIR:-/tmp}/dimdim-sqlwait.XXXXXX")"
  az sql server wait --resource-group "$RESOURCE_GROUP" --name "$SQL_SERVER_NAME" --created --timeout 600 --interval 15 > "$SQL_WAIT_OUT" 2>&1 &
  local pid=$!
  wait_bg "$pid" "SQL Server $SQL_SERVER_NAME" 660 sql_server_state
  cat "$SQL_WAIT_OUT"
  if (( WAIT_RC != 0 )); then
    diagnose_sql_server
    die "O SQL Server não ficou pronto em 10 min (código $WAIT_RC). Não tente novamente em loop: verifique a mensagem do Azure acima ou troque SQL_LOCATION."
  fi
  echo "SQL Server pronto (estado: $(sql_server_state))."
}

await_app_insights() {
  wait_bg "$AI_PID" "Application Insights" 660
  AI_PID=""
  cat "$AI_OUT"
  (( WAIT_RC == 0 )) || die "Application Insights falhou (código $WAIT_RC); veja a mensagem acima."
}

ensure_firewall_rule() {
  local rule_name="$1" start_ip="$2" end_ip="$3" action="create"
  if az sql server firewall-rule show --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" --name "$rule_name" --output none >/dev/null 2>&1; then
    action="update"
  fi
  az sql server firewall-rule "$action" \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SQL_SERVER_NAME" \
    --name "$rule_name" \
    --start-ip-address "$start_ip" \
    --end-ip-address "$end_ip" \
    --output none
}

db_status() {
  az sql db show --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" --name "$SQL_DATABASE_NAME" --query status --output tsv 2>/dev/null || echo "desconhecido"
}

wait_db_online() {
  local t0=$SECONDS status
  while true; do
    status="$(db_status)"
    echo "    banco '$SQL_DATABASE_NAME': $status ($((SECONDS - t0))s)"
    [[ "$status" == "Online" ]] && return 0
    if (( SECONDS - t0 >= 300 )); then
      die "O banco não ficou Online em 300s (último estado: $status)."
    fi
    sleep 10
  done
}

ensure_database() {
  if az sql db show --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" --name "$SQL_DATABASE_NAME" --output none >/dev/null 2>&1; then
    echo "Banco '$SQL_DATABASE_NAME' já existe: apenas verificando se está Online."
  else
    echo "Criando banco '$SQL_DATABASE_NAME' (Basic, limite de 15 min)..."
    local rc=0
    timeout 900 az sql db create \
      --resource-group "$RESOURCE_GROUP" \
      --server "$SQL_SERVER_NAME" \
      --name "$SQL_DATABASE_NAME" \
      --service-objective Basic \
      --backup-storage-redundancy Local \
      --output none || rc=$?
    if (( rc == 124 )); then
      die "A criação do banco excedeu 15 min."
    elif (( rc != 0 )); then
      die "A criação do banco falhou (código $rc); veja a mensagem do Azure acima."
    fi
  fi
  wait_db_online
}

# ---------------------------------------------------------------- aplicação
ensure_agent() {
  mkdir -p "$PROJECT_ROOT/.cache"
  AGENT_JAR="$PROJECT_ROOT/.cache/applicationinsights-agent-${AGENT_VERSION}.jar"
  if [[ -s "$AGENT_JAR" ]]; then
    echo "Agente Application Insights ${AGENT_VERSION} em cache: ${AGENT_JAR#"$PROJECT_ROOT"/}"
    return 0
  fi
  echo "Baixando agente Application Insights ${AGENT_VERSION}..."
  if ! curl --fail --silent --show-error --location --retry 3 --retry-delay 5 --max-time 120 \
    "https://github.com/microsoft/ApplicationInsights-Java/releases/download/${AGENT_VERSION}/applicationinsights-agent-${AGENT_VERSION}.jar" \
    --output "$AGENT_JAR.part"; then
    rm -f "$AGENT_JAR.part"
    die "Falha ao baixar o agente do Application Insights."
  fi
  mv "$AGENT_JAR.part" "$AGENT_JAR"
}

json_value() {
  local escaped="$1"
  escaped="${escaped//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  escaped="${escaped//$'\n'/\\n}"
  escaped="${escaped//$'\r'/\\r}"
  escaped="${escaped//$'\t'/\\t}"
  printf '"%s"' "$escaped"
}

configure_webapp() {
  local ai_conn
  ai_conn="$(az monitor app-insights component show --resource-group "$RESOURCE_GROUP" --app "$APP_INSIGHTS_NAME" --query connectionString --output tsv)" \
    || die "Não foi possível ler a connection string do Application Insights."
  [[ -n "$ai_conn" ]] || die "Application Insights sem connection string."

  APP_SETTINGS_FILE="$(mktemp "${TMPDIR:-/tmp}/dimdim-appsettings.XXXXXX.json")"
  {
    printf '{\n  "DATABASE_URL": ';                          json_value "$DATABASE_URL"
    printf ',\n  "DATABASE_USERNAME": ';                     json_value "$DATABASE_USERNAME"
    printf ',\n  "DATABASE_PASSWORD": ';                     json_value "$DATABASE_PASSWORD"
    printf ',\n  "JWT_SECRET": ';                            json_value "$JWT_SECRET"
    printf ',\n  "JWT_EXPIRATION": ';                        json_value "${JWT_EXPIRATION:-86400000}"
    printf ',\n  "APPLICATIONINSIGHTS_CONNECTION_STRING": '; json_value "$ai_conn"
    printf ',\n  "APPLICATIONINSIGHTS_ROLE_NAME": ';         json_value "dimdim"
    printf ',\n  "WEBSITES_PORT": ';                         json_value "$APP_PORT"
    printf ',\n  "WEBSITES_CONTAINER_START_TIME_LIMIT": ';   json_value "600"
    printf ',\n  "SPRING_PROFILES_ACTIVE": ';                json_value "azure"
    printf '\n}\n'
  } > "$APP_SETTINGS_FILE"

  echo "Aplicando app settings (uma única chamada; inclui WEBSITES_PORT=$APP_PORT)..."
  az webapp config appsettings set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$WEB_APP_NAME" \
    --settings "@$APP_SETTINGS_FILE" \
    --output none
  rm -f "$APP_SETTINGS_FILE"
  APP_SETTINGS_FILE=""

  echo "Aplicando always-on e comando de inicialização (uma única chamada)..."
  az webapp config set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$WEB_APP_NAME" \
    --always-on true \
    --startup-file "$STARTUP_FILE" \
    --output none
}

build_package() {
  ensure_agent
  STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dimdim-deploy.XXXXXX")"
  cp "$PROJECT_ROOT/target/dimdim.jar" "$STAGING_DIR/app.jar"
  cp "$AGENT_JAR" "$STAGING_DIR/applicationinsights-agent.jar"
  # zip ATUALIZA um arquivo existente; remover evita empacotar jar antigo.
  rm -f "$ZIP_FILE"
  (cd "$STAGING_DIR" && zip -q "$ZIP_FILE" app.jar applicationinsights-agent.jar)
  echo "Pacote criado: target/dimdim-appservice.zip ($(du -h "$ZIP_FILE" | cut -f1))"
}

diagnose_app() {
  echo >&2
  echo "================ Diagnóstico do App Service ================" >&2
  echo "Ativando logs do container (filesystem)..." >&2
  az webapp log config --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" --docker-container-logging filesystem --output none >&2 || true
  echo "Estado do app: $(az webapp show --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" --query state --output tsv 2>&1 || true)" >&2
  echo "Log ao vivo (60s):" >&2
  { timeout 60 az webapp log tail --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" 2>&1 || true; } | mask_ips >&2
  cat >&2 <<'CAUSES'

Causas prováveis:
  - Porta: o app precisa escutar em 8080 (WEBSITES_PORT=8080 e -Dserver.port=8080).
  - Banco: firewall do SQL, banco Offline, DATABASE_URL incorreta.
  - Credenciais: DATABASE_USERNAME/DATABASE_PASSWORD do usuário contido, ou JWT_SECRET ausente.
  - Memória/JVM: a primeira inicialização no B1 é lenta; veja o log acima.
CAUSES
}

deploy_zip() {
  echo "Enviando o pacote com az webapp deploy (síncrono; limite de 15 min)..."
  local rc=0
  # --timeout do az webapp deploy é em MILISSEGUNDOS.
  timeout 1000 az webapp deploy \
    --resource-group "$RESOURCE_GROUP" \
    --name "$WEB_APP_NAME" \
    --src-path "$ZIP_FILE" \
    --type zip \
    --timeout 900000 || rc=$?
  if (( rc != 0 )); then
    echo "ERRO: o deploy falhou (código $rc); mensagem do Azure acima." >&2
    diagnose_app
    exit 1
  fi
  echo "Deploy concluído."
}

validate_app() {
  echo "Validando $APP_URL (limite total de ~10 min, duas fases)..."
  if ! BASE_URL="$APP_URL" WAIT_TIMEOUT=600 WAIT_INTERVAL=10 bash "$SCRIPT_DIR/validate.sh"; then
    diagnose_app
    exit 1
  fi
}

# ================================================================ fluxo principal
echo "DimDim - deploy Azure | modo: $MODE | log: ${LOG_FILE#"$PROJECT_ROOT"/}"
echo "Região do App Service: $LOCATION | Região do SQL: $SQL_LOCATION"

step "Preflight (somente leitura): ferramentas, login, região e edição Basic"
check_env_and_names
check_tools
check_login
if [[ "$MODE" == "full" || "$MODE" == "app-only" ]]; then
  start_build
fi
if [[ "$MODE" == "app-only" ]]; then
  check_app_only_prereqs
else
  resolve_client_ip
  preflight_checks
fi

if [[ "$MODE" == "preflight-only" ]]; then
  step_end
  echo
  echo "Preflight concluído. Nada foi criado no Azure."
  exit 0
fi

if [[ "$MODE" != "app-only" ]]; then
  step "Providers e Resource Group"
  register_providers
  (( PREFLIGHT_DEFER_WEB == 0 )) || check_web_region
  (( PREFLIGHT_DEFER_SQL == 0 )) || check_sql_basic
  if az group show --name "$RESOURCE_GROUP" --output none >/dev/null 2>&1; then
    echo "Resource group '$RESOURCE_GROUP' reutilizado."
  else
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
    echo "Resource group '$RESOURCE_GROUP' criado em $LOCATION."
  fi

  step "Criando SQL Server (assíncrono), plano, Web App e Application Insights"
  start_app_insights
  create_sql_server
  create_plan_and_webapp

  step "Aguardando SQL Server e Application Insights"
  await_sql_server
  await_app_insights

  step "Firewall restrito, banco Basic e usuário contido do Azure SQL"
  ensure_firewall_rule AllowAzureServices 0.0.0.0 0.0.0.0
  ensure_firewall_rule AllowTemporaryClientIP "$CLIENT_IP" "$CLIENT_IP"
  echo "Regras de firewall: AllowAzureServices (0.0.0.0) e AllowTemporaryClientIP ($(mask_ip "$CLIENT_IP"))."
  ensure_database
  echo "Inicializando schema e usuário restrito (db_datareader/db_datawriter)..."
  bash "$SCRIPT_DIR/azure-sql-init.sh"
fi

if [[ "$MODE" == "infra-only" ]]; then
  step_end
  echo
  echo "Infraestrutura pronta. Próximo passo: bash scripts/azure-deploy.sh --app-only"
  exit 0
fi

step "Aguardando build Maven e testes"
await_build

step "Configurando o Web App (app settings, always-on e comando de inicialização)"
configure_webapp
build_package

step "Deploy do pacote zip no App Service"
deploy_zip

step "Validando a aplicação (/ e /actuator/health)"
validate_app

step_end
echo
echo "Deploy e validação concluídos: $APP_URL"
echo "Swagger UI: $APP_URL/swagger"
