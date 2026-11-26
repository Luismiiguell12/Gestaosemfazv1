'use client';
import { useEffect, useRef, type ReactNode } from 'react';
import { Icone } from '../layout/Icone';

export type TomSelo = 'positivo' | 'alerta' | 'critico' | 'info' | 'neutro';
export const Selo = ({ tom, children }: { tom: TomSelo; children: ReactNode }) => <span className={`selo selo-${tom}`}>{children}</span>;

export function Aviso({ tom, titulo, children, role }: { tom: 'info' | 'alerta' | 'critico' | 'sucesso'; titulo?: string; children: ReactNode; role?: 'alert' | 'status' | 'note' }) {
  return (
    <section role={role ?? (tom === 'critico' ? 'alert' : 'status')} className={`aviso aviso-${tom}`}>
      {tom === 'alerta' && <Icone nome="alerta" tamanho={22} cor="var(--aviso-alerta-icone)" traco={2} />}
      <div style={{ flex: 1, minWidth: 0 }}>{titulo && <strong>{titulo} </strong>}{children}</div>
    </section>
  );
}

export const EstadoVazio = ({ children }: { children: ReactNode }) => <div className="vazio">{children}</div>;

/** diálogo modal acessível (foco preso, Esc fecha) */
export function Dialogo({ titulo, aberto, fechar, children, acoes }: { titulo: string; aberto: boolean; fechar: () => void; children: ReactNode; acoes?: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!aberto) return;
    const anterior = document.activeElement as HTMLElement | null;
    ref.current?.querySelector<HTMLElement>('input, select, textarea, button')?.focus();
    const tecla = (e: KeyboardEvent) => {
      if (e.key === 'Escape') fechar();
      if (e.key === 'Tab' && ref.current) {
        const f = ref.current.querySelectorAll<HTMLElement>('a, button, input, select, textarea');
        if (!f.length) return;
        const [p, u] = [f[0], f[f.length - 1]];
        if (e.shiftKey && document.activeElement === p) { e.preventDefault(); u.focus(); }
        else if (!e.shiftKey && document.activeElement === u) { e.preventDefault(); p.focus(); }
      }
    };
    document.addEventListener('keydown', tecla);
    return () => { document.removeEventListener('keydown', tecla); anterior?.focus(); };
  }, [aberto, fechar]);
  if (!aberto) return null;
  return (
    <div className="dialogo-fundo" onMouseDown={(e) => e.target === e.currentTarget && fechar()}>
      <div ref={ref} className="dialogo" role="dialog" aria-modal="true" aria-label={titulo}>
        <h2>{titulo}</h2>
        {children}
        {acoes && <div className="dialogo-acoes">{acoes}</div>}
      </div>
    </div>
  );
}

export function Campo({ rotulo, ajuda, erro, children }: { rotulo: string; ajuda?: string; erro?: string | null; children: ReactNode }) {
  return (
    <label className="campo">
      {rotulo}
      {children}
      {ajuda && <span className="ajuda">{ajuda}</span>}
      {erro && <span className="erro-campo" role="alert">{erro}</span>}
    </label>
  );
}

export const Carregando = () => <div className="vazio" role="status">Carregando…</div>;
