'use client';
import Link from 'next/link';
import { useEffect, useRef, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useSessao } from '@/lib/sessao';
import { quando } from '@/lib/formato';
import { Icone } from './Icone';

interface Notificacao { id: string; titulo: string; texto: string | null; link: string | null; lida_em: string | null; criado_em: string }

export function Notificacoes() {
  const { info } = useSessao();
  const [lista, setLista] = useState<Notificacao[]>([]);
  const [aberto, setAberto] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  const carregar = async () => {
    const { data } = await supabase.from('notificacoes').select('id,titulo,texto,link,lida_em,criado_em').order('criado_em', { ascending: false }).limit(20);
    setLista((data as Notificacao[]) ?? []);
  };
  useEffect(() => {
    if (!info?.sessao_ok) return;
    void carregar();
    const t = setInterval(carregar, 60000);
    return () => clearInterval(t);
  }, [info?.sessao_ok]);
  useEffect(() => {
    const fora = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setAberto(false); };
    document.addEventListener('mousedown', fora);
    return () => document.removeEventListener('mousedown', fora);
  }, []);

  const novas = lista.filter((n) => !n.lida_em).length;
  const marcar = async () => { await supabase.rpc('marcar_notificacoes_lidas', { p_ids: null }); await carregar(); };

  return (
    <div ref={ref} style={{ position: 'relative' }}>
      <button type="button" className="botao botao-icone" aria-label={`Notificações (${novas} novas)`} aria-expanded={aberto} onClick={() => setAberto(!aberto)}>
        <Icone nome="sino" tamanho={20} cor="var(--cor-texto-forte)" traco={2} />
        {novas > 0 && <span className="contador">{novas}</span>}
      </button>
      {aberto && (
        <div className="painel-flutuante" role="dialog" aria-label="Notificações">
          <div className="cartao-topo"><h2 style={{ margin: 0, fontSize: 15 }}>Notificações</h2>{novas > 0 && <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-primaria)', cursor: 'pointer' }} onClick={marcar}>Marcar como lidas</button>}</div>
          {lista.length === 0 && <div className="vazio">Nenhuma notificação.</div>}
          {lista.map((n) => (
            <Link key={n.id} href={n.link ?? '/'} className="item-lista" onClick={() => setAberto(false)} style={{ fontWeight: n.lida_em ? 400 : 600 }}>
              {n.titulo}<br /><span className="meta">{n.texto} · {quando(n.criado_em)}</span>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
