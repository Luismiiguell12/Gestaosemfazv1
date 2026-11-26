-- GERADO AUTOMATICAMENTE por scripts/gerar-sql-unico.mjs. Não editar à mão.
-- Uso: Supabase (web) → SQL Editor → New query → colar TUDO → Run. Somente em projeto NOVO e vazio.
-- Contém 13 migrations, na ordem.

-- ===================== 20261126000100_base.sql =====================
-- Fase 1 · base: extensões, schemas, tipos, utilitários
create schema if not exists extensions;
create extension if not exists unaccent with schema extensions;
create extension if not exists pgcrypto with schema extensions;
grant usage on schema extensions to authenticated, service_role;

-- schema interno (não exposto pela API)
create schema if not exists app;
revoke all on schema app from public;
grant usage on schema app to authenticated, service_role;

-- privilégios: nada por padrão
revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon;
alter default privileges in schema public revoke all on tables from anon, authenticated;
-- global (padrão por schema não consegue revogar o EXECUTE de PUBLIC)
alter default privileges revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from anon;

create type public.perfil_usuario as enum ('administrador', 'secretaria', 'diretor', 'coordenador', 'funcionario');
create type public.tipo_unidade as enum ('gabinete', 'diretoria', 'coordenadoria', 'assessoria');
create type public.situacao_servidor as enum ('ativo', 'inativo');
create type public.status_modulo as enum ('ativo', 'em_breve', 'em_definicao');
create type public.status_solicitacao as enum ('pendente', 'aprovada', 'recusada', 'bloqueada', 'cancelada');
create type public.tipo_solicitacao as enum (
  'unidade_criar', 'unidade_alterar',
  'cargo_criar', 'cargo_alterar',
  'servidor_alterar',
  'usuario_perfil',
  'acesso_unidade_conceder', 'acesso_unidade_retirar',
  'feriado_alterar', 'feriado_excluir'
);

-- normalização p/ busca (sem acento, minúsculas)
create or replace function app.normalizar(t text)
returns text language sql immutable parallel safe set search_path = ''
as $$ select lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(t, ''))) $$;

create or replace function app.tocar_atualizado_em()
returns trigger language plpgsql set search_path = ''
as $$ begin new.atualizado_em := now(); return new; end $$;

-- erro genérico ao usuário (sem detalhes internos)
create or replace function app.erro(mensagem text, codigo text default 'P0001')
returns void language plpgsql set search_path = ''
as $$ begin raise exception using message = mensagem, errcode = codigo; end $$;

-- ===================== 20261126000200_tabelas.sql =====================
-- Fase 1 · tabelas

-- estrutura organizacional (cadastrável, não fixa no código)
create table public.unidades (
  id uuid primary key default gen_random_uuid(),
  sigla text not null check (btrim(sigla) <> '' and length(sigla) <= 40),
  nome text not null check (btrim(nome) <> '' and length(nome) <= 200),
  tipo public.tipo_unidade not null,
  unidade_pai_id uuid references public.unidades (id) on delete restrict,
  ordem integer not null default 0,
  ativa boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint unidades_raiz_gabinete check ((tipo = 'gabinete') = (unidade_pai_id is null)),
  constraint unidades_pai_diferente check (unidade_pai_id is null or unidade_pai_id <> id)
);
create unique index unidades_sigla_uk on public.unidades (app.normalizar(sigla));
create unique index unidades_um_gabinete on public.unidades (tipo) where tipo = 'gabinete';
create index unidades_pai_idx on public.unidades (unidade_pai_id);

create or replace function app.unidades_validar()
returns trigger language plpgsql set search_path = ''
as $$
declare v_pai public.tipo_unidade; v_ciclo boolean;
begin
  if new.unidade_pai_id is not null then
    select tipo into v_pai from public.unidades where id = new.unidade_pai_id;
    if new.tipo = 'diretoria' and v_pai <> 'gabinete' then
      perform app.erro('Diretoria deve estar ligada ao Gabinete.', '23514');
    end if;
    if new.tipo = 'assessoria' and v_pai <> 'gabinete' then
      perform app.erro('Assessoria deve estar ligada ao Gabinete.', '23514');
    end if;
    if new.tipo = 'coordenadoria' and v_pai not in ('gabinete', 'diretoria') then
      perform app.erro('Coordenadoria deve estar ligada a uma diretoria ou ao Gabinete.', '23514');
    end if;
    with recursive cadeia(id) as (
      select new.unidade_pai_id
      union
      select u.unidade_pai_id from public.unidades u join cadeia c on u.id = c.id where u.unidade_pai_id is not null
    ) select exists (select 1 from cadeia where id = new.id) into v_ciclo;
    if v_ciclo then perform app.erro('Estrutura inválida: ciclo entre unidades.', '23514'); end if;
  end if;
  return new;
end $$;
create trigger unidades_validar before insert or update on public.unidades
  for each row execute function app.unidades_validar();
create trigger unidades_atualizado before update on public.unidades
  for each row execute function app.tocar_atualizado_em();

