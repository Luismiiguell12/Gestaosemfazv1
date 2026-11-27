-- Fase 4 · renovação automática (6.17), avisos de vencimento (6.10), painel e busca

alter table public.demandas add column contrato_id uuid references public.contratos (id);
create index demandas_contrato_idx on public.demandas (contrato_id) where contrato_id is not null;

-- uma renovação por vigência (fim efetivo): aditivo de prazo gera nova vigência → nova renovação no futuro
create table public.contrato_renovacoes (
  contrato_id uuid not null references public.contratos (id),
  fim_vigencia date not null,
  demanda_id uuid references public.demandas (id),
  criada_em timestamptz not null default now(),
  primary key (contrato_id, fim_vigencia)
);
create table public.contrato_avisos (
  contrato_id uuid not null references public.contratos (id),
  fim_vigencia date not null,
  dias integer not null,
  em timestamptz not null default now(),
  primary key (contrato_id, fim_vigencia, dias)
);
do $$
declare t text;
begin
  foreach t in array array['contrato_renovacoes', 'contrato_avisos'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;
create policy contrato_renov_ler on public.contrato_renovacoes for select to authenticated using ((select app.acesso_contratos()));
create policy contrato_avisos_ler on public.contrato_avisos for select to authenticated using ((select app.acesso_contratos()));

insert into public.configuracoes (chave, valor, descricao) values
  ('contratos.dias_renovacao', '90', 'Dias antes do fim da vigência para criar a demanda de renovação'),
  ('contratos.dias_aviso_vencimento', '[90, 60, 30, 15]', 'Dias antes do fim da vigência em que quem tem o módulo contratos é avisado'),
  ('contratos.checklist_renovacao', '["Certidões do locador", "Laudo de avaliação", "Manifestação de interesse", "Parecer jurídico"]',
   'Checklist de documentos da demanda de renovação (provisório — validar com a SEMFAZ)'),
  ('contratos.prazo_renovacao_dias_uteis', '30', 'Prazo (dias úteis) da demanda de renovação')
on conflict (chave) do nothing;

-- usuários ativos com um módulo (pacote do perfil ∪ extras) — para avisos de rotinas sem sessão
create or replace function app.usuarios_com_modulo(p_codigo text)
returns setof uuid language sql stable security definer set search_path = ''
as $$
  select u.id from public.usuarios u join public.servidores s on s.id = u.servidor_id
   where u.ativo and s.situacao = 'ativo'
     and (exists (select 1 from public.pacotes_padrao pp where pp.perfil = u.perfil and pp.modulo_codigo = p_codigo)
          or exists (select 1 from public.usuario_modulos_extras e where e.usuario_id = u.id and e.modulo_codigo = p_codigo))
$$;

-- cria a demanda de renovação (uma vez por vigência)
create or replace function app.criar_renovacao(p_contrato uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  c public.contratos; v_id uuid; v_unidade uuid; v_criador uuid; v_item text; i integer := 0; v_u uuid;
  v_prazo integer := coalesce((select (valor)::int from public.configuracoes where chave = 'contratos.prazo_renovacao_dias_uteis'), 30);
begin
  select * into c from public.contratos where id = p_contrato;
  insert into public.contrato_renovacoes (contrato_id, fim_vigencia) values (c.id, c.fim_vigencia) on conflict do nothing;
  if not found then return null; end if;  -- já criada para esta vigência
  v_unidade := coalesce((select unidade_id from public.servidores where id = c.fiscal_servidor_id), c.unidade_ocupante_id,
                        (select id from public.unidades where unidade_pai_id is null and ativa order by ordem limit 1));
  v_criador := coalesce(app.usuario_do_servidor(c.fiscal_servidor_id), c.criado_por,
                        (select u.id from public.usuarios u where u.ativo and u.perfil in ('secretaria', 'administrador') order by u.perfil limit 1));
  insert into public.demandas (titulo, descricao, origem, unidade_id, prioridade, prazo, criado_por, contrato_id)
  values ('Renovação do contrato nº ' || c.numero, 'Demanda criada automaticamente: a vigência do contrato termina em ' || to_char(c.fim_vigencia, 'DD/MM/YYYY') || '.',
          'outra', v_unidade, 'alta', least(public.somar_dias_uteis(current_date, v_prazo), c.fim_vigencia), v_criador, c.id)
  returning id into v_id;
  update public.contrato_renovacoes set demanda_id = v_id where contrato_id = c.id and fim_vigencia = c.fim_vigencia;
  perform app.historico(v_id, 'criada', jsonb_build_object('automatica', 'renovacao'));
  if c.fiscal_servidor_id is not null then perform app.definir_titulares(v_id, array[c.fiscal_servidor_id]); end if;
  for v_item in select jsonb_array_elements_text(coalesce((select valor from public.configuracoes where chave = 'contratos.checklist_renovacao'), '[]'::jsonb)) loop
    insert into public.demanda_checklist (demanda_id, texto, ordem) values (v_id, left(v_item, 300), i); i := i + 1;
  end loop;
  -- quem tem a permissão de contratos acompanha a demanda
  for v_u in select app.usuarios_com_modulo('contratos') loop
    insert into public.demanda_participantes (demanda_id, usuario_id) values (v_id, v_u) on conflict do nothing;
    perform app.notificar(v_u, 'contrato_renovacao', 'Renovação de contrato', 'Renovação do contrato nº ' || c.numero, '/demandas/ficha?id=' || v_id);
  end loop;
  perform app.historico_contrato(c.id, 'renovacao_criada', jsonb_build_object('demanda', v_id));
  return v_id;
end $$;

create or replace function app.rotina_contratos()
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  c public.contratos; v_dias integer; v_marco integer; v_u uuid; n integer := 0;
  v_renov integer := coalesce((select (valor)::int from public.configuracoes where chave = 'contratos.dias_renovacao'), 90);
  v_marcos integer[] := coalesce((select array(select jsonb_array_elements_text(valor)::int) from public.configuracoes where chave = 'contratos.dias_aviso_vencimento'), array[90, 60, 30, 15]);
begin
  for c in select * from public.contratos where not encerrado and fim_vigencia >= current_date loop
    v_dias := c.fim_vigencia - current_date;
    if v_dias <= v_renov and app.criar_renovacao(c.id) is not null then n := n + 1; end if;
    -- aviso no menor marco já alcançado, uma vez por marco
    select min(m) into v_marco from unnest(v_marcos) m where v_dias <= m;
    if v_marco is not null then
      insert into public.contrato_avisos (contrato_id, fim_vigencia, dias) values (c.id, c.fim_vigencia, v_marco) on conflict do nothing;
      if found then
        for v_u in select app.usuarios_com_modulo('contratos') union select app.usuario_do_servidor(c.fiscal_servidor_id) loop
          continue when v_u is null;
          perform app.notificar(v_u, 'contrato_vencendo', 'Contrato vencendo',
            'Contrato nº ' || c.numero || ' termina em ' || to_char(c.fim_vigencia, 'DD/MM/YYYY') || ' (' || v_dias || ' dias)', '/contratos/ficha?id=' || c.id);
        end loop;
      end if;
    end if;
  end loop;
  return n;
end $$;

create or replace function app.rotinas_diarias_demandas()
returns void language plpgsql security definer set search_path = ''
as $$ begin perform app.gerar_ocorrencias(); perform app.aplicar_substituicoes(); perform app.rotina_contratos(); perform app.avisar_prazos(); end $$;
revoke execute on function app.rotinas_diarias_demandas() from public, anon, authenticated;
revoke execute on function app.rotina_contratos() from public, anon, authenticated;
revoke execute on function app.criar_renovacao(uuid) from public, anon, authenticated;

-- aditivo de prazo aprovado: avisa na demanda de renovação aberta
create or replace function app.renovacao_registrada(p_contrato uuid, p_novo_fim date)
returns void language plpgsql security definer set search_path = ''
as $$
declare r record; v_s uuid; v_u uuid;
begin
  for r in select d.id, d.numero, d.titulo from public.demandas d where d.contrato_id = p_contrato and d.status not in ('concluida', 'recusada', 'cancelada') loop
    perform app.historico(r.id, 'renovacao_registrada', jsonb_build_object('novo_fim', to_char(p_novo_fim, 'DD/MM/YYYY')));
    for v_u in select app.usuario_do_servidor(servidor_id) from public.demanda_responsaveis where demanda_id = r.id and ativo
               union select usuario_id from public.demanda_participantes where demanda_id = r.id loop
      continue when v_u is null;
      perform app.notificar(v_u, 'contrato_renovacao', 'Renovação registrada',
        'Aditivo de prazo aprovado (#' || r.numero || '): nova vigência até ' || to_char(p_novo_fim, 'DD/MM/YYYY'), '/demandas/ficha?id=' || r.id);
    end loop;
  end loop;
end $$;

-- ===== ficha do contrato (protótipo Contrato) =====
create or replace function public.contrato_ficha(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare c public.contratos; v jsonb;
begin
  if not app.acesso_contratos() then perform app.erro('Sem permissão para contratos.', '42501'); end if;
  select * into c from public.contratos where id = p_id;
  if not found then return null; end if;
  select jsonb_build_object(
    'contrato', to_jsonb(c) || jsonb_build_object(
        'valor_anual', c.valor_mensal * 12,
        'unidade', (select sigla from public.unidades where id = c.unidade_ocupante_id),
        'fiscal', (select nome_completo from public.servidores where id = c.fiscal_servidor_id),
        'dias_restantes', c.fim_vigencia - current_date),
    'locador', public.locador_dados(c.locador_id, false),
    'aditivos', coalesce((select jsonb_agg(to_jsonb(a) order by a.numero) from public.aditivos a where a.contrato_id = c.id), '[]'::jsonb),
    'alugueis', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'competencia', a.competencia, 'valor', a.valor, 'vencimento', a.vencimento,
                  'pago_em', a.pago_em, 'valor_pago', a.valor_pago,
                  'situacao', case when a.pago_em is not null then 'pago' when a.vencimento < current_date then 'atrasado' else 'pendente' end) order by a.competencia)
                  from public.alugueis a where a.contrato_id = c.id), '[]'::jsonb),
    'ucs', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'fornecedor', u.fornecedor, 'numero', u.numero, 'descricao', u.descricao,
                  'ultima', (select jsonb_build_object('competencia', f.competencia, 'valor', f.valor, 'pago_em', f.pago_em, 'vencimento', f.vencimento)
                               from public.faturas f where f.uc_id = u.id order by f.competencia desc limit 1)) order by u.fornecedor, u.numero)
                  from public.unidades_consumidoras u where u.contrato_id = c.id and u.ativa), '[]'::jsonb),
    'documentos', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'nome', d.nome, 'path', d.path, 'tamanho', d.tamanho, 'aditivo_id', d.aditivo_id,
                  'enviado_em', d.enviado_em, 'enviado_por', app.nome_usuario(d.enviado_por)) order by d.enviado_em)
                  from public.contrato_documentos d where d.contrato_id = c.id), '[]'::jsonb),
    'historico', coalesce((select jsonb_agg(jsonb_build_object('em', h.em, 'acao', h.acao, 'detalhes', h.detalhes, 'ator', app.nome_usuario(h.ator_id)) order by h.em desc)
                  from (select * from public.contrato_historico where contrato_id = c.id order by em desc limit 100) h), '[]'::jsonb),
    'renovacao', (select jsonb_build_object('demanda_id', d.id, 'numero', d.numero, 'status', d.status) from public.demandas d
                   where d.contrato_id = c.id order by d.criado_em desc limit 1),
    'pendentes', (select count(*) from public.solicitacoes s where s.alvo_id = c.id and s.status = 'pendente' and s.tipo in ('contrato_alterar', 'contrato_aditivo'))
  ) into v;
  return v;
