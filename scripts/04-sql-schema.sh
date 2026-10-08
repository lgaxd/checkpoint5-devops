#!/usr/bin/env bash
# Etapa 04 — Schema do Azure SQL: aplica o DDL (scripts/azure-sql.sql) e cria o usuário
# contido da aplicação, apenas com db_datareader e db_datawriter (sem privilégio de admin).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
step_begin "Schema do banco (DDL) e usuário restrito da aplicação"
require_env SQL_ADMIN_USERNAME SQL_ADMIN_PASSWORD DATABASE_USERNAME DATABASE_PASSWORD
require_tools "$SQLCMD"

if [[ ! "$DATABASE_USERNAME" =~ ^[A-Za-z_][A-Za-z0-9_@#\$-]{0,127}$ ]]; then
  die "DATABASE_USERNAME deve ser um identificador SQL simples (letras, números, _, @, #, $ ou -)."
fi
[[ "$DATABASE_USERNAME" != "$SQL_ADMIN_USERNAME" ]] || die "DATABASE_USERNAME deve ser diferente de SQL_ADMIN_USERNAME."

SQLCMD_SERVER="tcp:${SQL_SERVER_NAME}.database.windows.net,1433"
SQL_MAX_ATTEMPTS="${SQL_MAX_ATTEMPTS:-8}"
SQL_RETRY_DELAY="${SQL_RETRY_DELAY:-15}"
SQL_OUT_FILE="$(mktemp "${TMPDIR:-/tmp}/dimdim-sqlcmd.XXXXXX")"
USER_SQL_FILE=""
trap 'rc=$?; rm -f "$SQL_OUT_FILE" "$USER_SQL_FILE"; step_finish "$rc"' EXIT

# Executa um arquivo .sql. Só repete em falha de conexão/firewall; erro de SQL aborta.
# -N: conexão criptografada; -l 30: login timeout de 30s (válidos no sqlcmd ODBC e no go-sqlcmd).
run_sqlcmd() {
  local sql_file="$1" attempt rc
  for attempt in $(seq 1 "$SQL_MAX_ATTEMPTS"); do
    rc=0
    SQLCMDPASSWORD="$SQL_ADMIN_PASSWORD" "$SQLCMD" \
      -S "$SQLCMD_SERVER" \
      -d "$SQL_DATABASE_NAME" \
      -U "$SQL_ADMIN_USERNAME" \
      -N \
      -l 30 \
      -b \
      -i "$sql_file" > "$SQL_OUT_FILE" 2>&1 || rc=$?
    mask_ips < "$SQL_OUT_FILE"
    if (( rc == 0 )); then
      return 0
    fi
    if grep -qiE 'not allowed to access the server|login timeout|network-related|instance-specific|TCP Provider|connection (was )?(refused|reset)|could not open a connection|timeout expired|is not currently available' "$SQL_OUT_FILE"; then
      if (( attempt < SQL_MAX_ATTEMPTS )); then
        echo "    falha de conexão/firewall (tentativa $attempt/$SQL_MAX_ATTEMPTS, sqlcmd saiu com $rc); nova tentativa em ${SQL_RETRY_DELAY}s (a regra de firewall pode levar alguns segundos para propagar)..." >&2
        sleep "$SQL_RETRY_DELAY"
        continue
      fi
      echo "ERRO: sem conexão com o Azure SQL após $SQL_MAX_ATTEMPTS tentativas. Confira o firewall (AllowTemporaryClientIP) e o IP detectado." >&2
      return 1
    fi
    echo "ERRO de SQL (sem nova tentativa; sqlcmd saiu com $rc). Corrija o script e execute novamente." >&2
    return 1
  done
}

echo "Aplicando DDL ao Azure SQL Database '$SQL_DATABASE_NAME'..."
run_sqlcmd "$SCRIPT_DIR/azure-sql.sql"

PASSWORD_SQL="$(printf '%s' "$DATABASE_PASSWORD" | sed "s/'/''/g")"
USER_SQL_FILE="$(mktemp "${TMPDIR:-/tmp}/dimdim-user.XXXXXX.sql")"
cat > "$USER_SQL_FILE" <<SQL
IF DATABASE_PRINCIPAL_ID(N'${DATABASE_USERNAME}') IS NULL
BEGIN
    CREATE USER [${DATABASE_USERNAME}] WITH PASSWORD = N'${PASSWORD_SQL}';
END
ELSE
BEGIN
    ALTER USER [${DATABASE_USERNAME}] WITH PASSWORD = N'${PASSWORD_SQL}';
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members drm
    JOIN sys.database_principals role_principal ON role_principal.principal_id = drm.role_principal_id
    JOIN sys.database_principals member_principal ON member_principal.principal_id = drm.member_principal_id
    WHERE role_principal.name = N'db_datareader' AND member_principal.name = N'${DATABASE_USERNAME}'
)
    ALTER ROLE db_datareader ADD MEMBER [${DATABASE_USERNAME}];

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members drm
    JOIN sys.database_principals role_principal ON role_principal.principal_id = drm.role_principal_id
    JOIN sys.database_principals member_principal ON member_principal.principal_id = drm.member_principal_id
    WHERE role_principal.name = N'db_datawriter' AND member_principal.name = N'${DATABASE_USERNAME}'
)
    ALTER ROLE db_datawriter ADD MEMBER [${DATABASE_USERNAME}];
SQL

echo "Criando/atualizando usuário restrito da aplicação e permissões CRUD..."
run_sqlcmd "$USER_SQL_FILE"

echo "Azure SQL inicializado. A aplicação usa '$DATABASE_USERNAME' (sem privilégios de administração do servidor)."
