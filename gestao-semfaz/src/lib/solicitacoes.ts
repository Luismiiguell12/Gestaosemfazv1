import { ROTULO_ABRANGENCIA, ROTULO_PERFIL, type Perfil } from './validacao';
import { dataCurta } from './formato';

export type TipoSolicitacao =
  | 'unidade_criar' | 'unidade_alterar' | 'cargo_criar' | 'cargo_alterar' | 'servidor_alterar'
  | 'usuario_perfil' | 'acesso_unidade_conceder' | 'acesso_unidade_retirar' | 'feriado_alterar' | 'feriado_excluir';

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
};

export const ROTULO_TIPO_LONGO: Record<TipoSolicitacao, string> = {
  unidade_criar: 'Criação de unidade', unidade_alterar: 'Alteração de unidade', cargo_criar: 'Criação de cargo',
  cargo_alterar: 'Alteração de cargo', servidor_alterar: 'Alteração de dados de servidor', usuario_perfil: 'Alteração de perfil',
  acesso_unidade_conceder: 'Acesso extra a unidade', acesso_unidade_retirar: 'Retirada de acesso a unidade',
  feriado_alterar: 'Alteração de feriado', feriado_excluir: 'Exclusão de feriado',
};

export const ROTULO_CAMPO: Record<string, string> = {
  sigla: 'Sigla', nome: 'Nome', tipo: 'Tipo', unidade_pai_id: 'Unidade superior', ordem: 'Ordem', ativa: 'Situação', ativo: 'Situação',
  nome_completo: 'Nome', matricula: 'Matrícula', cargo_id: 'Cargo', unidade_id: 'Unidade', situacao: 'Situação',
  email_institucional: 'E-mail institucional', perfil: 'Perfil no sistema', data: 'Data', descricao: 'Descrição', abrangencia: 'Abrangência',
};

export const ROTULO_STATUS = { pendente: 'Pendente', aprovada: 'Aprovada', recusada: 'Recusada', bloqueada: 'Bloqueada', cancelada: 'Cancelada' } as const;
export const TOM_STATUS = { pendente: 'alerta', aprovada: 'positivo', recusada: 'critico', bloqueada: 'critico', cancelada: 'neutro' } as const;

export function formatarValor(campo: string, v: unknown, nomes: { unidades: Map<string, string>; cargos: Map<string, string> }): string {
  if (v === null || v === undefined || v === '') return '—';
  if (campo === 'unidade_pai_id' || campo === 'unidade_id') return nomes.unidades.get(String(v)) ?? '—';
  if (campo === 'cargo_id') return nomes.cargos.get(String(v)) ?? '—';
  if (campo === 'perfil') return ROTULO_PERFIL[v as Perfil] ?? String(v);
  if (campo === 'abrangencia') return ROTULO_ABRANGENCIA[v as keyof typeof ROTULO_ABRANGENCIA] ?? String(v);
  if (campo === 'data') return dataCurta(String(v));
  if (campo === 'ativa' || campo === 'ativo') return v ? 'Ativa' : 'Inativa';
  if (campo === 'situacao') return v === 'ativo' ? 'Ativo' : 'Inativo';
  return String(v);
}
