-- Fase 5 · Produtividade (Adendo 01) · regras versionadas, cadastro e designações
-- Minuta de decreto: todo número fica em prod_regras (versionada por início de vigência).

update public.modulos set status = 'ativo' where codigo = 'produtividade';
-- permissão produtividade.institucional.gerir (adendo 4.3.4): só como módulo extra
insert into public.modulos (codigo, nome, rota, icone, ordem, status, fase, no_menu)
values ('prod_institucional', 'Produtividade · metas e arrecadação', '/produtividade', 'grafico', 150, 'ativo', 5, false)
on conflict (codigo) do nothing;

-- ===== cadastro: entrada/saída na SEMFAZ (dias elegíveis) e chefia designada =====
alter table public.servidores
  add column data_entrada_semfaz date,
  add column data_saida_semfaz date,
  add column chefia_designada_id uuid references public.servidores (id),
  add constraint servidores_datas_semfaz check (data_saida_semfaz is null or data_entrada_semfaz is null or data_saida_semfaz >= data_entrada_semfaz),
  add constraint servidores_chefia_designada_propria check (chefia_designada_id is distinct from id);

create or replace function app.campos_permitidos(t public.tipo_solicitacao)
returns text[] language sql immutable set search_path = ''
as $$
  select case t
    when 'unidade_criar' then array['sigla', 'nome', 'tipo', 'unidade_pai_id', 'ordem']
    when 'unidade_alterar' then array['sigla', 'nome', 'unidade_pai_id', 'ordem', 'ativa']
    when 'cargo_criar' then array['nome', 'carreira_excluida']
    when 'cargo_alterar' then array['nome', 'ativo', 'carreira_excluida']
    when 'servidor_alterar' then array['nome_completo', 'matricula', 'cargo_id', 'unidade_id', 'situacao', 'email_institucional', 'tipo_vinculo', 'exerce_comissao',
                                       'data_entrada_semfaz', 'data_saida_semfaz']
    when 'usuario_perfil' then array['perfil']
    when 'acesso_unidade_conceder' then array['unidade_id']
    when 'acesso_unidade_retirar' then array['unidade_id']
    when 'feriado_alterar' then array['data', 'descricao', 'abrangencia']
    else array[]::text[]
  end
$$;

