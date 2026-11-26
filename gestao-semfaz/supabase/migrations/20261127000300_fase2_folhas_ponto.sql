-- Fase 2 · folhas de ponto (6.8) e controle de entrega (6.18)
-- O PDF do RH é lido no navegador de quem envia (secretária/admin); o cruzamento
-- matrícula → servidor → unidade é feito AQUI no banco (fonte da verdade).

create table public.folhas_lotes (
  id uuid primary key default gen_random_uuid(),
  competencia date not null check (extract(day from competencia) = 1),
  arquivo_path text,
  total_paginas integer not null check (total_paginas between 1 and 2000),
  concluido boolean not null default false,
  enviado_por uuid not null references public.usuarios (id),
  criado_em timestamptz not null default now()
);
create index folhas_lotes_comp_idx on public.folhas_lotes (competencia, criado_em desc);

create table public.folhas_paginas (
  lote_id uuid not null references public.folhas_lotes (id) on delete cascade,
  pagina integer not null check (pagina >= 1),
  matricula_lida text check (matricula_lida is null or length(matricula_lida) <= 40),
  nome_lido text check (nome_lido is null or length(nome_lido) <= 200),
  servidor_id uuid references public.servidores (id),
  unidade_id uuid references public.unidades (id),
  vinculado_por uuid references public.usuarios (id),
  primary key (lote_id, pagina)
);

create table public.folhas_arquivos (
  id uuid primary key default gen_random_uuid(),
  lote_id uuid not null references public.folhas_lotes (id) on delete cascade,
  unidade_id uuid references public.unidades (id),   -- null = "Não identificadas"
  path text not null unique,
  paginas integer not null check (paginas >= 0),
  servidores integer not null check (servidores >= 0),
  criado_em timestamptz not null default now()
);
create index folhas_arquivos_lote_idx on public.folhas_arquivos (lote_id, unidade_id, criado_em desc);

create table public.folhas_entregas (
  competencia date not null check (extract(day from competencia) = 1),
  unidade_id uuid not null references public.unidades (id),
  enviada_em date,
  recebida_por uuid references public.servidores (id),
  devolvida_em date,
  devolvida_por uuid references public.servidores (id),
  ultimo_aviso_atraso date,
  atualizado_por uuid references public.usuarios (id),
  atualizado_em timestamptz not null default now(),
  primary key (competencia, unidade_id),
  constraint folhas_entregas_ordem check (devolvida_em is null or (enviada_em is not null and devolvida_em >= enviada_em)),
  constraint folhas_entregas_envio check (enviada_em is null or recebida_por is not null),
  constraint folhas_entregas_devolucao check (devolvida_em is null or devolvida_por is not null)
);

