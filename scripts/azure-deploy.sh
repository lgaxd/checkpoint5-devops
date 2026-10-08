#!/usr/bin/env bash
# Executa as etapas do deploy em sequência, parando na primeira falha.
# Cada etapa também pode ser executada isoladamente: bash scripts/0N-*.sh
#
# Uso:
#   bash scripts/azure-deploy.sh            todas as etapas (01 a 10)
#   bash scripts/azure-deploy.sh 07         da etapa 07 até a 10 (ex.: redeploy sem recriar infra)
#   bash scripts/azure-deploy.sh 02 06      somente as etapas 02 a 06 (ex.: só infraestrutura)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FROM="${1:-01}"
TO="${2:-10}"
[[ "$FROM" =~ ^[0-9]{2}$ && "$TO" =~ ^[0-9]{2}$ ]] || { echo "Uso: bash scripts/azure-deploy.sh [DE] [ATE]  (ex.: 07 10)" >&2; exit 2; }

for step in "$SCRIPT_DIR"/[0-9][0-9]-*.sh; do
  n="$(basename "$step")"
  n="${n%%-*}"
  (( 10#$n >= 10#$FROM && 10#$n <= 10#$TO && 10#$n < 99 )) || continue
  bash "$step"
done

echo
echo "Etapas $FROM a $TO concluídas."
