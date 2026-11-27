// Leitura de planilha (CSV ou XLSX) como ENTRADA NÃO CONFIÁVEL:
// tipo real, tamanho, nº de linhas e colunas obrigatórias são conferidos aqui;
// valores são revalidados no banco (prévia) antes de gravar.

export const PLANILHA_TAMANHO_MAX = 2 * 1024 * 1024;
export const PLANILHA_LINHAS_MAX = 2000;

export interface ColunaPlanilha { chave: string; rotulo: string; aliases: string[]; obrigatoria: boolean }

export const COLUNAS_SERVIDORES: ColunaPlanilha[] = [
  { chave: 'nome', rotulo: 'nome', aliases: ['nome', 'nome completo', 'servidor'], obrigatoria: true },
  { chave: 'matricula', rotulo: 'matrícula', aliases: ['matricula', 'matricula funcional', 'mat'], obrigatoria: true },
  { chave: 'cargo', rotulo: 'cargo', aliases: ['cargo'], obrigatoria: true },
  { chave: 'unidade', rotulo: 'unidade', aliases: ['unidade', 'lotacao', 'sigla da unidade'], obrigatoria: true },
  { chave: 'email', rotulo: 'e-mail institucional', aliases: ['email', 'e mail', 'email institucional', 'e mail institucional'], obrigatoria: true },
  { chave: 'ferias', rotulo: 'saldo de férias', aliases: ['saldo de ferias', 'ferias', 'saldo ferias'], obrigatoria: true },
  { chave: 'licenca_premio', rotulo: 'saldo de licença-prêmio', aliases: ['saldo de licenca premio', 'licenca premio', 'saldo licenca premio'], obrigatoria: true },
  { chave: 'folgas', rotulo: 'saldo de folgas', aliases: ['saldo de folgas', 'folgas', 'saldo folgas'], obrigatoria: true },
  // adendo 01 (produtividade), seção 2
  { chave: 'tipo_vinculo', rotulo: 'tipo de vínculo', aliases: ['tipo de vinculo', 'vinculo', 'tipo vinculo'], obrigatoria: true },
  { chave: 'exerce_comissao', rotulo: 'cargo em comissão/função de confiança', aliases: ['cargo em comissao funcao de confianca', 'cargo em comissao', 'funcao de confianca', 'exerce comissao'], obrigatoria: false },
];

export const COLUNAS_SALDOS: ColunaPlanilha[] = [
  { chave: 'matricula', rotulo: 'matrícula', aliases: ['matricula', 'matricula funcional', 'mat'], obrigatoria: true },
  { chave: 'ferias', rotulo: 'saldo de férias', aliases: ['saldo de ferias', 'ferias', 'saldo ferias'], obrigatoria: true },
  { chave: 'licenca_premio', rotulo: 'saldo de licença-prêmio', aliases: ['saldo de licenca premio', 'licenca premio', 'saldo licenca premio'], obrigatoria: true },
  { chave: 'folgas', rotulo: 'saldo de folgas', aliases: ['saldo de folgas', 'folgas', 'saldo folgas'], obrigatoria: true },
];

