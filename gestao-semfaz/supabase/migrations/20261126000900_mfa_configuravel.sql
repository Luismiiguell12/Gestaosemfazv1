-- MFA obrigatória vira configuração (padrão: ligada, como no prompt 5).
-- Desligar só em ambiente de testes, com dados fictícios. Mudança fica na auditoria.
insert into public.configuracoes (chave, valor, descricao) values
  ('auth.mfa_obrigatoria', 'true', 'Exigir verificação em duas etapas de administrador e secretária (manter true em produção)')
on conflict (chave) do nothing;

create or replace function app.exige_mfa(p public.perfil_usuario)
returns boolean language sql stable security definer set search_path = ''
as $$
  select p in ('administrador', 'secretaria')
     and coalesce((select (c.valor)::boolean from public.configuracoes c where c.chave = 'auth.mfa_obrigatoria'), true)
$$;
