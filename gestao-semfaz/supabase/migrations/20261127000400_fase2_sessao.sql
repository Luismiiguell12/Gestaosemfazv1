-- Fase 2 · minha_sessao passa a informar o servidor_id (telas de férias)
create or replace function public.minha_sessao()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select case when u.id is null then jsonb_build_object('autorizado', false, 'motivo', 'sem_cadastro')
    when not u.ativo or s.situacao <> 'ativo' then jsonb_build_object('autorizado', false, 'motivo', 'desativado')
    else jsonb_build_object(
      'autorizado', true,
      'usuario_id', u.id,
      'servidor_id', u.servidor_id,
      'perfil', u.perfil,
      'nome', s.nome_completo,
      'cargo', c.nome,
      'unidade_id', s.unidade_id,
      'unidade_sigla', un.sigla,
      'mfa_exigida', app.exige_mfa(u.perfil),
      'aal', coalesce(auth.jwt() ->> 'aal', 'aal1'),
      'sessao_ok', app.sessao_ok(),
      'modulos', coalesce((select jsonb_agg(m order by m) from app.modulos_do_usuario() m), '[]'::jsonb)
    ) end
  from (select auth.uid() as uid) x
  left join public.usuarios u on u.id = x.uid
  left join public.servidores s on s.id = u.servidor_id
  left join public.cargos c on c.id = s.cargo_id
  left join public.unidades un on un.id = s.unidade_id
$$;