// Contratos e faturas: colunas PROVISÓRIAS (modelo oficial pendente — seção 9)
export const COLUNAS_CONTRATOS: ColunaPlanilha[] = [
  { chave: 'numero', rotulo: 'número do contrato', aliases: ['numero do contrato', 'numero', 'contrato', 'n do contrato'], obrigatoria: true },
  { chave: 'processo', rotulo: 'processo', aliases: ['processo', 'numero do processo', 'n do processo'], obrigatoria: false },
  { chave: 'locador_tipo', rotulo: 'tipo do locador (PF/PJ)', aliases: ['tipo do locador pf pj', 'tipo do locador', 'pf pj', 'tipo'], obrigatoria: true },
  { chave: 'locador_nome', rotulo: 'locador', aliases: ['locador', 'nome do locador'], obrigatoria: true },
  { chave: 'locador_documento', rotulo: 'CPF/CNPJ do locador', aliases: ['cpf cnpj do locador', 'cpf cnpj', 'cpf', 'cnpj', 'documento'], obrigatoria: true },
  { chave: 'locador_email', rotulo: 'e-mail do locador', aliases: ['e mail do locador', 'email do locador', 'email', 'e mail'], obrigatoria: false },
  { chave: 'locador_telefone', rotulo: 'telefone do locador', aliases: ['telefone do locador', 'telefone'], obrigatoria: false },
  { chave: 'imovel_descricao', rotulo: 'imóvel', aliases: ['imovel', 'descricao do imovel'], obrigatoria: true },
  { chave: 'imovel_endereco', rotulo: 'endereço', aliases: ['endereco', 'endereco do imovel'], obrigatoria: false },
  { chave: 'unidade', rotulo: 'unidade ocupante', aliases: ['unidade ocupante', 'unidade', 'sigla da unidade'], obrigatoria: false },
  { chave: 'inicio', rotulo: 'início da vigência', aliases: ['inicio da vigencia', 'inicio'], obrigatoria: true },
  { chave: 'fim', rotulo: 'fim da vigência', aliases: ['fim da vigencia', 'fim', 'termino'], obrigatoria: true },
  { chave: 'valor_mensal', rotulo: 'valor mensal', aliases: ['valor mensal', 'valor', 'aluguel'], obrigatoria: true },
  { chave: 'dia_vencimento', rotulo: 'dia de vencimento', aliases: ['dia de vencimento', 'vencimento', 'dia'], obrigatoria: false },
  { chave: 'fiscal_matricula', rotulo: 'matrícula do fiscal', aliases: ['matricula do fiscal', 'fiscal matricula', 'fiscal'], obrigatoria: false },
  { chave: 'indice_reajuste', rotulo: 'índice de reajuste', aliases: ['indice de reajuste', 'indice'], obrigatoria: false },
  { chave: 'mes_database', rotulo: 'mês da data-base', aliases: ['mes da data base', 'data base', 'mes data base'], obrigatoria: false },
];

export const COLUNAS_FATURAS: ColunaPlanilha[] = [
  { chave: 'fornecedor', rotulo: 'fornecedor', aliases: ['fornecedor', 'concessionaria'], obrigatoria: true },
  { chave: 'uc', rotulo: 'unidade consumidora', aliases: ['unidade consumidora', 'uc', 'matricula', 'numero da uc'], obrigatoria: true },
  { chave: 'competencia', rotulo: 'competência (mm/aaaa)', aliases: ['competencia mm aaaa', 'competencia', 'mes referencia', 'referencia'], obrigatoria: true },
  { chave: 'consumo', rotulo: 'consumo', aliases: ['consumo', 'consumo kwh m3', 'kwh', 'm3'], obrigatoria: false },
  { chave: 'valor', rotulo: 'valor', aliases: ['valor', 'valor da fatura'], obrigatoria: true },
  { chave: 'vencimento', rotulo: 'vencimento', aliases: ['vencimento', 'data de vencimento'], obrigatoria: true },
  { chave: 'pago_em', rotulo: 'pago em', aliases: ['pago em', 'data do pagamento', 'pagamento'], obrigatoria: false },
];

export const normalizarCabecalho = (t: string) =>
  t.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

export type TipoPlanilha = 'csv' | 'xlsx';

export function tipoPlanilha(inicio: Uint8Array): TipoPlanilha | null {
  if (inicio.length >= 4 && inicio[0] === 0x50 && inicio[1] === 0x4b && inicio[2] === 0x03 && inicio[3] === 0x04) return 'xlsx'; // ZIP
  if (inicio.length === 0) return null;
  // texto: sem bytes nulos nem de controle (exceto tab/CR/LF)
  return Array.from(inicio).every((b) => b === 9 || b === 10 || b === 13 || b >= 32) ? 'csv' : null;
}

