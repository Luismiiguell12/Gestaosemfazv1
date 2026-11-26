'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { Suspense, useMemo, useState, type DragEvent } from 'react';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { NovaDemanda, SugerirDemanda } from '@/components/demandas/Formularios';
import { Aviso, Campo, Dialogo, EstadoVazio, Selo } from '@/components/ui';
import {
  COLUNAS, COR_PRIORIDADE, iniciaisCurtas, ROTULO_ORIGEM, ROTULO_PRIORIDADE, ROTULO_STATUS, textoPrazo, TOM_STATUS,
  type DemandaLista, type Origem, type Prioridade, type StatusDemanda,
} from '@/lib/demandas';
import { mensagemErro } from '@/lib/erros';
import { dataCurta } from '@/lib/formato';
import { ehChefia, ehGestorGeral, useSessao } from '@/lib/sessao';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';

export default function DemandasPage() {
  return <AppShell modulo="demandas"><Suspense><Quadro /></Suspense></AppShell>;
}

const selectFiltro = { fontSize: 14, padding: '8px 10px', border: '1px solid var(--cor-borda-campo)', borderRadius: 8, background: '#fff', minWidth: 150, minHeight: 40 } as const;

function Quadro() {
  const { info } = useSessao();
  const router = useRouter();
  const chefia = ehGestorGeral(info) || ehChefia(info);
  const [versao, setVersao] = useState(0);
  const recarregar = () => setVersao((v) => v + 1);
  const lista = useConsulta(async () => supabase.rpc('listar_demandas', { p_incluir_encerradas_dias: 60 }), [versao]);
  const todas = (lista.dados as DemandaLista[] | null) ?? [];

  const [visao, setVisao] = useState<'quadro' | 'lista'>('quadro');
  const [f, setF] = useState({ unidade: '', responsavel: '', origem: '', prioridade: '', busca: '' });
  const [verSugestoes, setVerSugestoes] = useState(false);
  const [nova, setNova] = useState(false);
  const [sugerir, setSugerir] = useState(false);
  const [decidir, setDecidir] = useState<{ d: DemandaLista; aprovar: boolean } | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [arrastando, setArrastando] = useState<string | null>(null);

  const unidades = useMemo(() => [...new Map(todas.map((d) => [d.unidade_id, d.unidade])).entries()].sort((a, b) => a[1].localeCompare(b[1])), [todas]);
  const pessoas = useMemo(() => [...new Map(todas.flatMap((d) => d.responsaveis.map((r) => [r.servidor_id, r.nome] as const))).entries()].sort((a, b) => a[1].localeCompare(b[1], 'pt-BR')), [todas]);
  const sugestoes = todas.filter((d) => d.status === 'sugerida' && d.criado_por !== info?.usuario_id);
  const filtradas = todas.filter((d) => d.status !== 'sugerida' && d.status !== 'recusada' && d.status !== 'cancelada'
    && (!f.unidade || d.unidade_id === f.unidade)
    && (!f.responsavel || d.responsaveis.some((r) => r.servidor_id === f.responsavel))
    && (!f.origem || d.origem === f.origem)
    && (!f.prioridade || d.prioridade === f.prioridade)
    && (!f.busca || `${d.titulo} ${d.numero_processo ?? ''} #${d.numero}`.toLowerCase().includes(f.busca.toLowerCase())));
  const minhasSugestoes = todas.filter((d) => d.status === 'sugerida' && d.criado_por === info?.usuario_id);

  const titulo = info?.perfil === 'funcionario' ? 'Minhas demandas'
    : info?.perfil === 'diretor' || info?.perfil === 'coordenador' ? `Demandas · ${info.unidade_sigla ?? ''}` : 'Demandas';

  const mover = async (id: string, status: StatusDemanda) => {
    setErro(null);
    const { error } = await supabase.rpc('mudar_status_demanda', { p_id: id, p_status: status });
    if (error) setErro(mensagemErro(error));
    recarregar();
  };
  const soltar = (e: DragEvent, status: StatusDemanda) => {
    e.preventDefault();
    const id = e.dataTransfer.getData('text/plain');
    setArrastando(null);
    const d = todas.find((x) => x.id === id);
    if (d && d.status !== status) void mover(id, status);
  };

  return (
    <>
      <Cabecalho
        trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Demandas' }]}
        titulo={titulo}
        acoes={<>
          <div role="group" aria-label="Visualização" style={{ display: 'flex', border: '1px solid var(--cor-borda-campo)', borderRadius: 10, overflow: 'hidden', background: '#fff' }}>
            {(['lista', 'quadro'] as const).map((v) => (
              <button key={v} type="button" aria-pressed={visao === v} onClick={() => setVisao(v)}
                style={{ height: 42, padding: '0 14px', border: 0, fontSize: 14, cursor: 'pointer', background: visao === v ? 'var(--cor-texto-forte)' : '#fff', color: visao === v ? '#fff' : 'var(--cor-texto-forte)' }}>
                {v === 'lista' ? 'Lista' : 'Quadro'}
              </button>
            ))}
            <Link href="/calendario" style={{ height: 42, padding: '0 14px', display: 'flex', alignItems: 'center', fontSize: 14, color: 'var(--cor-texto-forte)', textDecoration: 'none' }}>Calendário</Link>
          </div>
          {chefia && <Link href="/demandas/recorrentes" className="botao">Recorrentes</Link>}
          {chefia
            ? <button type="button" className="botao botao-primario" onClick={() => setNova(true)}>+ Nova demanda</button>
            : <button type="button" className="botao botao-primario" onClick={() => setSugerir(true)}>+ Sugerir demanda</button>}
        </>}
      />

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, alignItems: 'flex-end' }}>
        {unidades.length > 1 && (
          <label className="campo campo-leve">Unidade<select style={selectFiltro} value={f.unidade} onChange={(e) => setF({ ...f, unidade: e.target.value })}><option value="">Todas</option>{unidades.map(([id, s]) => <option key={id} value={id}>{s}</option>)}</select></label>
        )}
        <label className="campo campo-leve">Responsável<select style={selectFiltro} value={f.responsavel} onChange={(e) => setF({ ...f, responsavel: e.target.value })}><option value="">Todos</option>{pessoas.map(([id, n]) => <option key={id} value={id}>{n}</option>)}</select></label>
        <label className="campo campo-leve">Origem<select style={selectFiltro} value={f.origem} onChange={(e) => setF({ ...f, origem: e.target.value })}><option value="">Todas</option>{(Object.keys(ROTULO_ORIGEM) as Origem[]).map((o) => <option key={o} value={o}>{ROTULO_ORIGEM[o]}</option>)}</select></label>
        <label className="campo campo-leve">Urgência<select style={selectFiltro} value={f.prioridade} onChange={(e) => setF({ ...f, prioridade: e.target.value })}><option value="">Todas</option>{(Object.keys(ROTULO_PRIORIDADE) as Prioridade[]).map((p) => <option key={p} value={p}>{ROTULO_PRIORIDADE[p]}</option>)}</select></label>
        <label className="campo campo-leve" style={{ flex: '1 1 220px' }}>Buscar<input type="search" placeholder="Título ou nº do processo" value={f.busca} maxLength={100} onChange={(e) => setF({ ...f, busca: e.target.value })} style={{ font: 'inherit', fontSize: 14, padding: '8px 10px', border: '1px solid var(--cor-borda-campo)', borderRadius: 8, minHeight: 40 }} /></label>
      </div>

      {chefia && sugestoes.length > 0 && (
        <section role="status" className="aviso aviso-info" style={{ justifyContent: 'space-between', alignItems: 'center', fontSize: 14, flexWrap: 'wrap' }}>
          <span><strong>{sugestoes.length} demanda{sugestoes.length > 1 ? 's' : ''} sugerida{sugestoes.length > 1 ? 's' : ''} por funcionários</strong> aguarda{sugestoes.length > 1 ? 'm' : ''} a aprovação do diretor ou do coordenador.</span>
          <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-primaria)', fontWeight: 600, cursor: 'pointer', fontSize: 14 }} onClick={() => setVerSugestoes(!verSugestoes)}>{verSugestoes ? 'Fechar sugestões' : 'Revisar sugestões'}</button>
        </section>
      )}
      {verSugestoes && (
        <section className="cartao">
          <h2>Sugestões pendentes</h2>
          {sugestoes.map((d) => (
            <div key={d.id} className="item-lista" style={{ display: 'flex', flexWrap: 'wrap', gap: 10, justifyContent: 'space-between', alignItems: 'center' }}>
              <span><Link href={`/demandas/ficha?id=${d.id}`}><strong>#{d.numero} {d.titulo}</strong></Link><br /><span className="meta">{d.unidade} · {ROTULO_ORIGEM[d.origem]} · {ROTULO_PRIORIDADE[d.prioridade]}{d.prazo ? ` · prazo sugerido ${dataCurta(d.prazo)}` : ''}</span></span>
              <span className="acoes" style={{ gap: 8 }}>
                <button type="button" className="botao" style={{ minHeight: 40 }} onClick={() => setDecidir({ d, aprovar: false })}>Recusar</button>
                <button type="button" className="botao botao-escuro" style={{ minHeight: 40 }} onClick={() => setDecidir({ d, aprovar: true })}>Aprovar</button>
              </span>
            </div>
          ))}
        </section>
      )}
      {minhasSugestoes.length > 0 && <Aviso tom="info">{minhasSugestoes.length} sugestão(ões) sua(s) aguardando a chefia: {minhasSugestoes.map((d) => `#${d.numero} ${d.titulo}`).join('; ')}.</Aviso>}
      {erro && <Aviso tom="critico">{erro}</Aviso>}
      {lista.erro && <Aviso tom="critico">{lista.erro}</Aviso>}

      {visao === 'quadro' ? (
        <div style={{ overflowX: 'auto' }}>
          <div className="quadro">
            {COLUNAS.map((c) => {
              const cards = filtradas.filter((d) => d.status === c.status);
              return (
                <section key={c.status} className="coluna-quadro" data-alvo={arrastando ? 'true' : undefined} aria-label={c.nome}
                  onDragOver={(e) => e.preventDefault()} onDrop={(e) => soltar(e, c.status)}>
                  <h2>{c.nome}<span>{cards.length}</span></h2>
                  {cards.map((d) => <Cartao key={d.id} d={d} arrastavel={chefia || d.sou_responsavel} aoArrastar={setArrastando} abrir={() => router.push(`/demandas/ficha?id=${d.id}`)} />)}
                </section>
              );
            })}
          </div>
        </div>
      ) : (
        <section className="cartao">
          <div className="tabela-rolagem">
            <table className="tabela tabela-cartoes">
              <thead><tr><th>Nº</th><th>Demanda</th><th>Unidade</th><th>Responsáveis</th><th>Urgência</th><th>Situação</th><th>Prazo</th></tr></thead>
              <tbody>
                {filtradas.map((d) => {
                  const p = textoPrazo(d);
                  return (
                    <tr key={d.id} className="clicavel" tabIndex={0} onClick={() => router.push(`/demandas/ficha?id=${d.id}`)} onKeyDown={(e) => e.key === 'Enter' && router.push(`/demandas/ficha?id=${d.id}`)}>
                      <td data-rotulo="Nº">#{d.numero}</td>
                      <td data-rotulo="Demanda"><strong>{d.titulo}</strong>{d.etapas_total > 0 && <><br /><span className="texto-suave">{d.etapas_feitas} de {d.etapas_total} etapas</span></>}</td>
                      <td data-rotulo="Unidade">{d.unidade}</td>
                      <td data-rotulo="Responsáveis">{d.responsaveis.map((r) => r.nome + (r.papel === 'substituto' ? ' (substituto)' : '')).join(', ') || '—'}</td>
                      <td data-rotulo="Urgência"><span className="selo" style={{ background: COR_PRIORIDADE[d.prioridade][0], color: COR_PRIORIDADE[d.prioridade][1] }}>{ROTULO_PRIORIDADE[d.prioridade]}</span></td>
                      <td data-rotulo="Situação"><Selo tom={TOM_STATUS[d.status]}>{ROTULO_STATUS[d.status]}</Selo></td>
                      <td data-rotulo="Prazo" style={{ color: p.atrasada ? 'var(--cor-critico)' : undefined, fontWeight: p.atrasada ? 600 : 400 }}>{p.texto}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </section>
      )}
      {!lista.carregando && filtradas.length === 0 && <div className="cartao"><EstadoVazio>Nenhuma demanda com esses filtros.</EstadoVazio></div>}
      <p className="nota">Prazos contados em dias úteis, sem fins de semana e feriados cadastrados. Arrastar um cartão muda o status e fica no histórico.</p>

      {nova && <NovaDemanda fechar={() => setNova(false)} aoSalvar={(id) => router.push(`/demandas/ficha?id=${id}`)} />}
      {sugerir && <SugerirDemanda fechar={() => setSugerir(false)} aoSalvar={recarregar} />}
      {decidir && <DecidirSugestao d={decidir.d} aprovar={decidir.aprovar} fechar={() => setDecidir(null)} aoSalvar={recarregar} />}
    </>
  );
}

function Cartao({ d, arrastavel, aoArrastar, abrir }: { d: DemandaLista; arrastavel: boolean; aoArrastar: (id: string | null) => void; abrir: () => void }) {
  const p = textoPrazo(d);
  const [bg, fg, borda] = COR_PRIORIDADE[d.prioridade];
  return (
    <article className="cartao-demanda" style={{ borderTopColor: borda }} draggable={arrastavel} tabIndex={0} role="link" aria-label={`#${d.numero} ${d.titulo}`}
      onDragStart={(e) => { e.dataTransfer.setData('text/plain', d.id); aoArrastar(d.id); }} onDragEnd={() => aoArrastar(null)}
      onClick={abrir} onKeyDown={(e) => e.key === 'Enter' && abrir()}>
      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 6, fontSize: 11, fontWeight: 600 }}>
        <span style={{ color: 'var(--cor-texto-suave)' }}>{d.unidade} · {ROTULO_ORIGEM[d.origem]}</span>
        <span style={{ padding: '1px 7px', borderRadius: 8, background: bg, color: fg }}>{ROTULO_PRIORIDADE[d.prioridade]}</span>
      </div>
      <div style={{ fontSize: 14, fontWeight: 600, lineHeight: 1.3 }}>{d.titulo}</div>
      {d.etapas_total > 0 && <div className="texto-suave" style={{ fontSize: 11 }}>{d.etapas_feitas} de {d.etapas_total} etapas</div>}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: 12 }}>
        <div style={{ display: 'flex' }}>
          {d.responsaveis.slice(0, 4).map((r) => (
            <span key={r.servidor_id} title={r.nome + (r.papel === 'substituto' ? ' (substituto)' : '')} className="avatar-mini" style={{ outline: r.papel === 'substituto' ? '2px dashed var(--cor-alerta)' : undefined }}>{iniciaisCurtas(r.nome)}</span>
          ))}
        </div>
        <span style={{ color: p.atrasada ? 'var(--cor-critico)' : 'var(--cor-texto-2)', fontWeight: 600 }}>{p.texto}</span>
      </div>
    </article>
  );
}

