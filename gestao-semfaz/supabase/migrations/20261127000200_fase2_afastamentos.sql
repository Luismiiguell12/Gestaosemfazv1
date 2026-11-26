-- Fase 2 · férias, licença-prêmio e folgas (6.7) + substituto (6.14)

create type public.tipo_afastamento as enum ('ferias', 'licenca_premio', 'folga');
create type public.status_afastamento as enum ('solicitado', 'aprovado', 'recusado', 'cancelado');

create table public.afastamentos (
  id uuid primary key default gen_random_uuid(),
  servidor_id uuid not null references public.servidores (id) on delete restrict,
  tipo public.tipo_afastamento not null,
  inicio date not null,
  fim date not null,
  status public.status_afastamento not null default 'solicitado',
  observacao text check (observacao is null or length(observacao) <= 1000),
  substituto_id uuid references public.servidores (id),
  conflito_mesmo_cargo boolean not null default false,
  solicitado_por uuid not null references public.usuarios (id),
  decidido_por uuid references public.usuarios (id),
  decidido_em timestamptz,
  comentario_decisao text check (comentario_decisao is null or length(comentario_decisao) <= 1000),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint afastamentos_periodo check (fim >= inicio and fim - inicio <= 366),
  constraint afastamentos_substituto_aprovado check (status <> 'aprovado' or substituto_id is not null),
  constraint afastamentos_substituto_outro check (substituto_id is null or substituto_id <> servidor_id),
  constraint afastamentos_recusa_comentada check (status <> 'recusado' or length(btrim(coalesce(comentario_decisao, ''))) > 0)
);
create index afastamentos_servidor_idx on public.afastamentos (servidor_id, inicio);
create index afastamentos_periodo_idx on public.afastamentos (inicio, fim) where status in ('solicitado', 'aprovado');
create trigger afastamentos_atualizado before update on public.afastamentos
  for each row execute function app.tocar_atualizado_em();
create trigger afastamentos_auditoria after insert or update or delete on public.afastamentos
  for each row execute function app.auditar_linha();

-- mesmo servidor não pode ter dois afastamentos ativos sobrepostos
create or replace function app.afastamentos_validar()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.status in ('solicitado', 'aprovado') and exists (
    select 1 from public.afastamentos a
     where a.servidor_id = new.servidor_id and a.id <> new.id and a.status in ('solicitado', 'aprovado')
       and daterange(a.inicio, a.fim, '[]') && daterange(new.inicio, new.fim, '[]')) then
    perform app.erro('Já existe férias, licença ou folga deste servidor nesse período.', '23P01');
  end if;
  -- aviso (não bloqueia): mesmo cargo e unidade com afastamento sobreposto
  new.conflito_mesmo_cargo := exists (
    select 1 from public.servidores t
      join public.servidores s on s.unidade_id = t.unidade_id and s.cargo_id = t.cargo_id and s.id <> t.id
      join public.afastamentos a on a.servidor_id = s.id and a.status in ('solicitado', 'aprovado') and a.id <> new.id
     where t.id = new.servidor_id and daterange(a.inicio, a.fim, '[]') && daterange(new.inicio, new.fim, '[]'));
  if new.substituto_id is not null then
    if not exists (select 1 from public.servidores s join public.servidores t on t.id = new.servidor_id
                    where s.id = new.substituto_id and s.unidade_id = t.unidade_id and s.situacao = 'ativo') then
      perform app.erro('O substituto deve ser um servidor ativo da mesma unidade.', '23514');
    end if;
    if new.status = 'aprovado' and exists (
      select 1 from public.afastamentos a
       where a.servidor_id = new.substituto_id and a.status = 'aprovado'
         and daterange(a.inicio, a.fim, '[]') && daterange(new.inicio, new.fim, '[]')) then
      perform app.erro('O substituto também estará afastado nesse período.', '23514');
    end if;
  end if;
  return new;
end $$;
create trigger afastamentos_validar before insert or update on public.afastamentos
  for each row execute function app.afastamentos_validar();

