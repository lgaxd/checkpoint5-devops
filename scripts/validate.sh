#!/usr/bin/env bash
# Valida a aplicação em duas etapas, sempre por código HTTP (sem --fail, para
# que o corpo da resposta apareça quando algo falha):
#   Fase 1: GET /                 -> 200 (o container subiu)
#   Fase 2: GET /actuator/health  -> 200 e "status":"UP" (o banco responde)
#
# Uso standalone: BASE_URL=https://meu-app.azurewebsites.net bash scripts/validate.sh
# Variáveis:
#   BASE_URL       padrão http://localhost:8080
#   WAIT_TIMEOUT   segundos de espera total (as duas fases juntas); 0 = tentativa única
#   WAIT_INTERVAL  segundos entre tentativas (padrão 10)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-common.sh
source "$SCRIPT_DIR/lib-common.sh"

BASE_URL="${BASE_URL:-http://localhost:8080}"
BASE_URL="${BASE_URL%/}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-0}"
WAIT_INTERVAL="${WAIT_INTERVAL:-10}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl é necessário para validar a aplicação." >&2
  exit 1
fi

BODY_FILE="$(mktemp "${TMPDIR:-/tmp}/dimdim-validate.XXXXXX")"
trap 'rm -f "$BODY_FILE"' EXIT
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

wait_phase "Fase 1/2 (container no ar)" "/" status
echo "    OK: a aplicação responde em /."
wait_phase "Fase 2/2 (banco de dados)" "/actuator/health" health
echo "    OK: health UP (inclui a conexão com o Azure SQL)."
echo "Validação concluída: $BASE_URL"
