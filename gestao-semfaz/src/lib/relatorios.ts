import type { Coluna } from './exportar';

export type Filtro = 'periodo' | 'meses' | 'unidade' | 'situacaoContrato' | 'situacaoAluguel' | 'dias' | 'ano' | 'fornecedor' | 'soVencidas' | 'tabela';
export interface Valores { de: string; ate: string; unidade: string; situacao: string; dias: string; ano: string; fornecedor: string; tabela: string }

export interface Relatorio {
  id: string; grupo: string; titulo: string; descricao: string; modulo: string | null; rpc: string | null;
  filtros: Filtro[]; colunas: Coluna[]; params: (v: Valores) => Record<string, unknown>;
  /** módulos que precisam estar liberados além de "relatorios" (qualquer um deles) */
  exige?: string[]; somenteGestor?: boolean; pendente?: string;
}

const nul = (v: string) => (v ? v : null);
const mes = (v: string) => (v ? `${v}-01` : null);

export const SITUACAO_ALUGUEL: Record<string, string> = { pago: 'Pago', pendente: 'Pendente', vencido: 'Vencido' };
export const SITUACAO_FATURA: Record<string, string> = { paga: 'Paga', pendente: 'Pendente', vencida: 'Vencida' };
export const SITUACAO_FOLHA: Record<string, string> = { devolvida: 'Devolvida', enviada: 'Entregue à unidade', nao_enviada: 'Não entregue' };
export const TIPO_AFAST: Record<string, string> = { ferias: 'Férias', licenca_premio: 'Licença-prêmio', folga: 'Folga' };
export const STATUS_AFAST: Record<string, string> = { solicitado: 'Pedido', aprovado: 'Aprovado' };
export const FORNECEDOR: Record<string, string> = { energisa: 'Energisa', igua: 'Iguá', cercos: 'Cercos' };

