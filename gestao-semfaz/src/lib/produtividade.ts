// Produtividade (Adendo 01): tipos, rótulos e documentos (Anexo I e Anexo II) gerados no navegador.
import type { TomSelo } from '@/components/ui';
import { paraWinAnsi, textoCelula } from './exportar';

export type StatusAv = 'rascunho' | 'enviada' | 'ciente' | 'em_recurso' | 'aguardando_homologacao' | 'homologada' | 'retificada';
export const ROTULO_STATUS_AV: Record<StatusAv, string> = {
  rascunho: 'Rascunho', enviada: 'Enviada', ciente: 'Ciente', em_recurso: 'Em recurso', aguardando_homologacao: 'Aguardando homologação',
  homologada: 'Homologada', retificada: 'Retificada',
};
export const TOM_STATUS_AV: Record<StatusAv, TomSelo> = {
  rascunho: 'neutro', enviada: 'info', ciente: 'info', em_recurso: 'alerta', aguardando_homologacao: 'alerta', homologada: 'positivo', retificada: 'neutro',
};
export const TIPO_PROVA: Record<string, string> = { demanda: 'Demanda', checklist: 'Etapa do checklist', mensagem: 'Mensagem/feedback', anexo: 'Anexo', externa: 'Referência externa' };
export const HISTORICO_AV: Record<string, string> = {
  aberta: 'Avaliação aberta', periodo_dividido: 'Período dividido (mudança no mês)', periodo_criado: 'Período parcial criado', avaliador_trocado: 'Chefia avaliadora alterada',
  enviada: 'Enviada ao servidor', ciente: 'Ciência registrada', recurso: 'Recurso apresentado', recurso_decidido: 'Recurso decidido', sem_recurso: 'Prazo de recurso esgotado sem recurso',
  homologada: 'Homologada', devolvida: 'Devolvida à chefia', retificada: 'Retificada', retificacao_aberta: 'Retificação aberta',
};
export const AVISO_DECRETO = 'Avaliação conforme o Decreto do Adicional de Desempenho e Produtividade (minuta — Adendo 01).';

export interface Indicador { codigo: string; nome: string; maximo: number }
export interface Nota { indicador: string; nota: number | null; justificativa: string | null; equivalente: boolean; justificativa_equivalente: string | null }
export interface Prova { id: string; indicador: string; tipo: string; ref_id: string | null; path: string | null; nome: string | null; descricao: string | null; titulo: string | null; demanda_id: string | null; criado_em: string }
export interface Recurso { id: string; razoes: string; anexo_path: string | null; criado_em: string; prazo_revisao: string; revisor: string | null; fundamentacao: string | null; decidido_em: string | null;
  notas_antes: Record<string, { nota: number }> | null; notas_depois: Record<string, { nota: number }> | null }
export interface Detalhe {
  avaliacao: { id: string; competencia: string; servidor_id: string; servidor: string; matricula: string; cargo: string | null; exerce_comissao: boolean; unidade: string | null;
    avaliador: string | null; avaliador_id: string | null; periodo_inicio: string; periodo_fim: string; status: StatusAv; limitacoes: string | null; total_funcional: number | null;
    enviada_em: string | null; ciente_em: string | null; ciencia_meio: string | null; ciencia_anexo: string | null; ciencia_registrada_por_nome: string | null; prazo_recurso: string | null;
    homologada_em: string | null; homologada_por_nome: string | null; devolucao_motivo: string | null; retifica_id: string | null; retificacao_justificativa: string | null };
  regra: { versao: number; indicadores: Indicador[]; max_funcional: number; prazos: Record<string, number> };
  notas: Nota[]; provas: Prova[]; recursos: Recurso[];
  historico: { em: string; acao: string; detalhes: Record<string, unknown>; ator: string | null }[];
  pendencias_envio: string[];
  permissoes: { editar: boolean; ciencia: boolean; ciencia_outro_meio: boolean; recorrer: boolean; decidir_recurso: boolean; homologar: boolean; retificar: boolean; gerir: boolean };
}
export interface Demonstrativo {
  servidor: string; matricula: string; cargo: string | null; unidade: string | null; competencia: string; provisorio?: boolean; homologado_em?: string; versao?: number;
  regra_versao: number; transicao: boolean; pontos_funcionais: number; pontos_institucionais: number | null; nota_total: number; nota_enquadramento: number;
  minimo_funcional_atingido: boolean; minimo_total_atingido: boolean; motivo_zero: string | null; percentual: number; dias_elegiveis: number; dias_mes: number;
  fator: number; percentual_efetivo: number; valor?: number | null; vencimento_basico?: number | null;
  periodos: { avaliacao_id: string; inicio: string; fim: string; status: StatusAv; pontos: number; dias_elegiveis: number; avaliador: string | null }[];
  institucional: { ano: number; quadrimestre: number; pontos: number; homologado_em: string; memoria: Memoria } | null;
}
export interface Memoria { pontos: number; soma_contribuicoes: number; max_institucional: number; regra_versao: number;
  receitas: { receita: string; nome: string; meta: number; arrecadado: number; indice: number; peso: number; contribuicao: number }[] }

