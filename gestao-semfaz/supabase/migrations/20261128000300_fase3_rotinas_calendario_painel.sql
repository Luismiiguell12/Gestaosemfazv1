-- Fase 3 · recorrentes (6.15), substituto nas demandas (6.14), aviso de prazo (6.10),
-- calendário (6.3), indicadores do painel (6.1) e busca geral com demandas (6.19)

-- ===== demandas recorrentes =====
create type public.periodicidade as enum ('mensal', 'trimestral', 'semestral', 'anual');
create type public.situacao_recorrencia as enum ('ativa', 'pausada', 'encerrada');

create table public.recorrencias (
  id uuid primary key default gen_random_uuid(),
  titulo text not null check (length(btrim(titulo)) between 3 and 200),
  descricao text check (descricao is null or length(descricao) <= 5000),
  unidade_id uuid not null references public.unidades (id),
  periodicidade public.periodicidade not null,
  prazo_dias_uteis integer not null check (prazo_dias_uteis between 1 and 120),
  prioridade public.prioridade_demanda not null default 'media',
  responsaveis uuid[] not null check (cardinality(responsaveis) between 1 and 20),
  checklist text[] not null default '{}',
  situacao public.situacao_recorrencia not null default 'ativa',
  proxima_em date not null,
  criado_por uuid not null references public.usuarios (id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
alter table public.demandas add constraint demandas_recorrencia_fk foreign key (recorrencia_id) references public.recorrencias (id);
create trigger recorrencias_atualizado before update on public.recorrencias for each row execute function app.tocar_atualizado_em();
alter table public.recorrencias enable row level security;
revoke all on public.recorrencias from anon, authenticated;
grant select on public.recorrencias to authenticated;
create policy recorrencias_ler on public.recorrencias for select to authenticated using ((select app.pode_gerir_demanda(unidade_id)));
create trigger recorrencias_auditoria after insert or update or delete on public.recorrencias for each row execute function app.auditar_linha();

create or replace function public.salvar_recorrencia(p_id uuid, p_dados jsonb, p_responsaveis uuid[], p_checklist text[] default '{}')
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := p_id; v_unidade uuid := (p_dados ->> 'unidade_id')::uuid; v_s uuid; v_inicio date := coalesce((p_dados ->> 'proxima_em')::date, current_date);
begin
  if p_id is not null then select unidade_id into v_unidade from public.recorrencias where id = p_id; end if;
  if v_unidade is null or not app.pode_gerir_demanda(v_unidade) then perform app.erro('Somente a chefia da unidade cria modelos recorrentes.', '42501'); end if;
  if coalesce(array_length(p_responsaveis, 1), 0) = 0 then perform app.erro('Indique pelo menos um responsável.', '22023'); end if;
  foreach v_s in array p_responsaveis loop
    if not app.gestor_geral() and not app.na_escopo((select unidade_id from public.servidores where id = v_s)) then perform app.erro('Responsável fora da sua unidade.', '42501'); end if;
  end loop;
  if v_inicio < current_date then perform app.erro('A primeira ocorrência deve ser hoje ou depois.', '22023'); end if;
  if p_id is null then
    insert into public.recorrencias (titulo, descricao, unidade_id, periodicidade, prazo_dias_uteis, prioridade, responsaveis, checklist, proxima_em, criado_por)
    values (btrim(p_dados ->> 'titulo'), nullif(btrim(coalesce(p_dados ->> 'descricao', '')), ''), v_unidade, (p_dados ->> 'periodicidade')::public.periodicidade,
            (p_dados ->> 'prazo_dias_uteis')::int, coalesce((p_dados ->> 'prioridade')::public.prioridade_demanda, 'media'), p_responsaveis,
            coalesce(p_checklist, '{}'), v_inicio, auth.uid())
    returning id into v_id;
  else
    -- editar o modelo vale só para as próximas ocorrências (as já criadas não mudam)
    update public.recorrencias set titulo = btrim(p_dados ->> 'titulo'), descricao = nullif(btrim(coalesce(p_dados ->> 'descricao', '')), ''),
      periodicidade = (p_dados ->> 'periodicidade')::public.periodicidade, prazo_dias_uteis = (p_dados ->> 'prazo_dias_uteis')::int,
      prioridade = coalesce((p_dados ->> 'prioridade')::public.prioridade_demanda, prioridade), responsaveis = p_responsaveis,
      checklist = coalesce(p_checklist, '{}'), proxima_em = coalesce((p_dados ->> 'proxima_em')::date, proxima_em)
     where id = p_id and situacao <> 'encerrada';
    if not found then perform app.erro('Modelo não encontrado ou encerrado.', 'P0002'); end if;
  end if;
  return v_id;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or not_null_violation then
  perform app.erro('Dados inválidos.', '22023');
end $$;

create or replace function public.mudar_situacao_recorrencia(p_id uuid, p_situacao public.situacao_recorrencia)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not app.pode_gerir_demanda((select unidade_id from public.recorrencias where id = p_id)) then
    perform app.erro('Pausar ou encerrar exige a chefia da unidade.', '42501');
  end if;
  update public.recorrencias set situacao = p_situacao where id = p_id and situacao <> 'encerrada';
  if not found then perform app.erro('Modelo não encontrado ou já encerrado.', 'P0002'); end if;
end $$;

create or replace function app.proximo_periodo(d date, p public.periodicidade)
returns date language sql immutable set search_path = ''
as $$ select (d + case p when 'mensal' then interval '1 month' when 'trimestral' then interval '3 months' when 'semestral' then interval '6 months' else interval '1 year' end)::date $$;

-- cria cada ocorrência uma única vez (constraint unique (recorrencia_id, ocorrencia_ref))
create or replace function app.gerar_ocorrencias()
returns integer language plpgsql security definer set search_path = ''
as $$
declare r public.recorrencias; v_id uuid; n integer := 0; v_item text; i integer;
begin
  for r in select * from public.recorrencias where situacao = 'ativa' and proxima_em <= current_date for update loop
    insert into public.demandas (titulo, descricao, origem, unidade_id, prioridade, prazo, recorrencia_id, ocorrencia_ref, criado_por)
    values (r.titulo, r.descricao, 'recorrente', r.unidade_id, r.prioridade, public.somar_dias_uteis(r.proxima_em, r.prazo_dias_uteis),
            r.id, to_char(r.proxima_em, 'YYYY-MM-DD'), r.criado_por)
    on conflict (recorrencia_id, ocorrencia_ref) do nothing
    returning id into v_id;
    if v_id is not null then
      perform app.historico(v_id, 'criada_por_rotina', jsonb_build_object('modelo', r.id, 'referencia', to_char(r.proxima_em, 'DD/MM/YYYY')));
      perform app.definir_titulares(v_id, (select array_agg(x) from unnest(r.responsaveis) x join public.servidores s on s.id = x and s.situacao = 'ativo'));
      i := 0;
      foreach v_item in array r.checklist loop
        insert into public.demanda_checklist (demanda_id, texto, ordem) values (v_id, left(v_item, 300), i); i := i + 1;
      end loop;
      n := n + 1;
    end if;
    update public.recorrencias set proxima_em = app.proximo_periodo(proxima_em, periodicidade) where id = r.id;
  end loop;
  return n;
end $$;

-- ===== substituto nas demandas (6.14) =====
create table public.substituicoes (
  afastamento_id uuid primary key references public.afastamentos (id),
  aplicada_em timestamptz not null default now(),
  encerrada_em timestamptz
);
alter table public.substituicoes enable row level security;
revoke all on public.substituicoes from anon, authenticated;

create or replace function app.aplicar_substituicoes()
returns integer language plpgsql security definer set search_path = ''
as $$
declare a record; d record; v_u uuid; v_chefe uuid; n integer := 0; v_primeiro date;
begin
  -- início: a partir do 1º dia útil do afastamento, substituto entra como responsável adicional (titular continua)
  for a in select af.*, s.nome_completo as titular_nome, s.unidade_id, sb.nome_completo as substituto_nome
             from public.afastamentos af join public.servidores s on s.id = af.servidor_id join public.servidores sb on sb.id = af.substituto_id
            where af.status = 'aprovado' and af.substituto_id is not null and current_date <= af.fim
  loop
    v_primeiro := case when public.eh_dia_util(a.inicio) then a.inicio else public.somar_dias_uteis(a.inicio, 1) end;
    continue when current_date < v_primeiro or v_primeiro > a.fim;
    for d in select dm.id from public.demandas dm join public.demanda_responsaveis r on r.demanda_id = dm.id
              where r.servidor_id = a.servidor_id and r.ativo and r.papel = 'titular'
                and dm.status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao')
                and not exists (select 1 from public.demanda_responsaveis x where x.demanda_id = dm.id and x.servidor_id = a.substituto_id and x.ativo)
    loop
      insert into public.demanda_responsaveis as r (demanda_id, servidor_id, papel, ativo, afastamento_id)
      values (d.id, a.substituto_id, 'substituto', true, a.id)
      on conflict (demanda_id, servidor_id) do update set papel = 'substituto', ativo = true, afastamento_id = excluded.afastamento_id, removido_em = null;
      perform app.historico(d.id, 'substituicao_inicio', jsonb_build_object('titular', a.titular_nome, 'substituto', a.substituto_nome, 'ate', a.fim));
      n := n + 1;
    end loop;
    if not exists (select 1 from public.substituicoes where afastamento_id = a.id) then
      insert into public.substituicoes (afastamento_id) values (a.id);
      v_u := app.usuario_do_servidor(a.substituto_id);
      if v_u is not null then
        perform app.notificar(v_u, 'substituicao_inicio', 'Início de substituição', 'Você substitui ' || a.titular_nome || ' até ' || to_char(a.fim, 'DD/MM'), '/demandas');
      end if;
      for v_chefe in select app.chefes_da_unidade(a.unidade_id) loop
        perform app.notificar(v_chefe, 'substituicao_inicio', 'Início de substituição', a.substituto_nome || ' substitui ' || a.titular_nome || ' até ' || to_char(a.fim, 'DD/MM'), '/ferias');
      end loop;
    end if;
  end loop;
  -- retorno: substituto sai das demandas que não concluiu
  for a in select af.id, sb.nome_completo as substituto_nome from public.substituicoes su join public.afastamentos af on af.id = su.afastamento_id
             join public.servidores sb on sb.id = af.substituto_id
            where su.encerrada_em is null and (af.fim < current_date or af.status <> 'aprovado')
  loop
    for d in select r.demanda_id from public.demanda_responsaveis r join public.demandas dm on dm.id = r.demanda_id
              where r.afastamento_id = a.id and r.papel = 'substituto' and r.ativo and dm.status <> 'concluida'
    loop
      update public.demanda_responsaveis set ativo = false, removido_em = now() where demanda_id = d.demanda_id and afastamento_id = a.id and papel = 'substituto';
      perform app.historico(d.demanda_id, 'substituicao_fim', jsonb_build_object('substituto', a.substituto_nome));
    end loop;
    update public.substituicoes set encerrada_em = now() where afastamento_id = a.id;
  end loop;
  return n;
end $$;

-- ===== aviso de prazo próximo (hoje ou próximo dia útil), uma vez por dia =====
create or replace function app.avisar_prazos()
returns integer language plpgsql security definer set search_path = ''
as $$
declare d record; v_s uuid; v_u uuid; n integer := 0; v_dias integer;
begin
  for d in select * from public.demandas where status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao')
             and prazo is not null and prazo >= current_date and ultimo_aviso_prazo is distinct from current_date loop
    v_dias := public.dias_uteis_entre(current_date, d.prazo);
    continue when v_dias > 1;
    for v_s in select servidor_id from public.demanda_responsaveis where demanda_id = d.id and ativo loop
      v_u := app.usuario_do_servidor(v_s);
      if v_u is not null then
        perform app.notificar(v_u, 'demanda_prazo', case when v_dias = 0 then 'Prazo vence hoje' else 'Prazo vence no próximo dia útil' end,
          '#' || d.numero || ' ' || d.titulo, '/demandas/ficha?id=' || d.id);
      end if;
    end loop;
    update public.demandas set ultimo_aviso_prazo = current_date where id = d.id;
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function app.rotinas_diarias_demandas()
returns void language plpgsql security definer set search_path = ''
as $$ begin perform app.gerar_ocorrencias(); perform app.aplicar_substituicoes(); perform app.avisar_prazos(); end $$;
revoke execute on function app.rotinas_diarias_demandas() from public, anon, authenticated;
revoke execute on function app.gerar_ocorrencias() from public, anon, authenticated;
revoke execute on function app.aplicar_substituicoes() from public, anon, authenticated;
revoke execute on function app.avisar_prazos() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('rotinas-diarias-demandas', '5 9 * * *', 'select app.rotinas_diarias_demandas()');  -- 06:05 de Brasília
  end if;
exception when others then
  raise notice 'pg_cron indisponível: agendar app.rotinas_diarias_demandas() manualmente';
end $$;

-- ===== calendário (6.3) =====
create type public.tipo_compromisso as enum ('compromisso', 'prazo');

create table public.compromissos (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid references public.unidades (id),   -- null = calendário geral do Gabinete (Secretária)
  titulo text not null check (length(btrim(titulo)) between 2 and 200),
  descricao text check (descricao is null or length(descricao) <= 2000),
  local text check (local is null or length(local) <= 200),
  tipo public.tipo_compromisso not null default 'compromisso',
  inicio timestamptz not null,
  fim timestamptz not null,
  dia_inteiro boolean not null default false,
  cancelado boolean not null default false,
  criado_por uuid not null references public.usuarios (id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint compromissos_periodo check (fim >= inicio and fim - inicio <= interval '31 days')
);
create index compromissos_inicio_idx on public.compromissos (inicio);
create trigger compromissos_atualizado before update on public.compromissos for each row execute function app.tocar_atualizado_em();
create table public.compromisso_participantes (
  compromisso_id uuid not null references public.compromissos (id) on delete cascade,
  servidor_id uuid not null references public.servidores (id),
  primary key (compromisso_id, servidor_id)
);

create or replace function app.pode_editar_calendario(p_unidade uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select app.gestor_geral()
      or (p_unidade is not null and app.sessao_ok() and app.perfil_atual() in ('diretor', 'coordenador')
          and app.tem_modulo('calendario') and app.na_escopo(p_unidade))
$$;

create or replace function app.pode_ver_compromisso(p_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select app.sessao_ok() and exists (
    select 1 from public.compromissos c where c.id = p_id and (
      app.pode_editar_calendario(c.unidade_id)
      or exists (select 1 from public.compromisso_participantes p where p.compromisso_id = c.id and p.servidor_id = app.servidor_atual())
    ))
$$;
grant execute on function app.pode_ver_compromisso(uuid) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['compromissos', 'compromisso_participantes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()', t || '_auditoria', t);
  end loop;
end $$;
create policy compromissos_ler on public.compromissos for select to authenticated using ((select app.pode_ver_compromisso(id)));
create policy compromisso_part_ler on public.compromisso_participantes for select to authenticated using ((select app.pode_ver_compromisso(compromisso_id)));

create or replace function public.salvar_compromisso(p_id uuid, p_dados jsonb, p_participantes uuid[] default '{}')
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := p_id; v_unidade uuid := nullif(p_dados ->> 'unidade_id', '')::uuid; v_s uuid; v_u uuid;
begin
  if p_id is not null then select unidade_id into v_unidade from public.compromissos where id = p_id; end if;
  if not app.pode_editar_calendario(v_unidade) then perform app.erro('Você só pode editar o calendário da sua unidade.', '42501'); end if;
  if p_id is null then
    insert into public.compromissos (unidade_id, titulo, descricao, local, tipo, inicio, fim, dia_inteiro, criado_por)
    values (v_unidade, btrim(p_dados ->> 'titulo'), nullif(btrim(coalesce(p_dados ->> 'descricao', '')), ''), nullif(btrim(coalesce(p_dados ->> 'local', '')), ''),
            coalesce((p_dados ->> 'tipo')::public.tipo_compromisso, 'compromisso'), (p_dados ->> 'inicio')::timestamptz,
            coalesce((p_dados ->> 'fim')::timestamptz, (p_dados ->> 'inicio')::timestamptz), coalesce((p_dados ->> 'dia_inteiro')::boolean, false), auth.uid())
    returning id into v_id;
  else
    update public.compromissos set titulo = btrim(p_dados ->> 'titulo'), descricao = nullif(btrim(coalesce(p_dados ->> 'descricao', '')), ''),
      local = nullif(btrim(coalesce(p_dados ->> 'local', '')), ''), tipo = coalesce((p_dados ->> 'tipo')::public.tipo_compromisso, tipo),
      inicio = (p_dados ->> 'inicio')::timestamptz, fim = coalesce((p_dados ->> 'fim')::timestamptz, (p_dados ->> 'inicio')::timestamptz),
      dia_inteiro = coalesce((p_dados ->> 'dia_inteiro')::boolean, dia_inteiro)
     where id = p_id and not cancelado;
    if not found then perform app.erro('Compromisso não encontrado ou cancelado.', 'P0002'); end if;
  end if;
  delete from public.compromisso_participantes where compromisso_id = v_id and not (servidor_id = any (coalesce(p_participantes, '{}'::uuid[])));
  foreach v_s in array coalesce(p_participantes, '{}'::uuid[]) loop
    insert into public.compromisso_participantes (compromisso_id, servidor_id) values (v_id, v_s) on conflict do nothing;
    if found then
      v_u := app.usuario_do_servidor(v_s);
      if v_u is not null and v_u is distinct from auth.uid() then
        perform app.notificar(v_u, 'compromisso', 'Você foi incluído em um compromisso',
          btrim(p_dados ->> 'titulo') || ' · ' || to_char(((p_dados ->> 'inicio')::timestamptz) at time zone 'America/Maceio', 'DD/MM HH24:MI'), '/calendario');
      end if;
    end if;
  end loop;
  return v_id;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or not_null_violation then
  perform app.erro('Dados inválidos.', '22023');
end $$;

create or replace function public.cancelar_compromisso(p_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not app.pode_editar_calendario((select unidade_id from public.compromissos where id = p_id)) then perform app.erro('Sem permissão.', '42501'); end if;
  update public.compromissos set cancelado = true where id = p_id and not cancelado;
  if not found then perform app.erro('Compromisso não encontrado.', 'P0002'); end if;
end $$;

-- eventos do período: compromissos, prazos de demandas e feriados — cada um só o que a pessoa pode ver
create or replace function public.eventos_calendario(p_inicio date, p_fim date)
returns table (tipo text, id uuid, titulo text, inicio timestamptz, fim timestamptz, dia_inteiro boolean, unidade_id uuid, unidade text,
               local text, descricao text, participantes jsonb, editavel boolean)
language sql stable security definer set search_path = ''
as $$
  select c.tipo::text, c.id, c.titulo, c.inicio, c.fim, c.dia_inteiro, c.unidade_id, coalesce(u.sigla, 'Geral do Gabinete'), c.local, c.descricao,
         coalesce((select jsonb_agg(jsonb_build_object('servidor_id', s.id, 'nome', s.nome_completo) order by s.nome_completo)
                     from public.compromisso_participantes p join public.servidores s on s.id = p.servidor_id where p.compromisso_id = c.id), '[]'::jsonb),
         app.pode_editar_calendario(c.unidade_id)
    from public.compromissos c left join public.unidades u on u.id = c.unidade_id
   where not c.cancelado and app.pode_ver_compromisso(c.id) and c.inicio < (p_fim + 1)::timestamptz and c.fim >= p_inicio::timestamptz
  union all
  select 'demanda', d.id, '#' || d.numero || ' ' || d.titulo, d.prazo::timestamptz, d.prazo::timestamptz, true, d.unidade_id, u.sigla, null, null,
         coalesce((select jsonb_agg(jsonb_build_object('servidor_id', s.id, 'nome', s.nome_completo) order by s.nome_completo)
                     from public.demanda_responsaveis r join public.servidores s on s.id = r.servidor_id where r.demanda_id = d.id and r.ativo), '[]'::jsonb),
         false
    from public.demandas d join public.unidades u on u.id = d.unidade_id
   where d.prazo between p_inicio and p_fim and d.status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao') and app.pode_ver_demanda(d.id)
  union all
  select 'feriado', f.id, f.descricao, f.data::timestamptz, f.data::timestamptz, true, null, null, null, null, '[]'::jsonb, false
    from public.feriados f where app.sessao_ok() and f.data between p_inicio and p_fim
  order by 4
$$;

-- ===== painel (6.1) =====
create or replace function public.painel_unidades()
returns table (unidade_id uuid, a_fazer integer, em_andamento integer, concluidas integer, atrasadas integer, apertadas integer, concluidas_90 integer, no_prazo_90 integer)
language sql stable security definer set search_path = ''
as $$
  select u.id,
    count(*) filter (where d.status = 'a_fazer')::int,
    count(*) filter (where d.status in ('em_andamento', 'aguardando_terceiros', 'em_revisao'))::int,
    count(*) filter (where d.status = 'concluida' and d.concluida_em > now() - interval '30 days')::int,
    count(*) filter (where d.status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao') and d.prazo < current_date)::int,
    count(*) filter (where d.status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao') and d.prazo >= current_date
                     and public.dias_uteis_entre(current_date, d.prazo) <= coalesce((select (valor)::int from public.configuracoes where chave = 'demandas.prazo_apertado_dias_uteis'), 2))::int,
    count(*) filter (where d.status = 'concluida' and d.concluida_em > now() - interval '90 days' and d.prazo is not null)::int,
    count(*) filter (where d.status = 'concluida' and d.concluida_em > now() - interval '90 days' and d.prazo is not null and (d.concluida_em at time zone 'America/Maceio')::date <= d.prazo)::int
  from public.unidades u left join public.demandas d on d.unidade_id = u.id
  where u.ativa and app.sessao_ok() and app.perfil_atual() <> 'funcionario' and u.id in (select app.unidades_escopo())
  group by u.id
$$;

-- números do próprio servidor (painel do funcionário). Demanda com vários responsáveis conta para cada um.
create or replace function public.meus_indicadores()
returns jsonb language sql stable security definer set search_path = ''
as $$
  with minhas as (
    select d.* from public.demandas d join public.demanda_responsaveis r on r.demanda_id = d.id
     where r.servidor_id = app.servidor_atual() and app.sessao_ok()
  )
  select jsonb_build_object(
    'abertas', (select count(*) from minhas where status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao')),
    'atrasadas', (select count(*) from minhas where status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao') and prazo < current_date),
    'concluidas_mes', (select count(*) from minhas where status = 'concluida' and date_trunc('month', concluida_em) = date_trunc('month', now())),
    'no_prazo_pct', (select case when count(*) = 0 then null else round(100.0 * count(*) filter (where (concluida_em at time zone 'America/Maceio')::date <= prazo) / count(*)) end
                       from minhas where status = 'concluida' and prazo is not null and concluida_em > now() - interval '90 days'),
    'por_mes', (select jsonb_agg(jsonb_build_object('mes', to_char(m, 'YYYY-MM'),
                  'concluidas', (select count(*) from minhas where status = 'concluida' and date_trunc('month', concluida_em) = m)) order by m)
                  from generate_series(date_trunc('month', now()) - interval '5 months', date_trunc('month', now()), interval '1 month') m)
  )
$$;

insert into public.configuracoes (chave, valor, descricao) values
  ('demandas.prazo_apertado_dias_uteis', '2', 'Demanda aberta com prazo em até N dias úteis deixa a unidade em "Prazo apertado"')
on conflict (chave) do nothing;

-- ===== busca geral: + demandas (título, nº do processo ou #número) — invoker, RLS decide =====
create or replace function public.busca_geral(termo text, limite integer default 8)
returns table (tipo text, id uuid, titulo text, subtitulo text, rota text)
language plpgsql stable security invoker set search_path = ''
as $$
declare q text := app.normalizar(btrim(coalesce(termo, '')));
        lim integer := least(greatest(coalesce(limite, 8), 1), 20);
        num bigint := case when btrim(coalesce(termo, '')) ~ '^#?[0-9]{1,12}$' then ltrim(btrim(termo), '#')::bigint end;
begin
  if length(q) < 2 and num is null then return; end if;
  q := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return query
    (select 'demanda'::text, d.id, '#' || d.numero || ' ' || d.titulo, coalesce('Processo ' || d.numero_processo, 'Demanda'), '/demandas/ficha?id=' || d.id
       from public.demandas d
      where app.normalizar(d.titulo) like q or app.normalizar(coalesce(d.numero_processo, '')) like q or d.numero = num
      order by d.numero desc limit lim)
    union all
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

update public.modulos set status = 'ativo' where codigo = 'demandas';

grant execute on function public.salvar_recorrencia(uuid, jsonb, uuid[], text[]) to authenticated;
grant execute on function public.mudar_situacao_recorrencia(uuid, public.situacao_recorrencia) to authenticated;
grant execute on function public.salvar_compromisso(uuid, jsonb, uuid[]) to authenticated;
grant execute on function public.cancelar_compromisso(uuid) to authenticated;
grant execute on function public.eventos_calendario(date, date) to authenticated;
grant execute on function public.painel_unidades() to authenticated;
grant execute on function public.meus_indicadores() to authenticated;
grant execute on function public.busca_geral(text, integer) to authenticated;
