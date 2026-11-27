// Backup dos arquivos do Storage (PDFs de contratos, folhas de ponto, anexos) em um .zip.
// Uso (só no GitHub Actions ou na máquina do administrador; NUNCA no navegador):
//   SUPABASE_URL=https://xxx.supabase.co SUPABASE_SERVICE_ROLE_KEY=... node scripts/backup-storage.mjs saida/storage.zip
// Não imprime nomes de arquivos nem conteúdo; só totais.
import { writeFileSync } from 'node:fs';
import { zipSync } from 'fflate';

const url = process.env.SUPABASE_URL?.replace(/\/$/, '');
const chave = process.env.SUPABASE_SERVICE_ROLE_KEY;
const saida = process.argv[2];
if (!url || !chave || !saida) { console.error('Defina SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY e o arquivo de saída.'); process.exit(2); }
const h = { Authorization: `Bearer ${chave}`, apikey: chave };

async function api(caminho, init = {}) {
  const r = await fetch(`${url}/storage/v1${caminho}`, { ...init, headers: { ...h, ...(init.headers ?? {}) } });
  if (!r.ok) throw new Error(`Storage respondeu ${r.status} em ${caminho.split('/').slice(0, 3).join('/')}`);
  return r;
}

async function listar(bucket, prefixo = '') {
  const itens = [];
  for (let offset = 0; ; offset += 1000) {
    const r = await api(`/object/list/${bucket}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ prefix: prefixo, limit: 1000, offset }) });
    const pagina = await r.json();
    for (const o of pagina) {
      const nome = prefixo ? `${prefixo}/${o.name}` : o.name;
      if (o.id === null || o.id === undefined) itens.push(...await listar(bucket, nome)); // pasta
      else itens.push(nome);
    }
    if (pagina.length < 1000) return itens;
  }
}

const arquivos = {};
let total = 0, bytes = 0;
const buckets = await (await api('/bucket')).json();
for (const b of buckets) {
  for (const nome of await listar(b.id)) {
    const dados = new Uint8Array(await (await api(`/object/${b.id}/${nome.split('/').map(encodeURIComponent).join('/')}`)).arrayBuffer());
    arquivos[`${b.id}/${nome}`] = [dados, { level: 0 }]; // PDFs já são comprimidos
    total++; bytes += dados.length;
  }
}
writeFileSync(saida, zipSync(arquivos));
console.log(`storage: ${buckets.length} bucket(s), ${total} arquivo(s), ${(bytes / 1048576).toFixed(1)} MB`);
