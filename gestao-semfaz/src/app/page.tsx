'use client';
import Link from 'next/link';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { EstadoVazio } from '@/components/ui';
import { supabase } from '@/lib/supabase';
import { ehGestorGeral, useSessao, type InfoSessao } from '@/lib/sessao';
import { useConsulta } from '@/lib/useConsulta';
import { agruparParaPainel, caminho, type Unidade } from '@/lib/estrutura';
import { dataExtenso, primeiroNome, quando, saudacao } from '@/lib/formato';

export default function PainelPage() {
  return (
    <AppShell modulo="painel">
      <Painel />
    </AppShell>
  );
}

function Painel() {
  const { info } = useSessao();
  return info?.perfil === 'funcionario' ? <PainelFuncionario info={info} /> : <PainelGestao info={info!} />;
}

interface Pedido { id: string; resumo: string; solicitante_id: string; solicitante_nome: string; criado_em: string }

// ===== Painel da Secretária / chefia (Main.dc.html) =====
function PainelGestao({ info }: { info: InfoSessao }) {
  const geral = ehGestorGeral(info);
  const unidades = useConsulta(async () => supabase.from('unidades').select('id,sigla,nome,tipo,unidade_pai_id,ordem,ativa'), []);
  const escopo = useConsulta(async () => supabase.rpc('minhas_unidades_escopo'), []);
  const pedidos = useConsulta(async () => supabase.rpc('listar_solicitacoes', { p_aba: 'pendentes' }), []);

  const visiveis = geral ? undefined : new Set(((escopo.dados as string[] | null) ?? []).map(String));
  const grupos = agruparParaPainel((unidades.dados as Unidade[] | null) ?? [], visiveis);
  const lista = ((pedidos.dados as Pedido[] | null) ?? []).filter((p) => !geral || p.solicitante_id !== info.usuario_id);

  const kpis = [
    { v: '—', l: 'Demandas atrasadas', s: 'disponível na Fase 3', bg: 'var(--selo-critico-bg)', fg: 'var(--cor-critico)' },
    { v: String(lista.length), l: geral ? 'Aprovações para você' : 'Pedidos aguardando', s: geral ? 'alterações de dados' : 'enviados por você', bg: 'var(--selo-primaria-bg)', fg: 'var(--cor-primaria)', href: '/aprovacoes' },
    { v: '—', l: 'Contratos vencendo', s: 'disponível na Fase 4', bg: 'var(--selo-alerta-bg)', fg: 'var(--selo-alerta-fg)' },
    { v: '—', l: 'Aluguéis pendentes', s: 'disponível na Fase 4', bg: 'var(--selo-neutro-bg)', fg: 'var(--cor-texto-forte)' },
  ];

  return (
    <>
      <Cabecalho acima={<div className="data-extenso">{dataExtenso()}</div>} titulo={`${saudacao()}, ${primeiroNome(info.nome)}`} />

      <section aria-label="O que pede atenção hoje" className="kpis">
        {kpis.map((k) => {
          const corpo = (
            <>
              <span className="kpi-valor" style={{ background: k.bg, color: k.fg }}>{k.v}</span>
              <span className="kpi-texto"><strong>{k.l}</strong><br /><small>{k.s}</small></span>
            </>
          );
          return k.href ? <Link key={k.l} href={k.href} className="kpi">{corpo}</Link> : <div key={k.l} className="kpi">{corpo}</div>;
        })}
      </section>

      <div className="linha">
        <section aria-label="Saúde das unidades" className="col-principal">
          <div className="cartao-topo">
            <h2 style={{ margin: 0, fontSize: 18 }}>Como estão as unidades</h2>
            <div className="legenda">
              <span><span aria-hidden="true" className="ponto" style={{ background: 'var(--cor-positivo)' }} /> Em dia</span>
              <span><span aria-hidden="true" className="ponto" style={{ background: 'var(--cor-alerta)' }} /> Prazo apertado</span>
              <span><span aria-hidden="true" className="ponto" style={{ background: 'var(--cor-critico)' }} /> Com atraso</span>
            </div>
          </div>
          {unidades.carregando && <EstadoVazio>Carregando…</EstadoVazio>}
          {grupos.map((g) => (
            <div key={g.id} className="cartao cartao-xl">
              <div className="grupo-titulo"><h3>{g.nome}</h3><span>demandas a partir da Fase 3</span></div>
              <div className="grade-unidades">
                {g.unidades.map((u) => (
                  <Link key={u.id} href={`/usuarios?unidade=${u.id}`} className="cartao-unidade">
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 6 }}>
                      <strong style={{ fontSize: 14 }}>{u.tipo === 'gabinete' ? 'Gabinete' : u.sigla}</strong>
                      <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--cor-texto-suave)' }}>sem dados</span>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
                      <span className="numero" style={{ color: 'var(--cor-texto-suave)' }}>—</span>
                      <span style={{ fontSize: 12, color: 'var(--cor-texto-suave)' }}>atrasadas</span>
                    </div>
                    <div aria-hidden="true" className="barra" />
                    <div style={{ fontSize: 11, color: 'var(--cor-texto-suave)' }}>0 a fazer · 0 em andamento · 0 concluídas</div>
                  </Link>
                ))}
              </div>
            </div>
          ))}
        </section>

        <aside className="col-lateral">
          <section className="cartao cartao-xl">
            <div className="cartao-topo"><h2 style={{ fontSize: 16 }}>{geral ? 'Aguardando sua aprovação' : 'Meus pedidos pendentes'}</h2><Link href="/aprovacoes">Abrir</Link></div>
            {lista.length === 0 && !pedidos.carregando && <EstadoVazio>Nenhum pedido pendente.</EstadoVazio>}
            {lista.slice(0, 3).map((p) => (
              <Link key={p.id} href={`/aprovacoes?id=${p.id}`} className="item-lista"><strong>{p.resumo}</strong><br /><span className="meta">{p.solicitante_nome} · {quando(p.criado_em)}</span></Link>
            ))}
          </section>
          <section className="cartao cartao-xl">
            <h2 style={{ fontSize: 16, marginBottom: 6 }}>Contratos perto do vencimento</h2>
            <EstadoVazio>Disponível na Fase 4 (contratos de locação).</EstadoVazio>
          </section>
          <section className="cartao cartao-xl">
            <div className="cartao-topo"><h2 style={{ fontSize: 16, marginBottom: 6 }}>Próximos compromissos</h2><Link href="/calendario">Calendário</Link></div>
            <EstadoVazio>Disponível na Fase 3 (calendário).</EstadoVazio>
          </section>
          <section className="cartao cartao-xl">
            <div className="cartao-topo"><h2 style={{ fontSize: 16, marginBottom: 6 }}>Ausências neste mês</h2></div>
            <EstadoVazio>Disponível na Fase 2 (férias e licenças).</EstadoVazio>
          </section>
        </aside>
      </div>
      <p className="nota">Clique numa unidade para ver os servidores dela. Indicadores de demandas, contratos e ausências chegam nas próximas fases.</p>
    </>
  );
}

