-- Fase 2 · saldos do RH e importação de servidores/saldos por planilha (6.7)
-- Saldos são dados pessoais: só o próprio, a chefia (escopo), secretária e admin.

create table public.saldos_servidor (
  servidor_id uuid primary key references public.servidores (id) on delete cascade,
  ferias_dias numeric(6,1) not null default 0 check (ferias_dias between 0 and 9999),
  licenca_premio_dias numeric(6,1) not null default 0 check (licenca_premio_dias between 0 and 9999),
  folgas numeric(6,1) not null default 0 check (folgas between 0 and 9999),
  fonte text not null default 'RH',
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid references public.usuarios (id)
);
alter table public.saldos_servidor enable row level security;
revoke all on public.saldos_servidor from anon, authenticated;
grant select on public.saldos_servidor to authenticated;
create policy saldos_ler on public.saldos_servidor for select to authenticated using (
  (select app.sessao_ok()) and (
    servidor_id = (select app.servidor_atual())
    or ((select app.tem_modulo('ferias'))
        and exists (select 1 from public.servidores s where s.id = servidor_id and s.unidade_id in (select app.unidades_escopo())))
  )
);
create trigger saldos_servidor_auditoria after insert or update or delete on public.saldos_servidor
  for each row execute function app.auditar_linha();

-- id pela chave de saldo (auditoria usa "id"; aqui é servidor_id)
create or replace function app.auditar_linha()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_old jsonb; v_new jsonb; v_id text;
begin
  if tg_op in ('UPDATE', 'DELETE') then v_old := to_jsonb(old); end if;
  if tg_op in ('INSERT', 'UPDATE') then v_new := to_jsonb(new); end if;
  if tg_op = 'UPDATE' and v_old = v_new then return null; end if;
  v_id := coalesce(v_new ->> 'id', v_old ->> 'id',
                   concat_ws(':', coalesce(v_new, v_old) ->> 'usuario_id', coalesce(v_new, v_old) ->> 'servidor_id',
                             coalesce(v_new, v_old) ->> 'modulo_codigo', coalesce(v_new, v_old) ->> 'unidade_id',
                             coalesce(v_new, v_old) ->> 'perfil', coalesce(v_new, v_old) ->> 'chave'));
  perform app.registrar_evento(lower(tg_op), tg_table_name, v_id, v_old, v_new);
  return null;
end $$;

