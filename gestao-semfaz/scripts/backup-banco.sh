#!/usr/bin/env bash
# Backup dos DADOS do banco (a estrutura vem das migrations versionadas).
# Uso: DB_URL=postgresql://... scripts/backup-banco.sh <pasta-saida>
# Gera: dados.dump (public + app), auth.dump (usuários, identidades e fatores MFA), estrutura.sql (referência).
# Nada é impresso com dados; a URL do banco nunca vai para o log.
set -euo pipefail
: "${DB_URL:?Defina DB_URL}"
SAIDA="${1:?Informe a pasta de saída}"
mkdir -p "$SAIDA"

pg_dump "$DB_URL" --format=custom --data-only --no-owner --no-privileges \
  --schema=public --schema=app --file="$SAIDA/dados.dump"

# auth: só o necessário para as pessoas continuarem entrando (sem sessões/tokens)
AUTH_TABELAS=()
for t in users identities mfa_factors; do
  if psql "$DB_URL" -tAc "select to_regclass('auth.$t') is not null" | grep -q t; then AUTH_TABELAS+=(--table="auth.$t"); fi
done
pg_dump "$DB_URL" --format=custom --data-only --no-owner --no-privileges "${AUTH_TABELAS[@]}" --file="$SAIDA/auth.dump"

pg_dump "$DB_URL" --schema-only --no-owner --schema=public --schema=app --file="$SAIDA/estrutura.sql"

# contagem por tabela, para conferir a restauração
psql "$DB_URL" -tA -F ';' -c "select relname, n_live_tup from pg_stat_user_tables where schemaname in ('public','app') order by 1" > "$SAIDA/contagem.csv" || true
date -u +%Y-%m-%dT%H:%M:%SZ > "$SAIDA/gerado-em.txt"
echo "backup do banco: $(du -sh "$SAIDA" | cut -f1)"
