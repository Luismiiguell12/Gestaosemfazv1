import { ROTULO_ABRANGENCIA, ROTULO_PERFIL, ROTULO_VINCULO, type Perfil } from './validacao';
import { dataCurta, moeda } from './formato';

export type TipoSolicitacao =
  | 'unidade_criar' | 'unidade_alterar' | 'cargo_criar' | 'cargo_alterar' | 'servidor_alterar'
  | 'usuario_perfil' | 'acesso_unidade_conceder' | 'acesso_unidade_retirar' | 'feriado_alterar' | 'feriado_excluir'
  | 'contrato_alterar' | 'contrato_aditivo';

export interface Solicitacao {
  id: string; tipo: TipoSolicitacao; resumo: string; alvo_id: string | null;
  dados_antes: Record<string, unknown>; dados_depois: Record<string, unknown>;
  justificativa: string; anexo_path: string | null; status: 'pendente' | 'aprovada' | 'recusada' | 'bloqueada' | 'cancelada';
  criado_em: string; solicitante_id: string; solicitante_nome: string; decidido_por_nome: string | null; decidido_em: string | null; comentario_decisao: string | null;
}

export const ROTULO_TIPO: Record<TipoSolicitacao, string> = {
  unidade_criar: 'Estrutura', unidade_alterar: 'Estrutura', cargo_criar: 'Cargo', cargo_alterar: 'Cargo',
  servidor_alterar: 'Dados de servidor', usuario_perfil: 'Permissão', acesso_unidade_conceder: 'Permissão',
  acesso_unidade_retirar: 'Permissão', feriado_alterar: 'Feriado', feriado_excluir: 'Feriado',
  contrato_alterar: 'Contrato', contrato_aditivo: 'Contrato',
};

export const ROTULO_TIPO_LONGO: Record<TipoSolicitacao, string> = {
  unidade_criar: 'Criação de unidade', unidade_alterar: 'Alteração de unidade', cargo_criar: 'Criação de cargo',
  cargo_alterar: 'Alteração de cargo', servidor_alterar: 'Alteração de dados de servidor', usuario_perfil: 'Alteração de perfil',
  acesso_unidade_conceder: 'Acesso extra a unidade', acesso_unidade_retirar: 'Retirada de acesso a unidade',
  feriado_alterar: 'Alteração de feriado', feriado_excluir: 'Exclusão de feriado',
  contrato_alterar: 'Alteração de contrato', contrato_aditivo: 'Aditivo de contrato',
};

export const ROTULO_CAMPO: Record<string, string> = {
  sigla: 'Sigla', nome: 'Nome', tipo: 'Tipo', unidade_pai_id: 'Unidade superior', ordem: 'Ordem', ativa: 'Situação', ativo: 'Situação',
  nome_completo: 'Nome', matricula: 'Matrícula', cargo_id: 'Cargo', unidade_id: 'Unidade', situacao: 'Situação',
  email_institucional: 'E-mail institucional', perfil: 'Perfil no sistema', data: 'Data', descricao: 'Descrição', abrangencia: 'Abrangência',
  numero: 'Número', processo: 'Processo', imovel_descricao: 'Imóvel', imovel_endereco: 'Endereço do imóvel', unidade_ocupante_id: 'Unidade ocupante',
  valor_mensal: 'Valor mensal', dia_vencimento: 'Dia de vencimento', fiscal_servidor_id: 'Fiscal do contrato', indice_reajuste: 'Índice de reajuste',
  mes_database: 'Mês da data-base', encerrado: 'Encerrado', fim_vigencia: 'Fim da vigência', novo_fim: 'Nova vigência até', novo_valor: 'Novo valor mensal',
  data_assinatura: 'Data de assinatura',
  tipo_vinculo: 'Tipo de vínculo', exerce_comissao: 'Cargo em comissão/função de confiança', carreira_excluida: 'Carreira excluída do adicional',
};

export const ROTULO_STATUS = { pendente: 'Pendente', aprovada: 'Aprovada', recusada: 'Recusada', bloqueada: 'Bloqueada', cancelada: 'Cancelada' } as const;
export const TOM_STATUS = { pendente: 'alerta', aprovada: 'positivo', recusada: 'critico', bloqueada: 'critico', cancelada: 'neutro' } as const;

export function formatarValor(campo: string, v: unknown, nomes: { unidades: Map<string, string>; cargos: Map<string, string>; servidores?: Map<string, string> }): string {
  if (v === null || v === undefined || v === '') return '—';
  if (campo === 'valor_mensal' || campo === 'novo_valor') return moeda(Number(v));
  if (campo === 'fim_vigencia' || campo === 'novo_fim' || campo === 'data_assinatura') return dataCurta(String(v));
  if (campo === 'fiscal_servidor_id') return nomes.servidores?.get(String(v)) ?? 'Servidor indicado';
  if (campo === 'encerrado' || campo === 'exerce_comissao' || campo === 'carreira_excluida') return v ? 'Sim' : 'Não';
  if (campo === 'tipo_vinculo') return ROTULO_VINCULO[v as keyof typeof ROTULO_VINCULO] ?? String(v);
  if (campo === 'unidade_pai_id' || campo === 'unidade_id' || campo === 'unidade_ocupante_id') return nomes.unidades.get(String(v)) ?? '—';
  if (campo === 'cargo_id') return nomes.cargos.get(String(v)) ?? '—';
  if (campo === 'perfil') return ROTULO_PERFIL[v as Perfil] ?? String(v);
  if (campo === 'abrangencia') return ROTULO_ABRANGENCIA[v as keyof typeof ROTULO_ABRANGENCIA] ?? String(v);
  if (campo === 'data') return dataCurta(String(v));
  if (campo === 'ativa' || campo === 'ativo') return v ? 'Ativa' : 'Inativa';
  if (campo === 'situacao') return v === 'ativo' ? 'Ativo' : 'Inativo';
  return String(v);
}