// ===== Painel do funcionário (Funcionario.dc.html) =====
function PainelFuncionario({ info }: { info: InfoSessao }) {
  const unidades = useConsulta(async () => supabase.from('unidades').select('id,sigla,nome,tipo,unidade_pai_id,ordem,ativa'), []);
  const lotacao = caminho((unidades.dados as Unidade[] | null) ?? [], info.unidade_id).filter((u) => u.tipo !== 'gabinete').reverse().map((u) => u.sigla);
  const kpis = [
    { label: 'Demandas abertas', color: 'var(--cor-texto-forte)' },
    { label: 'Atrasadas', color: 'var(--cor-critico)' },
    { label: 'Concluídas no mês', color: 'var(--cor-positivo)' },
    { label: 'Entregues no prazo', color: 'var(--cor-primaria)' },
  ];
  return (
    <>
      <Cabecalho
        trilha={[{ rotulo: 'Início' }, { rotulo: 'Meu painel' }]}
        titulo={`Olá, ${primeiroNome(info.nome)}`}
        subtitulo={[info.cargo, ...lotacao].filter(Boolean).join(' · ')}
        acoes={<button type="button" className="botao botao-primario" disabled title="Disponível na Fase 3">+ Sugerir demanda</button>}
      />
      <section aria-label="Meus números do mês" className="kpis">
        {kpis.map((k) => (
          <div key={k.label} className="kpi-simples"><div className="rotulo">{k.label}</div><div className="valor" style={{ color: k.color }}>—</div></div>
        ))}
      </section>
      <div className="linha">
        <div className="col-principal" style={{ gap: 20 }}>
          <section className="cartao">
            <div className="cartao-topo"><h2>Minhas demandas</h2></div>
            <EstadoVazio>Disponível na Fase 3 (demandas).</EstadoVazio>
          </section>
          <section className="cartao">
            <div className="cartao-topo"><h2>Minha produtividade</h2><span className="texto-suave">Demandas concluídas por mês</span></div>
            <EstadoVazio>Disponível quando o módulo de demandas estiver ativo.</EstadoVazio>
            <p className="nota" style={{ marginTop: 14 }}>Os critérios de produtividade seguirão o modelo da carreira dos fiscais, ainda em definição. Os indicadores não são avaliação automática do servidor.</p>
          </section>
        </div>
        <aside className="col-lateral" style={{ gap: 20 }}>
          <section className="cartao"><h2 style={{ marginBottom: 8 }}>Minha agenda</h2><EstadoVazio>Disponível na Fase 3 (calendário).</EstadoVazio></section>
          <section className="cartao">
            <h2 style={{ marginBottom: 10 }}>Minhas férias e folgas</h2>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, minmax(0, 1fr))', gap: 10, textAlign: 'center' }}>
              {['dias de férias', 'licença-prêmio', 'folgas'].map((r) => (
                <div key={r} style={{ background: 'var(--cor-fundo)', borderRadius: 10, padding: '10px 4px' }}>
                  <div style={{ fontSize: 22, fontWeight: 700, color: 'var(--cor-texto-forte)' }}>—</div><div className="texto-suave">{r}</div>
                </div>
              ))}
            </div>
            <p className="nota" style={{ marginTop: 12 }}>Saldos do RH disponíveis na Fase 2.</p>
            <button type="button" className="botao botao-bloco" style={{ marginTop: 12 }} disabled title="Disponível na Fase 2">Solicitar férias ou folga</button>
          </section>
        </aside>
      </div>
      <p className="nota">Você vê só as próprias demandas, a própria agenda e a própria produtividade.</p>
    </>
  );
}