-- chefia substituta/designada (adendo 3.2.1): Secretária ou Administrador, direto e auditado
create or replace function public.prod_definir_chefia_designada(p_servidor uuid, p_chefia uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if p_chefia is not null and not exists (select 1 from public.servidores where id = p_chefia and situacao = 'ativo') then
    perform app.erro('Chefia inexistente ou inativa.', '22023');
  end if;
  update public.servidores set chefia_designada_id = p_chefia where id = p_servidor;
  if not found then perform app.erro('Servidor não encontrado.', 'P0002'); end if;
exception when check_violation then perform app.erro('O servidor não pode ser a própria chefia.', '23514');
end $$;

-- chefe de uma unidade: gabinete → secretária; diretoria → diretor; demais → coordenador/chefe
create or replace function app.chefe_da_unidade(p_unidade uuid)
returns uuid language sql stable security definer set search_path = ''
as $$
  select s.id from public.usuarios u join public.servidores s on s.id = u.servidor_id join public.unidades un on un.id = p_unidade
   where u.ativo and s.situacao = 'ativo'
     and ((un.tipo = 'gabinete' and u.perfil = 'secretaria')
          or (un.tipo = 'diretoria' and u.perfil = 'diretor' and s.unidade_id = p_unidade)
          or (un.tipo not in ('gabinete', 'diretoria') and u.perfil = 'coordenador' and s.unidade_id = p_unidade))
   order by s.nome_completo limit 1
$$;

-- chefia imediata (adendo 3.2.1): designada > chefe da unidade > (se é o chefe) chefe da unidade superior
create or replace function app.chefia_imediata(p_servidor uuid)
returns uuid language plpgsql stable security definer set search_path = ''
as $$
declare s public.servidores; v_un uuid; v_chefe uuid; i integer := 0;
begin
  select * into s from public.servidores where id = p_servidor;
  if s.chefia_designada_id is not null then return s.chefia_designada_id; end if;
  v_un := s.unidade_id;
  while v_un is not null and i < 10 loop
    v_chefe := app.chefe_da_unidade(v_un);
    if v_chefe is not null and v_chefe <> p_servidor then return v_chefe; end if;
    select unidade_pai_id into v_un from public.unidades where id = v_un;
    i := i + 1;
  end loop;
  return null;  -- topo (Secretária): sem chefia; designar se for elegível
end $$;

-- ===== regras versionadas (adendo 5.6) =====
create table public.prod_regras (
  id uuid primary key default gen_random_uuid(),
  versao integer generated always as identity unique,
  inicio_vigencia date not null unique,
  indicadores jsonb not null,             -- [{codigo, nome, maximo}]
  receitas jsonb not null,                -- [{codigo, nome, peso}]  (peso em fração: 0.25)
  max_funcional numeric(6,2) not null,
  max_institucional numeric(6,2) not null,
  minimo_funcional numeric(6,2) not null,
  minimo_total integer not null,
  faixas jsonb not null,                  -- [{de, ate, percentual}]
  percentual_maximo numeric(5,2) not null default 30 check (percentual_maximo > 0 and percentual_maximo <= 30),
  prazos jsonb not null,                  -- dias úteis: ciencia, recurso, revisao, alerta_revisao; dias corridos: alerta_rascunho
  afastamentos_exercicio jsonb not null,  -- {ferias: true, ...}; tipo ausente = não conta
  regra_institucional text not null default 'ultimo_homologado' check (regra_institucional in ('ultimo_homologado')),
  observacao text check (observacao is null or length(observacao) <= 2000),
  criado_por uuid references public.usuarios (id),
  criado_em timestamptz not null default now()
);

create or replace function app.validar_regras()
returns trigger language plpgsql set search_path = ''
as $$
declare v_soma numeric; v_ant numeric := -1; f jsonb;
begin
  if jsonb_typeof(new.indicadores) <> 'array' or jsonb_array_length(new.indicadores) = 0
     or exists (select 1 from jsonb_array_elements(new.indicadores) x where coalesce(x ->> 'codigo', '') = '' or coalesce(x ->> 'nome', '') = '' or coalesce((x ->> 'maximo')::numeric, 0) <= 0) then
    raise exception using message = 'Indicadores inválidos (código, nome e máximo > 0).', errcode = '23514';
  end if;
  select sum((x ->> 'maximo')::numeric) into v_soma from jsonb_array_elements(new.indicadores) x;
  if v_soma <> new.max_funcional then raise exception using message = 'A soma dos máximos dos indicadores deve ser igual ao máximo funcional.', errcode = '23514'; end if;
  if jsonb_typeof(new.receitas) <> 'array' or jsonb_array_length(new.receitas) = 0
     or exists (select 1 from jsonb_array_elements(new.receitas) x where coalesce(x ->> 'codigo', '') = '' or coalesce((x ->> 'peso')::numeric, 0) <= 0) then
    raise exception using message = 'Receitas inválidas (código e peso > 0).', errcode = '23514';
  end if;
  select sum((x ->> 'peso')::numeric) into v_soma from jsonb_array_elements(new.receitas) x;
  if v_soma <> 1 then raise exception using message = 'A soma dos pesos das receitas deve ser 100%.', errcode = '23514'; end if;
  if new.max_funcional + new.max_institucional <> 100 then raise exception using message = 'Máximo funcional + institucional deve ser 100.', errcode = '23514'; end if;
  if new.minimo_funcional < 0 or new.minimo_funcional > new.max_funcional or new.minimo_total < 0 or new.minimo_total > 100 then
    raise exception using message = 'Mínimos inválidos.', errcode = '23514';
  end if;
  for f in select x from jsonb_array_elements(new.faixas) x order by (x ->> 'de')::numeric loop
    if (f ->> 'de')::numeric > (f ->> 'ate')::numeric or (f ->> 'de')::numeric <= v_ant
       or (f ->> 'percentual')::numeric <= 0 or (f ->> 'percentual')::numeric > new.percentual_maximo then
      raise exception using message = 'Faixas inválidas (sem sobreposição; percentual até o máximo).', errcode = '23514';
    end if;
    v_ant := (f ->> 'ate')::numeric;
  end loop;
  return new;
end $$;
create trigger prod_regras_validar before insert on public.prod_regras for each row execute function app.validar_regras();
-- versão nunca muda: mudar regra = nova versão
create trigger prod_regras_imutavel before update or delete on public.prod_regras for each row execute function app.auditoria_imutavel();

insert into public.prod_regras (inicio_vigencia, indicadores, receitas, max_funcional, max_institucional, minimo_funcional, minimo_total, faixas, prazos, afastamentos_exercicio, observacao)
values ('2026-01-01',
  '[{"codigo":"F1","nome":"Qualidade e eficiência na execução das atividades","maximo":20},
    {"codigo":"F2","nome":"Cumprimento de prazos e metas de trabalho","maximo":15},
    {"codigo":"F3","nome":"Produtividade e entregas realizadas","maximo":15},
    {"codigo":"F4","nome":"Qualidade do atendimento ao contribuinte e ao público interno","maximo":10},
    {"codigo":"F5","nome":"Organização, responsabilidade e cooperação institucional","maximo":10}]',
  '[{"codigo":"R1","nome":"IPTU","peso":0.25},{"codigo":"R2","nome":"ISSQN","peso":0.30},{"codigo":"R3","nome":"ITBI","peso":0.10},
    {"codigo":"R4","nome":"Taxas (poder de polícia e serviços)","peso":0.10},{"codigo":"R5","nome":"Dívida ativa (recuperação de créditos)","peso":0.25}]',
  70, 30, 42, 60,
  '[{"de":60,"ate":69,"percentual":12},{"de":70,"ate":79,"percentual":18},{"de":80,"ate":89,"percentual":24},{"de":90,"ate":100,"percentual":30}]',
  '{"ciencia":3,"recurso":5,"revisao":10,"alerta_revisao":8,"alerta_rascunho":3}',
  '{"ferias":true,"licenca_premio":true,"folga":true}',
  'Valores iniciais da minuta do decreto (Adendo 01). Pendente texto final.');

