const TZ = 'America/Maceio'; // fuso de Sergipe

export function dataExtenso(d = new Date()): string {
  const s = new Intl.DateTimeFormat('pt-BR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: TZ }).format(d);
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export function saudacao(d = new Date()): string {
  const h = Number(new Intl.DateTimeFormat('pt-BR', { hour: 'numeric', hourCycle: 'h23', timeZone: TZ }).format(d));
  return h < 12 ? 'Bom dia' : h < 18 ? 'Boa tarde' : 'Boa noite';
}

export const primeiroNome = (n?: string | null) => (n ?? '').trim().split(/\s+/)[0] ?? '';

export function iniciais(n?: string | null): string {
  const p = (n ?? '').trim().split(/\s+/).filter(Boolean);
  return ((p[0]?.[0] ?? '') + (p.length > 1 ? p[p.length - 1][0] : '')).toUpperCase();
}

/** 'YYYY-MM-DD' → 'DD/MM/YYYY' sem fuso */
export function dataCurta(iso?: string | null): string {
  if (!iso) return '—';
  const [y, m, d] = iso.slice(0, 10).split('-');
  return `${d}/${m}/${y}`;
}

export function dataHora(iso?: string | null): string {
  if (!iso) return '—';
  return new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short', timeZone: TZ }).format(new Date(iso));
}

export function quando(iso: string, agora = new Date()): string {
  const d = new Date(iso);
  const fmt = (x: Date) => new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit', timeZone: TZ }).format(x);
  if (fmt(d) === fmt(agora)) return 'hoje';
  if (fmt(d) === fmt(new Date(agora.getTime() - 86400000))) return 'ontem';
  return fmt(d);
}

export function diaSemana(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number);
  return new Intl.DateTimeFormat('pt-BR', { weekday: 'long', timeZone: 'UTC' }).format(new Date(Date.UTC(y, m - 1, d)));
}
