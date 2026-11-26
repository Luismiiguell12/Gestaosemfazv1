-- GERADO AUTOMATICAMENTE por scripts/gerar-sql-unico.mjs. Não editar à mão.
-- Uso: Supabase (web) → SQL Editor → New query → colar TUDO → Run. Somente em projeto NOVO e vazio.
-- Contém 21 migrations, na ordem.

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
   'Alternativa quando a matrícula não está logo abaixo do rótulo "Matrícula" (formato do relatório do RH, validado em 26/11/2026)'),
  ('folhas.prazo_devolucao_dias_uteis', '5', 'Prazo para a unidade devolver as folhas assinadas (dias úteis)')
on conflict (chave) do nothing;

create or replace function app.matricula_chave(m text)
returns text language sql immutable parallel safe set search_path = ''
as $$ select nullif(coalesce(nullif(ltrim(upper(btrim(coalesce(m, ''))), '0'), ''), case when btrim(coalesce(m, '')) ~ '^0+$' then '0' end), '') $$;
create index servidores_matricula_chave_idx on public.servidores (app.matricula_chave(matricula));
-- usada pelo índice: quem insere servidor precisa poder executá-la
grant execute on function app.matricula_chave(text) to authenticated, service_role;

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
    -- casa a matrícula ignorando maiúsculas e zeros à esquerda ("12345" = "012345");
    -- se houver mais de um candidato, deixa sem vínculo para conferência manual
    insert into public.folhas_paginas (lote_id, pagina, matricula_lida, nome_lido, servidor_id, unidade_id)
    select v_id, (r ->> 'pagina')::int, left(nullif(btrim(r ->> 'matricula'), ''), 40), left(nullif(btrim(r ->> 'nome'), ''), 200),
           c.id, c.unidade_id
      from (select 1) x
      left join lateral (
        select s.id, s.unidade_id from public.servidores s
         where app.matricula_chave(s.matricula) = app.matricula_chave(r ->> 'matricula')
           and (select count(*) from public.servidores s2 where app.matricula_chave(s2.matricula) = app.matricula_chave(r ->> 'matricula')) = 1
      ) c on true;
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

-- ===================== 20261128000100_fase3_demandas.sql =====================
-- Fase 3 · demandas (6.2), checklist (6.16), histórico. Prazos em dias úteis.

create type public.status_demanda as enum ('sugerida', 'a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao', 'concluida', 'recusada', 'cancelada');
create type public.prioridade_demanda as enum ('baixa', 'media', 'alta', 'critica');
create type public.origem_demanda as enum ('processo', 'email', 'whatsapp', 'recorrente', 'outra');

