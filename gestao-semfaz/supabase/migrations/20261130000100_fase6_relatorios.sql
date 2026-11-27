-- Fase 6 · relatórios (6.11) e registro de exportações (5.1: auditoria e limite)
-- Relatórios de dados = SECURITY INVOKER: as próprias políticas de RLS decidem o escopo
-- (secretária/admin tudo; diretor a diretoria; coordenador a unidade; funcionário o próprio).

create or replace function app.pode_relatorio(p_modulo text default null)
returns boolean language sql stable security definer set search_path = ''
as $$ select app.sessao_ok() and app.tem_modulo('relatorios') and (p_modulo is null or app.tem_modulo(p_modulo)) $$;
grant execute on function app.pode_relatorio(text) to authenticated;

-- ===== exportações: histórico próprio ("Gerados recentemente") + auditoria + limite =====
create table public.exportacoes (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.usuarios (id),
  relatorio text not null check (relatorio ~ '^[a-z_]{3,40}$'),
  titulo text not null check (length(titulo) between 1 and 200),
  formato text not null check (formato in ('pdf', 'xlsx', 'csv')),
  filtros jsonb not null default '{}'::jsonb check (length(filtros::text) <= 2000),
  linhas integer not null check (linhas >= 0),
  em timestamptz not null default now()
);
create index exportacoes_usuario_idx on public.exportacoes (usuario_id, em desc);
alter table public.exportacoes enable row level security;
revoke all on public.exportacoes from anon, authenticated;
grant select on public.exportacoes to authenticated;
create policy exportacoes_ler on public.exportacoes for select to authenticated
  using ((select app.sessao_ok()) and usuario_id = (select auth.uid()));
create trigger exportacoes_imutavel before update or delete on public.exportacoes for each row execute function app.auditoria_imutavel();

insert into public.configuracoes (chave, valor, descricao) values
  ('relatorios.exportacoes_por_hora', '60', 'Limite de exportações por usuário por hora'),
  ('relatorios.linhas_max', '20000', 'Máximo de linhas por relatório')
on conflict (chave) do nothing;

create or replace function public.registrar_exportacao(p_relatorio text, p_titulo text, p_formato text, p_filtros jsonb, p_linhas integer)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_lim integer := coalesce((select (valor)::int from public.configuracoes where chave = 'relatorios.exportacoes_por_hora'), 60);
begin
  if not app.pode_relatorio() then perform app.erro('Sem permissão para relatórios.', '42501'); end if;
  if (select count(*) from public.exportacoes where usuario_id = auth.uid() and em > now() - interval '1 hour') >= v_lim then
    perform app.erro('Limite de exportações por hora atingido. Tente mais tarde.', '54000');
  end if;
  insert into public.exportacoes (usuario_id, relatorio, titulo, formato, filtros, linhas)
  values (auth.uid(), p_relatorio, left(p_titulo, 200), p_formato, coalesce(p_filtros, '{}'::jsonb), p_linhas);
  perform app.registrar_evento('exportacao', 'relatorios', p_relatorio, null,
    jsonb_build_object('formato', p_formato, 'filtros', coalesce(p_filtros, '{}'::jsonb), 'linhas', p_linhas));
exception when check_violation then perform app.erro('Dados da exportação inválidos.', '22023');
end $$;

