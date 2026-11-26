// Junta as migrations num arquivo único p/ colar no SQL Editor do Supabase (web).
// Rodar após criar/alterar migration: node scripts/gerar-sql-unico.mjs
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';

const dir = new URL('../supabase/migrations/', import.meta.url);
export function gerar() {
  const arquivos = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
  const partes = arquivos.map((f) => `-- ===================== ${f} =====================\n${readFileSync(new URL(f, dir), 'utf8').trim()}\n`);
  return `-- GERADO AUTOMATICAMENTE por scripts/gerar-sql-unico.mjs. Não editar à mão.
-- Uso: Supabase (web) → SQL Editor → New query → colar TUDO → Run. Somente em projeto NOVO e vazio.
-- Contém ${arquivos.length} migrations, na ordem.

${partes.join('\n')}`;
}
if (import.meta.url === `file://${process.argv[1]}`) {
  writeFileSync(new URL('../supabase/deploy/banco-completo.sql', import.meta.url), gerar());
  console.log('supabase/deploy/banco-completo.sql gerado');
}