const NUM = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 4 });
export const num = (v: number | string | null | undefined) => (v === null || v === undefined || v === '' ? '—' : NUM.format(Number(v)));
export const pct = (v: number | string | null | undefined) => (v === null || v === undefined ? '—' : `${NUM.format(Number(v))}%`);
const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
export const nomeCompetencia = (iso: string) => { const [a, m] = iso.split('-'); return `${MESES[Number(m) - 1]} de ${a}`; };
export const QUADRIMESTRE = ['', 'jan–abr', 'mai–ago', 'set–dez'];

/** linhas do arquivo de encaminhamento à SEMAD (XLSX/CSV) */
export const COLUNAS_SEMAD = [
  { chave: 'servidor', rotulo: 'Servidor' }, { chave: 'matricula', rotulo: 'Matrícula', largura: 1.3 }, { chave: 'cargo', rotulo: 'Cargo efetivo', largura: 1.8 },
  { chave: 'unidade', rotulo: 'Unidade', largura: 1.1 }, { chave: 'competencia', rotulo: 'Competência', tipo: 'data' as const },
  { chave: 'pontos_funcionais', rotulo: 'Pontuação funcional', tipo: 'numero' as const }, { chave: 'pontos_institucionais', rotulo: 'Pontuação institucional', tipo: 'numero' as const },
  { chave: 'quadrimestre_ref', rotulo: 'Quadrimestre de referência', largura: 1.6 }, { chave: 'nota_total', rotulo: 'Nota total', tipo: 'numero' as const },
  { chave: 'nota_enquadramento', rotulo: 'Nota de enquadramento', tipo: 'numero' as const }, { chave: 'percentual', rotulo: 'Percentual (%)', tipo: 'numero' as const },
  { chave: 'dias_elegiveis', rotulo: 'Dias elegíveis', tipo: 'numero' as const }, { chave: 'dias_mes', rotulo: 'Dias do mês', tipo: 'numero' as const },
  { chave: 'fator', rotulo: 'Fator', tipo: 'numero' as const }, { chave: 'percentual_efetivo', rotulo: 'Percentual efetivo (%)', tipo: 'numero' as const },
];
export function linhaSemad(d: Demonstrativo): Record<string, unknown> {
  return { ...d, quadrimestre_ref: d.institucional ? `${d.institucional.quadrimestre}º/${d.institucional.ano}` : 'Transição (§ 12 do art. 15-B)',
    pontos_institucionais: d.pontos_institucionais ?? null };
}

// ===== PDFs (A4 retrato): Anexo I e Anexo II =====
type Pdf = { doc: import('pdf-lib').PDFDocument; pg: import('pdf-lib').PDFPage; y: number; fr: import('pdf-lib').PDFFont; fb: import('pdf-lib').PDFFont; rgb: typeof import('pdf-lib').rgb };
const [W, H, M] = [595.28, 841.89, 42];

