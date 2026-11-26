-- Fase 1 · RLS em TODAS as tabelas. Sem política = sem acesso.

do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- leitura básica (organograma, cargos, módulos, configurações): qualquer usuário ativo (D4)
grant select on public.unidades, public.cargos, public.modulos, public.pacotes_padrao, public.configuracoes, public.feriados to authenticated;
create policy unidades_ler on public.unidades for select to authenticated using ((select app.sessao_ok()));
create policy cargos_ler on public.cargos for select to authenticated using ((select app.sessao_ok()));
create policy modulos_ler on public.modulos for select to authenticated using ((select app.sessao_ok()));
create policy pacotes_ler on public.pacotes_padrao for select to authenticated using ((select app.sessao_ok()));
create policy configuracoes_ler on public.configuracoes for select to authenticated using ((select app.sessao_ok()));
create policy feriados_ler on public.feriados for select to authenticated using ((select app.sessao_ok()));

-- feriado novo: secretária/admin (alteração e exclusão só por aprovação)
grant insert (data, descricao, abrangencia) on public.feriados to authenticated;
create policy feriados_inserir on public.feriados for insert to authenticated with check ((select app.gestor_geral()));

-- servidores: o próprio; chefia no escopo com módulo "usuarios"
grant select on public.servidores to authenticated;
create policy servidores_ler on public.servidores for select to authenticated using (
  (select app.sessao_ok()) and (
    id = (select app.servidor_atual())
    or ((select app.tem_modulo('usuarios')) and unidade_id in (select app.unidades_escopo()))
  )
);
grant insert (nome_completo, matricula, cargo_id, unidade_id, email_institucional) on public.servidores to authenticated;
create policy servidores_inserir on public.servidores for insert to authenticated with check ((select app.gestor_geral()));

-- usuários
grant select on public.usuarios to authenticated;
create policy usuarios_ler on public.usuarios for select to authenticated using (
  (select app.sessao_ok()) and (
    id = (select app.uid())
    or ((select app.tem_modulo('usuarios'))
        and exists (select 1 from public.servidores s where s.id = servidor_id and s.unidade_id in (select app.unidades_escopo())))
  )
);

grant select on public.usuario_modulos_extras, public.usuario_unidades_extras to authenticated;
create policy modulos_extras_ler on public.usuario_modulos_extras for select to authenticated using (
  (select app.sessao_ok()) and (
    usuario_id = (select app.uid())
    or exists (select 1 from public.usuarios u where u.id = usuario_id)  -- herda escopo da política de usuarios
  )
);
create policy unidades_extras_ler on public.usuario_unidades_extras for select to authenticated using (
  (select app.sessao_ok()) and (
    usuario_id = (select app.uid())
    or exists (select 1 from public.usuarios u where u.id = usuario_id)
  )
);

-- solicitações: solicitante ou secretária/admin
grant select on public.solicitacoes to authenticated;
create policy solicitacoes_ler on public.solicitacoes for select to authenticated using (
  (select app.sessao_ok()) and (solicitante_id = (select app.uid()) or (select app.gestor_geral()))
);

-- notificações: só as próprias
grant select on public.notificacoes to authenticated;
create policy notificacoes_ler on public.notificacoes for select to authenticated using (
  (select app.sessao_ok()) and usuario_id = (select app.uid())
);

-- auditoria: secretária/admin com módulo auditoria
grant select on public.auditoria to authenticated;
create policy auditoria_ler on public.auditoria for select to authenticated using (
  (select app.gestor_geral()) and (select app.tem_modulo('auditoria'))
);

-- limites_requisicao: nenhuma política (só service-role)
