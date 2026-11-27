import { unzipSync, strFromU8 } from 'fflate';
import { PDFDocument } from 'pdf-lib';
import { describe, expect, it } from 'vitest';
import { gerarCsv, gerarPdf, gerarXlsx, neutralizarFormula, nomeArquivo, paraWinAnsi, textoCelula, type Tabela } from '@/lib/exportar';
import { podeRelatorio, prepararLinhas, RELATORIOS } from '@/lib/relatorios';

const T = (linhas: Record<string, unknown>[] = []): Tabela => ({
  titulo: 'Aluguéis', filtros: ['Competências: 01/2026 a 03/2026'], geradoPor: 'Secretária Exemplo', geradoEm: new Date('2026-11-27T12:00:00Z'),
  colunas: [{ chave: 'contrato', rotulo: 'Contrato' }, { chave: 'valor', rotulo: 'Valor', tipo: 'moeda' }, { chave: 'venc', rotulo: 'Vencimento', tipo: 'data' }, { chave: 'obs', rotulo: 'Obs.' }],
  linhas,
});

describe('formatação de células', () => {
  it('moeda, data e booleano no padrão brasileiro', () => {
    expect(textoCelula(1234.5, 'moeda').replace(/\s/g, ' ')).toBe('R$ 1.234,50');
    expect(textoCelula('2026-02-10', 'data')).toBe('10/02/2026');
    expect(textoCelula(true)).toBe('Sim');
    expect(textoCelula(null, 'moeda')).toBe('');
  });
  it('neutraliza fórmulas (CSV injection) e troca caracteres fora do WinAnsi', () => {
    for (const f of ['=HYPERLINK("x")', '+1', '-1+2', '@SUM(A1)']) expect(neutralizarFormula(f).startsWith("'")).toBe(true);
    expect(neutralizarFormula('Contrato 1')).toBe('Contrato 1');
    expect(paraWinAnsi('Ação · nº 1 ≥ 2 – ok ✓')).toBe('Ação · nº 1 >= 2 – ok ?');
    expect(nomeArquivo('Saldos de férias e folgas', 'xlsx', new Date('2026-11-27T12:00:00Z'))).toBe('saldos-de-ferias-e-folgas-2026-11-27.xlsx');
  });
});

describe('arquivos gerados', () => {
  const linhas = [{ contrato: '014/2024', valor: 3740, venc: '2026-02-10', obs: '=cmd|"/c calc"!A1' }, { contrato: 'Ação; "aspas"', valor: null, venc: null, obs: 'linha\nquebrada' }];

  it('CSV: BOM, ; e aspas escapadas, fórmula neutralizada', async () => {
    const bytes = new Uint8Array(await gerarCsv(T(linhas)).arrayBuffer());
    expect([...bytes.slice(0, 3)]).toEqual([0xef, 0xbb, 0xbf]);
    const txt = '\uFEFF' + new TextDecoder().decode(bytes);
    const l = txt.slice(1).split('\r\n');
    expect(l[0]).toBe('Contrato;Valor;Vencimento;Obs.');
    expect(l[1]).toContain(`;10/02/2026;"'=cmd|""/c calc""!A1"`);
    expect(txt).toContain('"Ação; ""aspas"""');
  });

  it('Excel: pacote válido, número como número, data como série, texto escapado', async () => {
    const z = unzipSync(new Uint8Array(await (await gerarXlsx(T(linhas))).arrayBuffer()));
    expect(Object.keys(z).sort()).toEqual(['[Content_Types].xml', '_rels/.rels', 'xl/_rels/workbook.xml.rels', 'xl/styles.xml', 'xl/workbook.xml', 'xl/worksheets/sheet1.xml']);
    const s = strFromU8(z['xl/worksheets/sheet1.xml']);
    expect(s).toContain('<v>3740</v>');
    expect(s).toContain(`<v>${(Date.UTC(2026, 1, 10) - Date.UTC(1899, 11, 30)) / 86400000}</v>`);
    expect(s).toContain('Ação; &quot;aspas&quot;');
    expect(s).toContain('<autoFilter ref="A5:D7"/>');
    expect(s).not.toContain('<f>'); // nada de fórmula
  });

  it('PDF: abre, tem título e quebra páginas em listas longas', async () => {
    const muitas = Array.from({ length: 120 }, (_, i) => ({ contrato: `${i}/2026`, valor: 100 + i, venc: '2026-02-10', obs: 'Observação com acentuação – ok' }));
    const pdf = await PDFDocument.load(new Uint8Array(await (await gerarPdf(T(muitas))).arrayBuffer()));
    expect(pdf.getTitle()).toBe('Aluguéis');
    expect(pdf.getPageCount()).toBeGreaterThan(2);
    const vazio = await PDFDocument.load(new Uint8Array(await (await gerarPdf(T())).arrayBuffer()));
    expect(vazio.getPageCount()).toBe(1);
  });
});

describe('catálogo de relatórios', () => {
  it('protótipo: 4 grupos com 3 relatórios cada (+ folhas de ponto); produtividade pendente', () => {
    const grupos = [...new Set(RELATORIOS.map((r) => r.grupo))];
    expect(grupos).toEqual(['Demandas e produtividade', 'Contratos de locação', 'Água e energia', 'Pessoas e controle']);
    expect(RELATORIOS.find((r) => r.id === 'produtividade')?.pendente).toBeTruthy();
    for (const r of RELATORIOS.filter((x) => !x.pendente)) expect(r.rpc && r.colunas.length).toBeTruthy();
  });
  it('acesso no navegador segue módulos e perfil', () => {
    const cont = RELATORIOS.find((r) => r.id === 'contratos')!;
    const fat = RELATORIOS.find((r) => r.id === 'faturas')!;
    const aud = RELATORIOS.find((r) => r.id === 'auditoria')!;
    expect(podeRelatorio(cont, ['relatorios'], false)).toBe(false);
    expect(podeRelatorio(cont, ['relatorios', 'contratos'], false)).toBe(true);
    expect(podeRelatorio(cont, ['contratos'], true)).toBe(false);
    expect(podeRelatorio(fat, ['relatorios', 'unidades_consumidoras'], false)).toBe(true);
    expect(podeRelatorio(aud, ['relatorios', 'auditoria'], false)).toBe(false);
    expect(podeRelatorio(aud, ['relatorios', 'auditoria'], true)).toBe(true);
  });
  it('rótulos legíveis para os códigos do banco', () => {
    expect(prepararLinhas('faturas', [{ fornecedor: 'igua', situacao: 'vencida' }])[0]).toMatchObject({ fornecedor_rotulo: 'Iguá', situacao_rotulo: 'Vencida' });
    expect(prepararLinhas('escala_ferias', [{ tipo: 'licenca_premio', situacao: 'aprovado' }])[0]).toMatchObject({ tipo_rotulo: 'Licença-prêmio', situacao_rotulo: 'Aprovado' });
  });
});
