-- Adendo 01 (Produtividade), seção 2 · campos de elegibilidade no cadastro, criados já agora
-- para a Fase 5 não precisar de migração destrutiva. Só acrescenta colunas.

create type public.tipo_vinculo as enum ('efetivo', 'comissionado', 'temporario');

alter table public.servidores
  add column tipo_vinculo public.tipo_vinculo,
  add column exerce_comissao boolean not null default false;
comment on column public.servidores.tipo_vinculo is 'Obrigatório para cadastros novos. Servidores antigos ficam sem valor até a chefia/RH informar (não elegíveis enquanto isso).';
comment on column public.servidores.exerce_comissao is 'Exerce cargo em comissão ou função de confiança na SEMFAZ';

alter table public.cargos add column carreira_excluida boolean not null default false;
comment on column public.cargos.carreira_excluida is 'Carreira excluída do adicional (§ 3º do art. 15-A da LC 138/2025). Lista oficial pendente: nenhuma marcada.';

-- obrigatório em cadastro novo e não pode voltar a ficar vazio (sem quebrar registros antigos)
create or replace function app.exigir_tipo_vinculo()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.tipo_vinculo is null and (tg_op = 'INSERT' or old.tipo_vinculo is not null) then
    raise exception using message = 'Informe o tipo de vínculo (efetivo, comissionado ou temporário).', errcode = '23502';
  end if;
  return new;
end $$;
create trigger servidores_tipo_vinculo before insert or update of tipo_vinculo on public.servidores
  for each row execute function app.exigir_tipo_vinculo();

-- elegível ao adicional: calculado, nunca digitado (efetivo e carreira não excluída;
-- comissionado puro e temporário não entram; efetivo em comissão/função entra)
create or replace function app.elegivel_adicional(p_servidor uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(s.tipo_vinculo = 'efetivo' and not c.carreira_excluida, false)
    from public.servidores s join public.cargos c on c.id = s.cargo_id where s.id = p_servidor
$$;
-- campo calculado da API: /servidores?select=*,elegivel_adicional
create or replace function public.elegivel_adicional(s public.servidores)
returns boolean language sql stable security invoker set search_path = ''
as $$ select coalesce(s.tipo_vinculo = 'efetivo' and not (select c.carreira_excluida from public.cargos c where c.id = s.cargo_id), false) $$;
grant execute on function public.elegivel_adicional(public.servidores) to authenticated;
revoke execute on function app.elegivel_adicional(uuid) from public, anon, authenticated;

grant insert (tipo_vinculo, exerce_comissao) on public.servidores to authenticated;

-- ===== aprovações: novos campos alteráveis =====
create or replace function app.campos_permitidos(t public.tipo_solicitacao)
returns text[] language sql immutable set search_path = ''
as $$
  select case t
    when 'unidade_criar' then array['sigla', 'nome', 'tipo', 'unidade_pai_id', 'ordem']
    when 'unidade_alterar' then array['sigla', 'nome', 'unidade_pai_id', 'ordem', 'ativa']
    when 'cargo_criar' then array['nome', 'carreira_excluida']
    when 'cargo_alterar' then array['nome', 'ativo', 'carreira_excluida']
    when 'servidor_alterar' then array['nome_completo', 'matricula', 'cargo_id', 'unidade_id', 'situacao', 'email_institucional', 'tipo_vinculo', 'exerce_comissao']
    when 'usuario_perfil' then array['perfil']
    when 'acesso_unidade_conceder' then array['unidade_id']
    when 'acesso_unidade_retirar' then array['unidade_id']
    when 'feriado_alterar' then array['data', 'descricao', 'abrangencia']
    else array[]::text[]
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
    when 'tipo_vinculo' then 'tipo de vínculo' when 'exerce_comissao' then 'cargo em comissão/função de confiança'
    when 'carreira_excluida' then 'carreira excluída do adicional'
    else k
  end
$$;

-- cargo novo aprovado grava também a marca de carreira excluída
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
      insert into public.cargos (nome, carreira_excluida) values (s.dados_depois ->> 'nome', coalesce((s.dados_depois ->> 'carreira_excluida')::boolean, false));
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
revoke execute on function app.aplicar_solicitacao(public.solicitacoes) from public, anon, authenticated;

-- ===== importação de servidores: coluna "tipo de vínculo" (obrigatória) e "cargo em comissão" (opcional) =====
create or replace function app.vinculo_planilha(t text)
returns public.tipo_vinculo language sql immutable set search_path = ''
as $$
  select case app.normalizar(btrim(coalesce(t, '')))
    when 'efetivo' then 'efetivo' when 'comissionado' then 'comissionado' when 'temporario' then 'temporario'
    when 'contratado' then 'temporario' end::public.tipo_vinculo
$$;
create or replace function app.sim_nao_planilha(t text)
returns boolean language sql immutable set search_path = ''
as $$ select case app.normalizar(btrim(coalesce(t, ''))) when 'sim' then true when 's' then true when 'nao' then false when 'n' then false when '' then false end $$;

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
    if app.vinculo_planilha(r ->> 'tipo_vinculo') is null then
      return query select n, 'tipo_vinculo', 'Tipo de vínculo deve ser efetivo, comissionado ou temporário.';
    end if;
    if app.sim_nao_planilha(r ->> 'exerce_comissao') is null then
      return query select n, 'exerce_comissao', 'Cargo em comissão/função de confiança: use sim ou não.';
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
    insert into public.servidores (nome_completo, matricula, cargo_id, unidade_id, email_institucional, tipo_vinculo, exerce_comissao)
    values (
      r ->> 'nome', r ->> 'matricula',
      (select c.id from public.cargos c where c.ativo and app.normalizar(c.nome) = app.normalizar(r ->> 'cargo')),
      (select u.id from public.unidades u where u.ativa and app.normalizar(u.sigla) = app.normalizar(r ->> 'unidade')),
      nullif(btrim(coalesce(r ->> 'email', '')), ''),
      app.vinculo_planilha(r ->> 'tipo_vinculo'), app.sim_nao_planilha(r ->> 'exerce_comissao')
    ) returning id into v_id;
    insert into public.saldos_servidor (servidor_id, ferias_dias, licenca_premio_dias, folgas, fonte, atualizado_por)
    values (v_id, app.numero_planilha(r ->> 'ferias'), app.numero_planilha(r ->> 'licenca_premio'),
            app.numero_planilha(r ->> 'folgas'), 'Planilha de servidores', auth.uid());
    n := n + 1;
  end loop;
  return n;
end $$;
