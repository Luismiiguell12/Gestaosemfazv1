-- Fase 4 · unidades consumidoras e faturas de água/energia (6.6)
-- Sem anexo de fatura/comprovante. Pagamento sem aprovação.

create or replace function app.acesso_ucs()
returns boolean language sql stable security definer set search_path = ''
as $$ select app.sessao_ok() and (app.tem_modulo('contratos') or app.tem_modulo('unidades_consumidoras')) $$;
grant execute on function app.acesso_ucs() to authenticated;

create table public.unidades_consumidoras (
  id uuid primary key default gen_random_uuid(),
  fornecedor public.fornecedor_uc not null,
  numero text not null check (btrim(numero) ~ '^[0-9A-Za-z./-]{3,30}$'),
  contrato_id uuid not null references public.contratos (id),
  descricao text check (descricao is null or length(descricao) <= 120),
  ativa boolean not null default true,
  criado_em timestamptz not null default now(),
  unique (fornecedor, numero)
);

create table public.faturas (
  id uuid primary key default gen_random_uuid(),
  uc_id uuid not null references public.unidades_consumidoras (id),
  competencia date not null check (extract(day from competencia) = 1),
  consumo numeric(12,2) check (consumo is null or consumo >= 0),
  valor numeric(12,2) not null check (valor > 0),
  vencimento date not null,
  pago_em date,
  registrado_por uuid references public.usuarios (id),
  origem text not null default 'manual' check (origem in ('manual', 'importacao')),
  criado_por uuid references public.usuarios (id),
  criado_em timestamptz not null default now(),
  unique (uc_id, competencia)
);
create index faturas_comp_idx on public.faturas (competencia);