export const RELATORIOS: Relatorio[] = [
  { id: 'demandas_unidade', grupo: 'Demandas e produtividade', titulo: 'Demandas por unidade', descricao: 'Abertas, atrasadas e concluídas', modulo: 'demandas', rpc: 'relatorio_demandas_unidade',
    filtros: ['periodo', 'unidade'], params: (v) => ({ p_de: v.de, p_ate: v.ate, p_unidade: nul(v.unidade) }),
    colunas: [{ chave: 'unidade', rotulo: 'Unidade' }, { chave: 'abertas', rotulo: 'Abertas', tipo: 'numero' }, { chave: 'atrasadas', rotulo: 'Atrasadas', tipo: 'numero' },
      { chave: 'criadas_periodo', rotulo: 'Criadas no período', tipo: 'numero' }, { chave: 'concluidas_periodo', rotulo: 'Concluídas no período', tipo: 'numero' },
      { chave: 'concluidas_no_prazo', rotulo: 'Concluídas no prazo', tipo: 'numero' }, { chave: 'no_prazo_pct', rotulo: '% no prazo', tipo: 'percentual' }] },
  { id: 'demandas_servidor', grupo: 'Demandas e produtividade', titulo: 'Demandas por servidor', descricao: 'Recebidas, concluídas e prazos', modulo: 'demandas', rpc: 'relatorio_demandas_servidor',
    filtros: ['periodo', 'unidade'], params: (v) => ({ p_de: v.de, p_ate: v.ate, p_unidade: nul(v.unidade) }),
    colunas: [{ chave: 'servidor', rotulo: 'Servidor' }, { chave: 'matricula', rotulo: 'Matrícula', largura: 1.4 }, { chave: 'unidade', rotulo: 'Unidade', largura: 1.4 },
      { chave: 'recebidas_periodo', rotulo: 'Recebidas no período', tipo: 'numero' }, { chave: 'abertas', rotulo: 'Abertas', tipo: 'numero' }, { chave: 'atrasadas', rotulo: 'Atrasadas', tipo: 'numero' },
      { chave: 'concluidas_periodo', rotulo: 'Concluídas no período', tipo: 'numero' }, { chave: 'concluidas_no_prazo', rotulo: 'No prazo', tipo: 'numero' }] },
  { id: 'produtividade', grupo: 'Demandas e produtividade', titulo: 'Produtividade', descricao: 'Indicadores por período', modulo: 'produtividade', rpc: null, filtros: [], colunas: [], params: () => ({}),
    pendente: 'Em definição: aguardando as regras de produtividade (material dos fiscais).' },

  { id: 'contratos', grupo: 'Contratos de locação', titulo: 'Contratos', descricao: 'Vigência, valores e aditivos', modulo: 'contratos', rpc: 'relatorio_contratos',
    filtros: ['situacaoContrato'], params: (v) => ({ p_situacao: v.situacao || 'vigentes' }),
    colunas: [{ chave: 'numero', rotulo: 'Contrato', largura: 1.3 }, { chave: 'processo', rotulo: 'Processo', largura: 1.4 }, { chave: 'locador', rotulo: 'Locador' }, { chave: 'imovel', rotulo: 'Imóvel' },
      { chave: 'unidade', rotulo: 'Unidade', largura: 1.1 }, { chave: 'inicio', rotulo: 'Início', tipo: 'data' }, { chave: 'fim_vigencia', rotulo: 'Vigência até', tipo: 'data' },
      { chave: 'valor_mensal', rotulo: 'Valor mensal', tipo: 'moeda' }, { chave: 'valor_anual', rotulo: 'Valor anual', tipo: 'moeda' }, { chave: 'aditivos', rotulo: 'Aditivos', tipo: 'numero', largura: 1 },
      { chave: 'fiscal', rotulo: 'Fiscal' }, { chave: 'encerrado', rotulo: 'Encerrado', largura: 1 }] },
  { id: 'contratos_vencer', grupo: 'Contratos de locação', titulo: 'Contratos a vencer', descricao: 'Próximos 30, 60 ou 90 dias', modulo: 'contratos', rpc: 'relatorio_contratos_vencer',
    filtros: ['dias'], params: (v) => ({ p_dias: Number(v.dias || 90) }),
    colunas: [{ chave: 'numero', rotulo: 'Contrato', largura: 1.3 }, { chave: 'locador', rotulo: 'Locador' }, { chave: 'imovel', rotulo: 'Imóvel' }, { chave: 'unidade', rotulo: 'Unidade', largura: 1.1 },
      { chave: 'fim_vigencia', rotulo: 'Vigência até', tipo: 'data' }, { chave: 'dias_restantes', rotulo: 'Dias restantes', tipo: 'numero' }, { chave: 'valor_mensal', rotulo: 'Valor mensal', tipo: 'moeda' },
      { chave: 'fiscal', rotulo: 'Fiscal' }, { chave: 'renovacao', rotulo: 'Demanda de renovação', largura: 2 }] },
  { id: 'alugueis', grupo: 'Contratos de locação', titulo: 'Aluguéis', descricao: 'Pagos e pendentes por mês', modulo: 'contratos', rpc: 'relatorio_alugueis',
    filtros: ['meses', 'situacaoAluguel'], params: (v) => ({ p_de: mes(v.de), p_ate: mes(v.ate), p_situacao: v.situacao || 'todos' }),
    colunas: [{ chave: 'competencia', rotulo: 'Competência', tipo: 'data' }, { chave: 'contrato', rotulo: 'Contrato', largura: 1.3 }, { chave: 'locador', rotulo: 'Locador' }, { chave: 'imovel', rotulo: 'Imóvel' },
      { chave: 'valor', rotulo: 'Valor', tipo: 'moeda' }, { chave: 'vencimento', rotulo: 'Vencimento', tipo: 'data' }, { chave: 'pago_em', rotulo: 'Pago em', tipo: 'data' },
      { chave: 'valor_pago', rotulo: 'Valor pago', tipo: 'moeda' }, { chave: 'situacao_rotulo', rotulo: 'Situação', largura: 1.2 }] },

  { id: 'faturas', grupo: 'Água e energia', titulo: 'Faturas por fornecedor', descricao: 'Energisa, Iguá e Cercos', modulo: null, exige: ['contratos', 'unidades_consumidoras'], rpc: 'relatorio_faturas',
    filtros: ['meses', 'fornecedor'], params: (v) => ({ p_de: mes(v.de), p_ate: mes(v.ate), p_fornecedor: nul(v.fornecedor), p_so_vencidas: false }),
    colunas: COLUNAS_FATURA() },
  { id: 'faturas_vencidas', grupo: 'Água e energia', titulo: 'Faturas vencidas', descricao: 'Sem pagamento registrado', modulo: null, exige: ['contratos', 'unidades_consumidoras'], rpc: 'relatorio_faturas',
    filtros: ['meses', 'fornecedor'], params: (v) => ({ p_de: mes(v.de), p_ate: mes(v.ate), p_fornecedor: nul(v.fornecedor), p_so_vencidas: true }),
    colunas: COLUNAS_FATURA() },
  { id: 'gasto_contrato', grupo: 'Água e energia', titulo: 'Gasto por contrato', descricao: 'Aluguel + água + energia', modulo: 'contratos', rpc: 'relatorio_gasto_contrato',
    filtros: ['meses'], params: (v) => ({ p_de: mes(v.de), p_ate: mes(v.ate) }),
    colunas: [{ chave: 'contrato', rotulo: 'Contrato', largura: 1.3 }, { chave: 'imovel', rotulo: 'Imóvel' }, { chave: 'unidade', rotulo: 'Unidade', largura: 1.1 },
      { chave: 'aluguel', rotulo: 'Aluguel', tipo: 'moeda' }, { chave: 'agua', rotulo: 'Água', tipo: 'moeda' }, { chave: 'energia', rotulo: 'Energia', tipo: 'moeda' }, { chave: 'total', rotulo: 'Total', tipo: 'moeda' }] },

  { id: 'escala_ferias', grupo: 'Pessoas e controle', titulo: 'Escala de férias', descricao: 'Por unidade e cargo', modulo: 'ferias', rpc: 'relatorio_escala_ferias',
    filtros: ['ano', 'unidade'], params: (v) => ({ p_ano: Number(v.ano), p_unidade: nul(v.unidade) }),
    colunas: [{ chave: 'servidor', rotulo: 'Servidor' }, { chave: 'matricula', rotulo: 'Matrícula', largura: 1.3 }, { chave: 'cargo', rotulo: 'Cargo', largura: 2 }, { chave: 'unidade', rotulo: 'Unidade', largura: 1.1 },
      { chave: 'tipo_rotulo', rotulo: 'Tipo', largura: 1.4 }, { chave: 'inicio', rotulo: 'Início', tipo: 'data' }, { chave: 'fim', rotulo: 'Fim', tipo: 'data' }, { chave: 'dias', rotulo: 'Dias', tipo: 'numero', largura: 0.9 },
      { chave: 'situacao_rotulo', rotulo: 'Situação', largura: 1.1 }, { chave: 'substituto', rotulo: 'Substituto' }] },
  { id: 'saldos', grupo: 'Pessoas e controle', titulo: 'Saldos de férias e folgas', descricao: 'Por servidor', modulo: 'ferias', rpc: 'relatorio_saldos',
    filtros: ['unidade'], params: (v) => ({ p_unidade: nul(v.unidade) }),
    colunas: [{ chave: 'servidor', rotulo: 'Servidor' }, { chave: 'matricula', rotulo: 'Matrícula', largura: 1.3 }, { chave: 'cargo', rotulo: 'Cargo', largura: 2 }, { chave: 'unidade', rotulo: 'Unidade', largura: 1.1 },
      { chave: 'ferias_dias', rotulo: 'Férias (dias)', tipo: 'numero' }, { chave: 'licenca_premio_dias', rotulo: 'Licença-prêmio (dias)', tipo: 'numero' }, { chave: 'folgas', rotulo: 'Folgas', tipo: 'numero' },
      { chave: 'fonte', rotulo: 'Fonte', largura: 1.6 }, { chave: 'atualizado_em', rotulo: 'Atualizado em', tipo: 'dataHora', largura: 1.8 }] },
  { id: 'folhas', grupo: 'Pessoas e controle', titulo: 'Entrega das folhas de ponto', descricao: 'Entregues, devolvidas e atrasadas', modulo: 'folhas_ponto', rpc: 'relatorio_folhas',
    filtros: ['meses'], params: (v) => ({ p_de: mes(v.de), p_ate: mes(v.ate) }),
    colunas: [{ chave: 'competencia', rotulo: 'Competência', tipo: 'data' }, { chave: 'unidade', rotulo: 'Unidade', largura: 1.2 }, { chave: 'situacao_rotulo', rotulo: 'Situação', largura: 1.6 },
      { chave: 'enviada_em', rotulo: 'Entregue em', tipo: 'data' }, { chave: 'recebida_por', rotulo: 'Recebida por' }, { chave: 'devolvida_em', rotulo: 'Devolvida em', tipo: 'data' },
      { chave: 'devolvida_por', rotulo: 'Devolvida por' }, { chave: 'atrasada', rotulo: 'Atrasada', largura: 1 }] },
  { id: 'auditoria', grupo: 'Pessoas e controle', titulo: 'Auditoria', descricao: 'Quem fez o quê e quando', modulo: 'auditoria', somenteGestor: true, rpc: 'relatorio_auditoria',
    filtros: ['periodo', 'tabela'], params: (v) => ({ p_de: v.de, p_ate: v.ate, p_tabela: nul(v.tabela) }),
    colunas: [{ chave: 'em', rotulo: 'Quando', tipo: 'dataHora', largura: 1.6 }, { chave: 'autor', rotulo: 'Quem', largura: 2 }, { chave: 'perfil', rotulo: 'Perfil', largura: 1.2 },
      { chave: 'acao', rotulo: 'Ação', largura: 1.4 }, { chave: 'tabela', rotulo: 'Registro', largura: 1.4 }, { chave: 'registro', rotulo: 'Identificador', largura: 2 },
      { chave: 'antes', rotulo: 'Antes', largura: 3 }, { chave: 'depois', rotulo: 'Depois', largura: 3 }] },
];

