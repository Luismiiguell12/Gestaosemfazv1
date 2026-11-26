'use client';
import Link from 'next/link';
import { useEffect, useId, useRef, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { Icone } from './Icone';

interface Resultado { tipo: string; id: string; titulo: string; subtitulo: string; rota: string }
const GRUPOS: Record<string, string> = { unidade: 'Unidades administrativas', servidor: 'Servidores', contrato: 'Contratos', demanda: 'Demandas', uc: 'Unidades consumidoras' };

// Pesquisa no banco (ignora acento/maiúscula). RLS filtra o que cada um vê.
export function BuscaGeral() {
  const [termo, setTermo] = useState('');
  const [res, setRes] = useState<Resultado[] | null>(null);
  const [aberto, setAberto] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const idLista = useId();

  useEffect(() => {
    const t = termo.trim();
    if (t.length < 2) { setRes(null); return; }
    const h = setTimeout(async () => {
      const { data } = await supabase.rpc('busca_geral', { termo: t.slice(0, 100), limite: 6 });
      setRes((data as Resultado[]) ?? []);
      setAberto(true);
    }, 250);
    return () => clearTimeout(h);
  }, [termo]);

  useEffect(() => {
    const fora = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setAberto(false); };
    document.addEventListener('mousedown', fora);
    return () => document.removeEventListener('mousedown', fora);
  }, []);

  const grupos = Object.entries(
    (res ?? []).reduce<Record<string, Resultado[]>>((acc, r) => ((acc[r.tipo] ??= []).push(r), acc), {}),
  );

  return (
    <div ref={ref} className="busca" role="search">
      <Icone nome="busca" cor="var(--cor-texto-suave)" traco={2} />
      <input
        type="search" aria-label="Busca geral" placeholder="Buscar contrato, servidor, demanda…" value={termo} maxLength={100}
        onChange={(e) => setTermo(e.target.value)} onFocus={() => res && setAberto(true)}
        onKeyDown={(e) => e.key === 'Escape' && setAberto(false)}
        aria-expanded={aberto} aria-controls={idLista} autoComplete="off"
      />
      {aberto && res && (
        <div id={idLista} className="busca-resultados" role="listbox" aria-label="Resultados da busca">
          {grupos.length === 0 && <div className="busca-item">Nada encontrado no que você pode ver.</div>}
          {grupos.map(([tipo, itens]) => (
            <div key={tipo} role="group" aria-label={GRUPOS[tipo] ?? tipo}>
              <div className="busca-grupo">{GRUPOS[tipo] ?? tipo}</div>
              {itens.map((r) => (
                <Link key={r.id} href={r.rota} className="busca-item" role="option" aria-selected="false" onClick={() => { setAberto(false); setTermo(''); }}>
                  {r.titulo}<small>{r.subtitulo}</small>
                </Link>
              ))}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