do $$
declare t text;
begin
  foreach t in array array['unidades_consumidoras', 'faturas'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()', t || '_auditoria', t);
  end loop;
end $$;
create policy ucs_ler on public.unidades_consumidoras for select to authenticated using ((select app.acesso_ucs()));
create policy faturas_ler on public.faturas for select to authenticated using ((select app.acesso_ucs()));

create or replace function public.criar_uc(p_fornecedor public.fornecedor_uc, p_numero text, p_contrato uuid, p_descricao text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not app.acesso_contratos() then perform app.erro('Sem permissão para contratos.', '42501'); end if;
  insert into public.unidades_consumidoras (fornecedor, numero, contrato_id, descricao)
  values (p_fornecedor, btrim(p_numero), p_contrato, nullif(btrim(coalesce(p_descricao, '')), ''))
  returning id into v_id;
  perform app.historico_contrato(p_contrato, 'uc_vinculada', jsonb_build_object('fornecedor', p_fornecedor, 'numero', btrim(p_numero)));
  return v_id;
exception
  when unique_violation then perform app.erro('Unidade consumidora já cadastrada.', '23505');
  when check_violation then perform app.erro('Número da unidade consumidora inválido.', '23514');
  when foreign_key_violation then perform app.erro('Contrato não encontrado.', '23503');
end $$;

-- lançamento manual (registro novo); corrigir lançamento existente = só se ainda não pago
create or replace function public.lancar_fatura(p_uc uuid, p_competencia date, p_valor numeric, p_vencimento date, p_consumo numeric default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not app.acesso_ucs() then perform app.erro('Sem permissão para faturas.', '42501'); end if;
  insert into public.faturas (uc_id, competencia, consumo, valor, vencimento, criado_por)
  values (p_uc, date_trunc('month', p_competencia)::date, p_consumo, p_valor, p_vencimento, auth.uid())
  returning id into v_id;
  return v_id;
exception
  when unique_violation then perform app.erro('Já existe fatura dessa unidade consumidora nessa competência.', '23505');
  when check_violation or not_null_violation then perform app.erro('Dados da fatura inválidos.', '23514');
  when foreign_key_violation then perform app.erro('Unidade consumidora não encontrada.', '23503');
end $$;

create or replace function public.registrar_pagamento_fatura(p_id uuid, p_data date)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not app.acesso_ucs() then perform app.erro('Sem permissão para faturas.', '42501'); end if;
  if p_data is null or p_data > current_date then perform app.erro('Data de pagamento inválida.', '22023'); end if;
  update public.faturas set pago_em = p_data, registrado_por = auth.uid() where id = p_id and pago_em is null;
  if not found then perform app.erro('Fatura não encontrada ou já paga.', 'P0002'); end if;
end $$;

-- importação de faturas: prévia → tudo ou nada. Colunas provisórias (modelo oficial pendente, seção 9)
create or replace function app.validar_planilha_faturas(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
declare r jsonb; n integer; v_forn text; v_uc uuid; v_comp date;
begin
  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then perform app.erro('Planilha sem linhas.', '22023'); end if;
  if jsonb_array_length(p_linhas) > 3000 then perform app.erro('Máximo de 3000 faturas por importação.', '22023'); end if;
  for r in select * from jsonb_array_elements(p_linhas) loop
    n := coalesce((r ->> 'linha')::int, 0);
    v_forn := lower(btrim(coalesce(r ->> 'fornecedor', '')));
    v_forn := case v_forn when 'iguá' then 'igua' else v_forn end;
    v_uc := null;
    if v_forn not in ('energisa', 'igua', 'cercos') then return query select n, 'fornecedor', 'Fornecedor deve ser Energisa, Iguá ou Cercos.';
    else
      select u.id into v_uc from public.unidades_consumidoras u where u.fornecedor = v_forn::public.fornecedor_uc and u.numero = btrim(coalesce(r ->> 'uc', ''));
      if v_uc is null then return query select n, 'uc', 'Unidade consumidora não cadastrada.'; end if;
    end if;
    v_comp := case when btrim(coalesce(r ->> 'competencia', '')) ~ '^\d{1,2}/\d{4}$' then to_date('01/' || btrim(r ->> 'competencia'), 'DD/MM/YYYY') else null end;
    if v_comp is null then return query select n, 'competencia', 'Competência inválida (use mm/aaaa).';
    elsif v_uc is not null and exists (select 1 from public.faturas f where f.uc_id = v_uc and f.competencia = v_comp) then
      return query select n, 'competencia', 'Fatura dessa competência já lançada.';
    elsif (select count(*) from jsonb_array_elements(p_linhas) x where lower(btrim(x ->> 'fornecedor')) = lower(btrim(r ->> 'fornecedor'))
              and btrim(x ->> 'uc') = btrim(r ->> 'uc') and btrim(x ->> 'competencia') = btrim(r ->> 'competencia')) > 1 then
      return query select n, 'competencia', 'Fatura repetida na planilha.';
    end if;
    if app.valor_planilha(r ->> 'valor') is null or app.valor_planilha(r ->> 'valor') <= 0 then return query select n, 'valor', 'Valor inválido.'; end if;
    if nullif(btrim(coalesce(r ->> 'consumo', '')), '') is not null and app.valor_planilha(r ->> 'consumo') is null then return query select n, 'consumo', 'Consumo inválido.'; end if;
    if app.data_planilha(r ->> 'vencimento') is null then return query select n, 'vencimento', 'Vencimento inválido (use dd/mm/aaaa).'; end if;
    if nullif(btrim(coalesce(r ->> 'pago_em', '')), '') is not null and (app.data_planilha(r ->> 'pago_em') is null or app.data_planilha(r ->> 'pago_em') > current_date) then
      return query select n, 'pago_em', 'Data de pagamento inválida.';
    end if;
  end loop;
end $$;

create or replace function public.importar_faturas_previa(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not app.acesso_ucs() then perform app.erro('Sem permissão para faturas.', '42501'); end if;
  return query select * from app.validar_planilha_faturas(p_linhas) order by 1, 2;
end $$;

create or replace function public.importar_faturas(p_linhas jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare r jsonb; n integer := 0; v_forn text;
begin
  if not app.acesso_ucs() then perform app.erro('Sem permissão para faturas.', '42501'); end if;
  if exists (select 1 from app.validar_planilha_faturas(p_linhas)) then perform app.erro('A planilha tem erros. Corrija e confira a prévia antes de importar.', '22023'); end if;
  perform set_config('app.origem', 'importacao_faturas', true);
  for r in select * from jsonb_array_elements(p_linhas) loop
    v_forn := lower(btrim(r ->> 'fornecedor')); v_forn := case v_forn when 'iguá' then 'igua' else v_forn end;
    insert into public.faturas (uc_id, competencia, consumo, valor, vencimento, pago_em, registrado_por, origem, criado_por)
    select u.id, to_date('01/' || btrim(r ->> 'competencia'), 'DD/MM/YYYY'), app.valor_planilha(r ->> 'consumo'), app.valor_planilha(r ->> 'valor'),
           app.data_planilha(r ->> 'vencimento'), app.data_planilha(r ->> 'pago_em'),
           case when app.data_planilha(r ->> 'pago_em') is not null then auth.uid() end, 'importacao', auth.uid()
      from public.unidades_consumidoras u where u.fornecedor = v_forn::public.fornecedor_uc and u.numero = btrim(r ->> 'uc');
    n := n + 1;
  end loop;
  return n;
end $$;

-- tela de UCs: KPIs e lista da competência (protótipo UnidadesConsumidoras)
create or replace function public.ucs_competencia(p_competencia date, p_fornecedor public.fornecedor_uc default null)
returns table (uc_id uuid, fornecedor public.fornecedor_uc, numero text, descricao text, contrato_id uuid, contrato_numero text, imovel text,
               fatura_id uuid, consumo numeric, valor numeric, vencimento date, pago_em date, situacao text)
language plpgsql stable security definer set search_path = ''
as $$
declare v_comp date := date_trunc('month', coalesce(p_competencia, current_date))::date;
begin
  if not app.acesso_ucs() then perform app.erro('Sem permissão para faturas.', '42501'); end if;
  return query
    select u.id, u.fornecedor, u.numero, u.descricao, c.id, c.numero, c.imovel_descricao, f.id, f.consumo, f.valor, f.vencimento, f.pago_em,
           case when f.id is null then 'sem_lancamento' when f.pago_em is not null then 'paga'
                when f.vencimento < current_date then 'atrasada' else 'pendente' end
      from public.unidades_consumidoras u
      join public.contratos c on c.id = u.contrato_id
      left join public.faturas f on f.uc_id = u.id and f.competencia = v_comp
     where u.ativa and (p_fornecedor is null or u.fornecedor = p_fornecedor)
     order by u.fornecedor, c.numero, u.numero;
end $$;

grant execute on function public.criar_uc(public.fornecedor_uc, text, uuid, text) to authenticated;
grant execute on function public.lancar_fatura(uuid, date, numeric, date, numeric) to authenticated;
grant execute on function public.registrar_pagamento_fatura(uuid, date) to authenticated;
grant execute on function public.importar_faturas_previa(jsonb) to authenticated;
grant execute on function public.importar_faturas(jsonb) to authenticated;
grant execute on function public.ucs_competencia(date, public.fornecedor_uc) to authenticated;
