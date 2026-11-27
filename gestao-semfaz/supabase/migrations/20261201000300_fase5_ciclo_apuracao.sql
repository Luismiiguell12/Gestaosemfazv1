-- Fase 5 · ciclo mensal de avaliação (adendo seções 3, 5, 6 e 9): tabelas, acesso, imutabilidade, segregação e apuração

create table public.prod_competencias (
  competencia date primary key check (extract(day from competencia) = 1),
  regra_id uuid not null references public.prod_regras (id),
  fechamento date not null,
  status text not null default 'aberta' check (status in ('aberta', 'encaminhada')),
  aberta_por uuid references public.usuarios (id),
  aberta_em timestamptz not null default now()
);

create table public.prod_avaliacoes (
  id uuid primary key default gen_random_uuid(),
  competencia date not null references public.prod_competencias (competencia),
  servidor_id uuid not null references public.servidores (id),
  periodo_inicio date not null,
  periodo_fim date not null,
  unidade_id uuid references public.unidades (id),
  avaliador_id uuid references public.servidores (id),
  status text not null default 'rascunho'
    check (status in ('rascunho', 'enviada', 'ciente', 'em_recurso', 'aguardando_homologacao', 'homologada', 'retificada')),
  limitacoes text check (limitacoes is null or length(limitacoes) <= 3000),
  total_funcional numeric(6,2),
  enviada_em timestamptz,
  ciente_em timestamptz,
  ciencia_meio text check (ciencia_meio in ('sistema', 'outro_meio')),
  ciencia_anexo text,
  ciencia_registrada_por uuid references public.usuarios (id),
  prazo_recurso date,
  sem_recurso_em timestamptz,
  homologada_por uuid references public.usuarios (id),
  homologada_em timestamptz,
  devolucao_motivo text,
  retifica_id uuid references public.prod_avaliacoes (id),
  retificacao_justificativa text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint prod_av_periodo check (periodo_fim >= periodo_inicio and date_trunc('month', periodo_inicio) = competencia and date_trunc('month', periodo_fim) = competencia),
  constraint prod_av_autoavaliacao check (avaliador_id is distinct from servidor_id),          -- ninguém avalia a si mesmo
  constraint prod_av_ciencia_outro_meio check (ciencia_meio is distinct from 'outro_meio' or ciencia_anexo is not null)
);
create unique index prod_av_periodo_uk on public.prod_avaliacoes (competencia, servidor_id, periodo_inicio) where status <> 'retificada';
create index prod_av_avaliador_idx on public.prod_avaliacoes (avaliador_id, competencia);
create trigger prod_av_atualizado before update on public.prod_avaliacoes for each row execute function app.tocar_atualizado_em();

create table public.prod_notas (
  avaliacao_id uuid not null references public.prod_avaliacoes (id),
  indicador text not null,
  nota numeric(5,2) check (nota >= 0 and nota <= 100),          -- e o trigger confere o máximo do indicador
  justificativa text check (justificativa is null or length(justificativa) <= 4000),
  equivalente boolean not null default false,
  justificativa_equivalente text check (justificativa_equivalente is null or length(justificativa_equivalente) <= 2000),
  primary key (avaliacao_id, indicador)
);

create table public.prod_provas (
  id uuid primary key default gen_random_uuid(),
  avaliacao_id uuid not null references public.prod_avaliacoes (id),
  indicador text not null,
  tipo text not null check (tipo in ('demanda', 'checklist', 'mensagem', 'anexo', 'externa')),
  ref_id uuid,
  path text,
  nome text check (nome is null or length(nome) <= 200),
  descricao text check (descricao is null or length(descricao) <= 1000),
  criado_por uuid references public.usuarios (id),
  criado_em timestamptz not null default now(),
  constraint prod_provas_coerente check (
    (tipo in ('demanda', 'checklist', 'mensagem') and ref_id is not null) or (tipo = 'anexo' and path is not null) or (tipo = 'externa' and length(btrim(coalesce(descricao, ''))) >= 3))
);
create index prod_provas_av_idx on public.prod_provas (avaliacao_id, indicador);

