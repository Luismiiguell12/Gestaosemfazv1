# Revisão final de segurança e LGPD — Fase 7 (27/11/2026)

Escopo: Fases 1 a 4 e 6, mais os campos do Adendo 01. Fase 5 (Produtividade) ainda não implementada.

## 1. Verificação automática no Supabase de testes (resultado real)

`scripts/verificar-seguranca.sql` executado no projeto `uacgmmuycbfxeigxgtla` em 27/11/2026. **0 FALHAS.**

| Item | Resultado |
|---|---|
| RLS em todas as tabelas (42) | ok |
| `anon` sem acesso a tabelas | ok |
| Funções de `public`/`app` fechadas para `anon`/PUBLIC | ok |
| `SECURITY DEFINER` com `search_path` fixo | ok |
| Buckets do Storage privados (anexos, folhas-ponto, demandas, contratos) | ok |
| Auditoria imutável (bloqueio de UPDATE e TRUNCATE; DELETE bloqueado por privilégio e trigger) | ok |
| CPF do locador sem acesso direto pela API | ok |
| Rotinas diárias no pg_cron | ok |
| Administradores ativos (1) | ok |
| MFA obrigatória | **ATENÇÃO**: desligada no ambiente de testes a pedido (D19). Religar em produção |
| Permissões padrão | **ATENÇÃO**: 49 itens provisórios (seção 9) |
| Servidores com vínculo informado | **ATENÇÃO**: 13 servidores de teste sem vínculo (D56) |

A mesma verificação roda no CI a cada mudança e **reprova** o build se aparecer alguma FALHA.

## 2. OWASP Top 10 — consolidado

| Risco | Como está tratado | Onde está a prova |
|---|---|---|
| A01 Controle de acesso | RLS em todas as tabelas; regra de escopo por perfil/unidade em funções únicas; escritas só por RPC; aprovação com "ninguém aprova o próprio pedido" | `tests/db/*` (≈ 100 testes de banco, inclusive tentativas indevidas por perfil e anônimo) |
| A02 Criptografia / dados sensíveis | HTTPS (Supabase/Pages); CPF/contato mascarados; backup cifrado AES-256; nenhuma chave no frontend | `tests/unit/deploy.test.ts` (segredos no bundle), `locador_dados` |
| A03 Injeção | Sem SQL dinâmico com entrada do usuário (só `format(%I)` com nomes internos); busca escapa curingas; React escapa texto; exportações neutralizam fórmulas | testes de busca, CSV |
| A04 Design inseguro | Histórico e auditoria só crescem; arquivos nunca apagados; versões; hash de versão nas aprovações; importações tudo-ou-nada | testes de aprovação e importação |
| A05 Configuração | Cadastro público desligado; buckets privados com tipo/tamanho; CSP com hashes; anti-clickjacking; funções internas sem EXECUTE | `verificar-seguranca.sql`, `scripts/csp.mjs` |
| A06 Componentes vulneráveis | Dependabot agrupado; `npm audit --omit=dev` no CI (0 vulnerabilidades) | CI |
| A07 Autenticação | Senha ≥ 12 com complexidade; MFA TOTP para admin/secretária (configurável); sessão de 12 h e inatividade de 2 h; token recusado para usuário inativo (hook) | `config.toml`, testes de sessão |
| A08 Integridade | Tipo real de arquivo (assinatura) antes do envio; caminhos gerados pelo sistema e conferidos no banco; CI obrigatório | testes de anexos |
| A09 Logs e monitoramento | Auditoria de todas as tabelas de negócio, logins e exportações; nada de dado pessoal em mensagens de erro | testes de auditoria |
| A10 SSRF | Não há busca de URL informada pelo usuário | — |

## 3. Riscos abertos (resolver antes de dados reais)

| # | Risco | Mitigação planejada | Situação |
|---|---|---|---|
| R1 | MFA desligada no ambiente de testes | Produção nasce com `auth.mfa_obrigatoria = true` (padrão das migrations) | Checklist de implantação |
| R2 | GitHub Pages não envia cabeçalhos HTTP (HSTS, `frame-ancestors`) | Hospedagem com cabeçalhos (Cloudflare Pages/Netlify/servidor da Prefeitura) | Pendente decisão da TI |
| R3 | Repositório público | Tornar privado antes da produção | Pendente |
| R4 | Tipo real do arquivo conferido só no navegador (o bucket limita tipo e tamanho) | Edge Function de validação no upload, ou aceitar o risco residual (só usuários autenticados enviam) | Pendente decisão |
| R5 | E-mail (SMTP) e push não configurados: avisos só dentro do sistema | Configurar SMTP institucional; push na sequência | Pendente |
| R6 | Limite de tentativas de login depende do padrão do Supabase | Conferir limites no painel de produção | Checklist |
| R7 | Backup próprio depende de secrets e de o workflow não ser pausado (60 dias sem commit em repo público) | Conferência mensal; cópia mensal fora do GitHub | Checklist |
| R8 | Permissões padrão provisórias | Definição oficial da SEMFAZ (seção 9) | Pendente |

## 4. LGPD — situação

- Inventário dos dados por fase: `docs/lgpd.md` (rascunho para o DPO).
- **Minimização**: CPF só do locador (mascarado), sem CPF de servidor; folhas de ponto lidas só para matrícula e nome; exportações não ficam guardadas.
- **Acesso**: o próprio, a chefia do escopo, a secretária e o administrador; contratos por módulo; dados completos do locador só com permissão específica e auditada.
- **Direitos do titular** (art. 18): consulta pelo próprio servidor nas telas (saldos, férias, demandas, cadastro); correção por pedido de alteração (aprovação); relatório individual pela secretária.
- **Incidente**: a auditoria permite reconstruir quem acessou e quando; plano de comunicação ao DPO/ANPD a definir pela Prefeitura.
- **Pendências do DPO**: bases legais por tratamento, prazos de retenção (auditoria, pedidos, avaliações da Fase 5 — o adendo pede guarda permanente), aviso de privacidade aos usuários.
- **Fase 5**: avaliação de desempenho é dado pessoal; acesso definido no adendo (seção 8).

## 5. Conclusão

O sistema está **apto para continuar em testes com dados fictícios**. **Não está liberado para dados reais** até os itens R1–R3, R8, o parecer do DPO e o checklist de `docs/implantacao.md`.
