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
    v_antes := jsonb_strip_nulls(jsonb_build_object('fim_vigencia', case when v_prazo then v_linha -> 'fim_vigencia' end,
                                                    'valor_mensal', case when v_altval then v_linha -> 'valor_mensal' end));
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
