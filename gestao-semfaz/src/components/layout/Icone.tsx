// Ícones de traço (estilo Lucide) copiados dos protótipos.
const P: Record<string, React.ReactNode> = {
  painel: <><rect x="3" y="3" width="7" height="9" rx="1.5" /><rect x="14" y="3" width="7" height="5" rx="1.5" /><rect x="14" y="12" width="7" height="9" rx="1.5" /><rect x="3" y="16" width="7" height="5" rx="1.5" /></>,
  demandas: <><path d="M9 6h11" /><path d="M9 12h11" /><path d="M9 18h11" /><path d="m3 6 1.5 1.5L7 5" /><path d="m3 12 1.5 1.5L7 11" /><path d="m3 18 1.5 1.5L7 17" /></>,
  calendario: <><rect x="3" y="4" width="18" height="17" rx="2" /><path d="M8 2v4" /><path d="M16 2v4" /><path d="M3 10h18" /></>,
  contratos: <><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><path d="M14 3v5h5" /><path d="M9 13h6" /><path d="M9 17h6" /></>,
  energia: <path d="M13 2 4 14h7l-1 8 9-12h-7z" />,
  ferias: <><circle cx="12" cy="12" r="4" /><path d="M12 2v2" /><path d="M12 20v2" /><path d="m4.9 4.9 1.4 1.4" /><path d="m17.7 17.7 1.4 1.4" /><path d="M2 12h2" /><path d="M20 12h2" /><path d="m4.9 19.1 1.4-1.4" /><path d="m17.7 6.3 1.4-1.4" /></>,
  relogio: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
  grafico: <><path d="M3 3v18h18" /><path d="m7 15 4-4 3 3 5-6" /></>,
  aprovacoes: <><circle cx="12" cy="12" r="9" /><path d="m8 12 3 3 5-6" /></>,
  relatorios: <><path d="M21 12A9 9 0 1 1 12 3v9z" /><path d="M15 3.5A9 9 0 0 1 20.5 9H15z" /></>,
  usuarios: <><circle cx="9" cy="8" r="3.5" /><path d="M2.5 20a6.5 6.5 0 0 1 13 0" /><path d="M16 4.5a3.5 3.5 0 0 1 0 7" /><path d="M18 14a6 6 0 0 1 3.5 6" /></>,
  recibo: <><path d="M5 3h14v18l-3-2-2 2-2-2-2 2-2-2-3 2z" /><path d="M9 8h6" /><path d="M9 12h6" /></>,
  busca: <><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></>,
  sino: <><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" /><path d="M10.3 21a1.9 1.9 0 0 0 3.4 0" /></>,
  alerta: <><path d="M12 3 2 20h20L12 3z" /><path d="M12 10v4" /><path d="M12 17.5v.5" /></>,
  info: <><circle cx="12" cy="12" r="9" /><path d="M12 8v5" /><path d="M12 16.5v.5" /></>,
  menu: <><path d="M4 6h16" /><path d="M4 12h16" /><path d="M4 18h16" /></>,
  fechar: <><path d="M6 6l12 12" /><path d="M18 6 6 18" /></>,
};

export function Icone({ nome, tamanho = 18, cor = 'currentColor', traco = 1.8 }: { nome: string; tamanho?: number; cor?: string; traco?: number }) {
  return (
    <svg aria-hidden="true" width={tamanho} height={tamanho} viewBox="0 0 24 24" fill="none" stroke={cor} strokeWidth={traco} strokeLinecap="round" strokeLinejoin="round">
      {P[nome] ?? P.painel}
    </svg>
  );
}

export function Logo({ tamanho = 38 }: { tamanho?: number }) {
  return (
    <svg role="img" aria-label="Logo Gestão SEMFAZ" width={tamanho} height={tamanho} viewBox="0 0 40 40" style={{ flex: 'none' }}>
      <rect x="0" y="0" width="40" height="40" rx="10" fill="var(--cor-logo)" />
      <path d="M28 13.5A10 10 0 1 0 30 21h-9" fill="none" stroke="var(--cor-menu)" strokeWidth="3.6" strokeLinecap="round" />
      <rect x="17" y="24" width="3" height="5" rx="1" fill="var(--cor-menu)" />
      <rect x="21.5" y="21" width="3" height="8" rx="1" fill="var(--cor-menu)" />
    </svg>
  );
}