create table public.prod_recursos (
  id uuid primary key default gen_random_uuid(),
  avaliacao_id uuid not null references public.prod_avaliacoes (id),
  razoes text not null check (length(btrim(razoes)) between 10 and 6000),
  anexo_path text,
  criado_em timestamptz not null default now(),
  prazo_revisao date not null,
  revisor_id uuid references public.usuarios (id),
  fundamentacao text check (fundamentacao is null or length(btrim(fundamentacao)) >= 20),
  decidido_em timestamptz,
  notas_antes jsonb,
  notas_depois jsonb,
  constraint prod_recurso_decisao check ((decidido_em is null) = (fundamentacao is null))
);

create table public.prod_historico (
  id bigint generated always as identity primary key,
  avaliacao_id uuid not null references public.prod_avaliacoes (id),
  em timestamptz not null default now(),
  ator_id uuid references public.usuarios (id),
  acao text not null,
  detalhes jsonb not null default '{}'::jsonb
);

-- demonstrativo congelado na homologação (memória de cálculo guardada para sempre)
create table public.prod_apuracoes (
  competencia date not null,
  servidor_id uuid not null references public.servidores (id),
  versao integer not null,
  dados jsonb not null,
  criado_em timestamptz not null default now(),
  primary key (competencia, servidor_id, versao)
);

create table public.prod_encaminhamentos (
  id uuid primary key default gen_random_uuid(),
  competencia date not null references public.prod_competencias (competencia),
  versao integer not null,
  linhas jsonb not null,
  observacao text,
  gerado_por uuid references public.usuarios (id),
  gerado_em timestamptz not null default now(),
  unique (competencia, versao)
);

create table public.prod_correcoes (
  id uuid primary key default gen_random_uuid(),
  competencia date not null,
  servidor_id uuid not null references public.servidores (id),
  avaliacao_id uuid references public.prod_avaliacoes (id),
  descricao text not null check (length(btrim(descricao)) between 10 and 3000),
  nova_avaliacao_id uuid references public.prod_avaliacoes (id),
  registrada_por uuid references public.usuarios (id),
  em timestamptz not null default now()
);

create table public.prod_alertas (
  avaliacao_id uuid not null,
  tipo text not null,
  chave text not null default '',
  em timestamptz not null default now(),
  primary key (avaliacao_id, tipo, chave)
);

-- ===== guarda permanente e imutabilidade (adendo 9) =====
do $$
declare t text;
begin
  foreach t in array array['prod_historico', 'prod_apuracoes', 'prod_encaminhamentos', 'prod_correcoes'] loop
    execute format('create trigger %I before update or delete on public.%I for each row execute function app.auditoria_imutavel()', t || '_imutavel', t);
  end loop;
end $$;
create trigger prod_avaliacoes_sem_delete before delete on public.prod_avaliacoes for each row execute function app.auditoria_imutavel();
create trigger prod_recursos_sem_delete before delete on public.prod_recursos for each row execute function app.auditoria_imutavel();

-- avaliação homologada não muda (só passa a "retificada"); retificada nunca muda
create or replace function app.prod_av_imutavel()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if old.status = 'retificada' or (old.status = 'homologada' and (new.status <> 'retificada'
       or (to_jsonb(new) - array['status', 'atualizado_em']) is distinct from (to_jsonb(old) - array['status', 'atualizado_em']))) then
    raise exception using message = 'Avaliação homologada não pode ser alterada. Use retificação.', errcode = '42501';
  end if;
  return new;
end $$;
create trigger prod_av_imutavel before update on public.prod_avaliacoes for each row execute function app.prod_av_imutavel();