create or replace function app.regra_vigente(p_data date)
returns uuid language sql stable security definer set search_path = ''
as $$ select id from public.prod_regras where inicio_vigencia <= p_data order by inicio_vigencia desc limit 1 $$;

create or replace function public.prod_criar_regra(p_dados jsonb)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if (p_dados ->> 'inicio_vigencia')::date < current_date then perform app.erro('A nova versão só vale de hoje em diante.', '22023'); end if;
  insert into public.prod_regras (inicio_vigencia, indicadores, receitas, max_funcional, max_institucional, minimo_funcional, minimo_total, faixas,
                                  percentual_maximo, prazos, afastamentos_exercicio, observacao, criado_por)
  values ((p_dados ->> 'inicio_vigencia')::date, p_dados -> 'indicadores', p_dados -> 'receitas', (p_dados ->> 'max_funcional')::numeric,
          (p_dados ->> 'max_institucional')::numeric, (p_dados ->> 'minimo_funcional')::numeric, (p_dados ->> 'minimo_total')::int, p_dados -> 'faixas',
          coalesce((p_dados ->> 'percentual_maximo')::numeric, 30), p_dados -> 'prazos', p_dados -> 'afastamentos_exercicio', p_dados ->> 'observacao', auth.uid())
  returning id into v_id;
  return v_id;
