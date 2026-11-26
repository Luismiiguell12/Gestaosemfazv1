-- Fase 1 · auditoria imutável

create table public.auditoria (
  id bigint generated always as identity primary key,
  em timestamptz not null default now(),
  ator_id uuid,
  ator_perfil public.perfil_usuario,
  acao text not null,
  tabela text,
  registro_id text,
  antes jsonb,
  depois jsonb,
  contexto jsonb not null default '{}'::jsonb
);
create index auditoria_em_idx on public.auditoria (em desc);
create index auditoria_ator_idx on public.auditoria (ator_id);
create index auditoria_tabela_idx on public.auditoria (tabela, registro_id);

create or replace function app.auditoria_imutavel()
returns trigger language plpgsql set search_path = ''
as $$ begin raise exception using message = 'Registros de auditoria não podem ser alterados nem apagados.', errcode = '42501'; end $$;

create trigger auditoria_sem_update before update or delete on public.auditoria
  for each row execute function app.auditoria_imutavel();
create trigger auditoria_sem_truncate before truncate on public.auditoria
  for each statement execute function app.auditoria_imutavel();

revoke all on public.auditoria from public, anon, authenticated, service_role;

create or replace function app.contexto_auditoria()
returns jsonb language sql stable set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'papel', auth.jwt() ->> 'role',
    'aal', auth.jwt() ->> 'aal',
    'solicitacao_id', nullif(current_setting('app.solicitacao_id', true), '')
  ))
$$;

create or replace function app.registrar_evento(p_acao text, p_tabela text, p_registro text, p_antes jsonb, p_depois jsonb, p_ator uuid default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_ator uuid := coalesce(p_ator, auth.uid());
begin
  insert into public.auditoria (ator_id, ator_perfil, acao, tabela, registro_id, antes, depois, contexto)
  values (v_ator, (select perfil from public.usuarios where id = v_ator), p_acao, p_tabela, p_registro, p_antes, p_depois, app.contexto_auditoria());
end $$;

create or replace function app.auditar_linha()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_old jsonb; v_new jsonb; v_id text;
begin
  if tg_op in ('UPDATE', 'DELETE') then v_old := to_jsonb(old); end if;
  if tg_op in ('INSERT', 'UPDATE') then v_new := to_jsonb(new); end if;
  if tg_op = 'UPDATE' and v_old = v_new then return null; end if;
  v_id := coalesce(v_new ->> 'id', v_old ->> 'id',
                   concat_ws(':', coalesce(v_new, v_old) ->> 'usuario_id', coalesce(v_new, v_old) ->> 'modulo_codigo',
                             coalesce(v_new, v_old) ->> 'unidade_id', coalesce(v_new, v_old) ->> 'perfil',
                             coalesce(v_new, v_old) ->> 'chave'));
  perform app.registrar_evento(lower(tg_op), tg_table_name, v_id, v_old, v_new);
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array['unidades', 'cargos', 'servidores', 'usuarios', 'modulos', 'pacotes_padrao',
                           'usuario_modulos_extras', 'usuario_unidades_extras', 'feriados', 'solicitacoes', 'configuracoes']
  loop
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()',
                   t || '_auditoria', t);
  end loop;
end $$;

revoke execute on function app.registrar_evento(text, text, text, jsonb, jsonb, uuid) from public, anon, authenticated;
