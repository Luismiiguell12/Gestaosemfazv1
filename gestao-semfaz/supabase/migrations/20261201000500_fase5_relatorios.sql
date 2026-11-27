-- Fase 5 · relatórios da produtividade (adendo 12: Anexo I, Anexo II, arquivo SEMAD e Dossiê do ciclo)

-- resultado por servidor da competência (só quem o perfil pode ver; demonstrativo congelado se homologado)
create or replace function public.relatorio_produtividade(p_comp date)
returns table (servidor text, matricula text, unidade text, situacao text, pontos_funcionais numeric, pontos_institucionais numeric, regra text,
               nota_total numeric, nota_enquadramento integer, percentual numeric, dias_elegiveis integer, dias_mes integer, fator numeric, percentual_efetivo numeric, homologado boolean)
language plpgsql stable security definer set search_path = ''
as $$
declare v_comp date := date_trunc('month', p_comp)::date; s record; d jsonb;
begin
  if not app.pode_relatorio('produtividade') then return; end if;
  for s in select distinct on (a.servidor_id) a.servidor_id, sv.nome_completo, sv.matricula, u.sigla,
                  (select string_agg(distinct x.status, ', ') from public.prod_avaliacoes x where x.competencia = v_comp and x.servidor_id = a.servidor_id and x.status <> 'retificada') st
             from public.prod_avaliacoes a join public.servidores sv on sv.id = a.servidor_id left join public.unidades u on u.id = sv.unidade_id
            where a.competencia = v_comp and a.status <> 'retificada' and app.pode_ver_avaliacao(a.id)
              and (a.status <> 'rascunho' or app.gestor_geral() or a.avaliador_id = app.servidor_atual())
            order by a.servidor_id loop
    select dados into d from public.prod_apuracoes where competencia = v_comp and servidor_id = s.servidor_id order by versao desc limit 1;
    d := coalesce(d, app.prod_apurar(v_comp, s.servidor_id) || '{"provisorio": true}');
    return query select s.nome_completo, s.matricula, s.sigla, s.st, (d ->> 'pontos_funcionais')::numeric, (d ->> 'pontos_institucionais')::numeric,
      case when (d ->> 'transicao')::boolean then 'transição' else 'normal' end, (d ->> 'nota_total')::numeric, (d ->> 'nota_enquadramento')::int,
      (d ->> 'percentual')::numeric, (d ->> 'dias_elegiveis')::int, (d ->> 'dias_mes')::int, (d ->> 'fator')::numeric, (d ->> 'percentual_efetivo')::numeric,
      not coalesce((d ->> 'provisorio')::boolean, false);
  end loop;
end $$;

-- Dossiê do ciclo (adendo 9): tudo da competência para o Controle Interno — Secretária/Administrador
create or replace function public.relatorio_dossie(p_comp date)
returns table (servidor text, matricula text, unidade text, periodo text, chefia text, situacao text, pontos numeric, provas integer, enviada_em timestamptz,
               ciencia text, recurso text, homologacao text, retificacao text, demonstrativo_versao integer, encaminhamentos text, correcoes integer)
language plpgsql stable security definer set search_path = ''
as $$
declare v_comp date := date_trunc('month', p_comp)::date;
begin
  if not (app.pode_relatorio('produtividade') and app.gestor_geral()) then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  return query
    select sv.nome_completo, sv.matricula, u.sigla, to_char(a.periodo_inicio, 'DD/MM') || ' a ' || to_char(a.periodo_fim, 'DD/MM/YYYY'),
           av.nome_completo, a.status, a.total_funcional, (select count(*)::int from public.prod_provas p where p.avaliacao_id = a.id), a.enviada_em,
           case when a.ciente_em is null then 'pendente' else to_char(a.ciente_em at time zone 'America/Maceio', 'DD/MM/YYYY HH24:MI') || case when a.ciencia_meio = 'outro_meio' then ' (outro meio, com anexo)' else '' end end,
           coalesce((select string_agg(to_char(r.criado_em at time zone 'America/Maceio', 'DD/MM/YYYY') || case when r.decidido_em is null then ' · pendente' else ' · decidido por ' || coalesce(app.nome_usuario(r.revisor_id), '—') end, '; ')
                       from public.prod_recursos r where r.avaliacao_id = a.id), case when a.sem_recurso_em is not null then 'sem recurso (prazo esgotado)' else '—' end),
           case when a.homologada_em is null then 'pendente' else to_char(a.homologada_em at time zone 'America/Maceio', 'DD/MM/YYYY') || ' · ' || coalesce(app.nome_usuario(a.homologada_por), '—') end,
           case when a.retifica_id is not null then 'retifica avaliação anterior: ' || coalesce(a.retificacao_justificativa, '')
                when a.status = 'retificada' then 'substituída por retificação' else '—' end,
           (select max(p.versao) from public.prod_apuracoes p where p.competencia = v_comp and p.servidor_id = a.servidor_id),
           coalesce((select string_agg('v' || e.versao || ' em ' || to_char(e.gerado_em at time zone 'America/Maceio', 'DD/MM/YYYY'), ', ' order by e.versao) from public.prod_encaminhamentos e where e.competencia = v_comp), '—'),
           (select count(*)::int from public.prod_correcoes c where c.competencia = v_comp and c.servidor_id = a.servidor_id)
      from public.prod_avaliacoes a join public.servidores sv on sv.id = a.servidor_id left join public.unidades u on u.id = a.unidade_id
      left join public.servidores av on av.id = a.avaliador_id
     where a.competencia = v_comp
     order by u.sigla, sv.nome_completo, a.periodo_inicio, a.criado_em;
end $$;

grant execute on function public.relatorio_produtividade(date), public.relatorio_dossie(date) to authenticated;