exception
  when unique_violation then perform app.erro('Já existe versão com esse início de vigência.', '23505');
  when not_null_violation or invalid_text_representation or invalid_datetime_format then perform app.erro('Dados da regra incompletos ou inválidos.', '22023');
end $$;

-- ===== designações: autoridade revisora e instância de homologação (adendo 6.8) =====
create table public.prod_designacoes (
  id uuid primary key default gen_random_uuid(),
  papel text not null check (papel in ('revisora', 'homologacao')),
  usuario_id uuid not null references public.usuarios (id),
  inicio date not null default current_date,
  fim date,
  ato text check (ato is null or length(ato) <= 300),
  criado_por uuid references public.usuarios (id),
  criado_em timestamptz not null default now(),
  constraint prod_designacoes_periodo check (fim is null or fim >= inicio)
);

create or replace function app.tem_designacao(p_papel text, p_usuario uuid default null, p_data date default current_date)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.prod_designacoes d join public.usuarios u on u.id = d.usuario_id
                  where d.papel = p_papel and d.usuario_id = coalesce(p_usuario, auth.uid()) and u.ativo
                    and d.inicio <= p_data and (d.fim is null or d.fim >= p_data))
$$;
grant execute on function app.tem_designacao(text, uuid, date) to authenticated;

create or replace function public.prod_designar(p_papel text, p_usuario uuid, p_inicio date default current_date, p_ato text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  insert into public.prod_designacoes (papel, usuario_id, inicio, ato, criado_por) values (p_papel, p_usuario, coalesce(p_inicio, current_date), p_ato, auth.uid())
  returning id into v_id;
  return v_id;
exception when check_violation or foreign_key_violation then perform app.erro('Designação inválida.', '22023');
end $$;

create or replace function public.prod_encerrar_designacao(p_id uuid, p_fim date default current_date)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  update public.prod_designacoes set fim = coalesce(p_fim, current_date) where id = p_id and fim is null;
  if not found then perform app.erro('Designação não encontrada ou já encerrada.', 'P0002'); end if;
exception when check_violation then perform app.erro('Data de fim antes do início.', '22023');
end $$;

-- ===== valor em R$ (adendo 5.5): desligado; vencimento básico só se ligado, acesso restrito =====
insert into public.configuracoes (chave, valor, descricao) values
  ('produtividade.calcular_valor', 'false', 'Calcular valor em R$ do adicional (pendente de decisão da SEMFAZ; padrão: não)')
on conflict (chave) do nothing;
create table public.prod_vencimentos (
  servidor_id uuid not null references public.servidores (id),
  competencia date not null check (extract(day from competencia) = 1),
  vencimento_basico numeric(12,2) not null check (vencimento_basico > 0),
  informado_por uuid references public.usuarios (id),
  informado_em timestamptz not null default now(),
  primary key (servidor_id, competencia)
);

do $$
declare t text;
begin
  foreach t in array array['prod_regras', 'prod_designacoes', 'prod_vencimentos'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()', t || '_auditoria', t);
  end loop;
end $$;
create policy prod_regras_ler on public.prod_regras for select to authenticated using ((select app.sessao_ok()) and (select app.tem_modulo('produtividade')));
create policy prod_designacoes_ler on public.prod_designacoes for select to authenticated using ((select app.sessao_ok()) and (select app.tem_modulo('produtividade')));
create policy prod_vencimentos_ler on public.prod_vencimentos for select to authenticated using ((select app.gestor_geral()));

grant execute on function public.prod_definir_chefia_designada(uuid, uuid) to authenticated;
grant execute on function public.prod_criar_regra(jsonb) to authenticated;
grant execute on function public.prod_designar(text, uuid, date, text) to authenticated;
grant execute on function public.prod_encerrar_designacao(uuid, date) to authenticated;
