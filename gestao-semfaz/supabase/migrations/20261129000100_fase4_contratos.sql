-- Fase 4 · contratos de locação (6.5): ficha única, aditivos, documentos, aluguéis
-- Acesso por MÓDULO (não por unidade): quem a Secretária liberar (prompt 4).
-- LGPD: CPF e contato do locador mascarados; completo só com o módulo "locadores_dados".

create or replace function app.acesso_contratos()
returns boolean language sql stable security definer set search_path = ''
as $$ select app.sessao_ok() and app.tem_modulo('contratos') $$;
grant execute on function app.acesso_contratos() to authenticated;

-- ===== utilitários de planilha / documentos =====
create or replace function app.so_digitos(t text)
returns text language sql immutable set search_path = ''
as $$ select regexp_replace(coalesce(t, ''), '[^0-9]', '', 'g') $$;

create or replace function app.cpf_valido(c text)
returns boolean language plpgsql immutable set search_path = ''
as $$
declare d text := app.so_digitos(c); s integer; i integer; r integer;
begin
  if length(d) <> 11 or d ~ '^(.)\1{10}$' then return false; end if;
  s := 0; for i in 1..9 loop s := s + substr(d, i, 1)::int * (11 - i); end loop;
  r := (s * 10) % 11; if r = 10 then r := 0; end if;
  if r <> substr(d, 10, 1)::int then return false; end if;
  s := 0; for i in 1..10 loop s := s + substr(d, i, 1)::int * (12 - i); end loop;
  r := (s * 10) % 11; if r = 10 then r := 0; end if;
  return r = substr(d, 11, 1)::int;
end $$;

create or replace function app.cnpj_valido(c text)
returns boolean language plpgsql immutable set search_path = ''
as $$
declare d text := app.so_digitos(c); p1 int[] := array[5,4,3,2,9,8,7,6,5,4,3,2]; p2 int[] := array[6,5,4,3,2,9,8,7,6,5,4,3,2]; s int; i int; r int;
begin
  if length(d) <> 14 or d ~ '^(.)\1{13}$' then return false; end if;
  s := 0; for i in 1..12 loop s := s + substr(d, i, 1)::int * p1[i]; end loop;
  r := s % 11; r := case when r < 2 then 0 else 11 - r end;
  if r <> substr(d, 13, 1)::int then return false; end if;
  s := 0; for i in 1..13 loop s := s + substr(d, i, 1)::int * p2[i]; end loop;
  r := s % 11; r := case when r < 2 then 0 else 11 - r end;
  return r = substr(d, 14, 1)::int;
end $$;

create or replace function app.data_planilha(t text)
returns date language plpgsql immutable set search_path = ''
as $$
declare v text := btrim(coalesce(t, ''));
begin
  if v ~ '^\d{4}-\d{2}-\d{2}' then return left(v, 10)::date; end if;
  if v ~ '^\d{1,2}/\d{1,2}/\d{4}$' then return to_date(v, 'DD/MM/YYYY'); end if;
  return null;
exception when others then return null;
end $$;

create or replace function app.valor_planilha(t text)
returns numeric language plpgsql immutable set search_path = ''
as $$
declare v text := replace(btrim(coalesce(t, '')), 'R$', '');
begin
  v := btrim(v);
  if v ~ ',\d{1,2}$' then v := replace(replace(v, '.', ''), ',', '.'); end if;  -- 1.234,56
  if v !~ '^\d+(\.\d{1,2})?$' then return null; end if;
  return v::numeric;
exception when others then return null;
end $$;

create or replace function app.mascarar_documento(d text, t public.tipo_pessoa)
returns text language sql immutable set search_path = ''
as $$
  select case when d is null then null
    when t = 'PJ' and length(d) = 14 then substr(d,1,2)||'.'||substr(d,3,3)||'.'||substr(d,6,3)||'/'||substr(d,9,4)||'-'||substr(d,13,2)  -- CNPJ não é dado pessoal
    when length(d) = 11 then '***.' || substr(d, 4, 3) || '.' || substr(d, 7, 3) || '-**'
    else '***' end
$$;

