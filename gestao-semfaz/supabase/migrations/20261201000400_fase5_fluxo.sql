-- Fase 5 · fluxo do ciclo mensal (adendo 6): abertura → rascunho → enviada → ciente → (recurso) → homologação → SEMAD

create or replace function app.prod_regra_da(p_av uuid)
returns public.prod_regras language sql stable security definer set search_path = ''
as $$ select r.* from public.prod_avaliacoes a join public.prod_competencias c on c.competencia = a.competencia join public.prod_regras r on r.id = c.regra_id where a.id = p_av $$;

create or replace function app.prod_av(p_id uuid)
returns public.prod_avaliacoes language plpgsql stable security definer set search_path = ''
as $$
declare a public.prod_avaliacoes;
begin
  select * into a from public.prod_avaliacoes where id = p_id;
  if not found then perform app.erro('Avaliação não encontrada.', 'P0002'); end if;
  return a;
end $$;

create or replace function app.prod_eh_avaliador(a public.prod_avaliacoes)
returns boolean language sql stable security definer set search_path = ''
as $$ select app.sessao_ok() and a.avaliador_id is not null and a.avaliador_id = app.servidor_atual() and a.servidor_id <> app.servidor_atual() $$;

create or replace function app.prod_avisar(p_servidor uuid, p_titulo text, p_texto text, p_av uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_u uuid := app.usuario_do_servidor(p_servidor);
begin
  if v_u is not null then
    perform app.notificar(v_u, 'produtividade', p_titulo, p_texto, case when p_av is null then '/produtividade' else '/produtividade/avaliacao?id=' || p_av end);
  end if;
end $$;

-- ===== abertura do ciclo (Secretária/Admin) =====
create or replace function public.prod_abrir_competencia(p_comp date, p_fechamento date default null)
returns integer language plpgsql security definer set search_path = ''
as $$
declare v_comp date := date_trunc('month', p_comp)::date; v_fim date; v_regra uuid; s record; n integer := 0; v_id uuid;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  v_fim := (v_comp + interval '1 month' - interval '1 day')::date;
  if v_comp > date_trunc('month', current_date)::date then perform app.erro('Só é possível abrir o mês atual ou meses anteriores.', '22023'); end if;
  v_regra := app.regra_vigente(v_comp);
  if v_regra is null then perform app.erro('Não há regra de produtividade vigente para essa competência.', '22023'); end if;
  insert into public.prod_competencias (competencia, regra_id, fechamento, aberta_por)
  values (v_comp, v_regra, coalesce(p_fechamento, (v_fim + 10)), auth.uid())
  on conflict (competencia) do nothing;
  if exists (select 1 from public.prod_competencias where competencia = v_comp and status = 'encaminhada') then
    perform app.erro('Competência já encaminhada à SEMAD.', '22023');
  end if;
  -- só elegíveis (efetivo e carreira não excluída), ativos e em exercício na SEMFAZ no mês; não duplica
  for s in select sv.* from public.servidores sv
            where sv.situacao = 'ativo' and app.elegivel_adicional(sv.id)
              and (sv.data_entrada_semfaz is null or sv.data_entrada_semfaz <= v_fim)
              and (sv.data_saida_semfaz is null or sv.data_saida_semfaz >= v_comp)
              and not exists (select 1 from public.prod_avaliacoes a where a.competencia = v_comp and a.servidor_id = sv.id and a.status <> 'retificada') loop
    insert into public.prod_avaliacoes (competencia, servidor_id, periodo_inicio, periodo_fim, unidade_id, avaliador_id)
    values (v_comp, s.id, greatest(v_comp, coalesce(s.data_entrada_semfaz, v_comp)), least(v_fim, coalesce(s.data_saida_semfaz, v_fim)), s.unidade_id, app.chefia_imediata(s.id))
    returning id into v_id;
    perform app.prod_hist(v_id, 'aberta', jsonb_build_object('avaliador', (select nome_completo from public.servidores where id = app.chefia_imediata(s.id))));
    n := n + 1;
  end loop;
  for s in select distinct a.avaliador_id from public.prod_avaliacoes a where a.competencia = v_comp and a.status = 'rascunho' and a.avaliador_id is not null loop
    perform app.prod_avisar(s.avaliador_id, 'Avaliações de desempenho abertas', 'Competência ' || to_char(v_comp, 'MM/YYYY'), null);
  end loop;
  return n;
end $$;

-- mudança de unidade/atribuições no mês: avaliação parcial por período (art. 14 § 2º)
create or replace function public.prod_dividir_periodo(p_id uuid, p_a_partir date, p_avaliador uuid, p_unidade uuid default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare a public.prod_avaliacoes := app.prod_av(p_id); v_id uuid;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if a.status <> 'rascunho' then perform app.erro('Só é possível dividir avaliação em rascunho.', '22023'); end if;
  if p_a_partir <= a.periodo_inicio or p_a_partir > a.periodo_fim then perform app.erro('Data de divisão fora do período.', '22023'); end if;
  update public.prod_avaliacoes set periodo_fim = p_a_partir - 1 where id = p_id;
  insert into public.prod_avaliacoes (competencia, servidor_id, periodo_inicio, periodo_fim, unidade_id, avaliador_id)
  values (a.competencia, a.servidor_id, p_a_partir, a.periodo_fim, coalesce(p_unidade, a.unidade_id), p_avaliador)
  returning id into v_id;
  perform app.prod_hist(p_id, 'periodo_dividido', jsonb_build_object('ate', p_a_partir - 1));
  perform app.prod_hist(v_id, 'periodo_criado', jsonb_build_object('de', p_a_partir));
  return v_id;
exception when check_violation then perform app.erro('Avaliador inválido (ninguém avalia a si mesmo).', '23514');
end $$;

-- troca da chefia que avalia (exceções): Secretária/Admin, só em rascunho
create or replace function public.prod_trocar_avaliador(p_id uuid, p_avaliador uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.prod_avaliacoes := app.prod_av(p_id);
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if a.status <> 'rascunho' then perform app.erro('Só em rascunho.', '22023'); end if;
  update public.prod_avaliacoes set avaliador_id = p_avaliador where id = p_id;
  perform app.prod_hist(p_id, 'avaliador_trocado', jsonb_build_object('avaliador', (select nome_completo from public.servidores where id = p_avaliador)));
exception when check_violation then perform app.erro('Ninguém avalia a si mesmo.', '23514');
end $$;

-- ===== formulário (chefia imediata) =====
create or replace function public.prod_salvar_avaliacao(p_id uuid, p_notas jsonb, p_limitacoes text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.prod_avaliacoes := app.prod_av(p_id); x jsonb;
begin
  if not app.prod_eh_avaliador(a) then perform app.erro('Somente a chefia imediata que avalia.', '42501'); end if;
  if a.status <> 'rascunho' then perform app.erro('A avaliação já foi enviada.', '22023'); end if;
  for x in select * from jsonb_array_elements(coalesce(p_notas, '[]'::jsonb)) loop
    insert into public.prod_notas (avaliacao_id, indicador, nota, justificativa, equivalente, justificativa_equivalente)
    values (p_id, x ->> 'indicador', nullif(x ->> 'nota', '')::numeric, nullif(btrim(coalesce(x ->> 'justificativa', '')), ''),
            coalesce((x ->> 'equivalente')::boolean, false), nullif(btrim(coalesce(x ->> 'justificativa_equivalente', '')), ''))
    on conflict (avaliacao_id, indicador) do update set nota = excluded.nota, justificativa = excluded.justificativa,
      equivalente = excluded.equivalente, justificativa_equivalente = excluded.justificativa_equivalente;
  end loop;
  update public.prod_avaliacoes set limitacoes = nullif(btrim(coalesce(p_limitacoes, '')), ''),
    total_funcional = (select sum(nota) from public.prod_notas where avaliacao_id = p_id) where id = p_id;
exception
  when invalid_text_representation then perform app.erro('Nota inválida.', '22023');
  when numeric_value_out_of_range then perform app.erro('Nota fora do limite.', '23514');
end $$;

-- prova: registro do sistema (demanda, etapa, mensagem do servidor no período), anexo ou referência externa
create or replace function public.prod_adicionar_prova(p_id uuid, p_indicador text, p_tipo text, p_ref uuid default null, p_descricao text default null,
                                                       p_path text default null, p_nome text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare a public.prod_avaliacoes := app.prod_av(p_id); v_id uuid; v_ok boolean;
begin
  if not app.prod_eh_avaliador(a) then perform app.erro('Somente a chefia imediata que avalia.', '42501'); end if;
  if p_tipo = 'demanda' then
    v_ok := exists (select 1 from public.demanda_responsaveis r where r.demanda_id = p_ref and r.servidor_id = a.servidor_id);
  elsif p_tipo = 'checklist' then
    v_ok := exists (select 1 from public.demanda_checklist c join public.demanda_responsaveis r on r.demanda_id = c.demanda_id
                     where c.id = p_ref and r.servidor_id = a.servidor_id);
  elsif p_tipo = 'mensagem' then
    v_ok := exists (select 1 from public.demanda_mensagens m join public.demanda_responsaveis r on r.demanda_id = m.demanda_id
                     where m.id = p_ref and r.servidor_id = a.servidor_id);
  elsif p_tipo = 'anexo' then
    v_ok := p_path like 'avaliacoes/' || p_id::text || '/%' and exists (select 1 from storage.objects o where o.bucket_id = 'produtividade' and o.name = p_path);
  else
    v_ok := p_tipo = 'externa';
  end if;
  if not coalesce(v_ok, false) then perform app.erro('Prova inválida: o registro precisa ser do servidor avaliado.', '22023'); end if;
  if not exists (select 1 from jsonb_array_elements((app.prod_regra_da(p_id)).indicadores) x where x ->> 'codigo' = p_indicador) then
    perform app.erro('Indicador inexistente.', '22023');
  end if;
  insert into public.prod_provas (avaliacao_id, indicador, tipo, ref_id, path, nome, descricao, criado_por)
  values (p_id, p_indicador, p_tipo, p_ref, p_path, left(p_nome, 200), nullif(btrim(coalesce(p_descricao, '')), ''), auth.uid())
  returning id into v_id;
  return v_id;
exception when check_violation then perform app.erro('Prova incompleta (referência externa precisa de descrição).', '23514');
end $$;

create or replace function public.prod_remover_prova(p_prova uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_av uuid := (select avaliacao_id from public.prod_provas where id = p_prova);
begin
  if v_av is null or not app.prod_eh_avaliador(app.prod_av(v_av)) then perform app.erro('Somente a chefia imediata que avalia.', '42501'); end if;
  delete from public.prod_provas where id = p_prova;
end $$;

-- envio: todos os indicadores pontuados, justificados e provados (validação no banco)
create or replace function app.prod_pendencias_envio(p_id uuid)
returns text[] language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(msg order by ordem), '{}') from (
    select x.ordinality ordem, x.value ->> 'codigo' || ': ' ||
      case when n.nota is null then 'sem nota'
           when length(btrim(coalesce(n.justificativa, ''))) < 10 then 'sem justificativa (mín. 10 caracteres)'
           when n.equivalente and length(btrim(coalesce(n.justificativa_equivalente, ''))) < 10 then 'critério equivalente sem justificativa'
           when not exists (select 1 from public.prod_provas p where p.avaliacao_id = p_id and p.indicador = x.value ->> 'codigo') then 'sem prova'
      end msg
      from jsonb_array_elements((app.prod_regra_da(p_id)).indicadores) with ordinality x
      left join public.prod_notas n on n.avaliacao_id = p_id and n.indicador = x.value ->> 'codigo'
  ) t where msg is not null
$$;

create or replace function public.prod_enviar(p_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.prod_avaliacoes := app.prod_av(p_id); v_pend text[];
begin
  if not app.prod_eh_avaliador(a) then perform app.erro('Somente a chefia imediata que avalia.', '42501'); end if;
  if a.status <> 'rascunho' then perform app.erro('A avaliação já foi enviada.', '22023'); end if;
  v_pend := app.prod_pendencias_envio(p_id);
  if cardinality(v_pend) > 0 then perform app.erro('Não é possível enviar: ' || array_to_string(v_pend, '; ') || '.', '22023'); end if;
  update public.prod_avaliacoes set status = 'enviada', enviada_em = now(), devolucao_motivo = null,
    total_funcional = (select sum(nota) from public.prod_notas where avaliacao_id = p_id) where id = p_id;
  perform app.prod_hist(p_id, 'enviada', jsonb_build_object('total', (select sum(nota) from public.prod_notas where avaliacao_id = p_id)));
  perform app.prod_avisar(a.servidor_id, 'Avaliação de desempenho para ciência', 'Competência ' || to_char(a.competencia, 'MM/YYYY'), p_id);
end $$;

-- ===== ciência (art. 16) e recurso =====
create or replace function public.prod_dar_ciencia(p_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.prod_avaliacoes := app.prod_av(p_id); r public.prod_regras := app.prod_regra_da(p_id);
begin
  if not app.sessao_ok() or a.servidor_id is distinct from app.servidor_atual() then perform app.erro('Somente o próprio servidor dá ciência.', '42501'); end if;
  if a.status <> 'enviada' then perform app.erro('Avaliação não está aguardando ciência.', '22023'); end if;
  update public.prod_avaliacoes set status = 'ciente', ciente_em = now(), ciencia_meio = 'sistema', ciencia_registrada_por = auth.uid(),
    prazo_recurso = public.somar_dias_uteis(current_date, coalesce((r.prazos ->> 'recurso')::int, 5)) where id = p_id;
  perform app.prod_hist(p_id, 'ciente', jsonb_build_object('meio', 'sistema'));
end $$;

create or replace function public.prod_ciencia_outro_meio(p_id uuid, p_data date, p_anexo text)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.prod_avaliacoes := app.prod_av(p_id); r public.prod_regras := app.prod_regra_da(p_id);
begin
  if not (app.prod_eh_avaliador(a) or app.gestor_geral()) then perform app.erro('Somente a chefia que avaliou ou a Secretária.', '42501'); end if;
  if a.status <> 'enviada' then perform app.erro('Avaliação não está aguardando ciência.', '22023'); end if;
  if p_data is null or p_data > current_date or p_data < a.enviada_em::date then perform app.erro('Data da ciência inválida.', '22023'); end if;
  if p_anexo is null or p_anexo not like 'avaliacoes/' || p_id::text || '/%' or not exists (select 1 from storage.objects o where o.bucket_id = 'produtividade' and o.name = p_anexo) then
    perform app.erro('Anexe o documento assinado da ciência.', '22023');
  end if;
  update public.prod_avaliacoes set status = 'ciente', ciente_em = p_data::timestamptz, ciencia_meio = 'outro_meio', ciencia_anexo = p_anexo, ciencia_registrada_por = auth.uid(),
    prazo_recurso = public.somar_dias_uteis(p_data, coalesce((r.prazos ->> 'recurso')::int, 5)) where id = p_id;
  perform app.prod_hist(p_id, 'ciente', jsonb_build_object('meio', 'outro_meio', 'data', p_data));
end $$;

create or replace function public.prod_recorrer(p_id uuid, p_razoes text, p_anexo text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare a public.prod_avaliacoes := app.prod_av(p_id); r public.prod_regras := app.prod_regra_da(p_id); v_id uuid; v_rev uuid;
begin
  if not app.sessao_ok() or a.servidor_id is distinct from app.servidor_atual() then perform app.erro('Somente o próprio servidor pode recorrer.', '42501'); end if;
  if a.status <> 'ciente' or a.prazo_recurso is null or current_date > a.prazo_recurso then
    perform app.erro('Fora do prazo de recurso.', '22023');
  end if;
  if p_anexo is not null and (p_anexo not like 'avaliacoes/' || p_id::text || '/%' or not exists (select 1 from storage.objects o where o.bucket_id = 'produtividade' and o.name = p_anexo)) then
    perform app.erro('Anexo inválido.', '22023');
  end if;
  -- autoridade revisora designada, sem conflito com o avaliado nem com quem avaliou
  select d.usuario_id into v_rev from public.prod_designacoes d join public.usuarios u on u.id = d.usuario_id
   where d.papel = 'revisora' and u.ativo and d.inicio <= current_date and (d.fim is null or d.fim >= current_date)
     and d.usuario_id is distinct from auth.uid() and d.usuario_id is distinct from app.usuario_do_servidor(a.avaliador_id)
   order by d.inicio limit 1;
  insert into public.prod_recursos (avaliacao_id, razoes, anexo_path, prazo_revisao, revisor_id)
  values (p_id, btrim(p_razoes), p_anexo, public.somar_dias_uteis(current_date, coalesce((r.prazos ->> 'revisao')::int, 10)), v_rev)
  returning id into v_id;
  update public.prod_avaliacoes set status = 'em_recurso' where id = p_id;
  perform app.prod_hist(p_id, 'recurso', '{}'::jsonb);
  if v_rev is not null then
    perform app.notificar(v_rev, 'produtividade', 'Recurso de avaliação para decidir', 'Competência ' || to_char(a.competencia, 'MM/YYYY'), '/produtividade/avaliacao?id=' || p_id);
  else
    perform app.notificar(u.id, 'produtividade', 'Recurso sem autoridade revisora designada', 'Designe a autoridade revisora em Produtividade › Configuração', '/produtividade')
      from public.usuarios u where u.ativo and u.perfil in ('secretaria', 'administrador');
  end if;
  return v_id;
exception when check_violation then perform app.erro('Escreva as razões do recurso (mín. 10 caracteres).', '23514');
end $$;

-- revisão: decisão fundamentada; alteração de indicador sempre com justificativa
create or replace function public.prod_decidir_recurso(p_id uuid, p_fundamentacao text, p_notas jsonb default '[]'::jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.prod_avaliacoes := app.prod_av(p_id); rc public.prod_recursos; x jsonb; v_antes jsonb;
begin
  if not (app.sessao_ok() and app.tem_designacao('revisora')) then perform app.erro('Somente a autoridade revisora designada.', '42501'); end if;
  if a.status <> 'em_recurso' then perform app.erro('Avaliação não está em recurso.', '22023'); end if;
  select * into rc from public.prod_recursos where avaliacao_id = p_id and decidido_em is null order by criado_em desc limit 1;
  if rc.revisor_id is not null and rc.revisor_id <> auth.uid() then perform app.erro('Recurso dirigido a outra autoridade revisora.', '42501'); end if;
  if length(btrim(coalesce(p_fundamentacao, ''))) < 20 then perform app.erro('Decisão fundamentada obrigatória (mín. 20 caracteres).', '22023'); end if;
  update public.prod_recursos set revisor_id = auth.uid() where id = rc.id;   -- segregação conferida pelo trigger
  select jsonb_object_agg(indicador, jsonb_build_object('nota', nota, 'justificativa', justificativa)) into v_antes from public.prod_notas where avaliacao_id = p_id;
  for x in select * from jsonb_array_elements(coalesce(p_notas, '[]'::jsonb)) loop
    if length(btrim(coalesce(x ->> 'justificativa', ''))) < 10 then perform app.erro('Cada indicador alterado precisa de justificativa.', '22023'); end if;
    update public.prod_notas set nota = (x ->> 'nota')::numeric, justificativa = btrim(x ->> 'justificativa') where avaliacao_id = p_id and indicador = x ->> 'indicador';
    if not found then perform app.erro('Indicador inexistente.', '22023'); end if;
  end loop;
  update public.prod_recursos set fundamentacao = btrim(p_fundamentacao), decidido_em = now(), notas_antes = v_antes,
    notas_depois = (select jsonb_object_agg(indicador, jsonb_build_object('nota', nota, 'justificativa', justificativa)) from public.prod_notas where avaliacao_id = p_id)
   where id = rc.id;
  update public.prod_avaliacoes set status = 'aguardando_homologacao', total_funcional = (select sum(nota) from public.prod_notas where avaliacao_id = p_id) where id = p_id;
  perform app.prod_hist(p_id, 'recurso_decidido', jsonb_build_object('alterou', jsonb_array_length(coalesce(p_notas, '[]'::jsonb)) > 0));
  perform app.prod_avisar(a.servidor_id, 'Recurso decidido', 'Competência ' || to_char(a.competencia, 'MM/YYYY'), p_id);
exception when invalid_text_representation then perform app.erro('Nota inválida.', '22023');
end $$;

-- ===== homologação (art. 17): individual ou em lote; devolução com motivo =====
create or replace function public.prod_homologar(p_ids uuid[])
returns integer language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; a public.prod_avaliacoes; n integer := 0; v_ver integer;
begin
  if not (app.sessao_ok() and app.tem_designacao('homologacao')) then perform app.erro('Somente a instância de homologação designada.', '42501'); end if;
  foreach v_id in array coalesce(p_ids, '{}'::uuid[]) loop
    a := app.prod_av(v_id);
    if a.status <> 'aguardando_homologacao' then perform app.erro('Há avaliação que não está aguardando homologação.', '22023'); end if;
    update public.prod_avaliacoes set status = 'homologada', homologada_por = auth.uid(), homologada_em = now() where id = v_id;  -- segregação no trigger
    perform app.prod_hist(v_id, 'homologada', '{}'::jsonb);
    -- todos os períodos do servidor homologados: congela o demonstrativo
    if not exists (select 1 from public.prod_avaliacoes x where x.competencia = a.competencia and x.servidor_id = a.servidor_id and x.status not in ('homologada', 'retificada')) then
      select coalesce(max(versao), 0) + 1 into v_ver from public.prod_apuracoes where competencia = a.competencia and servidor_id = a.servidor_id;
      insert into public.prod_apuracoes (competencia, servidor_id, versao, dados)
      values (a.competencia, a.servidor_id, v_ver, app.prod_apurar(a.competencia, a.servidor_id) || jsonb_build_object('homologado_em', now(), 'versao', v_ver));
    end if;
    perform app.prod_avisar(a.servidor_id, 'Avaliação homologada', 'Competência ' || to_char(a.competencia, 'MM/YYYY'), v_id);
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.prod_devolver(p_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.prod_avaliacoes := app.prod_av(p_id);
begin
  if not (app.sessao_ok() and app.tem_designacao('homologacao')) then perform app.erro('Somente a instância de homologação designada.', '42501'); end if;
  if a.status <> 'aguardando_homologacao' then perform app.erro('Avaliação não está aguardando homologação.', '22023'); end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then perform app.erro('Informe o motivo da devolução (mín. 10 caracteres).', '22023'); end if;
  if a.avaliador_id = app.servidor_atual() or a.servidor_id = app.servidor_atual() then perform app.erro('Segregação de funções.', '42501'); end if;
  update public.prod_avaliacoes set status = 'rascunho', devolucao_motivo = btrim(p_motivo), enviada_em = null, ciente_em = null, ciencia_meio = null,
    ciencia_anexo = null, ciencia_registrada_por = null, prazo_recurso = null, sem_recurso_em = null where id = p_id;
  perform app.prod_hist(p_id, 'devolvida', jsonb_build_object('motivo', btrim(p_motivo)));
  if a.avaliador_id is not null then perform app.prod_avisar(a.avaliador_id, 'Avaliação devolvida pela homologação', btrim(p_motivo), p_id); end if;
end $$;

-- ===== retificação depois da homologação (art. 21-23): novo registro ligado ao original =====
create or replace function public.prod_retificar(p_id uuid, p_justificativa text, p_correcao text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare a public.prod_avaliacoes := app.prod_av(p_id); v_id uuid;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if a.status <> 'homologada' then perform app.erro('Só avaliação homologada é retificada.', '22023'); end if;
  if length(btrim(coalesce(p_justificativa, ''))) < 10 then perform app.erro('Justificativa obrigatória (mín. 10 caracteres).', '22023'); end if;
  update public.prod_avaliacoes set status = 'retificada' where id = p_id;
  insert into public.prod_avaliacoes (competencia, servidor_id, periodo_inicio, periodo_fim, unidade_id, avaliador_id, limitacoes, retifica_id, retificacao_justificativa)
  values (a.competencia, a.servidor_id, a.periodo_inicio, a.periodo_fim, a.unidade_id, a.avaliador_id, a.limitacoes, p_id, btrim(p_justificativa))
  returning id into v_id;
  insert into public.prod_notas (avaliacao_id, indicador, nota, justificativa, equivalente, justificativa_equivalente)
  select v_id, indicador, nota, justificativa, equivalente, justificativa_equivalente from public.prod_notas where avaliacao_id = p_id;
  insert into public.prod_provas (avaliacao_id, indicador, tipo, ref_id, path, nome, descricao, criado_por)
  select v_id, indicador, tipo, ref_id, path, nome, descricao, criado_por from public.prod_provas where avaliacao_id = p_id;
  perform app.prod_hist(p_id, 'retificada', jsonb_build_object('nova', v_id, 'justificativa', btrim(p_justificativa)));
  perform app.prod_hist(v_id, 'retificacao_aberta', jsonb_build_object('original', p_id));
  if p_correcao is not null then
    insert into public.prod_correcoes (competencia, servidor_id, avaliacao_id, descricao, nova_avaliacao_id, registrada_por)
    values (a.competencia, a.servidor_id, p_id, btrim(p_correcao), v_id, auth.uid());
  end if;
  if a.avaliador_id is not null then perform app.prod_avisar(a.avaliador_id, 'Avaliação em retificação', btrim(p_justificativa), v_id); end if;
  return v_id;
end $$;

-- ===== encaminhamento à SEMAD (art. 19): versão do arquivo registrada =====
create or replace function public.prod_encaminhar_semad(p_comp date, p_observacao text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_comp date := date_trunc('month', p_comp)::date; v_id uuid; v_ver integer; v_linhas jsonb;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if not exists (select 1 from public.prod_competencias where competencia = v_comp) then perform app.erro('Competência não aberta.', 'P0002'); end if;
  if exists (select 1 from public.prod_avaliacoes where competencia = v_comp and status not in ('homologada', 'retificada')) then
    perform app.erro('Há avaliações não homologadas nesta competência.', '22023');
  end if;
  select coalesce(jsonb_agg(d.dados || jsonb_build_object('servidor', s.nome_completo, 'matricula', s.matricula, 'cargo', cg.nome, 'unidade', un.sigla) order by s.nome_completo), '[]'::jsonb)
    into v_linhas
    from (select distinct on (servidor_id) servidor_id, dados from public.prod_apuracoes where competencia = v_comp order by servidor_id, versao desc) d
    join public.servidores s on s.id = d.servidor_id left join public.cargos cg on cg.id = s.cargo_id left join public.unidades un on un.id = s.unidade_id;
  if jsonb_array_length(v_linhas) = 0 then perform app.erro('Nada homologado para encaminhar.', '22023'); end if;
  select coalesce(max(versao), 0) + 1 into v_ver from public.prod_encaminhamentos where competencia = v_comp;
  insert into public.prod_encaminhamentos (competencia, versao, linhas, observacao, gerado_por) values (v_comp, v_ver, v_linhas, p_observacao, auth.uid())
  returning id into v_id;
  update public.prod_competencias set status = 'encaminhada' where competencia = v_comp;
  return v_id;
end $$;

-- inconsistência apontada pela SEMAD: registro de correção ligado (nada é apagado)
create or replace function public.prod_registrar_inconsistencia(p_comp date, p_servidor uuid, p_descricao text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  insert into public.prod_correcoes (competencia, servidor_id, avaliacao_id, descricao, registrada_por)
  values (date_trunc('month', p_comp)::date, p_servidor,
          (select id from public.prod_avaliacoes where competencia = date_trunc('month', p_comp)::date and servidor_id = p_servidor and status = 'homologada' order by periodo_inicio limit 1),
          btrim(p_descricao), auth.uid())
  returning id into v_id;
  return v_id;
exception when check_violation then perform app.erro('Descreva a inconsistência (mín. 10 caracteres).', '23514');
end $$;

-- ===== listagens e subsídios =====
create or replace function public.prod_listar(p_comp date)
returns table (id uuid, servidor_id uuid, servidor text, matricula text, unidade text, avaliador text, avaliador_id uuid, periodo_inicio date, periodo_fim date,
               status text, total_funcional numeric, prazo_recurso date, pendencias integer, retifica_id uuid, sou_avaliador boolean)
language sql stable security definer set search_path = ''
as $$
  select a.id, a.servidor_id, s.nome_completo, s.matricula, u.sigla, av.nome_completo, a.avaliador_id, a.periodo_inicio, a.periodo_fim, a.status,
         a.total_funcional, a.prazo_recurso, case when a.status = 'rascunho' then cardinality(app.prod_pendencias_envio(a.id)) else 0 end, a.retifica_id,
         a.avaliador_id = app.servidor_atual()
    from public.prod_avaliacoes a join public.servidores s on s.id = a.servidor_id left join public.unidades u on u.id = a.unidade_id
    left join public.servidores av on av.id = a.avaliador_id
   where a.competencia = date_trunc('month', p_comp)::date and app.pode_ver_avaliacao(a.id)
     and (a.servidor_id <> app.servidor_atual() or app.gestor_geral() or a.status <> 'rascunho')
   order by u.sigla, s.nome_completo, a.periodo_inicio
$$;

-- painel de subsídios do mês: SÓ FATOS (adendo 3.2.6); nenhuma nota sugerida
create or replace function public.prod_subsidios(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare a public.prod_avaliacoes := app.prod_av(p_id); v_ini timestamptz; v_fim timestamptz;
begin
  if not app.pode_ver_avaliacao(p_id) then perform app.erro('Acesso não permitido.', '42501'); end if;
  v_ini := (a.periodo_inicio::timestamp at time zone 'America/Maceio'); v_fim := ((a.periodo_fim + 1)::timestamp at time zone 'America/Maceio');
  return jsonb_build_object(
    'recebidas', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'numero', d.numero, 'titulo', d.titulo) order by d.numero)
                  from public.demanda_responsaveis r join public.demandas d on d.id = r.demanda_id
                 where r.servidor_id = a.servidor_id and r.adicionado_em >= v_ini and r.adicionado_em < v_fim and d.status not in ('sugerida', 'recusada', 'cancelada')), '[]'),
    'concluidas', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'numero', d.numero, 'titulo', d.titulo, 'no_prazo', d.prazo is null or (d.concluida_em at time zone 'America/Maceio')::date <= d.prazo,
                     'dias_uteis', public.dias_uteis_entre((r.adicionado_em at time zone 'America/Maceio')::date, (d.concluida_em at time zone 'America/Maceio')::date)) order by d.numero)
                  from public.demanda_responsaveis r join public.demandas d on d.id = r.demanda_id
                 where r.servidor_id = a.servidor_id and d.status = 'concluida' and d.concluida_em >= v_ini and d.concluida_em < v_fim), '[]'),
    'atrasadas', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'numero', d.numero, 'titulo', d.titulo, 'prazo', d.prazo) order by d.prazo)
                  from public.demanda_responsaveis r join public.demandas d on d.id = r.demanda_id
                 where r.servidor_id = a.servidor_id and r.ativo and d.prazo is not null and d.prazo between a.periodo_inicio and a.periodo_fim
                   and (d.status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao') and d.prazo < current_date
                        or d.status = 'concluida' and (d.concluida_em at time zone 'America/Maceio')::date > d.prazo)), '[]'),
    'checklist', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'demanda_id', c.demanda_id, 'texto', c.texto) order by c.feito_em)
                  from public.demanda_checklist c where c.feito and not c.removido and c.feito_por = app.usuario_do_servidor(a.servidor_id)
                   and c.feito_em >= v_ini and c.feito_em < v_fim), '[]'),
    'feedbacks', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'demanda_id', m.demanda_id, 'feedback', m.feedback, 'comentario', m.feedback_comentario) order by m.feedback_em)
                  from public.demanda_mensagens m where m.autor_id = app.usuario_do_servidor(a.servidor_id) and m.feedback is not null
                   and m.feedback_em >= v_ini and m.feedback_em < v_fim), '[]'),
    'afastamentos', coalesce((select jsonb_agg(jsonb_build_object('tipo', af.tipo, 'inicio', greatest(af.inicio, a.periodo_inicio), 'fim', least(af.fim, a.periodo_fim),
                     'dias', least(af.fim, a.periodo_fim) - greatest(af.inicio, a.periodo_inicio) + 1) order by af.inicio)
                  from public.afastamentos af where af.servidor_id = a.servidor_id and af.status = 'aprovado' and af.inicio <= a.periodo_fim and af.fim >= a.periodo_inicio), '[]')
  );
