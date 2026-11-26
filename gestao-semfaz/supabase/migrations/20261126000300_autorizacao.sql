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
