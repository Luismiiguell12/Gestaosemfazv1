'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useSessao } from '@/lib/sessao';
import { useConsulta } from '@/lib/useConsulta';
import { ROTULO_PERFIL } from '@/lib/validacao';
import { Icone, Logo } from './Icone';

interface Modulo { codigo: string; nome: string; rota: string; icone: string; ordem: number; status: 'ativo' | 'em_breve' | 'em_definicao'; no_menu: boolean }
const TAG = { em_breve: 'em breve', em_definicao: 'em definição', ativo: '' } as const;

const ativo = (rota: string, atual: string) => {
  const a = atual.replace(/\/$/, '') || '/';
  return rota === '/' ? a === '/' : a === rota || a.startsWith(rota + '/');
};

export function Menu({ aberto, fechar }: { aberto: boolean; fechar: () => void }) {
  const pathname = usePathname() ?? '/';
  const { info, sair } = useSessao();
  const { dados } = useConsulta(
    async () => supabase.from('modulos').select('codigo,nome,rota,icone,ordem,status,no_menu').eq('no_menu', true).order('ordem'),
    [info?.usuario_id],
  );
  const meus = (dados as Modulo[] | null ?? []).filter((m) => info?.modulos?.includes(m.codigo));

  return (
    <>
      {aberto && <div className="menu-fundo" onClick={fechar} aria-hidden="true" />}
      <nav id="menu-principal" aria-label="Menu principal" className="menu" data-aberto={aberto}>
        <div className="menu-marca">
          <Logo />
          <div><div className="menu-marca-nome">Gestão SEMFAZ</div><div className="menu-marca-sub">Prefeitura de Lagarto/SE</div></div>
        </div>
        {meus.map((m) =>
          m.status === 'ativo' ? (
            <Link key={m.codigo} href={m.rota} className="menu-item" aria-current={ativo(m.rota, pathname) ? 'page' : undefined} onClick={fechar}>
              <Icone nome={m.icone} /><span>{m.nome}</span>
            </Link>
          ) : (
            <span key={m.codigo} className="menu-item" aria-disabled="true" title={`${m.nome}: ${TAG[m.status]}`}>
              <Icone nome={m.icone} /><span>{m.nome}</span><span className="menu-tag">{TAG[m.status]}</span>
            </span>
          ),
        )}
        <div className="menu-rodape">
          {info?.nome && <span>{info.nome}<br />{info.perfil ? ROTULO_PERFIL[info.perfil] : ''}</span>}
          {info?.aal !== 'aal2' && info?.perfil === 'diretor' && <Link href="/mfa" style={{ color: 'var(--cor-logo)' }}>Ativar verificação em duas etapas (recomendado)</Link>}
          <button type="button" className="menu-sair" onClick={() => void sair()}>Sair</button>
        </div>
      </nav>
    </>
  );
}
