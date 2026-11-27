-- Verificação de segurança do banco (Fase 7). Só LEITURA.
-- Rodar no SQL Editor do Supabase ou com psql antes de cada implantação.
-- Cada linha devolve: item, situação ('ok' | 'FALHA' | 'ATENÇÃO') e detalhe.

with checks as (
  -- 1. RLS em todas as tabelas do schema public
  select 'RLS em todas as tabelas' item,
         case when count(*) = 0 then 'ok' else 'FALHA' end situacao,
         coalesce(string_agg(c.relname, ', '), 'nenhuma tabela sem RLS') detalhe
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
  union all
  -- 2. anon sem nenhum privilégio em tabelas
  select 'anon sem acesso a tabelas', case when count(*) = 0 then 'ok' else 'FALHA' end,
         coalesce(string_agg(distinct table_name, ', '), 'nenhum grant para anon')
    from information_schema.role_table_grants where grantee = 'anon' and table_schema in ('public', 'app', 'storage')
     and table_name not in ('buckets', 'objects', 'migrations', 's3_multipart_uploads', 's3_multipart_uploads_parts', 'buckets_analytics', 'prefixes', 'buckets_vectors', 'vector_indexes')
  union all
  -- 3. nenhuma função de public/app executável por anon ou PUBLIC
  select 'funções fechadas para anon/PUBLIC', case when count(*) = 0 then 'ok' else 'FALHA' end,
         coalesce(string_agg(distinct routine_schema || '.' || routine_name, ', '), 'nenhuma')
    from information_schema.role_routine_grants where grantee in ('anon', 'PUBLIC') and routine_schema in ('public', 'app')
  union all
  -- 4. SECURITY DEFINER sempre com search_path fixo
  select 'security definer com search_path fixo', case when count(*) = 0 then 'ok' else 'FALHA' end,
         coalesce(string_agg(n.nspname || '.' || p.proname, ', '), 'todas fixas')
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'app') and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%')
  union all
  -- 5. buckets privados
  select 'buckets do Storage privados', case when count(*) filter (where public) = 0 then 'ok' else 'FALHA' end,
         string_agg(id || case when public then ' (PÚBLICO)' else '' end, ', ')
    from storage.buckets
  union all
  -- 6. auditoria imutável
  select 'auditoria imutável (trigger)', case when count(*) > 0 then 'ok' else 'FALHA' end,
         coalesce(string_agg(tgname, ', '), 'sem trigger de bloqueio')
    from pg_trigger where tgrelid = 'public.auditoria'::regclass and not tgisinternal
  union all
  -- 7. MFA obrigatória ligada (desligar só no ambiente de testes)
  select 'MFA obrigatória para admin/secretária',
         case when coalesce((select (valor)::boolean from public.configuracoes where chave = 'auth.mfa_obrigatoria'), true) then 'ok' else 'ATENÇÃO' end,
         'auth.mfa_obrigatoria = ' || coalesce((select valor::text from public.configuracoes where chave = 'auth.mfa_obrigatoria'), 'true (padrão)')
  union all
  -- 8. rotinas agendadas
  select 'rotinas diárias (pg_cron)',
         case when to_regclass('cron.job') is null then 'ATENÇÃO'
              when (xpath('/row/n/text()', query_to_xml($q$select count(*) n from cron.job where jobname in ('rotinas-diarias-demandas', 'avisar-atrasos-folhas')$q$, false, true, '')))[1]::text = '2' then 'ok'
              else 'ATENÇÃO' end,
         case when to_regclass('cron.job') is null then 'pg_cron não instalado: rotinas diárias não rodam sozinhas'
              else (xpath('/row/j/text()', query_to_xml($q$select string_agg(jobname || ' ' || schedule, ', ') j from cron.job$q$, false, true, '')))[1]::text end
  union all
  -- 9. ao menos um administrador ativo, e não muitos
  select 'administradores ativos', case when count(*) between 1 and 3 then 'ok' else 'ATENÇÃO' end, count(*)::text || ' administrador(es)'
    from public.usuarios where perfil = 'administrador' and ativo
  union all
  -- 10. CPF do locador fora da API
  select 'CPF do locador sem acesso direto',
         case when has_column_privilege('authenticated', 'public.locadores', 'documento', 'select') then 'FALHA' else 'ok' end,
         'coluna locadores.documento só via RPC mascarada'
  union all
  -- 11. servidores sem tipo de vínculo (adendo 01)
  select 'servidores com vínculo informado',
         case when count(*) filter (where tipo_vinculo is null and situacao = 'ativo') = 0 then 'ok' else 'ATENÇÃO' end,
         count(*) filter (where tipo_vinculo is null and situacao = 'ativo')::text || ' servidor(es) ativo(s) sem vínculo (não elegíveis ao adicional)'
    from public.servidores
  union all
  -- 12. pacote padrão ainda provisório
  select 'permissões padrão oficiais',
         case when count(*) filter (where provisorio) = 0 then 'ok' else 'ATENÇÃO' end,
         count(*) filter (where provisorio)::text || ' item(ns) do pacote padrão ainda provisório(s) (seção 9)'
    from public.pacotes_padrao
)
select * from checks order by case situacao when 'FALHA' then 0 when 'ATENÇÃO' then 1 else 2 end, item;
