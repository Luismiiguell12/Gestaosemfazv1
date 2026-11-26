// Fumaça E2E: serve o export estático (out/) e simula a API do Supabase com dados FICTÍCIOS.
// Verifica: CSP presente e sem violações, guarda de login, MFA, telas principais, celular sem rolagem lateral.
// Uso: npm run build (com NEXT_PUBLIC_SUPABASE_URL=https://exemplo.supabase.co) && npm run test:e2e
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readFileSync, statSync } from 'node:fs';
import { extname, join } from 'node:path';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); } catch { ({ chromium } = require(process.env.PLAYWRIGHT_PATH ?? '/opt/node22/lib/node_modules/playwright')); }

const OUT = new URL('../../out/', import.meta.url).pathname;
const SHOTS = process.env.SHOTS_DIR ?? new URL('../../test-results/telas/', import.meta.url).pathname;
mkdirSync(SHOTS, { recursive: true });
const API = 'https://exemplo.supabase.co';
const TIPOS = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.woff2': 'font/woff2', '.woff': 'font/woff', '.webmanifest': 'application/manifest+json', '.txt': 'text/plain' };

const servidor = createServer((req, res) => {
  let p = join(OUT, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (existsSync(p) && statSync(p).isDirectory()) p = join(p, 'index.html');
  if (!existsSync(p)) { res.writeHead(404); res.end(readFileSync(join(OUT, '404.html'))); return; }
  res.writeHead(200, { 'content-type': TIPOS[extname(p)] ?? 'application/octet-stream' });
  res.end(readFileSync(p));
}).listen(4173);
const BASE = 'http://localhost:4173';

// ---------- dados fictícios ----------
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const jwt = (aal) => `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub: 'u-sec', role: 'authenticated', aal, exp: 4102444800 })}.assinatura`;
const sessao = (aal) => ({ access_token: jwt(aal), refresh_token: 'r', token_type: 'bearer', expires_in: 3600, expires_at: 4102444800, user: { id: 'u-sec', email: 'secretaria@exemplo.gov.br', aud: 'authenticated', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' } });
const UN = (id, sigla, nome, tipo, pai, ordem) => ({ id, sigla, nome, tipo, unidade_pai_id: pai, ordem, ativa: true });
const unidades = [
  UN('gab', 'Gabinete', 'Gabinete do Secretário', 'gabinete', null, 0), UN('asplan', 'ASPLAN', 'ASPLAN', 'assessoria', 'gab', 1),
  UN('astin', 'ASTIN', 'ASTIN', 'assessoria', 'gab', 2), UN('jur', 'Jurídica', 'Assessoria Jurídica', 'assessoria', 'gab', 3),
  UN('pav', 'PAV', 'Coordenadoria do PAV e da Ordem Cronológica', 'coordenadoria', 'gab', 4),
  UN('dat', 'DAT', 'Diretoria de Administração Tributária', 'diretoria', 'gab', 5), UN('defc', 'DEFC', 'Diretoria de Execução Financeira e Contabilidade', 'diretoria', 'gab', 6),
  UN('coacam', 'COACAM', 'COACAM', 'coordenadoria', 'dat', 1), UN('cofit', 'COFIT', 'Coordenadoria de Fiscalização e Tributos', 'coordenadoria', 'dat', 2),
  UN('coac', 'COAC', 'COAC', 'coordenadoria', 'dat', 3), UN('cocmi', 'COCMI', 'COCMI', 'coordenadoria', 'dat', 4),
  UN('conta', 'CONTA', 'CONTA', 'coordenadoria', 'defc', 1), UN('coef', 'COEF', 'COEF', 'coordenadoria', 'defc', 2),
];
const cargos = [{ id: 'c1', nome: 'Auditor Fiscal', ativo: true }, { id: 'c2', nome: 'Agente Administrativo', ativo: true }, { id: 'c3', nome: 'Coordenador(a)', ativo: true }];
const servidores = [
  ['s1', 'Coordenador da COFIT', '000106', 'c3', 'coordenador.cofit@exemplo.gov.br'], ['s2', 'Servidor A', '000101', 'c1', 'servidor.a@exemplo.gov.br'],
  ['s3', 'Servidor E', '000102', 'c1', 'servidor.e@exemplo.gov.br'], ['s4', 'Servidor F', '000103', 'c1', null], ['s5', 'Servidor G', '000104', 'c2', null],
].map(([id, nome_completo, matricula, cargo_id, email_institucional]) => ({ id, nome_completo, matricula, cargo_id, unidade_id: 'cofit', situacao: 'ativo', email_institucional }));
const usuarios = [{ id: 'u1', servidor_id: 's1', perfil: 'coordenador', ativo: true }, { id: 'u2', servidor_id: 's2', perfil: 'funcionario', ativo: true }, { id: 'u3', servidor_id: 's3', perfil: 'funcionario', ativo: true }];
const M = (codigo, nome, rota, icone, ordem, status) => ({ codigo, nome, rota, icone, ordem, status, no_menu: true });
const modulos = [
  M('painel', 'Painel', '/', 'painel', 10, 'ativo'), M('demandas', 'Demandas', '/demandas', 'demandas', 20, 'em_breve'), M('calendario', 'Calendário', '/calendario', 'calendario', 30, 'ativo'),
  M('contratos', 'Contratos de locação', '/contratos', 'contratos', 40, 'em_breve'), M('unidades_consumidoras', 'Unidades consumidoras', '/unidades-consumidoras', 'energia', 50, 'em_breve'),
  M('ferias', 'Férias e folgas', '/ferias', 'ferias', 60, 'em_breve'), M('folhas_ponto', 'Folhas de ponto', '/folhas-ponto', 'relogio', 70, 'em_breve'),
  M('produtividade', 'Produtividade', '/produtividade', 'grafico', 80, 'em_definicao'), M('aprovacoes', 'Aprovações', '/aprovacoes', 'aprovacoes', 90, 'ativo'),
  M('relatorios', 'Relatórios', '/relatorios', 'relatorios', 100, 'ativo'), M('usuarios', 'Unidades e usuários', '/usuarios', 'usuarios', 110, 'ativo'),
  M('obrigacoes_fiscais', 'Obrigações fiscais', '/obrigacoes-fiscais', 'recibo', 120, 'em_breve'),
];
const pedidos = [
  { id: 'p1', tipo: 'servidor_alterar', resumo: 'Servidor Servidor G · matrícula', alvo_id: 's5', dados_antes: { matricula: '000104' }, dados_depois: { matricula: '000555' }, justificativa: 'Correção conforme portaria nº 000/2026.', anexo_path: null, status: 'pendente', criado_em: new Date(Date.now() - 86400000).toISOString(), solicitante_id: 'u1', solicitante_nome: 'Coordenador da COFIT', decidido_por_nome: null, decidido_em: null, comentario_decisao: null },
  { id: 'p2', tipo: 'unidade_criar', resumo: 'Nova unidade: Núcleo de IBS', alvo_id: null, dados_antes: {}, dados_depois: { sigla: 'NIBS', nome: 'Núcleo de IBS', tipo: 'coordenadoria', unidade_pai_id: 'dat' }, justificativa: 'Reforma 2027.', anexo_path: null, status: 'pendente', criado_em: '2026-11-24T13:00:00Z', solicitante_id: 'u9', solicitante_nome: 'Diretor da DAT', decidido_por_nome: null, decidido_em: null, comentario_decisao: null },
];
const info = (perfil, aal) => ({ autorizado: true, usuario_id: 'u-sec', perfil, nome: perfil === 'funcionario' ? 'Servidor A' : 'Secretária Exemplo', cargo: perfil === 'funcionario' ? 'Auditor Fiscal' : 'Secretário(a)', unidade_id: perfil === 'funcionario' ? 'cofit' : 'gab', unidade_sigla: 'Gabinete', mfa_exigida: perfil === 'secretaria', aal, sessao_ok: perfil !== 'secretaria' || aal === 'aal2', modulos: perfil === 'funcionario' ? ['painel', 'demandas', 'calendario', 'ferias', 'produtividade'] : [...modulos.map((m) => m.codigo), 'auditoria'] });

async function simularApi(page, perfil, aal) {
  await page.route(`${API}/**`, async (route) => {
    const u = new URL(route.request().url());
    const p = u.pathname;
    const json = (d) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(d) });
    if (p.endsWith('/rpc/minha_sessao')) return json(info(perfil, aal));
    if (p.endsWith('/rpc/minhas_unidades_escopo')) return json(unidades.map((x) => x.id));
    if (p.endsWith('/rpc/listar_solicitacoes')) return json(pedidos);
    if (p.endsWith('/rpc/busca_geral')) return json([{ tipo: 'unidade', id: 'cofit', titulo: 'COFIT', subtitulo: 'Coordenadoria de Fiscalização e Tributos', rota: '/usuarios?unidade=cofit' }]);
    const t = p.split('/').pop();
    const tabelas = { unidades, cargos, servidores, usuarios, modulos, pacotes_padrao: [], usuario_modulos_extras: [], usuario_unidades_extras: [], notificacoes: [], feriados: [{ id: 'f1', data: '2026-12-25', descricao: 'Natal', abrangencia: 'nacional' }], auditoria: [] };
    if (t in tabelas) return json(tabelas[t]);
    if (p.includes('/auth/v1/factors') || p.includes('/auth/v1/user')) return json({ id: 'u-sec', factors: [] });
    return json([]);
  });
}

const erros = [];
const browser = await chromium.launch();
const passos = [];
async function passo(nome, fn) {
  try { await fn(); passos.push(['ok', nome]); } catch (e) { passos.push(['FALHOU', nome, e.message.split('\n')[0]]); }
}
async function novaPagina({ mobile = false, perfil, aal = 'aal2' } = {}) {
  const ctx = await browser.newContext(mobile ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, isMobile: true, hasTouch: true } : { viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  page.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) erros.push(m.text()); });
  page.on('pageerror', (e) => erros.push(e.message));
  if (perfil) {
    await simularApi(page, perfil, aal);
    await ctx.addInitScript((s) => localStorage.setItem('sb-exemplo-auth-token', s), JSON.stringify(sessao(aal)));
  }
  return page;
}

