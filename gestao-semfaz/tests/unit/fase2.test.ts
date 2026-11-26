import { describe, expect, it } from 'vitest';
import * as PDFLib from 'pdf-lib';
import { agruparPorUnidade, ehPdf, extrairMatricula, juntarPdfs, lerPaginas, montarPdfUnidade, type PaginaMapeada } from '@/lib/folhas';
import { COLUNAS_SALDOS, COLUNAS_SERVIDORES, lerCsv, mapearColunas, tipoPlanilha } from '@/lib/planilha';

async function pdfDeTeste(paginas: [string, string][]) {
  const doc = await PDFLib.PDFDocument.create();
  const f = await doc.embedFont(PDFLib.StandardFonts.Helvetica);
  for (const [nome, mat] of paginas) {
    const p = doc.addPage([595, 842]);
    p.drawText('PREFEITURA - FOLHA DE PONTO - NOVEMBRO/2026', { x: 40, y: 800, size: 10, font: f });
    p.drawText(`Nome: ${nome}`, { x: 40, y: 770, size: 10, font: f });
    p.drawText(`Matrícula: ${mat}`, { x: 340, y: 770, size: 10, font: f });
  }
  return doc.save();
}

async function pdfjsNode() {
  const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
  pdfjs.GlobalWorkerOptions.workerSrc = new URL('../../node_modules/pdfjs-dist/legacy/build/pdf.worker.mjs', import.meta.url).href;
  return pdfjs;
}

describe('folhas de ponto: leitura e separação', () => {
  it('extrai matrícula de textos variados', () => {
    expect(extrairMatricula('Nome: X Matrícula: 000101 Cargo')).toBe('000101');
    expect(extrairMatricula('MATRICULA 12.345-6')).toBe('12.345-6');
    expect(extrairMatricula('sem número aqui')).toBeNull();
  });

  it('lê um PDF real, agrupa por unidade e monta os PDFs com folha de rosto', async () => {
    const original = await pdfDeTeste([['Servidor E', '000102'], ['Servidor B', '000201'], ['Servidor X', '999999'], ['Servidor A', '000101']]);
    expect(ehPdf(original)).toBe(true);
    const lidas = await lerPaginas(await pdfjsNode() as never, original);
    expect(lidas.map((l) => l.matricula)).toEqual(['000102', '000201', '999999', '000101']);
    expect(lidas[0].nome).toBe('Servidor E');

    // simula o cruzamento feito no banco
    const banco: Record<string, [string, string, string, number]> = {
      '000101': ['Servidor A', 'u-cofit', 'COFIT', 2], '000102': ['Servidor E', 'u-cofit', 'COFIT', 2], '000201': ['Servidor B', 'u-conta', 'CONTA', 1],
    };
    const mapeadas: PaginaMapeada[] = lidas.map((l) => {
      const b = banco[l.matricula ?? ''];
      return { pagina: l.pagina, matricula_lida: l.matricula, nome_lido: l.nome, servidor: b?.[0] ?? null, unidade_id: b?.[1] ?? null, unidade: b?.[2] ?? null, ordem_unidade: b?.[3] ?? null };
    });
    const grupos = agruparPorUnidade(mapeadas);
    expect(grupos.map((g) => `${g.unidade}:${g.paginas.map((p) => p.servidor ?? '?').join(',')}`))
      .toEqual(['CONTA:Servidor B', 'COFIT:Servidor A,Servidor E', 'Não identificadas:?']);

    const lib = PDFLib as never;
    const cofit = await montarPdfUnidade(lib, original, grupos[1], '11/2026');
    const docCofit = await PDFLib.PDFDocument.load(cofit);
    expect(docCofit.getPageCount()).toBe(3); // rosto + 2
    const textoCofit = await lerPaginas(await pdfjsNode() as never, cofit);
    expect(textoCofit.map((p) => p.matricula)).toEqual([null, '000101', '000102']); // ordem alfabética
    const todos = await juntarPdfs(lib, await Promise.all(grupos.map((g) => montarPdfUnidade(lib, original, g, '11/2026'))));
    expect((await PDFLib.PDFDocument.load(todos)).getPageCount()).toBe(4 + 3); // 4 páginas + 3 rostos; nenhuma descartada
  });
});

describe('planilhas', () => {
  it('detecta tipo real (xlsx = zip; csv = texto) e recusa binário', () => {
    expect(tipoPlanilha(new Uint8Array([0x50, 0x4b, 0x03, 0x04]))).toBe('xlsx');
    expect(tipoPlanilha(new TextEncoder().encode('nome;matricula\n'))).toBe('csv');
    expect(tipoPlanilha(new Uint8Array([0x4d, 0x5a, 0x00, 0x01]))).toBeNull();
  });
  it('lê CSV com ; e aspas, e mapeia cabeçalhos com acento/maiúsculas', () => {
    const csv = '﻿Nome;Matrícula;Cargo;Unidade;E-mail institucional;Saldo de férias;Saldo de licença-prêmio;Saldo de folgas\r\n"Silva; José";000777;Auditor Fiscal;COFIT;;30;0;"2"\r\n;;;;;;;\r\n';
    const r = mapearColunas(lerCsv(csv), COLUNAS_SERVIDORES);
    expect(r.faltando).toEqual([]);
    expect(r.linhas).toEqual([{ linha: '2', nome: 'Silva; José', matricula: '000777', cargo: 'Auditor Fiscal', unidade: 'COFIT', email: '', ferias: '30', licenca_premio: '0', folgas: '2' }]);
  });
  it('aponta colunas obrigatórias faltando', () => {
    const r = mapearColunas([['matricula', 'ferias'], ['1', '2']], COLUNAS_SALDOS);
    expect(r.faltando).toEqual(['saldo de licença-prêmio', 'saldo de folgas']);
  });
});