-- ===== tabelas =====
create table public.locadores (
  id uuid primary key default gen_random_uuid(),
  tipo public.tipo_pessoa not null,
  nome text not null check (length(btrim(nome)) between 2 and 200),
  documento text not null unique check ((tipo = 'PF' and app.cpf_valido(documento)) or (tipo = 'PJ' and app.cnpj_valido(documento))),
  email text check (email is null or (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and length(email) <= 254)),
  telefone text check (telefone is null or telefone ~ '^[0-9]{10,11}$'),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table public.contratos (
  id uuid primary key default gen_random_uuid(),
  numero text not null check (length(btrim(numero)) between 1 and 30),
  processo text check (processo is null or length(processo) <= 60),
  locador_id uuid not null references public.locadores (id),
  imovel_descricao text not null check (length(btrim(imovel_descricao)) between 2 and 200),
  imovel_endereco text check (imovel_endereco is null or length(imovel_endereco) <= 300),
  unidade_ocupante_id uuid references public.unidades (id),
  inicio date not null,
  fim_original date not null,
  fim_vigencia date not null,
  valor_mensal numeric(12,2) not null check (valor_mensal > 0),
  dia_vencimento integer not null default 10 check (dia_vencimento between 1 and 28),
  fiscal_servidor_id uuid references public.servidores (id),
  indice_reajuste text check (indice_reajuste is null or length(indice_reajuste) <= 40),
  mes_database integer check (mes_database between 1 and 12),
  encerrado boolean not null default false,
  criado_por uuid references public.usuarios (id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint contratos_periodo check (fim_original >= inicio and fim_vigencia >= fim_original)
);
create unique index contratos_numero_uk on public.contratos (app.normalizar(numero));
create trigger contratos_atualizado before update on public.contratos for each row execute function app.tocar_atualizado_em();
create trigger locadores_atualizado before update on public.locadores for each row execute function app.tocar_atualizado_em();

create table public.aditivos (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos (id),
  numero integer not null,
  altera_prazo boolean not null default false,
  altera_valor boolean not null default false,
  novo_fim date,
  novo_valor numeric(12,2) check (novo_valor is null or novo_valor > 0),
  data_assinatura date,
  descricao text check (descricao is null or length(descricao) <= 2000),
  solicitacao_id uuid references public.solicitacoes (id),
  criado_em timestamptz not null default now(),
  unique (contrato_id, numero),
  constraint aditivos_coerente check ((altera_prazo = (novo_fim is not null)) and (altera_valor = (novo_valor is not null)) and (altera_prazo or altera_valor))
);

create table public.contrato_documentos (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos (id),
  aditivo_id uuid references public.aditivos (id),
  nome text not null check (length(nome) between 1 and 120),
  path text not null unique,
  tamanho integer not null check (tamanho between 1 and 31457280),
  enviado_por uuid not null references public.usuarios (id),
  enviado_em timestamptz not null default now()
);

create table public.alugueis (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos (id),
  competencia date not null check (extract(day from competencia) = 1),
  valor numeric(12,2) not null check (valor > 0),
  vencimento date not null,
  pago_em date,
  valor_pago numeric(12,2) check (valor_pago is null or valor_pago > 0),
  registrado_por uuid references public.usuarios (id),
  registrado_em timestamptz,
  unique (contrato_id, competencia),
  constraint alugueis_pagamento check ((pago_em is null) = (valor_pago is null))
);
create index alugueis_venc_idx on public.alugueis (vencimento) where pago_em is null;

create table public.contrato_historico (
  id bigint generated always as identity primary key,
  contrato_id uuid not null references public.contratos (id),
  em timestamptz not null default now(),
  ator_id uuid references public.usuarios (id),
  acao text not null,
  detalhes jsonb not null default '{}'::jsonb
);
create trigger contrato_historico_imutavel before update or delete on public.contrato_historico for each row execute function app.auditoria_imutavel();
create trigger contrato_documentos_sem_delete before delete on public.contrato_documentos for each row execute function app.auditoria_imutavel();

do $$
declare t text;
begin
  foreach t in array array['locadores', 'contratos', 'aditivos', 'contrato_documentos', 'alugueis', 'contrato_historico'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    if t <> 'contrato_historico' then
      execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()', t || '_auditoria', t);
    end if;
  end loop;
end $$;
-- locadores: só colunas não sensíveis pela API; documento/contato só via RPC (mascarado)
grant select (id, tipo, nome) on public.locadores to authenticated;
grant select on public.contratos, public.aditivos, public.contrato_documentos, public.alugueis, public.contrato_historico to authenticated;
create policy locadores_ler on public.locadores for select to authenticated using ((select app.acesso_contratos()));
create policy contratos_ler on public.contratos for select to authenticated using ((select app.acesso_contratos()));
create policy aditivos_ler on public.aditivos for select to authenticated using ((select app.acesso_contratos()));
create policy contrato_docs_ler on public.contrato_documentos for select to authenticated using ((select app.acesso_contratos()));
create policy alugueis_ler on public.alugueis for select to authenticated using ((select app.acesso_contratos()));
create policy contrato_hist_ler on public.contrato_historico for select to authenticated using ((select app.acesso_contratos()));

create or replace function app.historico_contrato(p_contrato uuid, p_acao text, p_detalhes jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = ''
as $$ insert into public.contrato_historico (contrato_id, ator_id, acao, detalhes) values (p_contrato, auth.uid(), p_acao, coalesce(p_detalhes, '{}'::jsonb)) $$;

-- aluguéis mês a mês até o fim da vigência efetiva (não recria os que já existem)
create or replace function app.gerar_alugueis(p_contrato uuid)
returns integer language plpgsql security definer set search_path = ''
as $$
declare c public.contratos; m date; n integer := 0;
begin
  select * into c from public.contratos where id = p_contrato;
  for m in select generate_series(date_trunc('month', c.inicio), date_trunc('month', c.fim_vigencia), interval '1 month')::date loop
    insert into public.alugueis (contrato_id, competencia, valor, vencimento)
    values (c.id, m, c.valor_mensal, make_date(extract(year from m)::int, extract(month from m)::int, c.dia_vencimento))
    on conflict (contrato_id, competencia) do nothing;
    if found then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- ===== locador: mascarado por padrão; completo só com permissão específica (e auditado) =====
create or replace function public.locador_dados(p_locador uuid, p_completo boolean default false)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare l public.locadores; v_pode boolean := app.sessao_ok() and app.tem_modulo('locadores_dados');
begin
  if not app.acesso_contratos() then perform app.erro('Acesso não permitido.', '42501'); end if;
  select * into l from public.locadores where id = p_locador;
  if not found then return null; end if;
  if p_completo and not v_pode then perform app.erro('Exibir CPF e contato completos exige permissão específica.', '42501'); end if;
  if p_completo then
    perform app.registrar_evento('ver_dados_locador', 'locadores', l.id::text, null, jsonb_build_object('campos', 'documento,email,telefone'));
    return jsonb_build_object('id', l.id, 'tipo', l.tipo, 'nome', l.nome, 'documento', l.documento, 'email', l.email, 'telefone', l.telefone, 'mascarado', false, 'pode_ver_completo', true);
  end if;
  return jsonb_build_object('id', l.id, 'tipo', l.tipo, 'nome', l.nome, 'documento', app.mascarar_documento(l.documento, l.tipo),
    'email', case when l.email is null then null else left(l.email, 2) || '***@' || split_part(l.email, '@', 2) end,
    'telefone', case when l.telefone is null then null else '(' || left(l.telefone, 2) || ') *****-' || right(l.telefone, 4) end,
    'mascarado', true, 'pode_ver_completo', v_pode);
end $$;

-- ===== cadastro manual (registro novo: sem aprovação) =====
create or replace function app.obter_locador(p jsonb)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_doc text := app.so_digitos(p ->> 'documento'); v_id uuid;
begin
  select id into v_id from public.locadores where documento = v_doc;
  if v_id is not null then return v_id; end if;  -- já cadastrado: não sobrescreve (alterar passa por aprovação)
  insert into public.locadores (tipo, nome, documento, email, telefone)
  values ((p ->> 'tipo')::public.tipo_pessoa, btrim(p ->> 'nome'), v_doc, nullif(lower(btrim(coalesce(p ->> 'email', ''))), ''),
          nullif(app.so_digitos(p ->> 'telefone'), ''))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.criar_contrato(p_dados jsonb, p_locador jsonb)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_fim date := (p_dados ->> 'fim')::date;
begin
  if not app.acesso_contratos() then perform app.erro('Sem permissão para contratos.', '42501'); end if;
  insert into public.contratos (numero, processo, locador_id, imovel_descricao, imovel_endereco, unidade_ocupante_id, inicio, fim_original, fim_vigencia,
                                valor_mensal, dia_vencimento, fiscal_servidor_id, indice_reajuste, mes_database, criado_por)
  values (btrim(p_dados ->> 'numero'), nullif(btrim(coalesce(p_dados ->> 'processo', '')), ''), app.obter_locador(p_locador), btrim(p_dados ->> 'imovel_descricao'),
          nullif(btrim(coalesce(p_dados ->> 'imovel_endereco', '')), ''), nullif(p_dados ->> 'unidade_ocupante_id', '')::uuid, (p_dados ->> 'inicio')::date,
          v_fim, v_fim, (p_dados ->> 'valor_mensal')::numeric, coalesce((p_dados ->> 'dia_vencimento')::int, 10),
          nullif(p_dados ->> 'fiscal_servidor_id', '')::uuid, nullif(btrim(coalesce(p_dados ->> 'indice_reajuste', '')), ''), nullif(p_dados ->> 'mes_database', '')::int, auth.uid())
  returning id into v_id;
  perform app.gerar_alugueis(v_id);
  perform app.historico_contrato(v_id, 'cadastrado');
  return v_id;
exception
  when unique_violation then perform app.erro('Já existe contrato com esse número ou locador com esse documento.', '23505');
  when check_violation then perform app.erro('Dados inválidos (confira CPF/CNPJ, datas e valor).', '23514');
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or not_null_violation then perform app.erro('Dados inválidos.', '22023');
end $$;

-- ===== pagamento de aluguel: sem aprovação (prompt 6.6/aprovações) =====
create or replace function public.registrar_pagamento_aluguel(p_id uuid, p_data date, p_valor numeric)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.alugueis;
begin
  if not app.acesso_contratos() then perform app.erro('Sem permissão para contratos.', '42501'); end if;
  select * into a from public.alugueis where id = p_id for update;
  if not found then perform app.erro('Aluguel não encontrado.', 'P0002'); end if;
  if a.pago_em is not null then perform app.erro('Pagamento já registrado.', '22023'); end if;
  if p_data is null or p_data > current_date then perform app.erro('Data de pagamento inválida.', '22023'); end if;
  if p_valor is null or p_valor <= 0 then perform app.erro('Valor inválido.', '22023'); end if;
  update public.alugueis set pago_em = p_data, valor_pago = p_valor, registrado_por = auth.uid(), registrado_em = now() where id = p_id;
  perform app.historico_contrato(a.contrato_id, 'pagamento', jsonb_build_object('competencia', to_char(a.competencia, 'MM/YYYY'), 'valor', p_valor));
end $$;

-- desfazer registro errado: só Secretária/Admin, com motivo (auditado)
create or replace function public.desfazer_pagamento_aluguel(p_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = ''
as $$
declare a public.alugueis;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if length(btrim(coalesce(p_motivo, ''))) < 5 then perform app.erro('Informe o motivo.', '22023'); end if;
  select * into a from public.alugueis where id = p_id for update;
  if not found or a.pago_em is null then perform app.erro('Pagamento não encontrado.', 'P0002'); end if;
  update public.alugueis set pago_em = null, valor_pago = null, registrado_por = null, registrado_em = null where id = p_id;
  perform app.historico_contrato(a.contrato_id, 'pagamento_desfeito', jsonb_build_object('competencia', to_char(a.competencia, 'MM/YYYY'), 'motivo', p_motivo));
end $$;

-- ===== documentos (PDF do contrato e dos aditivos) =====
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('contratos', 'contratos', false, 31457280, array['application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
create policy contratos_doc_enviar on storage.objects for insert to authenticated with check (
  bucket_id = 'contratos' and (select app.acesso_contratos()) and name ~ '^contratos/[0-9a-f-]{36}/[0-9a-f-]{36}\.pdf$'
);
create policy contratos_doc_ler on storage.objects for select to authenticated using (bucket_id = 'contratos' and (select app.acesso_contratos()));

create or replace function public.registrar_documento_contrato(p_contrato uuid, p_path text, p_nome text, p_tamanho integer, p_aditivo uuid default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not app.acesso_contratos() then perform app.erro('Sem permissão para contratos.', '42501'); end if;
  if p_path not like 'contratos/' || p_contrato::text || '/%'
     or not exists (select 1 from storage.objects o where o.bucket_id = 'contratos' and o.name = p_path) then
    perform app.erro('Arquivo inválido.', '22023');
  end if;
  if p_aditivo is not null and not exists (select 1 from public.aditivos where id = p_aditivo and contrato_id = p_contrato) then
    perform app.erro('Aditivo inválido.', '22023');
  end if;
  insert into public.contrato_documentos (contrato_id, aditivo_id, nome, path, tamanho, enviado_por)
  values (p_contrato, p_aditivo, left(regexp_replace(coalesce(p_nome, 'documento.pdf'), '[^A-Za-zÀ-ÿ0-9 ._()-]', '_', 'g'), 120), p_path, p_tamanho, auth.uid())
  returning id into v_id;
  perform app.historico_contrato(p_contrato, 'documento', jsonb_build_object('nome', left(p_nome, 120)));
  return v_id;
end $$;

-- ===== importação inicial por planilha (~60 contratos): prévia → tudo ou nada =====
create or replace function app.validar_planilha_contratos(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
declare r jsonb; n integer; v_doc text; v_tipo text; v_ini date; v_fim date;
begin
  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then perform app.erro('Planilha sem linhas.', '22023'); end if;
  if jsonb_array_length(p_linhas) > 1000 then perform app.erro('Máximo de 1000 contratos por importação.', '22023'); end if;
  for r in select * from jsonb_array_elements(p_linhas) loop
    n := coalesce((r ->> 'linha')::int, 0);
    if btrim(coalesce(r ->> 'numero', '')) = '' then return query select n, 'numero', 'Número do contrato vazio.';
    elsif exists (select 1 from public.contratos c where app.normalizar(c.numero) = app.normalizar(r ->> 'numero')) then return query select n, 'numero', 'Contrato já cadastrado.';
    elsif (select count(*) from jsonb_array_elements(p_linhas) x where app.normalizar(x ->> 'numero') = app.normalizar(r ->> 'numero')) > 1 then return query select n, 'numero', 'Número duplicado na planilha.';
    end if;
    if length(btrim(coalesce(r ->> 'locador_nome', ''))) < 2 then return query select n, 'locador_nome', 'Nome do locador vazio.'; end if;
    v_tipo := upper(btrim(coalesce(r ->> 'locador_tipo', '')));
    v_doc := app.so_digitos(r ->> 'locador_documento');
    if v_tipo not in ('PF', 'PJ') then return query select n, 'locador_tipo', 'Tipo do locador deve ser PF ou PJ.';
    elsif (v_tipo = 'PF' and not app.cpf_valido(v_doc)) or (v_tipo = 'PJ' and not app.cnpj_valido(v_doc)) then
      return query select n, 'locador_documento', case when v_tipo = 'PF' then 'CPF inválido.' else 'CNPJ inválido.' end;
    end if;
    if nullif(btrim(coalesce(r ->> 'locador_email', '')), '') is not null and (r ->> 'locador_email') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return query select n, 'locador_email', 'E-mail inválido.'; end if;
    if nullif(app.so_digitos(r ->> 'locador_telefone'), '') is not null and app.so_digitos(r ->> 'locador_telefone') !~ '^[0-9]{10,11}$' then return query select n, 'locador_telefone', 'Telefone inválido (DDD + número).'; end if;
    if length(btrim(coalesce(r ->> 'imovel_descricao', ''))) < 2 then return query select n, 'imovel_descricao', 'Descrição do imóvel vazia.'; end if;
    if nullif(btrim(coalesce(r ->> 'unidade', '')), '') is not null and not exists (select 1 from public.unidades u where app.normalizar(u.sigla) = app.normalizar(r ->> 'unidade')) then
      return query select n, 'unidade', 'Unidade inexistente.';
    end if;
    v_ini := app.data_planilha(r ->> 'inicio'); v_fim := app.data_planilha(r ->> 'fim');
    if v_ini is null then return query select n, 'inicio', 'Data de início inválida (use dd/mm/aaaa).'; end if;
    if v_fim is null then return query select n, 'fim', 'Data de fim inválida (use dd/mm/aaaa).';
    elsif v_ini is not null and v_fim < v_ini then return query select n, 'fim', 'Fim antes do início.'; end if;
    if app.valor_planilha(r ->> 'valor_mensal') is null or app.valor_planilha(r ->> 'valor_mensal') <= 0 then return query select n, 'valor_mensal', 'Valor mensal inválido.'; end if;
    if nullif(btrim(coalesce(r ->> 'dia_vencimento', '')), '') is not null and (btrim(r ->> 'dia_vencimento') !~ '^\d{1,2}$' or (r ->> 'dia_vencimento')::int not between 1 and 28) then
      return query select n, 'dia_vencimento', 'Dia de vencimento deve ser de 1 a 28.';
    end if;
    if nullif(btrim(coalesce(r ->> 'fiscal_matricula', '')), '') is not null and not exists (select 1 from public.servidores s where app.matricula_chave(s.matricula) = app.matricula_chave(r ->> 'fiscal_matricula')) then
      return query select n, 'fiscal_matricula', 'Fiscal não encontrado pela matrícula.';
    end if;
    if nullif(btrim(coalesce(r ->> 'mes_database', '')), '') is not null and (btrim(r ->> 'mes_database') !~ '^\d{1,2}$' or (r ->> 'mes_database')::int not between 1 and 12) then
      return query select n, 'mes_database', 'Mês da data-base deve ser de 1 a 12.';
    end if;
  end loop;
end $$;

create or replace function public.importar_contratos_previa(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not app.acesso_contratos() then perform app.erro('Sem permissão para contratos.', '42501'); end if;
  return query select * from app.validar_planilha_contratos(p_linhas) order by 1, 2;
end $$;

create or replace function public.importar_contratos(p_linhas jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare r jsonb; v_id uuid; n integer := 0;
begin
  if not app.acesso_contratos() then perform app.erro('Sem permissão para contratos.', '42501'); end if;
  if exists (select 1 from app.validar_planilha_contratos(p_linhas)) then perform app.erro('A planilha tem erros. Corrija e confira a prévia antes de importar.', '22023'); end if;
  perform set_config('app.origem', 'importacao_contratos', true);
  for r in select * from jsonb_array_elements(p_linhas) loop
    insert into public.contratos (numero, processo, locador_id, imovel_descricao, imovel_endereco, unidade_ocupante_id, inicio, fim_original, fim_vigencia,
                                  valor_mensal, dia_vencimento, fiscal_servidor_id, indice_reajuste, mes_database, criado_por)
    values (btrim(r ->> 'numero'), nullif(btrim(coalesce(r ->> 'processo', '')), ''),
            app.obter_locador(jsonb_build_object('tipo', upper(btrim(r ->> 'locador_tipo')), 'nome', r ->> 'locador_nome', 'documento', r ->> 'locador_documento',
                                                 'email', r ->> 'locador_email', 'telefone', r ->> 'locador_telefone')),
            btrim(r ->> 'imovel_descricao'), nullif(btrim(coalesce(r ->> 'imovel_endereco', '')), ''),
            (select u.id from public.unidades u where app.normalizar(u.sigla) = app.normalizar(r ->> 'unidade')),
            app.data_planilha(r ->> 'inicio'), app.data_planilha(r ->> 'fim'), app.data_planilha(r ->> 'fim'), app.valor_planilha(r ->> 'valor_mensal'),
            coalesce(nullif(btrim(coalesce(r ->> 'dia_vencimento', '')), '')::int, 10),
            (select s.id from public.servidores s where app.matricula_chave(s.matricula) = app.matricula_chave(r ->> 'fiscal_matricula') limit 1),
            nullif(btrim(coalesce(r ->> 'indice_reajuste', '')), ''), nullif(btrim(coalesce(r ->> 'mes_database', '')), '')::int, auth.uid())
    returning id into v_id;
    perform app.gerar_alugueis(v_id);
    perform app.historico_contrato(v_id, 'importado');
    n := n + 1;
  end loop;
  return n;
end $$;

grant execute on function public.locador_dados(uuid, boolean) to authenticated;
grant execute on function public.criar_contrato(jsonb, jsonb) to authenticated;
grant execute on function public.registrar_pagamento_aluguel(uuid, date, numeric) to authenticated;
grant execute on function public.desfazer_pagamento_aluguel(uuid, text) to authenticated;
grant execute on function public.registrar_documento_contrato(uuid, text, text, integer, uuid) to authenticated;
grant execute on function public.importar_contratos_previa(jsonb) to authenticated;
grant execute on function public.importar_contratos(jsonb) to authenticated;
grant execute on function app.matricula_chave(text), app.cpf_valido(text), app.cnpj_valido(text) to authenticated;
