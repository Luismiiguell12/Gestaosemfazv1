-- Fase 3 · conversa da demanda (6.21) e anexos (6.20)

create type public.feedback_mensagem as enum ('aprovado', 'ajustar', 'refazer');
create type public.tipo_mensagem as enum ('mensagem', 'pedido_atualizacao');

create table public.demanda_anexos (
  id uuid primary key default gen_random_uuid(),
  demanda_id uuid not null references public.demandas (id) on delete cascade,
  nome text not null check (length(nome) between 1 and 120),
  path text not null unique,
  tipo text not null check (tipo in ('pdf', 'png', 'jpg', 'docx', 'xlsx')),
  tamanho integer not null check (tamanho between 1 and 20971520),
  versao integer not null default 1,
  substitui_id uuid references public.demanda_anexos (id),
  enviado_por uuid not null references public.usuarios (id),
  enviado_em timestamptz not null default now()
);
create index demanda_anexos_idx on public.demanda_anexos (demanda_id, enviado_em);

create table public.demanda_mensagens (
  id uuid primary key default gen_random_uuid(),
  demanda_id uuid not null references public.demandas (id) on delete cascade,
  autor_id uuid not null references public.usuarios (id),
  tipo public.tipo_mensagem not null default 'mensagem',
  texto text not null check (length(btrim(texto)) between 1 and 4000),
  anexo_id uuid references public.demanda_anexos (id),
  criado_em timestamptz not null default now(),
  editado_em timestamptz,
  feedback public.feedback_mensagem,
  feedback_comentario text check (feedback_comentario is null or length(feedback_comentario) <= 1000),
  feedback_por uuid references public.usuarios (id),
  feedback_em timestamptz
);
create index demanda_mensagens_idx on public.demanda_mensagens (demanda_id, criado_em);