-- notas e provas: só com a avaliação em rascunho (chefia) ou em recurso (revisora); nota ≤ máximo da versão da regra
create or replace function app.prod_nota_valida()
returns trigger language plpgsql set search_path = ''
as $$
declare a public.prod_avaliacoes; v_max numeric; v_av uuid := case when tg_op = 'DELETE' then old.avaliacao_id else new.avaliacao_id end;
begin
  select * into a from public.prod_avaliacoes where id = v_av;
  if a.status not in ('rascunho', 'em_recurso') then
    raise exception using message = 'Notas e provas só mudam com a avaliação em rascunho (ou em recurso, pela autoridade revisora).', errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  if tg_table_name = 'prod_notas' then
    select (x ->> 'maximo')::numeric into v_max
      from public.prod_competencias c join public.prod_regras r on r.id = c.regra_id, jsonb_array_elements(r.indicadores) x
     where c.competencia = a.competencia and x ->> 'codigo' = new.indicador;
    if v_max is null then raise exception using message = 'Indicador inexistente na regra deste ciclo.', errcode = '23514'; end if;
    if new.nota is not null and (new.nota < 0 or new.nota > v_max) then
      raise exception using message = format('Nota do indicador %s deve ficar entre 0 e %s.', new.indicador, v_max), errcode = '23514';
    end if;
  end if;
  return new;
end $$;
create trigger prod_notas_valida before insert or update or delete on public.prod_notas for each row execute function app.prod_nota_valida();
create trigger prod_provas_valida before insert or update or delete on public.prod_provas for each row execute function app.prod_nota_valida();

-- segregação (adendo 6.7), garantida no banco inclusive para o Administrador
create or replace function app.prod_segregacao()
returns trigger language plpgsql set search_path = ''
as $$
declare a public.prod_avaliacoes; v_serv uuid; v_aval uuid; v_rev uuid;
begin
  if tg_table_name = 'prod_recursos' then
    if new.revisor_id is null then return new; end if;
    select * into a from public.prod_avaliacoes where id = new.avaliacao_id;
  else
    if new.homologada_por is null or new.homologada_por is not distinct from old.homologada_por then return new; end if;
    a := new;
  end if;
  v_serv := app.usuario_do_servidor(a.servidor_id);
  v_aval := app.usuario_do_servidor(a.avaliador_id);
  if tg_table_name = 'prod_recursos' then
    if new.revisor_id in (v_serv, v_aval) then
      raise exception using message = 'Segregação de funções: quem avaliou (ou o próprio servidor) não pode revisar.', errcode = '42501';
    end if;
  else
    select r.revisor_id into v_rev from public.prod_recursos r where r.avaliacao_id = a.id and r.decidido_em is not null order by r.criado_em desc limit 1;
    if new.homologada_por in (v_serv, v_aval) or new.homologada_por is not distinct from v_rev then
      raise exception using message = 'Segregação de funções: quem foi avaliado, avaliou ou revisou não pode homologar.', errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger prod_av_segregacao before update on public.prod_avaliacoes for each row execute function app.prod_segregacao();
create trigger prod_recurso_segregacao before insert or update on public.prod_recursos for each row execute function app.prod_segregacao();

