# Gestão SEMFAZ

Plataforma interna da Secretaria Municipal da Fazenda de Lagarto/SE. Especificação: `docs/PROMPT.md`. Situação: `docs/PROJECT_STATUS.md`. Arquitetura: `docs/architecture.md`.

## Rodar localmente

```bash
npm install
cp .env.example .env.local   # preencha URL e anon key (nunca faça commit)
supabase start               # requer Supabase CLI + Docker
supabase db reset            # aplica migrations + seed fictício
npm run dev
```

Primeiro administrador (uma vez, local):

```bash
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/criar-primeiro-admin.mjs --email admin@exemplo.gov.br --nome "Administrador Exemplo" --matricula 000002 --cargo "Analista de Sistemas" --unidade ASTIN
```

## Testes

```bash
npm run typecheck
PGHOST=localhost PGUSER=postgres PGPASSWORD=... npm test   # unitários + banco (PostgreSQL 16 + shim do Supabase)
NEXT_PUBLIC_SUPABASE_URL=https://exemplo.supabase.co NEXT_PUBLIC_SUPABASE_ANON_KEY=x npm run build
npm run test:e2e                                           # fumaça com API simulada
```
