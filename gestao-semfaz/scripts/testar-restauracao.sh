#!/usr/bin/env bash
# Teste de restauração (Fase 7): banco A com dados fictícios → backup cifrado → banco B só com a estrutura
# → restauração → compara a contagem de todas as tabelas. Só PostgreSQL local; nenhum dado real.
set -euo pipefail
export PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGPASSWORD=${PGPASSWORD:-postgres}
cd "$(dirname "$0")/.."
A=gestao_semfaz_test; B=gestao_semfaz_restaurado
TMP=$(mktemp -d); trap 'rm -rf "$TMP"; dropdb --if-exists "$B" >/dev/null 2>&1 || true' EXIT
export BACKUP_PASSPHRASE="senha-de-teste-ficticia-$RANDOM"

bash scripts/db-test-setup.sh >/dev/null                      # A: migrations + seed fictício
psql -d "$A" -q -f tests/db/fixtures.sql                      # + usuários fictícios
# + movimento fictício (como a secretária): contrato, aluguéis, UC, fatura, demanda, auditoria
psql -d "$A" -q -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a002","role":"authenticated","aal":"aal2"}', true);
select public.criar_contrato('{"numero":"900/2026","imovel_descricao":"Sala fictícia","inicio":"2026-01-01","fim":"2026-12-31","valor_mensal":1000}', '{"tipo":"PF","nome":"Locador Fictício","documento":"52998224725"}');
select public.criar_uc('igua', '998877', (select id from public.contratos where numero = '900/2026'));
select public.lancar_fatura((select id from public.unidades_consumidoras where numero = '998877'), '2026-10-01', 80, '2026-10-20', 10);
select public.criar_demanda(json_build_object('titulo', 'Demanda fictícia', 'unidade_id', (select id from public.unidades where sigla = 'COFIT'))::jsonb, array[(select id from public.servidores where matricula = '000101')]);
commit;
SQL
DB_URL="postgresql:///$A" bash scripts/backup-banco.sh "$TMP/bkp" >/dev/null
mkdir -p "$TMP/rest"
tar -C "$TMP/bkp" -cf - dados.dump auth.dump | gpg --batch --quiet --pinentry-mode loopback --passphrase "$BACKUP_PASSPHRASE" --symmetric --cipher-algo AES256 -o "$TMP/rest/backup-teste.tar.gpg"
cp "$TMP/bkp/contagem.csv" "$TMP/rest/"
if strings "$TMP/rest/backup-teste.tar.gpg" | grep -q "exemplo.gov.br"; then echo "FALHA: arquivo cifrado contém texto legível"; exit 1; fi

dropdb --if-exists "$B"; createdb "$B"                         # B: só estrutura (sem seed)
psql -d "$B" -q -v ON_ERROR_STOP=1 -f tests/db/shim/supabase_shim.sql
for f in supabase/migrations/*.sql; do psql -d "$B" -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null; done
DB_URL="postgresql:///$B" bash scripts/restaurar-backup.sh "$TMP/rest" >/dev/null

conta() { psql -d "$1" -tA -F ';' -c "select table_schema||'.'||table_name, (xpath('/row/n/text()', query_to_xml(format('select count(*) n from %I.%I', table_schema, table_name), false, true, '')))[1]::text from information_schema.tables where table_schema in ('public','app','auth') and table_type = 'BASE TABLE' order by 1"; }
if diff <(conta "$A") <(conta "$B") > "$TMP/diff.txt"; then
  # numeração continua (sequências restauradas): a próxima demanda não repete número
  ultimo=$(psql -d "$A" -tAc "select max(numero) from public.demandas")
  proximo=$(psql -d "$B" -tAc "select nextval(pg_get_serial_sequence('public.demandas', 'numero'))")
  [ "$proximo" -gt "$ultimo" ] || { echo "FALHA: sequência de demandas não restaurada ($proximo <= $ultimo)"; exit 1; }
  echo "ok: restauração idêntica ($(conta "$A" | wc -l) tabelas, $(conta "$A" | awk -F';' '{s+=$2} END {print s}') linhas)"
else
  echo "FALHA: contagens diferentes"; cat "$TMP/diff.txt"; exit 1
fi
