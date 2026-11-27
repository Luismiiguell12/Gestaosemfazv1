-- ============================================================================
-- CARGA DE DEMONSTRAÇÃO — SOMENTE AMBIENTE DE TESTES. NUNCA EM PRODUÇÃO.
-- Todos os nomes, matrículas, CPFs/CNPJs, valores e textos são FICTÍCIOS.
-- Pré-requisitos: migrations aplicadas + supabase/seed.sql + usuários da
-- secretária (000001) e do administrador (000002) criados.
-- Datas relativas a hoje. Rodar uma vez (aborta se já tiver rodado).
-- ============================================================================
do $demo$
declare
  v_sec uuid := (select u.id from public.usuarios u join public.servidores s on s.id = u.servidor_id where s.matricula = '000001');
  v_adm uuid := (select u.id from public.usuarios u join public.servidores s on s.id = u.servidor_id where s.matricula = '000002');
  hoje date := current_date;
  mes_passado date := (date_trunc('month', current_date) - interval '1 month')::date;
  r record; v_id uuid; v_dem uuid; v_loc uuid; v_ct uuid; v_uc uuid; i integer; v_comp date; v_av uuid; v_n numeric[];
  v_txt text;
begin
  if v_sec is null or v_adm is null then raise exception 'Crie antes os usuários da secretária (000001) e do administrador (000002).'; end if;
  if exists (select 1 from public.contratos where numero = 'DEMO-001/2025') then raise exception 'Carga de demonstração já aplicada.'; end if;

  -- ===== servidores: vínculo (Adendo 01), datas e servidores extras de outras unidades =====
  update public.servidores set tipo_vinculo = case when matricula = '000001' then 'comissionado'::public.tipo_vinculo else 'efetivo'::public.tipo_vinculo end,
         exerce_comissao = matricula in ('000001', '000010', '000011', '000106', '000206'), data_entrada_semfaz = date '2019-03-01'
   where tipo_vinculo is null;
  insert into public.servidores (nome_completo, matricula, cargo_id, unidade_id, tipo_vinculo, exerce_comissao, data_entrada_semfaz)
  select v.nome, v.mat, (select id from public.cargos where nome = v.cargo), (select id from public.unidades where sigla = v.sigla), v.vinc::public.tipo_vinculo, false, date '2021-02-01'
    from (values
      ('Servidor J', '000401', 'Auditor Fiscal', 'COACAM', 'efetivo'), ('Servidor K', '000402', 'Auditor Fiscal', 'COACAM', 'efetivo'),
      ('Servidor L', '000501', 'Agente Administrativo', 'COEF', 'efetivo'), ('Servidor M', '000502', 'Agente Administrativo', 'COEF', 'temporario'),
      ('Servidor N', '000601', 'Assessor(a)', 'ASPLAN', 'comissionado'), ('Servidor O', '000602', 'Agente Administrativo', 'ASPLAN', 'efetivo'),
      ('Servidor P', '000701', 'Agente Administrativo', 'PAV', 'efetivo'), ('Servidor Q', '000202', 'Agente Administrativo', 'CONTA', 'efetivo'),
      ('Servidor R', '000302', 'Auditor Fiscal', 'COAC', 'efetivo'), ('Servidor S', '000801', 'Agente Administrativo', 'COCMI', 'efetivo')
    ) v(nome, mat, cargo, sigla, vinc)
   where not exists (select 1 from public.servidores s where s.matricula = v.mat);
  insert into public.saldos_servidor (servidor_id, ferias_dias, licenca_premio_dias, folgas, fonte)
  select s.id, 10 + (abs(hashtext(s.matricula)) % 21), (abs(hashtext(s.matricula || 'lp')) % 4) * 30, abs(hashtext(s.matricula || 'f')) % 5, 'Levantamento fictício do RH'
    from public.servidores s on conflict (servidor_id) do nothing;

  -- ===== férias, licenças e folgas =====
  insert into public.afastamentos (servidor_id, tipo, inicio, fim, status, substituto_id, solicitado_por, decidido_por, decidido_em, observacao)
  select (select id from public.servidores where matricula = a.mat), a.tipo::public.tipo_afastamento, hoje + a.ini, hoje + a.fim, a.st::public.status_afastamento,
         (select id from public.servidores where matricula = a.sub), v_sec, case when a.st = 'aprovado' then v_sec end, case when a.st = 'aprovado' then now() end, a.obs
    from (values
      ('000102', 'ferias', -6, 8, 'aprovado', '000103', 'Férias de verão'),
      ('000201', 'folga', 2, 2, 'aprovado', '000202', null),
      ('000104', 'ferias', 20, 39, 'solicitado', null, 'Viagem em família'),
      ('000301', 'licenca_premio', 35, 64, 'aprovado', '000302', null),
      ('000401', 'ferias', 45, 59, 'solicitado', null, null),
      ('000105', 'ferias', -40, -26, 'aprovado', '000104', null),
      ('000501', 'folga', 9, 10, 'solicitado', null, 'Compensação de plantão')
    ) a(mat, tipo, ini, fim, st, sub, obs);

  -- ===== demandas (quadro, prazos, checklist, conversa, feedback) =====
  for r in select * from (values
      ('Relatório mensal de fiscalização do ISS', 'COFIT', 'processo', '2041/2026', 'alta', 'em_andamento', 5, array['000101', '000102'], array['Levantar autos de infração', 'Consolidar valores', 'Revisar com a coordenação'], 2),
      ('Auditoria em contribuintes do Simples Nacional', 'COFIT', 'processo', '2055/2026', 'critica', 'a_fazer', -3, array['000101'], array['Selecionar amostra', 'Notificar contribuintes'], 0),
      ('Parecer sobre isenção de IPTU — entidade fictícia', 'COFIT', 'email', null, 'media', 'em_revisao', 2, array['000102'], array['Analisar documentação', 'Redigir parecer'], 2),
      ('Atualização da planta genérica de valores', 'COACAM', 'processo', '1980/2026', 'alta', 'aguardando_terceiros', 15, array['000401', '000402'], array['Coletar dados do cartório', 'Simular impactos'], 1),
      ('Conciliação das receitas de outubro', 'CONTA', 'outra', null, 'alta', 'em_andamento', 1, array['000201', '000202'], array['Extratos bancários', 'Lançamentos contábeis', 'Relatório final'], 1),
      ('Balancete do 3º trimestre', 'CONTA', 'outra', null, 'media', 'concluida', -10, array['000202'], array['Fechar trimestre'], 1),
      ('Atendimento a pedidos de certidão negativa', 'COAC', 'whatsapp', null, 'media', 'a_fazer', 4, array['000301', '000302'], array[]::text[], 0),
      ('Revisão do cadastro mobiliário', 'COAC', 'processo', '2102/2026', 'baixa', 'em_andamento', -1, array['000302'], array['Cruzar com Junta Comercial', 'Atualizar cadastros'], 1),
      ('Plano de metas de arrecadação 2027', 'ASPLAN', 'outra', null, 'alta', 'em_andamento', 12, array['000602'], array['Série histórica', 'Projeção', 'Validação com a Secretária'], 1),
      ('Mutirão de negociação da dívida ativa', 'COCMI', 'processo', '2150/2026', 'critica', 'a_fazer', 6, array['000801'], array['Montar lista de devedores', 'Agendar atendimentos'], 0),
      ('Treinamento sobre a reforma tributária (IBS)', 'Gabinete', 'outra', null, 'media', 'concluida', -20, array['000106', '000206'], array['Contratar instrutor', 'Reservar auditório'], 2),
      ('Resposta a ofício do Tribunal de Contas', 'DAT', 'email', null, 'critica', 'em_revisao', 0, array['000010'], array['Levantar informações', 'Minuta de resposta'], 2),
      ('Relatório de execução orçamentária', 'COEF', 'outra', null, 'media', 'concluida', -5, array['000501'], array['Extrair dados', 'Montar relatório'], 2),
      ('Publicação do calendário fiscal 2027', 'PAV', 'outra', null, 'baixa', 'a_fazer', 25, array['000701'], array[]::text[], 0),
      ('Fiscalização de ITBI em loteamento', 'COFIT', 'processo', '2177/2026', 'media', 'concluida', -14, array['000103'], array['Vistoria', 'Laudo'], 2)
    ) d(titulo, sigla, origem, proc, prio, st, prazo, resp, check_itens, feitos) loop
    insert into public.demandas (titulo, descricao, origem, numero_processo, unidade_id, prioridade, status, prazo, criado_por, criado_em, iniciada_em, concluida_em)
    values (r.titulo, 'Demanda fictícia criada para demonstração.', r.origem::public.origem_demanda, r.proc, (select id from public.unidades where sigla = r.sigla),
            r.prio::public.prioridade_demanda, r.st::public.status_demanda, hoje + r.prazo, v_sec, now() - interval '20 days',
            case when r.st <> 'a_fazer' then now() - interval '12 days' end,
            case when r.st = 'concluida' then (hoje + r.prazo - 1)::timestamptz + interval '15 hours' end)
    returning id into v_dem;
    insert into public.demanda_responsaveis (demanda_id, servidor_id, papel, adicionado_em)
    select v_dem, s.id, 'titular', now() - interval '20 days' from public.servidores s where s.matricula = any (r.resp);
    i := 0;
    foreach v_txt in array coalesce(r.check_itens, array[]::text[]) loop
      insert into public.demanda_checklist (demanda_id, texto, ordem, feito, feito_por, feito_em)
      values (v_dem, v_txt, i, i < r.feitos, case when i < r.feitos then v_sec end, case when i < r.feitos then now() - interval '5 days' end);
      i := i + 1;
    end loop;
    insert into public.demanda_historico (demanda_id, ator_id, acao, detalhes, em) values (v_dem, v_sec, 'criada', jsonb_build_object('prazo', hoje + r.prazo), now() - interval '20 days');
    if r.st <> 'a_fazer' then
      insert into public.demanda_mensagens (demanda_id, autor_id, texto, criado_em) values (v_dem, v_sec, 'Bom dia! Favor priorizar esta demanda e registrar o andamento por aqui.', now() - interval '10 days');
      insert into public.demanda_mensagens (demanda_id, autor_id, texto, criado_em, feedback, feedback_comentario, feedback_por, feedback_em)
      values (v_dem, v_adm, 'Primeira versão concluída; segue para conferência.', now() - interval '4 days',
              case when r.st = 'concluida' then 'aprovado' when r.st = 'em_revisao' then 'ajustar' end::public.feedback_mensagem,
              case when r.st = 'em_revisao' then 'Detalhar a memória de cálculo.' end, case when r.st in ('concluida', 'em_revisao') then v_sec end,
              case when r.st in ('concluida', 'em_revisao') then now() - interval '3 days' end);
    end if;
  end loop;
  -- sugestão de funcionário aguardando a chefia
  insert into public.demandas (titulo, descricao, origem, unidade_id, prioridade, status, prazo, criado_por)
  values ('Sugestão: padronizar modelo de notificação', 'Sugestão fictícia para demonstração.', 'outra', (select id from public.unidades where sigla = 'COFIT'), 'baixa', 'sugerida', hoje + 30, v_adm);
  -- modelo recorrente
  insert into public.recorrencias (titulo, descricao, unidade_id, periodicidade, prazo_dias_uteis, prioridade, responsaveis, checklist, proxima_em, criado_por)
  values ('Fechamento mensal da arrecadação', 'Modelo fictício de demanda recorrente.', (select id from public.unidades where sigla = 'CONTA'), 'mensal', 5, 'alta',
          array[(select id from public.servidores where matricula = '000201')], array['Extrair relatório', 'Conferir com o banco'], (date_trunc('month', hoje) + interval '1 month')::date, v_sec);

  -- ===== calendário =====
  insert into public.compromissos (unidade_id, titulo, descricao, local, inicio, fim, criado_por)
  values (null, 'Reunião de planejamento da SEMFAZ', 'Pauta fictícia: metas do próximo quadrimestre.', 'Sala da Secretária', (hoje + 2)::timestamp + interval '9 hours', (hoje + 2)::timestamp + interval '11 hours', v_sec),
         ((select id from public.unidades where sigla = 'DAT'), 'Alinhamento da fiscalização', null, 'Sala da DAT', (hoje + 5)::timestamp + interval '14 hours', (hoje + 5)::timestamp + interval '15 hours', v_sec),
         ((select id from public.unidades where sigla = 'CONTA'), 'Visita técnica ao banco arrecadador', null, 'Agência fictícia', (hoje + 9)::timestamp + interval '10 hours', (hoje + 9)::timestamp + interval '12 hours', v_sec);
  insert into public.compromisso_participantes (compromisso_id, servidor_id)
  select c.id, s.id from public.compromissos c, public.servidores s where c.titulo = 'Reunião de planejamento da SEMFAZ' and s.matricula in ('000010', '000011', '000106', '000206');

  -- ===== contratos de locação =====
  for r in select * from (values
      ('DEMO-001/2025', 'PF', 'Locador Fictício Um', '52601815906', 'Prédio da COAC', 'Rua Fictícia, 100 – Centro', 'COAC', -700, 18, 3740.00, '000302'),
      ('DEMO-002/2025', 'PJ', 'Imobiliária Exemplo Ltda', '99351819000160', 'Arquivo central', 'Av. Exemplo, 2000 – Bairro Novo', 'Gabinete', -500, 55, 5200.00, '000202'),
      ('DEMO-003/2026', 'PF', 'Locadora Fictícia Dois', '08301661305', 'Anexo da DEFC', 'Travessa Modelo, 45', 'DEFC', -300, 240, 2980.00, '000501'),
      ('DEMO-004/2026', 'PJ', 'Empreendimentos Fictícios S.A.', '09378657000161', 'Depósito de materiais', 'Rodovia Fictícia, km 3', 'PAV', -200, 400, 1850.00, '000701'),
      ('DEMO-005/2026', 'PF', 'Locador Fictício Três', '18609139034', 'Posto de atendimento ao contribuinte', 'Praça Exemplar, 12', 'COAC', -120, 610, 2450.00, '000301'),
      ('DEMO-006/2024', 'PJ', 'Patrimonial Exemplo Ltda', '97543231000183', 'Sala da ASPLAN', 'Rua das Amostras, 300', 'ASPLAN', -900, 82, 3100.00, '000602')
    ) c(num, tipo, nome, doc, imovel, ender, sigla, ini, fim, valor, fiscal) loop
    insert into public.locadores (tipo, nome, documento, email, telefone) values (r.tipo::public.tipo_pessoa, r.nome, r.doc, 'contato.' || lower(split_part(r.num, '/', 1)) || '@exemplo.com', '799990000' || right(r.num, 2))
    on conflict (documento) do update set nome = excluded.nome returning id into v_loc;
    insert into public.contratos (numero, processo, locador_id, imovel_descricao, imovel_endereco, unidade_ocupante_id, inicio, fim_original, fim_vigencia, valor_mensal, dia_vencimento,
                                  fiscal_servidor_id, indice_reajuste, mes_database, criado_por)
    values (r.num, 'PROC-' || right(r.num, 6), v_loc, r.imovel, r.ender, (select id from public.unidades where sigla = r.sigla), hoje + r.ini, hoje + r.fim, hoje + r.fim, r.valor, 10,
            (select id from public.servidores where matricula = r.fiscal), 'IPCA', extract(month from hoje + r.ini)::int, v_sec)
    returning id into v_ct;
    perform app.gerar_alugueis(v_ct);
    -- pagos até dois meses atrás; um vencido sem pagamento no 1º e no 6º contrato
    update public.alugueis set pago_em = vencimento - 3, valor_pago = valor, registrado_por = v_sec, registrado_em = now()
     where contrato_id = v_ct and vencimento < hoje - case when r.num in ('DEMO-001/2025', 'DEMO-006/2024') then 35 else 0 end;
    insert into public.contrato_historico (contrato_id, ator_id, acao, detalhes) values (v_ct, v_sec, 'importado', '{}');
    -- unidades consumidoras e faturas dos últimos 3 meses
    for i in 0..1 loop
      insert into public.unidades_consumidoras (fornecedor, numero, contrato_id)
      values (case i when 0 then (case when r.num in ('DEMO-002/2025', 'DEMO-004/2026') then 'cercos' else 'energisa' end) else 'igua' end::public.fornecedor_uc,
              case i when 0 then 'UC' else 'MAT' end || '-' || right(split_part(r.num, '/', 1), 3) || i, v_ct)
      returning id into v_uc;
      insert into public.faturas (uc_id, competencia, consumo, valor, vencimento, pago_em, registrado_por, criado_por)
      select v_uc, m::date, case i when 0 then 300 + (abs(hashtext(r.num || m::text)) % 900) else 8 + (abs(hashtext(r.num || m::text)) % 25) end,
             case i when 0 then 280 + (abs(hashtext(r.num || m::text)) % 900) else 60 + (abs(hashtext(r.num || m::text)) % 150) end + 0.37,
             (m + interval '1 month' + interval '19 days')::date,
             case when m < date_trunc('month', hoje) - interval '1 month' or (i = 0 and r.num <> 'DEMO-002/2025') then (m + interval '1 month' + interval '15 days')::date end,
             v_sec, v_sec
        from generate_series(date_trunc('month', hoje) - interval '3 months', date_trunc('month', hoje) - interval '1 month', interval '1 month') m
       where (m + interval '1 month' + interval '15 days')::date <= hoje or true;
    end loop;
  end loop;
  -- pagamentos de faturas não podem ser futuros
  update public.faturas set pago_em = null, registrado_por = null where pago_em > hoje;
  -- aditivo de prazo e valor no contrato 2
  select id into v_ct from public.contratos where numero = 'DEMO-002/2025';
  insert into public.aditivos (contrato_id, numero, altera_prazo, altera_valor, novo_fim, novo_valor, data_assinatura, descricao)
  select id, 1, true, true, fim_vigencia, valor_mensal, inicio + 360, '1º termo aditivo fictício (prazo e valor)' from public.contratos where id = v_ct;
  update public.contratos set fim_original = fim_vigencia - 365 where id = v_ct;

  -- ===== folhas de ponto: entregas do mês passado =====
  insert into public.folhas_entregas (competencia, unidade_id, enviada_em, recebida_por, devolvida_em, devolvida_por, atualizado_por)
  select mes_passado, u.id, hoje - 12, (select id from public.servidores where unidade_id = u.id order by matricula limit 1),
         case when u.sigla in ('COFIT', 'CONTA', 'COAC') then hoje - 6 end,
         case when u.sigla in ('COFIT', 'CONTA', 'COAC') then (select id from public.servidores where unidade_id = u.id order by matricula limit 1) end, v_sec
    from public.unidades u where u.sigla in ('COFIT', 'CONTA', 'COAC', 'COACAM', 'COEF')
  on conflict do nothing;

  -- ===== produtividade (Adendo 01) =====
  insert into public.prod_designacoes (papel, usuario_id, ato, criado_por) values ('homologacao', v_adm, 'Portaria fictícia nº 1/2026', v_sec), ('revisora', v_adm, 'Portaria fictícia nº 2/2026', v_sec);
  -- resultado institucional homologado do 2º quadrimestre (metas de exemplo carregadas como se publicadas antes do início)
  alter table public.prod_metas disable trigger prod_metas_travar;
  insert into public.prod_metas (ano, quadrimestre, receita, valor, memoria, fonte, criado_por, criado_em)
  select extract(year from hoje)::int, 2, x.r, x.meta, 'Média dos 3 anos anteriores + 5% (fictício)', 'Estudo fictício da ASPLAN', v_sec, make_date(extract(year from hoje)::int, 4, 20)
    from (values ('R1', 4200000.00), ('R2', 6100000.00), ('R3', 900000.00), ('R4', 650000.00), ('R5', 1500000.00)) x(r, meta);
  alter table public.prod_metas enable trigger prod_metas_travar;
  insert into public.prod_arrecadacao (ano, quadrimestre, receita, valor, fonte, criado_por)
  select extract(year from hoje)::int, 2, x.r, x.v, 'Balancete contábil fictício', v_sec
    from (values ('R1', 3780000.00), ('R2', 6400000.00), ('R3', 720000.00), ('R4', 650000.00), ('R5', 900000.00)) x(r, v);
  insert into public.prod_resultados_inst (ano, quadrimestre, regra_id, pontos, memoria, status, apurado_por, apurado_em, homologado_por, homologado_em)
  select extract(year from hoje)::int, 2, app.regra_vigente(make_date(extract(year from hoje)::int, 5, 1)), (m ->> 'pontos')::numeric, m, 'homologado', v_sec,
         make_date(extract(year from hoje)::int, 9, 8)::timestamptz, v_adm, make_date(extract(year from hoje)::int, 9, 12)::timestamptz
    from (select app.calcular_institucional(extract(year from hoje)::int, 2, app.regra_vigente(make_date(extract(year from hoje)::int, 5, 1))) m) x;

  -- competência do mês passado aberta pela Secretária (mesma lógica da tela)
  perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform public.prod_abrir_competencia(mes_passado);
  perform set_config('request.jwt.claims', '', true);
  -- notas, justificativas e provas fictícias; situações variadas para visualizar o fluxo
  i := 0;
  for r in select a.id, s.matricula from public.prod_avaliacoes a join public.servidores s on s.id = a.servidor_id
            where a.competencia = mes_passado order by s.matricula loop
    i := i + 1;
    v_n := case i % 5 when 0 then array[19, 14, 14, 9, 9] when 1 then array[17, 12, 13, 8, 8] when 2 then array[15, 11, 10, 7, 8]
                        when 3 then array[12, 9, 9, 6, 6] else array[18, 13, 12, 9, 8] end;
    insert into public.prod_notas (avaliacao_id, indicador, nota, justificativa, equivalente, justificativa_equivalente)
    select r.id, 'F' || k, v_n[k], 'Justificativa fictícia: entregas e registros do mês analisados pela chefia.', k = 4 and i % 3 = 0,
           case when k = 4 and i % 3 = 0 then 'Não atende público externo; avaliado o atendimento interno.' end
      from generate_series(1, 5) k;
    insert into public.prod_provas (avaliacao_id, indicador, tipo, descricao, criado_por)
    select r.id, 'F' || k, 'externa', 'Relatório mensal fictício nº ' || (100 + i) || '/' || extract(year from hoje), v_sec from generate_series(1, 5) k;
    update public.prod_avaliacoes set total_funcional = (select sum(nota) from public.prod_notas where avaliacao_id = r.id) where id = r.id;
    insert into public.prod_historico (avaliacao_id, ator_id, acao) values (r.id, v_sec, 'enviada');
    -- distribuição das situações
    if i % 6 = 1 then null;                                                         -- continua em rascunho
    elsif i % 6 = 2 then update public.prod_avaliacoes set status = 'enviada', enviada_em = now() - interval '2 days' where id = r.id;
    elsif i % 6 = 3 then update public.prod_avaliacoes set status = 'ciente', enviada_em = now() - interval '4 days', ciente_em = now() - interval '3 days', ciencia_meio = 'sistema',
                          prazo_recurso = public.somar_dias_uteis(hoje, 2) where id = r.id;
    elsif i % 6 = 4 and r.matricula <> '000002' then
      update public.prod_avaliacoes set status = 'ciente', enviada_em = now() - interval '9 days', ciente_em = now() - interval '8 days', ciencia_meio = 'sistema', prazo_recurso = hoje where id = r.id;
      insert into public.prod_recursos (avaliacao_id, razoes, prazo_revisao, revisor_id) values (r.id, 'Recurso fictício: discordo da nota de F3, pois concluí todas as demandas no prazo.', public.somar_dias_uteis(hoje, 8), v_adm);
      update public.prod_avaliacoes set status = 'em_recurso' where id = r.id;
    elsif i % 6 = 4 then update public.prod_avaliacoes set status = 'enviada', enviada_em = now() - interval '1 day' where id = r.id;
    else
      update public.prod_avaliacoes set status = 'aguardando_homologacao', enviada_em = now() - interval '12 days', ciente_em = now() - interval '11 days', ciencia_meio = 'sistema',
             prazo_recurso = hoje - 3, sem_recurso_em = now() - interval '2 days' where id = r.id;
    end if;
  end loop;
  -- algumas homologadas (instância de homologação = administrador; nunca a própria avaliação)
  for r in select a.id, a.servidor_id, a.competencia from public.prod_avaliacoes a join public.servidores s on s.id = a.servidor_id
            where a.competencia = mes_passado and a.status = 'aguardando_homologacao' and s.matricula <> '000002' order by s.matricula limit 3 loop
    update public.prod_avaliacoes set status = 'homologada', homologada_por = v_adm, homologada_em = now() - interval '1 day' where id = r.id;
    insert into public.prod_apuracoes (competencia, servidor_id, versao, dados)
    values (r.competencia, r.servidor_id, 1, app.prod_apurar(r.competencia, r.servidor_id) || jsonb_build_object('homologado_em', now() - interval '1 day', 'versao', 1));
  end loop;

  -- ===== avisos e rotinas (renovação de contrato vencendo, avisos de vencimento) =====
  perform app.rotina_contratos();
  insert into public.notificacoes (usuario_id, tipo, titulo, texto, link)
  values (v_sec, 'aprovacao_pedido', 'Pedido de aprovação', 'Exemplo fictício: alteração de dados de servidor', '/aprovacoes'),
         (v_adm, 'produtividade', 'Recurso de avaliação para decidir', 'Competência ' || to_char(mes_passado, 'MM/YYYY'), '/produtividade'),
         (v_adm, 'produtividade', 'Competência pronta para homologar', to_char(mes_passado, 'MM/YYYY'), '/produtividade');
end
$demo$;

-- pedidos de aprovação de exemplo (administrador pede; a secretária decide)
do $p$
declare v_adm uuid := (select u.id from public.usuarios u join public.servidores s on s.id = u.servidor_id where s.matricula = '000002');
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform public.solicitar('servidor_alterar', (select id from public.servidores where matricula = '000402'), jsonb_build_object('nome_completo', 'Servidor K da Silva'), 'Correção de nome (exemplo fictício)');
  perform public.solicitar_contrato('contrato_alterar', (select id from public.contratos where numero = 'DEMO-003/2026'), jsonb_build_object('valor_mensal', 3150), 'Reajuste anual pelo IPCA (exemplo fictício)');
  perform set_config('request.jwt.claims', '', true);
end $p$;