/** CSV com ; ou , e aspas */
export function lerCsv(texto: string): string[][] {
  const t = texto.replace(/^﻿/, '');
  const primeira = t.split(/\r?\n/, 1)[0] ?? '';
  const sep = (primeira.match(/;/g)?.length ?? 0) >= (primeira.match(/,/g)?.length ?? 0) ? ';' : ',';
  const linhas: string[][] = [];
  let campo = '', linha: string[] = [], aspas = false;
  for (let i = 0; i < t.length; i++) {
    const ch = t[i];
    if (aspas) {
      if (ch === '"' && t[i + 1] === '"') { campo += '"'; i++; }
      else if (ch === '"') aspas = false;
      else campo += ch;
    } else if (ch === '"') aspas = true;
    else if (ch === sep) { linha.push(campo); campo = ''; }
    else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && t[i + 1] === '\n') i++;
      linha.push(campo); linhas.push(linha); linha = []; campo = '';
    } else campo += ch;
  }
  if (campo !== '' || linha.length) { linha.push(campo); linhas.push(linha); }
  return linhas.filter((l) => l.some((c) => c.trim() !== ''));
}

export interface ResultadoPlanilha { linhas: Record<string, string>[]; faltando: string[]; erro?: string }

/** célula → texto; data do Excel vira aaaa-mm-dd (o banco aceita dd/mm/aaaa ou ISO) */
export const celula = (v: unknown) => (v instanceof Date ? (isNaN(v.getTime()) ? '' : v.toISOString().slice(0, 10)) : String(v ?? '').trim());

/** converte matriz (1ª linha = cabeçalho) em objetos com as chaves do sistema; nº da linha = linha na planilha */
export function mapearColunas(matriz: unknown[][], colunas: ColunaPlanilha[]): ResultadoPlanilha {
  if (matriz.length < 2) return { linhas: [], faltando: [], erro: 'A planilha não tem linhas de dados.' };
  if (matriz.length - 1 > PLANILHA_LINHAS_MAX) return { linhas: [], faltando: [], erro: `Máximo de ${PLANILHA_LINHAS_MAX} linhas por importação.` };
  const cab = matriz[0].map((c) => normalizarCabecalho(String(c ?? '')));
  const idx = new Map<string, number>();
  for (const col of colunas) {
    const i = cab.findIndex((h) => col.aliases.includes(h));
    if (i >= 0) idx.set(col.chave, i);
  }
  const faltando = colunas.filter((c) => c.obrigatoria && !idx.has(c.chave)).map((c) => c.rotulo);
  if (faltando.length) return { linhas: [], faltando };
  const linhas = matriz.slice(1).map((l, n) => {
    const o: Record<string, string> = { linha: String(n + 2) };
    for (const [chave, i] of idx) o[chave] = celula(l[i]).slice(0, 300);
    return o;
  }).filter((o) => Object.entries(o).some(([k, v]) => k !== 'linha' && v !== ''));
  return { linhas, faltando: [] };
}

export async function lerPlanilha(arquivo: File, colunas: ColunaPlanilha[]): Promise<ResultadoPlanilha> {
  if (arquivo.size === 0) return { linhas: [], faltando: [], erro: 'Arquivo vazio.' };
  if (arquivo.size > PLANILHA_TAMANHO_MAX) return { linhas: [], faltando: [], erro: 'Arquivo maior que 2 MB.' };
  const tipo = tipoPlanilha(new Uint8Array(await arquivo.slice(0, 512).arrayBuffer()));
  if (!tipo) return { linhas: [], faltando: [], erro: 'Tipo não aceito. Envie .xlsx ou .csv.' };
  try {
    if (tipo === 'csv') return mapearColunas(lerCsv(await arquivo.text()), colunas);
    const { readSheet } = await import('read-excel-file/browser');
    const linhas = await readSheet(arquivo);
    return mapearColunas(linhas as unknown[][], colunas);
  } catch {
    return { linhas: [], faltando: [], erro: 'Não foi possível ler a planilha.' };
  }
}

/** modelo em CSV (abre no Excel); ; como separador e BOM para acentos */
export function modeloCsv(colunas: ColunaPlanilha[], exemplo: string[]): Blob {
  const linha = (v: string[]) => v.map((c) => (/[;"\n]/.test(c) ? `"${c.replace(/"/g, '""')}"` : c)).join(';');
  return new Blob(['﻿' + linha(colunas.map((c) => c.rotulo)) + '\r\n' + linha(exemplo) + '\r\n'], { type: 'text/csv;charset=utf-8' });
}
