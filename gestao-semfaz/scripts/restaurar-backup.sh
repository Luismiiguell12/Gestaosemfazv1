#!/usr/bin/env bash
# Restaura um backup gerado por backup-banco.sh num banco que JÁ TEM a estrutura
# (projeto novo + supabase/deploy/banco-completo.sql, ou `supabase db push`).
# Uso: DB_URL=postgresql://... scripts/restaurar-backup.sh <pasta-com-dados.dump-e-auth.dump>
#      Se a pasta tiver backup-*.tar.gpg, decifra antes (pede BACKUP_PASSPHRASE).
# Os gatilhos ficam desligados durante a carga (session_replication_role = replica):
# a auditoria não é duplicada e as regras de imutabilidade não bloqueiam a carga.
set -euo pipefail
: "${DB_URL:?Defina DB_URL}"
PASTA="${1:?Informe a pasta do backup}"

cifrado=$(ls "$PASTA"/backup-*.tar.gpg 2>/dev/null | head -1 || true)
if [ -n "$cifrado" ]; then
  : "${BACKUP_PASSPHRASE:?Defina BACKUP_PASSPHRASE para decifrar}"
  printf '%s' "$BACKUP_PASSPHRASE" | gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 0 --decrypt "$cifrado" | tar -x -C "$PASTA"
fi

# segurança: só restaura em banco sem cadastro (projeto novo); nunca por cima de dados
if [ "$(psql "$DB_URL" -tAc "select count(*) from public.servidores")" != "0" ] && [ "${FORCAR:-}" != "sim" ]; then
  echo "O banco de destino já tem servidores cadastrados. Restauração recusada (use um projeto novo)." >&2; exit 1
fi

# tudo numa transação: limpa o que as migrations pré-carregam (módulos, configurações...) e carrega o backup
{
  echo "set session_replication_role = replica;"
  psql "$DB_URL" -tAc "select 'truncate table ' || string_agg(format('%I.%I', schemaname, tablename), ', ') || ' cascade;' from pg_tables where schemaname in ('public','app')"
  [ -f "$PASTA/auth.dump" ] && pg_restore --data-only --no-owner --no-privileges --file=- "$PASTA/auth.dump"
  pg_restore --data-only --no-owner --no-privileges --file=- "$PASTA/dados.dump"
} | grep -v '^SET transaction_timeout' \
  | psql "$DB_URL" -v ON_ERROR_STOP=1 --single-transaction -q   # (pg_dump 17+ grava transaction_timeout, que servidor 16 não conhece)
echo "restauração concluída. Confira com scripts/verificar-seguranca.sql e compare com contagem.csv"
