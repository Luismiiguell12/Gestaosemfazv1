-- Fase 1 · tabelas

-- estrutura organizacional (cadastrável, não fixa no código)
create table public.unidades (
  id uuid primary key default gen_random_uuid(),
  sigla text not null check (btrim(sigla) <> '' and length(sigla) <= 40),
  nome text not null check (btrim(nome) <> '' and length(nome) <= 200),
  tipo public.tipo_unidade not null,
  unidade_pai_id uuid references public.unidades (id) on delete restrict,
  ordem integer not null default 0,
  ativa boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint unidades_raiz_gabinete check ((tipo = 'gabinete') = (unidade_pai_id is null)),
  constraint unidades_pai_diferente check (unidade_pai_id is null or unidade_pai_id <> id)
);
create unique index unidades_sigla_uk on public.unidades (app.normalizar(sigla));
create unique index unidades_um_gabinete on public.unidades (tipo) where tipo = 'gabinete';
create index unidades_pai_idx on public.unidades (unidade_pai_id);

create or replace function app.unidades_validar()
returns trigger language plpgsql set search_path = ''
as $$
declare v_pai public.tipo_unidade; v_ciclo boolean;
begin
  if new.unidade_pai_id is not null then
    select tipo into v_pai from public.unidades where id = new.unidade_pai_id;
    if new.tipo = 'diretoria' and v_pai <> 'gabinete' then
      perform app.erro('Diretoria deve estar ligada ao Gabinete.', '23514');
    end if;
    if new.tipo = 'assessoria' and v_pai <> 'gabinete' then
      perform app.erro('Assessoria deve estar ligada ao Gabinete.', '23514');
    end if;
    if new.tipo = 'coordenadoria' and v_pai not in ('gabinete', 'diretoria') then
      perform app.erro('Coordenadoria deve estar ligada a uma diretoria ou ao Gabinete.', '23514');
    end if;
    with recursive cadeia(id) as (
      select new.unidade_pai_id
      union
      select u.unidade_pai_id from public.unidades u join cadeia c on u.id = c.id where u.unidade_pai_id is not null
    ) select exists (select 1 from cadeia where id = new.id) into v_ciclo;
    if v_ciclo then perform app.erro('Estrutura inválida: ciclo entre unidades.', '23514'); end if;
  end if;
  return new;
end $$;
create trigger unidades_validar before insert or update on public.unidades
  for each row execute function app.unidades_validar();
create trigger unidades_atualizado before update on public.unidades
  for each row execute function app.tocar_atualizado_em();