function COLUNAS_FATURA(): Coluna[] {
  return [{ chave: 'competencia', rotulo: 'Competência', tipo: 'data' }, { chave: 'fornecedor_rotulo', rotulo: 'Fornecedor', largura: 1.2 }, { chave: 'uc', rotulo: 'UC / matrícula', largura: 1.4 },
    { chave: 'contrato', rotulo: 'Contrato', largura: 1.3 }, { chave: 'imovel', rotulo: 'Imóvel' }, { chave: 'consumo', rotulo: 'Consumo', tipo: 'numero' }, { chave: 'valor', rotulo: 'Valor', tipo: 'moeda' },
    { chave: 'vencimento', rotulo: 'Vencimento', tipo: 'data' }, { chave: 'pago_em', rotulo: 'Pago em', tipo: 'data' }, { chave: 'situacao_rotulo', rotulo: 'Situação', largura: 1.1 }];
}

/** rótulos legíveis para os códigos que vêm do banco */
export function prepararLinhas(id: string, linhas: Record<string, unknown>[]): Record<string, unknown>[] {
  return linhas.map((l) => {
    const r: Record<string, unknown> = { ...l };
    if (id === 'alugueis') r.situacao_rotulo = SITUACAO_ALUGUEL[String(l.situacao)] ?? l.situacao;
    if (id === 'faturas' || id === 'faturas_vencidas') { r.situacao_rotulo = SITUACAO_FATURA[String(l.situacao)] ?? l.situacao; r.fornecedor_rotulo = FORNECEDOR[String(l.fornecedor)] ?? l.fornecedor; }
    if (id === 'folhas') r.situacao_rotulo = SITUACAO_FOLHA[String(l.situacao)] ?? l.situacao;
    if (id === 'escala_ferias') { r.tipo_rotulo = TIPO_AFAST[String(l.tipo)] ?? l.tipo; r.situacao_rotulo = STATUS_AFAST[String(l.situacao)] ?? l.situacao; }
    return r;
  });
}

/** quem pode abrir o relatório (o banco confere de novo) */
export function podeRelatorio(r: Relatorio, modulos: string[], gestor: boolean): boolean {
  if (!modulos.includes('relatorios') || r.pendente) return false;
  if (r.somenteGestor && !gestor) return false;
  if (r.modulo && !modulos.includes(r.modulo)) return false;
  if (r.exige && !r.exige.some((m) => modulos.includes(m))) return false;
  return true;
}
