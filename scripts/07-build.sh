#!/usr/bin/env bash
# Etapa 07 — Build local: roda os testes, gera o JAR com Maven e monta o pacote zip
# (app.jar + agente Java do Application Insights) que será enviado ao App Service.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
step_begin "Testes, build Maven e pacote de deploy"
require_tools zip curl

echo "-- Testes e build (./mvnw clean package)"
(cd "$PROJECT_ROOT" && bash ./mvnw --batch-mode clean package)
[[ -f "$PROJECT_ROOT/target/dimdim.jar" ]] || die "O build terminou sem gerar target/dimdim.jar."

echo "-- Agente Java do Application Insights $AGENT_VERSION"
mkdir -p "$PROJECT_ROOT/.cache"
AGENT_JAR="$PROJECT_ROOT/.cache/applicationinsights-agent-${AGENT_VERSION}.jar"
if [[ -s "$AGENT_JAR" ]]; then
  echo "Em cache: .cache/$(basename "$AGENT_JAR")"
else
  echo "Baixando do repositório oficial da Microsoft no GitHub..."
  if ! curl --fail --silent --show-error --location --retry 3 --retry-delay 5 --max-time 120 \
    "https://github.com/microsoft/ApplicationInsights-Java/releases/download/${AGENT_VERSION}/applicationinsights-agent-${AGENT_VERSION}.jar" \
    --output "$AGENT_JAR.part"; then
    rm -f "$AGENT_JAR.part"
    die "Falha ao baixar o agente do Application Insights."
  fi
  mv "$AGENT_JAR.part" "$AGENT_JAR"
fi

echo "-- Pacote zip"
STAGING_DIR="$PROJECT_ROOT/target/package"
mkdir -p "$STAGING_DIR"
cp "$PROJECT_ROOT/target/dimdim.jar" "$STAGING_DIR/app.jar"
cp "$AGENT_JAR" "$STAGING_DIR/applicationinsights-agent.jar"
rm -f "$ZIP_FILE"
(cd "$STAGING_DIR" && zip -q "$ZIP_FILE" app.jar applicationinsights-agent.jar)
echo "Pacote criado: target/$(basename "$ZIP_FILE") ($(du -h "$ZIP_FILE" | cut -f1))"
