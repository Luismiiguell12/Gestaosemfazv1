# Revisão OWASP Top 10 (2021) — Fase 1

| Risco | Situação na Fase 1 | Evidência | Pendência |
|---|---|---|---|
| A01 Controle de acesso quebrado | RLS em todas as tabelas; gate `sessao_ok()` consulta o banco a cada request; sem UPDATE/DELETE direto nas tabelas protegidas; RPCs validam perfil, escopo e campos; ninguém aprova o próprio pedido | `tests/db/acesso.test.ts`, `aprovacoes.test.ts` (anon, funcionário, desativado, sem MFA, escopo) | Validar no Supabase real |
| A02 Falhas criptográficas | HTTPS (GitHub Pages/Supabase); senhas e TOTP no Supabase Auth; `upgrade-insecure-requests` | `scripts/csp.mjs` | HSTS depende do host |
| A03 Injeção | PostgREST parametrizado; SQL dinâmico só com `quote_ident` sobre campos de lista fixa; busca escapa `%` e `_`; React escapa saída; sem `innerHTML` | `atualizar_por_json`, `busca_geral`, teste de varredura do frontend | — |
| A04 Design inseguro | Aprovação com hash do registro (bloqueia se mudou); limite de requisições no convite; anexos com nome gerado | `decidir_solicitacao`, `consumir_limite` | — |
| A05 Configuração incorreta | `anon` sem privilégio; EXECUTE revogado de PUBLIC; `search_path` fixo em funções `SECURITY DEFINER`; cadastro público desligado | testes de privilégios | CSP via `<meta>` (sem `frame-ancestors`); CORS da API REST não configurável no Supabase hospedado |
| A06 Componentes vulneráveis | Versões fixadas; `npm audit` no CI; Dependabot | `.github/` | Ativar alertas no GitHub |
| A07 Falhas de identificação/autenticação | Senha ≥ 12 com complexidade; limite de tentativas; MFA obrigatória p/ admin e secretária (no banco); sessão com timebox; hook bloqueia token de inativo; mensagem de login não revela se o e-mail existe | `config.toml`, `custom_access_token_hook`, testes de MFA | Configurar SMTP próprio |
| A08 Integridade de software/dados | Auditoria imutável (nem superusuário altera); deploy manual por workflow | testes de auditoria | — |
| A09 Logs e monitoramento | Auditoria de alterações, logins (hook), permissões | `auditoria` | Alertas de segurança: Fase 7 |
| A10 SSRF | Sem busca de URLs no servidor; `redirect_to` do convite restrito à origem permitida | `convidar-usuario` | — |

Testes desta revisão: os listados no relatório da Fase 1. Itens marcados "validar no Supabase real" não foram executados no Supabase (ver PROJECT_STATUS).