async function novoPdf(titulo: string): Promise<Pdf> {
  const { PDFDocument, StandardFonts, rgb } = await import('pdf-lib');
  const doc = await PDFDocument.create();
  doc.setTitle(titulo); doc.setProducer('Gestão SEMFAZ'); doc.setCreator('Gestão SEMFAZ');
  const p: Pdf = { doc, pg: doc.addPage([W, H]), y: H - M, fr: await doc.embedFont(StandardFonts.Helvetica), fb: await doc.embedFont(StandardFonts.HelveticaBold), rgb };
  texto(p, 'PREFEITURA MUNICIPAL DE LAGARTO/SE · SECRETARIA MUNICIPAL DA FAZENDA', 8, true);
  p.y -= 4; texto(p, titulo, 13, true); p.y -= 6;
  return p;
}
function quebrar(p: Pdf, t: string, tam: number, larg: number, bold = false): string[] {
  const f = bold ? p.fb : p.fr; const out: string[] = [];
  for (const par of paraWinAnsi(t).split('\n')) {
    let linha = '';
    for (const pal of par.split(' ')) {
      const tent = linha ? `${linha} ${pal}` : pal;
      if (f.widthOfTextAtSize(tent, tam) > larg && linha) { out.push(linha); linha = pal; } else linha = tent;
    }
    out.push(linha);
  }
  return out;
}
function espaco(p: Pdf, h: number) { if (p.y - h < M) { p.pg = p.doc.addPage([W, H]); p.y = H - M; } }
function texto(p: Pdf, t: string, tam = 9, bold = false, x = M, larg = W - 2 * M) {
  for (const l of quebrar(p, t, tam, larg, bold)) { espaco(p, tam + 3); p.pg.drawText(l, { x, y: p.y - tam, size: tam, font: bold ? p.fb : p.fr, color: p.rgb(0.1, 0.14, 0.25) }); p.y -= tam + 3; }
}
function secao(p: Pdf, t: string) { p.y -= 8; espaco(p, 30); p.pg.drawRectangle({ x: M, y: p.y - 14, width: W - 2 * M, height: 16, color: p.rgb(0.92, 0.94, 0.98) }); p.pg.drawText(paraWinAnsi(t), { x: M + 4, y: p.y - 10, size: 9, font: p.fb, color: p.rgb(0.1, 0.15, 0.38) }); p.y -= 20; }
function campos(p: Pdf, pares: [string, string][]) { for (const [k, v] of pares) texto(p, `${k}: ${v || '—'}`, 9); }
function tabela(p: Pdf, cols: { t: string; w: number; dir?: boolean }[], linhas: string[][]) {
  const tot = cols.reduce((a, c) => a + c.w, 0); const ws = cols.map((c) => (c.w / tot) * (W - 2 * M));
  const linha = (vals: string[], bold: boolean) => {
    const partes = vals.map((v, i) => quebrar(p, v, 8, ws[i] - 6, bold));
    const h = Math.max(...partes.map((x) => x.length)) * 10 + 4;
    espaco(p, h);
    let x = M;
    partes.forEach((ls, i) => { ls.forEach((l, j) => { const f = bold ? p.fb : p.fr; const xx = cols[i].dir ? x + ws[i] - 3 - f.widthOfTextAtSize(l, 8) : x + 3;
      p.pg.drawText(l, { x: xx, y: p.y - 9 - j * 10, size: 8, font: f, color: p.rgb(0.1, 0.14, 0.25) }); }); x += ws[i]; });
    p.y -= h; p.pg.drawLine({ start: { x: M, y: p.y + 1 }, end: { x: W - M, y: p.y + 1 }, thickness: 0.4, color: p.rgb(0.85, 0.87, 0.9) });
  };
  linha(cols.map((c) => c.t), true);
  linhas.forEach((l) => linha(l, false));
}
async function fechar(p: Pdf): Promise<Blob> {
  const pags = p.doc.getPages();
  pags.forEach((pg, i) => pg.drawText(paraWinAnsi(`Gestão SEMFAZ · gerado em ${new Date().toLocaleString('pt-BR', { timeZone: 'America/Maceio' })} · página ${i + 1} de ${pags.length}`), { x: M, y: 18, size: 7, font: p.fr, color: p.rgb(0.4, 0.44, 0.5) }));
  return new Blob([(await p.doc.save()) as BlobPart], { type: 'application/pdf' });
}
const dh = (v: string | null | undefined) => (v ? textoCelula(v, 'dataHora') : '—');
const dt = (v: string | null | undefined) => (v ? textoCelula(v, 'data') : '—');