do $$
declare t text;
begin
  foreach t in array array['folhas_lotes', 'folhas_paginas', 'folhas_arquivos', 'folhas_entregas'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()', t || '_auditoria', t);
  end loop;
end $$;

create or replace function app.chefia_folhas()
returns boolean language sql stable security definer set search_path = ''
as $$ select app.sessao_ok() and app.perfil_atual() in ('diretor', 'coordenador') and app.tem_modulo('folhas_ponto') $$;

create policy folhas_lotes_ler on public.folhas_lotes for select to authenticated
  using ((select app.gestor_geral()) or (select app.chefia_folhas()));
create policy folhas_paginas_ler on public.folhas_paginas for select to authenticated
  using ((select app.gestor_geral()));
create policy folhas_arquivos_ler on public.folhas_arquivos for select to authenticated using (
  (select app.gestor_geral()) or ((select app.chefia_folhas()) and unidade_id in (select app.unidades_escopo()))
);
create policy folhas_entregas_ler on public.folhas_entregas for select to authenticated using (
  (select app.gestor_geral()) or ((select app.chefia_folhas()) and unidade_id in (select app.unidades_escopo()))
);

insert into public.configuracoes (chave, valor, descricao) values
  ('folhas.regex_matricula', to_jsonb('Matr[íi]cula[^0-9A-Za-z]{0,10}([0-9][0-9./-]{0,19})'::text),
   'Alternativa quando a matrícula não está logo abaixo do rótulo "Matrícula" (formato do relatório do RH, validado em 26/11/2026)'),
  ('folhas.prazo_devolucao_dias_uteis', '5', 'Prazo para a unidade devolver as folhas assinadas (dias úteis)')
on conflict (chave) do nothing;

create or replace function app.matricula_chave(m text)
returns text language sql immutable parallel safe set search_path = ''
as $$ select nullif(coalesce(nullif(ltrim(upper(btrim(coalesce(m, ''))), '0'), ''), case when btrim(coalesce(m, '')) ~ '^0+$' then '0' end), '') $$;
create index servidores_matricula_chave_idx on public.servidores (app.matricula_chave(matricula));
-- usada pelo índice: quem insere servidor precisa poder executá-la
grant execute on function app.matricula_chave(text) to authenticated, service_role;

-- ===== 1) cria o lote com o resultado da leitura do PDF (pagina, matricula, nome) e cruza no banco =====
create or replace function public.criar_lote_folhas(p_competencia date, p_paginas jsonb)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; r jsonb; n integer;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if p_competencia is null or extract(day from p_competencia) <> 1 then perform app.erro('Competência inválida.', '22023'); end if;
  if jsonb_typeof(p_paginas) <> 'array' then perform app.erro('Leitura do PDF inválida.', '22023'); end if;
  n := jsonb_array_length(p_paginas);
  if n < 1 or n > 2000 then perform app.erro('O PDF deve ter de 1 a 2000 páginas.', '22023'); end if;
  insert into public.folhas_lotes (competencia, total_paginas, enviado_por) values (p_competencia, n, auth.uid()) returning id into v_id;
  for r in select * from jsonb_array_elements(p_paginas) loop
    -- casa a matrícula ignorando maiúsculas e zeros à esquerda ("12345" = "012345");
    -- se houver mais de um candidato, deixa sem vínculo para conferência manual
    insert into public.folhas_paginas (lote_id, pagina, matricula_lida, nome_lido, servidor_id, unidade_id)
    select v_id, (r ->> 'pagina')::int, left(nullif(btrim(r ->> 'matricula'), ''), 40), left(nullif(btrim(r ->> 'nome'), ''), 200),
           c.id, c.unidade_id
      from (select 1) x
      left join lateral (
        select s.id, s.unidade_id from public.servidores s
         where app.matricula_chave(s.matricula) = app.matricula_chave(r ->> 'matricula')
           and (select count(*) from public.servidores s2 where app.matricula_chave(s2.matricula) = app.matricula_chave(r ->> 'matricula')) = 1
      ) c on true;
  end loop;
  if (select count(*) from public.folhas_paginas where lote_id = v_id) <> n
     or exists (select 1 from public.folhas_paginas where lote_id = v_id and pagina > n) then
    perform app.erro('Leitura do PDF inválida (páginas repetidas ou fora de ordem).', '22023');
  end if;
  return v_id;
end $$;