-- cargos (lista oficial pendente)
create table public.cargos (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (btrim(nome) <> '' and length(nome) <= 120),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create unique index cargos_nome_uk on public.cargos (app.normalizar(nome));
create trigger cargos_atualizado before update on public.cargos
  for each row execute function app.tocar_atualizado_em();

-- servidores: matrícula obrigatória e única (chave das folhas de ponto)
create table public.servidores (
  id uuid primary key default gen_random_uuid(),
  nome_completo text not null check (btrim(nome_completo) <> '' and length(nome_completo) <= 200),
  matricula text not null check (matricula ~ '^[0-9A-Za-z./-]{1,20}$'),
  cargo_id uuid not null references public.cargos (id) on delete restrict,
  unidade_id uuid not null references public.unidades (id) on delete restrict,
  situacao public.situacao_servidor not null default 'ativo',
  email_institucional text check (
    email_institucional is null or (email_institucional ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and length(email_institucional) <= 254)
  ),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create unique index servidores_matricula_uk on public.servidores (upper(matricula));
create unique index servidores_email_uk on public.servidores (lower(email_institucional)) where email_institucional is not null;
create index servidores_unidade_idx on public.servidores (unidade_id);

create or replace function app.servidores_normalizar()
returns trigger language plpgsql set search_path = ''
as $$
begin
  new.matricula := btrim(new.matricula);
  new.nome_completo := btrim(regexp_replace(new.nome_completo, '\s+', ' ', 'g'));
  new.email_institucional := nullif(lower(btrim(new.email_institucional)), '');
  return new;
end $$;
create trigger servidores_normalizar before insert or update on public.servidores
  for each row execute function app.servidores_normalizar();
create trigger servidores_atualizado before update on public.servidores
  for each row execute function app.tocar_atualizado_em();

-- contas de acesso (1:1 com auth.users)
create table public.usuarios (
  id uuid primary key references auth.users (id) on delete restrict,
  servidor_id uuid not null unique references public.servidores (id) on delete restrict,
  perfil public.perfil_usuario not null,
  ativo boolean not null default true,
  desativado_em timestamptz,
  desativado_por uuid references public.usuarios (id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create trigger usuarios_atualizado before update on public.usuarios
  for each row execute function app.tocar_atualizado_em();

create or replace function app.usuarios_validar()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if not exists (select 1 from public.servidores s where s.id = new.servidor_id and s.email_institucional is not null) then
    perform app.erro('Servidor sem e-mail institucional não pode ter login.', '23514');
  end if;
  return new;
end $$;
create trigger usuarios_validar before insert or update of servidor_id on public.usuarios
  for each row execute function app.usuarios_validar();

-- e-mail do servidor com login não pode ser removido
create or replace function app.servidores_email_login()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.email_institucional is null and exists (select 1 from public.usuarios u where u.servidor_id = new.id) then
    perform app.erro('E-mail institucional é obrigatório para quem tem login.', '23514');
  end if;
  return new;
end $$;
create trigger servidores_email_login before update of email_institucional on public.servidores
  for each row execute function app.servidores_email_login();

-- módulos e pacotes
create table public.modulos (
  codigo text primary key check (codigo ~ '^[a-z_]{2,40}$'),
  nome text not null,
  rota text not null,
  icone text not null,
  ordem integer not null,
  status public.status_modulo not null default 'em_breve',
  fase integer not null check (fase between 1 and 9),
  no_menu boolean not null default true
);

-- PROVISÓRIO: aguardando definição oficial da SEMFAZ (prompt seção 4)
create table public.pacotes_padrao (
  perfil public.perfil_usuario not null,
  modulo_codigo text not null references public.modulos (codigo) on delete cascade,
  provisorio boolean not null default true,
  primary key (perfil, modulo_codigo)
);

create table public.usuario_modulos_extras (
  usuario_id uuid not null references public.usuarios (id) on delete cascade,
  modulo_codigo text not null references public.modulos (codigo) on delete cascade,
  concedido_por uuid not null references public.usuarios (id),
  concedido_em timestamptz not null default now(),
  primary key (usuario_id, modulo_codigo)
);

create table public.usuario_unidades_extras (
  usuario_id uuid not null references public.usuarios (id) on delete cascade,
  unidade_id uuid not null references public.unidades (id) on delete cascade,
  solicitacao_id uuid,
  concedido_em timestamptz not null default now(),
  primary key (usuario_id, unidade_id)
);

-- feriados (dias úteis)
create table public.feriados (
  id uuid primary key default gen_random_uuid(),
  data date not null unique,
  descricao text not null check (btrim(descricao) <> '' and length(descricao) <= 120),
  abrangencia text not null check (abrangencia in ('nacional', 'estadual', 'municipal', 'ponto_facultativo')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create trigger feriados_atualizado before update on public.feriados
  for each row execute function app.tocar_atualizado_em();

-- aprovações
create table public.solicitacoes (
  id uuid primary key default gen_random_uuid(),
  tipo public.tipo_solicitacao not null,
  alvo_id uuid,
  dados_antes jsonb not null default '{}'::jsonb,
  dados_depois jsonb not null default '{}'::jsonb,
  versao_alvo text,
  justificativa text not null check (length(btrim(justificativa)) between 5 and 2000),
  anexo_path text check (anexo_path is null or anexo_path ~ '^aprovacoes/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|png|jpg)$'),
  solicitante_id uuid not null references public.usuarios (id),
  status public.status_solicitacao not null default 'pendente',
  decidido_por uuid references public.usuarios (id),
  decidido_em timestamptz,
  comentario_decisao text check (comentario_decisao is null or length(comentario_decisao) <= 2000),
  criado_em timestamptz not null default now(),
  constraint solicitacoes_nao_aprova_proprio check (decidido_por is null or decidido_por <> solicitante_id),
  constraint solicitacoes_recusa_comentada check (status <> 'recusada' or length(btrim(coalesce(comentario_decisao, ''))) > 0),
  constraint solicitacoes_decisao_completa check ((status in ('aprovada', 'recusada')) = (decidido_por is not null))
);
create index solicitacoes_status_idx on public.solicitacoes (status, criado_em desc);
create index solicitacoes_solicitante_idx on public.solicitacoes (solicitante_id);
alter table public.usuario_unidades_extras
  add constraint usuario_unidades_extras_solicitacao_fk foreign key (solicitacao_id) references public.solicitacoes (id);

-- notificações internas
create table public.notificacoes (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.usuarios (id) on delete cascade,
  tipo text not null,
  titulo text not null,
  texto text,
  link text check (link is null or link ~ '^/[A-Za-z0-9/_?=&.-]*$'),
  lida_em timestamptz,
  criado_em timestamptz not null default now()
);
create index notificacoes_usuario_idx on public.notificacoes (usuario_id, criado_em desc);

-- configurações (prazos etc.)
create table public.configuracoes (
  chave text primary key check (chave ~ '^[a-z_.]{2,80}$'),
  valor jsonb not null,
  descricao text not null
);

-- limite de requisições (só service-role)
create table public.limites_requisicao (
  chave text primary key,
  janela_inicio timestamptz not null,
  contador integer not null
);
