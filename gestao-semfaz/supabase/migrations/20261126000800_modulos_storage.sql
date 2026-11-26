-- Fase 1 · módulos, pacote padrão PROVISÓRIO, configurações, storage privado

insert into public.modulos (codigo, nome, rota, icone, ordem, status, fase, no_menu) values
  ('painel', 'Painel', '/', 'painel', 10, 'ativo', 1, true),
  ('demandas', 'Demandas', '/demandas', 'demandas', 20, 'em_breve', 3, true),
  ('calendario', 'Calendário', '/calendario', 'calendario', 30, 'ativo', 1, true),
  ('contratos', 'Contratos de locação', '/contratos', 'contratos', 40, 'em_breve', 4, true),
  ('unidades_consumidoras', 'Unidades consumidoras', '/unidades-consumidoras', 'energia', 50, 'em_breve', 4, true),
  ('ferias', 'Férias e folgas', '/ferias', 'ferias', 60, 'em_breve', 2, true),
  ('folhas_ponto', 'Folhas de ponto', '/folhas-ponto', 'relogio', 70, 'em_breve', 2, true),
  ('produtividade', 'Produtividade', '/produtividade', 'grafico', 80, 'em_definicao', 5, true),
  ('aprovacoes', 'Aprovações', '/aprovacoes', 'aprovacoes', 90, 'ativo', 1, true),
  ('relatorios', 'Relatórios', '/relatorios', 'relatorios', 100, 'ativo', 1, true),
  ('usuarios', 'Unidades e usuários', '/usuarios', 'usuarios', 110, 'ativo', 1, true),
  ('obrigacoes_fiscais', 'Obrigações fiscais', '/obrigacoes-fiscais', 'recibo', 120, 'em_breve', 9, true),
  ('auditoria', 'Auditoria', '/relatorios', 'relatorios', 130, 'ativo', 1, false);

-- PROVISÓRIO (rascunho da seção 4 + menu dos protótipos). Aguardando definição oficial.
insert into public.pacotes_padrao (perfil, modulo_codigo, provisorio)
select p::public.perfil_usuario, m.codigo, true
  from unnest(array['administrador', 'secretaria']) p cross join public.modulos m;
insert into public.pacotes_padrao (perfil, modulo_codigo, provisorio)
select p::public.perfil_usuario, m, true
  from unnest(array['diretor', 'coordenador']) p
 cross join unnest(array['painel', 'demandas', 'calendario', 'ferias', 'folhas_ponto', 'produtividade', 'aprovacoes', 'relatorios', 'usuarios']) m;
insert into public.pacotes_padrao (perfil, modulo_codigo, provisorio)
select 'funcionario', m, true from unnest(array['painel', 'demandas', 'calendario', 'ferias', 'produtividade']) m;

insert into public.configuracoes (chave, valor, descricao) values
  ('auth.mfa_recomendada_diretor', 'true', 'Exibir recomendação de MFA para diretores'),
  ('anexos.tamanho_max_mb', '10', 'Tamanho máximo de anexos (MB)'),
  ('anexos.url_validade_s', '60', 'Validade dos links temporários de arquivos (segundos)');

-- storage privado
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('anexos', 'anexos', false, 10485760, array['application/pdf', 'image/png', 'image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- envio: só na própria pasta aprovacoes/<uid>/<uuid>.<ext>
create policy anexos_aprovacao_enviar on storage.objects for insert to authenticated with check (
  bucket_id = 'anexos'
  and (select app.sessao_ok())
  and (storage.foldername(name))[1] = 'aprovacoes'
  and (storage.foldername(name))[2] = (select app.uid())::text
  and name ~ '^aprovacoes/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|png|jpg)$'
);
-- leitura: segue a permissão da solicitação
create policy anexos_aprovacao_ler on storage.objects for select to authenticated using (
  bucket_id = 'anexos'
  and (select app.sessao_ok())
  and (
    ((storage.foldername(name))[1] = 'aprovacoes' and (storage.foldername(name))[2] = (select app.uid())::text)
    or exists (select 1 from public.solicitacoes s where s.anexo_path = name)  -- RLS de solicitacoes aplica
  )
);
-- sem UPDATE/DELETE: anexos nunca são apagados
