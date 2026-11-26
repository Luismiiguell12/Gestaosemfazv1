// Gera os PNG do PWA a partir do logo SVG (usa Playwright). Rodar só quando o logo mudar.
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); } catch { ({ chromium } = require(process.env.PLAYWRIGHT_PATH ?? '/opt/node22/lib/node_modules/playwright')); }
import { readFileSync } from 'node:fs';

const svg = readFileSync(new URL('../public/icons/logo.svg', import.meta.url), 'utf8');
const browser = await chromium.launch();
const page = await browser.newPage();
for (const [nome, tam, margem] of [['icon-192', 192, 0], ['icon-512', 512, 0], ['icon-maskable-512', 512, 0.12]]) {
  await page.setViewportSize({ width: tam, height: tam });
  const pad = Math.round(tam * margem);
  await page.setContent(`<html><body style="margin:0;background:${margem ? '#18215A' : 'transparent'}"><div style="padding:${pad}px;width:${tam - 2 * pad}px;height:${tam - 2 * pad}px">${svg.replace('<svg ', '<svg width="100%" height="100%" ')}</div></body></html>`);
  await page.screenshot({ path: new URL(`../public/icons/${nome}.png`, import.meta.url).pathname, omitBackground: !margem });
}
await browser.close();
console.log('ícones gerados');