alter table public.afastamentos enable row level security;
revoke all on public.afastamentos from anon, authenticated;
grant select on public.afastamentos to authenticated;
-- próprio servidor; quem é substituto; chefia no escopo com módulo de férias; secretária/admin
create policy afastamentos_ler on public.afastamentos for select to authenticated using (
  (select app.sessao_ok()) and (
    servidor_id = (select app.servidor_atual())
    or substituto_id = (select app.servidor_atual())
    or ((select app.tem_modulo('ferias'))
        and exists (select 1 from public.servidores s where s.id = servidor_id and s.unidade_id in (select app.unidades_escopo())))
  )
);

-- chefia do servidor: perfil diretor/coordenador com a unidade no escopo e módulo de férias
create or replace function app.eh_chefia_de(p_servidor uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select app.gestor_geral()
      or (app.perfil_atual() in ('diretor', 'coordenador') and app.tem_modulo('ferias')
          and app.na_escopo((select unidade_id from public.servidores where id = p_servidor)))
$$;

-- usuários que chefiam a unidade (para notificar): coordenador da unidade e diretor acima dela
create or replace function app.chefes_da_unidade(p_unidade uuid)
returns setof uuid language sql stable security definer set search_path = ''
as $$
  select u.id from public.usuarios u join public.servidores s on s.id = u.servidor_id
   where u.ativo and s.situacao = 'ativo' and (
     (u.perfil = 'coordenador' and s.unidade_id = p_unidade)
     or (u.perfil = 'diretor' and p_unidade in (select app.subarvore(s.unidade_id)))
   )
$$;

create or replace function app.rotulo_afastamento(t public.tipo_afastamento)
returns text language sql immutable set search_path = ''
as $$ select case t when 'ferias' then 'Férias' when 'licenca_premio' then 'Licença-prêmio' else 'Folga' end $$;

-- outros servidores da mesma unidade e cargo com férias/afastamento no período (aviso, decisão é da chefia)
create or replace function public.conflitos_mesmo_cargo(p_servidor uuid, p_inicio date, p_fim date, p_ignorar uuid default null)
returns table (afastamento_id uuid, servidor_id uuid, nome text, tipo public.tipo_afastamento, inicio date, fim date, status public.status_afastamento)
language sql stable security definer set search_path = ''
as $$
  select a.id, s.id, s.nome_completo, a.tipo, a.inicio, a.fim, a.status
    from public.servidores t
    join public.servidores s on s.unidade_id = t.unidade_id and s.cargo_id = t.cargo_id and s.id <> t.id
    join public.afastamentos a on a.servidor_id = s.id and a.status in ('solicitado', 'aprovado')
   where t.id = p_servidor and app.eh_chefia_de(p_servidor)
     and (p_ignorar is null or a.id <> p_ignorar)
     and daterange(a.inicio, a.fim, '[]') && daterange(p_inicio, p_fim, '[]')
   order by a.inicio
$$;

create or replace function public.solicitar_afastamento(p_servidor uuid, p_tipo public.tipo_afastamento, p_inicio date, p_fim date, p_observacao text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_nome text; v_unidade uuid; v_conflito boolean; v_chefe uuid;
begin
  if not app.sessao_ok() then perform app.erro('Acesso não permitido.', '42501'); end if;
  if p_servidor is distinct from app.servidor_atual() and not app.eh_chefia_de(p_servidor) then
    perform app.erro('Você só pode pedir afastamento para você ou para servidores que chefia.', '42501');
  end if;
  if p_inicio is null or p_fim is null or p_fim < p_inicio then perform app.erro('Período inválido.', '22023'); end if;
  if p_inicio < current_date - 30 then perform app.erro('Período muito antigo.', '22023'); end if;
  select nome_completo, unidade_id into v_nome, v_unidade from public.servidores where id = p_servidor and situacao = 'ativo';
  if v_nome is null then perform app.erro('Servidor inexistente ou inativo.', 'P0002'); end if;
  insert into public.afastamentos (servidor_id, tipo, inicio, fim, observacao, solicitado_por)
  values (p_servidor, p_tipo, p_inicio, p_fim, nullif(btrim(coalesce(p_observacao, '')), ''), auth.uid())
  returning id, conflito_mesmo_cargo into v_id, v_conflito;
  for v_chefe in select app.chefes_da_unidade(v_unidade) loop
    if v_chefe <> auth.uid() then
      perform app.notificar(v_chefe, 'afastamento_pedido', app.rotulo_afastamento(p_tipo) || ' para aprovar',
        v_nome || ' · ' || to_char(p_inicio, 'DD/MM') || ' a ' || to_char(p_fim, 'DD/MM/YYYY')
        || case when v_conflito then ' · mesmo cargo no período' else '' end, '/ferias?pedido=' || v_id);
    end if;
  end loop;
  return v_id;
end $$;

-- aprovar exige substituto da mesma unidade; aviso de mesmo cargo não bloqueia (decisão da chefia)
create or replace function public.decidir_afastamento(p_id uuid, p_aprovar boolean, p_substituto uuid default null, p_comentario text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.afastamentos; v_nome text; v_unidade uuid; v_sub_usuario uuid; v_coment text := nullif(btrim(coalesce(p_comentario, '')), ''); v_chefe uuid;
begin
  if not app.sessao_ok() then perform app.erro('Acesso não permitido.', '42501'); end if;
  select * into a from public.afastamentos where id = p_id for update;
  if not found then perform app.erro('Pedido não encontrado.', 'P0002'); end if;
  if not app.eh_chefia_de(a.servidor_id) then perform app.erro('Somente a chefia do servidor pode decidir.', '42501'); end if;
  if a.servidor_id = app.servidor_atual() then perform app.erro('Ninguém aprova o próprio afastamento.', '42501'); end if;
  if a.status <> 'solicitado' then perform app.erro('Este pedido já foi decidido.', '22023'); end if;
  select nome_completo, unidade_id into v_nome, v_unidade from public.servidores where id = a.servidor_id;

  if not p_aprovar then
    if v_coment is null then perform app.erro('Informe o comentário para recusar.', '22023'); end if;
    update public.afastamentos set status = 'recusado', decidido_por = auth.uid(), decidido_em = now(), comentario_decisao = v_coment where id = p_id;
  else
    if p_substituto is null then perform app.erro('Indique o substituto (obrigatório).', '22023'); end if;
    update public.afastamentos set status = 'aprovado', substituto_id = p_substituto, decidido_por = auth.uid(), decidido_em = now(),
      comentario_decisao = v_coment where id = p_id;
    select u.id into v_sub_usuario from public.usuarios u where u.servidor_id = p_substituto and u.ativo;
    if v_sub_usuario is not null then
      perform app.notificar(v_sub_usuario, 'substituto', 'Você será substituto',
        v_nome || ' · ' || app.rotulo_afastamento(a.tipo) || ' ' || to_char(a.inicio, 'DD/MM') || ' a ' || to_char(a.fim, 'DD/MM/YYYY'), '/ferias');
    end if;
    for v_chefe in select app.chefes_da_unidade(v_unidade) loop
      if v_chefe <> auth.uid() then
        perform app.notificar(v_chefe, 'afastamento_aprovado', app.rotulo_afastamento(a.tipo) || ' aprovada(s)',
          v_nome || ' · substituto: ' || (select nome_completo from public.servidores where id = p_substituto), '/ferias');
      end if;
    end loop;
  end if;
  perform app.notificar(a.solicitado_por, 'afastamento_resultado',
    app.rotulo_afastamento(a.tipo) || case when p_aprovar then ' aprovada(s)' else ' recusada(s)' end,
    v_nome || ' · ' || to_char(a.inicio, 'DD/MM') || ' a ' || to_char(a.fim, 'DD/MM/YYYY'), '/ferias');
end $$;

-- escala editável pela chefia: remarcar período ou cancelar (auditado); solicitante cancela o próprio pedido pendente
create or replace function public.remarcar_afastamento(p_id uuid, p_inicio date, p_fim date, p_substituto uuid default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.afastamentos;
begin
  if not app.sessao_ok() then perform app.erro('Acesso não permitido.', '42501'); end if;
  select * into a from public.afastamentos where id = p_id for update;
  if not found then perform app.erro('Registro não encontrado.', 'P0002'); end if;
  if not app.eh_chefia_de(a.servidor_id) or a.servidor_id = app.servidor_atual() then
    perform app.erro('Somente a chefia do servidor pode remarcar.', '42501');
  end if;
  if a.status not in ('solicitado', 'aprovado') then perform app.erro('Só é possível remarcar pedidos ativos.', '22023'); end if;
  if p_inicio is null or p_fim is null or p_fim < p_inicio then perform app.erro('Período inválido.', '22023'); end if;
  update public.afastamentos set inicio = p_inicio, fim = p_fim, substituto_id = coalesce(p_substituto, substituto_id) where id = p_id;
end $$;

create or replace function public.cancelar_afastamento(p_id uuid, p_motivo text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.afastamentos;
begin
  if not app.sessao_ok() then perform app.erro('Acesso não permitido.', '42501'); end if;
  select * into a from public.afastamentos where id = p_id for update;
  if not found then perform app.erro('Registro não encontrado.', 'P0002'); end if;
  if not ((a.solicitado_por = auth.uid() and a.status = 'solicitado')
          or (app.eh_chefia_de(a.servidor_id) and a.servidor_id is distinct from app.servidor_atual())) then
    perform app.erro('Você não pode cancelar este registro.', '42501');
  end if;
  if a.status not in ('solicitado', 'aprovado') then perform app.erro('Registro já encerrado.', '22023'); end if;
  update public.afastamentos set status = 'cancelado', comentario_decisao = nullif(btrim(coalesce(p_motivo, '')), '') where id = p_id;
end $$;

-- ausências do mês (painel). Mesma regra de visibilidade de afastamentos_ler,
-- aplicada explicitamente (o substituto precisa ver o nome de quem substitui).
create or replace function public.ausencias_do_mes(p_mes date default current_date)
returns table (afastamento_id uuid, servidor text, unidade text, tipo public.tipo_afastamento, inicio date, fim date, substituto text)
language sql stable security definer set search_path = ''
as $$
  select a.id, s.nome_completo, u.sigla, a.tipo, a.inicio, a.fim,
         (select sb.nome_completo from public.servidores sb where sb.id = a.substituto_id)
    from public.afastamentos a
    join public.servidores s on s.id = a.servidor_id
    join public.unidades u on u.id = s.unidade_id
   where a.status = 'aprovado' and app.sessao_ok()
     and (a.servidor_id = app.servidor_atual() or a.substituto_id = app.servidor_atual()
          or (app.tem_modulo('ferias') and app.na_escopo(s.unidade_id)))
     and daterange(a.inicio, a.fim, '[]') && daterange(date_trunc('month', p_mes)::date, (date_trunc('month', p_mes) + interval '1 month - 1 day')::date, '[]')
   order by a.inicio
$$;

grant execute on function public.conflitos_mesmo_cargo(uuid, date, date, uuid) to authenticated;
grant execute on function public.solicitar_afastamento(uuid, public.tipo_afastamento, date, date, text) to authenticated;
grant execute on function public.decidir_afastamento(uuid, boolean, uuid, text) to authenticated;
grant execute on function public.remarcar_afastamento(uuid, date, date, uuid) to authenticated;
grant execute on function public.cancelar_afastamento(uuid, text) to authenticated;
grant execute on function public.ausencias_do_mes(date) to authenticated;
revoke execute on function public.conflitos_mesmo_cargo(uuid, date, date, uuid) from anon;
revoke execute on function public.solicitar_afastamento(uuid, public.tipo_afastamento, date, date, text) from anon;
revoke execute on function public.decidir_afastamento(uuid, boolean, uuid, text) from anon;
revoke execute on function public.remarcar_afastamento(uuid, date, date, uuid) from anon;
revoke execute on function public.cancelar_afastamento(uuid, text) from anon;
revoke execute on function public.ausencias_do_mes(date) from anon;