do $$
declare t text;
begin
  foreach t in array array['demanda_anexos', 'demanda_mensagens'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.auditar_linha()', t || '_auditoria', t);
  end loop;
end $$;
create policy demanda_anexos_ler on public.demanda_anexos for select to authenticated using ((select app.pode_ver_demanda(demanda_id)));
create policy demanda_msg_ler on public.demanda_mensagens for select to authenticated using ((select app.pode_ver_demanda(demanda_id)));
-- mensagens e anexos nunca são apagados
create trigger demanda_mensagens_sem_delete before delete on public.demanda_mensagens for each row execute function app.auditoria_imutavel();
create trigger demanda_anexos_sem_delete before delete on public.demanda_anexos for each row execute function app.auditoria_imutavel();

-- ===== mensagens =====
create or replace function public.enviar_mensagem(p_demanda uuid, p_texto text, p_mencoes uuid[] default '{}', p_anexo uuid default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_u uuid; v_autor text := app.nome_usuario(auth.uid());
begin
  if not app.pode_ver_demanda(p_demanda) then perform app.erro('Você não participa desta demanda.', '42501'); end if;
  if length(btrim(coalesce(p_texto, ''))) = 0 then perform app.erro('Mensagem vazia.', '22023'); end if;
  if p_anexo is not null and not exists (select 1 from public.demanda_anexos where id = p_anexo and demanda_id = p_demanda) then
    perform app.erro('Anexo inválido.', '22023');
  end if;
  insert into public.demanda_mensagens (demanda_id, autor_id, texto, anexo_id) values (p_demanda, auth.uid(), left(btrim(p_texto), 4000), p_anexo) returning id into v_id;
  foreach v_u in array coalesce(p_mencoes, '{}'::uuid[]) loop
    continue when v_u = auth.uid();
    if not exists (select 1 from public.usuarios u join public.servidores s on s.id = u.servidor_id where u.id = v_u and u.ativo and s.situacao = 'ativo') then
      continue;
    end if;
    insert into public.demanda_participantes (demanda_id, usuario_id) values (p_demanda, v_u) on conflict do nothing;
    perform app.notificar(v_u, 'demanda_mencao', v_autor || ' mencionou você', app.titulo_demanda(p_demanda), '/demandas/ficha?id=' || p_demanda);
    perform app.historico(p_demanda, 'mencao', jsonb_build_object('usuario', app.nome_usuario(v_u)));
  end loop;
  return v_id;
end $$;

create or replace function public.editar_mensagem(p_id uuid, p_texto text)
returns void language plpgsql security definer set search_path = ''
as $$
declare m public.demanda_mensagens;
begin
  select * into m from public.demanda_mensagens where id = p_id;
  if not found or m.autor_id <> auth.uid() or not app.pode_ver_demanda(m.demanda_id) then perform app.erro('Só o autor edita a mensagem.', '42501'); end if;
  if length(btrim(coalesce(p_texto, ''))) = 0 then perform app.erro('Mensagem vazia.', '22023'); end if;
  update public.demanda_mensagens set texto = left(btrim(p_texto), 4000), editado_em = now() where id = p_id;  -- texto anterior fica na auditoria
end $$;

-- "Pedir atualização": secretária, diretor ou coordenador
create or replace function public.pedir_atualizacao(p_demanda uuid, p_texto text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_s uuid; v_u uuid;
begin
  if not app.pode_gerir_demanda((select unidade_id from public.demandas where id = p_demanda)) then
    perform app.erro('Somente a chefia ou a Secretária pedem atualização.', '42501');
  end if;
  insert into public.demanda_mensagens (demanda_id, autor_id, tipo, texto)
  values (p_demanda, auth.uid(), 'pedido_atualizacao', coalesce(nullif(btrim(coalesce(p_texto, '')), ''), 'Por favor, relate o andamento desta demanda.'))
  returning id into v_id;
  for v_s in select servidor_id from public.demanda_responsaveis where demanda_id = p_demanda and ativo loop
    v_u := app.usuario_do_servidor(v_s);
    if v_u is not null then
      perform app.notificar(v_u, 'demanda_pedido_atualizacao', 'Pedido de atualização', app.titulo_demanda(p_demanda), '/demandas/ficha?id=' || p_demanda);
    end if;
  end loop;
  perform app.historico(p_demanda, 'pedido_atualizacao');
  return v_id;
end $$;

-- feedback da chefia em uma mensagem
create or replace function public.dar_feedback(p_mensagem uuid, p_feedback public.feedback_mensagem, p_comentario text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare m public.demanda_mensagens; v_rotulo text := case p_feedback when 'aprovado' then 'Aprovado' when 'ajustar' then 'Ajustar' else 'Refazer' end;
begin
  select * into m from public.demanda_mensagens where id = p_mensagem;
  if not found then perform app.erro('Mensagem não encontrada.', 'P0002'); end if;
  if not app.pode_gerir_demanda((select unidade_id from public.demandas where id = m.demanda_id)) then
    perform app.erro('Somente a chefia ou a Secretária dão feedback.', '42501');
  end if;
  if m.autor_id = auth.uid() then perform app.erro('Feedback é sobre a mensagem de outra pessoa.', '22023'); end if;
  update public.demanda_mensagens set feedback = p_feedback, feedback_comentario = nullif(btrim(coalesce(p_comentario, '')), ''),
    feedback_por = auth.uid(), feedback_em = now() where id = p_mensagem;
  perform app.historico(m.demanda_id, 'feedback', jsonb_build_object('feedback', v_rotulo, 'comentario', p_comentario));
  perform app.notificar(m.autor_id, 'demanda_feedback', 'Feedback: ' || v_rotulo, app.titulo_demanda(m.demanda_id), '/demandas/ficha?id=' || m.demanda_id);
end $$;

-- colegas para menção com @ (nomes do organograma; sem dados pessoais)
create or replace function public.usuarios_mencionaveis(p_termo text)
returns table (usuario_id uuid, nome text, unidade text)
language sql stable security definer set search_path = ''
as $$
  select u.id, s.nome_completo, un.sigla
    from public.usuarios u join public.servidores s on s.id = u.servidor_id join public.unidades un on un.id = s.unidade_id
   where app.sessao_ok() and u.ativo and s.situacao = 'ativo' and length(btrim(coalesce(p_termo, ''))) >= 1
     and app.normalizar(s.nome_completo) like '%' || replace(replace(app.normalizar(btrim(p_termo)), '%', ''), '_', '') || '%'
   order by s.nome_completo limit 8
$$;

-- ===== anexos (bucket privado "demandas"; acesso igual ao da demanda) =====
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('demandas', 'demandas', false, 20971520, array['application/pdf', 'image/png', 'image/jpeg',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function app.demanda_do_caminho(p_nome text)
returns uuid language sql immutable set search_path = ''
as $$ select case when p_nome ~ '^demandas/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|png|jpg|docx|xlsx)$' then (split_part(p_nome, '/', 2))::uuid end $$;
grant execute on function app.demanda_do_caminho(text) to authenticated;

create or replace function app.pode_anexar(p_demanda uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select p_demanda is not null and (app.eh_responsavel(p_demanda) or app.pode_gerir_demanda((select unidade_id from public.demandas where id = p_demanda))) $$;
grant execute on function app.pode_anexar(uuid) to authenticated;

create policy demandas_anexo_enviar on storage.objects for insert to authenticated with check (
  bucket_id = 'demandas' and (select app.pode_anexar(app.demanda_do_caminho(name)))
);
create policy demandas_anexo_ler on storage.objects for select to authenticated using (
  bucket_id = 'demandas' and (select app.pode_ver_demanda(app.demanda_do_caminho(name)))
);

create or replace function public.registrar_anexo(p_demanda uuid, p_path text, p_nome text, p_tipo text, p_tamanho integer, p_substitui uuid default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_versao integer := 1;
begin
  if not app.pode_anexar(p_demanda) then perform app.erro('Somente responsáveis ou a chefia anexam arquivos.', '42501'); end if;
  if app.demanda_do_caminho(p_path) is distinct from p_demanda
     or not exists (select 1 from storage.objects o where o.bucket_id = 'demandas' and o.name = p_path) then
    perform app.erro('Arquivo inválido.', '22023');
  end if;
  if p_substitui is not null then
    select versao + 1 into v_versao from public.demanda_anexos where id = p_substitui and demanda_id = p_demanda;
    if v_versao is null then perform app.erro('Anexo a substituir não encontrado.', 'P0002'); end if;
  end if;
  insert into public.demanda_anexos (demanda_id, nome, path, tipo, tamanho, versao, substitui_id, enviado_por)
  values (p_demanda, left(regexp_replace(coalesce(p_nome, 'arquivo'), '[^A-Za-zÀ-ÿ0-9 ._()-]', '_', 'g'), 120), p_path, p_tipo, p_tamanho, v_versao, p_substitui, auth.uid())
  returning id into v_id;
  perform app.historico(p_demanda, case when p_substitui is null then 'anexo' else 'anexo_nova_versao' end,
    jsonb_build_object('nome', left(p_nome, 120), 'versao', v_versao));
  return v_id;
end $$;

-- ===== ficha completa (uma chamada) =====
create or replace function public.demanda_detalhe(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare d public.demandas;
begin
  if not app.pode_ver_demanda(p_id) then return null; end if;
  select * into d from public.demandas where id = p_id;
  return jsonb_build_object(
    'demanda', to_jsonb(d) - 'ultimo_aviso_prazo' || jsonb_build_object(
      'unidade', (select sigla from public.unidades where id = d.unidade_id),
      'criado_por_nome', app.nome_usuario(d.criado_por),
      'dias_uteis', case when d.prazo is null then null else public.dias_uteis_entre(current_date, d.prazo) end),
    'permissoes', jsonb_build_object('gerir', app.pode_gerir_demanda(d.unidade_id), 'responsavel', app.eh_responsavel(p_id),
      'anexar', app.pode_anexar(p_id), 'proprio_criador', d.criado_por = auth.uid()),
    'responsaveis', coalesce((select jsonb_agg(jsonb_build_object('servidor_id', s.id, 'nome', s.nome_completo, 'papel', r.papel, 'usuario_id', app.usuario_do_servidor(s.id)) order by r.papel, s.nome_completo)
                                from public.demanda_responsaveis r join public.servidores s on s.id = r.servidor_id where r.demanda_id = p_id and r.ativo), '[]'::jsonb),
    'checklist', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'texto', c.texto, 'feito', c.feito, 'responsavel', (select nome_completo from public.servidores where id = c.responsavel_id),
                                  'feito_por', app.nome_usuario(c.feito_por), 'feito_em', c.feito_em) order by c.ordem)
                             from public.demanda_checklist c where c.demanda_id = p_id and not c.removido), '[]'::jsonb),
    'mensagens', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'tipo', m.tipo, 'texto', m.texto, 'autor_id', m.autor_id, 'autor', app.nome_usuario(m.autor_id),
                                  'criado_em', m.criado_em, 'editado_em', m.editado_em, 'feedback', m.feedback, 'feedback_comentario', m.feedback_comentario,
                                  'feedback_por', app.nome_usuario(m.feedback_por), 'anexo', (select jsonb_build_object('id', a.id, 'nome', a.nome, 'path', a.path) from public.demanda_anexos a where a.id = m.anexo_id))
                                  order by m.criado_em) from public.demanda_mensagens m where m.demanda_id = p_id), '[]'::jsonb),
    'anexos', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'nome', a.nome, 'path', a.path, 'tipo', a.tipo, 'tamanho', a.tamanho, 'versao', a.versao,
                                  'substitui_id', a.substitui_id, 'enviado_por', app.nome_usuario(a.enviado_por), 'enviado_em', a.enviado_em) order by a.enviado_em)
                          from public.demanda_anexos a where a.demanda_id = p_id), '[]'::jsonb),
    'historico', coalesce((select jsonb_agg(jsonb_build_object('em', h.em, 'ator', app.nome_usuario(h.ator_id), 'acao', h.acao, 'detalhes', h.detalhes) order by h.em desc, h.id desc)
                             from public.demanda_historico h where h.demanda_id = p_id), '[]'::jsonb)
  );
end $$;

grant execute on function public.enviar_mensagem(uuid, text, uuid[], uuid) to authenticated;
grant execute on function public.editar_mensagem(uuid, text) to authenticated;
grant execute on function public.pedir_atualizacao(uuid, text) to authenticated;
grant execute on function public.dar_feedback(uuid, public.feedback_mensagem, text) to authenticated;
grant execute on function public.usuarios_mencionaveis(text) to authenticated;
grant execute on function public.registrar_anexo(uuid, text, text, text, integer, uuid) to authenticated;
grant execute on function public.demanda_detalhe(uuid) to authenticated;
