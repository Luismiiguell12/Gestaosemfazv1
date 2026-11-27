// Exportação de relatórios (PDF, Excel, CSV) gerada no navegador, só com o que a pessoa já pode ver.
// Sem dados de terceiros e sem guardar cópia em servidor.

export type Formato = 'pdf' | 'xlsx' | 'csv';
export type TipoColuna = 'texto' | 'numero' | 'moeda' | 'data' | 'dataHora' | 'percentual';
export interface Coluna { chave: string; rotulo: string; tipo?: TipoColuna; largura?: number }
export type Linha = Record<string, unknown>;
export interface Tabela { titulo: string; filtros: string[]; colunas: Coluna[]; linhas: Linha[]; geradoPor: string; geradoEm: Date }

const BRL = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });
const NUM = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 2 });

/** valor exibido (PDF/CSV) */
export function textoCelula(v: unknown, tipo: TipoColuna = 'texto'): string {
  if (v === null || v === undefined || v === '') return '';
  if (typeof v === 'boolean') return v ? 'Sim' : 'Não';
  switch (tipo) {
    case 'moeda': return BRL.format(Number(v));
    case 'numero': return NUM.format(Number(v));
    case 'percentual': return `${NUM.format(Number(v))}%`;
    case 'data': { const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(v)); return m ? `${m[3]}/${m[2]}/${m[1]}` : String(v); }
    case 'dataHora': { const d = new Date(String(v)); return isNaN(d.getTime()) ? String(v) : d.toLocaleString('pt-BR', { timeZone: 'America/Maceio' }); }
    default: return typeof v === 'object' ? JSON.stringify(v) : String(v);
  }
}

/** impede que o Excel interprete texto como fórmula (CSV injection) */
export const neutralizarFormula = (t: string) => (/^[=+\-@\t\r]/.test(t) ? `'${t}` : t);

