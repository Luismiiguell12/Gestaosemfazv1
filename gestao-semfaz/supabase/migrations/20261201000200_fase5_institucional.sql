-- Fase 5 · desempenho institucional (quadrimestral, até 30 pontos) — adendo seção 4

create or replace function app.inicio_quadrimestre(p_ano integer, p_q integer)
returns date language sql immutable set search_path = ''
as $$ select make_date(p_ano, (p_q - 1) * 4 + 1, 1) $$;
create or replace function app.fim_quadrimestre(p_ano integer, p_q integer)
returns date language sql immutable set search_path = ''
as $$ select (make_date(p_ano, (p_q - 1) * 4 + 1, 1) + interval '4 months' - interval '1 day')::date $$;

-- permissão produtividade.institucional.gerir: módulo extra "prod_institucional" (Secretária/Admin sempre)
create or replace function app.gere_institucional()
returns boolean language sql stable security definer set search_path = ''
as $$ select app.sessao_ok() and (app.gestor_geral() or app.tem_modulo('prod_institucional')) $$;
grant execute on function app.gere_institucional() to authenticated;

create table public.prod_metas (
  id uuid primary key default gen_random_uuid(),
  ano integer not null check (ano between 2020 and 2100),
  quadrimestre integer not null check (quadrimestre between 1 and 3),
  receita text not null check (receita ~ '^R[0-9]{1,2}$'),
  valor numeric(16,2) not null check (valor > 0),
  memoria text not null check (length(btrim(memoria)) between 5 and 4000),
  fonte text not null check (length(btrim(fonte)) between 3 and 500),
  anexo_path text,
  retificacao boolean not null default false,
  justificativa text,
  vale_para_ciclo boolean not null default true,
  criado_por uuid references public.usuarios (id),
  criado_em timestamptz not null default now(),
  constraint prod_metas_retificacao check (not retificacao or length(btrim(coalesce(justificativa, ''))) >= 10)
);
create unique index prod_metas_uk on public.prod_metas (ano, quadrimestre, receita) where not retificacao;

-- meta publicada antes do início; depois que o quadrimestre começa fica TRAVADA (inclusive para o Administrador).
-- retificação depois do início é só registro: não vale para o ciclo já iniciado (art. 11 § 2º e art. 24).
create or replace function app.travar_meta()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') and current_date >= app.inicio_quadrimestre(old.ano, old.quadrimestre) then
    raise exception using message = 'Meta travada: o quadrimestre já começou. Use retificação (não vale para este ciclo).', errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  if current_date >= app.inicio_quadrimestre(new.ano, new.quadrimestre) then
    if not new.retificacao then
      raise exception using message = 'Meta deve ser publicada antes do início do quadrimestre. Depois, só retificação.', errcode = '42501';
    end if;
    new.vale_para_ciclo := false;
  end if;
  return new;
end $$;
create trigger prod_metas_travar before insert or update or delete on public.prod_metas for each row execute function app.travar_meta();