/** Anexo I – Formulário de Avaliação Mensal do Desempenho Funcional */
export async function pdfAnexoI(D: Detalhe): Promise<Blob> {
  const a = D.avaliacao;
  const p = await novoPdf('ANEXO I – FORMULÁRIO DE AVALIAÇÃO MENSAL DO DESEMPENHO FUNCIONAL');
  secao(p, 'Identificação');
  campos(p, [['Servidor', a.servidor], ['Matrícula', a.matricula], ['Cargo efetivo', a.cargo ?? ''], ['Função exercida', a.exerce_comissao ? 'Cargo em comissão/função de confiança' : 'Não exerce'],
    ['Unidade', a.unidade ?? ''], ['Mês/ano', nomeCompetencia(a.competencia)], ['Período avaliado', `${dt(a.periodo_inicio)} a ${dt(a.periodo_fim)}`], ['Regra aplicada', `versão ${D.regra.versao}`]]);
  secao(p, 'Indicadores');
  const nota = (c: string) => D.notas.find((n) => n.indicador === c);
  tabela(p, [{ t: 'Código', w: 0.7 }, { t: 'Indicador', w: 4 }, { t: 'Máximo', w: 0.9, dir: true }, { t: 'Atribuído', w: 1, dir: true }],
    D.regra.indicadores.map((i) => [i.codigo, i.nome, num(i.maximo), num(nota(i.codigo)?.nota ?? null)]));
  texto(p, `Total: ${num(D.notas.reduce((s, n) => s + Number(n.nota ?? 0), 0))} / ${num(D.regra.max_funcional)}`, 10, true);
  secao(p, 'Justificativas, critérios equivalentes e provas');
  for (const i of D.regra.indicadores) {
    const n = nota(i.codigo);
    texto(p, `${i.codigo} – ${i.nome}`, 9, true);
    texto(p, `Justificativa: ${n?.justificativa ?? '—'}`);
    if (n?.equivalente) texto(p, `Critério equivalente: ${n.justificativa_equivalente ?? '—'}`);
    for (const pr of D.provas.filter((x) => x.indicador === i.codigo)) texto(p, `• ${TIPO_PROVA[pr.tipo] ?? pr.tipo}: ${pr.titulo ?? pr.descricao ?? pr.nome ?? ''}`, 8, false, M + 10, W - 2 * M - 10);
    p.y -= 4;
  }
  if (a.limitacoes) { secao(p, 'Limitações estruturais ou operacionais'); texto(p, a.limitacoes); }
  secao(p, 'Ciência e chefia');
  campos(p, [['Chefia imediata', a.avaliador ?? ''], ['Enviada em', dh(a.enviada_em)],
    ['Ciência do servidor', a.ciente_em ? `${dh(a.ciente_em)} (${a.ciencia_meio === 'outro_meio' ? `outro meio, registrada por ${a.ciencia_registrada_por_nome ?? ''}` : 'no sistema'})` : 'pendente']]);
  return fechar(p);
}

