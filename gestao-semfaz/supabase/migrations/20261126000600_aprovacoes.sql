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