create table public.prod_arrecadacao (
  id uuid primary key default gen_random_uuid(),
  ano integer not null check (ano between 2020 and 2100),
  quadrimestre integer not null check (quadrimestre between 1 and 3),
  receita text not null check (receita ~ '^R[0-9]{1,2}$'),
  valor numeric(16,2) not null check (valor >= 0),
  fonte text not null check (length(btrim(fonte)) between 3 and 500),
  anexo_path text,
  origem text not null default 'manual' check (origem in ('manual', 'importacao')),
  criado_por uuid references public.usuarios (id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (ano, quadrimestre, receita)
);

create table public.prod_resultados_inst (
  id uuid primary key default gen_random_uuid(),
  ano integer not null,
  quadrimestre integer not null,
  regra_id uuid not null references public.prod_regras (id),
  pontos numeric(8,4) not null check (pontos between 0 and 100),
  memoria jsonb not null,
  status text not null default 'apurado' check (status in ('apurado', 'homologado')),
  apurado_por uuid references public.usuarios (id),
  apurado_em timestamptz not null default now(),
  homologado_por uuid references public.usuarios (id),
  homologado_em timestamptz,
  unique (ano, quadrimestre),
  constraint prod_resultado_segregacao check (homologado_por is null or homologado_por is distinct from apurado_por)
);
-- homologado = imutável; arrecadação do quadrimestre homologado também
create or replace function app.resultado_inst_imutavel()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if old.status = 'homologado' then raise exception using message = 'Resultado institucional homologado não pode ser alterado.', errcode = '42501'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
create trigger prod_resultados_inst_imutavel before update or delete on public.prod_resultados_inst for each row execute function app.resultado_inst_imutavel();
create or replace function app.arrecadacao_travada()
returns trigger language plpgsql set search_path = ''
as $$
declare r record := case when tg_op = 'DELETE' then old else new end;
begin
  if exists (select 1 from public.prod_resultados_inst x where x.ano = r.ano and x.quadrimestre = r.quadrimestre and x.status = 'homologado')
     or (tg_op <> 'INSERT' and exists (select 1 from public.prod_resultados_inst x where x.ano = old.ano and x.quadrimestre = old.quadrimestre and x.status = 'homologado')) then
    raise exception using message = 'Quadrimestre já homologado: arrecadação travada.', errcode = '42501';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
create trigger prod_arrecadacao_travar before insert or update or delete on public.prod_arrecadacao for each row execute function app.arrecadacao_travada();

do $$
declare t text;
begin
  foreach t in array array['prod_metas', 'prod_arrecadacao', 'prod_resultados_inst'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()', t || '_auditoria', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select app.sessao_ok()) and ((select app.tem_modulo(''produtividade'')) or (select app.gere_institucional())))', t || '_ler', t);
  end loop;
end $$;

-- ===== lançamentos (RPC) =====
create or replace function app.receita_valida(p_receita text, p_data date)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.prod_regras r, jsonb_array_elements(r.receitas) x where r.id = app.regra_vigente(p_data) and x ->> 'codigo' = p_receita) $$;

