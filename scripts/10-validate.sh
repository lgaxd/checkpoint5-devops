#!/usr/bin/env bash
# Etapa 10 — Validação da aplicação publicada, em duas fases, sempre por código HTTP:
#   Fase 1: GET /                 -> 200 (o container subiu e responde na porta 80)
#   Fase 2: GET /actuator/health  -> 200 e "status":"UP" (a conexão com o Azure SQL funciona)
#
# Variáveis opcionais:
#   BASE_URL       padrão https://<WEB_APP_NAME>.azurewebsites.net
#   WAIT_TIMEOUT   segundos de espera total (as duas fases juntas; padrão 600; 0 = tentativa única)
#   WAIT_INTERVAL  segundos entre tentativas (padrão 10)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
step_begin "Validação da aplicação (/ e /actuator/health)"
require_tools curl

BASE_URL="${BASE_URL:-$APP_URL}"
BASE_URL="${BASE_URL%/}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-600}"
WAIT_INTERVAL="${WAIT_INTERVAL:-10}"

BODY_FILE="$(mktemp "${TMPDIR:-/tmp}/dimdim-validate.XXXXXX")"
trap 'rc=$?; rm -f "$BODY_FILE"; step_finish "$rc"' EXIT
START=$SECONDS
DEADLINE=$((START + WAIT_TIMEOUT))
HTTP_CODE="000"

probe() {
  HTTP_CODE="$(curl -s -o "$BODY_FILE" -w '%{http_code}' --max-time 20 "$BASE_URL$1")" || true
  [[ -n "$HTTP_CODE" ]] || HTTP_CODE="000"
}

show_failure() {
  echo "    Último status HTTP: $HTTP_CODE ($BASE_URL$1)" >&2
  echo "    Corpo da resposta (até 1000 bytes):" >&2
  head -c 1000 "$BODY_FILE" | mask_ips | sed 's/^/      /' >&2
  echo >&2
  # Só coleta logs do App Service quando a URL validada é a do Web App configurado.
  [[ "$BASE_URL" != "$APP_URL" ]] || diagnose_app
}

# wait_phase <rótulo> <caminho> <modo: status|health>
wait_phase() {
  local label="$1" path="$2" mode="$3" attempt=0
  echo "$label: GET $BASE_URL$path"
  while true; do
    attempt=$((attempt + 1))
    probe "$path"
    echo "    tentativa $attempt: HTTP $HTTP_CODE (decorrido $((SECONDS - START))s)"
    if [[ "$HTTP_CODE" == "200" ]]; then
      if [[ "$mode" == "status" ]] || grep -q '"status":"UP"' "$BODY_FILE"; then
        return 0
      fi
    fi
    if (( SECONDS >= DEADLINE )); then
      echo "FALHA em $label após $((SECONDS - START))s." >&2
      show_failure "$path"
      return 1
    fi
    sleep "$WAIT_INTERVAL"
  done
}

echo "O primeiro start da JVM no plano B1 leva alguns minutos; tentativas sem resposta são esperadas."
wait_phase "Fase 1/2 (container no ar)" "/" status
echo "    OK: a aplicação responde em /."
wait_phase "Fase 2/2 (banco de dados)" "/actuator/health" health
echo "    OK: health UP (inclui a conexão com o Azure SQL)."
echo
echo "Aplicação validada: $BASE_URL"
echo "Swagger UI:         $BASE_URL/swagger"