-- ===== 2) registra os arquivos gerados (original e um por unidade) =====
create or replace function public.registrar_arquivos_folhas(p_lote uuid, p_original text, p_arquivos jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare r jsonb; v_prefixo text := 'lotes/' || p_lote::text || '/';
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  if not exists (select 1 from public.folhas_lotes where id = p_lote) then perform app.erro('Lote não encontrado.', 'P0002'); end if;
  if p_original is not null then
    if p_original <> v_prefixo || 'original.pdf'
       or not exists (select 1 from storage.objects o where o.bucket_id = 'folhas-ponto' and o.name = p_original) then
      perform app.erro('Arquivo original inválido.', '22023');
    end if;
    update public.folhas_lotes set arquivo_path = p_original where id = p_lote;
  end if;
  for r in select * from jsonb_array_elements(coalesce(p_arquivos, '[]'::jsonb)) loop
    if (r ->> 'path') not like v_prefixo || 'unidades/%'
       or not exists (select 1 from storage.objects o where o.bucket_id = 'folhas-ponto' and o.name = r ->> 'path') then
      perform app.erro('Arquivo de unidade inválido.', '22023');
    end if;
    insert into public.folhas_arquivos (lote_id, unidade_id, path, paginas, servidores)
    values (p_lote, nullif(r ->> 'unidade_id', '')::uuid, r ->> 'path', (r ->> 'paginas')::int, (r ->> 'servidores')::int);
  end loop;
  update public.folhas_lotes set concluido = arquivo_path is not null where id = p_lote;
end $$;

-- ===== vincular página sem servidor (nenhuma página é descartada) =====
create or replace function public.vincular_pagina_folha(p_lote uuid, p_pagina integer, p_servidor uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_unidade uuid;
begin
  if not app.gestor_geral() then perform app.erro('Somente a Secretária ou o Administrador do sistema.', '42501'); end if;
  select unidade_id into v_unidade from public.servidores where id = p_servidor;
  if v_unidade is null then perform app.erro('Servidor não encontrado.', 'P0002'); end if;
  update public.folhas_paginas set servidor_id = p_servidor, unidade_id = v_unidade, vinculado_por = auth.uid()
   where lote_id = p_lote and pagina = p_pagina;
  if not found then perform app.erro('Página não encontrada.', 'P0002'); end if;
  return v_unidade;
end $$;

-- páginas do lote com nome do servidor (para montar os PDFs em ordem alfabética)
create or replace function public.paginas_do_lote(p_lote uuid)
returns table (pagina integer, matricula_lida text, nome_lido text, servidor_id uuid, servidor text, unidade_id uuid, unidade text, ordem_unidade integer)
language sql stable security definer set search_path = ''
as $$
  select p.pagina, p.matricula_lida, p.nome_lido, p.servidor_id, s.nome_completo, p.unidade_id, u.sigla, u.ordem
    from public.folhas_paginas p
    left join public.servidores s on s.id = p.servidor_id
    left join public.unidades u on u.id = p.unidade_id
   where p.lote_id = p_lote and app.gestor_geral()
   order by p.pagina
$$;

-- ===== controle de entrega (6.18): secretária/admin ou chefia da unidade =====
create or replace function public.registrar_entrega_folha(p_competencia date, p_unidade uuid, p_etapa text, p_data date, p_pessoa uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not (app.gestor_geral() or (app.chefia_folhas() and app.na_escopo(p_unidade))) then
    perform app.erro('Sem permissão para esta unidade.', '42501');
  end if;
  if p_competencia is null or extract(day from p_competencia) <> 1 then perform app.erro('Competência inválida.', '22023'); end if;
  if p_data is null or p_data > current_date then perform app.erro('Data inválida.', '22023'); end if;
  if p_pessoa is not null and not exists (select 1 from public.servidores where id = p_pessoa and unidade_id = p_unidade) then
    perform app.erro('A pessoa deve ser servidor da unidade.', '22023');
  end if;
  if p_etapa = 'envio' then
    insert into public.folhas_entregas as e (competencia, unidade_id, enviada_em, recebida_por, atualizado_por)
    values (p_competencia, p_unidade, p_data, p_pessoa, auth.uid())
    on conflict (competencia, unidade_id) do update set enviada_em = excluded.enviada_em, recebida_por = excluded.recebida_por,
      atualizado_por = excluded.atualizado_por, atualizado_em = now();
  elsif p_etapa = 'devolucao' then
    update public.folhas_entregas set devolvida_em = p_data, devolvida_por = p_pessoa, atualizado_por = auth.uid(), atualizado_em = now()
     where competencia = p_competencia and unidade_id = p_unidade;
    if not found then perform app.erro('Registre o envio antes da devolução.', '22023'); end if;
  else
    perform app.erro('Etapa inválida.', '22023');
  end if;
end $$;

-- situação por unidade (não enviada / enviada / devolvida / atrasada) — invoker: RLS decide quais unidades aparecem
create or replace function public.situacao_entregas(p_competencia date)
returns table (unidade_id uuid, sigla text, ordem integer, situacao text, enviada_em date, recebida_por text, devolvida_em date, devolvida_por text, atrasada boolean)
language sql stable security invoker set search_path = ''
as $$
  select u.id, u.sigla, u.ordem,
         case when e.devolvida_em is not null then 'devolvida' when e.enviada_em is not null then 'enviada' else 'nao_enviada' end,
         e.enviada_em, sr.nome_completo, e.devolvida_em, sd.nome_completo,
         (e.enviada_em is not null and e.devolvida_em is null
          and public.dias_uteis_entre(e.enviada_em, current_date)
              > coalesce((select (c.valor)::int from public.configuracoes c where c.chave = 'folhas.prazo_devolucao_dias_uteis'), 5))
    from public.unidades u
    left join public.folhas_entregas e on e.unidade_id = u.id and e.competencia = p_competencia
    left join public.servidores sr on sr.id = e.recebida_por
    left join public.servidores sd on sd.id = e.devolvida_por
   where u.ativa and (app.gestor_geral() or (app.chefia_folhas() and u.id in (select app.unidades_escopo())))
   order by u.ordem, u.sigla
$$;

-- ===== aviso diário de atraso na devolução (chefia da unidade) =====
create or replace function app.avisar_atrasos_folhas()
returns integer language plpgsql security definer set search_path = ''
as $$
declare e record; v_chefe uuid; n integer := 0;
        v_prazo integer := coalesce((select (valor)::int from public.configuracoes where chave = 'folhas.prazo_devolucao_dias_uteis'), 5);
begin
  for e in
    select f.*, u.sigla from public.folhas_entregas f join public.unidades u on u.id = f.unidade_id
     where f.enviada_em is not null and f.devolvida_em is null
       and public.dias_uteis_entre(f.enviada_em, current_date) > v_prazo
       and (f.ultimo_aviso_atraso is null or f.ultimo_aviso_atraso < current_date)
  loop
    for v_chefe in select app.chefes_da_unidade(e.unidade_id) loop
      perform app.notificar(v_chefe, 'folha_atrasada', 'Folhas de ponto em atraso',
        e.sigla || ' · competência ' || to_char(e.competencia, 'MM/YYYY') || ' · enviada em ' || to_char(e.enviada_em, 'DD/MM'), '/folhas-ponto');
    end loop;
    update public.folhas_entregas set ultimo_aviso_atraso = current_date where competencia = e.competencia and unidade_id = e.unidade_id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function app.avisar_atrasos_folhas() from public, anon, authenticated;

-- agenda diária (pg_cron, se disponível no servidor — no Supabase: habilitar a extensão)
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('avisar-atrasos-folhas', '0 11 * * 1-5', 'select app.avisar_atrasos_folhas()');
  end if;
exception when others then
  raise notice 'pg_cron indisponível: agendar app.avisar_atrasos_folhas() manualmente';
end $$;

-- ===== storage privado =====
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('folhas-ponto', 'folhas-ponto', false, 52428800, array['application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy folhas_enviar on storage.objects for insert to authenticated with check (
  bucket_id = 'folhas-ponto' and (select app.gestor_geral())
  and name ~ '^lotes/[0-9a-f-]{36}/(original|unidades/(sem-unidade|[0-9a-f-]{36})-[0-9]{13})\.pdf$'
);
create policy folhas_ler on storage.objects for select to authenticated using (
  bucket_id = 'folhas-ponto' and (
    (select app.gestor_geral())
    or exists (select 1 from public.folhas_arquivos f where f.path = name)  -- RLS de folhas_arquivos aplica (escopo)
  )
);

-- módulos da Fase 2 ativos
update public.modulos set status = 'ativo' where codigo in ('ferias', 'folhas_ponto');

grant execute on function public.criar_lote_folhas(date, jsonb) to authenticated;
grant execute on function public.registrar_arquivos_folhas(uuid, text, jsonb) to authenticated;
grant execute on function public.vincular_pagina_folha(uuid, integer, uuid) to authenticated;
grant execute on function public.paginas_do_lote(uuid) to authenticated;
grant execute on function public.registrar_entrega_folha(date, uuid, text, date, uuid) to authenticated;
grant execute on function public.situacao_entregas(date) to authenticated;
grant execute on function app.chefia_folhas() to authenticated;
revoke execute on function public.criar_lote_folhas(date, jsonb) from anon;
revoke execute on function public.registrar_arquivos_folhas(uuid, text, jsonb) from anon;
revoke execute on function public.vincular_pagina_folha(uuid, integer, uuid) from anon;
revoke execute on function public.paginas_do_lote(uuid) from anon;
revoke execute on function public.registrar_entrega_folha(date, uuid, text, date, uuid) from anon;
revoke execute on function public.situacao_entregas(date) from anon;