end $$;

-- formulário completo (para a tela e o Anexo I)
create or replace function public.prod_avaliacao_detalhe(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare a public.prod_avaliacoes := app.prod_av(p_id); r public.prod_regras := app.prod_regra_da(p_id);
begin
  if not app.pode_ver_avaliacao(p_id) then perform app.erro('Acesso não permitido.', '42501'); end if;
  if a.status = 'rascunho' and a.servidor_id = app.servidor_atual() and not app.gestor_geral() then perform app.erro('Avaliação ainda não enviada.', '42501'); end if;
  return jsonb_build_object(
    'avaliacao', to_jsonb(a) || jsonb_build_object(
       'servidor', (select nome_completo from public.servidores where id = a.servidor_id),
       'matricula', (select matricula from public.servidores where id = a.servidor_id),
       'cargo', (select cg.nome from public.servidores s join public.cargos cg on cg.id = s.cargo_id where s.id = a.servidor_id),
       'exerce_comissao', (select exerce_comissao from public.servidores where id = a.servidor_id),
       'unidade', (select sigla from public.unidades where id = a.unidade_id),
       'avaliador', (select nome_completo from public.servidores where id = a.avaliador_id),
       'homologada_por_nome', app.nome_usuario(a.homologada_por),
       'ciencia_registrada_por_nome', app.nome_usuario(a.ciencia_registrada_por)),
    'regra', jsonb_build_object('versao', r.versao, 'indicadores', r.indicadores, 'max_funcional', r.max_funcional, 'prazos', r.prazos),
    'notas', coalesce((select jsonb_agg(to_jsonb(n)) from public.prod_notas n where n.avaliacao_id = p_id), '[]'),
    'provas', coalesce((select jsonb_agg(to_jsonb(p) || jsonb_build_object('titulo', case p.tipo
                          when 'demanda' then (select '#' || numero || ' ' || titulo from public.demandas where id = p.ref_id)
                          when 'checklist' then (select texto from public.demanda_checklist where id = p.ref_id)
                          when 'mensagem' then (select left(texto, 120) from public.demanda_mensagens where id = p.ref_id)
                          else coalesce(p.nome, p.descricao) end,
                        'demanda_id', case p.tipo when 'demanda' then p.ref_id when 'checklist' then (select demanda_id from public.demanda_checklist where id = p.ref_id)
                                                  when 'mensagem' then (select demanda_id from public.demanda_mensagens where id = p.ref_id) end) order by p.criado_em)
                       from public.prod_provas p where p.avaliacao_id = p_id), '[]'),
    'recursos', coalesce((select jsonb_agg(to_jsonb(x) || jsonb_build_object('revisor', app.nome_usuario(x.revisor_id)) order by x.criado_em) from public.prod_recursos x where x.avaliacao_id = p_id), '[]'),
    'historico', coalesce((select jsonb_agg(jsonb_build_object('em', h.em, 'acao', h.acao, 'detalhes', h.detalhes, 'ator', app.nome_usuario(h.ator_id)) order by h.em) from public.prod_historico h where h.avaliacao_id = p_id), '[]'),
    'pendencias_envio', to_jsonb(app.prod_pendencias_envio(p_id)),
    'permissoes', jsonb_build_object(
       'editar', a.status = 'rascunho' and app.prod_eh_avaliador(a),
       'ciencia', a.status = 'enviada' and a.servidor_id = app.servidor_atual(),
       'ciencia_outro_meio', a.status = 'enviada' and (app.prod_eh_avaliador(a) or app.gestor_geral()),
       'recorrer', a.status = 'ciente' and a.servidor_id = app.servidor_atual() and current_date <= a.prazo_recurso,
       'decidir_recurso', a.status = 'em_recurso' and app.tem_designacao('revisora') and auth.uid() not in (coalesce(app.usuario_do_servidor(a.servidor_id), gen_random_uuid()), coalesce(app.usuario_do_servidor(a.avaliador_id), gen_random_uuid())),
       'homologar', a.status = 'aguardando_homologacao' and app.tem_designacao('homologacao'),
       'retificar', a.status = 'homologada' and app.gestor_geral(),
       'gerir', app.gestor_geral())
  );
end $$;

-- painel do funcionário: "Minha produtividade"
create or replace function public.prod_minhas()
returns table (competencia date, avaliacao_id uuid, status text, total_funcional numeric, prazo_recurso date, nota_enquadramento integer, percentual numeric, homologada boolean)
language sql stable security definer set search_path = ''
as $$
  select a.competencia, a.id, a.status, a.total_funcional, a.prazo_recurso,
         (select (dados ->> 'nota_enquadramento')::int from public.prod_apuracoes p where p.competencia = a.competencia and p.servidor_id = a.servidor_id order by versao desc limit 1),
         (select (dados ->> 'percentual')::numeric from public.prod_apuracoes p where p.competencia = a.competencia and p.servidor_id = a.servidor_id order by versao desc limit 1),
         a.status = 'homologada'
    from public.prod_avaliacoes a
   where app.sessao_ok() and a.servidor_id = app.servidor_atual() and a.status not in ('rascunho', 'retificada')
   order by a.competencia desc, a.periodo_inicio desc limit 24
$$;

-- painéis: só agregados por unidade, sem nome (adendo 8)
create or replace function public.prod_resumo(p_comp date)
returns table (unidade text, total integer, rascunho integer, enviada integer, ciente integer, em_recurso integer, aguardando integer, homologada integer)
language sql stable security definer set search_path = ''
as $$
  select u.sigla, count(*)::int, count(*) filter (where a.status = 'rascunho')::int, count(*) filter (where a.status = 'enviada')::int,
         count(*) filter (where a.status = 'ciente')::int, count(*) filter (where a.status = 'em_recurso')::int,
         count(*) filter (where a.status = 'aguardando_homologacao')::int, count(*) filter (where a.status = 'homologada')::int
    from public.prod_avaliacoes a left join public.unidades u on u.id = a.unidade_id
   where a.competencia = date_trunc('month', p_comp)::date and a.status <> 'retificada' and app.sessao_ok()
     and (app.gestor_geral() or app.tem_designacao('homologacao') or (app.perfil_atual() in ('diretor', 'coordenador') and app.na_escopo(a.unidade_id)))
   group by u.sigla order by u.sigla
$$;

-- ===== rotina diária: prazos e alertas (adendo 6.10) =====
create or replace function app.prod_alerta_uma_vez(p_av uuid, p_tipo text, p_chave text default '')
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.prod_alertas (avaliacao_id, tipo, chave) values (p_av, p_tipo, coalesce(p_chave, ''));
  return true;
exception when unique_violation then return false;
end $$;

create or replace function app.rotina_produtividade()
returns integer language plpgsql security definer set search_path = ''
as $$
declare a record; n integer := 0; v_u uuid;
begin
  -- prazo de recurso esgotado sem recurso → aguardando homologação
  for a in select * from public.prod_avaliacoes where status = 'ciente' and prazo_recurso < current_date loop
    update public.prod_avaliacoes set status = 'aguardando_homologacao', sem_recurso_em = now() where id = a.id;
    insert into public.prod_historico (avaliacao_id, acao, detalhes) values (a.id, 'sem_recurso', jsonb_build_object('prazo', a.prazo_recurso));
    n := n + 1;
  end loop;
  -- ciência pendente além do prazo → chefia e Secretária
  for a in select av.*, r.prazos from public.prod_avaliacoes av join public.prod_competencias c on c.competencia = av.competencia join public.prod_regras r on r.id = c.regra_id
            where av.status = 'enviada' and public.dias_uteis_entre(av.enviada_em::date, current_date) >= coalesce((r.prazos ->> 'ciencia')::int, 3) loop
    if app.prod_alerta_uma_vez(a.id, 'ciencia_pendente') then
      perform app.prod_avisar(a.avaliador_id, 'Ciência pendente', 'Servidor ainda não deu ciência; registre por outro meio se preciso', a.id);
      for v_u in select u.id from public.usuarios u where u.ativo and u.perfil = 'secretaria' loop
        perform app.notificar(v_u, 'produtividade', 'Ciência pendente', 'Avaliação sem ciência do servidor', '/produtividade/avaliacao?id=' || a.id);
      end loop;
    end if;
  end loop;
  -- prazo de recurso terminando (último dia) → servidor
  for a in select * from public.prod_avaliacoes where status = 'ciente' and prazo_recurso = current_date loop
    if app.prod_alerta_uma_vez(a.id, 'recurso_termina') then perform app.prod_avisar(a.servidor_id, 'Prazo de recurso termina hoje', 'Avaliação de desempenho', a.id); end if;
  end loop;
  -- revisão a partir do 8º dia útil → revisora e Secretária
  for a in select av.id, rc.revisor_id, rc.criado_em, r.prazos from public.prod_avaliacoes av join public.prod_recursos rc on rc.avaliacao_id = av.id and rc.decidido_em is null
             join public.prod_competencias c on c.competencia = av.competencia join public.prod_regras r on r.id = c.regra_id
            where av.status = 'em_recurso' and public.dias_uteis_entre(rc.criado_em::date, current_date) >= coalesce((r.prazos ->> 'alerta_revisao')::int, 8) loop
    if app.prod_alerta_uma_vez(a.id, 'revisao_prazo') then
      for v_u in select a.revisor_id union select u.id from public.usuarios u where u.ativo and u.perfil = 'secretaria' loop
        continue when v_u is null;
        perform app.notificar(v_u, 'produtividade', 'Revisão perto do prazo', 'Recurso aguardando decisão', '/produtividade/avaliacao?id=' || a.id);
      end loop;
    end if;
  end loop;
  -- rascunho perto do fechamento → chefia (uma vez)
  for a in select av.* from public.prod_avaliacoes av join public.prod_competencias c on c.competencia = av.competencia join public.prod_regras r on r.id = c.regra_id
            where av.status = 'rascunho' and c.fechamento - current_date between 0 and coalesce((r.prazos ->> 'alerta_rascunho')::int, 3) loop
    if app.prod_alerta_uma_vez(a.id, 'rascunho_fechamento') then perform app.prod_avisar(a.avaliador_id, 'Avaliação em rascunho perto do fechamento', 'Envie ao servidor', a.id); end if;
  end loop;
  -- competência pronta para homologar → instância de homologação (uma vez por competência)
  for a in select c.competencia from public.prod_competencias c where c.status = 'aberta'
             and exists (select 1 from public.prod_avaliacoes x where x.competencia = c.competencia and x.status = 'aguardando_homologacao')
             and not exists (select 1 from public.prod_avaliacoes x where x.competencia = c.competencia and x.status in ('rascunho', 'enviada', 'ciente', 'em_recurso')) loop
    if app.prod_alerta_uma_vez('00000000-0000-0000-0000-000000000000', 'competencia_pronta', a.competencia::text) then
      for v_u in select d.usuario_id from public.prod_designacoes d where d.papel = 'homologacao' and d.inicio <= current_date and (d.fim is null or d.fim >= current_date) loop
        perform app.notificar(v_u, 'produtividade', 'Competência pronta para homologar', to_char(a.competencia, 'MM/YYYY'), '/produtividade');
      end loop;
    end if;
  end loop;
  return n;
end $$;

create or replace function app.rotinas_diarias_demandas()
returns void language plpgsql security definer set search_path = ''
as $$ begin perform app.gerar_ocorrencias(); perform app.aplicar_substituicoes(); perform app.rotina_contratos(); perform app.rotina_produtividade(); perform app.avisar_prazos(); end $$;
revoke execute on function app.rotinas_diarias_demandas(), app.rotina_produtividade() from public, anon, authenticated;

grant execute on function public.prod_abrir_competencia(date, date), public.prod_dividir_periodo(uuid, date, uuid, uuid), public.prod_trocar_avaliador(uuid, uuid),
  public.prod_salvar_avaliacao(uuid, jsonb, text), public.prod_adicionar_prova(uuid, text, text, uuid, text, text, text), public.prod_remover_prova(uuid),
  public.prod_enviar(uuid), public.prod_dar_ciencia(uuid), public.prod_ciencia_outro_meio(uuid, date, text), public.prod_recorrer(uuid, text, text),
  public.prod_decidir_recurso(uuid, text, jsonb), public.prod_homologar(uuid[]), public.prod_devolver(uuid, text), public.prod_retificar(uuid, text, text),
  public.prod_encaminhar_semad(date, text), public.prod_registrar_inconsistencia(date, uuid, text), public.prod_listar(date), public.prod_subsidios(uuid),
  public.prod_avaliacao_detalhe(uuid), public.prod_minhas(), public.prod_resumo(date) to authenticated;