await passo('login: página renderiza com CSP e sem cadastro público', async () => {
  const page = await novaPagina();
  await page.goto(`${BASE}/login/`);
  await page.getByRole('heading', { name: 'Entrar' }).waitFor();
  const csp = await page.locator('meta[http-equiv="Content-Security-Policy"]').getAttribute('content');
  assert.match(csp, /script-src 'self' 'sha256-/);
  assert.doesNotMatch(csp, /script-src[^;]*unsafe-inline/);
  assert.match(csp, /object-src 'none'/);
  assert.equal(await page.getByText(/cadastre-se|criar conta/i).count(), 0);
  await page.screenshot({ path: `${SHOTS}/login.png` });
});

await passo('sem sessão: painel redireciona para login', async () => {
  const page = await novaPagina();
  await page.goto(`${BASE}/`);
  await page.waitForURL(/\/login\/?$/);
});

await passo('secretária sem MFA (aal1) vai para /mfa', async () => {
  const page = await novaPagina({ perfil: 'secretaria', aal: 'aal1' });
  await page.goto(`${BASE}/`);
  await page.waitForURL(/\/mfa\/?$/);
});

await passo('painel da secretária (desktop) segue o protótipo', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/`);
  await page.getByRole('heading', { name: 'Como estão as unidades' }).waitFor();
  for (const t of ['Aguardando sua aprovação', 'Contratos perto do vencimento', 'Próximos compromissos', 'Ausências neste mês', 'Ligadas ao Gabinete', 'DAT · Administração Tributária']) await page.getByText(t, { exact: true }).first().waitFor();
  assert.equal(await page.locator('nav[aria-label="Menu principal"] [aria-disabled="true"]').count(), 7);
  await page.getByText('Nova unidade: Núcleo de IBS').first().waitFor();
  await page.screenshot({ path: `${SHOTS}/painel-secretaria.png`, fullPage: true });
});

await passo('busca geral agrupa resultados', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/`);
  await page.getByLabel('Busca geral').fill('cofit');
  await page.getByText('Unidades administrativas').waitFor();
});

