#!/usr/bin/env bash
# Recria banco de teste: shim Supabase + migrations + seed (fictício).
# Uso: PGHOST=localhost PGUSER=postgres PGPASSWORD=... ./scripts/db-test-setup.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${TEST_DB:-gestao_semfaz_test}"
export PGHOST="${PGHOST:-localhost}" PGUSER="${PGUSER:-postgres}"

psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists ${DB} with (force)" -c "create database ${DB}"
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f tests/db/shim/supabase_shim.sql
for f in supabase/migrations/*.sql; do
  psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$f"
done
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f supabase/seed.sql
echo "ok: ${DB}"
