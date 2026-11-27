# Gestão SEMFAZ — Guia de implantação em produção

Fase 7. Passo a passo para colocar o sistema no ar com dados reais. **Nada de dado real antes de concluir a seção 1 (pré-requisitos) e a validação de segurança e LGPD.**

Ambientes: **testes** (Supabase `uacgmmuycbfxeigxgtla` + GitHub Pages, dados fictícios) → **produção** (projeto Supabase novo, só dados reais). Nunca reaproveitar o projeto de testes como produção.

## 1. Pré-requisitos (decisões e documentos)

| Item | Responsável | Situação |
|---|---|---|
| Validação das fases pelo responsável (roteiro em `docs/roteiro-testes.md`) | SEMFAZ | Pendente |
| Permissões padrão por perfil oficiais (seção 9) | SEMFAZ | Pendente (pacote provisório) |
| Lista oficial de cargos, modelo das planilhas, planilha de saldos do RH | SEMFAZ / RH | Pendente |
| Parecer do encarregado (DPO) sobre `docs/lgpd.md` (bases legais, retenção) | Prefeitura | Pendente |
| Hospedagem do frontend com cabeçalhos HTTP (ver 3.1) e domínio oficial | Prefeitura / TI | Pendente |
| Conta de e-mail institucional para envio (SMTP) | TI | Pendente |
| Fase 5 (Produtividade/Adendo 01), se for entrar já na produção | — | Não iniciada |

## 2. Banco (Supabase de produção)

1. Criar projeto novo no Supabase, **região São Paulo (sa-east-1)**, plano com **backup diário e PITR** (Pro ou superior). Senha do banco forte, guardada no cofre de senhas da TI.
2. Aplicar a estrutura, por um destes caminhos:
   - CLI: `supabase link --project-ref <ref>` e `supabase db push` (aplica `supabase/migrations/` em ordem); ou
   - Web: colar `supabase/deploy/banco-completo.sql` no SQL Editor. Se der erro de valor novo de enum, rode antes, sozinho, `supabase/migrations/20261129000050_fase4_tipos.sql`.
   - **Não** rodar `supabase/seed.sql` em produção (dados fictícios).
3. Extensão **pg_cron** (Database → Extensions) antes das migrations, ou reaplicar depois `20261127000300` e `20261129000300` para agendar as rotinas.
4. Conferir com `scripts/verificar-seguranca.sql` no SQL Editor: **nenhuma linha FALHA**.

## 3. Autenticação e e-mail

1. Authentication → Sign In / Providers: **desligar cadastro público** ("Allow new users to sign up" = off).
2. Senha: mínimo 12 caracteres, letras maiúsculas e minúsculas, números e símbolos; proteção contra senhas vazadas ligada.
3. Sessões: JWT 3600 s; tempo máximo de sessão 12 h; inatividade 2 h (como em `supabase/config.toml`).
4. MFA: TOTP ligado. No banco, **`auth.mfa_obrigatoria` = true** (padrão das migrations; no ambiente de testes está desligado — ver D19):
   `update public.configuracoes set valor = 'true' where chave = 'auth.mfa_obrigatoria';`
5. Hooks → Customize Access Token: `public.custom_access_token_hook`.
6. SMTP próprio (Settings → Auth → SMTP): remetente institucional; modelos de e-mail de convite e recuperação em português.
7. URL Configuration: *Site URL* = domínio oficial; *Redirect URLs* = `https://<domínio>/definir-senha/` e `https://<domínio>/recuperar-senha/`.
8. Edge Function `convidar-usuario`: `supabase functions deploy convidar-usuario` e secret `ALLOWED_ORIGIN=https://<domínio>`.
9. Primeiro administrador (na máquina do administrador, nunca no navegador):
   `SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/criar-primeiro-admin.mjs --email ... --nome "..." --matricula ... --cargo "..." --unidade ... --vinculo efetivo`
   Em seguida, apagar a chave do terminal/histórico.

### 3.1 Frontend

- Build: `NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY` do projeto de produção; `NEXT_PUBLIC_BASE_PATH` vazio se for domínio próprio.
- **Recomendado: hospedagem com cabeçalhos HTTP** (Cloudflare Pages, Netlify ou servidor da Prefeitura) em vez do GitHub Pages, para enviar:
  `Content-Security-Policy` (a mesma do `<meta>` + `frame-ancestors 'none'`), `Strict-Transport-Security: max-age=31536000; includeSubDomains`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy: camera=(), microphone=(), geolocation=()`.
- **Repositório privado** antes da produção (ou separar a configuração de produção em repositório privado). O código não tem segredos, mas a configuração de produção não deve ser pública.

## 4. Backup e restauração

- **Supabase**: backup diário automático do plano pago + PITR (restaurar a qualquer momento dos últimos dias).
- **Backup próprio** (cópia independente, inclui os arquivos do Storage): workflow `.github/workflows/backup.yml`, diário às 03:17 de Brasília, cifrado com AES-256 antes de sair do runner; guarda 30 dias como artefato.
  - Secrets: `SUPABASE_DB_URL` (string do *Session pooler*), `SUPABASE_SERVICE_ROLE_KEY`, `BACKUP_PASSPHRASE` (≥ 20 caracteres, guardada **também** fora do GitHub). Variável `NEXT_PUBLIC_SUPABASE_URL`.
  - Sem os secrets o workflow só avisa e termina.
  - Recomendado copiar o artefato mensalmente para armazenamento da Prefeitura (fora do GitHub).
- **Restauração** (projeto novo com a estrutura aplicada):
  `BACKUP_PASSPHRASE=... DB_URL=... scripts/restaurar-backup.sh <pasta-com-o-arquivo .tar.gpg>`
  O script recusa restaurar por cima de um banco que já tenha servidores. Arquivos do Storage: descompactar `storage.zip` e enviar pelo painel ou CLI (`supabase storage cp`).
- **Teste de restauração**: `scripts/testar-restauracao.sh` roda no CI a cada mudança (dados fictícios). Em produção, **testar a restauração a cada 6 meses** num projeto descartável e registrar o resultado.

## 5. GitHub

- Ativar: secret scanning, push protection, Dependabot alerts.
- Proteger a branch `main` (PR obrigatório, CI verde).
- Workflows agendados de repositórios públicos param após 60 dias sem commits: conferir o backup mensalmente.

## 6. Checklist do dia da implantação

- [ ] Projeto de produção criado (São Paulo, plano com backup/PITR)
- [ ] Migrations aplicadas; `verificar-seguranca.sql` sem FALHA
- [ ] Cadastro público desligado; senha forte; sessões; MFA obrigatória = true
- [ ] Hook de token, SMTP, URLs de redirecionamento, Edge Function com `ALLOWED_ORIGIN`
- [ ] Frontend publicado no domínio oficial com cabeçalhos de segurança
- [ ] Primeiro administrador criado; chave service_role fora do terminal
- [ ] Estrutura oficial (unidades, cargos) e permissões padrão oficiais cadastradas (`pacotes_padrao.provisorio = false`)
- [ ] Servidores importados com matrícula e tipo de vínculo; saldos do RH
- [ ] Backup próprio configurado e uma execução manual com sucesso
- [ ] Teste de login de cada perfil com MFA (admin e secretária)
- [ ] Aviso de privacidade aprovado pelo DPO publicado para os usuários
- [ ] Projeto de testes continua só com dados fictícios
