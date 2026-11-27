import { dataCurta } from './formato';

export type StatusDemanda = 'sugerida' | 'a_fazer' | 'em_andamento' | 'aguardando_terceiros' | 'em_revisao' | 'concluida' | 'recusada' | 'cancelada';
export type Prioridade = 'baixa' | 'media' | 'alta' | 'critica';
export type Origem = 'processo' | 'email' | 'whatsapp' | 'recorrente' | 'outra';

export interface Responsavel { servidor_id: string; nome: string; papel: 'titular' | 'substituto'; usuario_id?: string | null }
export interface DemandaLista {
  id: string; numero: number; titulo: string; origem: Origem; numero_processo: string | null; unidade_id: string; unidade: string;
  prioridade: Prioridade; status: StatusDemanda; prazo: string | null; dias_uteis: number | null; concluida_em: string | null;
  responsaveis: Responsavel[]; etapas_total: number; etapas_feitas: number; criado_por: string; sou_responsavel: boolean;
}

// colunas do quadro (protótipo Demandas.dc.html)
export const COLUNAS: { status: StatusDemanda; nome: string }[] = [
  { status: 'a_fazer', nome: 'A fazer' },
  { status: 'em_andamento', nome: 'Em andamento' },
  { status: 'aguardando_terceiros', nome: 'Aguardando terceiros' },
  { status: 'em_revisao', nome: 'Em revisão' },
  { status: 'concluida', nome: 'Concluída' },
];

export const ROTULO_STATUS: Record<StatusDemanda, string> = {
  sugerida: 'Sugestão', a_fazer: 'A fazer', em_andamento: 'Em andamento', aguardando_terceiros: 'Aguardando terceiros',
  em_revisao: 'Em revisão', concluida: 'Concluída', recusada: 'Recusada', cancelada: 'Cancelada',
};
export const TOM_STATUS: Record<StatusDemanda, 'positivo' | 'alerta' | 'critico' | 'info' | 'neutro'> = {
  sugerida: 'alerta', a_fazer: 'neutro', em_andamento: 'info', aguardando_terceiros: 'neutro', em_revisao: 'alerta',
  concluida: 'positivo', recusada: 'critico', cancelada: 'neutro',
};

export const ROTULO_PRIORIDADE: Record<Prioridade, string> = { baixa: 'Baixa', media: 'Média', alta: 'Alta', critica: 'Crítica' };
// [fundo, texto, borda superior do cartão]
export const COR_PRIORIDADE: Record<Prioridade, [string, string, string]> = {
  baixa: ['#EEF1F5', '#3A4557', '#C9D2DE'], media: ['#E6EEFB', '#1D4FB0', '#7C97E0'],
  alta: ['#FDF1DC', '#8A4B00', '#C77700'], critica: ['#FCE8E6', '#B3261E', '#B3261E'],
};

export const ROTULO_ORIGEM: Record<Origem, string> = { processo: 'Processo', email: 'E-mail', whatsapp: 'WhatsApp', recorrente: 'Recorrente', outra: 'Outra' };
export const ROTULO_ORIGEM_LONGO: Record<Origem, string> = {
  processo: 'Processo físico', email: 'E-mail institucional', whatsapp: 'WhatsApp', recorrente: 'Demanda recorrente', outra: 'Outra',
};

export const ABERTOS: StatusDemanda[] = ['a_fazer', 'em_andamento', 'aguardando_terceiros', 'em_revisao'];

/** texto do prazo como no protótipo: "em 3 dias úteis", "atrasada 2 dias", "concluída 24/11" */
export function textoPrazo(d: Pick<DemandaLista, 'status' | 'prazo' | 'dias_uteis' | 'concluida_em'>): { texto: string; atrasada: boolean } {
  if (d.status === 'concluida') return { texto: d.concluida_em ? `concluída ${dataCurta(d.concluida_em).slice(0, 5)}` : 'concluída', atrasada: false };
  if (!d.prazo || d.dias_uteis === null) return { texto: 'sem prazo', atrasada: false };
  if (d.dias_uteis < 0) return { texto: `atrasada ${-d.dias_uteis} dia${d.dias_uteis === -1 ? '' : 's'} úte${d.dias_uteis === -1 ? 'l' : 'is'}`, atrasada: true };
  if (d.dias_uteis === 0) return { texto: d.prazo < new Date().toISOString().slice(0, 10) ? 'atrasada' : 'vence hoje', atrasada: d.prazo < new Date().toISOString().slice(0, 10) };
  return { texto: `em ${d.dias_uteis} dia${d.dias_uteis === 1 ? '' : 's'} úte${d.dias_uteis === 1 ? 'l' : 'is'}`, atrasada: false };
}

export const iniciaisCurtas = (nome: string) => {
  const p = nome.trim().split(/\s+/);
  return ((p[0]?.[0] ?? '') + (p.length > 1 ? p[p.length - 1][0] : '')).toUpperCase();
};

/** menções: "@Nome" escolhidas no autocompletar viram ids (o servidor revalida) */
export function mencoesNoTexto(texto: string, escolhidas: { usuario_id: string; nome: string }[]) {
  return escolhidas.filter((m) => texto.includes(`@${m.nome}`)).map((m) => m.usuario_id);
}