-- ===== validação comum de linhas de planilha =====
-- Entrada: jsonb array de objetos {linha, nome, matricula, cargo, unidade, email, ferias, licenca_premio, folgas}
-- Saída: uma linha por erro (linha, campo, mensagem). Sem erros = pode importar.
create or replace function app.validar_planilha_servidores(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
declare r jsonb; n integer; v_mat text; v_email text; v_num text;
begin
  if jsonb_typeof(p_linhas) <> 'array' then perform app.erro('Planilha inválida.', '22023'); end if;
  if jsonb_array_length(p_linhas) = 0 then perform app.erro('Planilha sem linhas.', '22023'); end if;
  if jsonb_array_length(p_linhas) > 2000 then perform app.erro('Máximo de 2000 linhas por importação.', '22023'); end if;
  for r in select * from jsonb_array_elements(p_linhas) loop
    n := coalesce((r ->> 'linha')::int, 0);
    v_mat := btrim(coalesce(r ->> 'matricula', ''));
    v_email := nullif(lower(btrim(coalesce(r ->> 'email', ''))), '');
    if btrim(coalesce(r ->> 'nome', '')) = '' then return query select n, 'nome', 'Nome vazio.'; end if;
    if length(btrim(coalesce(r ->> 'nome', ''))) > 200 then return query select n, 'nome', 'Nome com mais de 200 caracteres.'; end if;
    if v_mat = '' then return query select n, 'matricula', 'Matrícula vazia.';
    elsif v_mat !~ '^[0-9A-Za-z./-]{1,20}$' then return query select n, 'matricula', 'Matrícula com formato inválido.';
    elsif exists (select 1 from public.servidores s where upper(s.matricula) = upper(v_mat)) then
      return query select n, 'matricula', 'Matrícula já cadastrada.';
    elsif (select count(*) from jsonb_array_elements(p_linhas) x where upper(btrim(x ->> 'matricula')) = upper(v_mat)) > 1 then
      return query select n, 'matricula', 'Matrícula duplicada na planilha.';
    end if;
    if not exists (select 1 from public.cargos c where c.ativo and app.normalizar(c.nome) = app.normalizar(r ->> 'cargo')) then
      return query select n, 'cargo', 'Cargo inexistente.';
    end if;
    if not exists (select 1 from public.unidades u where u.ativa and app.normalizar(u.sigla) = app.normalizar(r ->> 'unidade')) then
      return query select n, 'unidade', 'Unidade inexistente.';
    end if;
    if v_email is not null then
      if v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return query select n, 'email', 'E-mail inválido.';
      elsif exists (select 1 from public.servidores s where s.email_institucional = v_email) then
        return query select n, 'email', 'E-mail já cadastrado.';
      elsif (select count(*) from jsonb_array_elements(p_linhas) x where lower(btrim(x ->> 'email')) = v_email) > 1 then
        return query select n, 'email', 'E-mail duplicado na planilha.';
      end if;
    end if;
    foreach v_num in array array['ferias', 'licenca_premio', 'folgas'] loop
      if nullif(btrim(coalesce(r ->> v_num, '')), '') is not null
         and replace(btrim(r ->> v_num), ',', '.') !~ '^[0-9]{1,4}(\.[0-9])?$' then
        return query select n, v_num, 'Saldo inválido (use número, ex.: 30 ou 12,5).';
      end if;
    end loop;
  end loop;
end $$;

create or replace function app.numero_planilha(v text)
returns numeric language sql immutable set search_path = ''
as $$ select coalesce(nullif(replace(btrim(coalesce(v, '')), ',', '.'), '')::numeric, 0) $$;

create or replace function public.importar_servidores_previa(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  return query select * from app.validar_planilha_servidores(p_linhas) order by 1, 2;
end $$;

-- grava só se não houver nenhum erro (tudo ou nada)
create or replace function public.importar_servidores(p_linhas jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare r jsonb; v_id uuid; n integer := 0;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if exists (select 1 from app.validar_planilha_servidores(p_linhas)) then
    perform app.erro('A planilha tem erros. Corrija e confira a prévia antes de importar.', '22023');
  end if;
  perform set_config('app.origem', 'importacao_servidores', true);
  for r in select * from jsonb_array_elements(p_linhas) loop
    insert into public.servidores (nome_completo, matricula, cargo_id, unidade_id, email_institucional)
    values (
      r ->> 'nome', r ->> 'matricula',
      (select c.id from public.cargos c where c.ativo and app.normalizar(c.nome) = app.normalizar(r ->> 'cargo')),
      (select u.id from public.unidades u where u.ativa and app.normalizar(u.sigla) = app.normalizar(r ->> 'unidade')),
      nullif(btrim(coalesce(r ->> 'email', '')), '')
    ) returning id into v_id;
    insert into public.saldos_servidor (servidor_id, ferias_dias, licenca_premio_dias, folgas, fonte, atualizado_por)
    values (v_id, app.numero_planilha(r ->> 'ferias'), app.numero_planilha(r ->> 'licenca_premio'),
            app.numero_planilha(r ->> 'folgas'), 'Planilha de servidores', auth.uid());
    n := n + 1;
  end loop;
  return n;
end $$;

-- ===== saldos do RH (matrícula + 3 saldos); atualiza servidores existentes =====
create or replace function public.importar_saldos_previa(p_linhas jsonb)
returns table (linha integer, campo text, mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
declare r jsonb; n integer; v_num text; v_mat text;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then perform app.erro('Planilha sem linhas.', '22023'); end if;
  if jsonb_array_length(p_linhas) > 2000 then perform app.erro('Máximo de 2000 linhas por importação.', '22023'); end if;
  for r in select * from jsonb_array_elements(p_linhas) loop
    n := coalesce((r ->> 'linha')::int, 0);
    v_mat := btrim(coalesce(r ->> 'matricula', ''));
    if v_mat = '' then return query select n, 'matricula'::text, 'Matrícula vazia.'::text;
    elsif not exists (select 1 from public.servidores s where upper(s.matricula) = upper(v_mat)) then
      return query select n, 'matricula'::text, 'Matrícula não encontrada no cadastro.'::text;
    elsif (select count(*) from jsonb_array_elements(p_linhas) x where upper(btrim(x ->> 'matricula')) = upper(v_mat)) > 1 then
      return query select n, 'matricula'::text, 'Matrícula duplicada na planilha.'::text;
    end if;
    foreach v_num in array array['ferias', 'licenca_premio', 'folgas'] loop
      if replace(btrim(coalesce(r ->> v_num, '')), ',', '.') !~ '^[0-9]{1,4}(\.[0-9])?$' then
        return query select n, v_num, 'Saldo vazio ou inválido.'::text;
      end if;
    end loop;
  end loop;
end $$;

create or replace function public.importar_saldos(p_linhas jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare r jsonb; n integer := 0;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if exists (select 1 from public.importar_saldos_previa(p_linhas)) then
    perform app.erro('A planilha tem erros. Corrija e confira a prévia antes de importar.', '22023');
  end if;
  perform set_config('app.origem', 'importacao_saldos', true);
  for r in select * from jsonb_array_elements(p_linhas) loop
    insert into public.saldos_servidor as s (servidor_id, ferias_dias, licenca_premio_dias, folgas, fonte, atualizado_em, atualizado_por)
    select sv.id, app.numero_planilha(r ->> 'ferias'), app.numero_planilha(r ->> 'licenca_premio'), app.numero_planilha(r ->> 'folgas'),
           'Levantamento do RH', now(), auth.uid()
      from public.servidores sv where upper(sv.matricula) = upper(btrim(r ->> 'matricula'))
    on conflict (servidor_id) do update set ferias_dias = excluded.ferias_dias, licenca_premio_dias = excluded.licenca_premio_dias,
      folgas = excluded.folgas, fonte = excluded.fonte, atualizado_em = excluded.atualizado_em, atualizado_por = excluded.atualizado_por;
    n := n + 1;
  end loop;
  return n;
end $$;

grant execute on function public.importar_servidores_previa(jsonb) to authenticated;
grant execute on function public.importar_servidores(jsonb) to authenticated;
grant execute on function public.importar_saldos_previa(jsonb) to authenticated;
grant execute on function public.importar_saldos(jsonb) to authenticated;
revoke execute on function public.importar_servidores_previa(jsonb) from anon;
revoke execute on function public.importar_servidores(jsonb) from anon;
revoke execute on function public.importar_saldos_previa(jsonb) from anon;
revoke execute on function public.importar_saldos(jsonb) from anon;

-- origem da operação na auditoria (importação etc.)
create or replace function app.contexto_auditoria()
returns jsonb language sql stable set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'papel', auth.jwt() ->> 'role',
    'aal', auth.jwt() ->> 'aal',
    'solicitacao_id', nullif(current_setting('app.solicitacao_id', true), ''),
    'origem', nullif(current_setting('app.origem', true), '')
  ))
$$;