/** Anexo II – Demonstrativo de Apuração (blocos I a V) */
export async function pdfAnexoII(d: Demonstrativo, extra: { recursos?: Recurso[]; homologacao?: string; encaminhamento?: string } = {}): Promise<Blob> {
  const p = await novoPdf('ANEXO II – DEMONSTRATIVO DE APURAÇÃO DO ADICIONAL DE DESEMPENHO E PRODUTIVIDADE');
  if (d.provisorio) texto(p, 'PROVISÓRIO: ainda não homologado.', 9, true);
  secao(p, 'I – Identificação');
  campos(p, [['Servidor', d.servidor], ['Matrícula', d.matricula], ['Cargo efetivo', d.cargo ?? ''], ['Unidade', d.unidade ?? ''], ['Competência', nomeCompetencia(d.competencia)], ['Regra aplicada', `versão ${d.regra_versao}`]]);
  secao(p, 'II – Desempenho funcional (até 70 pontos)');
  tabela(p, [{ t: 'Período', w: 2 }, { t: 'Chefia', w: 2.5 }, { t: 'Pontos', w: 1, dir: true }, { t: 'Dias elegíveis', w: 1.2, dir: true }],
    d.periodos.map((x) => [`${dt(x.inicio)} a ${dt(x.fim)}`, x.avaliador ?? '—', num(x.pontos), String(x.dias_elegiveis)]));
  texto(p, `Pontuação funcional do mês${d.periodos.length > 1 ? ' (média ponderada pelos dias elegíveis)' : ''}: ${num(d.pontos_funcionais)}`, 9, true);
  secao(p, 'III – Desempenho institucional (até 30 pontos)');
  if (!d.institucional) texto(p, 'Sem resultado institucional homologado: aplicada a regra de transição – § 12 do art. 15-B (nota = funcional / 70 × 100).', 9, true);
  else {
    texto(p, `Quadrimestre de referência: ${d.institucional.quadrimestre}º/${d.institucional.ano} (${QUADRIMESTRE[d.institucional.quadrimestre]}), homologado em ${dh(d.institucional.homologado_em)}`);
    tabela(p, [{ t: 'Receita', w: 2.2 }, { t: 'Meta', w: 1.3, dir: true }, { t: 'Arrecadado', w: 1.3, dir: true }, { t: 'Índice', w: 0.8, dir: true }, { t: 'Peso', w: 0.8, dir: true }, { t: 'Contribuição', w: 1, dir: true }],
      d.institucional.memoria.receitas.map((r) => [r.nome, num(r.meta), num(r.arrecadado), num(r.indice), pct(Number(r.peso) * 100), num(r.contribuicao)]));
    texto(p, `Soma ${num(d.institucional.memoria.soma_contribuicoes)} × 30 = ${num(d.institucional.pontos)} pontos`, 9, true);
  }
  secao(p, 'IV – Nota, mínimos e percentual');
  campos(p, [['Nota total', num(d.nota_total)], ['Nota de enquadramento (fração desprezada)', String(d.nota_enquadramento)],
    ['Mínimo funcional (≥ 42) atingido', d.minimo_funcional_atingido ? 'Sim' : 'Não'], ['Mínimo de nota (≥ 60) atingido', d.minimo_total_atingido ? 'Sim' : 'Não'],
    ['Percentual', pct(d.percentual)], ...(d.motivo_zero ? [['Motivo do percentual zero', d.motivo_zero] as [string, string]] : []),
    ['Dias de exercício elegível / dias do mês', `${d.dias_elegiveis} / ${d.dias_mes}`], ['Fator de proporcionalidade', num(d.fator)], ['Percentual efetivo', pct(d.percentual_efetivo)],
    ...(d.valor !== undefined ? [['Valor (R$)', d.valor === null ? '—' : textoCelula(d.valor, 'moeda')] as [string, string]] : [])]);
  secao(p, 'V – Recurso, homologação e encaminhamento');
  const rec = extra.recursos ?? [];
  texto(p, rec.length ? rec.map((r) => `Recurso em ${dh(r.criado_em)}; decisão ${r.decidido_em ? `em ${dh(r.decidido_em)} por ${r.revisor ?? '—'}: ${r.fundamentacao}` : 'pendente'}`).join('\n') : 'Sem recurso.');
  texto(p, `Homologação: ${extra.homologacao ?? (d.homologado_em ? dh(d.homologado_em) : 'pendente')}`);
  texto(p, `Encaminhamento à SEMAD: ${extra.encaminhamento ?? 'pendente'}`);
  return fechar(p);
}
