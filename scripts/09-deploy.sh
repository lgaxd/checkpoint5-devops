#!/usr/bin/env bash
# Etapa 09 — Deploy: publica o pacote zip (gerado na etapa 07) no App Service com
# `az webapp deploy`, de forma síncrona. Não acompanha o start do site (--track-status false):
# esse acompanhamento do Azure CLI reporta falha mesmo com o site no ar quando há um erro
# antigo (LastError) registrado no app. Quem confirma que a aplicação subiu é a etapa 10.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
step_begin "Deploy do pacote com az webapp deploy"
require_login
[[ -f "$ZIP_FILE" ]] || die "Pacote não encontrado: target/$(basename "$ZIP_FILE"). Rode a etapa 07."

echo "Enviando target/$(basename "$ZIP_FILE") para '$WEB_APP_NAME' (limite de 15 min)..."
# --timeout do az webapp deploy é em MILISSEGUNDOS.
if ! timeout 1000 az webapp deploy \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEB_APP_NAME" \
  --src-path "$ZIP_FILE" \
  --type zip \
  --track-status false \
  --timeout 900000; then
  diagnose_app
  die "O deploy falhou (mensagem do Azure acima)."
fi
echo "Pacote publicado: $APP_URL (o site reinicia agora; valide com a etapa 10)."