end $$;

-- lista de contratos
create or replace function public.listar_contratos()
returns table (id uuid, numero text, locador text, imovel text, unidade text, fim_vigencia date, dias_restantes integer, valor_mensal numeric,
               fiscal text, encerrado boolean, alugueis_atrasados integer, aditivos integer)
language sql stable security definer set search_path = ''
as $$
  select c.id, c.numero, l.nome, c.imovel_descricao, u.sigla, c.fim_vigencia, c.fim_vigencia - current_date, c.valor_mensal, s.nome_completo, c.encerrado,
         (select count(*) from public.alugueis a where a.contrato_id = c.id and a.pago_em is null and a.vencimento < current_date)::int,
         (select count(*) from public.aditivos a where a.contrato_id = c.id)::int
    from public.contratos c join public.locadores l on l.id = c.locador_id
    left join public.unidades u on u.id = c.unidade_ocupante_id left join public.servidores s on s.id = c.fiscal_servidor_id
   where app.acesso_contratos()
   order by c.encerrado, c.fim_vigencia
$$;

-- painel da secretária: KPIs de contratos (só para quem tem o módulo)
create or replace function public.painel_contratos()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select case when not app.acesso_contratos() then null else jsonb_build_object(
    'vencendo', (select count(*) from public.contratos where not encerrado and fim_vigencia between current_date and current_date
                   + coalesce((select (valor)::int from public.configuracoes where chave = 'contratos.dias_renovacao'), 90)),
    'vencendo_30', (select count(*) from public.contratos where not encerrado and fim_vigencia between current_date and current_date + 30),
    'vencidos', (select count(*) from public.contratos where not encerrado and fim_vigencia < current_date),
    'alugueis_pendentes', (select count(*) from public.alugueis a join public.contratos c on c.id = a.contrato_id
                             where not c.encerrado and a.pago_em is null and a.vencimento <= current_date),
    'alugueis_pendentes_valor', (select coalesce(sum(a.valor), 0) from public.alugueis a join public.contratos c on c.id = a.contrato_id
                             where not c.encerrado and a.pago_em is null and a.vencimento <= current_date),
    'proximos', coalesce((select jsonb_agg(x order by x.fim_vigencia) from (
                   select c.id, c.numero, c.imovel_descricao, c.fim_vigencia, c.fim_vigencia - current_date as dias
                     from public.contratos c where not c.encerrado and c.fim_vigencia >= current_date order by c.fim_vigencia limit 5) x), '[]'::jsonb)
  ) end
$$;

-- ===== busca geral: + contratos (número, processo, imóvel, locador) =====
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
    (select 'contrato'::text, c.id, 'Contrato nº ' || c.numero, c.imovel_descricao || ' · ' || l.nome, '/contratos/ficha?id=' || c.id
       from public.contratos c join public.locadores l on l.id = c.locador_id
      where app.normalizar(c.numero) like q or app.normalizar(coalesce(c.processo, '')) like q
         or app.normalizar(c.imovel_descricao) like q or app.normalizar(l.nome) like q
      order by c.fim_vigencia limit lim)
    union all
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

update public.modulos set status = 'ativo' where codigo in ('contratos', 'unidades_consumidoras');

grant execute on function public.contrato_ficha(uuid) to authenticated;
grant execute on function public.listar_contratos() to authenticated;
grant execute on function public.painel_contratos() to authenticated;
grant execute on function public.busca_geral(text, integer) to authenticated;