-- ===== Demandas =====
create or replace function public.relatorio_demandas_unidade(p_de date, p_ate date, p_unidade uuid default null)
returns table (unidade text, abertas integer, atrasadas integer, criadas_periodo integer, concluidas_periodo integer, concluidas_no_prazo integer, no_prazo_pct integer)
language sql stable security invoker set search_path = ''
as $$
  select u.sigla,
    count(*) filter (where d.status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao'))::int,
    count(*) filter (where d.status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao') and d.prazo < current_date)::int,
    count(*) filter (where (d.criado_em at time zone 'America/Maceio')::date between p_de and p_ate)::int,
    count(*) filter (where d.status = 'concluida' and (d.concluida_em at time zone 'America/Maceio')::date between p_de and p_ate)::int,
    count(*) filter (where d.status = 'concluida' and (d.concluida_em at time zone 'America/Maceio')::date between p_de and p_ate
                     and d.prazo is not null and (d.concluida_em at time zone 'America/Maceio')::date <= d.prazo)::int,
    case when count(*) filter (where d.status = 'concluida' and (d.concluida_em at time zone 'America/Maceio')::date between p_de and p_ate and d.prazo is not null) = 0 then null
         else round(100.0 * count(*) filter (where d.status = 'concluida' and (d.concluida_em at time zone 'America/Maceio')::date between p_de and p_ate
                     and d.prazo is not null and (d.concluida_em at time zone 'America/Maceio')::date <= d.prazo)
                   / count(*) filter (where d.status = 'concluida' and (d.concluida_em at time zone 'America/Maceio')::date between p_de and p_ate and d.prazo is not null))::int end
  from public.demandas d join public.unidades u on u.id = d.unidade_id
  where app.pode_relatorio('demandas') and d.status not in ('sugerida', 'recusada', 'cancelada')
    and (p_unidade is null or d.unidade_id = p_unidade)
  group by u.sigla, u.ordem
  order by u.ordem, u.sigla
$$;

create or replace function public.relatorio_demandas_servidor(p_de date, p_ate date, p_unidade uuid default null)
returns table (servidor text, matricula text, unidade text, recebidas_periodo integer, abertas integer, atrasadas integer, concluidas_periodo integer, concluidas_no_prazo integer)
language sql stable security invoker set search_path = ''
as $$
  select s.nome_completo, s.matricula, u.sigla,
    count(*) filter (where (r.adicionado_em at time zone 'America/Maceio')::date between p_de and p_ate)::int,
    count(*) filter (where r.ativo and d.status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao'))::int,
    count(*) filter (where r.ativo and d.status in ('a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao') and d.prazo < current_date)::int,
    count(*) filter (where d.status = 'concluida' and (d.concluida_em at time zone 'America/Maceio')::date between p_de and p_ate)::int,
    count(*) filter (where d.status = 'concluida' and (d.concluida_em at time zone 'America/Maceio')::date between p_de and p_ate
                     and d.prazo is not null and (d.concluida_em at time zone 'America/Maceio')::date <= d.prazo)::int
  from public.demanda_responsaveis r
  join public.demandas d on d.id = r.demanda_id
  join public.servidores s on s.id = r.servidor_id
  left join public.unidades u on u.id = s.unidade_id
  where app.pode_relatorio('demandas') and d.status not in ('sugerida', 'recusada', 'cancelada')
    and (p_unidade is null or d.unidade_id = p_unidade)
  group by s.nome_completo, s.matricula, u.sigla
  order by u.sigla, s.nome_completo
$$;

-- ===== Contratos =====
create or replace function public.relatorio_contratos(p_situacao text default 'vigentes')
returns table (numero text, processo text, locador text, imovel text, unidade text, inicio date, fim_vigencia date, dias_restantes integer,
               valor_mensal numeric, valor_anual numeric, aditivos integer, fiscal text, encerrado boolean)
language sql stable security invoker set search_path = ''
as $$
  select c.numero, c.processo, l.nome, c.imovel_descricao, u.sigla, c.inicio, c.fim_vigencia, c.fim_vigencia - current_date,
         c.valor_mensal, c.valor_mensal * 12, (select count(*) from public.aditivos a where a.contrato_id = c.id)::int, s.nome_completo, c.encerrado
    from public.contratos c join public.locadores l on l.id = c.locador_id
    left join public.unidades u on u.id = c.unidade_ocupante_id left join public.servidores s on s.id = c.fiscal_servidor_id
   where app.pode_relatorio('contratos')
     and case coalesce(p_situacao, 'vigentes') when 'vigentes' then not c.encerrado when 'encerrados' then c.encerrado else true end
   order by c.encerrado, c.fim_vigencia
$$;

create or replace function public.relatorio_contratos_vencer(p_dias integer default 90)
returns table (numero text, locador text, imovel text, unidade text, fim_vigencia date, dias_restantes integer, valor_mensal numeric, fiscal text, renovacao text)
language sql stable security invoker set search_path = ''
as $$
  select c.numero, l.nome, c.imovel_descricao, u.sigla, c.fim_vigencia, c.fim_vigencia - current_date, c.valor_mensal, s.nome_completo,
         (select '#' || d.numero || ' · ' || d.status::text from public.demandas d where d.contrato_id = c.id order by d.criado_em desc limit 1)
    from public.contratos c join public.locadores l on l.id = c.locador_id
    left join public.unidades u on u.id = c.unidade_ocupante_id left join public.servidores s on s.id = c.fiscal_servidor_id
   where app.pode_relatorio('contratos') and not c.encerrado
     and c.fim_vigencia between current_date and current_date + least(greatest(coalesce(p_dias, 90), 1), 3650)
   order by c.fim_vigencia
$$;

create or replace function public.relatorio_alugueis(p_de date, p_ate date, p_situacao text default 'todos')
returns table (competencia date, contrato text, locador text, imovel text, valor numeric, vencimento date, pago_em date, valor_pago numeric, situacao text)
language sql stable security invoker set search_path = ''
as $$
  select a.competencia, c.numero, l.nome, c.imovel_descricao, a.valor, a.vencimento, a.pago_em, a.valor_pago,
         case when a.pago_em is not null then 'pago' when a.vencimento < current_date then 'vencido' else 'pendente' end
    from public.alugueis a join public.contratos c on c.id = a.contrato_id join public.locadores l on l.id = c.locador_id
   where app.pode_relatorio('contratos')
     and a.competencia between date_trunc('month', p_de)::date and date_trunc('month', p_ate)::date
     and case coalesce(p_situacao, 'todos') when 'pagos' then a.pago_em is not null when 'pendentes' then a.pago_em is null
                                            when 'vencidos' then a.pago_em is null and a.vencimento < current_date else true end
   order by a.competencia, c.numero
$$;

-- ===== Água e energia =====
create or replace function public.relatorio_faturas(p_de date, p_ate date, p_fornecedor public.fornecedor_uc default null, p_so_vencidas boolean default false)
returns table (competencia date, fornecedor text, uc text, contrato text, imovel text, consumo numeric, valor numeric, vencimento date, pago_em date, situacao text)
language sql stable security invoker set search_path = ''
as $$
  select f.competencia, u.fornecedor::text, u.numero, c.numero, c.imovel_descricao, f.consumo, f.valor, f.vencimento, f.pago_em,
         case when f.pago_em is not null then 'paga' when f.vencimento < current_date then 'vencida' else 'pendente' end
    from public.faturas f join public.unidades_consumidoras u on u.id = f.uc_id join public.contratos c on c.id = u.contrato_id
   where app.pode_relatorio() and app.acesso_ucs()
     and f.competencia between date_trunc('month', p_de)::date and date_trunc('month', p_ate)::date
     and (p_fornecedor is null or u.fornecedor = p_fornecedor)
     and (not coalesce(p_so_vencidas, false) or (f.pago_em is null and f.vencimento < current_date))
   order by f.competencia, u.fornecedor, u.numero
$$;

create or replace function public.relatorio_gasto_contrato(p_de date, p_ate date)
returns table (contrato text, imovel text, unidade text, aluguel numeric, agua numeric, energia numeric, total numeric)
language sql stable security invoker set search_path = ''
as $$
  with x as (
    select c.id, c.numero, c.imovel_descricao, un.sigla,
      coalesce((select sum(a.valor) from public.alugueis a where a.contrato_id = c.id and a.competencia between date_trunc('month', p_de)::date and date_trunc('month', p_ate)::date), 0) aluguel,
      coalesce((select sum(f.valor) from public.faturas f join public.unidades_consumidoras u on u.id = f.uc_id
                 where u.contrato_id = c.id and u.fornecedor = 'igua' and f.competencia between date_trunc('month', p_de)::date and date_trunc('month', p_ate)::date), 0) agua,
      coalesce((select sum(f.valor) from public.faturas f join public.unidades_consumidoras u on u.id = f.uc_id
                 where u.contrato_id = c.id and u.fornecedor <> 'igua' and f.competencia between date_trunc('month', p_de)::date and date_trunc('month', p_ate)::date), 0) energia
    from public.contratos c left join public.unidades un on un.id = c.unidade_ocupante_id
    where app.pode_relatorio('contratos')
  )
  select numero, imovel_descricao, sigla, aluguel, agua, energia, aluguel + agua + energia from x
   where aluguel + agua + energia > 0 order by aluguel + agua + energia desc
$$;

-- ===== Pessoas e controle =====
create or replace function public.relatorio_escala_ferias(p_ano integer, p_unidade uuid default null)
returns table (servidor text, matricula text, cargo text, unidade text, tipo text, inicio date, fim date, dias integer, situacao text, substituto text)
language sql stable security invoker set search_path = ''
as $$
  select s.nome_completo, s.matricula, cg.nome, u.sigla, a.tipo::text, a.inicio, a.fim, (a.fim - a.inicio + 1), a.status::text, sb.nome_completo
    from public.afastamentos a join public.servidores s on s.id = a.servidor_id
    left join public.cargos cg on cg.id = s.cargo_id left join public.unidades u on u.id = s.unidade_id
    left join public.servidores sb on sb.id = a.substituto_id
   where app.pode_relatorio('ferias') and a.status in ('solicitado', 'aprovado')
     and a.inicio <= make_date(p_ano, 12, 31) and a.fim >= make_date(p_ano, 1, 1)
     and (p_unidade is null or s.unidade_id = p_unidade)
   order by u.sigla, cg.nome, s.nome_completo, a.inicio
$$;

create or replace function public.relatorio_saldos(p_unidade uuid default null)
returns table (servidor text, matricula text, cargo text, unidade text, ferias_dias numeric, licenca_premio_dias numeric, folgas numeric, fonte text, atualizado_em timestamptz)
language sql stable security invoker set search_path = ''
as $$
  select s.nome_completo, s.matricula, cg.nome, u.sigla, sd.ferias_dias, sd.licenca_premio_dias, sd.folgas, sd.fonte, sd.atualizado_em
    from public.saldos_servidor sd join public.servidores s on s.id = sd.servidor_id
    left join public.cargos cg on cg.id = s.cargo_id left join public.unidades u on u.id = s.unidade_id
   where app.pode_relatorio('ferias') and s.situacao = 'ativo' and (p_unidade is null or s.unidade_id = p_unidade)
   order by u.sigla, s.nome_completo
$$;

create or replace function public.relatorio_folhas(p_de date, p_ate date)
returns table (competencia date, unidade text, situacao text, enviada_em date, recebida_por text, devolvida_em date, devolvida_por text, atrasada boolean)
language sql stable security invoker set search_path = ''
as $$
  select m::date, e.sigla, e.situacao, e.enviada_em, e.recebida_por, e.devolvida_em, e.devolvida_por, e.atrasada
    from generate_series(date_trunc('month', p_de), date_trunc('month', p_ate), interval '1 month') m
    cross join lateral public.situacao_entregas(m::date) e
   where app.pode_relatorio('folhas_ponto')
   order by 1, e.ordem, e.sigla
$$;

-- auditoria: só secretária/admin com o módulo; nome do autor em vez do id
create or replace function public.relatorio_auditoria(p_de date, p_ate date, p_tabela text default null)
returns table (em timestamptz, autor text, perfil text, acao text, tabela text, registro text, antes jsonb, depois jsonb, contexto jsonb)
language plpgsql stable security definer set search_path = ''
as $$
declare v_max integer := coalesce((select (valor)::int from public.configuracoes where chave = 'relatorios.linhas_max'), 20000);
begin
  if not (app.pode_relatorio('auditoria') and app.gestor_geral()) then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  return query
    select a.em, coalesce(app.nome_usuario(a.ator_id), case when a.ator_id is null then 'Sistema' else 'Usuário removido' end), a.ator_perfil::text,
           a.acao, a.tabela, a.registro_id, a.antes, a.depois, a.contexto
      from public.auditoria a
     where a.em >= (p_de::timestamp at time zone 'America/Maceio') and a.em < ((p_ate + 1)::timestamp at time zone 'America/Maceio')
       and (nullif(p_tabela, '') is null or a.tabela = p_tabela)
     order by a.em desc
     limit v_max;
end $$;

grant execute on function public.registrar_exportacao(text, text, text, jsonb, integer) to authenticated;
grant execute on function public.relatorio_demandas_unidade(date, date, uuid), public.relatorio_demandas_servidor(date, date, uuid),
  public.relatorio_contratos(text), public.relatorio_contratos_vencer(integer), public.relatorio_alugueis(date, date, text),
  public.relatorio_faturas(date, date, public.fornecedor_uc, boolean), public.relatorio_gasto_contrato(date, date),
  public.relatorio_escala_ferias(integer, uuid), public.relatorio_saldos(uuid), public.relatorio_folhas(date, date),
  public.relatorio_auditoria(date, date, text) to authenticated;