await passo('central de aprovações: antes/depois e botões', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/aprovacoes/`);
  await page.getByRole('button', { name: 'Aprovar alteração' }).waitFor();
  await page.getByText('000104').waitFor();
  await page.getByText('000555').waitFor();
  await page.screenshot({ path: `${SHOTS}/aprovacoes.png`, fullPage: true });
});

await passo('unidades e usuários: árvore, tabela e perfis', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/usuarios/?unidade=cofit`);
  await page.getByRole('heading', { name: 'COFIT · 5 servidores' }).waitFor();
  await page.getByText('Perfis do sistema').waitFor();
  await page.screenshot({ path: `${SHOTS}/usuarios.png`, fullPage: true });
  await page.getByText('Servidor A', { exact: true }).click();
  await page.getByRole('dialog').getByText('Módulos extras').waitFor();
  await page.screenshot({ path: `${SHOTS}/usuarios-detalhe.png` });
});

await passo('feriados e relatórios (auditoria)', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/calendario/`);
  await page.getByText('Natal').waitFor();
  await page.screenshot({ path: `${SHOTS}/feriados.png`, fullPage: true });
  await page.goto(`${BASE}/relatorios/`);
  await page.getByRole('button', { name: 'Consultar' }).click();
  await page.getByText('Nenhum registro no período.').waitFor();
  await page.screenshot({ path: `${SHOTS}/relatorios.png`, fullPage: true });
});

await passo('painel do funcionário: menu reduzido', async () => {
  const page = await novaPagina({ perfil: 'funcionario', aal: 'aal1' });
  await page.goto(`${BASE}/`);
  await page.getByText('Minhas férias e folgas').waitFor();
  assert.equal(await page.locator('nav[aria-label="Menu principal"] .menu-item').count(), 5);
  await page.screenshot({ path: `${SHOTS}/painel-funcionario.png`, fullPage: true });
});

await passo('celular: menu em gaveta, sem rolagem lateral, toques ≥ 44px', async () => {
  const page = await novaPagina({ perfil: 'secretaria', mobile: true });
  for (const rota of ['/', '/usuarios/?unidade=cofit', '/aprovacoes/']) {
    await page.goto(`${BASE}${rota}`);
    await page.getByRole('button', { name: 'Abrir menu' }).waitFor();
    const largura = await page.evaluate(() => document.documentElement.scrollWidth);
    assert.ok(largura <= 390, `${rota}: rolagem lateral (${largura}px)`);
  }
  await page.goto(`${BASE}/`);
  await page.screenshot({ path: `${SHOTS}/celular-painel.png`, fullPage: true });
  await page.getByRole('button', { name: 'Abrir menu' }).click();
  const menu = page.locator('nav[aria-label="Menu principal"]');
  await menu.getByText('Aprovações').waitFor();
  const alturas = await menu.locator('.menu-item').evaluateAll((els) => els.map((e) => e.getBoundingClientRect().height));
  assert.ok(alturas.every((h) => h >= 44), `itens do menu < 44px: ${alturas}`);
  await page.waitForTimeout(400); // fim da animação da gaveta
  await page.screenshot({ path: `${SHOTS}/celular-menu.png` });
});

await passo('PWA: manifest e service worker publicados', async () => {
  const page = await novaPagina();
  const r = await page.goto(`${BASE}/manifest.webmanifest`);
  const m = await r.json();
  assert.equal(m.display, 'standalone');
  assert.ok(m.icons.some((i) => i.sizes === '512x512'));
  const sw = await (await page.goto(`${BASE}/sw.js`)).text();
  assert.match(sw, /Nunca guarda respostas da API/);
});

await browser.close();
servidor.close();
const cspViolacoes = erros.filter((e) => /Content Security Policy/i.test(e));
passos.push([cspViolacoes.length ? 'FALHOU' : 'ok', `sem violações de CSP no console (${cspViolacoes.length})`, cspViolacoes[0] ?? '']);
for (const [s, n, d] of passos) console.log(`${s === 'ok' ? '✓' : '✗'} ${n}${d ? ` — ${d}` : ''}`);
const falhas = passos.filter((p) => p[0] !== 'ok').length;
console.log(`\n${passos.length - falhas} passaram, ${falhas} falharam`);
if (erros.length) console.log('Erros de console:', [...new Set(erros)].slice(0, 5));
process.exit(falhas ? 1 : 0);
