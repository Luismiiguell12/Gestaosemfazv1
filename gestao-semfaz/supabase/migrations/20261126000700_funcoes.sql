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