-- ===== quem vê (adendo 8) =====
create or replace function app.pode_ver_avaliacao(p_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select app.sessao_ok() and exists (
    select 1 from public.prod_avaliacoes a where a.id = p_id and (
      app.gestor_geral()
      or (a.servidor_id = app.servidor_atual() and a.status <> 'rascunho')                                   -- servidor: a própria, depois de enviada
      or a.avaliador_id = app.servidor_atual()                                                                -- chefia que avalia
      or (app.perfil_atual() = 'diretor' and app.na_escopo(a.unidade_id))                                     -- diretor: leitura da diretoria
      or exists (select 1 from public.prod_recursos r where r.avaliacao_id = a.id and r.revisor_id = auth.uid())
      or (a.status = 'em_recurso' and app.tem_designacao('revisora'))
      or (a.status in ('aguardando_homologacao', 'homologada', 'retificada') and app.tem_designacao('homologacao'))
    ))
$$;
grant execute on function app.pode_ver_avaliacao(uuid) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['prod_competencias', 'prod_avaliacoes', 'prod_notas', 'prod_provas', 'prod_recursos', 'prod_historico', 'prod_apuracoes',
                           'prod_encaminhamentos', 'prod_correcoes', 'prod_alertas'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    if t not in ('prod_historico', 'prod_alertas') then
      execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()', t || '_auditoria', t);
    end if;
  end loop;
end $$;
grant select on public.prod_competencias, public.prod_avaliacoes, public.prod_notas, public.prod_provas, public.prod_recursos, public.prod_historico,
  public.prod_apuracoes, public.prod_encaminhamentos, public.prod_correcoes to authenticated;
create policy prod_comp_ler on public.prod_competencias for select to authenticated using ((select app.sessao_ok()) and (select app.tem_modulo('produtividade')));
create policy prod_av_ler on public.prod_avaliacoes for select to authenticated using ((select app.pode_ver_avaliacao(id)));
create policy prod_notas_ler on public.prod_notas for select to authenticated using ((select app.pode_ver_avaliacao(avaliacao_id)));
create policy prod_provas_ler on public.prod_provas for select to authenticated using ((select app.pode_ver_avaliacao(avaliacao_id)));
create policy prod_recursos_ler on public.prod_recursos for select to authenticated using ((select app.pode_ver_avaliacao(avaliacao_id)));
create policy prod_hist_ler on public.prod_historico for select to authenticated using ((select app.pode_ver_avaliacao(avaliacao_id)));
create policy prod_apuracoes_ler on public.prod_apuracoes for select to authenticated using (
  (select app.gestor_geral()) or servidor_id = (select app.servidor_atual())
  or exists (select 1 from public.prod_avaliacoes a where a.competencia = prod_apuracoes.competencia and a.servidor_id = prod_apuracoes.servidor_id and app.pode_ver_avaliacao(a.id)));
create policy prod_enc_ler on public.prod_encaminhamentos for select to authenticated using ((select app.gestor_geral()) or (select app.tem_designacao('homologacao')));
create policy prod_corr_ler on public.prod_correcoes for select to authenticated using (
  (select app.gestor_geral()) or exists (select 1 from public.prod_avaliacoes a where a.id = prod_correcoes.avaliacao_id and app.pode_ver_avaliacao(a.id)));

-- uuid do caminho sem erro de conversão (SQL não garante a ordem do AND)
create or replace function app.uuid_seguro(t text)
returns uuid language sql immutable set search_path = ''
as $$ select case when t ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then t::uuid end $$;
grant execute on function app.uuid_seguro(text) to authenticated;

-- arquivos (provas, ciência por outro meio, recurso, metas/arrecadação): bucket privado
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('produtividade', 'produtividade', false, 20971520, array['application/pdf', 'image/png', 'image/jpeg',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
create policy produtividade_enviar on storage.objects for insert to authenticated with check (
  bucket_id = 'produtividade' and (
    (name ~ '^avaliacoes/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|png|jpg|docx|xlsx)$' and coalesce((select app.pode_ver_avaliacao(app.uuid_seguro(split_part(name, '/', 2)))), false))
    or (name ~ '^institucional/[0-9a-f-]{36}\.(pdf|png|jpg|docx|xlsx)$' and (select app.gere_institucional()))));
create policy produtividade_ler on storage.objects for select to authenticated using (
  bucket_id = 'produtividade' and (
    (name like 'avaliacoes/%' and coalesce((select app.pode_ver_avaliacao(app.uuid_seguro(split_part(name, '/', 2)))), false))
    or (name like 'institucional/%' and (select app.sessao_ok()) and ((select app.tem_modulo('produtividade')) or (select app.gere_institucional())))));

create or replace function app.prod_hist(p_av uuid, p_acao text, p_det jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = ''
as $$ insert into public.prod_historico (avaliacao_id, ator_id, acao, detalhes) values (p_av, auth.uid(), p_acao, coalesce(p_det, '{}'::jsonb)) $$;

-- ===== cálculo (adendo 5) =====
-- dias de exercício elegível no período: dentro da entrada/saída na SEMFAZ, menos afastamentos que não contam
create or replace function app.prod_dias_elegiveis(p_servidor uuid, p_ini date, p_fim date, p_afast jsonb)
returns integer language sql stable security definer set search_path = ''
as $$
  select count(*)::int from generate_series(p_ini, p_fim, interval '1 day') g, public.servidores s
   where s.id = p_servidor
     and (s.data_entrada_semfaz is null or g::date >= s.data_entrada_semfaz)
     and (s.data_saida_semfaz is null or g::date <= s.data_saida_semfaz)
     and not exists (select 1 from public.afastamentos a where a.servidor_id = p_servidor and a.status = 'aprovado'
                       and g::date between a.inicio and a.fim and not coalesce((p_afast ->> a.tipo::text)::boolean, false))
$$;

-- resultado institucional que vale para o mês: último homologado até o fechamento da competência; sem nenhum = transição
create or replace function app.prod_institucional_do_mes(p_comp date)
returns public.prod_resultados_inst language sql stable security definer set search_path = ''
as $$
  select r.* from public.prod_resultados_inst r, public.prod_competencias c
   where c.competencia = p_comp and r.status = 'homologado' and r.homologado_em::date <= c.fechamento
   order by r.homologado_em desc limit 1
$$;

-- nota total, enquadramento (sem fração), mínimos cumulativos, faixa e proporcionalidade
create or replace function app.prod_enquadrar(p_regra uuid, p_funcional numeric, p_institucional numeric, p_dias integer, p_dias_mes integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare r public.prod_regras; v_trans boolean := p_institucional is null; v_total numeric; v_enq integer; v_pct numeric := 0; v_ok_f boolean; v_ok_t boolean; v_motivo text;
begin
  select * into r from public.prod_regras where id = p_regra;
  v_total := case when v_trans then p_funcional / r.max_funcional * 100 else p_funcional + p_institucional end;
  v_enq := floor(v_total)::int;                                   -- despreza a fração (69,99 → 69)
  v_ok_f := p_funcional >= r.minimo_funcional;
  v_ok_t := v_enq >= r.minimo_total;
  if v_ok_f and v_ok_t then
    select coalesce((x ->> 'percentual')::numeric, 0) into v_pct from jsonb_array_elements(r.faixas) x
     where v_enq between (x ->> 'de')::numeric and (x ->> 'ate')::numeric;
    v_pct := coalesce(v_pct, 0);
  else
    v_motivo := concat_ws(' e ', case when not v_ok_f then format('pontuação funcional abaixo de %s', r.minimo_funcional) end,
                                case when not v_ok_t then format('nota abaixo de %s', r.minimo_total) end);
  end if;
  return jsonb_build_object(
    'regra_versao', r.versao, 'transicao', v_trans,
    'pontos_funcionais', p_funcional, 'pontos_institucionais', p_institucional,
    'nota_total', round(v_total, 4), 'nota_enquadramento', v_enq,
    'minimo_funcional_atingido', v_ok_f, 'minimo_total_atingido', v_ok_t, 'motivo_zero', v_motivo,
    'percentual', v_pct, 'dias_elegiveis', p_dias, 'dias_mes', p_dias_mes,
    'fator', case when p_dias_mes > 0 then round(p_dias::numeric / p_dias_mes, 4) else 0 end,
    'percentual_efetivo', case when p_dias_mes > 0 then round(v_pct * p_dias / p_dias_mes, 4) else 0 end);
end $$;

-- apuração do mês do servidor: média ponderada pelos dias elegíveis de cada período (art. 14 § 2º)
create or replace function app.prod_apurar(p_comp date, p_servidor uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare c public.prod_competencias; r public.prod_regras; a record; v_dias integer := 0; v_soma numeric := 0; v_periodos jsonb := '[]'::jsonb;
        v_dias_p integer; v_tot numeric; v_inst public.prod_resultados_inst; v_dias_mes integer; v_func numeric; v jsonb; v_venc numeric;
begin
  select * into c from public.prod_competencias where competencia = p_comp;
  select * into r from public.prod_regras where id = c.regra_id;
  v_dias_mes := extract(day from (p_comp + interval '1 month' - interval '1 day'))::int;
  for a in select av.*, (select sum(n.nota) from public.prod_notas n where n.avaliacao_id = av.id) as soma_notas
             from public.prod_avaliacoes av where av.competencia = p_comp and av.servidor_id = p_servidor and av.status <> 'retificada' order by av.periodo_inicio loop
    v_dias_p := app.prod_dias_elegiveis(p_servidor, a.periodo_inicio, a.periodo_fim, r.afastamentos_exercicio);
    v_tot := coalesce(a.soma_notas, 0);
    v_dias := v_dias + v_dias_p;
    v_soma := v_soma + v_tot * v_dias_p;
    v_periodos := v_periodos || jsonb_build_object('avaliacao_id', a.id, 'inicio', a.periodo_inicio, 'fim', a.periodo_fim, 'status', a.status,
                                                    'pontos', v_tot, 'dias_elegiveis', v_dias_p, 'avaliador', (select nome_completo from public.servidores where id = a.avaliador_id));
  end loop;
  v_func := case when v_dias > 0 then trunc(v_soma / v_dias, 2) else 0 end;   -- média ponderada, sem arredondar para cima
  v_inst := app.prod_institucional_do_mes(p_comp);
  v := app.prod_enquadrar(c.regra_id, v_func, v_inst.pontos, v_dias, v_dias_mes)
       || jsonb_build_object('competencia', p_comp, 'servidor_id', p_servidor, 'periodos', v_periodos,
                             'institucional', case when v_inst.id is null then null else jsonb_build_object('ano', v_inst.ano, 'quadrimestre', v_inst.quadrimestre,
                                                    'pontos', v_inst.pontos, 'homologado_em', v_inst.homologado_em, 'memoria', v_inst.memoria) end);
  if coalesce((select (valor)::boolean from public.configuracoes where chave = 'produtividade.calcular_valor'), false) then
    select vencimento_basico into v_venc from public.prod_vencimentos where servidor_id = p_servidor and competencia = p_comp;
    v := v || jsonb_build_object('vencimento_basico', v_venc, 'valor', case when v_venc is null then null else round(v_venc * (v ->> 'percentual_efetivo')::numeric / 100, 2) end);
  end if;
  return v;
end $$;

-- demonstrativo (Anexo II): congelado se homologado; ao vivo enquanto não
create or replace function public.prod_demonstrativo(p_comp date, p_servidor uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v jsonb; s record;
begin
  -- coalesce: servidor nulo/inexistente nunca libera (NULL não pode virar "permitido")
  if p_servidor is null or not coalesce(app.gestor_geral() or (p_servidor = app.servidor_atual() and app.sessao_ok())
          or exists (select 1 from public.prod_avaliacoes a where a.competencia = p_comp and a.servidor_id = p_servidor and app.pode_ver_avaliacao(a.id)), false) then
    perform app.erro('Acesso não permitido.', '42501');
  end if;
  if p_servidor = app.servidor_atual() and not app.gestor_geral()
     and not exists (select 1 from public.prod_avaliacoes a where a.competencia = p_comp and a.servidor_id = p_servidor and a.status <> 'rascunho') then
    perform app.erro('Avaliação ainda não enviada.', 'P0002');
  end if;
  select dados into v from public.prod_apuracoes where competencia = p_comp and servidor_id = p_servidor order by versao desc limit 1;
  if v is null then v := app.prod_apurar(p_comp, p_servidor) || jsonb_build_object('provisorio', true); end if;
  select sv.nome_completo, sv.matricula, cg.nome cargo, un.sigla unidade into s
    from public.servidores sv left join public.cargos cg on cg.id = sv.cargo_id left join public.unidades un on un.id = sv.unidade_id where sv.id = p_servidor;
  return v || jsonb_build_object('servidor', s.nome_completo, 'matricula', s.matricula, 'cargo', s.cargo, 'unidade', s.unidade);
end $$;

grant execute on function public.prod_demonstrativo(date, uuid) to authenticated;
revoke execute on function app.prod_apurar(date, uuid), app.prod_enquadrar(uuid, numeric, numeric, integer, integer), app.prod_dias_elegiveis(uuid, date, date, jsonb) from public, anon, authenticated;
