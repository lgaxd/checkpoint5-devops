#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
BASE_URL="${BASE_URL%/}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl é necessário para validar a aplicação." >&2
  exit 1
fi

echo "Verificando health check: $BASE_URL/actuator/health"
HEALTH="$(curl --fail --silent --show-error --max-time 20 "$BASE_URL/actuator/health")"
if [[ "$HEALTH" != *'"status":"UP"'* ]]; then
  echo "Health check retornou estado inesperado: $HEALTH" >&2
  exit 1
fi

echo "Aplicação saudável; o health check também verifica a conexão com o datasource SQL."