-- cargos (lista oficial pendente)
create table public.cargos (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (btrim(nome) <> '' and length(nome) <= 120),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create unique index cargos_nome_uk on public.cargos (app.normalizar(nome));
create trigger cargos_atualizado before update on public.cargos
  for each row execute function app.tocar_atualizado_em();

-- servidores: matrícula obrigatória e única (chave das folhas de ponto)
create table public.servidores (
  id uuid primary key default gen_random_uuid(),
  nome_completo text not null check (btrim(nome_completo) <> '' and length(nome_completo) <= 200),
  matricula text not null check (matricula ~ '^[0-9A-Za-z./-]{1,20}$'),
  cargo_id uuid not null references public.cargos (id) on delete restrict,
  unidade_id uuid not null references public.unidades (id) on delete restrict,
  situacao public.situacao_servidor not null default 'ativo',
  email_institucional text check (
    email_institucional is null or (email_institucional ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and length(email_institucional) <= 254)
  ),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create unique index servidores_matricula_uk on public.servidores (upper(matricula));
create unique index servidores_email_uk on public.servidores (lower(email_institucional)) where email_institucional is not null;
create index servidores_unidade_idx on public.servidores (unidade_id);

create or replace function app.servidores_normalizar()
returns trigger language plpgsql set search_path = ''
as $$
begin
  new.matricula := btrim(new.matricula);
  new.nome_completo := btrim(regexp_replace(new.nome_completo, '\s+', ' ', 'g'));
  new.email_institucional := nullif(lower(btrim(new.email_institucional)), '');
  return new;
end $$;
create trigger servidores_normalizar before insert or update on public.servidores
  for each row execute function app.servidores_normalizar();
create trigger servidores_atualizado before update on public.servidores
  for each row execute function app.tocar_atualizado_em();

-- contas de acesso (1:1 com auth.users)
create table public.usuarios (
  id uuid primary key references auth.users (id) on delete restrict,
  servidor_id uuid not null unique references public.servidores (id) on delete restrict,
  perfil public.perfil_usuario not null,
  ativo boolean not null default true,
  desativado_em timestamptz,
  desativado_por uuid references public.usuarios (id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create trigger usuarios_atualizado before update on public.usuarios
  for each row execute function app.tocar_atualizado_em();

create or replace function app.usuarios_validar()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if not exists (select 1 from public.servidores s where s.id = new.servidor_id and s.email_institucional is not null) then
    perform app.erro('Servidor sem e-mail institucional não pode ter login.', '23514');
  end if;
  return new;
end $$;
create trigger usuarios_validar before insert or update of servidor_id on public.usuarios
  for each row execute function app.usuarios_validar();

-- e-mail do servidor com login não pode ser removido
create or replace function app.servidores_email_login()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.email_institucional is null and exists (select 1 from public.usuarios u where u.servidor_id = new.id) then
    perform app.erro('E-mail institucional é obrigatório para quem tem login.', '23514');
  end if;
  return new;
end $$;
create trigger servidores_email_login before update of email_institucional on public.servidores
  for each row execute function app.servidores_email_login();

-- módulos e pacotes
create table public.modulos (
  codigo text primary key check (codigo ~ '^[a-z_]{2,40}$'),
  nome text not null,
  rota text not null,
  icone text not null,
  ordem integer not null,
  status public.status_modulo not null default 'em_breve',
  fase integer not null check (fase between 1 and 9),
  no_menu boolean not null default true
);

-- PROVISÓRIO: aguardando definição oficial da SEMFAZ (prompt seção 4)
create table public.pacotes_padrao (
  perfil public.perfil_usuario not null,
  modulo_codigo text not null references public.modulos (codigo) on delete cascade,
  provisorio boolean not null default true,
  primary key (perfil, modulo_codigo)
);

create table public.usuario_modulos_extras (
  usuario_id uuid not null references public.usuarios (id) on delete cascade,
  modulo_codigo text not null references public.modulos (codigo) on delete cascade,
  concedido_por uuid not null references public.usuarios (id),
  concedido_em timestamptz not null default now(),
  primary key (usuario_id, modulo_codigo)
);

create table public.usuario_unidades_extras (
  usuario_id uuid not null references public.usuarios (id) on delete cascade,
  unidade_id uuid not null references public.unidades (id) on delete cascade,
  solicitacao_id uuid,
  concedido_em timestamptz not null default now(),
  primary key (usuario_id, unidade_id)
);

-- feriados (dias úteis)
create table public.feriados (
  id uuid primary key default gen_random_uuid(),
  data date not null unique,
  descricao text not null check (btrim(descricao) <> '' and length(descricao) <= 120),
  abrangencia text not null check (abrangencia in ('nacional', 'estadual', 'municipal', 'ponto_facultativo')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create trigger feriados_atualizado before update on public.feriados
  for each row execute function app.tocar_atualizado_em();

-- aprovações
create table public.solicitacoes (
  id uuid primary key default gen_random_uuid(),
  tipo public.tipo_solicitacao not null,
  alvo_id uuid,
  dados_antes jsonb not null default '{}'::jsonb,
  dados_depois jsonb not null default '{}'::jsonb,
  versao_alvo text,
  justificativa text not null check (length(btrim(justificativa)) between 5 and 2000),
  anexo_path text check (anexo_path is null or anexo_path ~ '^aprovacoes/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|png|jpg)$'),
  solicitante_id uuid not null references public.usuarios (id),
  status public.status_solicitacao not null default 'pendente',
  decidido_por uuid references public.usuarios (id),
  decidido_em timestamptz,
  comentario_decisao text check (comentario_decisao is null or length(comentario_decisao) <= 2000),
  criado_em timestamptz not null default now(),
  constraint solicitacoes_nao_aprova_proprio check (decidido_por is null or decidido_por <> solicitante_id),
  constraint solicitacoes_recusa_comentada check (status <> 'recusada' or length(btrim(coalesce(comentario_decisao, ''))) > 0),
  constraint solicitacoes_decisao_completa check ((status in ('aprovada', 'recusada')) = (decidido_por is not null))
);
create index solicitacoes_status_idx on public.solicitacoes (status, criado_em desc);
create index solicitacoes_solicitante_idx on public.solicitacoes (solicitante_id);
alter table public.usuario_unidades_extras
  add constraint usuario_unidades_extras_solicitacao_fk foreign key (solicitacao_id) references public.solicitacoes (id);

-- notificações internas
create table public.notificacoes (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.usuarios (id) on delete cascade,
  tipo text not null,
  titulo text not null,
  texto text,
  link text check (link is null or link ~ '^/[A-Za-z0-9/_?=&.-]*$'),
  lida_em timestamptz,
  criado_em timestamptz not null default now()
);
create index notificacoes_usuario_idx on public.notificacoes (usuario_id, criado_em desc);

-- configurações (prazos etc.)
create table public.configuracoes (
  chave text primary key check (chave ~ '^[a-z_.]{2,80}$'),
  valor jsonb not null,
  descricao text not null
);

-- limite de requisições (só service-role)
create table public.limites_requisicao (
  chave text primary key,
  janela_inicio timestamptz not null,
  contador integer not null
);

-- ===================== 20261126000300_autorizacao.sql =====================
-- Fase 1 · funções de autorização (backend é a barreira; UI só esconde)
-- Encapsulam auth.uid()/auth.jwt() (Supabase) p/ facilitar migração.

create or replace function app.uid()
returns uuid language sql stable set search_path = ''
as $$ select auth.uid() $$;

create or replace function app.aal2()
returns boolean language sql stable set search_path = ''
as $$ select coalesce(auth.jwt() ->> 'aal', '') = 'aal2' $$;

-- perfil do usuário atual, só se conta e servidor ativos (checado no banco a cada request)
create or replace function app.perfil_atual()
returns public.perfil_usuario language sql stable security definer set search_path = ''
as $$
  select u.perfil
  from public.usuarios u join public.servidores s on s.id = u.servidor_id
  where u.id = auth.uid() and u.ativo and s.situacao = 'ativo'
$$;

create or replace function app.exige_mfa(p public.perfil_usuario)
returns boolean language sql immutable set search_path = ''
as $$ select p in ('administrador', 'secretaria') $$;

-- gate de toda política
create or replace function app.sessao_ok()
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(
    (select case when app.exige_mfa(p) then app.aal2() else true end
       from (select app.perfil_atual() as p) x where p is not null),
    false)
$$;

create or replace function app.gestor_geral()
returns boolean language sql stable security definer set search_path = ''
as $$ select app.sessao_ok() and app.perfil_atual() in ('administrador', 'secretaria') $$;

create or replace function app.eh_administrador()
returns boolean language sql stable security definer set search_path = ''
as $$ select app.sessao_ok() and app.perfil_atual() = 'administrador' $$;

create or replace function app.servidor_atual()
returns uuid language sql stable security definer set search_path = ''
as $$ select u.servidor_id from public.usuarios u where u.id = auth.uid() $$;

create or replace function app.unidade_atual()
returns uuid language sql stable security definer set search_path = ''
as $$
  select s.unidade_id from public.usuarios u join public.servidores s on s.id = u.servidor_id
  where u.id = auth.uid()
$$;

create or replace function app.subarvore(raiz uuid)
returns setof uuid language sql stable security definer set search_path = ''
as $$
  with recursive arv(id) as (
    select raiz
    union
    select u.id from public.unidades u join arv a on u.unidade_pai_id = a.id
  ) select id from arv where id is not null
$$;

-- unidades sob gestão do usuário atual
create or replace function app.unidades_escopo()
returns setof uuid language plpgsql stable security definer set search_path = ''
as $$
declare p public.perfil_usuario;
begin
  if not app.sessao_ok() then return; end if;
  p := app.perfil_atual();
  if p in ('administrador', 'secretaria') then
    return query select id from public.unidades;
  elsif p = 'diretor' then
    return query
      select app.subarvore(app.unidade_atual())
      union
      select app.subarvore(e.unidade_id) from public.usuario_unidades_extras e where e.usuario_id = auth.uid();
  elsif p = 'coordenador' then
    return query
      select app.unidade_atual()
      union
      select e.unidade_id from public.usuario_unidades_extras e where e.usuario_id = auth.uid();
  end if;
  -- funcionário: sem escopo de gestão (decisão D13)
end $$;

create or replace function app.na_escopo(unidade uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from app.unidades_escopo() e where e = unidade) $$;

-- módulos visíveis = pacote padrão do perfil ∪ extras
create or replace function app.modulos_do_usuario()
returns setof text language sql stable security definer set search_path = ''
as $$
  select pp.modulo_codigo from public.pacotes_padrao pp
   where app.sessao_ok() and pp.perfil = app.perfil_atual()
  union
  select e.modulo_codigo from public.usuario_modulos_extras e
   where app.sessao_ok() and e.usuario_id = auth.uid()
$$;

create or replace function app.tem_modulo(codigo text)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from app.modulos_do_usuario() m where m = codigo) $$;

grant execute on all functions in schema app to authenticated, service_role;

-- ===================== 20261126000400_auditoria.sql =====================
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

-- ===================== 20261126000500_rls.sql =====================
-- Fase 1 · RLS em TODAS as tabelas. Sem política = sem acesso.

do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- leitura básica (organograma, cargos, módulos, configurações): qualquer usuário ativo (D4)
grant select on public.unidades, public.cargos, public.modulos, public.pacotes_padrao, public.configuracoes, public.feriados to authenticated;
create policy unidades_ler on public.unidades for select to authenticated using ((select app.sessao_ok()));
create policy cargos_ler on public.cargos for select to authenticated using ((select app.sessao_ok()));
create policy modulos_ler on public.modulos for select to authenticated using ((select app.sessao_ok()));
create policy pacotes_ler on public.pacotes_padrao for select to authenticated using ((select app.sessao_ok()));
create policy configuracoes_ler on public.configuracoes for select to authenticated using ((select app.sessao_ok()));
create policy feriados_ler on public.feriados for select to authenticated using ((select app.sessao_ok()));

-- feriado novo: secretária/admin (alteração e exclusão só por aprovação)
grant insert (data, descricao, abrangencia) on public.feriados to authenticated;
create policy feriados_inserir on public.feriados for insert to authenticated with check ((select app.gestor_geral()));

-- servidores: o próprio; chefia no escopo com módulo "usuarios"
grant select on public.servidores to authenticated;
create policy servidores_ler on public.servidores for select to authenticated using (
  (select app.sessao_ok()) and (
    id = (select app.servidor_atual())
    or ((select app.tem_modulo('usuarios')) and unidade_id in (select app.unidades_escopo()))
  )
);
grant insert (nome_completo, matricula, cargo_id, unidade_id, email_institucional) on public.servidores to authenticated;
create policy servidores_inserir on public.servidores for insert to authenticated with check ((select app.gestor_geral()));

-- usuários
grant select on public.usuarios to authenticated;
create policy usuarios_ler on public.usuarios for select to authenticated using (
  (select app.sessao_ok()) and (
    id = (select app.uid())
    or ((select app.tem_modulo('usuarios'))
        and exists (select 1 from public.servidores s where s.id = servidor_id and s.unidade_id in (select app.unidades_escopo())))
  )
);

grant select on public.usuario_modulos_extras, public.usuario_unidades_extras to authenticated;
create policy modulos_extras_ler on public.usuario_modulos_extras for select to authenticated using (
  (select app.sessao_ok()) and (
    usuario_id = (select app.uid())
    or exists (select 1 from public.usuarios u where u.id = usuario_id)  -- herda escopo da política de usuarios
  )
);
create policy unidades_extras_ler on public.usuario_unidades_extras for select to authenticated using (
  (select app.sessao_ok()) and (
    usuario_id = (select app.uid())
    or exists (select 1 from public.usuarios u where u.id = usuario_id)
  )
);

-- solicitações: solicitante ou secretária/admin
grant select on public.solicitacoes to authenticated;
create policy solicitacoes_ler on public.solicitacoes for select to authenticated using (
  (select app.sessao_ok()) and (solicitante_id = (select app.uid()) or (select app.gestor_geral()))
);

-- notificações: só as próprias
grant select on public.notificacoes to authenticated;
create policy notificacoes_ler on public.notificacoes for select to authenticated using (
  (select app.sessao_ok()) and usuario_id = (select app.uid())
);

-- auditoria: secretária/admin com módulo auditoria
grant select on public.auditoria to authenticated;
create policy auditoria_ler on public.auditoria for select to authenticated using (
  (select app.gestor_geral()) and (select app.tem_modulo('auditoria'))
);

-- limites_requisicao: nenhuma política (só service-role)

-- ===================== 20261126000600_aprovacoes.sql =====================
-- Fase 1 · central de aprovações (6.9)
-- Tabelas protegidas não têm UPDATE/DELETE direto: só mudam aqui.

alter table public.solicitacoes add column resumo text not null default '';
alter table public.solicitacoes alter column resumo drop default;

create or replace function app.campos_permitidos(t public.tipo_solicitacao)
returns text[] language sql immutable set search_path = ''
as $$
  select case t
    when 'unidade_criar' then array['sigla', 'nome', 'tipo', 'unidade_pai_id', 'ordem']
    when 'unidade_alterar' then array['sigla', 'nome', 'unidade_pai_id', 'ordem', 'ativa']
    when 'cargo_criar' then array['nome']
    when 'cargo_alterar' then array['nome', 'ativo']
    when 'servidor_alterar' then array['nome_completo', 'matricula', 'cargo_id', 'unidade_id', 'situacao', 'email_institucional']
    when 'usuario_perfil' then array['perfil']
    when 'acesso_unidade_conceder' then array['unidade_id']
    when 'acesso_unidade_retirar' then array['unidade_id']
    when 'feriado_alterar' then array['data', 'descricao', 'abrangencia']
    else array[]::text[]
  end
$$;

create or replace function app.tabela_alvo(t public.tipo_solicitacao)
returns text language sql immutable set search_path = ''
as $$
  select case
    when t in ('unidade_criar', 'unidade_alterar') then 'unidades'
    when t in ('cargo_criar', 'cargo_alterar') then 'cargos'
    when t = 'servidor_alterar' then 'servidores'
    when t in ('usuario_perfil', 'acesso_unidade_conceder', 'acesso_unidade_retirar') then 'usuarios'
    else 'feriados'
  end
$$;

create or replace function app.rotulo_campo(k text)
returns text language sql immutable set search_path = ''
as $$
  select case k
    when 'sigla' then 'sigla' when 'nome' then 'nome' when 'tipo' then 'tipo'
    when 'unidade_pai_id' then 'unidade superior' when 'ordem' then 'ordem' when 'ativa' then 'situação'
    when 'ativo' then 'situação' when 'nome_completo' then 'nome' when 'matricula' then 'matrícula'
    when 'cargo_id' then 'cargo' when 'unidade_id' then 'unidade' when 'situacao' then 'situação'
    when 'email_institucional' then 'e-mail' when 'perfil' then 'perfil' when 'data' then 'data'
    when 'descricao' then 'descrição' when 'abrangencia' then 'abrangência' else k
  end
$$;

create or replace function app.linha_json(tabela text, registro uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v jsonb;
begin
  execute format('select to_jsonb(t) from public.%I t where t.id = $1', tabela) into v using registro;
  return v;
end $$;

create or replace function app.versao_registro(tabela text, registro uuid)
returns text language sql stable security definer set search_path = ''
as $$ select md5(app.linha_json(tabela, registro)::text) $$;

-- normaliza tipos via record da tabela (falha = dado inválido)
create or replace function app.normalizar_dados(tabela text, dados jsonb)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v jsonb;
begin
  execute format('select to_jsonb(jsonb_populate_record(null::public.%I, $1))', tabela) into v using dados;
  return (select coalesce(jsonb_object_agg(k, v -> k), '{}'::jsonb) from jsonb_object_keys(dados) k);
exception when others then
  perform app.erro('Dados inválidos na solicitação.', '22023');
end $$;

create or replace function app.atualizar_por_json(tabela text, registro uuid, dados jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_cols text; v_src text;
begin
  select string_agg(quote_ident(k), ', '), string_agg('r.' || quote_ident(k), ', ')
    into v_cols, v_src from jsonb_object_keys(dados) k;
  if v_cols is null then return; end if;
  execute format('update public.%I t set (%s) = (select %s from jsonb_populate_record(null::public.%I, $1) r) where t.id = $2',
                 tabela, v_cols, v_src, tabela) using dados, registro;
end $$;

create or replace function app.notificar(p_usuario uuid, p_tipo text, p_titulo text, p_texto text, p_link text)
returns void language sql security definer set search_path = ''
as $$ insert into public.notificacoes (usuario_id, tipo, titulo, texto, link) values (p_usuario, p_tipo, p_titulo, p_texto, p_link) $$;

create or replace function app.nome_usuario(p_usuario uuid)
returns text language sql stable security definer set search_path = ''
as $$ select s.nome_completo from public.usuarios u join public.servidores s on s.id = u.servidor_id where u.id = p_usuario $$;

-- ===== solicitar =====
create or replace function public.solicitar(
  p_tipo public.tipo_solicitacao, p_alvo_id uuid, p_dados jsonb, p_justificativa text, p_anexo_path text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_perfil public.perfil_usuario := app.perfil_atual();
  v_geral boolean := app.gestor_geral();
  v_chefia boolean;
  v_tabela text := app.tabela_alvo(p_tipo);
  v_linha jsonb;
  v_norm jsonb;
  v_antes jsonb := '{}'::jsonb;
  v_depois jsonb := '{}'::jsonb;
  v_versao text;
  v_ok boolean := false;
  v_resumo text;
  v_unidade uuid;
  v_id uuid;
  v_aprovador uuid;
begin
  if not app.sessao_ok() then perform app.erro('Acesso não permitido.', '42501'); end if;
  v_chefia := v_perfil in ('diretor', 'coordenador') and app.tem_modulo('usuarios');
  if p_dados is null or jsonb_typeof(p_dados) <> 'object' then perform app.erro('Dados inválidos na solicitação.', '22023'); end if;
  if exists (select 1 from jsonb_object_keys(p_dados) k where not (k = any (app.campos_permitidos(p_tipo)))) then
    perform app.erro('Campo não permitido nesta solicitação.', '22023');
  end if;

  if p_tipo in ('unidade_criar', 'cargo_criar') then
    if p_alvo_id is not null then perform app.erro('Dados inválidos na solicitação.', '22023'); end if;
  else
    v_linha := app.linha_json(v_tabela, p_alvo_id);
    if v_linha is null then perform app.erro('Registro não encontrado.', 'P0002'); end if;
    v_versao := md5(v_linha::text);
  end if;

  -- normalização / diferença
  if p_tipo in ('acesso_unidade_conceder', 'acesso_unidade_retirar') then
    begin v_unidade := (p_dados ->> 'unidade_id')::uuid;
    exception when others then perform app.erro('Dados inválidos na solicitação.', '22023'); end;
    if v_unidade is null or not exists (select 1 from public.unidades where id = v_unidade) then
      perform app.erro('Unidade não encontrada.', 'P0002');
    end if;
    v_depois := jsonb_build_object('unidade_id', v_unidade);
  elsif p_tipo = 'feriado_excluir' then
    v_antes := v_linha - array['id', 'criado_em', 'atualizado_em'];
  else
    v_norm := app.normalizar_dados(v_tabela, p_dados);
    if v_linha is null then
      v_depois := v_norm;
    else
      select coalesce(jsonb_object_agg(k, v_linha -> k), '{}'::jsonb), coalesce(jsonb_object_agg(k, v_norm -> k), '{}'::jsonb)
        into v_antes, v_depois
        from jsonb_object_keys(v_norm) k where (v_linha -> k) is distinct from (v_norm -> k);
    end if;
    if v_depois = '{}'::jsonb then perform app.erro('Nenhuma alteração informada.', '22023'); end if;
  end if;

  -- permissão por tipo
  case p_tipo
    when 'unidade_criar' then
      if not (v_depois ? 'sigla' and v_depois ? 'nome' and v_depois ? 'tipo') then
        perform app.erro('Informe sigla, nome e tipo da unidade.', '22023');
      end if;
      v_ok := v_geral or (v_perfil = 'diretor' and app.na_escopo((v_depois ->> 'unidade_pai_id')::uuid));
      v_resumo := 'Nova unidade: ' || (v_depois ->> 'nome');
    when 'unidade_alterar' then
      v_ok := v_geral or (v_perfil = 'diretor' and app.na_escopo(p_alvo_id)
              and (not v_depois ? 'unidade_pai_id' or app.na_escopo((v_depois ->> 'unidade_pai_id')::uuid)));
      v_resumo := 'Unidade ' || (v_linha ->> 'sigla');
    when 'servidor_alterar' then
      v_ok := v_geral or (v_chefia and app.na_escopo((v_linha ->> 'unidade_id')::uuid)
              and (not v_depois ? 'unidade_id' or app.na_escopo((v_depois ->> 'unidade_id')::uuid)));
      if v_depois ? 'matricula' and exists (
        select 1 from public.servidores s where upper(s.matricula) = upper(btrim(v_depois ->> 'matricula')) and s.id <> p_alvo_id) then
        perform app.erro('Matrícula já cadastrada para outro servidor.', '23505');
      end if;
      v_resumo := 'Servidor ' || (v_linha ->> 'nome_completo');
    when 'usuario_perfil' then
      v_ok := v_geral and p_alvo_id <> v_uid and ((v_depois ->> 'perfil') <> 'administrador' or v_perfil = 'administrador');
      v_resumo := 'Perfil de ' || app.nome_usuario(p_alvo_id);
    when 'acesso_unidade_conceder', 'acesso_unidade_retirar' then
      v_ok := (v_geral or (v_chefia and app.na_escopo(
                (select s.unidade_id from public.usuarios u join public.servidores s on s.id = u.servidor_id where u.id = p_alvo_id))))
              and p_alvo_id <> v_uid;
      if p_tipo = 'acesso_unidade_conceder' and exists (
        select 1 from public.usuario_unidades_extras e where e.usuario_id = p_alvo_id and e.unidade_id = v_unidade) then
        perform app.erro('Este acesso já está concedido.', '23505');
      end if;
      if p_tipo = 'acesso_unidade_retirar' and not exists (
        select 1 from public.usuario_unidades_extras e where e.usuario_id = p_alvo_id and e.unidade_id = v_unidade) then
        perform app.erro('Este acesso não existe.', 'P0002');
      end if;
      v_resumo := case when p_tipo = 'acesso_unidade_conceder' then 'Acesso extra à ' else 'Retirar acesso à ' end
                  || (select sigla from public.unidades where id = v_unidade) || ' · ' || app.nome_usuario(p_alvo_id);
    when 'cargo_criar' then
      v_ok := v_geral; v_resumo := 'Novo cargo: ' || (v_depois ->> 'nome');
    when 'cargo_alterar' then
      v_ok := v_geral; v_resumo := 'Cargo ' || (v_linha ->> 'nome');
    when 'feriado_alterar', 'feriado_excluir' then
      v_ok := v_geral;
      v_resumo := case when p_tipo = 'feriado_excluir' then 'Excluir feriado ' else 'Feriado ' end
                  || to_char((v_linha ->> 'data')::date, 'DD/MM/YYYY');
  end case;
  if not coalesce(v_ok, false) then perform app.erro('Você não tem permissão para esta solicitação.', '42501'); end if;

  if p_tipo = 'servidor_alterar' then
    -- ex.: "Matrícula de Servidor N" (protótipo Aprovações)
    v_resumo := (select string_agg(app.rotulo_campo(k), ', ') from jsonb_object_keys(v_depois) k);
    v_resumo := upper(left(v_resumo, 1)) || substr(v_resumo, 2) || ' de ' || (v_linha ->> 'nome_completo');
  elsif p_tipo in ('unidade_alterar', 'cargo_alterar', 'feriado_alterar') then
    v_resumo := v_resumo || ' · ' || (select string_agg(app.rotulo_campo(k), ', ') from jsonb_object_keys(v_depois) k);
  end if;

  if p_anexo_path is not null then
    if p_anexo_path not like 'aprovacoes/' || v_uid::text || '/%'
       or not exists (select 1 from storage.objects o where o.bucket_id = 'anexos' and o.name = p_anexo_path) then
      perform app.erro('Anexo inválido.', '22023');
    end if;
  end if;

  insert into public.solicitacoes (tipo, alvo_id, dados_antes, dados_depois, versao_alvo, justificativa, anexo_path, solicitante_id, resumo)
  values (p_tipo, p_alvo_id, v_antes, v_depois, v_versao, btrim(p_justificativa), p_anexo_path, v_uid, v_resumo)
  returning id into v_id;

  for v_aprovador in
    select u.id from public.usuarios u join public.servidores s on s.id = u.servidor_id
     where u.ativo and s.situacao = 'ativo' and u.perfil in ('administrador', 'secretaria') and u.id <> v_uid
  loop
    perform app.notificar(v_aprovador, 'aprovacao_pedido', 'Pedido de aprovação', v_resumo, '/aprovacoes?id=' || v_id);
  end loop;
  return v_id;
end $$;

-- ===== aplicar (interno) =====
create or replace function app.aplicar_solicitacao(s public.solicitacoes)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  case s.tipo
    when 'unidade_criar' then
      insert into public.unidades (sigla, nome, tipo, unidade_pai_id, ordem)
      select r.sigla, r.nome, r.tipo, r.unidade_pai_id, coalesce((s.dados_depois ->> 'ordem')::int, 0)
        from jsonb_populate_record(null::public.unidades, s.dados_depois) r;
    when 'cargo_criar' then
      insert into public.cargos (nome) values (s.dados_depois ->> 'nome');
    when 'feriado_excluir' then
      delete from public.feriados where id = s.alvo_id;
    when 'acesso_unidade_conceder' then
      insert into public.usuario_unidades_extras (usuario_id, unidade_id, solicitacao_id)
      values (s.alvo_id, (s.dados_depois ->> 'unidade_id')::uuid, s.id) on conflict do nothing;
    when 'acesso_unidade_retirar' then
      delete from public.usuario_unidades_extras where usuario_id = s.alvo_id and unidade_id = (s.dados_depois ->> 'unidade_id')::uuid;
    else
      perform app.atualizar_por_json(app.tabela_alvo(s.tipo), s.alvo_id, s.dados_depois);
  end case;
end $$;

-- ===== decidir =====
create or replace function public.decidir_solicitacao(p_id uuid, p_aprovar boolean, p_comentario text default null)
returns public.status_solicitacao language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  s public.solicitacoes;
  v_coment text := nullif(btrim(coalesce(p_comentario, '')), '');
begin
  if not app.gestor_geral() then
    perform app.erro('Somente a Secretária ou o Administrador do sistema podem decidir.', '42501');
  end if;
  select * into s from public.solicitacoes where id = p_id for update;
  if not found then perform app.erro('Pedido não encontrado.', 'P0002'); end if;
  if s.status <> 'pendente' then perform app.erro('Este pedido já foi decidido.', '22023'); end if;
  if s.solicitante_id = v_uid then perform app.erro('Ninguém aprova o próprio pedido.', '42501'); end if;

  if not p_aprovar then
    if v_coment is null then perform app.erro('Informe o comentário para recusar.', '22023'); end if;
    update public.solicitacoes set status = 'recusada', decidido_por = v_uid, decidido_em = now(), comentario_decisao = v_coment where id = p_id;
    perform app.notificar(s.solicitante_id, 'aprovacao_resultado', 'Pedido recusado', s.resumo, '/aprovacoes?id=' || p_id);
    return 'recusada';
  end if;

  if s.versao_alvo is not null and s.versao_alvo is distinct from app.versao_registro(app.tabela_alvo(s.tipo), s.alvo_id) then
    update public.solicitacoes set status = 'bloqueada', decidido_em = now(),
      comentario_decisao = 'O registro mudou depois do pedido. Refaça a solicitação.' where id = p_id;
    perform app.notificar(s.solicitante_id, 'aprovacao_resultado', 'Pedido bloqueado', s.resumo, '/aprovacoes?id=' || p_id);
    return 'bloqueada';
  end if;

  perform set_config('app.solicitacao_id', p_id::text, true);
  begin
    perform app.aplicar_solicitacao(s);
  exception
    when unique_violation then perform app.erro('Não foi possível aplicar: valor já existe (duplicado).', '23505');
    when foreign_key_violation then perform app.erro('Não foi possível aplicar: referência inexistente ou em uso.', '23503');
    when not_null_violation then perform app.erro('Não foi possível aplicar: campo obrigatório vazio.', '23502');
  end;
  update public.solicitacoes set status = 'aprovada', decidido_por = v_uid, decidido_em = now(), comentario_decisao = v_coment where id = p_id;
  perform set_config('app.solicitacao_id', '', true);
  perform app.notificar(s.solicitante_id, 'aprovacao_resultado', 'Pedido aprovado', s.resumo, '/aprovacoes?id=' || p_id);
  return 'aprovada';
end $$;

create or replace function public.cancelar_solicitacao(p_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not app.sessao_ok() then perform app.erro('Acesso não permitido.', '42501'); end if;
  update public.solicitacoes set status = 'cancelada', decidido_em = now()
   where id = p_id and solicitante_id = auth.uid() and status = 'pendente';
  if not found then perform app.erro('Pedido não encontrado ou já decidido.', 'P0002'); end if;
end $$;

-- listagem com nomes (respeita: secretária/admin = tudo; demais = próprios)
create or replace function public.listar_solicitacoes(p_aba text default 'pendentes')
returns table (
  id uuid, tipo public.tipo_solicitacao, resumo text, alvo_id uuid, dados_antes jsonb, dados_depois jsonb,
  justificativa text, anexo_path text, status public.status_solicitacao, criado_em timestamptz,
  solicitante_id uuid, solicitante_nome text, decidido_por_nome text, decidido_em timestamptz, comentario_decisao text
) language plpgsql stable security definer set search_path = ''
as $$
declare v_geral boolean := app.gestor_geral();
begin
  if not app.sessao_ok() then return; end if;
  return query
    select s.id, s.tipo, s.resumo, s.alvo_id, s.dados_antes, s.dados_depois, s.justificativa, s.anexo_path, s.status, s.criado_em,
           s.solicitante_id, app.nome_usuario(s.solicitante_id), app.nome_usuario(s.decidido_por), s.decidido_em, s.comentario_decisao
      from public.solicitacoes s
     where case p_aba
             when 'pendentes' then s.status = 'pendente' and (v_geral or s.solicitante_id = auth.uid())
             when 'meus' then s.solicitante_id = auth.uid()
             when 'historico' then s.status <> 'pendente' and (v_geral or s.solicitante_id = auth.uid())
             else false
           end
     order by s.criado_em desc
     limit 200;
end $$;

grant execute on function public.solicitar(public.tipo_solicitacao, uuid, jsonb, text, text) to authenticated;
grant execute on function public.decidir_solicitacao(uuid, boolean, text) to authenticated;
grant execute on function public.cancelar_solicitacao(uuid) to authenticated;
grant execute on function public.listar_solicitacoes(text) to authenticated;

-- ===================== 20261126000700_funcoes.sql =====================
-- Fase 1 · sessão, ações imediatas, busca, dias úteis, notificações, hook de token, limites

-- ===== sessão do usuário (UI) =====
create or replace function public.minha_sessao()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select case when u.id is null then jsonb_build_object('autorizado', false, 'motivo', 'sem_cadastro')
    when not u.ativo or s.situacao <> 'ativo' then jsonb_build_object('autorizado', false, 'motivo', 'desativado')
    else jsonb_build_object(
      'autorizado', true,
      'usuario_id', u.id,
      'perfil', u.perfil,
      'nome', s.nome_completo,
      'cargo', c.nome,
      'unidade_id', s.unidade_id,
      'unidade_sigla', un.sigla,
      'mfa_exigida', app.exige_mfa(u.perfil),
      'aal', coalesce(auth.jwt() ->> 'aal', 'aal1'),
      'sessao_ok', app.sessao_ok(),
      'modulos', coalesce((select jsonb_agg(m order by m) from app.modulos_do_usuario() m), '[]'::jsonb)
    ) end
  from (select auth.uid() as uid) x
  left join public.usuarios u on u.id = x.uid
  left join public.servidores s on s.id = u.servidor_id
  left join public.cargos c on c.id = s.cargo_id
  left join public.unidades un on un.id = s.unidade_id
$$;

-- ===== módulos extras: na hora, sem aprovação, auditado =====
create or replace function public.conceder_modulo_extra(p_usuario uuid, p_modulo text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if not exists (select 1 from public.usuarios where id = p_usuario) then perform app.erro('Usuário não encontrado.', 'P0002'); end if;
  if not exists (select 1 from public.modulos where codigo = p_modulo) then perform app.erro('Módulo não encontrado.', 'P0002'); end if;
  insert into public.usuario_modulos_extras (usuario_id, modulo_codigo, concedido_por)
  values (p_usuario, p_modulo, auth.uid()) on conflict do nothing;
  perform app.notificar(p_usuario, 'modulo_extra', 'Novo módulo liberado',
    (select nome from public.modulos where codigo = p_modulo), (select rota from public.modulos where codigo = p_modulo));
end $$;

create or replace function public.retirar_modulo_extra(p_usuario uuid, p_modulo text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  delete from public.usuario_modulos_extras where usuario_id = p_usuario and modulo_codigo = p_modulo;
  if not found then perform app.erro('Módulo extra não encontrado.', 'P0002'); end if;
end $$;

-- ===== desativar / reativar usuário: efeito imediato (RLS consulta o banco) =====
create or replace function public.desativar_usuario(p_usuario uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if p_usuario = auth.uid() then perform app.erro('Você não pode desativar o próprio usuário.', '42501'); end if;
  if (select perfil from public.usuarios where id = p_usuario) = 'administrador' and app.perfil_atual() <> 'administrador' then
    perform app.erro('Somente um administrador pode desativar outro administrador.', '42501');
  end if;
  update public.usuarios set ativo = false, desativado_em = now(), desativado_por = auth.uid() where id = p_usuario and ativo;
  if not found then perform app.erro('Usuário não encontrado ou já desativado.', 'P0002'); end if;
end $$;

create or replace function public.reativar_usuario(p_usuario uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  update public.usuarios set ativo = true, desativado_em = null, desativado_por = null where id = p_usuario and not ativo;
  if not found then perform app.erro('Usuário não encontrado ou já ativo.', 'P0002'); end if;
end $$;

-- ===== convite: chamado pela Edge Function com o token de quem convida =====
create or replace function public.pode_convidar()
returns boolean language sql stable security definer set search_path = ''
as $$ select app.gestor_geral() $$;

create or replace function public.registrar_convite(p_auth_id uuid, p_servidor uuid, p_perfil public.perfil_usuario)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_email text;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if p_perfil = 'administrador' and app.perfil_atual() <> 'administrador' then
    perform app.erro('Somente um administrador pode convidar outro administrador.', '42501');
  end if;
  select email_institucional into v_email from public.servidores where id = p_servidor and situacao = 'ativo';
  if v_email is null then perform app.erro('Servidor inexistente, inativo ou sem e-mail institucional.', '22023'); end if;
  if not exists (select 1 from auth.users au where au.id = p_auth_id and lower(au.email) = v_email) then
    perform app.erro('Convite inválido.', '22023');
  end if;
  if exists (select 1 from public.usuarios where servidor_id = p_servidor) then
    perform app.erro('Este servidor já tem usuário.', '23505');
  end if;
  insert into public.usuarios (id, servidor_id, perfil) values (p_auth_id, p_servidor, p_perfil);
end $$;

-- ===== notificações =====
create or replace function public.marcar_notificacoes_lidas(p_ids uuid[] default null)
returns void language sql security definer set search_path = ''
as $$
  update public.notificacoes set lida_em = now()
   where app.sessao_ok() and usuario_id = auth.uid() and lida_em is null and (p_ids is null or id = any (p_ids))
$$;

-- ===== dias úteis (6.13) =====
create or replace function public.eh_dia_util(d date)
returns boolean language sql stable security definer set search_path = ''
as $$ select extract(isodow from d) < 6 and not exists (select 1 from public.feriados f where f.data = d) $$;

-- dias úteis em (inicio, fim]; negativo se fim < inicio
create or replace function public.dias_uteis_entre(inicio date, fim date)
returns integer language sql stable security definer set search_path = ''
as $$
  select case when fim >= inicio
    then (select count(*)::int from generate_series(inicio + 1, fim, interval '1 day') g where public.eh_dia_util(g::date))
    else -(select count(*)::int from generate_series(fim + 1, inicio, interval '1 day') g where public.eh_dia_util(g::date))
  end
$$;

create or replace function public.somar_dias_uteis(inicio date, n integer)
returns date language plpgsql stable security definer set search_path = ''
as $$
declare d date := inicio; restante integer := abs(n); passo integer := case when n < 0 then -1 else 1 end;
begin
  if abs(n) > 3660 then perform app.erro('Prazo inválido.', '22023'); end if;
  while restante > 0 loop
    d := d + passo;
    if public.eh_dia_util(d) then restante := restante - 1; end if;
  end loop;
  return d;
end $$;

-- ===== busca geral (6.19): SECURITY INVOKER → RLS de cada tabela vale =====
create or replace function public.busca_geral(termo text, limite integer default 8)
returns table (tipo text, id uuid, titulo text, subtitulo text, rota text)
language plpgsql stable security invoker set search_path = ''
as $$
declare q text := app.normalizar(btrim(coalesce(termo, '')));
        lim integer := least(greatest(coalesce(limite, 8), 1), 20);
begin
  if length(q) < 2 or length(q) > 100 then return; end if;
  q := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return query
    (select 'unidade'::text, u.id, u.sigla, u.nome, '/usuarios?unidade=' || u.id
       from public.unidades u
      where app.normalizar(u.sigla) like q or app.normalizar(u.nome) like q
      order by u.sigla limit lim)
    union all
    (select 'servidor'::text, s.id, s.nome_completo, 'Matrícula ' || s.matricula, '/usuarios?servidor=' || s.id
       from public.servidores s
      where app.normalizar(s.nome_completo) like q or app.normalizar(s.matricula) like q
      order by s.nome_completo limit lim);
end $$;

-- ===== auditoria de eventos (login etc.) pela UI não é confiável: só hook/servidor =====

-- ===== hook de token do Supabase Auth: bloqueia inativo, audita login =====
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_uid uuid := (event ->> 'user_id')::uuid;
  v_perfil public.perfil_usuario;
  v_metodo text := coalesce(event ->> 'authentication_method', '');
begin
  select u.perfil into v_perfil
    from public.usuarios u join public.servidores s on s.id = u.servidor_id
   where u.id = v_uid and u.ativo and s.situacao = 'ativo';
  if v_perfil is null then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'Acesso não permitido.'));
  end if;
  if v_metodo <> 'token_refresh' then
    perform app.registrar_evento('login', 'auth', v_uid::text, null,
      jsonb_build_object('metodo', v_metodo, 'aal', event -> 'claims' ->> 'aal'), v_uid);
  end if;
  return jsonb_set(event, '{claims,app_perfil}', to_jsonb(v_perfil::text));
end $$;

-- ===== limite de requisições (Edge Functions, service-role) =====
create or replace function public.consumir_limite(p_chave text, p_maximo integer, p_janela_segundos integer)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v public.limites_requisicao;
begin
  insert into public.limites_requisicao as l (chave, janela_inicio, contador) values (p_chave, now(), 1)
  on conflict (chave) do update set
    contador = case when l.janela_inicio < now() - make_interval(secs => p_janela_segundos) then 1 else l.contador + 1 end,
    janela_inicio = case when l.janela_inicio < now() - make_interval(secs => p_janela_segundos) then now() else l.janela_inicio end
  returning * into v;
  return v.contador <= p_maximo;
end $$;

-- ===== grants =====
grant execute on function public.minha_sessao() to authenticated;
grant execute on function public.conceder_modulo_extra(uuid, text) to authenticated;
grant execute on function public.retirar_modulo_extra(uuid, text) to authenticated;
grant execute on function public.desativar_usuario(uuid) to authenticated;
grant execute on function public.reativar_usuario(uuid) to authenticated;
grant execute on function public.pode_convidar() to authenticated;
grant execute on function public.registrar_convite(uuid, uuid, public.perfil_usuario) to authenticated;
grant execute on function public.marcar_notificacoes_lidas(uuid[]) to authenticated;
grant execute on function public.eh_dia_util(date) to authenticated;
grant execute on function public.dias_uteis_entre(date, date) to authenticated;
grant execute on function public.somar_dias_uteis(date, integer) to authenticated;
grant execute on function public.busca_geral(text, integer) to authenticated;

revoke execute on function public.custom_access_token_hook(jsonb) from public, anon, authenticated;
grant usage on schema public to supabase_auth_admin;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;

revoke execute on function public.consumir_limite(text, integer, integer) from public, anon, authenticated;
grant execute on function public.consumir_limite(text, integer, integer) to service_role;

-- funções app usadas por políticas/busca (invoker)
grant execute on function app.normalizar(text) to authenticated;

-- unidades sob gestão (UI: árvore de Unidades e usuários)
create or replace function public.minhas_unidades_escopo()
returns setof uuid language sql stable security definer set search_path = ''
as $$ select app.unidades_escopo() $$;
grant execute on function public.minhas_unidades_escopo() to authenticated;

-- ===================== 20261126000800_modulos_storage.sql =====================
-- Fase 1 · módulos, pacote padrão PROVISÓRIO, configurações, storage privado

insert into public.modulos (codigo, nome, rota, icone, ordem, status, fase, no_menu) values
  ('painel', 'Painel', '/', 'painel', 10, 'ativo', 1, true),
  ('demandas', 'Demandas', '/demandas', 'demandas', 20, 'em_breve', 3, true),
  ('calendario', 'Calendário', '/calendario', 'calendario', 30, 'ativo', 1, true),
  ('contratos', 'Contratos de locação', '/contratos', 'contratos', 40, 'em_breve', 4, true),
  ('unidades_consumidoras', 'Unidades consumidoras', '/unidades-consumidoras', 'energia', 50, 'em_breve', 4, true),
  ('ferias', 'Férias e folgas', '/ferias', 'ferias', 60, 'em_breve', 2, true),
  ('folhas_ponto', 'Folhas de ponto', '/folhas-ponto', 'relogio', 70, 'em_breve', 2, true),
  ('produtividade', 'Produtividade', '/produtividade', 'grafico', 80, 'em_definicao', 5, true),
  ('aprovacoes', 'Aprovações', '/aprovacoes', 'aprovacoes', 90, 'ativo', 1, true),
  ('relatorios', 'Relatórios', '/relatorios', 'relatorios', 100, 'ativo', 1, true),
  ('usuarios', 'Unidades e usuários', '/usuarios', 'usuarios', 110, 'ativo', 1, true),
  ('obrigacoes_fiscais', 'Obrigações fiscais', '/obrigacoes-fiscais', 'recibo', 120, 'em_breve', 9, true),
  ('auditoria', 'Auditoria', '/relatorios', 'relatorios', 130, 'ativo', 1, false);

-- PROVISÓRIO (rascunho da seção 4 + menu dos protótipos). Aguardando definição oficial.
insert into public.pacotes_padrao (perfil, modulo_codigo, provisorio)
select p::public.perfil_usuario, m.codigo, true
  from unnest(array['administrador', 'secretaria']) p cross join public.modulos m;
insert into public.pacotes_padrao (perfil, modulo_codigo, provisorio)
select p::public.perfil_usuario, m, true
  from unnest(array['diretor', 'coordenador']) p
 cross join unnest(array['painel', 'demandas', 'calendario', 'ferias', 'folhas_ponto', 'produtividade', 'aprovacoes', 'relatorios', 'usuarios']) m;
insert into public.pacotes_padrao (perfil, modulo_codigo, provisorio)
select 'funcionario', m, true from unnest(array['painel', 'demandas', 'calendario', 'ferias', 'produtividade']) m;

insert into public.configuracoes (chave, valor, descricao) values
  ('auth.mfa_recomendada_diretor', 'true', 'Exibir recomendação de MFA para diretores'),
  ('anexos.tamanho_max_mb', '10', 'Tamanho máximo de anexos (MB)'),
  ('anexos.url_validade_s', '60', 'Validade dos links temporários de arquivos (segundos)');

-- storage privado
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('anexos', 'anexos', false, 10485760, array['application/pdf', 'image/png', 'image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- envio: só na própria pasta aprovacoes/<uid>/<uuid>.<ext>
create policy anexos_aprovacao_enviar on storage.objects for insert to authenticated with check (
  bucket_id = 'anexos'
  and (select app.sessao_ok())
  and (storage.foldername(name))[1] = 'aprovacoes'
  and (storage.foldername(name))[2] = (select app.uid())::text
  and name ~ '^aprovacoes/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|png|jpg)$'
);
-- leitura: segue a permissão da solicitação
create policy anexos_aprovacao_ler on storage.objects for select to authenticated using (
  bucket_id = 'anexos'
  and (select app.sessao_ok())
  and (
    ((storage.foldername(name))[1] = 'aprovacoes' and (storage.foldername(name))[2] = (select app.uid())::text)
    or exists (select 1 from public.solicitacoes s where s.anexo_path = name)  -- RLS de solicitacoes aplica
  )
);
-- sem UPDATE/DELETE: anexos nunca são apagados

-- ===================== 20261126000900_mfa_configuravel.sql =====================
-- MFA obrigatória vira configuração (padrão: ligada, como no prompt 5).
-- Desligar só em ambiente de testes, com dados fictícios. Mudança fica na auditoria.
insert into public.configuracoes (chave, valor, descricao) values
  ('auth.mfa_obrigatoria', 'true', 'Exigir verificação em duas etapas de administrador e secretária (manter true em produção)')
on conflict (chave) do nothing;

create or replace function app.exige_mfa(p public.perfil_usuario)
returns boolean language sql stable security definer set search_path = ''
as $$
  select p in ('administrador', 'secretaria')
     and coalesce((select (c.valor)::boolean from public.configuracoes c where c.chave = 'auth.mfa_obrigatoria'), true)
$$;

-- ===================== 20261127000100_fase2_servidores_saldos.sql =====================
-- Fase 2 · saldos do RH e importação de servidores/saldos por planilha (6.7)
-- Saldos são dados pessoais: só o próprio, a chefia (escopo), secretária e admin.

create table public.saldos_servidor (
  servidor_id uuid primary key references public.servidores (id) on delete cascade,
  ferias_dias numeric(6,1) not null default 0 check (ferias_dias between 0 and 9999),
  licenca_premio_dias numeric(6,1) not null default 0 check (licenca_premio_dias between 0 and 9999),
  folgas numeric(6,1) not null default 0 check (folgas between 0 and 9999),
  fonte text not null default 'RH',
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid references public.usuarios (id)
);
alter table public.saldos_servidor enable row level security;
revoke all on public.saldos_servidor from anon, authenticated;
grant select on public.saldos_servidor to authenticated;
create policy saldos_ler on public.saldos_servidor for select to authenticated using (
  (select app.sessao_ok()) and (
    servidor_id = (select app.servidor_atual())
    or ((select app.tem_modulo('ferias'))
        and exists (select 1 from public.servidores s where s.id = servidor_id and s.unidade_id in (select app.unidades_escopo())))
  )
);
create trigger saldos_servidor_auditoria after insert or update or delete on public.saldos_servidor
  for each row execute function app.auditar_linha();

-- id pela chave de saldo (auditoria usa "id"; aqui é servidor_id)
create or replace function app.auditar_linha()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_old jsonb; v_new jsonb; v_id text;
begin
  if tg_op in ('UPDATE', 'DELETE') then v_old := to_jsonb(old); end if;
  if tg_op in ('INSERT', 'UPDATE') then v_new := to_jsonb(new); end if;
  if tg_op = 'UPDATE' and v_old = v_new then return null; end if;
  v_id := coalesce(v_new ->> 'id', v_old ->> 'id',
                   concat_ws(':', coalesce(v_new, v_old) ->> 'usuario_id', coalesce(v_new, v_old) ->> 'servidor_id',
                             coalesce(v_new, v_old) ->> 'modulo_codigo', coalesce(v_new, v_old) ->> 'unidade_id',
                             coalesce(v_new, v_old) ->> 'perfil', coalesce(v_new, v_old) ->> 'chave'));
  perform app.registrar_evento(lower(tg_op), tg_table_name, v_id, v_old, v_new);
  return null;
end $$;

-- ===== validação comum de linhas de planilha =====
-- Entrada: jsonb array de objetos {linha, nome, matricula, cargo, unidade, email, ferias, licenca_premio, folgas}
-- Saída: uma linha por erro (linha, campo, mensagem). Sem erros = pode importar.
create or replace function app.validar_planilha_servidores(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
declare r jsonb; n integer; v_mat text; v_email text; v_num text;
begin
  if jsonb_typeof(p_linhas) <> 'array' then perform app.erro('Planilha inválida.', '22023'); end if;
  if jsonb_array_length(p_linhas) = 0 then perform app.erro('Planilha sem linhas.', '22023'); end if;
  if jsonb_array_length(p_linhas) > 2000 then perform app.erro('Máximo de 2000 linhas por importação.', '22023'); end if;
  for r in select * from jsonb_array_elements(p_linhas) loop
    n := coalesce((r ->> 'linha')::int, 0);
    v_mat := btrim(coalesce(r ->> 'matricula', ''));
    v_email := nullif(lower(btrim(coalesce(r ->> 'email', ''))), '');
    if btrim(coalesce(r ->> 'nome', '')) = '' then return query select n, 'nome', 'Nome vazio.'; end if;
    if length(btrim(coalesce(r ->> 'nome', ''))) > 200 then return query select n, 'nome', 'Nome com mais de 200 caracteres.'; end if;
    if v_mat = '' then return query select n, 'matricula', 'Matrícula vazia.';
    elsif v_mat !~ '^[0-9A-Za-z./-]{1,20}$' then return query select n, 'matricula', 'Matrícula com formato inválido.';
    elsif exists (select 1 from public.servidores s where upper(s.matricula) = upper(v_mat)) then
      return query select n, 'matricula', 'Matrícula já cadastrada.';
    elsif (select count(*) from jsonb_array_elements(p_linhas) x where upper(btrim(x ->> 'matricula')) = upper(v_mat)) > 1 then
      return query select n, 'matricula', 'Matrícula duplicada na planilha.';
    end if;
    if not exists (select 1 from public.cargos c where c.ativo and app.normalizar(c.nome) = app.normalizar(r ->> 'cargo')) then
      return query select n, 'cargo', 'Cargo inexistente.';
    end if;
    if not exists (select 1 from public.unidades u where u.ativa and app.normalizar(u.sigla) = app.normalizar(r ->> 'unidade')) then
      return query select n, 'unidade', 'Unidade inexistente.';
    end if;
    if v_email is not null then
      if v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return query select n, 'email', 'E-mail inválido.';
      elsif exists (select 1 from public.servidores s where s.email_institucional = v_email) then
        return query select n, 'email', 'E-mail já cadastrado.';
      elsif (select count(*) from jsonb_array_elements(p_linhas) x where lower(btrim(x ->> 'email')) = v_email) > 1 then
        return query select n, 'email', 'E-mail duplicado na planilha.';
      end if;
    end if;
    foreach v_num in array array['ferias', 'licenca_premio', 'folgas'] loop
      if nullif(btrim(coalesce(r ->> v_num, '')), '') is not null
         and replace(btrim(r ->> v_num), ',', '.') !~ '^[0-9]{1,4}(\.[0-9])?$' then
        return query select n, v_num, 'Saldo inválido (use número, ex.: 30 ou 12,5).';
      end if;
    end loop;
  end loop;
end $$;

create or replace function app.numero_planilha(v text)
returns numeric language sql immutable set search_path = ''
as $$ select coalesce(nullif(replace(btrim(coalesce(v, '')), ',', '.'), '')::numeric, 0) $$;

create or replace function public.importar_servidores_previa(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  return query select * from app.validar_planilha_servidores(p_linhas) order by 1, 2;
end $$;

-- grava só se não houver nenhum erro (tudo ou nada)
create or replace function public.importar_servidores(p_linhas jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare r jsonb; v_id uuid; n integer := 0;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if exists (select 1 from app.validar_planilha_servidores(p_linhas)) then
    perform app.erro('A planilha tem erros. Corrija e confira a prévia antes de importar.', '22023');
  end if;
  perform set_config('app.origem', 'importacao_servidores', true);
  for r in select * from jsonb_array_elements(p_linhas) loop
    insert into public.servidores (nome_completo, matricula, cargo_id, unidade_id, email_institucional)
    values (
      r ->> 'nome', r ->> 'matricula',
      (select c.id from public.cargos c where c.ativo and app.normalizar(c.nome) = app.normalizar(r ->> 'cargo')),
      (select u.id from public.unidades u where u.ativa and app.normalizar(u.sigla) = app.normalizar(r ->> 'unidade')),
      nullif(btrim(coalesce(r ->> 'email', '')), '')
    ) returning id into v_id;
    insert into public.saldos_servidor (servidor_id, ferias_dias, licenca_premio_dias, folgas, fonte, atualizado_por)
    values (v_id, app.numero_planilha(r ->> 'ferias'), app.numero_planilha(r ->> 'licenca_premio'),
            app.numero_planilha(r ->> 'folgas'), 'Planilha de servidores', auth.uid());
    n := n + 1;
  end loop;
  return n;
end $$;

-- ===== saldos do RH (matrícula + 3 saldos); atualiza servidores existentes =====
create or replace function public.importar_saldos_previa(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
declare r jsonb; n integer; v_num text; v_mat text;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then perform app.erro('Planilha sem linhas.', '22023'); end if;
  if jsonb_array_length(p_linhas) > 2000 then perform app.erro('Máximo de 2000 linhas por importação.', '22023'); end if;
  for r in select * from jsonb_array_elements(p_linhas) loop
    n := coalesce((r ->> 'linha')::int, 0);
    v_mat := btrim(coalesce(r ->> 'matricula', ''));
    if v_mat = '' then return query select n, 'matricula'::text, 'Matrícula vazia.'::text;
    elsif not exists (select 1 from public.servidores s where upper(s.matricula) = upper(v_mat)) then
      return query select n, 'matricula'::text, 'Matrícula não encontrada no cadastro.'::text;
    elsif (select count(*) from jsonb_array_elements(p_linhas) x where upper(btrim(x ->> 'matricula')) = upper(v_mat)) > 1 then
      return query select n, 'matricula'::text, 'Matrícula duplicada na planilha.'::text;
    end if;
    foreach v_num in array array['ferias', 'licenca_premio', 'folgas'] loop
      if replace(btrim(coalesce(r ->> v_num, '')), ',', '.') !~ '^[0-9]{1,4}(\.[0-9])?$' then
        return query select n, v_num, 'Saldo vazio ou inválido.'::text;
      end if;
    end loop;
  end loop;
end $$;

create or replace function public.importar_saldos(p_linhas jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare r jsonb; n integer := 0;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if exists (select 1 from public.importar_saldos_previa(p_linhas)) then
    perform app.erro('A planilha tem erros. Corrija e confira a prévia antes de importar.', '22023');
  end if;
  perform set_config('app.origem', 'importacao_saldos', true);
  for r in select * from jsonb_array_elements(p_linhas) loop
    insert into public.saldos_servidor as s (servidor_id, ferias_dias, licenca_premio_dias, folgas, fonte, atualizado_em, atualizado_por)
    select sv.id, app.numero_planilha(r ->> 'ferias'), app.numero_planilha(r ->> 'licenca_premio'), app.numero_planilha(r ->> 'folgas'),
           'Levantamento do RH', now(), auth.uid()
      from public.servidores sv where upper(sv.matricula) = upper(btrim(r ->> 'matricula'))
    on conflict (servidor_id) do update set ferias_dias = excluded.ferias_dias, licenca_premio_dias = excluded.licenca_premio_dias,
      folgas = excluded.folgas, fonte = excluded.fonte, atualizado_em = excluded.atualizado_em, atualizado_por = excluded.atualizado_por;
    n := n + 1;
  end loop;
  return n;
end $$;

grant execute on function public.importar_servidores_previa(jsonb) to authenticated;
grant execute on function public.importar_servidores(jsonb) to authenticated;
grant execute on function public.importar_saldos_previa(jsonb) to authenticated;
grant execute on function public.importar_saldos(jsonb) to authenticated;
revoke execute on function public.importar_servidores_previa(jsonb) from anon;
revoke execute on function public.importar_servidores(jsonb) from anon;
revoke execute on function public.importar_saldos_previa(jsonb) from anon;
revoke execute on function public.importar_saldos(jsonb) from anon;

-- origem da operação na auditoria (importação etc.)
create or replace function app.contexto_auditoria()
returns jsonb language sql stable set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'papel', auth.jwt() ->> 'role',
    'aal', auth.jwt() ->> 'aal',
    'solicitacao_id', nullif(current_setting('app.solicitacao_id', true), ''),
    'origem', nullif(current_setting('app.origem', true), '')
  ))
$$;

-- ===================== 20261127000200_fase2_afastamentos.sql =====================
-- Fase 2 · férias, licença-prêmio e folgas (6.7) + substituto (6.14)

create type public.tipo_afastamento as enum ('ferias', 'licenca_premio', 'folga');
create type public.status_afastamento as enum ('solicitado', 'aprovado', 'recusado', 'cancelado');

create table public.afastamentos (
  id uuid primary key default gen_random_uuid(),
  servidor_id uuid not null references public.servidores (id) on delete restrict,
  tipo public.tipo_afastamento not null,
  inicio date not null,
  fim date not null,
  status public.status_afastamento not null default 'solicitado',
  observacao text check (observacao is null or length(observacao) <= 1000),
  substituto_id uuid references public.servidores (id),
  conflito_mesmo_cargo boolean not null default false,
  solicitado_por uuid not null references public.usuarios (id),
  decidido_por uuid references public.usuarios (id),
  decidido_em timestamptz,
  comentario_decisao text check (comentario_decisao is null or length(comentario_decisao) <= 1000),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint afastamentos_periodo check (fim >= inicio and fim - inicio <= 366),
  constraint afastamentos_substituto_aprovado check (status <> 'aprovado' or substituto_id is not null),
  constraint afastamentos_substituto_outro check (substituto_id is null or substituto_id <> servidor_id),
  constraint afastamentos_recusa_comentada check (status <> 'recusado' or length(btrim(coalesce(comentario_decisao, ''))) > 0)
);
create index afastamentos_servidor_idx on public.afastamentos (servidor_id, inicio);
create index afastamentos_periodo_idx on public.afastamentos (inicio, fim) where status in ('solicitado', 'aprovado');
create trigger afastamentos_atualizado before update on public.afastamentos
  for each row execute function app.tocar_atualizado_em();
create trigger afastamentos_auditoria after insert or update or delete on public.afastamentos
  for each row execute function app.auditar_linha();

-- mesmo servidor não pode ter dois afastamentos ativos sobrepostos
create or replace function app.afastamentos_validar()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.status in ('solicitado', 'aprovado') and exists (
    select 1 from public.afastamentos a
     where a.servidor_id = new.servidor_id and a.id <> new.id and a.status in ('solicitado', 'aprovado')
       and daterange(a.inicio, a.fim, '[]') && daterange(new.inicio, new.fim, '[]')) then
    perform app.erro('Já existe férias, licença ou folga deste servidor nesse período.', '23P01');
  end if;
  -- aviso (não bloqueia): mesmo cargo e unidade com afastamento sobreposto
  new.conflito_mesmo_cargo := exists (
    select 1 from public.servidores t
      join public.servidores s on s.unidade_id = t.unidade_id and s.cargo_id = t.cargo_id and s.id <> t.id
      join public.afastamentos a on a.servidor_id = s.id and a.status in ('solicitado', 'aprovado') and a.id <> new.id
     where t.id = new.servidor_id and daterange(a.inicio, a.fim, '[]') && daterange(new.inicio, new.fim, '[]'));
  if new.substituto_id is not null then
    if not exists (select 1 from public.servidores s join public.servidores t on t.id = new.servidor_id
                    where s.id = new.substituto_id and s.unidade_id = t.unidade_id and s.situacao = 'ativo') then
      perform app.erro('O substituto deve ser um servidor ativo da mesma unidade.', '23514');
    end if;
    if new.status = 'aprovado' and exists (
      select 1 from public.afastamentos a
       where a.servidor_id = new.substituto_id and a.status = 'aprovado'
         and daterange(a.inicio, a.fim, '[]') && daterange(new.inicio, new.fim, '[]')) then
      perform app.erro('O substituto também estará afastado nesse período.', '23514');
    end if;
  end if;
  return new;
end $$;
create trigger afastamentos_validar before insert or update on public.afastamentos
  for each row execute function app.afastamentos_validar();

alter table public.afastamentos enable row level security;
revoke all on public.afastamentos from anon, authenticated;
grant select on public.afastamentos to authenticated;
-- próprio servidor; quem é substituto; chefia no escopo com módulo de férias; secretária/admin
create policy afastamentos_ler on public.afastamentos for select to authenticated using (
  (select app.sessao_ok()) and (
    servidor_id = (select app.servidor_atual())
    or substituto_id = (select app.servidor_atual())
    or ((select app.tem_modulo('ferias'))
        and exists (select 1 from public.servidores s where s.id = servidor_id and s.unidade_id in (select app.unidades_escopo())))
  )
);

-- chefia do servidor: perfil diretor/coordenador com a unidade no escopo e módulo de férias
create or replace function app.eh_chefia_de(p_servidor uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select app.gestor_geral()
      or (app.perfil_atual() in ('diretor', 'coordenador') and app.tem_modulo('ferias')
          and app.na_escopo((select unidade_id from public.servidores where id = p_servidor)))
$$;

-- usuários que chefiam a unidade (para notificar): coordenador da unidade e diretor acima dela
create or replace function app.chefes_da_unidade(p_unidade uuid)
returns setof uuid language sql stable security definer set search_path = ''
as $$
  select u.id from public.usuarios u join public.servidores s on s.id = u.servidor_id
   where u.ativo and s.situacao = 'ativo' and (
     (u.perfil = 'coordenador' and s.unidade_id = p_unidade)
     or (u.perfil = 'diretor' and p_unidade in (select app.subarvore(s.unidade_id)))
   )
$$;

create or replace function app.rotulo_afastamento(t public.tipo_afastamento)
returns text language sql immutable set search_path = ''
as $$ select case t when 'ferias' then 'Férias' when 'licenca_premio' then 'Licença-prêmio' else 'Folga' end $$;

-- outros servidores da mesma unidade e cargo com férias/afastamento no período (aviso, decisão é da chefia)
create or replace function public.conflitos_mesmo_cargo(p_servidor uuid, p_inicio date, p_fim date, p_ignorar uuid default null)
returns table (afastamento_id uuid, servidor_id uuid, nome text, tipo public.tipo_afastamento, inicio date, fim date, status public.status_afastamento)
language sql stable security definer set search_path = ''
as $$
  select a.id, s.id, s.nome_completo, a.tipo, a.inicio, a.fim, a.status
    from public.servidores t
    join public.servidores s on s.unidade_id = t.unidade_id and s.cargo_id = t.cargo_id and s.id <> t.id
    join public.afastamentos a on a.servidor_id = s.id and a.status in ('solicitado', 'aprovado')
   where t.id = p_servidor and app.eh_chefia_de(p_servidor)
     and (p_ignorar is null or a.id <> p_ignorar)
     and daterange(a.inicio, a.fim, '[]') && daterange(p_inicio, p_fim, '[]')
   order by a.inicio
$$;

create or replace function public.solicitar_afastamento(p_servidor uuid, p_tipo public.tipo_afastamento, p_inicio date, p_fim date, p_observacao text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_nome text; v_unidade uuid; v_conflito boolean; v_chefe uuid;
begin
  if not app.sessao_ok() then perform app.erro('Acesso não permitido.', '42501'); end if;
  if p_servidor is distinct from app.servidor_atual() and not app.eh_chefia_de(p_servidor) then
    perform app.erro('Você só pode pedir afastamento para você ou para servidores que chefia.', '42501');
  end if;
  if p_inicio is null or p_fim is null or p_fim < p_inicio then perform app.erro('Período inválido.', '22023'); end if;
  if p_inicio < current_date - 30 then perform app.erro('Período muito antigo.', '22023'); end if;
  select nome_completo, unidade_id into v_nome, v_unidade from public.servidores where id = p_servidor and situacao = 'ativo';
  if v_nome is null then perform app.erro('Servidor inexistente ou inativo.', 'P0002'); end if;
  insert into public.afastamentos (servidor_id, tipo, inicio, fim, observacao, solicitado_por)
  values (p_servidor, p_tipo, p_inicio, p_fim, nullif(btrim(coalesce(p_observacao, '')), ''), auth.uid())
  returning id, conflito_mesmo_cargo into v_id, v_conflito;
  for v_chefe in select app.chefes_da_unidade(v_unidade) loop
    if v_chefe <> auth.uid() then
      perform app.notificar(v_chefe, 'afastamento_pedido', app.rotulo_afastamento(p_tipo) || ' para aprovar',
        v_nome || ' · ' || to_char(p_inicio, 'DD/MM') || ' a ' || to_char(p_fim, 'DD/MM/YYYY')
        || case when v_conflito then ' · mesmo cargo no período' else '' end, '/ferias?pedido=' || v_id);
    end if;
  end loop;
  return v_id;
end $$;

-- aprovar exige substituto da mesma unidade; aviso de mesmo cargo não bloqueia (decisão da chefia)
create or replace function public.decidir_afastamento(p_id uuid, p_aprovar boolean, p_substituto uuid default null, p_comentario text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.afastamentos; v_nome text; v_unidade uuid; v_sub_usuario uuid; v_coment text := nullif(btrim(coalesce(p_comentario, '')), ''); v_chefe uuid;
begin
  if not app.sessao_ok() then perform app.erro('Acesso não permitido.', '42501'); end if;
  select * into a from public.afastamentos where id = p_id for update;
  if not found then perform app.erro('Pedido não encontrado.', 'P0002'); end if;
  if not app.eh_chefia_de(a.servidor_id) then perform app.erro('Somente a chefia do servidor pode decidir.', '42501'); end if;
  if a.servidor_id = app.servidor_atual() then perform app.erro('Ninguém aprova o próprio afastamento.', '42501'); end if;
  if a.status <> 'solicitado' then perform app.erro('Este pedido já foi decidido.', '22023'); end if;
  select nome_completo, unidade_id into v_nome, v_unidade from public.servidores where id = a.servidor_id;

  if not p_aprovar then
    if v_coment is null then perform app.erro('Informe o comentário para recusar.', '22023'); end if;
    update public.afastamentos set status = 'recusado', decidido_por = auth.uid(), decidido_em = now(), comentario_decisao = v_coment where id = p_id;
  else
    if p_substituto is null then perform app.erro('Indique o substituto (obrigatório).', '22023'); end if;
    update public.afastamentos set status = 'aprovado', substituto_id = p_substituto, decidido_por = auth.uid(), decidido_em = now(),
      comentario_decisao = v_coment where id = p_id;
    select u.id into v_sub_usuario from public.usuarios u where u.servidor_id = p_substituto and u.ativo;
    if v_sub_usuario is not null then
      perform app.notificar(v_sub_usuario, 'substituto', 'Você será substituto',
        v_nome || ' · ' || app.rotulo_afastamento(a.tipo) || ' ' || to_char(a.inicio, 'DD/MM') || ' a ' || to_char(a.fim, 'DD/MM/YYYY'), '/ferias');
    end if;
    for v_chefe in select app.chefes_da_unidade(v_unidade) loop
      if v_chefe <> auth.uid() then
        perform app.notificar(v_chefe, 'afastamento_aprovado', app.rotulo_afastamento(a.tipo) || ' aprovada(s)',
          v_nome || ' · substituto: ' || (select nome_completo from public.servidores where id = p_substituto), '/ferias');
      end if;
    end loop;
  end if;
  perform app.notificar(a.solicitado_por, 'afastamento_resultado',
    app.rotulo_afastamento(a.tipo) || case when p_aprovar then ' aprovada(s)' else ' recusada(s)' end,
    v_nome || ' · ' || to_char(a.inicio, 'DD/MM') || ' a ' || to_char(a.fim, 'DD/MM/YYYY'), '/ferias');
end $$;

-- escala editável pela chefia: remarcar período ou cancelar (auditado); solicitante cancela o próprio pedido pendente
create or replace function public.remarcar_afastamento(p_id uuid, p_inicio date, p_fim date, p_substituto uuid default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.afastamentos;
begin
  if not app.sessao_ok() then perform app.erro('Acesso não permitido.', '42501'); end if;
  select * into a from public.afastamentos where id = p_id for update;
  if not found then perform app.erro('Registro não encontrado.', 'P0002'); end if;
  if not app.eh_chefia_de(a.servidor_id) or a.servidor_id = app.servidor_atual() then
    perform app.erro('Somente a chefia do servidor pode remarcar.', '42501');
  end if;
  if a.status not in ('solicitado', 'aprovado') then perform app.erro('Só é possível remarcar pedidos ativos.', '22023'); end if;
  if p_inicio is null or p_fim is null or p_fim < p_inicio then perform app.erro('Período inválido.', '22023'); end if;
  update public.afastamentos set inicio = p_inicio, fim = p_fim, substituto_id = coalesce(p_substituto, substituto_id) where id = p_id;
end $$;

create or replace function public.cancelar_afastamento(p_id uuid, p_motivo text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.afastamentos;
begin
  if not app.sessao_ok() then perform app.erro('Acesso não permitido.', '42501'); end if;
  select * into a from public.afastamentos where id = p_id for update;
  if not found then perform app.erro('Registro não encontrado.', 'P0002'); end if;
  if not ((a.solicitado_por = auth.uid() and a.status = 'solicitado')
          or (app.eh_chefia_de(a.servidor_id) and a.servidor_id is distinct from app.servidor_atual())) then
    perform app.erro('Você não pode cancelar este registro.', '42501');
  end if;
  if a.status not in ('solicitado', 'aprovado') then perform app.erro('Registro já encerrado.', '22023'); end if;
  update public.afastamentos set status = 'cancelado', comentario_decisao = nullif(btrim(coalesce(p_motivo, '')), '') where id = p_id;
end $$;

-- ausências do mês (painel). Mesma regra de visibilidade de afastamentos_ler,
-- aplicada explicitamente (o substituto precisa ver o nome de quem substitui).
create or replace function public.ausencias_do_mes(p_mes date default current_date)
returns table (afastamento_id uuid, servidor text, unidade text, tipo public.tipo_afastamento, inicio date, fim date, substituto text)
language sql stable security definer set search_path = ''
as $$
  select a.id, s.nome_completo, u.sigla, a.tipo, a.inicio, a.fim,
         (select sb.nome_completo from public.servidores sb where sb.id = a.substituto_id)
    from public.afastamentos a
    join public.servidores s on s.id = a.servidor_id
    join public.unidades u on u.id = s.unidade_id
   where a.status = 'aprovado' and app.sessao_ok()
     and (a.servidor_id = app.servidor_atual() or a.substituto_id = app.servidor_atual()
          or (app.tem_modulo('ferias') and app.na_escopo(s.unidade_id)))
     and daterange(a.inicio, a.fim, '[]') && daterange(date_trunc('month', p_mes)::date, (date_trunc('month', p_mes) + interval '1 month - 1 day')::date, '[]')
   order by a.inicio
$$;

grant execute on function public.conflitos_mesmo_cargo(uuid, date, date, uuid) to authenticated;
grant execute on function public.solicitar_afastamento(uuid, public.tipo_afastamento, date, date, text) to authenticated;
grant execute on function public.decidir_afastamento(uuid, boolean, uuid, text) to authenticated;
grant execute on function public.remarcar_afastamento(uuid, date, date, uuid) to authenticated;
grant execute on function public.cancelar_afastamento(uuid, text) to authenticated;
grant execute on function public.ausencias_do_mes(date) to authenticated;
revoke execute on function public.conflitos_mesmo_cargo(uuid, date, date, uuid) from anon;
revoke execute on function public.solicitar_afastamento(uuid, public.tipo_afastamento, date, date, text) from anon;
revoke execute on function public.decidir_afastamento(uuid, boolean, uuid, text) from anon;
revoke execute on function public.remarcar_afastamento(uuid, date, date, uuid) from anon;
revoke execute on function public.cancelar_afastamento(uuid, text) from anon;
revoke execute on function public.ausencias_do_mes(date) from anon;

-- ===================== 20261127000300_fase2_folhas_ponto.sql =====================
-- Fase 2 · folhas de ponto (6.8) e controle de entrega (6.18)
-- O PDF do RH é lido no navegador de quem envia (secretária/admin); o cruzamento
-- matrícula → servidor → unidade é feito AQUI no banco (fonte da verdade).

create table public.folhas_lotes (
  id uuid primary key default gen_random_uuid(),
  competencia date not null check (extract(day from competencia) = 1),
  arquivo_path text,
  total_paginas integer not null check (total_paginas between 1 and 2000),
  concluido boolean not null default false,
  enviado_por uuid not null references public.usuarios (id),
  criado_em timestamptz not null default now()
);
create index folhas_lotes_comp_idx on public.folhas_lotes (competencia, criado_em desc);

create table public.folhas_paginas (
  lote_id uuid not null references public.folhas_lotes (id) on delete cascade,
  pagina integer not null check (pagina >= 1),
  matricula_lida text check (matricula_lida is null or length(matricula_lida) <= 40),
  nome_lido text check (nome_lido is null or length(nome_lido) <= 200),
  servidor_id uuid references public.servidores (id),
  unidade_id uuid references public.unidades (id),
  vinculado_por uuid references public.usuarios (id),
  primary key (lote_id, pagina)
);

create table public.folhas_arquivos (
  id uuid primary key default gen_random_uuid(),
  lote_id uuid not null references public.folhas_lotes (id) on delete cascade,
  unidade_id uuid references public.unidades (id),   -- null = "Não identificadas"
  path text not null unique,
  paginas integer not null check (paginas >= 0),
  servidores integer not null check (servidores >= 0),
  criado_em timestamptz not null default now()
);
create index folhas_arquivos_lote_idx on public.folhas_arquivos (lote_id, unidade_id, criado_em desc);

create table public.folhas_entregas (
  competencia date not null check (extract(day from competencia) = 1),
  unidade_id uuid not null references public.unidades (id),
  enviada_em date,
  recebida_por uuid references public.servidores (id),
  devolvida_em date,
  devolvida_por uuid references public.servidores (id),
  ultimo_aviso_atraso date,
  atualizado_por uuid references public.usuarios (id),
  atualizado_em timestamptz not null default now(),
  primary key (competencia, unidade_id),
  constraint folhas_entregas_ordem check (devolvida_em is null or (enviada_em is not null and devolvida_em >= enviada_em)),
  constraint folhas_entregas_envio check (enviada_em is null or recebida_por is not null),
  constraint folhas_entregas_devolucao check (devolvida_em is null or devolvida_por is not null)
);

do $$
declare t text;
begin
  foreach t in array array['folhas_lotes', 'folhas_paginas', 'folhas_arquivos', 'folhas_entregas'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()', t || '_auditoria', t);
  end loop;
end $$;

create or replace function app.chefia_folhas()
returns boolean language sql stable security definer set search_path = ''
as $$ select app.sessao_ok() and app.perfil_atual() in ('diretor', 'coordenador') and app.tem_modulo('folhas_ponto') $$;

create policy folhas_lotes_ler on public.folhas_lotes for select to authenticated
  using ((select app.gestor_geral()) or (select app.chefia_folhas()));
create policy folhas_paginas_ler on public.folhas_paginas for select to authenticated
  using ((select app.gestor_geral()));
create policy folhas_arquivos_ler on public.folhas_arquivos for select to authenticated using (
  (select app.gestor_geral()) or ((select app.chefia_folhas()) and unidade_id in (select app.unidades_escopo()))
);
create policy folhas_entregas_ler on public.folhas_entregas for select to authenticated using (
  (select app.gestor_geral()) or ((select app.chefia_folhas()) and unidade_id in (select app.unidades_escopo()))
);

insert into public.configuracoes (chave, valor, descricao) values
  ('folhas.regex_matricula', to_jsonb('Matr[íi]cula[^0-9A-Za-z]{0,10}([0-9][0-9./-]{0,19})'::text),
   'Expressão que encontra a matrícula em cada página do PDF do RH (PENDENTE: confirmar com o modelo real do RH)'),
  ('folhas.prazo_devolucao_dias_uteis', '5', 'Prazo para a unidade devolver as folhas assinadas (dias úteis)')
on conflict (chave) do nothing;

-- ===== 1) cria o lote com o resultado da leitura do PDF (pagina, matricula, nome) e cruza no banco =====
create or replace function public.criar_lote_folhas(p_competencia date, p_paginas jsonb)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; r jsonb; n integer;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if p_competencia is null or extract(day from p_competencia) <> 1 then perform app.erro('Competência inválida.', '22023'); end if;
  if jsonb_typeof(p_paginas) <> 'array' then perform app.erro('Leitura do PDF inválida.', '22023'); end if;
  n := jsonb_array_length(p_paginas);
  if n < 1 or n > 2000 then perform app.erro('O PDF deve ter de 1 a 2000 páginas.', '22023'); end if;
  insert into public.folhas_lotes (competencia, total_paginas, enviado_por) values (p_competencia, n, auth.uid()) returning id into v_id;
  for r in select * from jsonb_array_elements(p_paginas) loop
    insert into public.folhas_paginas (lote_id, pagina, matricula_lida, nome_lido, servidor_id, unidade_id)
    select v_id, (r ->> 'pagina')::int, left(nullif(btrim(r ->> 'matricula'), ''), 40), left(nullif(btrim(r ->> 'nome'), ''), 200), s.id, s.unidade_id
      from (select 1) x
      left join public.servidores s on upper(s.matricula) = upper(btrim(r ->> 'matricula'));
  end loop;
  if (select count(*) from public.folhas_paginas where lote_id = v_id) <> n
     or exists (select 1 from public.folhas_paginas where lote_id = v_id and pagina > n) then
    perform app.erro('Leitura do PDF inválida (páginas repetidas ou fora de ordem).', '22023');
  end if;
  return v_id;
end $$;

-- ===== 2) registra os arquivos gerados (original e um por unidade) =====
create or replace function public.registrar_arquivos_folhas(p_lote uuid, p_original text, p_arquivos jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare r jsonb; v_prefixo text := 'lotes/' || p_lote::text || '/';
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if not exists (select 1 from public.folhas_lotes where id = p_lote) then perform app.erro('Lote não encontrado.', 'P0002'); end if;
  if p_original is not null then
    if p_original <> v_prefixo || 'original.pdf'
       or not exists (select 1 from storage.objects o where o.bucket_id = 'folhas-ponto' and o.name = p_original) then
      perform app.erro('Arquivo original inválido.', '22023');
    end if;
    update public.folhas_lotes set arquivo_path = p_original where id = p_lote;
  end if;
  for r in select * from jsonb_array_elements(coalesce(p_arquivos, '[]'::jsonb)) loop
    if (r ->> 'path') not like v_prefixo || 'unidades/%'
       or not exists (select 1 from storage.objects o where o.bucket_id = 'folhas-ponto' and o.name = r ->> 'path') then
      perform app.erro('Arquivo de unidade inválido.', '22023');
    end if;
    insert into public.folhas_arquivos (lote_id, unidade_id, path, paginas, servidores)
    values (p_lote, nullif(r ->> 'unidade_id', '')::uuid, r ->> 'path', (r ->> 'paginas')::int, (r ->> 'servidores')::int);
  end loop;
  update public.folhas_lotes set concluido = arquivo_path is not null where id = p_lote;
end $$;

-- ===== vincular página sem servidor (nenhuma página é descartada) =====
create or replace function public.vincular_pagina_folha(p_lote uuid, p_pagina integer, p_servidor uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_unidade uuid;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  select unidade_id into v_unidade from public.servidores where id = p_servidor;
  if v_unidade is null then perform app.erro('Servidor não encontrado.', 'P0002'); end if;
  update public.folhas_paginas set servidor_id = p_servidor, unidade_id = v_unidade, vinculado_por = auth.uid()
   where lote_id = p_lote and pagina = p_pagina;
  if not found then perform app.erro('Página não encontrada.', 'P0002'); end if;
  return v_unidade;
end $$;

-- páginas do lote com nome do servidor (para montar os PDFs em ordem alfabética)
create or replace function public.paginas_do_lote(p_lote uuid)
returns table (pagina integer, matricula_lida text, nome_lido text, servidor_id uuid, servidor text, unidade_id uuid, unidade text, ordem_unidade integer)
language sql stable security definer set search_path = ''
as $$
  select p.pagina, p.matricula_lida, p.nome_lido, p.servidor_id, s.nome_completo, p.unidade_id, u.sigla, u.ordem
    from public.folhas_paginas p
    left join public.servidores s on s.id = p.servidor_id
    left join public.unidades u on u.id = p.unidade_id
   where p.lote_id = p_lote and app.gestor_geral()
   order by p.pagina
$$;

-- ===== controle de entrega (6.18): secretária/admin ou chefia da unidade =====
create or replace function public.registrar_entrega_folha(p_competencia date, p_unidade uuid, p_etapa text, p_data date, p_pessoa uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not (app.gestor_geral() or (app.chefia_folhas() and app.na_escopo(p_unidade))) then
    perform app.erro('Sem permissão para esta unidade.', '42501');
  end if;
  if p_competencia is null or extract(day from p_competencia) <> 1 then perform app.erro('Competência inválida.', '22023'); end if;
  if p_data is null or p_data > current_date then perform app.erro('Data inválida.', '22023'); end if;
  if p_pessoa is not null and not exists (select 1 from public.servidores where id = p_pessoa and unidade_id = p_unidade) then
    perform app.erro('A pessoa deve ser servidor da unidade.', '22023');
  end if;
  if p_etapa = 'envio' then
    insert into public.folhas_entregas as e (competencia, unidade_id, enviada_em, recebida_por, atualizado_por)
    values (p_competencia, p_unidade, p_data, p_pessoa, auth.uid())
    on conflict (competencia, unidade_id) do update set enviada_em = excluded.enviada_em, recebida_por = excluded.recebida_por,
      atualizado_por = excluded.atualizado_por, atualizado_em = now();
  elsif p_etapa = 'devolucao' then
    update public.folhas_entregas set devolvida_em = p_data, devolvida_por = p_pessoa, atualizado_por = auth.uid(), atualizado_em = now()
     where competencia = p_competencia and unidade_id = p_unidade;
    if not found then perform app.erro('Registre o envio antes da devolução.', '22023'); end if;
  else
    perform app.erro('Etapa inválida.', '22023');
  end if;
end $$;

-- situação por unidade (não enviada / enviada / devolvida / atrasada) — invoker: RLS decide quais unidades aparecem
create or replace function public.situacao_entregas(p_competencia date)
returns table (unidade_id uuid, sigla text, ordem integer, situacao text, enviada_em date, recebida_por text, devolvida_em date, devolvida_por text, atrasada boolean)
language sql stable security invoker set search_path = ''
as $$
  select u.id, u.sigla, u.ordem,
         case when e.devolvida_em is not null then 'devolvida' when e.enviada_em is not null then 'enviada' else 'nao_enviada' end,
         e.enviada_em, sr.nome_completo, e.devolvida_em, sd.nome_completo,
         (e.enviada_em is not null and e.devolvida_em is null
          and public.dias_uteis_entre(e.enviada_em, current_date)
              > coalesce((select (c.valor)::int from public.configuracoes c where c.chave = 'folhas.prazo_devolucao_dias_uteis'), 5))
    from public.unidades u
    left join public.folhas_entregas e on e.unidade_id = u.id and e.competencia = p_competencia
    left join public.servidores sr on sr.id = e.recebida_por
    left join public.servidores sd on sd.id = e.devolvida_por
   where u.ativa and (app.gestor_geral() or (app.chefia_folhas() and u.id in (select app.unidades_escopo())))
   order by u.ordem, u.sigla
$$;

-- ===== aviso diário de atraso na devolução (chefia da unidade) =====
create or replace function app.avisar_atrasos_folhas()
returns integer language plpgsql security definer set search_path = ''
as $$
declare e record; v_chefe uuid; n integer := 0;
        v_prazo integer := coalesce((select (valor)::int from public.configuracoes where chave = 'folhas.prazo_devolucao_dias_uteis'), 5);
begin
  for e in
    select f.*, u.sigla from public.folhas_entregas f join public.unidades u on u.id = f.unidade_id
     where f.enviada_em is not null and f.devolvida_em is null
       and public.dias_uteis_entre(f.enviada_em, current_date) > v_prazo
       and (f.ultimo_aviso_atraso is null or f.ultimo_aviso_atraso < current_date)
  loop
    for v_chefe in select app.chefes_da_unidade(e.unidade_id) loop
      perform app.notificar(v_chefe, 'folha_atrasada', 'Folhas de ponto em atraso',
        e.sigla || ' · competência ' || to_char(e.competencia, 'MM/YYYY') || ' · enviada em ' || to_char(e.enviada_em, 'DD/MM'), '/folhas-ponto');
    end loop;
    update public.folhas_entregas set ultimo_aviso_atraso = current_date where competencia = e.competencia and unidade_id = e.unidade_id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function app.avisar_atrasos_folhas() from public, anon, authenticated;

-- agenda diária (pg_cron, se disponível no servidor — no Supabase: habilitar a extensão)
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('avisar-atrasos-folhas', '0 11 * * 1-5', 'select app.avisar_atrasos_folhas()');
  end if;
exception when others then
  raise notice 'pg_cron indisponível: agendar app.avisar_atrasos_folhas() manualmente';
end $$;

-- ===== storage privado =====
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('folhas-ponto', 'folhas-ponto', false, 52428800, array['application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy folhas_enviar on storage.objects for insert to authenticated with check (
  bucket_id = 'folhas-ponto' and (select app.gestor_geral())
  and name ~ '^lotes/[0-9a-f-]{36}/(original|unidades/(sem-unidade|[0-9a-f-]{36})-[0-9]{13})\.pdf$'
);
create policy folhas_ler on storage.objects for select to authenticated using (
  bucket_id = 'folhas-ponto' and (
    (select app.gestor_geral())
    or exists (select 1 from public.folhas_arquivos f where f.path = name)  -- RLS de folhas_arquivos aplica (escopo)
  )
);

-- módulos da Fase 2 ativos
update public.modulos set status = 'ativo' where codigo in ('ferias', 'folhas_ponto');

grant execute on function public.criar_lote_folhas(date, jsonb) to authenticated;
grant execute on function public.registrar_arquivos_folhas(uuid, text, jsonb) to authenticated;
grant execute on function public.vincular_pagina_folha(uuid, integer, uuid) to authenticated;
grant execute on function public.paginas_do_lote(uuid) to authenticated;
grant execute on function public.registrar_entrega_folha(date, uuid, text, date, uuid) to authenticated;
grant execute on function public.situacao_entregas(date) to authenticated;
grant execute on function app.chefia_folhas() to authenticated;
revoke execute on function public.criar_lote_folhas(date, jsonb) from anon;
revoke execute on function public.registrar_arquivos_folhas(uuid, text, jsonb) from anon;
revoke execute on function public.vincular_pagina_folha(uuid, integer, uuid) from anon;
revoke execute on function public.paginas_do_lote(uuid) from anon;
revoke execute on function public.registrar_entrega_folha(date, uuid, text, date, uuid) from anon;
revoke execute on function public.situacao_entregas(date) from anon;

-- ===================== 20261127000400_fase2_sessao.sql =====================
-- Fase 2 · minha_sessao passa a informar o servidor_id (telas de férias)
create or replace function public.minha_sessao()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select case when u.id is null then jsonb_build_object('autorizado', false, 'motivo', 'sem_cadastro')
    when not u.ativo or s.situacao <> 'ativo' then jsonb_build_object('autorizado', false, 'motivo', 'desativado')
    else jsonb_build_object(
      'autorizado', true,
      'usuario_id', u.id,
      'servidor_id', u.servidor_id,
      'perfil', u.perfil,
      'nome', s.nome_completo,
      'cargo', c.nome,
      'unidade_id', s.unidade_id,
      'unidade_sigla', un.sigla,
      'mfa_exigida', app.exige_mfa(u.perfil),
      'aal', coalesce(auth.jwt() ->> 'aal', 'aal1'),
      'sessao_ok', app.sessao_ok(),
      'modulos', coalesce((select jsonb_agg(m order by m) from app.modulos_do_usuario() m), '[]'::jsonb)
    ) end
  from (select auth.uid() as uid) x
  left join public.usuarios u on u.id = x.uid
  left join public.servidores s on s.id = u.servidor_id
  left join public.cargos c on c.id = s.cargo_id
  left join public.unidades un on un.id = s.unidade_id
$$;
