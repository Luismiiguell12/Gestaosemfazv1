// Mensagens ao usuário sem detalhes internos (sem SQL, stack trace ou dados pessoais).
const GENERICA = 'Não foi possível concluir. Tente novamente.';
const INTERNAS = /permission denied|duplicate key|violates|null value|syntax|relation|column|function|constraint|schema|jwt|invalid input/i;
const POR_CODIGO: Record<string, string> = {
  '42501': 'Você não tem permissão para esta ação.',
  '23505': 'Já existe um registro com esses dados.',
  '23503': 'Referência inexistente ou em uso.',
  '23502': 'Preencha os campos obrigatórios.',
  '23514': 'Valor inválido.',
  '22023': 'Dados inválidos.',
  PGRST301: 'Sua sessão expirou. Entre novamente.',
};

export function mensagemErro(e: unknown): string {
  if (!e || typeof e !== 'object') return GENERICA;
  const { message, code } = e as { message?: string; code?: string };
  if (message && !INTERNAS.test(message) && message.length < 200 && /[à-úÀ-Ú]|\.$/.test(message)) return message;
  if (code && POR_CODIGO[code]) return POR_CODIGO[code];
  return GENERICA;
}
