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