// ===== CSV: ; como separador, BOM para acentos, números no formato brasileiro =====
export function gerarCsv(t: Tabela): Blob {
  const esc = (c: string) => (/[;"\n\r]/.test(c) ? `"${c.replace(/"/g, '""')}"` : c);
  const linha = (v: string[]) => v.map((c) => esc(neutralizarFormula(c))).join(';');
  const corpo = [linha(t.colunas.map((c) => c.rotulo)), ...t.linhas.map((l) => linha(t.colunas.map((c) => textoCelula(l[c.chave], c.tipo))))];
  return new Blob(['﻿' + corpo.join('\r\n') + '\r\n'], { type: 'text/csv;charset=utf-8' });
}

// ===== XLSX mínimo (Office Open XML) com fflate: números como número, datas como data =====
const xml = (t: string) => t.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '');
const letraColuna = (i: number) => { let s = ''; i += 1; while (i > 0) { const m = (i - 1) % 26; s = String.fromCharCode(65 + m) + s; i = Math.floor((i - 1) / 26); } return s; };
const serialExcel = (iso: string) => { const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso); return m ? (Date.UTC(+m[1], +m[2] - 1, +m[3]) - Date.UTC(1899, 11, 30)) / 86400000 : null; };
// estilos: 0 normal, 1 cabeçalho (negrito), 2 data, 3 moeda, 4 número, 5 título
const ESTILO: Partial<Record<TipoColuna, number>> = { data: 2, moeda: 3, numero: 4, percentual: 4 };

export async function gerarXlsx(t: Tabela): Promise<Blob> {
  const { zipSync, strToU8 } = await import('fflate');
  const celula = (ref: string, v: unknown, tipo: TipoColuna = 'texto', estilo = 0) => {
    if (v === null || v === undefined || v === '') return '';
    if ((tipo === 'moeda' || tipo === 'numero' || tipo === 'percentual') && Number.isFinite(Number(v)))
      return `<c r="${ref}" s="${ESTILO[tipo]}"><v>${Number(v)}</v></c>`;
    if (tipo === 'data') { const s = serialExcel(String(v)); if (s !== null) return `<c r="${ref}" s="2"><v>${s}</v></c>`; }
    return `<c r="${ref}" t="inlineStr" s="${estilo}"><is><t xml:space="preserve">${xml(textoCelula(v, tipo))}</t></is></c>`;
  };
  const linhasXml: string[] = [];
  let r = 1;
  linhasXml.push(`<row r="${r}">${celula(`A${r}`, t.titulo, 'texto', 5)}</row>`); r++;
  for (const f of [...t.filtros, `Gerado por ${t.geradoPor} em ${t.geradoEm.toLocaleString('pt-BR', { timeZone: 'America/Maceio' })}`]) { linhasXml.push(`<row r="${r}">${celula(`A${r}`, f)}</row>`); r++; }
  r++;
  const cab = r;
  linhasXml.push(`<row r="${r}">${t.colunas.map((c, i) => celula(`${letraColuna(i)}${r}`, c.rotulo, 'texto', 1)).join('')}</row>`); r++;
  for (const l of t.linhas) { linhasXml.push(`<row r="${r}">${t.colunas.map((c, i) => celula(`${letraColuna(i)}${r}`, l[c.chave], c.tipo)).join('')}</row>`); r++; }
  const larguras = t.colunas.map((c, i) => `<col min="${i + 1}" max="${i + 1}" width="${c.largura ?? (c.tipo === 'texto' || !c.tipo ? 28 : 14)}" customWidth="1"/>`).join('');
  const ultima = `${letraColuna(Math.max(t.colunas.length - 1, 0))}${Math.max(r - 1, cab)}`;
  const planilha = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="${cab}" topLeftCell="A${cab + 1}" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>${larguras}</cols><sheetData>${linhasXml.join('')}</sheetData><autoFilter ref="A${cab}:${ultima}"/></worksheet>`;
  const estilos = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="2"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/><numFmt numFmtId="165" formatCode="&quot;R$&quot; #,##0.00"/></numFmts><fonts count="3"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="14"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="6"><xf/><xf fontId="1" applyFont="1"/><xf numFmtId="164" applyNumberFormat="1"/><xf numFmtId="165" applyNumberFormat="1"/><xf numFmtId="4" applyNumberFormat="1"/><xf fontId="2" applyFont="1"/></cellXfs></styleSheet>`;
  const nomeAba = xml(t.titulo.replace(/[\\/?*[\]:]/g, ' ').slice(0, 31));
  const arquivos = {
    '[Content_Types].xml': strToU8(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>`),
    '_rels/.rels': strToU8(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`),
    'xl/workbook.xml': strToU8(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="${nomeAba}" sheetId="1" r:id="rId1"/></sheets><definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">'${nomeAba.replace(/'/g, "''")}'!$A$${cab}:$${letraColuna(Math.max(t.colunas.length - 1, 0))}$${Math.max(r - 1, cab)}</definedName></definedNames></workbook>`),
    'xl/_rels/workbook.xml.rels': strToU8(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`),
    'xl/worksheets/sheet1.xml': strToU8(planilha),
    'xl/styles.xml': strToU8(estilos),
  };
  return new Blob([zipSync(arquivos, { level: 6 }) as BlobPart], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
}

// ===== PDF (A4 paisagem) com pdf-lib e fonte padrão (WinAnsi) =====
/** troca caracteres fora do WinAnsi (a fonte padrão do PDF não tem) */
export const paraWinAnsi = (t: string) =>
  t.replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/≥/g, '>=').replace(/≤/g, '<=').replace(/→/g, '->')
    .replace(/[  ]/g, ' ').replace(/[^\x20-\x7E¡-ÿ–—•…€]/g, '?');

export async function gerarPdf(t: Tabela): Promise<Blob> {
  const { PDFDocument, StandardFonts, rgb } = await import('pdf-lib');
  const doc = await PDFDocument.create();
  doc.setTitle(t.titulo); doc.setProducer('Gestão SEMFAZ'); doc.setCreator('Gestão SEMFAZ');
  const fr = await doc.embedFont(StandardFonts.Helvetica);
  const fb = await doc.embedFont(StandardFonts.HelveticaBold);
  const [W, H, M] = [841.89, 595.28, 32];
  const tam = 8;
  const util = W - 2 * M;
  const pesos = t.colunas.map((c) => c.largura ?? (c.tipo === 'texto' || !c.tipo ? 3 : 1.6));
  const soma = pesos.reduce((a, b) => a + b, 0);
  const larg = pesos.map((p) => (p / soma) * util);
  const cortar = (s: string, w: number, f = fr) => {
    let x = paraWinAnsi(s);
    if (f.widthOfTextAtSize(x, tam) <= w) return x;
    while (x.length > 1 && f.widthOfTextAtSize(x + '…', tam) > w) x = x.slice(0, -1);
    return x + '…';
  };
  const AZUL = rgb(0.1, 0.15, 0.38), CINZA = rgb(0.36, 0.4, 0.47), LINHA = rgb(0.88, 0.9, 0.93);
  const paginas: ReturnType<typeof doc.addPage>[] = [];
  let pg = doc.addPage([W, H]); paginas.push(pg);
  let y = H - M;
  const cabecalhoTabela = () => {
    let x = M;
    pg.drawRectangle({ x: M, y: y - 4, width: util, height: 16, color: rgb(0.93, 0.95, 0.98) });
    t.colunas.forEach((c, i) => { pg.drawText(cortar(c.rotulo, larg[i] - 6, fb), { x: x + 3, y, size: tam, font: fb, color: AZUL }); x += larg[i]; });
    y -= 18;
  };
  pg.drawText(paraWinAnsi(t.titulo), { x: M, y: y - 6, size: 15, font: fb, color: AZUL }); y -= 26;
  for (const f of [...t.filtros, `Gerado por ${t.geradoPor} em ${t.geradoEm.toLocaleString('pt-BR', { timeZone: 'America/Maceio' })} · ${t.linhas.length} linha(s)`]) {
    pg.drawText(cortar(f, util), { x: M, y, size: 9, font: fr, color: CINZA }); y -= 13;
  }
  y -= 8;
  cabecalhoTabela();
  if (!t.linhas.length) pg.drawText('Nenhum registro.', { x: M + 3, y, size: tam, font: fr, color: CINZA });
  for (const l of t.linhas) {
    if (y < M + 20) { pg = doc.addPage([W, H]); paginas.push(pg); y = H - M; cabecalhoTabela(); }
    let x = M;
    t.colunas.forEach((c, i) => {
      const txt = cortar(textoCelula(l[c.chave], c.tipo), larg[i] - 6);
      const num = c.tipo === 'moeda' || c.tipo === 'numero' || c.tipo === 'percentual';
      pg.drawText(txt, { x: num ? x + larg[i] - 3 - fr.widthOfTextAtSize(txt, tam) : x + 3, y, size: tam, font: fr, color: rgb(0.11, 0.14, 0.2) });
      x += larg[i];
    });
    pg.drawLine({ start: { x: M, y: y - 4 }, end: { x: W - M, y: y - 4 }, thickness: 0.4, color: LINHA });
    y -= 14;
  }
  paginas.forEach((p, i) => p.drawText(paraWinAnsi(`Gestão SEMFAZ · Prefeitura de Lagarto/SE · página ${i + 1} de ${paginas.length}`), { x: M, y: 16, size: 7, font: fr, color: CINZA }));
  return new Blob([(await doc.save()) as BlobPart], { type: 'application/pdf' });
}

export async function gerarArquivo(formato: Formato, t: Tabela): Promise<Blob> {
  return formato === 'csv' ? gerarCsv(t) : formato === 'xlsx' ? gerarXlsx(t) : gerarPdf(t);
}

export const nomeArquivo = (titulo: string, formato: Formato, d = new Date()) =>
  `${titulo.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^A-Za-z0-9]+/g, '-').replace(/^-|-$/g, '').toLowerCase()}-${d.toISOString().slice(0, 10)}.${formato}`;

export function baixar(blob: Blob, nome: string) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = nome;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 10000);
}
