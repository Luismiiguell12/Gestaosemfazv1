'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState, type ReactNode } from 'react';
import { supabaseConfigurado } from '@/lib/supabase';
import { useSessao } from '@/lib/sessao';
import { BuscaGeral } from './BuscaGeral';
import { Icone } from './Icone';
import { Menu } from './Menu';
import { Notificacoes } from './Notificacoes';

/**
 * Guarda de navegação (UX). A segurança real está no banco (RLS):
 * mesmo que alguém pule esta checagem, a API não entrega dados.
 */
export function AppShell({ children, modulo }: { children: ReactNode; modulo?: string }) {
  const { carregando, session, info, sair } = useSessao();
  const router = useRouter();
  const [menuAberto, setMenuAberto] = useState(false);

  useEffect(() => {
    if (carregando) return;
    if (!session) router.replace('/login');
    else if (info?.autorizado && info.mfa_exigida && info.aal !== 'aal2') router.replace('/mfa');
  }, [carregando, session, info, router]);

  if (!supabaseConfigurado) return <div className="carregando">Sistema não configurado (variáveis do Supabase ausentes).</div>;
  if (carregando || !session || !info) return <div className="carregando" role="status">Carregando…</div>;
  if (!info.autorizado) {
    return (
      <div className="auth-form" style={{ minHeight: '100vh' }}>
        <div className="auth-cartao" role="alert">
          <h1>Acesso não permitido</h1>
          <p>{info.motivo === 'desativado' ? 'Seu usuário está desativado. Procure a Secretaria.' : 'Seu login não está vinculado a um servidor cadastrado.'}</p>
          <button type="button" className="botao" onClick={() => void sair()}>Sair</button>
        </div>
      </div>
    );
  }
  if (!info.sessao_ok) return <div className="carregando" role="status">Verificação em duas etapas necessária…</div>;
  const semModulo = modulo && !info.modulos?.includes(modulo);

  return (
    <div className="shell">
      <a href="#conteudo" className="pular-conteudo">Pular para o conteúdo</a>
      <Menu aberto={menuAberto} fechar={() => setMenuAberto(false)} />
      <main id="conteudo" className="conteudo" tabIndex={-1}>
        <BarraMenuMovel abrir={() => setMenuAberto(true)} />
        {semModulo ? (
          <div className="cartao" role="alert"><h2>Módulo não liberado</h2><p className="nota">Você não tem acesso a este módulo. <Link href="/">Voltar ao painel</Link></p></div>
        ) : children}
      </main>
    </div>
  );
}

function BarraMenuMovel({ abrir }: { abrir: () => void }) {
  return (
    <button type="button" className="botao botao-icone botao-menu" aria-label="Abrir menu" aria-controls="menu-principal" onClick={abrir}>
      <Icone nome="menu" tamanho={20} />
    </button>
  );
}

export interface ItemTrilha { rotulo: string; href?: string }

export function Cabecalho({ trilha, titulo, subtitulo, acima, acoes, comBusca = true }: {
  trilha?: ItemTrilha[]; titulo: string; subtitulo?: ReactNode; acima?: ReactNode; acoes?: ReactNode; comBusca?: boolean;
}) {
  return (
    <header className="cabecalho">
      <div>
        {acima}
        {trilha && (
          <nav aria-label="Trilha de navegação" className="trilha">
            {trilha.map((t, i) => (
              <span key={i}>{i > 0 && ' › '}{t.href ? <Link href={t.href}>{t.rotulo}</Link> : t.rotulo}</span>
            ))}
          </nav>
        )}
        <h1 className="titulo">{titulo}</h1>
        {subtitulo && <div className="subtitulo">{subtitulo}</div>}
      </div>
      <div className="acoes">
        {acoes}
        {comBusca && <><BuscaGeral /><Notificacoes /></>}
      </div>
    </header>
  );
}