function DecidirSugestao({ d, aprovar, fechar, aoSalvar }: { d: DemandaLista; aprovar: boolean; fechar: () => void; aoSalvar: () => void }) {
  const servidores = useConsulta(async () => supabase.from('servidores').select('id,nome_completo').eq('unidade_id', d.unidade_id).eq('situacao', 'ativo').order('nome_completo'), [d.unidade_id]);
  const [sel, setSel] = useState<string[]>([]);
  const [prazo, setPrazo] = useState(d.prazo ?? '');
  const [coment, setComent] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const salvar = async () => {
    setErro(null);
    const { error } = await supabase.rpc('decidir_sugestao', { p_id: d.id, p_aprovar: aprovar, p_responsaveis: sel, p_prazo: prazo || null, p_comentario: coment || null });
    if (error) { setErro(mensagemErro(error)); return; }
    aoSalvar(); fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo={`${aprovar ? 'Aprovar' : 'Recusar'} sugestão #${d.numero}`} acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className={`botao ${aprovar ? 'botao-positivo' : 'botao-critico'}`} onClick={salvar}>{aprovar ? 'Aprovar' : 'Recusar'}</button></>}>
      <div className="form">
        <p style={{ margin: 0 }}><strong>{d.titulo}</strong></p>
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        {aprovar && (
          <>
            <fieldset style={{ border: 0, padding: 0, margin: 0 }}>
              <legend style={{ fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Responsáveis</legend>
              {((servidores.dados as { id: string; nome_completo: string }[] | null) ?? []).map((s) => (
                <label key={s.id} style={{ display: 'flex', gap: 8, alignItems: 'center', minHeight: 36, fontSize: 14 }}>
                  <input type="checkbox" checked={sel.includes(s.id)} onChange={(e) => setSel(e.target.checked ? [...sel, s.id] : sel.filter((x) => x !== s.id))} />{s.nome_completo}
                </label>
              ))}
            </fieldset>
            <Campo rotulo="Prazo"><input type="date" value={prazo} onChange={(e) => setPrazo(e.target.value)} /></Campo>
          </>
        )}
        <Campo rotulo={aprovar ? 'Comentário (opcional)' : 'Comentário (obrigatório)'}><textarea rows={2} maxLength={1000} value={coment} onChange={(e) => setComent(e.target.value)} /></Campo>
      </div>
    </Dialogo>
  );
}
