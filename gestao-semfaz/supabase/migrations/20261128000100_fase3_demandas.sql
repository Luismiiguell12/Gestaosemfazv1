-- Fase 3 · demandas (6.2), checklist (6.16), histórico. Prazos em dias úteis.

create type public.status_demanda as enum ('sugerida', 'a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao', 'concluida', 'recusada', 'cancelada');
create type public.prioridade_demanda as enum ('baixa', 'media', 'alta', 'critica');
create type public.origem_demanda as enum ('processo', 'email', 'whatsapp', 'recorrente', 'outra');

create table public.demandas (
  id uuid primary key default gen_random_uuid(),
  numero bigint generated always as identity unique,
  titulo text not null check (length(btrim(titulo)) between 3 and 200),
  descricao text check (descricao is null or length(descricao) <= 5000),
  origem public.origem_demanda not null default 'outra',
  numero_processo text check (numero_processo is null or length(numero_processo) <= 60),
  unidade_id uuid not null references public.unidades (id),
  prioridade public.prioridade_demanda not null default 'media',
  status public.status_demanda not null default 'a_fazer',
  prazo date,
  recorrencia_id uuid,
  ocorrencia_ref text,
  criado_por uuid not null references public.usuarios (id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  iniciada_em timestamptz,
  concluida_em timestamptz,
  ultimo_aviso_prazo date,
  constraint demandas_ocorrencia_unica unique (recorrencia_id, ocorrencia_ref)
);
create index demandas_unidade_idx on public.demandas (unidade_id, status);
create index demandas_prazo_idx on public.demandas (prazo) where status not in ('concluida', 'recusada', 'cancelada');
create index demandas_busca_idx on public.demandas (app.normalizar(titulo));
create trigger demandas_atualizado before update on public.demandas for each row execute function app.tocar_atualizado_em();

create type public.papel_responsavel as enum ('titular', 'substituto');
create table public.demanda_responsaveis (
  demanda_id uuid not null references public.demandas (id) on delete cascade,
  servidor_id uuid not null references public.servidores (id),
  papel public.papel_responsavel not null default 'titular',
  ativo boolean not null default true,
  afastamento_id uuid references public.afastamentos (id),
  adicionado_em timestamptz not null default now(),
  removido_em timestamptz,
  primary key (demanda_id, servidor_id)
);
create index demanda_resp_servidor_idx on public.demanda_responsaveis (servidor_id) where ativo;

create table public.demanda_checklist (
  id uuid primary key default gen_random_uuid(),
  demanda_id uuid not null references public.demandas (id) on delete cascade,
  texto text not null check (length(btrim(texto)) between 1 and 300),
  responsavel_id uuid references public.servidores (id),
  ordem integer not null default 0,
  feito boolean not null default false,
  feito_por uuid references public.usuarios (id),
  feito_em timestamptz,
  removido boolean not null default false
);
create index demanda_checklist_idx on public.demanda_checklist (demanda_id, ordem);

-- histórico da demanda: só cresce
create table public.demanda_historico (
  id bigint generated always as identity primary key,
  demanda_id uuid not null references public.demandas (id) on delete cascade,
  em timestamptz not null default now(),
  ator_id uuid references public.usuarios (id),
  acao text not null,
  detalhes jsonb not null default '{}'::jsonb
);
create index demanda_historico_idx on public.demanda_historico (demanda_id, em);
create trigger demanda_historico_imutavel before update or delete on public.demanda_historico
  for each row execute function app.auditoria_imutavel();

-- quem foi mencionado passa a ver a conversa (e a ficha) daquela demanda
create table public.demanda_participantes (
  demanda_id uuid not null references public.demandas (id) on delete cascade,
  usuario_id uuid not null references public.usuarios (id),
  incluido_em timestamptz not null default now(),
  primary key (demanda_id, usuario_id)
);

do $$
declare t text;
begin
  foreach t in array array['demandas', 'demanda_responsaveis', 'demanda_checklist', 'demanda_historico', 'demanda_participantes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
  foreach t in array array['demandas', 'demanda_responsaveis', 'demanda_checklist'] loop
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()', t || '_auditoria', t);
  end loop;
end $$;

-- ===== regras de acesso (uma função, usada nas políticas e nas RPCs) =====
create or replace function app.eh_responsavel(p_demanda uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.demanda_responsaveis r where r.demanda_id = p_demanda and r.ativo and r.servidor_id = app.servidor_atual()) $$;

create or replace function app.pode_gerir_demanda(p_unidade uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select app.gestor_geral()
      or (app.sessao_ok() and app.perfil_atual() in ('diretor', 'coordenador') and app.tem_modulo('demandas') and app.na_escopo(p_unidade))
$$;

create or replace function app.pode_ver_demanda(p_demanda uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select app.sessao_ok() and exists (
    select 1 from public.demandas d where d.id = p_demanda and (
      app.pode_gerir_demanda(d.unidade_id)
      or app.eh_responsavel(d.id)
      or d.criado_por = auth.uid()
      or exists (select 1 from public.demanda_participantes p where p.demanda_id = d.id and p.usuario_id = auth.uid())
    ))
$$;

create policy demandas_ler on public.demandas for select to authenticated using ((select app.pode_ver_demanda(id)));
create policy demanda_resp_ler on public.demanda_responsaveis for select to authenticated using ((select app.pode_ver_demanda(demanda_id)));
create policy demanda_check_ler on public.demanda_checklist for select to authenticated using ((select app.pode_ver_demanda(demanda_id)));
create policy demanda_hist_ler on public.demanda_historico for select to authenticated using ((select app.pode_ver_demanda(demanda_id)));
create policy demanda_part_ler on public.demanda_participantes for select to authenticated using ((select app.pode_ver_demanda(demanda_id)));
grant execute on function app.pode_ver_demanda(uuid), app.pode_gerir_demanda(uuid), app.eh_responsavel(uuid) to authenticated;

create or replace function app.historico(p_demanda uuid, p_acao text, p_detalhes jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = ''
as $$ insert into public.demanda_historico (demanda_id, ator_id, acao, detalhes) values (p_demanda, auth.uid(), p_acao, coalesce(p_detalhes, '{}'::jsonb)) $$;

create or replace function app.usuario_do_servidor(p_servidor uuid)
returns uuid language sql stable security definer set search_path = ''
as $$ select u.id from public.usuarios u where u.servidor_id = p_servidor and u.ativo $$;

create or replace function app.titulo_demanda(p_demanda uuid)
returns text language sql stable security definer set search_path = ''
as $$ select '#' || numero || ' ' || titulo from public.demandas where id = p_demanda $$;

-- define os responsáveis titulares (diferença: entra/sai), notifica quem entrou
create or replace function app.definir_titulares(p_demanda uuid, p_servidores uuid[])
returns void language plpgsql security definer set search_path = ''
as $$
declare v_s uuid; v_unidade uuid; v_u uuid;
begin
  select unidade_id into v_unidade from public.demandas where id = p_demanda;
  foreach v_s in array coalesce(p_servidores, '{}'::uuid[]) loop
    if not exists (select 1 from public.servidores s where s.id = v_s and s.situacao = 'ativo') then
      perform app.erro('Responsável inexistente ou inativo.', '22023');
    end if;
    -- rotina agendada (sem usuário) já validou no modelo; usuário: só servidores do seu escopo
    if auth.uid() is not null and not app.gestor_geral() and not app.na_escopo((select unidade_id from public.servidores where id = v_s)) then
      perform app.erro('Responsável fora da sua unidade.', '42501');
    end if;
  end loop;
  -- sai quem não está na lista
  update public.demanda_responsaveis set ativo = false, removido_em = now()
   where demanda_id = p_demanda and papel = 'titular' and ativo and not (servidor_id = any (coalesce(p_servidores, '{}'::uuid[])));
  foreach v_s in array coalesce(p_servidores, '{}'::uuid[]) loop
    insert into public.demanda_responsaveis as r (demanda_id, servidor_id, papel, ativo)
    values (p_demanda, v_s, 'titular', true)
    on conflict (demanda_id, servidor_id) do update set papel = 'titular', ativo = true, removido_em = null, afastamento_id = null
      where not (r.ativo and r.papel = 'titular');
    if found then
      perform app.historico(p_demanda, 'responsavel_incluido', jsonb_build_object('servidor', (select nome_completo from public.servidores where id = v_s)));
      v_u := app.usuario_do_servidor(v_s);
      if v_u is not null and v_u is distinct from auth.uid() then
        perform app.notificar(v_u, 'demanda_inclusao', 'Você foi incluído em uma demanda', app.titulo_demanda(p_demanda), '/demandas/ficha?id=' || p_demanda);
      end if;
    end if;
  end loop;
end $$;

create or replace function app.validar_dados_demanda(d jsonb)
returns void language plpgsql immutable set search_path = ''
as $$
begin
  if d ? 'titulo' and length(btrim(coalesce(d ->> 'titulo', ''))) < 3 then perform app.erro('Título com pelo menos 3 caracteres.', '22023'); end if;
  if d ? 'origem' and (d ->> 'origem') not in ('processo', 'email', 'whatsapp', 'recorrente', 'outra') then perform app.erro('Origem inválida.', '22023'); end if;
  if d ? 'prioridade' and (d ->> 'prioridade') not in ('baixa', 'media', 'alta', 'critica') then perform app.erro('Prioridade inválida.', '22023'); end if;
end $$;

-- ===== criar (chefia) =====
create or replace function public.criar_demanda(p_dados jsonb, p_responsaveis uuid[], p_checklist text[] default '{}')
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_unidade uuid := (p_dados ->> 'unidade_id')::uuid; v_item text; i integer := 0;
begin
  if not app.pode_gerir_demanda(v_unidade) then perform app.erro('Somente a chefia da unidade cria demandas.', '42501'); end if;
  perform app.validar_dados_demanda(p_dados);
  insert into public.demandas (titulo, descricao, origem, numero_processo, unidade_id, prioridade, prazo, criado_por)
  values (btrim(p_dados ->> 'titulo'), nullif(btrim(coalesce(p_dados ->> 'descricao', '')), ''), coalesce((p_dados ->> 'origem')::public.origem_demanda, 'outra'),
          nullif(btrim(coalesce(p_dados ->> 'numero_processo', '')), ''), v_unidade, coalesce((p_dados ->> 'prioridade')::public.prioridade_demanda, 'media'),
          (p_dados ->> 'prazo')::date, auth.uid())
  returning id into v_id;
  perform app.historico(v_id, 'criada', jsonb_build_object('prazo', p_dados ->> 'prazo'));
  perform app.definir_titulares(v_id, p_responsaveis);
  foreach v_item in array coalesce(p_checklist, '{}'::text[]) loop
    if btrim(v_item) <> '' then
      insert into public.demanda_checklist (demanda_id, texto, ordem) values (v_id, left(btrim(v_item), 300), i);
      i := i + 1;
    end if;
  end loop;
  return v_id;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
  perform app.erro('Dados inválidos.', '22023');
end $$;

-- ===== sugerir (funcionário) e decidir sugestão (chefia) =====
create or replace function public.sugerir_demanda(p_dados jsonb)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_unidade uuid := app.unidade_atual(); v_chefe uuid;
begin
  if not app.sessao_ok() or not app.tem_modulo('demandas') then perform app.erro('Acesso não permitido.', '42501'); end if;
  perform app.validar_dados_demanda(p_dados);
  insert into public.demandas (titulo, descricao, origem, numero_processo, unidade_id, prioridade, prazo, status, criado_por)
  values (btrim(p_dados ->> 'titulo'), nullif(btrim(coalesce(p_dados ->> 'descricao', '')), ''), coalesce((p_dados ->> 'origem')::public.origem_demanda, 'outra'),
          nullif(btrim(coalesce(p_dados ->> 'numero_processo', '')), ''), v_unidade, coalesce((p_dados ->> 'prioridade')::public.prioridade_demanda, 'media'),
          (p_dados ->> 'prazo')::date, 'sugerida', auth.uid())
  returning id into v_id;
  perform app.historico(v_id, 'sugerida');
  for v_chefe in select app.chefes_da_unidade(v_unidade) loop
    perform app.notificar(v_chefe, 'demanda_sugestao', 'Sugestão de demanda', app.titulo_demanda(v_id), '/demandas/ficha?id=' || v_id);
  end loop;
  return v_id;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
  perform app.erro('Dados inválidos.', '22023');
end $$;

create or replace function public.decidir_sugestao(p_id uuid, p_aprovar boolean, p_responsaveis uuid[] default '{}', p_prazo date default null, p_comentario text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare d public.demandas;
begin
  select * into d from public.demandas where id = p_id for update;
  if not found or d.status <> 'sugerida' then perform app.erro('Sugestão não encontrada ou já decidida.', 'P0002'); end if;
  if not app.pode_gerir_demanda(d.unidade_id) then perform app.erro('Somente a chefia da unidade decide sugestões.', '42501'); end if;
  if d.criado_por = auth.uid() then perform app.erro('Ninguém aprova a própria sugestão.', '42501'); end if;
  if p_aprovar then
    if coalesce(array_length(p_responsaveis, 1), 0) = 0 then perform app.erro('Indique pelo menos um responsável.', '22023'); end if;
    update public.demandas set status = 'a_fazer', prazo = coalesce(p_prazo, prazo) where id = p_id;
    perform app.historico(p_id, 'sugestao_aprovada', jsonb_build_object('comentario', p_comentario));
    perform app.definir_titulares(p_id, p_responsaveis);
  else
    if length(btrim(coalesce(p_comentario, ''))) = 0 then perform app.erro('Informe o comentário para recusar.', '22023'); end if;
    update public.demandas set status = 'recusada' where id = p_id;
    perform app.historico(p_id, 'sugestao_recusada', jsonb_build_object('comentario', p_comentario));
  end if;
  perform app.notificar(d.criado_por, 'demanda_sugestao_resultado', case when p_aprovar then 'Sugestão aprovada' else 'Sugestão recusada' end,
    app.titulo_demanda(p_id), '/demandas/ficha?id=' || p_id);
end $$;

-- ===== editar dados (chefia) =====
create or replace function public.atualizar_demanda(p_id uuid, p_dados jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare d public.demandas; v_antes jsonb; v_depois jsonb; k text;
begin
  select * into d from public.demandas where id = p_id for update;
  if not found then perform app.erro('Demanda não encontrada.', 'P0002'); end if;
  if not app.pode_gerir_demanda(d.unidade_id) then perform app.erro('Somente a chefia da unidade edita a demanda.', '42501'); end if;
  if exists (select 1 from jsonb_object_keys(p_dados) x where x not in ('titulo', 'descricao', 'origem', 'numero_processo', 'prioridade', 'prazo')) then
    perform app.erro('Campo não permitido.', '22023');
  end if;
  perform app.validar_dados_demanda(p_dados);
  v_antes := (select jsonb_object_agg(k2, to_jsonb(d) -> k2) from jsonb_object_keys(p_dados) k2);
  update public.demandas set
    titulo = case when p_dados ? 'titulo' then btrim(p_dados ->> 'titulo') else titulo end,
    descricao = case when p_dados ? 'descricao' then nullif(btrim(coalesce(p_dados ->> 'descricao', '')), '') else descricao end,
    origem = case when p_dados ? 'origem' then (p_dados ->> 'origem')::public.origem_demanda else origem end,
    numero_processo = case when p_dados ? 'numero_processo' then nullif(btrim(coalesce(p_dados ->> 'numero_processo', '')), '') else numero_processo end,
    prioridade = case when p_dados ? 'prioridade' then (p_dados ->> 'prioridade')::public.prioridade_demanda else prioridade end,
    prazo = case when p_dados ? 'prazo' then (p_dados ->> 'prazo')::date else prazo end
   where id = p_id returning to_jsonb(demandas.*) into v_depois;
  perform app.historico(p_id, 'editada', jsonb_build_object('antes', v_antes,
    'depois', (select jsonb_object_agg(k2, v_depois -> k2) from jsonb_object_keys(p_dados) k2)));
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
  perform app.erro('Dados inválidos.', '22023');
end $$;

create or replace function public.definir_responsaveis(p_id uuid, p_servidores uuid[])
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not app.pode_gerir_demanda((select unidade_id from public.demandas where id = p_id)) then
    perform app.erro('Somente a chefia da unidade distribui a demanda.', '42501');
  end if;
  if coalesce(array_length(p_servidores, 1), 0) = 0 then perform app.erro('Indique pelo menos um responsável.', '22023'); end if;
  perform app.definir_titulares(p_id, p_servidores);
end $$;

-- ===== status (responsável ou chefia). Concluir é ação explícita, nunca automática =====
create or replace function public.mudar_status_demanda(p_id uuid, p_status public.status_demanda)
returns void language plpgsql security definer set search_path = ''
as $$
declare d public.demandas;
begin
  select * into d from public.demandas where id = p_id for update;
  if not found then perform app.erro('Demanda não encontrada.', 'P0002'); end if;
  if not (app.eh_responsavel(p_id) or app.pode_gerir_demanda(d.unidade_id)) then
    perform app.erro('Somente responsáveis ou a chefia mudam o status.', '42501');
  end if;
  if d.status in ('sugerida', 'recusada') or p_status in ('sugerida', 'recusada') then perform app.erro('Use a decisão de sugestão.', '22023'); end if;
  if p_status = 'cancelada' and not app.pode_gerir_demanda(d.unidade_id) then perform app.erro('Somente a chefia cancela.', '42501'); end if;
  if d.status = p_status then return; end if;
  update public.demandas set status = p_status,
    iniciada_em = case when p_status = 'em_andamento' and iniciada_em is null then now() else iniciada_em end,
    concluida_em = case when p_status = 'concluida' then now() else null end
   where id = p_id;
  perform app.historico(p_id, 'status', jsonb_build_object('de', d.status, 'para', p_status));
end $$;

-- ===== checklist =====
create or replace function public.adicionar_item_checklist(p_demanda uuid, p_texto text, p_responsavel uuid default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not (app.eh_responsavel(p_demanda) or app.pode_gerir_demanda((select unidade_id from public.demandas where id = p_demanda))) then
    perform app.erro('Somente responsáveis ou a chefia editam o checklist.', '42501');
  end if;
  insert into public.demanda_checklist (demanda_id, texto, responsavel_id, ordem)
  values (p_demanda, left(btrim(p_texto), 300), p_responsavel, coalesce((select max(ordem) + 1 from public.demanda_checklist where demanda_id = p_demanda), 0))
  returning id into v_id;
  perform app.historico(p_demanda, 'etapa_incluida', jsonb_build_object('etapa', left(btrim(p_texto), 300)));
  return v_id;
end $$;

create or replace function public.marcar_item_checklist(p_item uuid, p_feito boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare c public.demanda_checklist;
begin
  select * into c from public.demanda_checklist where id = p_item and not removido;
  if not found then perform app.erro('Etapa não encontrada.', 'P0002'); end if;
  if not (app.eh_responsavel(c.demanda_id) or app.pode_gerir_demanda((select unidade_id from public.demandas where id = c.demanda_id))) then
    perform app.erro('Somente responsáveis ou a chefia marcam etapas.', '42501');
  end if;
  if c.feito = p_feito then return; end if;
  update public.demanda_checklist set feito = p_feito, feito_por = case when p_feito then auth.uid() end, feito_em = case when p_feito then now() end where id = p_item;
  perform app.historico(c.demanda_id, case when p_feito then 'etapa_marcada' else 'etapa_desmarcada' end, jsonb_build_object('etapa', c.texto));
end $$;

create or replace function public.remover_item_checklist(p_item uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare c public.demanda_checklist;
begin
  select * into c from public.demanda_checklist where id = p_item and not removido;
  if not found then perform app.erro('Etapa não encontrada.', 'P0002'); end if;
  if not app.pode_gerir_demanda((select unidade_id from public.demandas where id = c.demanda_id)) then perform app.erro('Somente a chefia remove etapas.', '42501'); end if;
  update public.demanda_checklist set removido = true where id = p_item;
  perform app.historico(c.demanda_id, 'etapa_removida', jsonb_build_object('etapa', c.texto));
end $$;

-- ===== listagem para quadro/lista (com nomes dos responsáveis e andamento do checklist) =====
create or replace function public.listar_demandas(p_incluir_encerradas_dias integer default 60)
returns table (id uuid, numero bigint, titulo text, origem public.origem_demanda, numero_processo text, unidade_id uuid, unidade text,
               prioridade public.prioridade_demanda, status public.status_demanda, prazo date, dias_uteis integer, concluida_em timestamptz,
               responsaveis jsonb, etapas_total integer, etapas_feitas integer, criado_por uuid, sou_responsavel boolean)
language sql stable security definer set search_path = ''
as $$
  select d.id, d.numero, d.titulo, d.origem, d.numero_processo, d.unidade_id, u.sigla, d.prioridade, d.status, d.prazo,
         case when d.prazo is null then null else public.dias_uteis_entre(current_date, d.prazo) end,
         d.concluida_em,
         coalesce((select jsonb_agg(jsonb_build_object('servidor_id', s.id, 'nome', s.nome_completo, 'papel', r.papel) order by r.papel, s.nome_completo)
                     from public.demanda_responsaveis r join public.servidores s on s.id = r.servidor_id where r.demanda_id = d.id and r.ativo), '[]'::jsonb),
         (select count(*)::int from public.demanda_checklist c where c.demanda_id = d.id and not c.removido),
         (select count(*)::int from public.demanda_checklist c where c.demanda_id = d.id and not c.removido and c.feito),
         d.criado_por, app.eh_responsavel(d.id)
    from public.demandas d join public.unidades u on u.id = d.unidade_id
   where app.pode_ver_demanda(d.id)
     and (d.status not in ('concluida', 'recusada', 'cancelada') or coalesce(d.concluida_em, d.atualizado_em) > now() - make_interval(days => greatest(p_incluir_encerradas_dias, 0)))
   order by d.prazo nulls last, d.numero
$$;

grant execute on function public.criar_demanda(jsonb, uuid[], text[]) to authenticated;
grant execute on function public.sugerir_demanda(jsonb) to authenticated;
grant execute on function public.decidir_sugestao(uuid, boolean, uuid[], date, text) to authenticated;
grant execute on function public.atualizar_demanda(uuid, jsonb) to authenticated;
grant execute on function public.definir_responsaveis(uuid, uuid[]) to authenticated;
grant execute on function public.mudar_status_demanda(uuid, public.status_demanda) to authenticated;
grant execute on function public.adicionar_item_checklist(uuid, text, uuid) to authenticated;
grant execute on function public.marcar_item_checklist(uuid, boolean) to authenticated;
grant execute on function public.remover_item_checklist(uuid) to authenticated;
grant execute on function public.listar_demandas(integer) to authenticated;