create table public.demandas (
  id uuid primary key default gen_random_uuid(),
  numero bigint generated always as identity unique,
  titulo text not null check (length(btrim(titulo)) between 3 and 200),
  descricao text check (descricao is null or length(descricao) <= 5000),
  origem public.origem_demanda not null default 'outra',
  numero_processo text check (numero_processo is null or length(numero_processo) <= 60),
  unidade_id uuid not null references public.unidades (id),
  prioridade public.prioridade_demanda not null default 'media',
  status public.status_demanda not null default 'a_fazer',
  prazo date,
  recorrencia_id uuid,
  ocorrencia_ref text,
  criado_por uuid not null references public.usuarios (id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  iniciada_em timestamptz,
  concluida_em timestamptz,
  ultimo_aviso_prazo date,
  constraint demandas_ocorrencia_unica unique (recorrencia_id, ocorrencia_ref)
);
create index demandas_unidade_idx on public.demandas (unidade_id, status);
create index demandas_prazo_idx on public.demandas (prazo) where status not in ('concluida', 'recusada', 'cancelada');
create index demandas_busca_idx on public.demandas (app.normalizar(titulo));
create trigger demandas_atualizado before update on public.demandas for each row execute function app.tocar_atualizado_em();

create type public.papel_responsavel as enum ('titular', 'substituto');
create table public.demanda_responsaveis (
  demanda_id uuid not null references public.demandas (id) on delete cascade,
  servidor_id uuid not null references public.servidores (id),
  papel public.papel_responsavel not null default 'titular',
  ativo boolean not null default true,
  afastamento_id uuid references public.afastamentos (id),
  adicionado_em timestamptz not null default now(),
  removido_em timestamptz,
  primary key (demanda_id, servidor_id)
);
create index demanda_resp_servidor_idx on public.demanda_responsaveis (servidor_id) where ativo;

create table public.demanda_checklist (
  id uuid primary key default gen_random_uuid(),
  demanda_id uuid not null references public.demandas (id) on delete cascade,
  texto text not null check (length(btrim(texto)) between 1 and 300),
  responsavel_id uuid references public.servidores (id),
  ordem integer not null default 0,
  feito boolean not null default false,
  feito_por uuid references public.usuarios (id),
  feito_em timestamptz,
  removido boolean not null default false
);
create index demanda_checklist_idx on public.demanda_checklist (demanda_id, ordem);

-- histórico da demanda: só cresce
create table public.demanda_historico (
  id bigint generated always as identity primary key,
  demanda_id uuid not null references public.demandas (id) on delete cascade,
  em timestamptz not null default now(),
  ator_id uuid references public.usuarios (id),
  acao text not null,
  detalhes jsonb not null default '{}'::jsonb
);
create index demanda_historico_idx on public.demanda_historico (demanda_id, em);
create trigger demanda_historico_imutavel before update or delete on public.demanda_historico
  for each row execute function app.auditoria_imutavel();

-- quem foi mencionado passa a ver a conversa (e a ficha) daquela demanda
create table public.demanda_participantes (
  demanda_id uuid not null references public.demandas (id) on delete cascade,
  usuario_id uuid not null references public.usuarios (id),
  incluido_em timestamptz not null default now(),
  primary key (demanda_id, usuario_id)
);

do $$
declare t text;
begin
  foreach t in array array['demandas', 'demanda_responsaveis', 'demanda_checklist', 'demanda_historico', 'demanda_participantes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
  foreach t in array array['demandas', 'demanda_responsaveis', 'demanda_checklist'] loop
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()', t || '_auditoria', t);
  end loop;
end $$;

-- ===== regras de acesso (uma função, usada nas políticas e nas RPCs) =====
create or replace function app.eh_responsavel(p_demanda uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.demanda_responsaveis r where r.demanda_id = p_demanda and r.ativo and r.servidor_id = app.servidor_atual()) $$;

create or replace function app.pode_gerir_demanda(p_unidade uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select app.gestor_geral()
      or (app.sessao_ok() and app.perfil_atual() in ('diretor', 'coordenador') and app.tem_modulo('demandas') and app.na_escopo(p_unidade))
$$;

create or replace function app.pode_ver_demanda(p_demanda uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select app.sessao_ok() and exists (
    select 1 from public.demandas d where d.id = p_demanda and (
      app.pode_gerir_demanda(d.unidade_id)
      or app.eh_responsavel(d.id)
      or d.criado_por = auth.uid()
      or exists (select 1 from public.demanda_participantes p where p.demanda_id = d.id and p.usuario_id = auth.uid())
    ))
$$;

create policy demandas_ler on public.demandas for select to authenticated using ((select app.pode_ver_demanda(id)));
create policy demanda_resp_ler on public.demanda_responsaveis for select to authenticated using ((select app.pode_ver_demanda(demanda_id)));
create policy demanda_check_ler on public.demanda_checklist for select to authenticated using ((select app.pode_ver_demanda(demanda_id)));
create policy demanda_hist_ler on public.demanda_historico for select to authenticated using ((select app.pode_ver_demanda(demanda_id)));
create policy demanda_part_ler on public.demanda_participantes for select to authenticated using ((select app.pode_ver_demanda(demanda_id)));
grant execute on function app.pode_ver_demanda(uuid), app.pode_gerir_demanda(uuid), app.eh_responsavel(uuid) to authenticated;

create or replace function app.historico(p_demanda uuid, p_acao text, p_detalhes jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = ''
as $$ insert into public.demanda_historico (demanda_id, ator_id, acao, detalhes) values (p_demanda, auth.uid(), p_acao, coalesce(p_detalhes, '{}'::jsonb)) $$;

create or replace function app.usuario_do_servidor(p_servidor uuid)
returns uuid language sql stable security definer set search_path = ''
as $$ select u.id from public.usuarios u where u.servidor_id = p_servidor and u.ativo $$;

create or replace function app.titulo_demanda(p_demanda uuid)
returns text language sql stable security definer set search_path = ''
as $$ select '#' || numero || ' ' || titulo from public.demandas where id = p_demanda $$;

-- define os responsáveis titulares (diferença: entra/sai), notifica quem entrou
create or replace function app.definir_titulares(p_demanda uuid, p_servidores uuid[])
returns void language plpgsql security definer set search_path = ''
as $$
declare v_s uuid; v_unidade uuid; v_u uuid;
begin
  select unidade_id into v_unidade from public.demandas where id = p_demanda;
  foreach v_s in array coalesce(p_servidores, '{}'::uuid[]) loop
    if not exists (select 1 from public.servidores s where s.id = v_s and s.situacao = 'ativo') then
      perform app.erro('Responsável inexistente ou inativo.', '22023');
    end if;
    -- rotina agendada (sem usuário) já validou no modelo; usuário: só servidores do seu escopo
    if auth.uid() is not null and not app.gestor_geral() and not app.na_escopo((select unidade_id from public.servidores where id = v_s)) then
      perform app.erro('Responsável fora da sua unidade.', '42501');
    end if;
  end loop;
  -- sai quem não está na lista
  update public.demanda_responsaveis set ativo = false, removido_em = now()
   where demanda_id = p_demanda and papel = 'titular' and ativo and not (servidor_id = any (coalesce(p_servidores, '{}'::uuid[])));
  foreach v_s in array coalesce(p_servidores, '{}'::uuid[]) loop
    insert into public.demanda_responsaveis as r (demanda_id, servidor_id, papel, ativo)
    values (p_demanda, v_s, 'titular', true)
    on conflict (demanda_id, servidor_id) do update set papel = 'titular', ativo = true, removido_em = null, afastamento_id = null
      where not (r.ativo and r.papel = 'titular');
    if found then
      perform app.historico(p_demanda, 'responsavel_incluido', jsonb_build_object('servidor', (select nome_completo from public.servidores where id = v_s)));
      v_u := app.usuario_do_servidor(v_s);
      if v_u is not null and v_u is distinct from auth.uid() then
        perform app.notificar(v_u, 'demanda_inclusao', 'Você foi incluído em uma demanda', app.titulo_demanda(p_demanda), '/demandas/ficha?id=' || p_demanda);
      end if;
    end if;
  end loop;
end $$;

create or replace function app.validar_dados_demanda(d jsonb)
returns void language plpgsql immutable set search_path = ''
as $$
begin
  if d ? 'titulo' and length(btrim(coalesce(d ->> 'titulo', ''))) < 3 then perform app.erro('Título com pelo menos 3 caracteres.', '22023'); end if;
  if d ? 'origem' and (d ->> 'origem') not in ('processo', 'email', 'whatsapp', 'recorrente', 'outra') then perform app.erro('Origem inválida.', '22023'); end if;
  if d ? 'prioridade' and (d ->> 'prioridade') not in ('baixa', 'media', 'alta', 'critica') then perform app.erro('Prioridade inválida.', '22023'); end if;
end $$;

-- ===== criar (chefia) =====
create or replace function public.criar_demanda(p_dados jsonb, p_responsaveis uuid[], p_checklist text[] default '{}')
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_unidade uuid := (p_dados ->> 'unidade_id')::uuid; v_item text; i integer := 0;
begin
  if not app.pode_gerir_demanda(v_unidade) then perform app.erro('Somente a chefia da unidade cria demandas.', '42501'); end if;
  perform app.validar_dados_demanda(p_dados);
  insert into public.demandas (titulo, descricao, origem, numero_processo, unidade_id, prioridade, prazo, criado_por)
  values (btrim(p_dados ->> 'titulo'), nullif(btrim(coalesce(p_dados ->> 'descricao', '')), ''), coalesce((p_dados ->> 'origem')::public.origem_demanda, 'outra'),
          nullif(btrim(coalesce(p_dados ->> 'numero_processo', '')), ''), v_unidade, coalesce((p_dados ->> 'prioridade')::public.prioridade_demanda, 'media'),
          (p_dados ->> 'prazo')::date, auth.uid())
  returning id into v_id;
  perform app.historico(v_id, 'criada', jsonb_build_object('prazo', p_dados ->> 'prazo'));
  perform app.definir_titulares(v_id, p_responsaveis);
  foreach v_item in array coalesce(p_checklist, '{}'::text[]) loop
    if btrim(v_item) <> '' then
      insert into public.demanda_checklist (demanda_id, texto, ordem) values (v_id, left(btrim(v_item), 300), i);
      i := i + 1;
    end if;
  end loop;
  return v_id;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
  perform app.erro('Dados inválidos.', '22023');
end $$;

-- ===== sugerir (funcionário) e decidir sugestão (chefia) =====
create or replace function public.sugerir_demanda(p_dados jsonb)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_unidade uuid := app.unidade_atual(); v_chefe uuid;
begin
  if not app.sessao_ok() or not app.tem_modulo('demandas') then perform app.erro('Acesso não permitido.', '42501'); end if;
  perform app.validar_dados_demanda(p_dados);
  insert into public.demandas (titulo, descricao, origem, numero_processo, unidade_id, prioridade, prazo, status, criado_por)
  values (btrim(p_dados ->> 'titulo'), nullif(btrim(coalesce(p_dados ->> 'descricao', '')), ''), coalesce((p_dados ->> 'origem')::public.origem_demanda, 'outra'),
          nullif(btrim(coalesce(p_dados ->> 'numero_processo', '')), ''), v_unidade, coalesce((p_dados ->> 'prioridade')::public.prioridade_demanda, 'media'),
          (p_dados ->> 'prazo')::date, 'sugerida', auth.uid())
  returning id into v_id;
  perform app.historico(v_id, 'sugerida');
  for v_chefe in select app.chefes_da_unidade(v_unidade) loop
    perform app.notificar(v_chefe, 'demanda_sugestao', 'Sugestão de demanda', app.titulo_demanda(v_id), '/demandas/ficha?id=' || v_id);
  end loop;
  return v_id;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
  perform app.erro('Dados inválidos.', '22023');
end $$;

create or replace function public.decidir_sugestao(p_id uuid, p_aprovar boolean, p_responsaveis uuid[] default '{}', p_prazo date default null, p_comentario text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare d public.demandas;
begin
  select * into d from public.demandas where id = p_id for update;
  if not found or d.status <> 'sugerida' then perform app.erro('Sugestão não encontrada ou já decidida.', 'P0002'); end if;
  if not app.pode_gerir_demanda(d.unidade_id) then perform app.erro('Somente a chefia da unidade decide sugestões.', '42501'); end if;
  if d.criado_por = auth.uid() then perform app.erro('Ninguém aprova a própria sugestão.', '42501'); end if;
  if p_aprovar then
    if coalesce(array_length(p_responsaveis, 1), 0) = 0 then perform app.erro('Indique pelo menos um responsável.', '22023'); end if;
    update public.demandas set status = 'a_fazer', prazo = coalesce(p_prazo, prazo) where id = p_id;
    perform app.historico(p_id, 'sugestao_aprovada', jsonb_build_object('comentario', p_comentario));
    perform app.definir_titulares(p_id, p_responsaveis);
  else
    if length(btrim(coalesce(p_comentario, ''))) = 0 then perform app.erro('Informe o comentário para recusar.', '22023'); end if;
    update public.demandas set status = 'recusada' where id = p_id;
    perform app.historico(p_id, 'sugestao_recusada', jsonb_build_object('comentario', p_comentario));
  end if;
  perform app.notificar(d.criado_por, 'demanda_sugestao_resultado', case when p_aprovar then 'Sugestão aprovada' else 'Sugestão recusada' end,
    app.titulo_demanda(p_id), '/demandas/ficha?id=' || p_id);
end $$;

-- ===== editar dados (chefia) =====
create or replace function public.atualizar_demanda(p_id uuid, p_dados jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare d public.demandas; v_antes jsonb; v_depois jsonb; k text;
begin
  select * into d from public.demandas where id = p_id for update;
  if not found then perform app.erro('Demanda não encontrada.', 'P0002'); end if;
  if not app.pode_gerir_demanda(d.unidade_id) then perform app.erro('Somente a chefia da unidade edita a demanda.', '42501'); end if;
  if exists (select 1 from jsonb_object_keys(p_dados) x where x not in ('titulo', 'descricao', 'origem', 'numero_processo', 'prioridade', 'prazo')) then
    perform app.erro('Campo não permitido.', '22023');
  end if;
  perform app.validar_dados_demanda(p_dados);
  v_antes := (select jsonb_object_agg(k2, to_jsonb(d) -> k2) from jsonb_object_keys(p_dados) k2);
  update public.demandas set
    titulo = case when p_dados ? 'titulo' then btrim(p_dados ->> 'titulo') else titulo end,
    descricao = case when p_dados ? 'descricao' then nullif(btrim(coalesce(p_dados ->> 'descricao', '')), '') else descricao end,
    origem = case when p_dados ? 'origem' then (p_dados ->> 'origem')::public.origem_demanda else origem end,
    numero_processo = case when p_dados ? 'numero_processo' then nullif(btrim(coalesce(p_dados ->> 'numero_processo', '')), '') else numero_processo end,
    prioridade = case when p_dados ? 'prioridade' then (p_dados ->> 'prioridade')::public.prioridade_demanda else prioridade end,
    prazo = case when p_dados ? 'prazo' then (p_dados ->> 'prazo')::date else prazo end
   where id = p_id returning to_jsonb(demandas.*) into v_depois;
  perform app.historico(p_id, 'editada', jsonb_build_object('antes', v_antes,
    'depois', (select jsonb_object_agg(k2, v_depois -> k2) from jsonb_object_keys(p_dados) k2)));
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
  perform app.erro('Dados inválidos.', '22023');
end $$;

create or replace function public.definir_responsaveis(p_id uuid, p_servidores uuid[])
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not app.pode_gerir_demanda((select unidade_id from public.demandas where id = p_id)) then
    perform app.erro('Somente a chefia da unidade distribui a demanda.', '42501');
  end if;
  if coalesce(array_length(p_servidores, 1), 0) = 0 then perform app.erro('Indique pelo menos um responsável.', '22023'); end if;
  perform app.definir_titulares(p_id, p_servidores);
end $$;

-- ===== status (responsável ou chefia). Concluir é ação explícita, nunca automática =====
create or replace function public.mudar_status_demanda(p_id uuid, p_status public.status_demanda)
returns void language plpgsql security definer set search_path = ''
as $$
declare d public.demandas;
begin
  select * into d from public.demandas where id = p_id for update;
  if not found then perform app.erro('Demanda não encontrada.', 'P0002'); end if;
  if not (app.eh_responsavel(p_id) or app.pode_gerir_demanda(d.unidade_id)) then
    perform app.erro('Somente responsáveis ou a chefia mudam o status.', '42501');
  end if;
  if d.status in ('sugerida', 'recusada') or p_status in ('sugerida', 'recusada') then perform app.erro('Use a decisão de sugestão.', '22023'); end if;
  if p_status = 'cancelada' and not app.pode_gerir_demanda(d.unidade_id) then perform app.erro('Somente a chefia cancela.', '42501'); end if;
  if d.status = p_status then return; end if;
  update public.demandas set status = p_status,
    iniciada_em = case when p_status = 'em_andamento' and iniciada_em is null then now() else iniciada_em end,
    concluida_em = case when p_status = 'concluida' then now() else null end
   where id = p_id;
  perform app.historico(p_id, 'status', jsonb_build_object('de', d.status, 'para', p_status));
end $$;

-- ===== checklist =====
create or replace function public.adicionar_item_checklist(p_demanda uuid, p_texto text, p_responsavel uuid default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not (app.eh_responsavel(p_demanda) or app.pode_gerir_demanda((select unidade_id from public.demandas where id = p_demanda))) then
    perform app.erro('Somente responsáveis ou a chefia editam o checklist.', '42501');
  end if;
  insert into public.demanda_checklist (demanda_id, texto, responsavel_id, ordem)
  values (p_demanda, left(btrim(p_texto), 300), p_responsavel, coalesce((select max(ordem) + 1 from public.demanda_checklist where demanda_id = p_demanda), 0))
  returning id into v_id;
  perform app.historico(p_demanda, 'etapa_incluida', jsonb_build_object('etapa', left(btrim(p_texto), 300)));
  return v_id;
end $$;

create or replace function public.marcar_item_checklist(p_item uuid, p_feito boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare c public.demanda_checklist;
begin
  select * into c from public.demanda_checklist where id = p_item and not removido;
  if not found then perform app.erro('Etapa não encontrada.', 'P0002'); end if;
  if not (app.eh_responsavel(c.demanda_id) or app.pode_gerir_demanda((select unidade_id from public.demandas where id = c.demanda_id))) then
    perform app.erro('Somente responsáveis ou a chefia marcam etapas.', '42501');
  end if;
  if c.feito = p_feito then return; end if;
  update public.demanda_checklist set feito = p_feito, feito_por = case when p_feito then auth.uid() end, feito_em = case when p_feito then now() end where id = p_item;
  perform app.historico(c.demanda_id, case when p_feito then 'etapa_marcada' else 'etapa_desmarcada' end, jsonb_build_object('etapa', c.texto));
end $$;

create or replace function public.remover_item_checklist(p_item uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare c public.demanda_checklist;
begin
  select * into c from public.demanda_checklist where id = p_item and not removido;
  if not found then perform app.erro('Etapa não encontrada.', 'P0002'); end if;
  if not app.pode_gerir_demanda((select unidade_id from public.demandas where id = c.demanda_id)) then perform app.erro('Somente a chefia remove etapas.', '42501'); end if;
  update public.demanda_checklist set removido = true where id = p_item;
  perform app.historico(c.demanda_id, 'etapa_removida', jsonb_build_object('etapa', c.texto));
end $$;

-- ===== listagem para quadro/lista (com nomes dos responsáveis e andamento do checklist) =====
create or replace function public.listar_demandas(p_incluir_encerradas_dias integer default 60)
returns table (id uuid, numero bigint, titulo text, origem public.origem_demanda, numero_processo text, unidade_id uuid, unidade text,
               prioridade public.prioridade_demanda, status public.status_demanda, prazo date, dias_uteis integer, concluida_em timestamptz,
               responsaveis jsonb, etapas_total integer, etapas_feitas integer, criado_por uuid, sou_responsavel boolean)
language sql stable security definer set search_path = ''
as $$
  select d.id, d.numero, d.titulo, d.origem, d.numero_processo, d.unidade_id, u.sigla, d.prioridade, d.status, d.prazo,
         case when d.prazo is null then null else public.dias_uteis_entre(current_date, d.prazo) end,
         d.concluida_em,
         coalesce((select jsonb_agg(jsonb_build_object('servidor_id', s.id, 'nome', s.nome_completo, 'papel', r.papel) order by r.papel, s.nome_completo)
                     from public.demanda_responsaveis r join public.servidores s on s.id = r.servidor_id where r.demanda_id = d.id and r.ativo), '[]'::jsonb),
         (select count(*)::int from public.demanda_checklist c where c.demanda_id = d.id and not c.removido),
         (select count(*)::int from public.demanda_checklist c where c.demanda_id = d.id and not c.removido and c.feito),
         d.criado_por, app.eh_responsavel(d.id)
    from public.demandas d join public.unidades u on u.id = d.unidade_id
   where app.pode_ver_demanda(d.id)
     and (d.status not in ('concluida', 'recusada', 'cancelada') or coalesce(d.concluida_em, d.atualizado_em) > now() - make_interval(days => greatest(p_incluir_encerradas_dias, 0)))
   order by d.prazo nulls last, d.numero
$$;

grant execute on function public.criar_demanda(jsonb, uuid[], text[]) to authenticated;
grant execute on function public.sugerir_demanda(jsonb) to authenticated;
grant execute on function public.decidir_sugestao(uuid, boolean, uuid[], date, text) to authenticated;
grant execute on function public.atualizar_demanda(uuid, jsonb) to authenticated;
grant execute on function public.definir_responsaveis(uuid, uuid[]) to authenticated;
grant execute on function public.mudar_status_demanda(uuid, public.status_demanda) to authenticated;
grant execute on function public.adicionar_item_checklist(uuid, text, uuid) to authenticated;
grant execute on function public.marcar_item_checklist(uuid, boolean) to authenticated;
grant execute on function public.remover_item_checklist(uuid) to authenticated;
grant execute on function public.listar_demandas(integer) to authenticated;

-- ===================== 20261128000200_fase3_conversa_anexos.sql =====================
-- Fase 3 · conversa da demanda (6.21) e anexos (6.20)

create type public.feedback_mensagem as enum ('aprovado', 'ajustar', 'refazer');
create type public.tipo_mensagem as enum ('mensagem', 'pedido_atualizacao');

create table public.demanda_anexos (
  id uuid primary key default gen_random_uuid(),
  demanda_id uuid not null references public.demandas (id) on delete cascade,
  nome text not null check (length(nome) between 1 and 120),
  path text not null unique,
  tipo text not null check (tipo in ('pdf', 'png', 'jpg', 'docx', 'xlsx')),
  tamanho integer not null check (tamanho between 1 and 20971520),
  versao integer not null default 1,
  substitui_id uuid references public.demanda_anexos (id),
  enviado_por uuid not null references public.usuarios (id),
  enviado_em timestamptz not null default now()
);
create index demanda_anexos_idx on public.demanda_anexos (demanda_id, enviado_em);

create table public.demanda_mensagens (
  id uuid primary key default gen_random_uuid(),
  demanda_id uuid not null references public.demandas (id) on delete cascade,
  autor_id uuid not null references public.usuarios (id),
  tipo public.tipo_mensagem not null default 'mensagem',
  texto text not null check (length(btrim(texto)) between 1 and 4000),
  anexo_id uuid references public.demanda_anexos (id),
  criado_em timestamptz not null default now(),
  editado_em timestamptz,
  feedback public.feedback_mensagem,
  feedback_comentario text check (feedback_comentario is null or length(feedback_comentario) <= 1000),
  feedback_por uuid references public.usuarios (id),
  feedback_em timestamptz
);
create index demanda_mensagens_idx on public.demanda_mensagens (demanda_id, criado_em);

do $$
declare t text;
begin
  foreach t in array array['demanda_anexos', 'demanda_mensagens'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()', t || '_auditoria', t);
  end loop;
end $$;
create policy demanda_anexos_ler on public.demanda_anexos for select to authenticated using ((select app.pode_ver_demanda(demanda_id)));
create policy demanda_msg_ler on public.demanda_mensagens for select to authenticated using ((select app.pode_ver_demanda(demanda_id)));
-- mensagens e anexos nunca são apagados
create trigger demanda_mensagens_sem_delete before delete on public.demanda_mensagens for each row execute function app.auditoria_imutavel();
create trigger demanda_anexos_sem_delete before delete on public.demanda_anexos for each row execute function app.auditoria_imutavel();

-- ===== mensagens =====
create or replace function public.enviar_mensagem(p_demanda uuid, p_texto text, p_mencoes uuid[] default '{}', p_anexo uuid default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_u uuid; v_autor text := app.nome_usuario(auth.uid());
begin
  if not app.pode_ver_demanda(p_demanda) then perform app.erro('Você não participa desta demanda.', '42501'); end if;
  if length(btrim(coalesce(p_texto, ''))) = 0 then perform app.erro('Mensagem vazia.', '22023'); end if;
  if p_anexo is not null and not exists (select 1 from public.demanda_anexos where id = p_anexo and demanda_id = p_demanda) then
    perform app.erro('Anexo inválido.', '22023');
  end if;
  insert into public.demanda_mensagens (demanda_id, autor_id, texto, anexo_id) values (p_demanda, auth.uid(), left(btrim(p_texto), 4000), p_anexo) returning id into v_id;
  foreach v_u in array coalesce(p_mencoes, '{}'::uuid[]) loop
    continue when v_u = auth.uid();
    if not exists (select 1 from public.usuarios u join public.servidores s on s.id = u.servidor_id where u.id = v_u and u.ativo and s.situacao = 'ativo') then
      continue;
    end if;
    insert into public.demanda_participantes (demanda_id, usuario_id) values (p_demanda, v_u) on conflict do nothing;
    perform app.notificar(v_u, 'demanda_mencao', v_autor || ' mencionou você', app.titulo_demanda(p_demanda), '/demandas/ficha?id=' || p_demanda);
    perform app.historico(p_demanda, 'mencao', jsonb_build_object('usuario', app.nome_usuario(v_u)));
  end loop;
  return v_id;
end $$;

create or replace function public.editar_mensagem(p_id uuid, p_texto text)
returns void language plpgsql security definer set search_path = ''
as $$
declare m public.demanda_mensagens;
begin
  select * into m from public.demanda_mensagens where id = p_id;
  if not found or m.autor_id <> auth.uid() or not app.pode_ver_demanda(m.demanda_id) then perform app.erro('Só o autor edita a mensagem.', '42501'); end if;
  if length(btrim(coalesce(p_texto, ''))) = 0 then perform app.erro('Mensagem vazia.', '22023'); end if;
  update public.demanda_mensagens set texto = left(btrim(p_texto), 4000), editado_em = now() where id = p_id;  -- texto anterior fica na auditoria
end $$;

-- "Pedir atualização": secretária, diretor ou coordenador
create or replace function public.pedir_atualizacao(p_demanda uuid, p_texto text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_s uuid; v_u uuid;
begin
  if not app.pode_gerir_demanda((select unidade_id from public.demandas where id = p_demanda)) then
    perform app.erro('Somente a chefia ou a Secretária pedem atualização.', '42501');
  end if;
  insert into public.demanda_mensagens (demanda_id, autor_id, tipo, texto)
  values (p_demanda, auth.uid(), 'pedido_atualizacao', coalesce(nullif(btrim(coalesce(p_texto, '')), ''), 'Por favor, relate o andamento desta demanda.'))
  returning id into v_id;
  for v_s in select servidor_id from public.demanda_responsaveis where demanda_id = p_demanda and ativo loop
    v_u := app.usuario_do_servidor(v_s);
    if v_u is not null then
      perform app.notificar(v_u, 'demanda_pedido_atualizacao', 'Pedido de atualização', app.titulo_demanda(p_demanda), '/demandas/ficha?id=' || p_demanda);
    end if;
  end loop;
  perform app.historico(p_demanda, 'pedido_atualizacao');
  return v_id;
end $$;

-- feedback da chefia em uma mensagem
create or replace function public.dar_feedback(p_mensagem uuid, p_feedback public.feedback_mensagem, p_comentario text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare m public.demanda_mensagens; v_rotulo text := case p_feedback when 'aprovado' then 'Aprovado' when 'ajustar' then 'Ajustar' else 'Refazer' end;
begin
  select * into m from public.demanda_mensagens where id = p_mensagem;
  if not found then perform app.erro('Mensagem não encontrada.', 'P0002'); end if;
  if not app.pode_gerir_demanda((select unidade_id from public.demandas where id = m.demanda_id)) then
    perform app.erro('Somente a chefia ou a Secretária dão feedback.', '42501');
  end if;
  if m.autor_id = auth.uid() then perform app.erro('Feedback é sobre a mensagem de outra pessoa.', '22023'); end if;
  update public.demanda_mensagens set feedback = p_feedback, feedback_comentario = nullif(btrim(coalesce(p_comentario, '')), ''),
    feedback_por = auth.uid(), feedback_em = now() where id = p_mensagem;
  perform app.historico(m.demanda_id, 'feedback', jsonb_build_object('feedback', v_rotulo, 'comentario', p_comentario));
  perform app.notificar(m.autor_id, 'demanda_feedback', 'Feedback: ' || v_rotulo, app.titulo_demanda(m.demanda_id), '/demandas/ficha?id=' || m.demanda_id);
end $$;

-- colegas para menção com @ (nomes do organograma; sem dados pessoais)
create or replace function public.usuarios_mencionaveis(p_termo text)
returns table (usuario_id uuid, nome text, unidade text)
language sql stable security definer set search_path = ''
as $$
  select u.id, s.nome_completo, un.sigla
    from public.usuarios u join public.servidores s on s.id = u.servidor_id join public.unidades un on un.id = s.unidade_id
   where app.sessao_ok() and u.ativo and s.situacao = 'ativo' and length(btrim(coalesce(p_termo, ''))) >= 1
     and app.normalizar(s.nome_completo) like '%' || replace(replace(app.normalizar(btrim(p_termo)), '%', ''), '_', '') || '%'
   order by s.nome_completo limit 8
$$;

-- ===== anexos (bucket privado "demandas"; acesso igual ao da demanda) =====
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('demandas', 'demandas', false, 20971520, array['application/pdf', 'image/png', 'image/jpeg',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function app.demanda_do_caminho(p_nome text)
returns uuid language sql immutable set search_path = ''
as $$ select case when p_nome ~ '^demandas/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|png|jpg|docx|xlsx)$' then (split_part(p_nome, '/', 2))::uuid end $$;
grant execute on function app.demanda_do_caminho(text) to authenticated;

create or replace function app.pode_anexar(p_demanda uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select p_demanda is not null and (app.eh_responsavel(p_demanda) or app.pode_gerir_demanda((select unidade_id from public.demandas where id = p_demanda))) $$;
grant execute on function app.pode_anexar(uuid) to authenticated;

create policy demandas_anexo_enviar on storage.objects for insert to authenticated with check (
  bucket_id = 'demandas' and (select app.pode_anexar(app.demanda_do_caminho(name)))
);
create policy demandas_anexo_ler on storage.objects for select to authenticated using (
  bucket_id = 'demandas' and (select app.pode_ver_demanda(app.demanda_do_caminho(name)))
);

create or replace function public.registrar_anexo(p_demanda uuid, p_path text, p_nome text, p_tipo text, p_tamanho integer, p_substitui uuid default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_versao integer := 1;
begin
  if not app.pode_anexar(p_demanda) then perform app.erro('Somente responsáveis ou a chefia anexam arquivos.', '42501'); end if;
  if app.demanda_do_caminho(p_path) is distinct from p_demanda
     or not exists (select 1 from storage.objects o where o.bucket_id = 'demandas' and o.name = p_path) then
    perform app.erro('Arquivo inválido.', '22023');
  end if;
  if p_substitui is not null then
    select versao + 1 into v_versao from public.demanda_anexos where id = p_substitui and demanda_id = p_demanda;
    if v_versao is null then perform app.erro('Anexo a substituir não encontrado.', 'P0002'); end if;
  end if;
  insert into public.demanda_anexos (demanda_id, nome, path, tipo, tamanho, versao, substitui_id, enviado_por)
  values (p_demanda, left(regexp_replace(coalesce(p_nome, 'arquivo'), '[^A-Za-zÀ-ÿ0-9 ._()-]', '_', 'g'), 120), p_path, p_tipo, p_tamanho, v_versao, p_substitui, auth.uid())
  returning id into v_id;
  perform app.historico(p_demanda, case when p_substitui is null then 'anexo' else 'anexo_nova_versao' end,
    jsonb_build_object('nome', left(p_nome, 120), 'versao', v_versao));
  return v_id;
end $$;

-- ===== ficha completa (uma chamada) =====
create or replace function public.demanda_detalhe(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare d public.demandas;
begin
  if not app.pode_ver_demanda(p_id) then return null; end if;
  select * into d from public.demandas where id = p_id;
  return jsonb_build_object(
    'demanda', to_jsonb(d) - 'ultimo_aviso_prazo' || jsonb_build_object(
      'unidade', (select sigla from public.unidades where id = d.unidade_id),
      'criado_por_nome', app.nome_usuario(d.criado_por),
      'dias_uteis', case when d.prazo is null then null else public.dias_uteis_entre(current_date, d.prazo) end),
    'permissoes', jsonb_build_object('gerir', app.pode_gerir_demanda(d.unidade_id), 'responsavel', app.eh_responsavel(p_id),
      'anexar', app.pode_anexar(p_id), 'proprio_criador', d.criado_por = auth.uid()),
    'responsaveis', coalesce((select jsonb_agg(jsonb_build_object('servidor_id', s.id, 'nome', s.nome_completo, 'papel', r.papel, 'usuario_id', app.usuario_do_servidor(s.id)) order by r.papel, s.nome_completo)
                                from public.demanda_responsaveis r join public.servidores s on s.id = r.servidor_id where r.demanda_id = p_id and r.ativo), '[]'::jsonb),
    'checklist', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'texto', c.texto, 'feito', c.feito, 'responsavel', (select nome_completo from public.servidores where id = c.responsavel_id),
                                  'feito_por', app.nome_usuario(c.feito_por), 'feito_em', c.feito_em) order by c.ordem)
                             from public.demanda_checklist c where c.demanda_id = p_id and not c.removido), '[]'::jsonb),
    'mensagens', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'tipo', m.tipo, 'texto', m.texto, 'autor_id', m.autor_id, 'autor', app.nome_usuario(m.autor_id),
                                  'criado_em', m.criado_em, 'editado_em', m.editado_em, 'feedback', m.feedback, 'feedback_comentario', m.feedback_comentario,
                                  'feedback_por', app.nome_usuario(m.feedback_por), 'anexo', (select jsonb_build_object('id', a.id, 'nome', a.nome, 'path', a.path) from public.demanda_anexos a where a.id = m.anexo_id))
                                  order by m.criado_em) from public.demanda_mensagens m where m.demanda_id = p_id), '[]'::jsonb),
    'anexos', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'nome', a.nome, 'path', a.path, 'tipo', a.tipo, 'tamanho', a.tamanho, 'versao', a.versao,
                                  'substitui_id', a.substitui_id, 'enviado_por', app.nome_usuario(a.enviado_por), 'enviado_em', a.enviado_em) order by a.enviado_em)
                          from public.demanda_anexos a where a.demanda_id = p_id), '[]'::jsonb),
    'historico', coalesce((select jsonb_agg(jsonb_build_object('em', h.em, 'ator', app.nome_usuario(h.ator_id), 'acao', h.acao, 'detalhes', h.detalhes) order by h.em desc, h.id desc)
                             from public.demanda_historico h where h.demanda_id = p_id), '[]'::jsonb)
  );
end $$;

grant execute on function public.enviar_mensagem(uuid, text, uuid[], uuid) to authenticated;
grant execute on function public.editar_mensagem(uuid, text) to authenticated;
grant execute on function public.pedir_atualizacao(uuid, text) to authenticated;
grant execute on function public.dar_feedback(uuid, public.feedback_mensagem, text) to authenticated;
grant execute on function public.usuarios_mencionaveis(text) to authenticated;
grant execute on function public.registrar_anexo(uuid, text, text, text, integer, uuid) to authenticated;
grant execute on function public.demanda_detalhe(uuid) to authenticated;

-- ===================== 20261128000300_fase3_rotinas_calendario_painel.sql =====================
-- Fase 3 · recorrentes (6.15), substituto nas demandas (6.14), aviso de prazo (6.10),
-- calendário (6.3), indicadores do painel (6.1) e busca geral com demandas (6.19)

-- ===== demandas recorrentes =====
create type public.periodicidade as enum ('mensal', 'trimestral', 'semestral', 'anual');
create type public.situacao_recorrencia as enum ('ativa', 'pausada', 'encerrada');

create table public.recorrencias (
  id uuid primary key default gen_random_uuid(),
  titulo text not null check (length(btrim(titulo)) between 3 and 200),
  descricao text check (descricao is null or length(descricao) <= 5000),
  unidade_id uuid not null references public.unidades (id),
  periodicidade public.periodicidade not null,
  prazo_dias_uteis integer not null check (prazo_dias_uteis between 1 and 120),
  prioridade public.prioridade_demanda not null default 'media',
  responsaveis uuid[] not null check (cardinality(responsaveis) between 1 and 20),
  checklist text[] not null default '{}',
  situacao public.situacao_recorrencia not null default 'ativa',
  proxima_em date not null,
  criado_por uuid not null references public.usuarios (id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
alter table public.demandas add constraint demandas_recorrencia_fk foreign key (recorrencia_id) references public.recorrencias (id);
create trigger recorrencias_atualizado before update on public.recorrencias for each row execute function app.tocar_atualizado_em();
alter table public.recorrencias enable row level security;
revoke all on public.recorrencias from anon, authenticated;
grant select on public.recorrencias to authenticated;
create policy recorrencias_ler on public.recorrencias for select to authenticated using ((select app.pode_gerir_demanda(unidade_id)));
create trigger recorrencias_auditoria after insert or update or delete on public.recorrencias for each row execute function app.auditar_linha();

create or replace function public.salvar_recorrencia(p_id uuid, p_dados jsonb, p_responsaveis uuid[], p_checklist text[] default '{}')
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := p_id; v_unidade uuid := (p_dados ->> 'unidade_id')::uuid; v_s uuid; v_inicio date := coalesce((p_dados ->> 'proxima_em')::date, current_date);
begin
  if p_id is not null then select unidade_id into v_unidade from public.recorrencias where id = p_id; end if;
  if v_unidade is null or not app.pode_gerir_demanda(v_unidade) then perform app.erro('Somente a chefia da unidade cria modelos recorrentes.', '42501'); end if;
  if coalesce(array_length(p_responsaveis, 1), 0) = 0 then perform app.erro('Indique pelo menos um responsável.', '22023'); end if;
  foreach v_s in array p_responsaveis loop
    if not app.gestor_geral() and not app.na_escopo((select unidade_id from public.servidores where id = v_s)) then perform app.erro('Responsável fora da sua unidade.', '42501'); end if;
  end loop;
  if v_inicio < current_date then perform app.erro('A primeira ocorrência deve ser hoje ou depois.', '22023'); end if;
  if p_id is null then
    insert into public.recorrencias (titulo, descricao, unidade_id, periodicidade, prazo_dias_uteis, prioridade, responsaveis, checklist, proxima_em, criado_por)
    values (btrim(p_dados ->> 'titulo'), nullif(btrim(coalesce(p_dados ->> 'descricao', '')), ''), v_unidade, (p_dados ->> 'periodicidade')::public.periodicidade,
            (p_dados ->> 'prazo_dias_uteis')::int, coalesce((p_dados ->> 'prioridade')::public.prioridade_demanda, 'media'), p_responsaveis,
            coalesce(p_checklist, '{}'), v_inicio, auth.uid())
    returning id into v_id;
  else
    -- editar o modelo vale só para as próximas ocorrências (as já criadas não mudam)
    update public.recorrencias set titulo = btrim(p_dados ->> 'titulo'), descricao = nullif(btrim(coalesce(p_dados ->> 'descricao', '')), ''),
      periodicidade = (p_dados ->> 'periodicidade')::public.periodicidade, prazo_dias_uteis = (p_dados ->> 'prazo_dias_uteis')::int,
      prioridade = coalesce((p_dados ->> 'prioridade')::public.prioridade_demanda, prioridade), responsaveis = p_responsaveis,
      checklist = coalesce(p_checklist, '{}'), proxima_em = coalesce((p_dados ->> 'proxima_em')::date, proxima_em)
     where id = p_id and situacao <> 'encerrada';
    if not found then perform app.erro('Modelo não encontrado ou encerrado.', 'P0002'); end if;
  end if;
  return v_id;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or not_null_violation then
  perform app.erro('Dados inválidos.', '22023');
end $$;

create or replace function public.mudar_situacao_recorrencia(p_id uuid, p_situacao public.situacao_recorrencia)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not app.pode_gerir_demanda((select unidade_id from public.recorrencias where id = p_id)) then
    perform app.erro('Pausar ou encerrar exige a chefia da unidade.', '42501');
  end if;
  update public.recorrencias set situacao = p_situacao where id = p_id and situacao <> 'encerrada';
  if not found then perform app.erro('Modelo não encontrado ou já encerrado.', 'P0002'); end if;
end $$;

create or replace function app.proximo_periodo(d date, p public.periodicidade)
returns date language sql immutable set search_path = ''
as $$ select (d + case p when 'mensal' then interval '1 month' when 'trimestral' then interval '3 months' when 'semestral' then interval '6 months' else interval '1 year' end)::date $$;

-- cria cada ocorrência uma única vez (constraint unique (recorrencia_id, ocorrencia_ref))
create or replace function app.gerar_ocorrencias()
returns integer language plpgsql security definer set search_path = ''
as $$
declare r public.recorrencias; v_id uuid; n integer := 0; v_item text; i integer;
begin
  for r in select * from public.recorrencias where situacao = 'ativa' and proxima_em <= current_date for update loop
    insert into public.demandas (titulo, descricao, origem, unidade_id, prioridade, prazo, recorrencia_id, ocorrencia_ref, criado_por)
    values (r.titulo, r.descricao, 'recorrente', r.unidade_id, r.prioridade, public.somar_dias_uteis(r.proxima_em, r.prazo_dias_uteis),
            r.id, to_char(r.proxima_em, 'YYYY-MM-DD'), r.criado_por)
    on conflict (recorrencia_id, ocorrencia_ref) do nothing
    returning id into v_id;
    if v_id is not null then
      perform app.historico(v_id, 'criada_por_rotina', jsonb_build_object('modelo', r.id, 'referencia', to_char(r.proxima_em, 'DD/MM/YYYY')));
      perform app.definir_titulares(v_id, (select array_agg(x) from unnest(r.responsaveis) x join public.servidores s on s.id = x and s.situacao = 'ativo'));
      i := 0;
      foreach v_item in array r.checklist loop
        insert into public.demanda_checklist (demanda_id, texto, ordem) values (v_id, left(v_item, 300), i); i := i + 1;
      end loop;
      n := n + 1;
    end if;
    update public.recorrencias set proxima_em = app.proximo_periodo(proxima_em, periodicidade) where id = r.id;
  end loop;
  return n;
end $$;

-- ===== substituto nas demandas (6.14) =====
create table public.substituicoes (
  afastamento_id uuid primary key references public.afastamentos (id),
  aplicada_em timestamptz not null default now(),
  encerrada_em timestamptz
);
alter table public.substituicoes enable row level security;
revoke all on public.substituicoes from anon, authenticated;

create or replace function app.aplicar_substituicoes()
returns integer language plpgsql security definer set search_path = ''
as $$
declare a record; d record; v_u uuid; v_chefe uuid; n integer := 0; v_primeiro date;
begin
  -- início: a partir do 1º dia útil do afastamento, substituto entra como responsável adicional (titular continua)
  for a in select af.*, s.nome_completo as titular_nome, s.unidade_id, sb.nome_completo as substituto_nome
             from public.afastamentos af join public.servidores s on s.id = af.servidor_id join public.servidores sb on sb.id = af.substituto_id
            where af.status = 'aprovado' and af.substituto_id is not null and current_date <= af.fim
  loop
    v_primeiro := case when public.eh_dia_util(a.inicio) then a.inicio else public.somar_dias_uteis(a.inicio, 1) end;
    continue when current_date < v_primeiro or v_primeiro > a.fim;
    for d in select dm.id from public.demandas dm join public.demanda_responsaveis r on r.demanda_id = dm.id
              where r.servidor_id = a.servidor_id and r.ativo and r.papel = 'titular'
                and dm.status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao')
                and not exists (select 1 from public.demanda_responsaveis x where x.demanda_id = dm.id and x.servidor_id = a.substituto_id and x.ativo)
    loop
      insert into public.demanda_responsaveis as r (demanda_id, servidor_id, papel, ativo, afastamento_id)
      values (d.id, a.substituto_id, 'substituto', true, a.id)
      on conflict (demanda_id, servidor_id) do update set papel = 'substituto', ativo = true, afastamento_id = excluded.afastamento_id, removido_em = null;
      perform app.historico(d.id, 'substituicao_inicio', jsonb_build_object('titular', a.titular_nome, 'substituto', a.substituto_nome, 'ate', a.fim));
      n := n + 1;
    end loop;
    if not exists (select 1 from public.substituicoes where afastamento_id = a.id) then
      insert into public.substituicoes (afastamento_id) values (a.id);
      v_u := app.usuario_do_servidor(a.substituto_id);
      if v_u is not null then
        perform app.notificar(v_u, 'substituicao_inicio', 'Início de substituição', 'Você substitui ' || a.titular_nome || ' até ' || to_char(a.fim, 'DD/MM'), '/demandas');
      end if;
      for v_chefe in select app.chefes_da_unidade(a.unidade_id) loop
        perform app.notificar(v_chefe, 'substituicao_inicio', 'Início de substituição', a.substituto_nome || ' substitui ' || a.titular_nome || ' até ' || to_char(a.fim, 'DD/MM'), '/ferias');
      end loop;
    end if;
  end loop;
  -- retorno: substituto sai das demandas que não concluiu
  for a in select af.id, sb.nome_completo as substituto_nome from public.substituicoes su join public.afastamentos af on af.id = su.afastamento_id
             join public.servidores sb on sb.id = af.substituto_id
            where su.encerrada_em is null and (af.fim < current_date or af.status <> 'aprovado')
  loop
    for d in select r.demanda_id from public.demanda_responsaveis r join public.demandas dm on dm.id = r.demanda_id
              where r.afastamento_id = a.id and r.papel = 'substituto' and r.ativo and dm.status <> 'concluida'
    loop
      update public.demanda_responsaveis set ativo = false, removido_em = now() where demanda_id = d.demanda_id and afastamento_id = a.id and papel = 'substituto';
      perform app.historico(d.demanda_id, 'substituicao_fim', jsonb_build_object('substituto', a.substituto_nome));
    end loop;
    update public.substituicoes set encerrada_em = now() where afastamento_id = a.id;
  end loop;
  return n;
end $$;

-- ===== aviso de prazo próximo (hoje ou próximo dia útil), uma vez por dia =====
create or replace function app.avisar_prazos()
returns integer language plpgsql security definer set search_path = ''
as $$
declare d record; v_s uuid; v_u uuid; n integer := 0; v_dias integer;
begin
  for d in select * from public.demandas where status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao')
             and prazo is not null and prazo >= current_date and ultimo_aviso_prazo is distinct from current_date loop
    v_dias := public.dias_uteis_entre(current_date, d.prazo);
    continue when v_dias > 1;
    for v_s in select servidor_id from public.demanda_responsaveis where demanda_id = d.id and ativo loop
      v_u := app.usuario_do_servidor(v_s);
      if v_u is not null then
        perform app.notificar(v_u, 'demanda_prazo', case when v_dias = 0 then 'Prazo vence hoje' else 'Prazo vence no próximo dia útil' end,
          '#' || d.numero || ' ' || d.titulo, '/demandas/ficha?id=' || d.id);
      end if;
    end loop;
    update public.demandas set ultimo_aviso_prazo = current_date where id = d.id;
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function app.rotinas_diarias_demandas()
returns void language plpgsql security definer set search_path = ''
as $$ begin perform app.gerar_ocorrencias(); perform app.aplicar_substituicoes(); perform app.avisar_prazos(); end $$;
revoke execute on function app.rotinas_diarias_demandas() from public, anon, authenticated;
revoke execute on function app.gerar_ocorrencias() from public, anon, authenticated;
revoke execute on function app.aplicar_substituicoes() from public, anon, authenticated;
revoke execute on function app.avisar_prazos() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('rotinas-diarias-demandas', '5 9 * * *', 'select app.rotinas_diarias_demandas()');  -- 06:05 de Brasília
  end if;
exception when others then
  raise notice 'pg_cron indisponível: agendar app.rotinas_diarias_demandas() manualmente';
end $$;

-- ===== calendário (6.3) =====
create type public.tipo_compromisso as enum ('compromisso', 'prazo');

create table public.compromissos (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid references public.unidades (id),   -- null = calendário geral do Gabinete (Secretária)
  titulo text not null check (length(btrim(titulo)) between 2 and 200),
  descricao text check (descricao is null or length(descricao) <= 2000),
  local text check (local is null or length(local) <= 200),
  tipo public.tipo_compromisso not null default 'compromisso',
  inicio timestamptz not null,
  fim timestamptz not null,
  dia_inteiro boolean not null default false,
  cancelado boolean not null default false,
  criado_por uuid not null references public.usuarios (id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint compromissos_periodo check (fim >= inicio and fim - inicio <= interval '31 days')
);
create index compromissos_inicio_idx on public.compromissos (inicio);
create trigger compromissos_atualizado before update on public.compromissos for each row execute function app.tocar_atualizado_em();
create table public.compromisso_participantes (
  compromisso_id uuid not null references public.compromissos (id) on delete cascade,
  servidor_id uuid not null references public.servidores (id),
  primary key (compromisso_id, servidor_id)
);

create or replace function app.pode_editar_calendario(p_unidade uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select app.gestor_geral()
      or (p_unidade is not null and app.sessao_ok() and app.perfil_atual() in ('diretor', 'coordenador')
          and app.tem_modulo('calendario') and app.na_escopo(p_unidade))
$$;

create or replace function app.pode_ver_compromisso(p_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select app.sessao_ok() and exists (
    select 1 from public.compromissos c where c.id = p_id and (
      app.pode_editar_calendario(c.unidade_id)
      or exists (select 1 from public.compromisso_participantes p where p.compromisso_id = c.id and p.servidor_id = app.servidor_atual())
    ))
$$;
grant execute on function app.pode_ver_compromisso(uuid) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['compromissos', 'compromisso_participantes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()', t || '_auditoria', t);
  end loop;
end $$;
create policy compromissos_ler on public.compromissos for select to authenticated using ((select app.pode_ver_compromisso(id)));
create policy compromisso_part_ler on public.compromisso_participantes for select to authenticated using ((select app.pode_ver_compromisso(compromisso_id)));

create or replace function public.salvar_compromisso(p_id uuid, p_dados jsonb, p_participantes uuid[] default '{}')
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := p_id; v_unidade uuid := nullif(p_dados ->> 'unidade_id', '')::uuid; v_s uuid; v_u uuid;
begin
  if p_id is not null then select unidade_id into v_unidade from public.compromissos where id = p_id; end if;
  if not app.pode_editar_calendario(v_unidade) then perform app.erro('Você só pode editar o calendário da sua unidade.', '42501'); end if;
  if p_id is null then
    insert into public.compromissos (unidade_id, titulo, descricao, local, tipo, inicio, fim, dia_inteiro, criado_por)
    values (v_unidade, btrim(p_dados ->> 'titulo'), nullif(btrim(coalesce(p_dados ->> 'descricao', '')), ''), nullif(btrim(coalesce(p_dados ->> 'local', '')), ''),
            coalesce((p_dados ->> 'tipo')::public.tipo_compromisso, 'compromisso'), (p_dados ->> 'inicio')::timestamptz,
            coalesce((p_dados ->> 'fim')::timestamptz, (p_dados ->> 'inicio')::timestamptz), coalesce((p_dados ->> 'dia_inteiro')::boolean, false), auth.uid())
    returning id into v_id;
  else
    update public.compromissos set titulo = btrim(p_dados ->> 'titulo'), descricao = nullif(btrim(coalesce(p_dados ->> 'descricao', '')), ''),
      local = nullif(btrim(coalesce(p_dados ->> 'local', '')), ''), tipo = coalesce((p_dados ->> 'tipo')::public.tipo_compromisso, tipo),
      inicio = (p_dados ->> 'inicio')::timestamptz, fim = coalesce((p_dados ->> 'fim')::timestamptz, (p_dados ->> 'inicio')::timestamptz),
      dia_inteiro = coalesce((p_dados ->> 'dia_inteiro')::boolean, dia_inteiro)
     where id = p_id and not cancelado;
    if not found then perform app.erro('Compromisso não encontrado ou cancelado.', 'P0002'); end if;
  end if;
  delete from public.compromisso_participantes where compromisso_id = v_id and not (servidor_id = any (coalesce(p_participantes, '{}'::uuid[])));
  foreach v_s in array coalesce(p_participantes, '{}'::uuid[]) loop
    insert into public.compromisso_participantes (compromisso_id, servidor_id) values (v_id, v_s) on conflict do nothing;
    if found then
      v_u := app.usuario_do_servidor(v_s);
      if v_u is not null and v_u is distinct from auth.uid() then
        perform app.notificar(v_u, 'compromisso', 'Você foi incluído em um compromisso',
          btrim(p_dados ->> 'titulo') || ' · ' || to_char(((p_dados ->> 'inicio')::timestamptz) at time zone 'America/Maceio', 'DD/MM HH24:MI'), '/calendario');
      end if;
    end if;
  end loop;
  return v_id;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or not_null_violation then
  perform app.erro('Dados inválidos.', '22023');
end $$;

create or replace function public.cancelar_compromisso(p_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not app.pode_editar_calendario((select unidade_id from public.compromissos where id = p_id)) then perform app.erro('Sem permissão.', '42501'); end if;
  update public.compromissos set cancelado = true where id = p_id and not cancelado;
  if not found then perform app.erro('Compromisso não encontrado.', 'P0002'); end if;
end $$;

-- eventos do período: compromissos, prazos de demandas e feriados — cada um só o que a pessoa pode ver
create or replace function public.eventos_calendario(p_inicio date, p_fim date)
returns table (tipo text, id uuid, titulo text, inicio timestamptz, fim timestamptz, dia_inteiro boolean, unidade_id uuid, unidade text,
               local text, descricao text, participantes jsonb, editavel boolean)
language sql stable security definer set search_path = ''
as $$
  select c.tipo::text, c.id, c.titulo, c.inicio, c.fim, c.dia_inteiro, c.unidade_id, coalesce(u.sigla, 'Geral do Gabinete'), c.local, c.descricao,
         coalesce((select jsonb_agg(jsonb_build_object('servidor_id', s.id, 'nome', s.nome_completo) order by s.nome_completo)
                     from public.compromisso_participantes p join public.servidores s on s.id = p.servidor_id where p.compromisso_id = c.id), '[]'::jsonb),
         app.pode_editar_calendario(c.unidade_id)
    from public.compromissos c left join public.unidades u on u.id = c.unidade_id
   where not c.cancelado and app.pode_ver_compromisso(c.id) and c.inicio < (p_fim + 1)::timestamptz and c.fim >= p_inicio::timestamptz
  union all
  select 'demanda', d.id, '#' || d.numero || ' ' || d.titulo, d.prazo::timestamptz, d.prazo::timestamptz, true, d.unidade_id, u.sigla, null, null,
         coalesce((select jsonb_agg(jsonb_build_object('servidor_id', s.id, 'nome', s.nome_completo) order by s.nome_completo)
                     from public.demanda_responsaveis r join public.servidores s on s.id = r.servidor_id where r.demanda_id = d.id and r.ativo), '[]'::jsonb),
         false
    from public.demandas d join public.unidades u on u.id = d.unidade_id
   where d.prazo between p_inicio and p_fim and d.status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao') and app.pode_ver_demanda(d.id)
  union all
  select 'feriado', f.id, f.descricao, f.data::timestamptz, f.data::timestamptz, true, null, null, null, null, '[]'::jsonb, false
    from public.feriados f where app.sessao_ok() and f.data between p_inicio and p_fim
  order by 4
$$;

-- ===== painel (6.1) =====
create or replace function public.painel_unidades()
returns table (unidade_id uuid, a_fazer integer, em_andamento integer, concluidas integer, atrasadas integer, apertadas integer, concluidas_90 integer, no_prazo_90 integer)
language sql stable security definer set search_path = ''
as $$
  select u.id,
    count(*) filter (where d.status = 'a_fazer')::int,
    count(*) filter (where d.status in ('em_andamento', 'aguardando_terceiros', 'em_revisao'))::int,
    count(*) filter (where d.status = 'concluida' and d.concluida_em > now() - interval '30 days')::int,
    count(*) filter (where d.status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao') and d.prazo < current_date)::int,
    count(*) filter (where d.status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao') and d.prazo >= current_date
                     and public.dias_uteis_entre(current_date, d.prazo) <= coalesce((select (valor)::int from public.configuracoes where chave = 'demandas.prazo_apertado_dias_uteis'), 2))::int,
    count(*) filter (where d.status = 'concluida' and d.concluida_em > now() - interval '90 days' and d.prazo is not null)::int,
    count(*) filter (where d.status = 'concluida' and d.concluida_em > now() - interval '90 days' and d.prazo is not null and (d.concluida_em at time zone 'America/Maceio')::date <= d.prazo)::int
  from public.unidades u left join public.demandas d on d.unidade_id = u.id
  where u.ativa and app.sessao_ok() and app.perfil_atual() <> 'funcionario' and u.id in (select app.unidades_escopo())
  group by u.id
$$;

-- números do próprio servidor (painel do funcionário). Demanda com vários responsáveis conta para cada um.
create or replace function public.meus_indicadores()
returns jsonb language sql stable security definer set search_path = ''
as $$
  with minhas as (
    select d.* from public.demandas d join public.demanda_responsaveis r on r.demanda_id = d.id
     where r.servidor_id = app.servidor_atual() and app.sessao_ok()
  )
  select jsonb_build_object(
    'abertas', (select count(*) from minhas where status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao')),
    'atrasadas', (select count(*) from minhas where status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao') and prazo < current_date),
    'concluidas_mes', (select count(*) from minhas where status = 'concluida' and date_trunc('month', concluida_em) = date_trunc('month', now())),
    'no_prazo_pct', (select case when count(*) = 0 then null else round(100.0 * count(*) filter (where (concluida_em at time zone 'America/Maceio')::date <= prazo) / count(*)) end
                       from minhas where status = 'concluida' and prazo is not null and concluida_em > now() - interval '90 days'),
    'por_mes', (select jsonb_agg(jsonb_build_object('mes', to_char(m, 'YYYY-MM'),
                  'concluidas', (select count(*) from minhas where status = 'concluida' and date_trunc('month', concluida_em) = m)) order by m)
                  from generate_series(date_trunc('month', now()) - interval '5 months', date_trunc('month', now()), interval '1 month') m)
  )
$$;

insert into public.configuracoes (chave, valor, descricao) values
  ('demandas.prazo_apertado_dias_uteis', '2', 'Demanda aberta com prazo em até N dias úteis deixa a unidade em "Prazo apertado"')
on conflict (chave) do nothing;

-- ===== busca geral: + demandas (título, nº do processo ou #número) — invoker, RLS decide =====
create or replace function public.busca_geral(termo text, limite integer default 8)
returns table (tipo text, id uuid, titulo text, subtitulo text, rota text)
language plpgsql stable security invoker set search_path = ''
as $$
declare q text := app.normalizar(btrim(coalesce(termo, '')));
        lim integer := least(greatest(coalesce(limite, 8), 1), 20);
        num bigint := case when btrim(coalesce(termo, '')) ~ '^#?[0-9]{1,12}$' then ltrim(btrim(termo), '#')::bigint end;
begin
  if length(q) < 2 and num is null then return; end if;
  q := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return query
    (select 'demanda'::text, d.id, '#' || d.numero || ' ' || d.titulo, coalesce('Processo ' || d.numero_processo, 'Demanda'), '/demandas/ficha?id=' || d.id
       from public.demandas d
      where app.normalizar(d.titulo) like q or app.normalizar(coalesce(d.numero_processo, '')) like q or d.numero = num
      order by d.numero desc limit lim)
    union all
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

update public.modulos set status = 'ativo' where codigo = 'demandas';

grant execute on function public.salvar_recorrencia(uuid, jsonb, uuid[], text[]) to authenticated;
grant execute on function public.mudar_situacao_recorrencia(uuid, public.situacao_recorrencia) to authenticated;
grant execute on function public.salvar_compromisso(uuid, jsonb, uuid[]) to authenticated;
grant execute on function public.cancelar_compromisso(uuid) to authenticated;
grant execute on function public.eventos_calendario(date, date) to authenticated;
grant execute on function public.painel_unidades() to authenticated;
grant execute on function public.meus_indicadores() to authenticated;
grant execute on function public.busca_geral(text, integer) to authenticated;

-- ===================== 20261129000050_fase4_tipos.sql =====================
-- Fase 4 · tipos (valores novos de enum precisam de migration própria antes de serem usados)
alter type public.tipo_solicitacao add value if not exists 'contrato_alterar';
alter type public.tipo_solicitacao add value if not exists 'contrato_aditivo';

create type public.tipo_pessoa as enum ('PF', 'PJ');
create type public.fornecedor_uc as enum ('energisa', 'igua', 'cercos');

-- permissão específica para ver CPF/CNPJ e contato completos do locador (LGPD).
-- Não entra em nenhum pacote padrão: só como módulo extra concedido pela Secretária/Admin.
insert into public.modulos (codigo, nome, rota, icone, ordem, status, fase, no_menu)
values ('locadores_dados', 'Dados completos de locadores', '/contratos', 'contratos', 140, 'ativo', 4, false)
on conflict (codigo) do nothing;

-- ===================== 20261129000100_fase4_contratos.sql =====================
-- Fase 4 · contratos de locação (6.5): ficha única, aditivos, documentos, aluguéis
-- Acesso por MÓDULO (não por unidade): quem a Secretária liberar (prompt 4).
-- LGPD: CPF e contato do locador mascarados; completo só com o módulo "locadores_dados".

create or replace function app.acesso_contratos()
returns boolean language sql stable security definer set search_path = ''
as $$ select app.sessao_ok() and app.tem_modulo('contratos') $$;
grant execute on function app.acesso_contratos() to authenticated;

-- ===== utilitários de planilha / documentos =====
create or replace function app.so_digitos(t text)
returns text language sql immutable set search_path = ''
as $$ select regexp_replace(coalesce(t, ''), '[^0-9]', '', 'g') $$;

create or replace function app.cpf_valido(c text)
returns boolean language plpgsql immutable set search_path = ''
as $$
declare d text := app.so_digitos(c); s integer; i integer; r integer;
begin
  if length(d) <> 11 or d ~ '^(.)\1{10}$' then return false; end if;
  s := 0; for i in 1..9 loop s := s + substr(d, i, 1)::int * (11 - i); end loop;
  r := (s * 10) % 11; if r = 10 then r := 0; end if;
  if r <> substr(d, 10, 1)::int then return false; end if;
  s := 0; for i in 1..10 loop s := s + substr(d, i, 1)::int * (12 - i); end loop;
  r := (s * 10) % 11; if r = 10 then r := 0; end if;
  return r = substr(d, 11, 1)::int;
end $$;

create or replace function app.cnpj_valido(c text)
returns boolean language plpgsql immutable set search_path = ''
as $$
declare d text := app.so_digitos(c); p1 int[] := array[5,4,3,2,9,8,7,6,5,4,3,2]; p2 int[] := array[6,5,4,3,2,9,8,7,6,5,4,3,2]; s int; i int; r int;
begin
  if length(d) <> 14 or d ~ '^(.)\1{13}$' then return false; end if;
  s := 0; for i in 1..12 loop s := s + substr(d, i, 1)::int * p1[i]; end loop;
  r := s % 11; r := case when r < 2 then 0 else 11 - r end;
  if r <> substr(d, 13, 1)::int then return false; end if;
  s := 0; for i in 1..13 loop s := s + substr(d, i, 1)::int * p2[i]; end loop;
  r := s % 11; r := case when r < 2 then 0 else 11 - r end;
  return r = substr(d, 14, 1)::int;
end $$;

create or replace function app.data_planilha(t text)
returns date language plpgsql immutable set search_path = ''
as $$
declare v text := btrim(coalesce(t, ''));
begin
  if v ~ '^\d{4}-\d{2}-\d{2}' then return left(v, 10)::date; end if;
  if v ~ '^\d{1,2}/\d{1,2}/\d{4}$' then return to_date(v, 'DD/MM/YYYY'); end if;
  return null;
exception when others then return null;
end $$;

create or replace function app.valor_planilha(t text)
returns numeric language plpgsql immutable set search_path = ''
as $$
declare v text := replace(btrim(coalesce(t, '')), 'R$', '');
begin
  v := btrim(v);
  if v ~ ',\d{1,2}$' then v := replace(replace(v, '.', ''), ',', '.'); end if;  -- 1.234,56
  if v !~ '^\d+(\.\d{1,2})?$' then return null; end if;
  return v::numeric;
exception when others then return null;
end $$;

create or replace function app.mascarar_documento(d text, t public.tipo_pessoa)
returns text language sql immutable set search_path = ''
as $$
  select case when d is null then null
    when t = 'PJ' and length(d) = 14 then substr(d,1,2)||'.'||substr(d,3,3)||'.'||substr(d,6,3)||'/'||substr(d,9,4)||'-'||substr(d,13,2)  -- CNPJ não é dado pessoal
    when length(d) = 11 then '***.' || substr(d, 4, 3) || '.' || substr(d, 7, 3) || '-**'
    else '***' end
$$;

-- ===== tabelas =====
create table public.locadores (
  id uuid primary key default gen_random_uuid(),
  tipo public.tipo_pessoa not null,
  nome text not null check (length(btrim(nome)) between 2 and 200),
  documento text not null unique check ((tipo = 'PF' and app.cpf_valido(documento)) or (tipo = 'PJ' and app.cnpj_valido(documento))),
  email text check (email is null or (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and length(email) <= 254)),
  telefone text check (telefone is null or telefone ~ '^[0-9]{10,11}$'),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table public.contratos (
  id uuid primary key default gen_random_uuid(),
  numero text not null check (length(btrim(numero)) between 1 and 30),
  processo text check (processo is null or length(processo) <= 60),
  locador_id uuid not null references public.locadores (id),
  imovel_descricao text not null check (length(btrim(imovel_descricao)) between 2 and 200),
  imovel_endereco text check (imovel_endereco is null or length(imovel_endereco) <= 300),
  unidade_ocupante_id uuid references public.unidades (id),
  inicio date not null,
  fim_original date not null,
  fim_vigencia date not null,
  valor_mensal numeric(12,2) not null check (valor_mensal > 0),
  dia_vencimento integer not null default 10 check (dia_vencimento between 1 and 28),
  fiscal_servidor_id uuid references public.servidores (id),
  indice_reajuste text check (indice_reajuste is null or length(indice_reajuste) <= 40),
  mes_database integer check (mes_database between 1 and 12),
  encerrado boolean not null default false,
  criado_por uuid references public.usuarios (id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint contratos_periodo check (fim_original >= inicio and fim_vigencia >= fim_original)
);
create unique index contratos_numero_uk on public.contratos (app.normalizar(numero));
create trigger contratos_atualizado before update on public.contratos for each row execute function app.tocar_atualizado_em();
create trigger locadores_atualizado before update on public.locadores for each row execute function app.tocar_atualizado_em();

create table public.aditivos (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos (id),
  numero integer not null,
  altera_prazo boolean not null default false,
  altera_valor boolean not null default false,
  novo_fim date,
  novo_valor numeric(12,2) check (novo_valor is null or novo_valor > 0),
  data_assinatura date,
  descricao text check (descricao is null or length(descricao) <= 2000),
  solicitacao_id uuid references public.solicitacoes (id),
  criado_em timestamptz not null default now(),
  unique (contrato_id, numero),
  constraint aditivos_coerente check ((altera_prazo = (novo_fim is not null)) and (altera_valor = (novo_valor is not null)) and (altera_prazo or altera_valor))
);

create table public.contrato_documentos (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos (id),
  aditivo_id uuid references public.aditivos (id),
  nome text not null check (length(nome) between 1 and 120),
  path text not null unique,
  tamanho integer not null check (tamanho between 1 and 31457280),
  enviado_por uuid not null references public.usuarios (id),
  enviado_em timestamptz not null default now()
);

create table public.alugueis (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos (id),
  competencia date not null check (extract(day from competencia) = 1),
  valor numeric(12,2) not null check (valor > 0),
  vencimento date not null,
  pago_em date,
  valor_pago numeric(12,2) check (valor_pago is null or valor_pago > 0),
  registrado_por uuid references public.usuarios (id),
  registrado_em timestamptz,
  unique (contrato_id, competencia),
  constraint alugueis_pagamento check ((pago_em is null) = (valor_pago is null))
);
create index alugueis_venc_idx on public.alugueis (vencimento) where pago_em is null;

create table public.contrato_historico (
  id bigint generated always as identity primary key,
  contrato_id uuid not null references public.contratos (id),
  em timestamptz not null default now(),
  ator_id uuid references public.usuarios (id),
  acao text not null,
  detalhes jsonb not null default '{}'::jsonb
);
create trigger contrato_historico_imutavel before update or delete on public.contrato_historico for each row execute function app.auditoria_imutavel();
create trigger contrato_documentos_sem_delete before delete on public.contrato_documentos for each row execute function app.auditoria_imutavel();

do $$
declare t text;
begin
  foreach t in array array['locadores', 'contratos', 'aditivos', 'contrato_documentos', 'alugueis', 'contrato_historico'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    if t <> 'contrato_historico' then
      execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()', t || '_auditoria', t);
    end if;
  end loop;
end $$;
-- locadores: só colunas não sensíveis pela API; documento/contato só via RPC (mascarado)
grant select (id, tipo, nome) on public.locadores to authenticated;
grant select on public.contratos, public.aditivos, public.contrato_documentos, public.alugueis, public.contrato_historico to authenticated;
create policy locadores_ler on public.locadores for select to authenticated using ((select app.acesso_contratos()));
create policy contratos_ler on public.contratos for select to authenticated using ((select app.acesso_contratos()));
create policy aditivos_ler on public.aditivos for select to authenticated using ((select app.acesso_contratos()));
create policy contrato_docs_ler on public.contrato_documentos for select to authenticated using ((select app.acesso_contratos()));
create policy alugueis_ler on public.alugueis for select to authenticated using ((select app.acesso_contratos()));
create policy contrato_hist_ler on public.contrato_historico for select to authenticated using ((select app.acesso_contratos()));

create or replace function app.historico_contrato(p_contrato uuid, p_acao text, p_detalhes jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = ''
as $$ insert into public.contrato_historico (contrato_id, ator_id, acao, detalhes) values (p_contrato, auth.uid(), p_acao, coalesce(p_detalhes, '{}'::jsonb)) $$;

-- aluguéis mês a mês até o fim da vigência efetiva (não recria os que já existem)
create or replace function app.gerar_alugueis(p_contrato uuid)
returns integer language plpgsql security definer set search_path = ''
as $$
declare c public.contratos; m date; n integer := 0;
begin
  select * into c from public.contratos where id = p_contrato;
  for m in select generate_series(date_trunc('month', c.inicio), date_trunc('month', c.fim_vigencia), interval '1 month')::date loop
    insert into public.alugueis (contrato_id, competencia, valor, vencimento)
    values (c.id, m, c.valor_mensal, make_date(extract(year from m)::int, extract(month from m)::int, c.dia_vencimento))
    on conflict (contrato_id, competencia) do nothing;
    if found then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- ===== locador: mascarado por padrão; completo só com permissão específica (e auditado) =====
create or replace function public.locador_dados(p_locador uuid, p_completo boolean default false)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare l public.locadores; v_pode boolean := app.sessao_ok() and app.tem_modulo('locadores_dados');
begin
  if not app.acesso_contratos() then perform app.erro('Acesso não permitido.', '42501'); end if;
  select * into l from public.locadores where id = p_locador;
  if not found then return null; end if;
  if p_completo and not v_pode then perform app.erro('Exibir CPF e contato completos exige permissão específica.', '42501'); end if;
  if p_completo then
    perform app.registrar_evento('ver_dados_locador', 'locadores', l.id::text, null, jsonb_build_object('campos', 'documento,email,telefone'));
    return jsonb_build_object('id', l.id, 'tipo', l.tipo, 'nome', l.nome, 'documento', l.documento, 'email', l.email, 'telefone', l.telefone, 'mascarado', false, 'pode_ver_completo', true);
  end if;
  return jsonb_build_object('id', l.id, 'tipo', l.tipo, 'nome', l.nome, 'documento', app.mascarar_documento(l.documento, l.tipo),
    'email', case when l.email is null then null else left(l.email, 2) || '***@' || split_part(l.email, '@', 2) end,
    'telefone', case when l.telefone is null then null else '(' || left(l.telefone, 2) || ') *****-' || right(l.telefone, 4) end,
    'mascarado', true, 'pode_ver_completo', v_pode);
end $$;

-- ===== cadastro manual (registro novo: sem aprovação) =====
create or replace function app.obter_locador(p jsonb)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_doc text := app.so_digitos(p ->> 'documento'); v_id uuid;
begin
  select id into v_id from public.locadores where documento = v_doc;
  if v_id is not null then return v_id; end if;  -- já cadastrado: não sobrescreve (alterar passa por aprovação)
  insert into public.locadores (tipo, nome, documento, email, telefone)
  values ((p ->> 'tipo')::public.tipo_pessoa, btrim(p ->> 'nome'), v_doc, nullif(lower(btrim(coalesce(p ->> 'email', ''))), ''),
          nullif(app.so_digitos(p ->> 'telefone'), ''))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.criar_contrato(p_dados jsonb, p_locador jsonb)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_fim date := (p_dados ->> 'fim')::date;
begin
  if not app.acesso_contratos() then perform app.erro('Sem permissão para contratos.', '42501'); end if;
  insert into public.contratos (numero, processo, locador_id, imovel_descricao, imovel_endereco, unidade_ocupante_id, inicio, fim_original, fim_vigencia,
                                valor_mensal, dia_vencimento, fiscal_servidor_id, indice_reajuste, mes_database, criado_por)
  values (btrim(p_dados ->> 'numero'), nullif(btrim(coalesce(p_dados ->> 'processo', '')), ''), app.obter_locador(p_locador), btrim(p_dados ->> 'imovel_descricao'),
          nullif(btrim(coalesce(p_dados ->> 'imovel_endereco', '')), ''), nullif(p_dados ->> 'unidade_ocupante_id', '')::uuid, (p_dados ->> 'inicio')::date,
          v_fim, v_fim, (p_dados ->> 'valor_mensal')::numeric, coalesce((p_dados ->> 'dia_vencimento')::int, 10),
          nullif(p_dados ->> 'fiscal_servidor_id', '')::uuid, nullif(btrim(coalesce(p_dados ->> 'indice_reajuste', '')), ''), nullif(p_dados ->> 'mes_database', '')::int, auth.uid())
  returning id into v_id;
  perform app.gerar_alugueis(v_id);
  perform app.historico_contrato(v_id, 'cadastrado');
  return v_id;
exception
  when unique_violation then perform app.erro('Já existe contrato com esse número ou locador com esse documento.', '23505');
  when check_violation then perform app.erro('Dados inválidos (confira CPF/CNPJ, datas e valor).', '23514');
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or not_null_violation then perform app.erro('Dados inválidos.', '22023');
end $$;

-- ===== pagamento de aluguel: sem aprovação (prompt 6.6/aprovações) =====
create or replace function public.registrar_pagamento_aluguel(p_id uuid, p_data date, p_valor numeric)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.alugueis;
begin
  if not app.acesso_contratos() then perform app.erro('Sem permissão para contratos.', '42501'); end if;
  select * into a from public.alugueis where id = p_id for update;
  if not found then perform app.erro('Aluguel não encontrado.', 'P0002'); end if;
  if a.pago_em is not null then perform app.erro('Pagamento já registrado.', '22023'); end if;
  if p_data is null or p_data > current_date then perform app.erro('Data de pagamento inválida.', '22023'); end if;
  if p_valor is null or p_valor <= 0 then perform app.erro('Valor inválido.', '22023'); end if;
  update public.alugueis set pago_em = p_data, valor_pago = p_valor, registrado_por = auth.uid(), registrado_em = now() where id = p_id;
  perform app.historico_contrato(a.contrato_id, 'pagamento', jsonb_build_object('competencia', to_char(a.competencia, 'MM/YYYY'), 'valor', p_valor));
end $$;

-- desfazer registro errado: só Secretária/Admin, com motivo (auditado)
create or replace function public.desfazer_pagamento_aluguel(p_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.alugueis;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if length(btrim(coalesce(p_motivo, ''))) < 5 then perform app.erro('Informe o motivo.', '22023'); end if;
  select * into a from public.alugueis where id = p_id for update;
  if not found or a.pago_em is null then perform app.erro('Pagamento não encontrado.', 'P0002'); end if;
  update public.alugueis set pago_em = null, valor_pago = null, registrado_por = null, registrado_em = null where id = p_id;
  perform app.historico_contrato(a.contrato_id, 'pagamento_desfeito', jsonb_build_object('competencia', to_char(a.competencia, 'MM/YYYY'), 'motivo', p_motivo));
end $$;

-- ===== documentos (PDF do contrato e dos aditivos) =====
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('contratos', 'contratos', false, 31457280, array['application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
create policy contratos_doc_enviar on storage.objects for insert to authenticated with check (
  bucket_id = 'contratos' and (select app.acesso_contratos()) and name ~ '^contratos/[0-9a-f-]{36}/[0-9a-f-]{36}\.pdf$'
);
create policy contratos_doc_ler on storage.objects for select to authenticated using (bucket_id = 'contratos' and (select app.acesso_contratos()));

create or replace function public.registrar_documento_contrato(p_contrato uuid, p_path text, p_nome text, p_tamanho integer, p_aditivo uuid default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not app.acesso_contratos() then perform app.erro('Sem permissão para contratos.', '42501'); end if;
  if p_path not like 'contratos/' || p_contrato::text || '/%'
     or not exists (select 1 from storage.objects o where o.bucket_id = 'contratos' and o.name = p_path) then
    perform app.erro('Arquivo inválido.', '22023');
  end if;
  if p_aditivo is not null and not exists (select 1 from public.aditivos where id = p_aditivo and contrato_id = p_contrato) then
    perform app.erro('Aditivo inválido.', '22023');
  end if;
  insert into public.contrato_documentos (contrato_id, aditivo_id, nome, path, tamanho, enviado_por)
  values (p_contrato, p_aditivo, left(regexp_replace(coalesce(p_nome, 'documento.pdf'), '[^A-Za-zÀ-ÿ0-9 ._()-]', '_', 'g'), 120), p_path, p_tamanho, auth.uid())
  returning id into v_id;
  perform app.historico_contrato(p_contrato, 'documento', jsonb_build_object('nome', left(p_nome, 120)));
  return v_id;
end $$;

-- ===== importação inicial por planilha (~60 contratos): prévia → tudo ou nada =====
create or replace function app.validar_planilha_contratos(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
declare r jsonb; n integer; v_doc text; v_tipo text; v_ini date; v_fim date;
begin
  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then perform app.erro('Planilha sem linhas.', '22023'); end if;
  if jsonb_array_length(p_linhas) > 1000 then perform app.erro('Máximo de 1000 contratos por importação.', '22023'); end if;
  for r in select * from jsonb_array_elements(p_linhas) loop
    n := coalesce((r ->> 'linha')::int, 0);
    if btrim(coalesce(r ->> 'numero', '')) = '' then return query select n, 'numero', 'Número do contrato vazio.';
    elsif exists (select 1 from public.contratos c where app.normalizar(c.numero) = app.normalizar(r ->> 'numero')) then return query select n, 'numero', 'Contrato já cadastrado.';
    elsif (select count(*) from jsonb_array_elements(p_linhas) x where app.normalizar(x ->> 'numero') = app.normalizar(r ->> 'numero')) > 1 then return query select n, 'numero', 'Número duplicado na planilha.';
    end if;
    if length(btrim(coalesce(r ->> 'locador_nome', ''))) < 2 then return query select n, 'locador_nome', 'Nome do locador vazio.'; end if;
    v_tipo := upper(btrim(coalesce(r ->> 'locador_tipo', '')));
    v_doc := app.so_digitos(r ->> 'locador_documento');
    if v_tipo not in ('PF', 'PJ') then return query select n, 'locador_tipo', 'Tipo do locador deve ser PF ou PJ.';
    elsif (v_tipo = 'PF' and not app.cpf_valido(v_doc)) or (v_tipo = 'PJ' and not app.cnpj_valido(v_doc)) then
      return query select n, 'locador_documento', case when v_tipo = 'PF' then 'CPF inválido.' else 'CNPJ inválido.' end;
    end if;
    if nullif(btrim(coalesce(r ->> 'locador_email', '')), '') is not null and (r ->> 'locador_email') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return query select n, 'locador_email', 'E-mail inválido.'; end if;
    if nullif(app.so_digitos(r ->> 'locador_telefone'), '') is not null and app.so_digitos(r ->> 'locador_telefone') !~ '^[0-9]{10,11}$' then return query select n, 'locador_telefone', 'Telefone inválido (DDD + número).'; end if;
    if length(btrim(coalesce(r ->> 'imovel_descricao', ''))) < 2 then return query select n, 'imovel_descricao', 'Descrição do imóvel vazia.'; end if;
    if nullif(btrim(coalesce(r ->> 'unidade', '')), '') is not null and not exists (select 1 from public.unidades u where app.normalizar(u.sigla) = app.normalizar(r ->> 'unidade')) then
      return query select n, 'unidade', 'Unidade inexistente.';
    end if;
    v_ini := app.data_planilha(r ->> 'inicio'); v_fim := app.data_planilha(r ->> 'fim');
    if v_ini is null then return query select n, 'inicio', 'Data de início inválida (use dd/mm/aaaa).'; end if;
    if v_fim is null then return query select n, 'fim', 'Data de fim inválida (use dd/mm/aaaa).';
    elsif v_ini is not null and v_fim < v_ini then return query select n, 'fim', 'Fim antes do início.'; end if;
    if app.valor_planilha(r ->> 'valor_mensal') is null or app.valor_planilha(r ->> 'valor_mensal') <= 0 then return query select n, 'valor_mensal', 'Valor mensal inválido.'; end if;
    if nullif(btrim(coalesce(r ->> 'dia_vencimento', '')), '') is not null and (btrim(r ->> 'dia_vencimento') !~ '^\d{1,2}$' or (r ->> 'dia_vencimento')::int not between 1 and 28) then
      return query select n, 'dia_vencimento', 'Dia de vencimento deve ser de 1 a 28.';
    end if;
    if nullif(btrim(coalesce(r ->> 'fiscal_matricula', '')), '') is not null and not exists (select 1 from public.servidores s where app.matricula_chave(s.matricula) = app.matricula_chave(r ->> 'fiscal_matricula')) then
      return query select n, 'fiscal_matricula', 'Fiscal não encontrado pela matrícula.';
    end if;
    if nullif(btrim(coalesce(r ->> 'mes_database', '')), '') is not null and (btrim(r ->> 'mes_database') !~ '^\d{1,2}$' or (r ->> 'mes_database')::int not between 1 and 12) then
      return query select n, 'mes_database', 'Mês da data-base deve ser de 1 a 12.';
    end if;
  end loop;
end $$;

create or replace function public.importar_contratos_previa(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not app.acesso_contratos() then perform app.erro('Sem permissão para contratos.', '42501'); end if;
  return query select * from app.validar_planilha_contratos(p_linhas) order by 1, 2;
end $$;

create or replace function public.importar_contratos(p_linhas jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare r jsonb; v_id uuid; n integer := 0;
begin
  if not app.acesso_contratos() then perform app.erro('Sem permissão para contratos.', '42501'); end if;
  if exists (select 1 from app.validar_planilha_contratos(p_linhas)) then perform app.erro('A planilha tem erros. Corrija e confira a prévia antes de importar.', '22023'); end if;
  perform set_config('app.origem', 'importacao_contratos', true);
  for r in select * from jsonb_array_elements(p_linhas) loop
    insert into public.contratos (numero, processo, locador_id, imovel_descricao, imovel_endereco, unidade_ocupante_id, inicio, fim_original, fim_vigencia,
                                  valor_mensal, dia_vencimento, fiscal_servidor_id, indice_reajuste, mes_database, criado_por)
    values (btrim(r ->> 'numero'), nullif(btrim(coalesce(r ->> 'processo', '')), ''),
            app.obter_locador(jsonb_build_object('tipo', upper(btrim(r ->> 'locador_tipo')), 'nome', r ->> 'locador_nome', 'documento', r ->> 'locador_documento',
                                                 'email', r ->> 'locador_email', 'telefone', r ->> 'locador_telefone')),
            btrim(r ->> 'imovel_descricao'), nullif(btrim(coalesce(r ->> 'imovel_endereco', '')), ''),
            (select u.id from public.unidades u where app.normalizar(u.sigla) = app.normalizar(r ->> 'unidade')),
            app.data_planilha(r ->> 'inicio'), app.data_planilha(r ->> 'fim'), app.data_planilha(r ->> 'fim'), app.valor_planilha(r ->> 'valor_mensal'),
            coalesce(nullif(btrim(coalesce(r ->> 'dia_vencimento', '')), '')::int, 10),
            (select s.id from public.servidores s where app.matricula_chave(s.matricula) = app.matricula_chave(r ->> 'fiscal_matricula') limit 1),
            nullif(btrim(coalesce(r ->> 'indice_reajuste', '')), ''), nullif(btrim(coalesce(r ->> 'mes_database', '')), '')::int, auth.uid())
    returning id into v_id;
    perform app.gerar_alugueis(v_id);
    perform app.historico_contrato(v_id, 'importado');
    n := n + 1;
  end loop;
  return n;
end $$;

grant execute on function public.locador_dados(uuid, boolean) to authenticated;
grant execute on function public.criar_contrato(jsonb, jsonb) to authenticated;
grant execute on function public.registrar_pagamento_aluguel(uuid, date, numeric) to authenticated;
grant execute on function public.desfazer_pagamento_aluguel(uuid, text) to authenticated;
grant execute on function public.registrar_documento_contrato(uuid, text, text, integer, uuid) to authenticated;
grant execute on function public.importar_contratos_previa(jsonb) to authenticated;
grant execute on function public.importar_contratos(jsonb) to authenticated;
grant execute on function app.matricula_chave(text), app.cpf_valido(text), app.cnpj_valido(text) to authenticated;

-- ===================== 20261129000200_fase4_ucs_faturas.sql =====================
-- Fase 4 · unidades consumidoras e faturas de água/energia (6.6)
-- Sem anexo de fatura/comprovante. Pagamento sem aprovação.

create or replace function app.acesso_ucs()
returns boolean language sql stable security definer set search_path = ''
as $$ select app.sessao_ok() and (app.tem_modulo('contratos') or app.tem_modulo('unidades_consumidoras')) $$;
grant execute on function app.acesso_ucs() to authenticated;

create table public.unidades_consumidoras (
  id uuid primary key default gen_random_uuid(),
  fornecedor public.fornecedor_uc not null,
  numero text not null check (btrim(numero) ~ '^[0-9A-Za-z./-]{3,30}$'),
  contrato_id uuid not null references public.contratos (id),
  descricao text check (descricao is null or length(descricao) <= 120),
  ativa boolean not null default true,
  criado_em timestamptz not null default now(),
  unique (fornecedor, numero)
);

create table public.faturas (
  id uuid primary key default gen_random_uuid(),
  uc_id uuid not null references public.unidades_consumidoras (id),
  competencia date not null check (extract(day from competencia) = 1),
  consumo numeric(12,2) check (consumo is null or consumo >= 0),
  valor numeric(12,2) not null check (valor > 0),
  vencimento date not null,
  pago_em date,
  registrado_por uuid references public.usuarios (id),
  origem text not null default 'manual' check (origem in ('manual', 'importacao')),
  criado_por uuid references public.usuarios (id),
  criado_em timestamptz not null default now(),
  unique (uc_id, competencia)
);
create index faturas_comp_idx on public.faturas (competencia);

do $$
declare t text;
begin
  foreach t in array array['unidades_consumidoras', 'faturas'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()', t || '_auditoria', t);
  end loop;
end $$;
create policy ucs_ler on public.unidades_consumidoras for select to authenticated using ((select app.acesso_ucs()));
create policy faturas_ler on public.faturas for select to authenticated using ((select app.acesso_ucs()));

create or replace function public.criar_uc(p_fornecedor public.fornecedor_uc, p_numero text, p_contrato uuid, p_descricao text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not app.acesso_contratos() then perform app.erro('Sem permissão para contratos.', '42501'); end if;
  insert into public.unidades_consumidoras (fornecedor, numero, contrato_id, descricao)
  values (p_fornecedor, btrim(p_numero), p_contrato, nullif(btrim(coalesce(p_descricao, '')), ''))
  returning id into v_id;
  perform app.historico_contrato(p_contrato, 'uc_vinculada', jsonb_build_object('fornecedor', p_fornecedor, 'numero', btrim(p_numero)));
  return v_id;
exception
  when unique_violation then perform app.erro('Unidade consumidora já cadastrada.', '23505');
  when check_violation then perform app.erro('Número da unidade consumidora inválido.', '23514');
  when foreign_key_violation then perform app.erro('Contrato não encontrado.', '23503');
end $$;

-- lançamento manual (registro novo); corrigir lançamento existente = só se ainda não pago
create or replace function public.lancar_fatura(p_uc uuid, p_competencia date, p_valor numeric, p_vencimento date, p_consumo numeric default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not app.acesso_ucs() then perform app.erro('Sem permissão para faturas.', '42501'); end if;
  insert into public.faturas (uc_id, competencia, consumo, valor, vencimento, criado_por)
  values (p_uc, date_trunc('month', p_competencia)::date, p_consumo, p_valor, p_vencimento, auth.uid())
  returning id into v_id;
  return v_id;
exception
  when unique_violation then perform app.erro('Já existe fatura dessa unidade consumidora nessa competência.', '23505');
  when check_violation or not_null_violation then perform app.erro('Dados da fatura inválidos.', '23514');
  when foreign_key_violation then perform app.erro('Unidade consumidora não encontrada.', '23503');
end $$;

create or replace function public.registrar_pagamento_fatura(p_id uuid, p_data date)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not app.acesso_ucs() then perform app.erro('Sem permissão para faturas.', '42501'); end if;
  if p_data is null or p_data > current_date then perform app.erro('Data de pagamento inválida.', '22023'); end if;
  update public.faturas set pago_em = p_data, registrado_por = auth.uid() where id = p_id and pago_em is null;
  if not found then perform app.erro('Fatura não encontrada ou já paga.', 'P0002'); end if;
end $$;

-- competência: mm/aaaa ou data ISO (célula de data do Excel)
create or replace function app.competencia_planilha(t text)
returns date language plpgsql immutable set search_path = ''
as $$
declare v text := btrim(coalesce(t, ''));
begin
  if v ~ '^\d{1,2}/\d{4}$' then return to_date('01/' || v, 'DD/MM/YYYY'); end if;
  if v ~ '^\d{4}-\d{2}(-\d{2})?' then return date_trunc('month', to_date(left(v, 7) || '-01', 'YYYY-MM-DD'))::date; end if;
  return null;
exception when others then return null;
end $$;

-- importação de faturas: prévia → tudo ou nada. Colunas provisórias (modelo oficial pendente, seção 9)
create or replace function app.validar_planilha_faturas(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
declare r jsonb; n integer; v_forn text; v_uc uuid; v_comp date;
begin
  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then perform app.erro('Planilha sem linhas.', '22023'); end if;
  if jsonb_array_length(p_linhas) > 3000 then perform app.erro('Máximo de 3000 faturas por importação.', '22023'); end if;
  for r in select * from jsonb_array_elements(p_linhas) loop
    n := coalesce((r ->> 'linha')::int, 0);
    v_forn := lower(btrim(coalesce(r ->> 'fornecedor', '')));
    v_forn := case v_forn when 'iguá' then 'igua' else v_forn end;
    v_uc := null;
    if v_forn not in ('energisa', 'igua', 'cercos') then return query select n, 'fornecedor', 'Fornecedor deve ser Energisa, Iguá ou Cercos.';
    else
      select u.id into v_uc from public.unidades_consumidoras u where u.fornecedor = v_forn::public.fornecedor_uc and u.numero = btrim(coalesce(r ->> 'uc', ''));
      if v_uc is null then return query select n, 'uc', 'Unidade consumidora não cadastrada.'; end if;
    end if;
    v_comp := app.competencia_planilha(r ->> 'competencia');
    if v_comp is null then return query select n, 'competencia', 'Competência inválida (use mm/aaaa).';
    elsif v_uc is not null and exists (select 1 from public.faturas f where f.uc_id = v_uc and f.competencia = v_comp) then
      return query select n, 'competencia', 'Fatura dessa competência já lançada.';
    elsif (select count(*) from jsonb_array_elements(p_linhas) x where lower(btrim(x ->> 'fornecedor')) = lower(btrim(r ->> 'fornecedor'))
              and btrim(x ->> 'uc') = btrim(r ->> 'uc') and app.competencia_planilha(x ->> 'competencia') = v_comp) > 1 then
      return query select n, 'competencia', 'Fatura repetida na planilha.';
    end if;
    if app.valor_planilha(r ->> 'valor') is null or app.valor_planilha(r ->> 'valor') <= 0 then return query select n, 'valor', 'Valor inválido.'; end if;
    if nullif(btrim(coalesce(r ->> 'consumo', '')), '') is not null and app.valor_planilha(r ->> 'consumo') is null then return query select n, 'consumo', 'Consumo inválido.'; end if;
    if app.data_planilha(r ->> 'vencimento') is null then return query select n, 'vencimento', 'Vencimento inválido (use dd/mm/aaaa).'; end if;
    if nullif(btrim(coalesce(r ->> 'pago_em', '')), '') is not null and (app.data_planilha(r ->> 'pago_em') is null or app.data_planilha(r ->> 'pago_em') > current_date) then
      return query select n, 'pago_em', 'Data de pagamento inválida.';
    end if;
  end loop;
end $$;

create or replace function public.importar_faturas_previa(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not app.acesso_ucs() then perform app.erro('Sem permissão para faturas.', '42501'); end if;
  return query select * from app.validar_planilha_faturas(p_linhas) order by 1, 2;
end $$;

create or replace function public.importar_faturas(p_linhas jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare r jsonb; n integer := 0; v_forn text;
begin
  if not app.acesso_ucs() then perform app.erro('Sem permissão para faturas.', '42501'); end if;
  if exists (select 1 from app.validar_planilha_faturas(p_linhas)) then perform app.erro('A planilha tem erros. Corrija e confira a prévia antes de importar.', '22023'); end if;
  perform set_config('app.origem', 'importacao_faturas', true);
  for r in select * from jsonb_array_elements(p_linhas) loop
    v_forn := lower(btrim(r ->> 'fornecedor')); v_forn := case v_forn when 'iguá' then 'igua' else v_forn end;
    insert into public.faturas (uc_id, competencia, consumo, valor, vencimento, pago_em, registrado_por, origem, criado_por)
    select u.id, app.competencia_planilha(r ->> 'competencia'), app.valor_planilha(r ->> 'consumo'), app.valor_planilha(r ->> 'valor'),
           app.data_planilha(r ->> 'vencimento'), app.data_planilha(r ->> 'pago_em'),
           case when app.data_planilha(r ->> 'pago_em') is not null then auth.uid() end, 'importacao', auth.uid()
      from public.unidades_consumidoras u where u.fornecedor = v_forn::public.fornecedor_uc and u.numero = btrim(r ->> 'uc');
    n := n + 1;
  end loop;
  return n;
end $$;

-- tela de UCs: KPIs e lista da competência (protótipo UnidadesConsumidoras)
create or replace function public.ucs_competencia(p_competencia date, p_fornecedor public.fornecedor_uc default null)
returns table (uc_id uuid, fornecedor public.fornecedor_uc, numero text, descricao text, contrato_id uuid, contrato_numero text, imovel text,
               fatura_id uuid, consumo numeric, valor numeric, vencimento date, pago_em date, situacao text)
language plpgsql stable security definer set search_path = ''
as $$
declare v_comp date := date_trunc('month', coalesce(p_competencia, current_date))::date;
begin
  if not app.acesso_ucs() then perform app.erro('Sem permissão para faturas.', '42501'); end if;
  return query
    select u.id, u.fornecedor, u.numero, u.descricao, c.id, c.numero, c.imovel_descricao, f.id, f.consumo, f.valor, f.vencimento, f.pago_em,
           case when f.id is null then 'sem_lancamento' when f.pago_em is not null then 'paga'
                when f.vencimento < current_date then 'atrasada' else 'pendente' end
      from public.unidades_consumidoras u
      join public.contratos c on c.id = u.contrato_id
      left join public.faturas f on f.uc_id = u.id and f.competencia = v_comp
     where u.ativa and (p_fornecedor is null or u.fornecedor = p_fornecedor)
     order by u.fornecedor, c.numero, u.numero;
end $$;

grant execute on function public.criar_uc(public.fornecedor_uc, text, uuid, text) to authenticated;
grant execute on function public.lancar_fatura(uuid, date, numeric, date, numeric) to authenticated;
grant execute on function public.registrar_pagamento_fatura(uuid, date) to authenticated;
grant execute on function public.importar_faturas_previa(jsonb) to authenticated;
grant execute on function public.importar_faturas(jsonb) to authenticated;
grant execute on function public.ucs_competencia(date, public.fornecedor_uc) to authenticated;

-- ===================== 20261129000300_fase4_renovacao_painel.sql =====================
-- Fase 4 · renovação automática (6.17), avisos de vencimento (6.10), painel e busca

alter table public.demandas add column contrato_id uuid references public.contratos (id);
create index demandas_contrato_idx on public.demandas (contrato_id) where contrato_id is not null;

-- uma renovação por vigência (fim efetivo): aditivo de prazo gera nova vigência → nova renovação no futuro
create table public.contrato_renovacoes (
  contrato_id uuid not null references public.contratos (id),
  fim_vigencia date not null,
  demanda_id uuid references public.demandas (id),
  criada_em timestamptz not null default now(),
  primary key (contrato_id, fim_vigencia)
);
create table public.contrato_avisos (
  contrato_id uuid not null references public.contratos (id),
  fim_vigencia date not null,
  dias integer not null,
  em timestamptz not null default now(),
  primary key (contrato_id, fim_vigencia, dias)
);
do $$
declare t text;
begin
  foreach t in array array['contrato_renovacoes', 'contrato_avisos'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;
create policy contrato_renov_ler on public.contrato_renovacoes for select to authenticated using ((select app.acesso_contratos()));
create policy contrato_avisos_ler on public.contrato_avisos for select to authenticated using ((select app.acesso_contratos()));

insert into public.configuracoes (chave, valor, descricao) values
  ('contratos.dias_renovacao', '90', 'Dias antes do fim da vigência para criar a demanda de renovação'),
  ('contratos.dias_aviso_vencimento', '[90, 60, 30, 15]', 'Dias antes do fim da vigência em que quem tem o módulo contratos é avisado'),
  ('contratos.checklist_renovacao', '["Certidões do locador", "Laudo de avaliação", "Manifestação de interesse", "Parecer jurídico"]',
   'Checklist de documentos da demanda de renovação (provisório — validar com a SEMFAZ)'),
  ('contratos.prazo_renovacao_dias_uteis', '30', 'Prazo (dias úteis) da demanda de renovação')
on conflict (chave) do nothing;

-- usuários ativos com um módulo (pacote do perfil ∪ extras) — para avisos de rotinas sem sessão
create or replace function app.usuarios_com_modulo(p_codigo text)
returns setof uuid language sql stable security definer set search_path = ''
as $$
  select u.id from public.usuarios u join public.servidores s on s.id = u.servidor_id
   where u.ativo and s.situacao = 'ativo'
     and (exists (select 1 from public.pacotes_padrao pp where pp.perfil = u.perfil and pp.modulo_codigo = p_codigo)
          or exists (select 1 from public.usuario_modulos_extras e where e.usuario_id = u.id and e.modulo_codigo = p_codigo))
$$;

-- cria a demanda de renovação (uma vez por vigência)
create or replace function app.criar_renovacao(p_contrato uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  c public.contratos; v_id uuid; v_unidade uuid; v_criador uuid; v_item text; i integer := 0; v_u uuid;
  v_prazo integer := coalesce((select (valor)::int from public.configuracoes where chave = 'contratos.prazo_renovacao_dias_uteis'), 30);
begin
  select * into c from public.contratos where id = p_contrato;
  insert into public.contrato_renovacoes (contrato_id, fim_vigencia) values (c.id, c.fim_vigencia) on conflict do nothing;
  if not found then return null; end if;  -- já criada para esta vigência
  v_unidade := coalesce((select unidade_id from public.servidores where id = c.fiscal_servidor_id), c.unidade_ocupante_id,
                        (select id from public.unidades where unidade_pai_id is null and ativa order by ordem limit 1));
  v_criador := coalesce(app.usuario_do_servidor(c.fiscal_servidor_id), c.criado_por,
                        (select u.id from public.usuarios u where u.ativo and u.perfil in ('secretaria', 'administrador') order by u.perfil limit 1));
  insert into public.demandas (titulo, descricao, origem, unidade_id, prioridade, prazo, criado_por, contrato_id)
  values ('Renovação do contrato nº ' || c.numero, 'Demanda criada automaticamente: a vigência do contrato termina em ' || to_char(c.fim_vigencia, 'DD/MM/YYYY') || '.',
          'outra', v_unidade, 'alta', least(public.somar_dias_uteis(current_date, v_prazo), c.fim_vigencia), v_criador, c.id)
  returning id into v_id;
  update public.contrato_renovacoes set demanda_id = v_id where contrato_id = c.id and fim_vigencia = c.fim_vigencia;
  perform app.historico(v_id, 'criada', jsonb_build_object('automatica', 'renovacao'));
  if c.fiscal_servidor_id is not null then perform app.definir_titulares(v_id, array[c.fiscal_servidor_id]); end if;
  for v_item in select jsonb_array_elements_text(coalesce((select valor from public.configuracoes where chave = 'contratos.checklist_renovacao'), '[]'::jsonb)) loop
    insert into public.demanda_checklist (demanda_id, texto, ordem) values (v_id, left(v_item, 300), i); i := i + 1;
  end loop;
  -- quem tem a permissão de contratos acompanha a demanda
  for v_u in select app.usuarios_com_modulo('contratos') loop
    insert into public.demanda_participantes (demanda_id, usuario_id) values (v_id, v_u) on conflict do nothing;
    perform app.notificar(v_u, 'contrato_renovacao', 'Renovação de contrato', 'Renovação do contrato nº ' || c.numero, '/demandas/ficha?id=' || v_id);
  end loop;
  perform app.historico_contrato(c.id, 'renovacao_criada', jsonb_build_object('demanda', v_id));
  return v_id;
end $$;

create or replace function app.rotina_contratos()
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  c public.contratos; v_dias integer; v_marco integer; v_u uuid; n integer := 0;
  v_renov integer := coalesce((select (valor)::int from public.configuracoes where chave = 'contratos.dias_renovacao'), 90);
  v_marcos integer[] := coalesce((select array(select jsonb_array_elements_text(valor)::int) from public.configuracoes where chave = 'contratos.dias_aviso_vencimento'), array[90, 60, 30, 15]);
begin
  for c in select * from public.contratos where not encerrado and fim_vigencia >= current_date loop
    v_dias := c.fim_vigencia - current_date;
    if v_dias <= v_renov and app.criar_renovacao(c.id) is not null then n := n + 1; end if;
    -- aviso no menor marco já alcançado, uma vez por marco
    select min(m) into v_marco from unnest(v_marcos) m where v_dias <= m;
    if v_marco is not null then
      insert into public.contrato_avisos (contrato_id, fim_vigencia, dias) values (c.id, c.fim_vigencia, v_marco) on conflict do nothing;
      if found then
        for v_u in select app.usuarios_com_modulo('contratos') union select app.usuario_do_servidor(c.fiscal_servidor_id) loop
          continue when v_u is null;
          perform app.notificar(v_u, 'contrato_vencendo', 'Contrato vencendo',
            'Contrato nº ' || c.numero || ' termina em ' || to_char(c.fim_vigencia, 'DD/MM/YYYY') || ' (' || v_dias || ' dias)', '/contratos/ficha?id=' || c.id);
        end loop;
      end if;
    end if;
  end loop;
  return n;
end $$;

create or replace function app.rotinas_diarias_demandas()
returns void language plpgsql security definer set search_path = ''
as $$ begin perform app.gerar_ocorrencias(); perform app.aplicar_substituicoes(); perform app.rotina_contratos(); perform app.avisar_prazos(); end $$;
revoke execute on function app.rotinas_diarias_demandas() from public, anon, authenticated;
revoke execute on function app.rotina_contratos() from public, anon, authenticated;
revoke execute on function app.criar_renovacao(uuid) from public, anon, authenticated;

-- aditivo de prazo aprovado: avisa na demanda de renovação aberta
create or replace function app.renovacao_registrada(p_contrato uuid, p_novo_fim date)
returns void language plpgsql security definer set search_path = ''
as $$
declare r record; v_s uuid; v_u uuid;
begin
  for r in select d.id, d.numero, d.titulo from public.demandas d where d.contrato_id = p_contrato and d.status not in ('concluida', 'recusada', 'cancelada') loop
    perform app.historico(r.id, 'renovacao_registrada', jsonb_build_object('novo_fim', to_char(p_novo_fim, 'DD/MM/YYYY')));
    for v_u in select app.usuario_do_servidor(servidor_id) from public.demanda_responsaveis where demanda_id = r.id and ativo
               union select usuario_id from public.demanda_participantes where demanda_id = r.id loop
      continue when v_u is null;
      perform app.notificar(v_u, 'contrato_renovacao', 'Renovação registrada',
        'Aditivo de prazo aprovado (#' || r.numero || '): nova vigência até ' || to_char(p_novo_fim, 'DD/MM/YYYY'), '/demandas/ficha?id=' || r.id);
    end loop;
  end loop;
end $$;

-- ===== ficha do contrato (protótipo Contrato) =====
create or replace function public.contrato_ficha(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare c public.contratos; v jsonb;
begin
  if not app.acesso_contratos() then perform app.erro('Sem permissão para contratos.', '42501'); end if;
  select * into c from public.contratos where id = p_id;
  if not found then return null; end if;
  select jsonb_build_object(
    'contrato', to_jsonb(c) || jsonb_build_object(
        'valor_anual', c.valor_mensal * 12,
        'unidade', (select sigla from public.unidades where id = c.unidade_ocupante_id),
        'fiscal', (select nome_completo from public.servidores where id = c.fiscal_servidor_id),
        'dias_restantes', c.fim_vigencia - current_date),
    'locador', public.locador_dados(c.locador_id, false),
    'aditivos', coalesce((select jsonb_agg(to_jsonb(a) order by a.numero) from public.aditivos a where a.contrato_id = c.id), '[]'::jsonb),
    'alugueis', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'competencia', a.competencia, 'valor', a.valor, 'vencimento', a.vencimento,
                  'pago_em', a.pago_em, 'valor_pago', a.valor_pago,
                  'situacao', case when a.pago_em is not null then 'pago' when a.vencimento < current_date then 'atrasado' else 'pendente' end) order by a.competencia)
                  from public.alugueis a where a.contrato_id = c.id), '[]'::jsonb),
    'ucs', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'fornecedor', u.fornecedor, 'numero', u.numero, 'descricao', u.descricao,
                  'ultima', (select jsonb_build_object('competencia', f.competencia, 'valor', f.valor, 'pago_em', f.pago_em, 'vencimento', f.vencimento)
                               from public.faturas f where f.uc_id = u.id order by f.competencia desc limit 1)) order by u.fornecedor, u.numero)
                  from public.unidades_consumidoras u where u.contrato_id = c.id and u.ativa), '[]'::jsonb),
    'documentos', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'nome', d.nome, 'path', d.path, 'tamanho', d.tamanho, 'aditivo_id', d.aditivo_id,
                  'enviado_em', d.enviado_em, 'enviado_por', app.nome_usuario(d.enviado_por)) order by d.enviado_em)
                  from public.contrato_documentos d where d.contrato_id = c.id), '[]'::jsonb),
    'historico', coalesce((select jsonb_agg(jsonb_build_object('em', h.em, 'acao', h.acao, 'detalhes', h.detalhes, 'ator', app.nome_usuario(h.ator_id)) order by h.em desc)
                  from (select * from public.contrato_historico where contrato_id = c.id order by em desc limit 100) h), '[]'::jsonb),
    'renovacao', (select jsonb_build_object('demanda_id', d.id, 'numero', d.numero, 'status', d.status) from public.demandas d
                   where d.contrato_id = c.id order by d.criado_em desc limit 1),
    'pendentes', (select count(*) from public.solicitacoes s where s.alvo_id = c.id and s.status = 'pendente' and s.tipo in ('contrato_alterar', 'contrato_aditivo'))
  ) into v;
  return v;
end $$;

-- lista de contratos
create or replace function public.listar_contratos()
returns table (id uuid, numero text, locador text, imovel text, unidade text, fim_vigencia date, dias_restantes integer, valor_mensal numeric,
               fiscal text, encerrado boolean, alugueis_atrasados integer, aditivos integer)
language sql stable security definer set search_path = ''
as $$
  select c.id, c.numero, l.nome, c.imovel_descricao, u.sigla, c.fim_vigencia, c.fim_vigencia - current_date, c.valor_mensal, s.nome_completo, c.encerrado,
         (select count(*) from public.alugueis a where a.contrato_id = c.id and a.pago_em is null and a.vencimento < current_date)::int,
         (select count(*) from public.aditivos a where a.contrato_id = c.id)::int
    from public.contratos c join public.locadores l on l.id = c.locador_id
    left join public.unidades u on u.id = c.unidade_ocupante_id left join public.servidores s on s.id = c.fiscal_servidor_id
   where app.acesso_contratos()
   order by c.encerrado, c.fim_vigencia
$$;

-- painel da secretária: KPIs de contratos (só para quem tem o módulo)
create or replace function public.painel_contratos()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select case when not app.acesso_contratos() then null else jsonb_build_object(
    'vencendo', (select count(*) from public.contratos where not encerrado and fim_vigencia between current_date and current_date
                   + coalesce((select (valor)::int from public.configuracoes where chave = 'contratos.dias_renovacao'), 90)),
    'vencendo_30', (select count(*) from public.contratos where not encerrado and fim_vigencia between current_date and current_date + 30),
    'vencidos', (select count(*) from public.contratos where not encerrado and fim_vigencia < current_date),
    'alugueis_pendentes', (select count(*) from public.alugueis a join public.contratos c on c.id = a.contrato_id
                             where not c.encerrado and a.pago_em is null and a.vencimento <= current_date),
    'alugueis_pendentes_valor', (select coalesce(sum(a.valor), 0) from public.alugueis a join public.contratos c on c.id = a.contrato_id
                             where not c.encerrado and a.pago_em is null and a.vencimento <= current_date),
    'proximos', coalesce((select jsonb_agg(x order by x.fim_vigencia) from (
                   select c.id, c.numero, c.imovel_descricao, c.fim_vigencia, c.fim_vigencia - current_date as dias
                     from public.contratos c where not c.encerrado and c.fim_vigencia >= current_date order by c.fim_vigencia limit 5) x), '[]'::jsonb)
  ) end
$$;

-- ===== busca geral: + contratos (número, processo, imóvel, locador) =====
create or replace function public.busca_geral(termo text, limite integer default 8)
returns table (tipo text, id uuid, titulo text, subtitulo text, rota text)
language plpgsql stable security invoker set search_path = ''
as $$
declare q text := app.normalizar(btrim(coalesce(termo, '')));
        lim integer := least(greatest(coalesce(limite, 8), 1), 20);
        num bigint := case when btrim(coalesce(termo, '')) ~ '^#?[0-9]{1,12}$' then ltrim(btrim(termo), '#')::bigint end;
begin
  if length(q) < 2 and num is null then return; end if;
  q := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return query
    (select 'contrato'::text, c.id, 'Contrato nº ' || c.numero, c.imovel_descricao || ' · ' || l.nome, '/contratos/ficha?id=' || c.id
       from public.contratos c join public.locadores l on l.id = c.locador_id
      where app.normalizar(c.numero) like q or app.normalizar(coalesce(c.processo, '')) like q
         or app.normalizar(c.imovel_descricao) like q or app.normalizar(l.nome) like q
      order by c.fim_vigencia limit lim)
    union all
    (select 'demanda'::text, d.id, '#' || d.numero || ' ' || d.titulo, coalesce('Processo ' || d.numero_processo, 'Demanda'), '/demandas/ficha?id=' || d.id
       from public.demandas d
      where app.normalizar(d.titulo) like q or app.normalizar(coalesce(d.numero_processo, '')) like q or d.numero = num
      order by d.numero desc limit lim)
    union all
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

update public.modulos set status = 'ativo' where codigo in ('contratos', 'unidades_consumidoras');

grant execute on function public.contrato_ficha(uuid) to authenticated;
grant execute on function public.listar_contratos() to authenticated;
grant execute on function public.painel_contratos() to authenticated;
grant execute on function public.busca_geral(text, integer) to authenticated;

-- ===================== 20261129000400_fase4_aprovacoes.sql =====================
-- Fase 4 · alterações de contrato passam por aprovação (6.9)
-- public.solicitar continua recusando os tipos de contrato (campos_permitidos vazio p/ eles);
-- o pedido entra por public.solicitar_contrato, que valida os campos próprios.

create or replace function app.tabela_alvo(t public.tipo_solicitacao)
returns text language sql immutable set search_path = ''
as $$
  select case
    when t in ('unidade_criar', 'unidade_alterar') then 'unidades'
    when t in ('cargo_criar', 'cargo_alterar') then 'cargos'
    when t = 'servidor_alterar' then 'servidores'
    when t in ('usuario_perfil', 'acesso_unidade_conceder', 'acesso_unidade_retirar') then 'usuarios'
    when t::text in ('contrato_alterar', 'contrato_aditivo') then 'contratos'
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
    when 'descricao' then 'descrição' when 'abrangencia' then 'abrangência'
    when 'numero' then 'número' when 'processo' then 'processo' when 'imovel_descricao' then 'imóvel'
    when 'imovel_endereco' then 'endereço' when 'unidade_ocupante_id' then 'unidade ocupante'
    when 'valor_mensal' then 'valor mensal' when 'dia_vencimento' then 'dia de vencimento'
    when 'fiscal_servidor_id' then 'fiscal' when 'indice_reajuste' then 'índice de reajuste'
    when 'mes_database' then 'mês da data-base' when 'encerrado' then 'encerramento'
    when 'novo_fim' then 'nova vigência' when 'novo_valor' then 'novo valor' when 'data_assinatura' then 'assinatura'
    else k
  end
$$;

create or replace function app.campos_contrato()
returns text[] language sql immutable set search_path = ''
as $$ select array['numero', 'processo', 'imovel_descricao', 'imovel_endereco', 'unidade_ocupante_id', 'valor_mensal', 'dia_vencimento',
                   'fiscal_servidor_id', 'indice_reajuste', 'mes_database', 'encerrado'] $$;

create or replace function public.solicitar_contrato(
  p_tipo public.tipo_solicitacao, p_contrato uuid, p_dados jsonb, p_justificativa text, p_anexo_path text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid(); v_linha jsonb; v_norm jsonb; v_antes jsonb := '{}'::jsonb; v_depois jsonb := '{}'::jsonb;
  v_resumo text; v_id uuid; v_aprovador uuid; v_fim date; v_valor numeric; v_prazo boolean; v_altval boolean;
begin
  if not app.acesso_contratos() then perform app.erro('Sem permissão para contratos.', '42501'); end if;
  if p_tipo::text not in ('contrato_alterar', 'contrato_aditivo') then perform app.erro('Tipo de solicitação inválido.', '22023'); end if;
  if p_dados is null or jsonb_typeof(p_dados) <> 'object' then perform app.erro('Dados inválidos na solicitação.', '22023'); end if;
  v_linha := app.linha_json('contratos', p_contrato);
  if v_linha is null then perform app.erro('Contrato não encontrado.', 'P0002'); end if;
  if exists (select 1 from public.solicitacoes s where s.alvo_id = p_contrato and s.status = 'pendente' and s.tipo::text in ('contrato_alterar', 'contrato_aditivo')) then
    perform app.erro('Já existe pedido pendente para este contrato. Aguarde a decisão.', '23505');
  end if;

  if p_tipo::text = 'contrato_alterar' then
    if exists (select 1 from jsonb_object_keys(p_dados) k where not (k = any (app.campos_contrato()))) then
      perform app.erro('Campo não permitido nesta solicitação.', '22023');
    end if;
    v_norm := app.normalizar_dados('contratos', p_dados);
    select coalesce(jsonb_object_agg(k, v_linha -> k), '{}'::jsonb), coalesce(jsonb_object_agg(k, v_norm -> k), '{}'::jsonb)
      into v_antes, v_depois from jsonb_object_keys(v_norm) k where (v_linha -> k) is distinct from (v_norm -> k);
    if v_depois = '{}'::jsonb then perform app.erro('Nenhuma alteração informada.', '22023'); end if;
    if v_depois ? 'valor_mensal' and coalesce((v_depois ->> 'valor_mensal')::numeric, 0) <= 0 then perform app.erro('Valor mensal inválido.', '22023'); end if;
    if v_depois ? 'dia_vencimento' and coalesce((v_depois ->> 'dia_vencimento')::int, 0) not between 1 and 28 then perform app.erro('Dia de vencimento deve ser de 1 a 28.', '22023'); end if;
    if v_depois ? 'numero' and (length(btrim(coalesce(v_depois ->> 'numero', ''))) = 0
        or exists (select 1 from public.contratos c where app.normalizar(c.numero) = app.normalizar(v_depois ->> 'numero') and c.id <> p_contrato)) then
      perform app.erro('Número de contrato vazio ou já cadastrado.', '23505');
    end if;
    v_resumo := (select string_agg(app.rotulo_campo(k), ', ') from jsonb_object_keys(v_depois) k);
    v_resumo := upper(left(v_resumo, 1)) || substr(v_resumo, 2) || ' do contrato nº ' || (v_linha ->> 'numero');
  else
    if exists (select 1 from jsonb_object_keys(p_dados) k where not (k = any (array['novo_fim', 'novo_valor', 'data_assinatura', 'descricao']))) then
      perform app.erro('Campo não permitido nesta solicitação.', '22023');
    end if;
    begin
      v_fim := nullif(p_dados ->> 'novo_fim', '')::date;
      v_valor := nullif(p_dados ->> 'novo_valor', '')::numeric;
      if nullif(p_dados ->> 'data_assinatura', '') is not null then perform (p_dados ->> 'data_assinatura')::date; end if;
    exception when others then perform app.erro('Dados inválidos na solicitação.', '22023'); end;
    v_prazo := v_fim is not null; v_altval := v_valor is not null;
    if not (v_prazo or v_altval) then perform app.erro('Informe a nova vigência e/ou o novo valor.', '22023'); end if;
    if v_prazo and v_fim <= (v_linha ->> 'fim_vigencia')::date then perform app.erro('A nova vigência deve ser depois do fim atual.', '22023'); end if;
    if v_altval and v_valor <= 0 then perform app.erro('Valor inválido.', '22023'); end if;
    if length(coalesce(p_dados ->> 'descricao', '')) > 2000 then perform app.erro('Descrição muito longa.', '22023'); end if;
    -- "como está" com as mesmas chaves do "como fica" (tela de aprovações)
    v_antes := jsonb_strip_nulls(jsonb_build_object('novo_fim', case when v_prazo then v_linha -> 'fim_vigencia' end,
                                                    'novo_valor', case when v_altval then v_linha -> 'valor_mensal' end));
    v_depois := jsonb_strip_nulls(jsonb_build_object('novo_fim', v_fim, 'novo_valor', v_valor, 'data_assinatura', nullif(p_dados ->> 'data_assinatura', ''),
                                                     'descricao', nullif(btrim(coalesce(p_dados ->> 'descricao', '')), '')));
    v_resumo := 'Aditivo de ' || case when v_prazo and v_altval then 'prazo e valor' when v_prazo then 'prazo' else 'valor' end
                || ' do contrato nº ' || (v_linha ->> 'numero');
  end if;

  if p_anexo_path is not null and (p_anexo_path not like 'aprovacoes/' || v_uid::text || '/%'
       or not exists (select 1 from storage.objects o where o.bucket_id = 'anexos' and o.name = p_anexo_path)) then
    perform app.erro('Anexo inválido.', '22023');
  end if;

  insert into public.solicitacoes (tipo, alvo_id, dados_antes, dados_depois, versao_alvo, justificativa, anexo_path, solicitante_id, resumo)
  values (p_tipo, p_contrato, v_antes, v_depois, md5(v_linha::text), btrim(coalesce(p_justificativa, '')), p_anexo_path, v_uid, v_resumo)
  returning id into v_id;
  perform app.historico_contrato(p_contrato, 'pedido_aprovacao', jsonb_build_object('resumo', v_resumo));
  for v_aprovador in
    select u.id from public.usuarios u join public.servidores s on s.id = u.servidor_id
     where u.ativo and s.situacao = 'ativo' and u.perfil in ('administrador', 'secretaria') and u.id <> v_uid
  loop
    perform app.notificar(v_aprovador, 'aprovacao_pedido', 'Pedido de aprovação', v_resumo, '/aprovacoes?id=' || v_id);
  end loop;
  return v_id;
exception when check_violation then perform app.erro('Informe a justificativa (mín. 5 caracteres).', '23514');
end $$;

-- novo valor / dia de vencimento valem para os aluguéis ainda não pagos a partir do mês corrente
create or replace function app.reajustar_alugueis_abertos(p_contrato uuid)
returns void language sql security definer set search_path = ''
as $$
  update public.alugueis a set valor = c.valor_mensal,
         vencimento = make_date(extract(year from a.competencia)::int, extract(month from a.competencia)::int, c.dia_vencimento)
    from public.contratos c
   where c.id = p_contrato and a.contrato_id = c.id and a.pago_em is null and a.competencia >= date_trunc('month', current_date)
$$;

create or replace function app.aplicar_solicitacao(s public.solicitacoes)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_num integer; v_aditivo uuid; v_fim date; v_valor numeric;
begin
  case s.tipo::text
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
    when 'contrato_alterar' then
      perform app.atualizar_por_json('contratos', s.alvo_id, s.dados_depois);
      if s.dados_depois ?| array['valor_mensal', 'dia_vencimento'] then perform app.reajustar_alugueis_abertos(s.alvo_id); end if;
      perform app.historico_contrato(s.alvo_id, 'alterado', jsonb_build_object('resumo', s.resumo, 'solicitacao', s.id));
    when 'contrato_aditivo' then
      v_fim := (s.dados_depois ->> 'novo_fim')::date; v_valor := (s.dados_depois ->> 'novo_valor')::numeric;
      select coalesce(max(numero), 0) + 1 into v_num from public.aditivos where contrato_id = s.alvo_id;
      insert into public.aditivos (contrato_id, numero, altera_prazo, altera_valor, novo_fim, novo_valor, data_assinatura, descricao, solicitacao_id)
      values (s.alvo_id, v_num, v_fim is not null, v_valor is not null, v_fim, v_valor, (s.dados_depois ->> 'data_assinatura')::date, s.dados_depois ->> 'descricao', s.id)
      returning id into v_aditivo;
      update public.contratos set fim_vigencia = coalesce(v_fim, fim_vigencia), valor_mensal = coalesce(v_valor, valor_mensal) where id = s.alvo_id;
      if v_valor is not null then perform app.reajustar_alugueis_abertos(s.alvo_id); end if;
      perform app.gerar_alugueis(s.alvo_id);
      perform app.historico_contrato(s.alvo_id, 'aditivo', jsonb_build_object('numero', v_num, 'resumo', s.resumo, 'solicitacao', s.id));
      if v_fim is not null then perform app.renovacao_registrada(s.alvo_id, v_fim); end if;
    else
      perform app.atualizar_por_json(app.tabela_alvo(s.tipo), s.alvo_id, s.dados_depois);
  end case;
end $$;

grant execute on function public.solicitar_contrato(public.tipo_solicitacao, uuid, jsonb, text, text) to authenticated;
revoke execute on function app.aplicar_solicitacao(public.solicitacoes) from public, anon, authenticated;
revoke execute on function app.reajustar_alugueis_abertos(uuid) from public, anon, authenticated;
