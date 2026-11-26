// Pós-build: injeta CSP restritiva em cada HTML exportado, com hash SHA-256
// de cada script inline gerado pelo Next (evita 'unsafe-inline' em script-src).
// Limitação do GitHub Pages: CSP via <meta> não suporta frame-ancestors/report-uri.
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const OUT = new URL('../out/', import.meta.url).pathname;
const supa = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
let origemApi = '';
try { origemApi = supa ? new URL(supa).origin : ''; } catch { origemApi = ''; }
const ws = origemApi.replace(/^http/, 'ws');

const htmls = (dir) => readdirSync(dir).flatMap((n) => {
  const p = join(dir, n);
  return statSync(p).isDirectory() ? htmls(p) : n.endsWith('.html') ? [p] : [];
});

let total = 0;
for (const arq of htmls(OUT)) {
  let html = readFileSync(arq, 'utf8');
  if (html.includes('http-equiv="Content-Security-Policy"')) continue;
  const hashes = new Set();
  for (const m of html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)) {
    if (m[1].length) hashes.add(`'sha256-${createHash('sha256').update(m[1], 'utf8').digest('base64')}'`);
  }
  const csp = [
    "default-src 'self'",
    `script-src 'self' ${[...hashes].join(' ')}`.trim(),
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob:",
    "font-src 'self'",
    `connect-src 'self' ${origemApi} ${ws}`.trim(),
    "manifest-src 'self'",
    "worker-src 'self'",
    "frame-src 'none'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    'upgrade-insecure-requests',
  ].join('; ');
  html = html.replace(/<head>/, `<head><meta http-equiv="Content-Security-Policy" content="${csp}">`);
  writeFileSync(arq, html);
  total++;
}
console.log(`CSP aplicada em ${total} páginas`);