create or replace function public.prod_salvar_meta(p_ano integer, p_quadrimestre integer, p_receita text, p_valor numeric, p_memoria text, p_fonte text,
                                                   p_anexo text default null, p_justificativa_retificacao text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_inicio date := app.inicio_quadrimestre(p_ano, p_quadrimestre);
begin
  if not app.gere_institucional() then perform app.erro('Sem permissão para metas e arrecadação.', '42501'); end if;
  if not app.receita_valida(p_receita, v_inicio) then perform app.erro('Receita inválida para a regra vigente.', '22023'); end if;
  if p_justificativa_retificacao is not null then
    insert into public.prod_metas (ano, quadrimestre, receita, valor, memoria, fonte, anexo_path, retificacao, justificativa, criado_por)
    values (p_ano, p_quadrimestre, p_receita, p_valor, p_memoria, p_fonte, p_anexo, true, p_justificativa_retificacao, auth.uid()) returning id into v_id;
  else
    insert into public.prod_metas (ano, quadrimestre, receita, valor, memoria, fonte, anexo_path, criado_por)
    values (p_ano, p_quadrimestre, p_receita, p_valor, p_memoria, p_fonte, p_anexo, auth.uid())
    on conflict (ano, quadrimestre, receita) where not retificacao
    do update set valor = excluded.valor, memoria = excluded.memoria, fonte = excluded.fonte, anexo_path = excluded.anexo_path, criado_por = excluded.criado_por, criado_em = now()
    returning id into v_id;
  end if;
  return v_id;
exception when check_violation then perform app.erro('Dados da meta inválidos (valor > 0, memória de cálculo e fonte obrigatórias).', '23514');
end $$;

create or replace function public.prod_salvar_arrecadacao(p_ano integer, p_quadrimestre integer, p_receita text, p_valor numeric, p_fonte text, p_anexo text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not app.gere_institucional() then perform app.erro('Sem permissão para metas e arrecadação.', '42501'); end if;
  if not app.receita_valida(p_receita, app.inicio_quadrimestre(p_ano, p_quadrimestre)) then perform app.erro('Receita inválida para a regra vigente.', '22023'); end if;
  insert into public.prod_arrecadacao (ano, quadrimestre, receita, valor, fonte, anexo_path, criado_por)
  values (p_ano, p_quadrimestre, p_receita, p_valor, p_fonte, p_anexo, auth.uid())
  on conflict (ano, quadrimestre, receita) do update set valor = excluded.valor, fonte = excluded.fonte, anexo_path = excluded.anexo_path,
    criado_por = excluded.criado_por, atualizado_em = now()
  returning id into v_id;
  -- resultado ainda não homologado precisa ser apurado de novo
  delete from public.prod_resultados_inst where ano = p_ano and quadrimestre = p_quadrimestre and status = 'apurado';
  return v_id;
exception when check_violation then perform app.erro('Dados da arrecadação inválidos (valor ≥ 0 e fonte obrigatória).', '23514');
end $$;

-- importação: colunas ano, quadrimestre, receita (código R1..R5), valor, fonte. Prévia → tudo ou nada.
create or replace function app.validar_planilha_arrecadacao(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
declare r jsonb; n integer; v_ano integer; v_q integer;
begin
  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then perform app.erro('Planilha sem linhas.', '22023'); end if;
  if jsonb_array_length(p_linhas) > 500 then perform app.erro('Máximo de 500 linhas.', '22023'); end if;
  for r in select * from jsonb_array_elements(p_linhas) loop
    n := coalesce((r ->> 'linha')::int, 0);
    v_ano := case when btrim(coalesce(r ->> 'ano', '')) ~ '^\d{4}$' then (r ->> 'ano')::int end;
    v_q := case when btrim(coalesce(r ->> 'quadrimestre', '')) ~ '^[1-3]$' then (r ->> 'quadrimestre')::int end;
    if v_ano is null then return query select n, 'ano', 'Ano inválido (aaaa).'; end if;
    if v_q is null then return query select n, 'quadrimestre', 'Quadrimestre deve ser 1, 2 ou 3.'; end if;
    if v_ano is not null and v_q is not null and not app.receita_valida(upper(btrim(coalesce(r ->> 'receita', ''))), app.inicio_quadrimestre(v_ano, v_q)) then
      return query select n, 'receita', 'Receita inválida (use o código: R1 a R5).';
    elsif v_ano is not null and v_q is not null and exists (select 1 from public.prod_resultados_inst x where x.ano = v_ano and x.quadrimestre = v_q and x.status = 'homologado') then
      return query select n, 'quadrimestre', 'Quadrimestre já homologado.';
    elsif (select count(*) from jsonb_array_elements(p_linhas) x where btrim(x ->> 'ano') = btrim(r ->> 'ano') and btrim(x ->> 'quadrimestre') = btrim(r ->> 'quadrimestre')
             and upper(btrim(x ->> 'receita')) = upper(btrim(r ->> 'receita'))) > 1 then
      return query select n, 'receita', 'Receita repetida na planilha.';
    end if;
    if app.valor_planilha(r ->> 'valor') is null then return query select n, 'valor', 'Valor inválido.'; end if;
    if length(btrim(coalesce(r ->> 'fonte', ''))) < 3 then return query select n, 'fonte', 'Informe a fonte (relatório contábil oficial).'; end if;
  end loop;
end $$;

create or replace function public.prod_importar_arrecadacao_previa(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not app.gere_institucional() then perform app.erro('Sem permissão para metas e arrecadação.', '42501'); end if;
  return query select * from app.validar_planilha_arrecadacao(p_linhas) order by 1, 2;
end $$;

create or replace function public.prod_importar_arrecadacao(p_linhas jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare r jsonb; n integer := 0;
begin
  if not app.gere_institucional() then perform app.erro('Sem permissão para metas e arrecadação.', '42501'); end if;
  if exists (select 1 from app.validar_planilha_arrecadacao(p_linhas)) then perform app.erro('A planilha tem erros. Corrija e confira a prévia antes de importar.', '22023'); end if;
  perform set_config('app.origem', 'importacao_arrecadacao', true);
  for r in select * from jsonb_array_elements(p_linhas) loop
    perform public.prod_salvar_arrecadacao((r ->> 'ano')::int, (r ->> 'quadrimestre')::int, upper(btrim(r ->> 'receita')), app.valor_planilha(r ->> 'valor'), btrim(r ->> 'fonte'));
    update public.prod_arrecadacao set origem = 'importacao' where ano = (r ->> 'ano')::int and quadrimestre = (r ->> 'quadrimestre')::int and receita = upper(btrim(r ->> 'receita'));
    n := n + 1;
  end loop;
  return n;
end $$;

-- ===== apuração (adendo 4.2): numeric, índice ≤ 1, memória completa; meta 0/ausente = erro claro =====
create or replace function app.calcular_institucional(p_ano integer, p_q integer, p_regra uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare r public.prod_regras; x jsonb; v_meta numeric; v_arr numeric; v_ind numeric; v_soma numeric := 0; v_mem jsonb := '[]'::jsonb;
begin
  select * into r from public.prod_regras where id = p_regra;
  for x in select * from jsonb_array_elements(r.receitas) loop
    select m.valor into v_meta from public.prod_metas m
     where m.ano = p_ano and m.quadrimestre = p_q and m.receita = x ->> 'codigo' and not m.retificacao and m.vale_para_ciclo;
    if coalesce(v_meta, 0) <= 0 then
      perform app.erro(format('Quadrimestre %s/%s não pode ser apurado: meta ausente ou zero para %s.', p_q, p_ano, x ->> 'nome'), '22023');
    end if;
    select a.valor into v_arr from public.prod_arrecadacao a where a.ano = p_ano and a.quadrimestre = p_q and a.receita = x ->> 'codigo';
    if v_arr is null then perform app.erro(format('Quadrimestre %s/%s não pode ser apurado: falta a arrecadação de %s.', p_q, p_ano, x ->> 'nome'), '22023'); end if;
    v_ind := least(1::numeric, v_arr / v_meta);
    v_soma := v_soma + v_ind * (x ->> 'peso')::numeric;
    v_mem := v_mem || jsonb_build_object('receita', x ->> 'codigo', 'nome', x ->> 'nome', 'meta', v_meta, 'arrecadado', v_arr,
                                         'indice', round(v_ind, 4), 'peso', (x ->> 'peso')::numeric, 'contribuicao', round(v_ind * (x ->> 'peso')::numeric, 4));
  end loop;
  return jsonb_build_object('pontos', round(least(r.max_institucional, v_soma * r.max_institucional), 4), 'soma_contribuicoes', round(v_soma, 4),
                            'max_institucional', r.max_institucional, 'receitas', v_mem, 'regra_versao', r.versao);
end $$;

create or replace function public.prod_apurar_institucional(p_ano integer, p_quadrimestre integer)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_regra uuid := app.regra_vigente(app.inicio_quadrimestre(p_ano, p_quadrimestre)); v jsonb;
begin
  if not app.gere_institucional() then perform app.erro('Sem permissão para metas e arrecadação.', '42501'); end if;
  if current_date <= app.fim_quadrimestre(p_ano, p_quadrimestre) then perform app.erro('O quadrimestre ainda não terminou.', '22023'); end if;
  if exists (select 1 from public.prod_resultados_inst where ano = p_ano and quadrimestre = p_quadrimestre and status = 'homologado') then
    perform app.erro('Quadrimestre já homologado.', '22023');
  end if;
  v := app.calcular_institucional(p_ano, p_quadrimestre, v_regra);
  delete from public.prod_resultados_inst where ano = p_ano and quadrimestre = p_quadrimestre and status = 'apurado';
  insert into public.prod_resultados_inst (ano, quadrimestre, regra_id, pontos, memoria, apurado_por)
  values (p_ano, p_quadrimestre, v_regra, (v ->> 'pontos')::numeric, v, auth.uid());
  return v;
end $$;

create or replace function public.prod_homologar_institucional(p_ano integer, p_quadrimestre integer)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not (app.sessao_ok() and app.tem_designacao('homologacao')) then perform app.erro('Somente a instância de homologação designada.', '42501'); end if;
  update public.prod_resultados_inst set status = 'homologado', homologado_por = auth.uid(), homologado_em = now()
   where ano = p_ano and quadrimestre = p_quadrimestre and status = 'apurado';
  if not found then perform app.erro('Resultado não apurado ou já homologado.', 'P0002'); end if;
exception when check_violation then perform app.erro('Quem apurou não pode homologar o mesmo resultado.', '42501');
end $$;

grant execute on function public.prod_salvar_meta(integer, integer, text, numeric, text, text, text, text) to authenticated;
grant execute on function public.prod_salvar_arrecadacao(integer, integer, text, numeric, text, text) to authenticated;
grant execute on function public.prod_importar_arrecadacao_previa(jsonb) to authenticated;
grant execute on function public.prod_importar_arrecadacao(jsonb) to authenticated;
grant execute on function public.prod_apurar_institucional(integer, integer) to authenticated;
grant execute on function public.prod_homologar_institucional(integer, integer) to authenticated;
