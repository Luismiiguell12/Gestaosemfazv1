// Folhas de ponto: leitura do PDF do RH e montagem dos PDFs por unidade.
// Roda no navegador de quem envia. O cruzamento matrícula → servidor → unidade é do banco.
// As bibliotecas são injetadas (pdfjs/pdf-lib) para os mesmos códigos rodarem nos testes em Node.
import type { PDFDocument as PDFDocumentT, PDFFont } from 'pdf-lib';

export const PDF_TAMANHO_MAX = 50 * 1024 * 1024;
export const REGEX_MATRICULA_PADRAO = 'Matr[íi]cula[^0-9A-Za-z]{0,10}([0-9][0-9./-]{0,19})';

export interface PaginaLida { pagina: number; matricula: string | null; nome: string | null }

type PdfJs = {
  getDocument: (o: { data: Uint8Array; isEvalSupported?: boolean; disableFontFace?: boolean; useSystemFonts?: boolean }) => { promise: Promise<PdfDoc> };
};
type PdfDoc = { numPages: number; getPage: (n: number) => Promise<{ getTextContent: () => Promise<{ items: unknown[] }> }>; destroy?: () => Promise<void> };

export function ehPdf(b: Uint8Array) {
  return b.length >= 5 && b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46 && b[4] === 0x2d;
}

export function extrairMatricula(texto: string, regex = REGEX_MATRICULA_PADRAO): string | null {
  const m = new RegExp(regex, 'i').exec(texto);
  return m?.[1]?.replace(/[./-]+$/, '') ?? null;
}

export function extrairNome(texto: string): string | null {
  const m = /Nome(?: do servidor)?\s*[:\-]?\s*([A-Za-zÀ-ÿ'][A-Za-zÀ-ÿ' ]{2,80}?)(?=\s{2,}|\s+Matr|\s+Cargo|$)/i.exec(texto);
  return m?.[1]?.trim() ?? null;
}

/** lê o texto de cada página e extrai matrícula/nome; PDF escaneado (sem texto) volta sem matrícula */
export async function lerPaginas(pdfjs: PdfJs, bytes: Uint8Array, regex?: string, progresso?: (n: number, total: number) => void): Promise<PaginaLida[]> {
  const doc = await pdfjs.getDocument({ data: bytes.slice(), isEvalSupported: false, disableFontFace: true, useSystemFonts: false }).promise;
  const out: PaginaLida[] = [];
  for (let i = 1; i <= doc.numPages; i++) {
    const conteudo = await (await doc.getPage(i)).getTextContent();
    const texto = conteudo.items.map((it) => (it as { str?: string }).str ?? '').join(' ').replace(/\s+/g, ' ');
    out.push({ pagina: i, matricula: extrairMatricula(texto, regex), nome: extrairNome(texto) });
    progresso?.(i, doc.numPages);
  }
  await doc.destroy?.();
  return out;
}

export interface PaginaMapeada { pagina: number; servidor: string | null; unidade_id: string | null; unidade: string | null; ordem_unidade: number | null; matricula_lida: string | null; nome_lido: string | null }
export interface GrupoUnidade { unidade_id: string | null; unidade: string; ordem: number; paginas: PaginaMapeada[]; servidores: number }

const collator = new Intl.Collator('pt-BR', { sensitivity: 'base' });

/** agrupa por unidade (ordem das unidades; "Não identificadas" no fim) e ordena servidores alfabeticamente */
export function agruparPorUnidade(paginas: PaginaMapeada[]): GrupoUnidade[] {
  const mapa = new Map<string, GrupoUnidade>();
  for (const p of paginas) {
    const k = p.unidade_id ?? 'sem-unidade';
    if (!mapa.has(k)) mapa.set(k, { unidade_id: p.unidade_id, unidade: p.unidade ?? 'Não identificadas', ordem: p.unidade_id ? (p.ordem_unidade ?? 0) : 1e9, paginas: [], servidores: 0 });
    mapa.get(k)!.paginas.push(p);
  }
  const grupos = [...mapa.values()];
  for (const g of grupos) {
    g.paginas.sort((a, b) => collator.compare(a.servidor ?? a.nome_lido ?? '', b.servidor ?? b.nome_lido ?? '') || a.pagina - b.pagina);
    g.servidores = new Set(g.paginas.map((p) => p.servidor ?? `p${p.pagina}`)).size;
  }
  return grupos.sort((a, b) => a.ordem - b.ordem || collator.compare(a.unidade, b.unidade));
}

type PdfLib = { PDFDocument: typeof PDFDocumentT; StandardFonts: { Helvetica: string; HelveticaBold: string }; rgb: (r: number, g: number, b: number) => unknown };

async function folhaDeRosto(lib: PdfLib, doc: PDFDocumentT, g: GrupoUnidade, competencia: string, fontes: { r: PDFFont; b: PDFFont }) {
  const pg = doc.addPage([595.28, 841.89]);
  const cor = lib.rgb(0.102, 0.149, 0.376) as never;
  pg.drawText('Gestão SEMFAZ · Prefeitura de Lagarto/SE', { x: 56, y: 770, size: 11, font: fontes.r, color: cor });
  pg.drawText('Folhas de ponto', { x: 56, y: 700, size: 16, font: fontes.r, color: cor });
  pg.drawText(g.unidade, { x: 56, y: 660, size: 32, font: fontes.b, color: cor });
  pg.drawText(`Competência: ${competencia}`, { x: 56, y: 620, size: 13, font: fontes.r, color: cor });
  pg.drawText(`${g.servidores} servidor(es) · ${g.paginas.length} página(s)`, { x: 56, y: 598, size: 13, font: fontes.r, color: cor });
}

/** PDF de uma unidade: folha de rosto + páginas em ordem alfabética */
export async function montarPdfUnidade(lib: PdfLib, original: Uint8Array, g: GrupoUnidade, competencia: string): Promise<Uint8Array> {
  const fonte = await lib.PDFDocument.load(original);
  const doc = await lib.PDFDocument.create();
  const fontes = { r: await doc.embedFont(lib.StandardFonts.Helvetica), b: await doc.embedFont(lib.StandardFonts.HelveticaBold) };
  await folhaDeRosto(lib, doc, g, competencia, fontes);
  const copias = await doc.copyPages(fonte, g.paginas.map((p) => p.pagina - 1));
  copias.forEach((c) => doc.addPage(c));
  doc.setTitle(`Folhas de ponto ${competencia} · ${g.unidade}`);
  return doc.save();
}

/** junta vários PDFs (já com folha de rosto) num só, na ordem dada */
export async function juntarPdfs(lib: PdfLib, arquivos: Uint8Array[]): Promise<Uint8Array> {
  const doc = await lib.PDFDocument.create();
  for (const a of arquivos) {
    const f = await lib.PDFDocument.load(a);
    (await doc.copyPages(f, f.getPageIndices())).forEach((p) => doc.addPage(p));
  }
  return doc.save();
}

export const nomeArquivoUnidade = (unidade: string) =>
  unidade.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^A-Za-z0-9]+/g, '_').replace(/^_|_$/g, '');
