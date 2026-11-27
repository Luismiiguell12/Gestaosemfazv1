import type { TomSelo } from '@/components/ui';

export type Fornecedor = 'energisa' | 'igua' | 'cercos';
export const ROTULO_FORNECEDOR: Record<Fornecedor, string> = { energisa: 'Energisa', igua: 'Iguá', cercos: 'Cercos' };
export const COR_FORNECEDOR: Record<Fornecedor, string> = { energisa: '#F2B544', igua: '#3AA0D8', cercos: '#7A4FB5' };
export const UNIDADE_CONSUMO: Record<Fornecedor, string> = { energisa: 'kWh', igua: 'm³', cercos: 'kWh' };
export const ROTULO_NUMERO_UC: Record<Fornecedor, string> = { energisa: 'UC', igua: 'Matrícula', cercos: 'UC' };

export type SituacaoPagamento = 'pago' | 'paga' | 'pendente' | 'atrasado' | 'atrasada' | 'sem_lancamento';
export const SITUACAO: Record<SituacaoPagamento, { r: string; tom: TomSelo }> = {
  pago: { r: 'Pago', tom: 'positivo' }, paga: { r: 'Paga', tom: 'positivo' },
  pendente: { r: 'Pendente', tom: 'alerta' }, atrasado: { r: 'Vencido', tom: 'critico' }, atrasada: { r: 'Vencida', tom: 'critico' },
  sem_lancamento: { r: 'Sem lançamento', tom: 'neutro' },
};

/** selo de vigência a partir dos dias restantes */
export function seloVigencia(dias: number, encerrado: boolean, limite = 90): { texto: string; tom: TomSelo } {
  if (encerrado) return { texto: 'Encerrado', tom: 'neutro' };
  if (dias < 0) return { texto: `Vencido há ${-dias} dia(s)`, tom: 'critico' };
  if (dias === 0) return { texto: 'Vence hoje', tom: 'critico' };
  if (dias <= limite) return { texto: `Vence em ${dias} dia(s)`, tom: dias <= 30 ? 'critico' : 'alerta' };
  return { texto: 'Vigente', tom: 'positivo' };
}

/** '1.234,56' | '1234.56' → número; null se inválido */
export function lerValor(t: string): number | null {
  let v = t.replace(/R\$\s?/, '').trim();
  if (/,\d{1,2}$/.test(v)) v = v.replace(/\./g, '').replace(',', '.');
  return /^\d+(\.\d{1,2})?$/.test(v) && Number(v) > 0 ? Number(v) : null;
}

/** só dígitos; tamanho de CPF (11) ou CNPJ (14). Validação completa no banco. */
export const digitos = (t: string) => t.replace(/\D/g, '');

export function cpfValido(c: string): boolean {
  const d = digitos(c);
  if (d.length !== 11 || /^(\d)\1{10}$/.test(d)) return false;
  const dv = (n: number) => { let s = 0; for (let i = 0; i < n; i++) s += Number(d[i]) * (n + 1 - i); const r = (s * 10) % 11; return r === 10 ? 0 : r; };
  return dv(9) === Number(d[9]) && dv(10) === Number(d[10]);
}
export function cnpjValido(c: string): boolean {
  const d = digitos(c);
  if (d.length !== 14 || /^(\d)\1{13}$/.test(d)) return false;
  const dv = (n: number) => { const p = n === 12 ? [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2] : [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]; let s = 0; for (let i = 0; i < n; i++) s += Number(d[i]) * p[i]; const r = s % 11; return r < 2 ? 0 : 11 - r; };
  return dv(12) === Number(d[12]) && dv(13) === Number(d[13]);
}
