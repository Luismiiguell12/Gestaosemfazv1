'use client';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useMemo, useState } from 'react';
import { ImportarPlanilha } from '@/components/ImportarPlanilha';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { Aviso, Campo, Dialogo, EstadoVazio, Selo } from '@/components/ui';
import { mensagemErro } from '@/lib/erros';
import { baixar, gerarArquivo, type Formato } from '@/lib/exportar';
import { dataCurta, dataHora } from '@/lib/formato';
import {
  AVISO_DECRETO, COLUNAS_SEMAD, linhaSemad, nomeCompetencia, num, pct, pdfAnexoII, QUADRIMESTRE, ROTULO_STATUS_AV, TOM_STATUS_AV,
  type Demonstrativo, type Memoria, type StatusAv,
} from '@/lib/produtividade';
import { ehChefia, ehGestorGeral, temModulo, useSessao } from '@/lib/sessao';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';

interface Linha { id: string; servidor_id: string; servidor: string; matricula: string; unidade: string | null; avaliador: string | null; avaliador_id: string | null;
  periodo_inicio: string; periodo_fim: string; status: StatusAv; total_funcional: number | null; prazo_recurso: string | null; pendencias: number; retifica_id: string | null; sou_avaliador: boolean }
interface Designacao { id: string; papel: 'revisora' | 'homologacao'; usuario_id: string; inicio: string; fim: string | null; ato: string | null }

const mesIso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;
type Aba = 'avaliacoes' | 'indicadores' | 'institucional' | 'recursos' | 'homologacao' | 'semad' | 'configuracao';

export default function ProdutividadePage() {
  return <AppShell modulo="produtividade"><Suspense><Produtividade /></Suspense></AppShell>;
}

function Produtividade() {
  const { info } = useSessao();
  const params = useSearchParams();
  const router = useRouter();
  const gestor = ehGestorGeral(info);
  const hoje = new Date();
  const opcoes = useMemo(() => Array.from({ length: 13 }, (_, i) => mesIso(new Date(hoje.getFullYear(), hoje.getMonth() - i, 1))), []); // eslint-disable-line react-hooks/exhaustive-deps
  const [comp, setComp] = useState(params.get('comp') ?? opcoes[1]);
  const desig = useConsulta(async () => supabase.from('prod_designacoes').select('id,papel,usuario_id,inicio,fim,ato').order('inicio', { ascending: false }), []);
  const D = (desig.dados as Designacao[] | null) ?? [];
  const hojeIso = new Date().toISOString().slice(0, 10);
  const minha = (p: string) => D.some((d) => d.papel === p && d.usuario_id === info?.usuario_id && d.inicio <= hojeIso && (!d.fim || d.fim >= hojeIso));
  const institucional = gestor || temModulo(info, 'prod_institucional');
  const abas = ([
    ['avaliacoes', 'Avaliações do mês', true],
    ['indicadores', 'Indicadores de demandas', gestor || ehChefia(info)],
    ['institucional', 'Institucional', true],
    ['recursos', 'Recursos', gestor || minha('revisora')],
    ['homologacao', 'Homologação', gestor || minha('homologacao')],
    ['semad', 'Encaminhamento SEMAD', gestor],
    ['configuracao', 'Configuração', gestor],
  ] as [Aba, string, boolean][]).filter((a) => a[2]);
  const [aba, setAba] = useState<Aba>((params.get('aba') as Aba) ?? 'avaliacoes');

  return (
    <>
      <Cabecalho trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Produtividade' }]} titulo="Produtividade da equipe"
        acoes={<label className="campo campo-leve">Competência
          <select value={comp} onChange={(e) => { setComp(e.target.value); router.replace(`/produtividade?comp=${e.target.value}&aba=${aba}`); }}
            style={{ fontSize: 14, padding: '7px 10px', border: '1px solid var(--cor-borda-campo)', borderRadius: 8, background: '#fff' }}>
            {opcoes.map((o) => <option key={o} value={o}>{nomeCompetencia(o)}</option>)}
          </select></label>} />
      <Aviso tom="info">{AVISO_DECRETO} Os números de demandas são subsídio e prova para a chefia; o sistema não sugere nota.</Aviso>
      <div role="tablist" aria-label="Seções da produtividade" className="abas">
        {abas.map(([id, l]) => <button key={id} type="button" role="tab" className="aba" aria-selected={aba === id} onClick={() => setAba(id)}>{l}</button>)}
      </div>
      {aba === 'avaliacoes' && <Avaliacoes comp={comp} gestor={gestor} />}
      {aba === 'indicadores' && <Indicadores comp={comp} />}
      {aba === 'institucional' && <Institucional podeGerir={institucional} podeHomologar={minha('homologacao')} />}
      {aba === 'recursos' && <Fila comp={comp} status="em_recurso" vazio="Nenhum recurso aguardando decisão nesta competência." />}
      {aba === 'homologacao' && <Homologacao comp={comp} podeHomologar={minha('homologacao')} />}
      {aba === 'semad' && <Semad comp={comp} />}
      {aba === 'configuracao' && <Configuracao designacoes={D} recarregar={() => void desig.recarregar()} />}
    </>
  );
}

function TabelaAvaliacoes({ linhas, selecao }: { linhas: Linha[]; selecao?: { marcados: Set<string>; alternar: (id: string) => void } }) {
  const router = useRouter();
  if (!linhas.length) return null;
  return (
    <div className="tabela-rolagem">
      <table className="tabela tabela-cartoes">
        <thead><tr>{selecao && <th><span className="sr-only">Selecionar</span></th>}<th>Servidor</th><th>Unidade</th><th>Chefia avaliadora</th><th>Período</th><th>Situação</th><th style={{ textAlign: 'right' }}>Pontos /70</th></tr></thead>
        <tbody>
          {linhas.map((l) => {
            const abrir = () => router.push(`/produtividade/avaliacao?id=${l.id}`);
            return (
              <tr key={l.id} className="clicavel" tabIndex={0} onClick={abrir} onKeyDown={(e) => e.key === 'Enter' && abrir()}>
                {selecao && <td onClick={(e) => e.stopPropagation()}><input type="checkbox" aria-label={`Selecionar ${l.servidor}`} checked={selecao.marcados.has(l.id)} onChange={() => selecao.alternar(l.id)} /></td>}
                <td data-rotulo="Servidor"><strong>{l.servidor}</strong><br /><span className="texto-suave">Matrícula {l.matricula}{l.retifica_id ? ' · retificação' : ''}</span></td>
                <td data-rotulo="Unidade">{l.unidade ?? '—'}</td>
                <td data-rotulo="Chefia">{l.avaliador ?? <Selo tom="critico">sem chefia definida</Selo>}{l.sou_avaliador && <><br /><span className="texto-suave">você avalia</span></>}</td>
                <td data-rotulo="Período">{dataCurta(l.periodo_inicio)} a {dataCurta(l.periodo_fim)}</td>
                <td data-rotulo="Situação"><Selo tom={TOM_STATUS_AV[l.status]}>{ROTULO_STATUS_AV[l.status]}</Selo>
                  {l.status === 'rascunho' && l.pendencias > 0 && <><br /><span className="texto-suave">{l.pendencias} indicador(es) pendente(s)</span></>}
                  {l.status === 'ciente' && l.prazo_recurso && <><br /><span className="texto-suave">recurso até {dataCurta(l.prazo_recurso)}</span></>}</td>
                <td data-rotulo="Pontos" style={{ textAlign: 'right' }}>{num(l.total_funcional)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function Avaliacoes({ comp, gestor }: { comp: string; gestor: boolean }) {
  const [versao, setVersao] = useState(0);
  const lista = useConsulta(async () => supabase.rpc('prod_listar', { p_comp: comp }), [comp, versao]);
  const resumo = useConsulta(async () => supabase.rpc('prod_resumo', { p_comp: comp }), [comp, versao]);
  const L = (lista.dados as Linha[] | null) ?? [];
  const [filtro, setFiltro] = useState<'todas' | 'minhas' | 'pendentes'>('todas');
  const [erro, setErro] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const R = (resumo.dados as Record<string, number>[] | null) ?? [];
  const soma = (k: string) => R.reduce((s, x) => s + Number(x[k] ?? 0), 0);
  const filtradas = L.filter((l) => filtro === 'todas' || (filtro === 'minhas' && l.sou_avaliador) || (filtro === 'pendentes' && ['rascunho', 'enviada'].includes(l.status)));
  const abrir = async () => {
    setErro(null); setOk(null);
    const { data, error } = await supabase.rpc('prod_abrir_competencia', { p_comp: comp });
    if (error) return setErro(mensagemErro(error));
    setOk(`${data} avaliação(ões) criada(s) para ${nomeCompetencia(comp)}.`); setVersao((v) => v + 1);
  };
  return (
    <>
      {R.length > 0 && (
        <section aria-label="Resumo da competência" className="kpis">
          {[['Em rascunho', soma('rascunho'), 'var(--cor-texto-forte)'], ['Aguardando ciência', soma('enviada'), 'var(--selo-alerta-fg)'], ['Em recurso', soma('em_recurso'), 'var(--selo-alerta-fg)'],
            ['Homologadas', soma('homologada'), 'var(--cor-positivo)']].map(([l, v, cor]) =>
            <div key={String(l)} className="kpi-simples"><div className="rotulo">{l}</div><div className="valor" style={{ color: String(cor) }}>{v}</div></div>)}
        </section>
      )}
      <section className="cartao">
        <div className="cartao-topo" style={{ flexWrap: 'wrap', gap: 10 }}>
          <div role="tablist" aria-label="Filtro" className="abas">
            {([['todas', 'Todas'], ['minhas', 'Que eu avalio'], ['pendentes', 'Pendentes']] as const).map(([id, l]) =>
              <button key={id} type="button" role="tab" className="aba" style={{ height: 36 }} aria-selected={filtro === id} onClick={() => setFiltro(id)}>{l}</button>)}
          </div>
          {gestor && <button type="button" className="botao botao-primario" onClick={abrir}>{L.length ? 'Incluir servidores novos' : `Abrir ${nomeCompetencia(comp)}`}</button>}
        </div>
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        {ok && <Aviso tom="sucesso">{ok}</Aviso>}
        {lista.carregando && !L.length ? <div className="carregando">Carregando…</div> : !filtradas.length
          ? <EstadoVazio>{L.length ? 'Nada neste filtro.' : gestor ? 'Competência ainda não aberta. Ao abrir, o sistema cria uma avaliação para cada servidor elegível, ligada à chefia imediata.' : 'Nenhuma avaliação visível para você nesta competência.'}</EstadoVazio>
          : <TabelaAvaliacoes linhas={filtradas} />}
      </section>
      <p className="nota">Só entram servidores elegíveis (efetivos, inclusive em cargo em comissão ou função de confiança; fora: comissionados puros, temporários e carreiras excluídas). A chefia imediata vem da estrutura cadastrada ou da chefia designada.</p>
    </>
  );
}

// tela 12 do protótipo: números de demandas como subsídio (sem nota)
function Indicadores({ comp }: { comp: string }) {
  const ate = new Date(Number(comp.slice(0, 4)), Number(comp.slice(5, 7)), 0).toISOString().slice(0, 10);
  const de = new Date(Number(comp.slice(0, 4)), Number(comp.slice(5, 7)) - 3, 1).toISOString().slice(0, 10);
  const un = useConsulta(async () => supabase.rpc('relatorio_demandas_unidade', { p_de: de, p_ate: ate }), [comp]);
  const sv = useConsulta(async () => supabase.rpc('relatorio_demandas_servidor', { p_de: de, p_ate: ate }), [comp]);
  const U = (un.dados as { unidade: string; no_prazo_pct: number | null; concluidas_periodo: number; abertas: number; atrasadas: number }[] | null) ?? [];
  const S = (sv.dados as { servidor: string; unidade: string; recebidas_periodo: number; concluidas_periodo: number; concluidas_no_prazo: number; atrasadas: number }[] | null) ?? [];
  const tot = (k: keyof (typeof U)[number]) => U.reduce((s, x) => s + Number(x[k] ?? 0), 0);
  return (
    <>
      <section aria-label="Resumo do trimestre" className="kpis">
        {[['Concluídas no trimestre', tot('concluidas_periodo')], ['Em aberto', tot('abertas')], ['Atrasadas', tot('atrasadas')], ['Unidades', U.length]].map(([l, v]) =>
          <div key={String(l)} className="kpi-simples"><div className="rotulo">{l}</div><div className="valor">{v}</div></div>)}
      </section>
      <div className="linha">
        <section className="cartao col-lateral">
          <h2>Entregas no prazo por unidade</h2>
          <div className="texto-suave" style={{ marginBottom: 8 }}>% das demandas concluídas dentro do prazo ({dataCurta(de)} a {dataCurta(ate)})</div>
          {!U.length && <EstadoVazio>Sem dados.</EstadoVazio>}
          {U.map((u) => (
            <div key={u.unidade} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 0', fontSize: 13 }}>
              <span style={{ width: 70 }}>{u.unidade}</span>
              <div aria-hidden="true" style={{ flex: 1, height: 10, borderRadius: 5, background: 'var(--cor-divisor)', overflow: 'hidden' }}><div style={{ width: `${u.no_prazo_pct ?? 0}%`, height: '100%', background: 'var(--cor-primaria)' }} /></div>
              <span style={{ width: 44, textAlign: 'right' }}>{u.no_prazo_pct === null ? '—' : `${u.no_prazo_pct}%`}</span>
            </div>
          ))}
        </section>
        <section className="cartao col-principal">
          <h2>Por servidor</h2>
          <div className="tabela-rolagem">
            <table className="tabela tabela-cartoes">
              <thead><tr><th>Servidor</th><th>Unidade</th><th>Recebidas</th><th>Concluídas</th><th>No prazo</th><th>Atrasadas</th></tr></thead>
              <tbody>{S.map((p) => <tr key={p.servidor + p.unidade}><td data-rotulo="Servidor">{p.servidor}</td><td data-rotulo="Unidade">{p.unidade}</td><td data-rotulo="Recebidas">{p.recebidas_periodo}</td>
                <td data-rotulo="Concluídas">{p.concluidas_periodo}</td><td data-rotulo="No prazo">{p.concluidas_no_prazo}</td><td data-rotulo="Atrasadas">{p.atrasadas}</td></tr>)}</tbody>
            </table>
          </div>
          <p className="nota">Demandas com vários responsáveis contam para cada um. Esses números são subsídio para a chefia; não são a nota do servidor.</p>
        </section>
      </div>
    </>
  );
}

function Fila({ comp, status, vazio }: { comp: string; status: StatusAv; vazio: string }) {
  const lista = useConsulta(async () => supabase.rpc('prod_listar', { p_comp: comp }), [comp]);
  const L = ((lista.dados as Linha[] | null) ?? []).filter((l) => l.status === status);
  return <section className="cartao">{L.length ? <TabelaAvaliacoes linhas={L} /> : <EstadoVazio>{vazio}</EstadoVazio>}</section>;
}

function Homologacao({ comp, podeHomologar }: { comp: string; podeHomologar: boolean }) {
  const [versao, setVersao] = useState(0);
  const lista = useConsulta(async () => supabase.rpc('prod_listar', { p_comp: comp }), [comp, versao]);
  const L = ((lista.dados as Linha[] | null) ?? []).filter((l) => l.status === 'aguardando_homologacao');
  const [marc, setMarc] = useState<Set<string>>(new Set());
  const [erro, setErro] = useState<string | null>(null);
  const alternar = (id: string) => setMarc((m) => { const n = new Set(m); if (n.has(id)) n.delete(id); else n.add(id); return n; });
  const homologar = async () => {
    setErro(null);
    const { error } = await supabase.rpc('prod_homologar', { p_ids: [...marc] });
    if (error) return setErro(mensagemErro(error));
    setMarc(new Set()); setVersao((v) => v + 1);
  };
  return (
    <section className="cartao">
      <div className="cartao-topo" style={{ flexWrap: 'wrap', gap: 10 }}>
        <h2>Aguardando homologação · {nomeCompetencia(comp)}</h2>
        {podeHomologar && L.length > 0 && <div className="acoes">
          <button type="button" className="botao" onClick={() => setMarc(new Set(L.map((l) => l.id)))}>Marcar todas</button>
          <button type="button" className="botao botao-primario" disabled={!marc.size} onClick={homologar}>Homologar selecionadas ({marc.size})</button>
        </div>}
      </div>
      {erro && <Aviso tom="critico">{erro}</Aviso>}
      {!podeHomologar && <Aviso tom="info">Só a instância de homologação designada homologa. Designe em Configuração.</Aviso>}
      {L.length ? <TabelaAvaliacoes linhas={L} selecao={podeHomologar ? { marcados: marc, alternar } : undefined} /> : <EstadoVazio>Nada aguardando homologação.</EstadoVazio>}
      <p className="nota">Antes de homologar, confira a regularidade formal, as provas, os critérios e os cálculos (abra cada avaliação). Para devolver à chefia, abra a avaliação. Quem avaliou ou revisou não pode homologar a mesma avaliação.</p>
    </section>
  );
}

// ===== Institucional =====
interface Meta { id: string; ano: number; quadrimestre: number; receita: string; valor: number; memoria: string; fonte: string; retificacao: boolean; vale_para_ciclo: boolean; justificativa: string | null; criado_em: string }
interface Arrec { id: string; ano: number; quadrimestre: number; receita: string; valor: number; fonte: string; origem: string }
interface Resultado { id: string; ano: number; quadrimestre: number; pontos: number; memoria: Memoria; status: 'apurado' | 'homologado'; apurado_em: string; homologado_em: string | null }

function Institucional({ podeGerir, podeHomologar }: { podeGerir: boolean; podeHomologar: boolean }) {
  const hoje = new Date();
  const qAtual = Math.floor(hoje.getMonth() / 4) + 1;
  const [ano, setAno] = useState(hoje.getFullYear());
  const [q, setQ] = useState(qAtual);
  const [versao, setVersao] = useState(0);
  const regra = useConsulta(async () => supabase.from('prod_regras').select('receitas,inicio_vigencia').lte('inicio_vigencia', `${ano}-${String((q - 1) * 4 + 1).padStart(2, '0')}-01`).order('inicio_vigencia', { ascending: false }).limit(1).maybeSingle(), [ano, q]);
  const metas = useConsulta(async () => supabase.from('prod_metas').select('*').eq('ano', ano).eq('quadrimestre', q).order('criado_em'), [ano, q, versao]);
  const arr = useConsulta(async () => supabase.from('prod_arrecadacao').select('*').eq('ano', ano).eq('quadrimestre', q), [ano, q, versao]);
  const res = useConsulta(async () => supabase.from('prod_resultados_inst').select('*').eq('ano', ano).eq('quadrimestre', q).maybeSingle(), [ano, q, versao]);
  const receitas = ((regra.dados as { receitas: { codigo: string; nome: string; peso: number }[] } | null)?.receitas) ?? [];
  const M = (metas.dados as Meta[] | null) ?? []; const A = (arr.dados as Arrec[] | null) ?? []; const R = res.dados as Resultado | null;
  const [erro, setErro] = useState<string | null>(null);
  const [lancar, setLancar] = useState<null | { tipo: 'meta' | 'arrecadacao'; receita: string }>(null);
  const [importar, setImportar] = useState(false);
  const iniciado = new Date() >= new Date(ano, (q - 1) * 4, 1);
  const terminou = new Date() > new Date(ano, q * 4, 0);
  const rpc = async (fn: string, args: Record<string, unknown>) => { setErro(null); const { error } = await supabase.rpc(fn, args); if (error) setErro(mensagemErro(error)); setVersao((v) => v + 1); };

  return (
    <>
      <section className="cartao">
        <div className="cartao-topo" style={{ flexWrap: 'wrap', gap: 10 }}>
          <div className="acoes">
            <label className="campo campo-leve">Ano<select value={ano} onChange={(e) => setAno(Number(e.target.value))}>{[0, 1, 2].map((i) => hoje.getFullYear() + 1 - i).map((a) => <option key={a}>{a}</option>)}</select></label>
            <label className="campo campo-leve">Quadrimestre<select value={q} onChange={(e) => setQ(Number(e.target.value))}>{[1, 2, 3].map((x) => <option key={x} value={x}>{x}º ({QUADRIMESTRE[x]})</option>)}</select></label>
          </div>
          <div className="acoes">
            {podeGerir && <button type="button" className="botao" onClick={() => setImportar(true)}>Importar arrecadação</button>}
            {podeGerir && terminou && R?.status !== 'homologado' && <button type="button" className="botao botao-primario" onClick={() => void rpc('prod_apurar_institucional', { p_ano: ano, p_quadrimestre: q })}>Apurar quadrimestre</button>}
            {podeHomologar && R?.status === 'apurado' && <button type="button" className="botao botao-positivo" onClick={() => void rpc('prod_homologar_institucional', { p_ano: ano, p_quadrimestre: q })}>Homologar resultado</button>}
          </div>
        </div>
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        {iniciado && <Aviso tom="alerta">Quadrimestre iniciado: metas travadas. Correção só por retificação, que não vale para este ciclo.</Aviso>}
        <Aviso tom="info">Não somar dívida ativa nas outras receitas: a recuperação de créditos inscritos em dívida ativa (R5) é lançada separada.</Aviso>
        <div className="tabela-rolagem">
          <table className="tabela tabela-cartoes">
            <thead><tr><th>Receita</th><th style={{ textAlign: 'right' }}>Peso</th><th style={{ textAlign: 'right' }}>Meta</th><th style={{ textAlign: 'right' }}>Arrecadado</th><th>Fonte</th><th><span className="sr-only">Ações</span></th></tr></thead>
            <tbody>
              {receitas.map((r) => {
                const m = M.find((x) => x.receita === r.codigo && !x.retificacao); const a = A.find((x) => x.receita === r.codigo);
                return (
                  <tr key={r.codigo}>
                    <td data-rotulo="Receita"><strong>{r.codigo}</strong> {r.nome}{M.filter((x) => x.receita === r.codigo && x.retificacao).map((x) => <div key={x.id} className="texto-suave">retificação registrada ({num(x.valor)}) — não vale para este ciclo</div>)}</td>
                    <td data-rotulo="Peso" style={{ textAlign: 'right' }}>{pct(Number(r.peso) * 100)}</td>
                    <td data-rotulo="Meta" style={{ textAlign: 'right' }}>{m ? num(m.valor) : '—'}</td>
                    <td data-rotulo="Arrecadado" style={{ textAlign: 'right' }}>{a ? num(a.valor) : '—'}</td>
                    <td data-rotulo="Fonte"><span className="texto-suave">{[m?.fonte && `meta: ${m.fonte}`, a?.fonte && `arrecadação: ${a.fonte}`].filter(Boolean).join(' · ') || '—'}</span></td>
                    <td>{podeGerir && R?.status !== 'homologado' && <span className="acoes" style={{ gap: 8 }}>
                      <button type="button" className="botao-link" onClick={() => setLancar({ tipo: 'meta', receita: r.codigo })}>{iniciado ? 'Retificar meta' : 'Meta'}</button>
                      <button type="button" className="botao-link" onClick={() => setLancar({ tipo: 'arrecadacao', receita: r.codigo })}>Arrecadação</button></span>}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>
      {R && (
        <section className="cartao">
          <div className="cartao-topo"><h2>Resultado {q}º/{ano}: {num(R.pontos)} pontos /30</h2><Selo tom={R.status === 'homologado' ? 'positivo' : 'alerta'}>{R.status === 'homologado' ? `Homologado em ${dataHora(R.homologado_em)}` : 'Apurado, aguardando homologação'}</Selo></div>
          <div className="tabela-rolagem">
            <table className="tabela">
              <thead><tr><th>Receita</th><th style={{ textAlign: 'right' }}>Meta</th><th style={{ textAlign: 'right' }}>Arrecadado</th><th style={{ textAlign: 'right' }}>Índice (≤ 1)</th><th style={{ textAlign: 'right' }}>Peso</th><th style={{ textAlign: 'right' }}>Contribuição</th></tr></thead>
              <tbody>{R.memoria.receitas.map((x) => <tr key={x.receita}><td>{x.nome}</td><td style={{ textAlign: 'right' }}>{num(x.meta)}</td><td style={{ textAlign: 'right' }}>{num(x.arrecadado)}</td>
                <td style={{ textAlign: 'right' }}>{num(x.indice)}</td><td style={{ textAlign: 'right' }}>{pct(Number(x.peso) * 100)}</td><td style={{ textAlign: 'right' }}>{num(x.contribuicao)}</td></tr>)}</tbody>
            </table>
          </div>
          <p className="nota">Memória de cálculo: soma das contribuições {num(R.memoria.soma_contribuicoes)} × 30 = {num(R.pontos)} (limitado a 30). Só vale para os meses depois de homologado.</p>
        </section>
      )}
      {lancar && <LancarInstitucional {...lancar} ano={ano} q={q} retificacao={lancar.tipo === 'meta' && iniciado} fechar={() => setLancar(null)} aoSalvar={() => setVersao((v) => v + 1)} />}
      {importar && <ImportarPlanilha aberto fechar={() => setImportar(false)} titulo="Importar arrecadação (planilha)" rpcPrevia="prod_importar_arrecadacao_previa" rpcImportar="prod_importar_arrecadacao"
        colunas={[{ chave: 'ano', rotulo: 'ano', aliases: ['ano'], obrigatoria: true }, { chave: 'quadrimestre', rotulo: 'quadrimestre', aliases: ['quadrimestre', 'quad'], obrigatoria: true },
          { chave: 'receita', rotulo: 'receita (R1 a R5)', aliases: ['receita r1 a r5', 'receita', 'codigo'], obrigatoria: true }, { chave: 'valor', rotulo: 'valor arrecadado', aliases: ['valor arrecadado', 'valor', 'arrecadado'], obrigatoria: true },
          { chave: 'fonte', rotulo: 'fonte', aliases: ['fonte', 'relatorio'], obrigatoria: true }]}
        nomeModelo="modelo-arrecadacao.csv" exemplo={[String(ano), String(q), 'R1', '1.234.567,89', 'Balancete contábil oficial']}
        explicacao="Arrecadação realizada por receita e quadrimestre (relatório contábil oficial). Dívida ativa (R5) sempre separada. O sistema mostra todos os erros antes e só grava se não houver nenhum." aoImportar={() => setVersao((v) => v + 1)} />}
    </>
  );
}

function LancarInstitucional({ tipo, receita, ano, q, retificacao, fechar, aoSalvar }: { tipo: 'meta' | 'arrecadacao'; receita: string; ano: number; q: number; retificacao: boolean; fechar: () => void; aoSalvar: () => void }) {
  const [f, setF] = useState({ valor: '', memoria: '', fonte: '', justificativa: '' });
  const [arq, setArq] = useState<File | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const salvar = async () => {
    setErro(null);
    const v = Number(f.valor.replace(/\./g, '').replace(',', '.'));
    if (!Number.isFinite(v) || v < 0) return setErro('Valor inválido.');
    let path: string | null = null;
    if (arq) {
      path = `institucional/${crypto.randomUUID()}.${arq.name.toLowerCase().endsWith('.pdf') ? 'pdf' : 'xlsx'}`;
      const up = await supabase.storage.from('produtividade').upload(path, arq, { upsert: false });
      if (up.error) return setErro('Não foi possível enviar o anexo.');
    }
    const { error } = tipo === 'meta'
      ? await supabase.rpc('prod_salvar_meta', { p_ano: ano, p_quadrimestre: q, p_receita: receita, p_valor: v, p_memoria: f.memoria, p_fonte: f.fonte, p_anexo: path, p_justificativa_retificacao: retificacao ? f.justificativa : null })
      : await supabase.rpc('prod_salvar_arrecadacao', { p_ano: ano, p_quadrimestre: q, p_receita: receita, p_valor: v, p_fonte: f.fonte, p_anexo: path });
    if (error) return setErro(mensagemErro(error));
    aoSalvar(); fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo={`${tipo === 'meta' ? (retificacao ? 'Retificar meta' : 'Meta') : 'Arrecadação'} · ${receita} · ${q}º/${ano}`}
      acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={salvar}>Salvar</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        {retificacao && <Aviso tom="alerta">O quadrimestre já começou: esta retificação fica registrada, mas não vale para o ciclo já iniciado.</Aviso>}
        {receita === 'R5' && <Aviso tom="info">Dívida ativa: lance só a recuperação de créditos inscritos (com juros e multas), separada das demais receitas.</Aviso>}
        <Campo rotulo="Valor (R$)"><input inputMode="decimal" maxLength={20} value={f.valor} onChange={(e) => setF({ ...f, valor: e.target.value })} /></Campo>
        {tipo === 'meta' && <Campo rotulo="Memória de cálculo"><textarea rows={3} maxLength={4000} value={f.memoria} onChange={(e) => setF({ ...f, memoria: e.target.value })} /></Campo>}
        <Campo rotulo="Fonte" ajuda={tipo === 'arrecadacao' ? 'Relatório contábil oficial' : 'Ex.: LOA, estudo da ASPLAN'}><input maxLength={500} value={f.fonte} onChange={(e) => setF({ ...f, fonte: e.target.value })} /></Campo>
        {retificacao && <Campo rotulo="Justificativa da retificação"><textarea rows={2} maxLength={2000} value={f.justificativa} onChange={(e) => setF({ ...f, justificativa: e.target.value })} /></Campo>}
        <Campo rotulo="Anexo (opcional)" ajuda="PDF ou planilha"><input type="file" accept="application/pdf,.xlsx" onChange={(e) => setArq(e.target.files?.[0] ?? null)} /></Campo>
      </div>
    </Dialogo>
  );
}

// ===== SEMAD =====
interface Encaminhamento { id: string; versao: number; linhas: Demonstrativo[]; observacao: string | null; gerado_em: string; gerado_por: string }
function Semad({ comp }: { comp: string }) {
  const [versao, setVersao] = useState(0);
  const enc = useConsulta(async () => supabase.from('prod_encaminhamentos').select('*').eq('competencia', comp).order('versao', { ascending: false }), [comp, versao]);
  const corr = useConsulta(async () => supabase.from('prod_correcoes').select('*').eq('competencia', comp).order('em', { ascending: false }), [comp, versao]);
  const E = (enc.dados as Encaminhamento[] | null) ?? [];
  const C = (corr.dados as { id: string; descricao: string; em: string; nova_avaliacao_id: string | null }[] | null) ?? [];
  const [erro, setErro] = useState<string | null>(null);
  const encaminhar = async () => {
    setErro(null);
    const { error } = await supabase.rpc('prod_encaminhar_semad', { p_comp: comp });
    if (error) return setErro(mensagemErro(error));
    setVersao((v) => v + 1);
  };
  const exportar = async (e: Encaminhamento, f: Formato) => {
    const { data: s } = await supabase.rpc('registrar_exportacao', { p_relatorio: 'semad', p_titulo: `Encaminhamento SEMAD ${comp} v${e.versao}`, p_formato: f, p_filtros: { competencia: comp, versao: e.versao }, p_linhas: e.linhas.length });
    void s;
    const blob = await gerarArquivo(f, { titulo: `Adicional de Desempenho e Produtividade – ${nomeCompetencia(comp)} (v${e.versao})`, filtros: [`Encaminhamento à SEMAD em ${dataHora(e.gerado_em)}`],
      colunas: COLUNAS_SEMAD, linhas: e.linhas.map(linhaSemad), geradoPor: 'Gestão SEMFAZ', geradoEm: new Date() });
    baixar(blob, `semad-${comp.slice(0, 7)}-v${e.versao}.${f}`);
  };
  const anexos = async (e: Encaminhamento) => {
    const { PDFDocument } = await import('pdf-lib');
    const final = await PDFDocument.create();
    for (const d of e.linhas) {
      const b = await pdfAnexoII(d, { encaminhamento: `${dataHora(e.gerado_em)} (versão ${e.versao})` });
      const doc = await PDFDocument.load(await b.arrayBuffer());
      for (const pg of await final.copyPages(doc, doc.getPageIndices())) final.addPage(pg);
    }
    baixar(new Blob([(await final.save()) as BlobPart], { type: 'application/pdf' }), `anexo-ii-${comp.slice(0, 7)}-v${e.versao}.pdf`);
  };
  return (
    <>
      <section className="cartao">
        <div className="cartao-topo"><h2>Encaminhamento à SEMAD · {nomeCompetencia(comp)}</h2><button type="button" className="botao botao-primario" onClick={encaminhar}>{E.length ? 'Gerar nova versão' : 'Encaminhar competência'}</button></div>
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        {!E.length ? <EstadoVazio>Nenhum encaminhamento. Só é possível encaminhar com todas as avaliações homologadas.</EstadoVazio> : E.map((e) => (
          <div key={e.id} style={{ borderTop: '1px solid var(--cor-divisor)', padding: '10px 0', display: 'flex', justifyContent: 'space-between', gap: 10, flexWrap: 'wrap' }}>
            <span><strong>Versão {e.versao}</strong> · {e.linhas.length} servidor(es)<br /><span className="texto-suave">gerada em {dataHora(e.gerado_em)}</span></span>
            <span className="acoes"><button type="button" className="botao" onClick={() => void exportar(e, 'xlsx')}>Excel</button><button type="button" className="botao" onClick={() => void exportar(e, 'csv')}>CSV</button>
              <button type="button" className="botao" onClick={() => void anexos(e)}>Anexo II (PDF)</button></span>
          </div>
        ))}
      </section>
      <section className="cartao">
        <h2>Inconsistências e correções</h2>
        {!C.length ? <EstadoVazio>Nenhuma inconsistência registrada.</EstadoVazio> : C.map((x) => <div key={x.id} style={{ borderTop: '1px solid var(--cor-divisor)', padding: '8px 0', fontSize: 13 }}>{dataHora(x.em)} · {x.descricao}{x.nova_avaliacao_id && <> · <Link href={`/produtividade/avaliacao?id=${x.nova_avaliacao_id}`}>retificação</Link></>}</div>)}
        <p className="nota">Inconsistência apontada pela SEMAD: abra a avaliação homologada e use "Retificar" (gera novo registro ligado ao original, com nova homologação). Depois gere nova versão do encaminhamento. Nada é apagado.</p>
      </section>
    </>
  );
}

// ===== Configuração (Secretária/Administrador) =====
function Configuracao({ designacoes, recarregar }: { designacoes: Designacao[]; recarregar: () => void }) {
  const usuarios = useConsulta(async () => supabase.from('usuarios').select('id,servidor_id,perfil,ativo'), []);
  const servidores = useConsulta(async () => supabase.from('servidores').select('id,nome_completo,matricula,chefia_designada_id,situacao').eq('situacao', 'ativo').order('nome_completo'), []);
  const regras = useConsulta(async () => supabase.from('prod_regras').select('*').order('inicio_vigencia', { ascending: false }), []);
  const S = (servidores.dados as { id: string; nome_completo: string; matricula: string; chefia_designada_id: string | null }[] | null) ?? [];
  const Us = (usuarios.dados as { id: string; servidor_id: string; ativo: boolean }[] | null) ?? [];
  const nomeU = (id: string) => S.find((s) => s.id === Us.find((u) => u.id === id)?.servidor_id)?.nome_completo ?? '—';
  const R = (regras.dados as Record<string, unknown>[] | null) ?? [];
  const [f, setF] = useState({ papel: 'revisora', usuario: '', ato: '' });
  const [ch, setCh] = useState({ servidor: '', chefia: '' });
  const [erro, setErro] = useState<string | null>(null);
  const rpc = async (fn: string, a: Record<string, unknown>, depois?: () => void) => { setErro(null); const { error } = await supabase.rpc(fn, a); if (error) return setErro(mensagemErro(error)); depois?.(); recarregar(); void servidores.recarregar(); };
  const atual = R[0] as { versao: number; inicio_vigencia: string; indicadores: { codigo: string; nome: string; maximo: number }[]; faixas: { de: number; ate: number; percentual: number }[];
    minimo_funcional: number; minimo_total: number; prazos: Record<string, number>; afastamentos_exercicio: Record<string, boolean>; receitas: { codigo: string; nome: string; peso: number }[] } | undefined;
  return (
    <>
      {erro && <Aviso tom="critico">{erro}</Aviso>}
      <section className="cartao">
        <h2>Designações</h2>
        <p className="texto-suave">Autoridade revisora (decide recursos) e instância de homologação, definidas por ato do Secretário. Ninguém revisa ou homologa a própria avaliação, nem a que avaliou.</p>
        <div className="tabela-rolagem">
          <table className="tabela tabela-cartoes">
            <thead><tr><th>Papel</th><th>Pessoa</th><th>Início</th><th>Fim</th><th>Ato</th><th><span className="sr-only">Ações</span></th></tr></thead>
            <tbody>{designacoes.map((d) => <tr key={d.id}><td data-rotulo="Papel">{d.papel === 'revisora' ? 'Autoridade revisora' : 'Homologação'}</td><td data-rotulo="Pessoa">{nomeU(d.usuario_id)}</td>
              <td data-rotulo="Início">{dataCurta(d.inicio)}</td><td data-rotulo="Fim">{d.fim ? dataCurta(d.fim) : 'vigente'}</td><td data-rotulo="Ato">{d.ato ?? '—'}</td>
              <td>{!d.fim && <button type="button" className="botao-link" onClick={() => void rpc('prod_encerrar_designacao', { p_id: d.id })}>Encerrar</button>}</td></tr>)}</tbody>
          </table>
        </div>
        <div className="form-linha" style={{ marginTop: 10, alignItems: 'end' }}>
          <Campo rotulo="Papel"><select value={f.papel} onChange={(e) => setF({ ...f, papel: e.target.value })}><option value="revisora">Autoridade revisora</option><option value="homologacao">Instância de homologação</option></select></Campo>
          <Campo rotulo="Pessoa"><select value={f.usuario} onChange={(e) => setF({ ...f, usuario: e.target.value })}><option value="">Selecione…</option>{Us.filter((u) => u.ativo).map((u) => <option key={u.id} value={u.id}>{nomeU(u.id)}</option>)}</select></Campo>
          <Campo rotulo="Ato (opcional)"><input maxLength={300} value={f.ato} onChange={(e) => setF({ ...f, ato: e.target.value })} placeholder="Portaria nº…" /></Campo>
          <button type="button" className="botao botao-primario" disabled={!f.usuario} onClick={() => void rpc('prod_designar', { p_papel: f.papel, p_usuario: f.usuario, p_ato: f.ato || null }, () => setF({ ...f, usuario: '', ato: '' }))}>Designar</button>
        </div>
      </section>
      <section className="cartao">
        <h2>Chefia imediata designada</h2>
        <p className="texto-suave">Para exceções e afastamentos da chefia. Sem designação, vale a estrutura (coordenador → diretor → Secretária).</p>
        <div className="form-linha" style={{ alignItems: 'end' }}>
          <Campo rotulo="Servidor"><select value={ch.servidor} onChange={(e) => setCh({ servidor: e.target.value, chefia: S.find((s) => s.id === e.target.value)?.chefia_designada_id ?? '' })}><option value="">Selecione…</option>{S.map((s) => <option key={s.id} value={s.id}>{s.nome_completo}</option>)}</select></Campo>
          <Campo rotulo="Chefia designada"><select value={ch.chefia} onChange={(e) => setCh({ ...ch, chefia: e.target.value })}><option value="">Pela estrutura</option>{S.filter((s) => s.id !== ch.servidor).map((s) => <option key={s.id} value={s.id}>{s.nome_completo}</option>)}</select></Campo>
          <button type="button" className="botao botao-primario" disabled={!ch.servidor} onClick={() => void rpc('prod_definir_chefia_designada', { p_servidor: ch.servidor, p_chefia: ch.chefia || null })}>Salvar</button>
        </div>
        <ul style={{ fontSize: 13, marginTop: 8 }}>{S.filter((s) => s.chefia_designada_id).map((s) => <li key={s.id}>{s.nome_completo} → {S.find((x) => x.id === s.chefia_designada_id)?.nome_completo}</li>)}</ul>
      </section>
      {atual && (
        <section className="cartao">
          <h2>Regras vigentes · versão {atual.versao} (desde {dataCurta(atual.inicio_vigencia)})</h2>
          <div className="grade-3" style={{ fontSize: 13, gap: 16, alignItems: 'start' }}>
            <div><strong>Indicadores (até 70)</strong><ul>{atual.indicadores.map((i) => <li key={i.codigo}>{i.codigo} · {i.nome}: {i.maximo}</li>)}</ul></div>
            <div><strong>Receitas (até 30)</strong><ul>{atual.receitas.map((r) => <li key={r.codigo}>{r.codigo} · {r.nome}: {pct(r.peso * 100)}</li>)}</ul></div>
            <div><strong>Enquadramento</strong><ul><li>Mínimo funcional: {atual.minimo_funcional}</li><li>Nota mínima: {atual.minimo_total}</li>
              {atual.faixas.map((x) => <li key={x.de}>{x.de} a {x.ate}: {x.percentual}%</li>)}</ul>
              <strong>Prazos (dias úteis)</strong><ul><li>Ciência: {atual.prazos.ciencia}</li><li>Recurso: {atual.prazos.recurso}</li><li>Revisão: {atual.prazos.revisao} (alerta no {atual.prazos.alerta_revisao}º)</li></ul>
              <strong>Contam como exercício</strong><ul>{Object.entries(atual.afastamentos_exercicio).map(([k, v]) => <li key={k}>{k}: {v ? 'sim' : 'não'}</li>)}</ul></div>
          </div>
          <p className="nota">Regras ficam versionadas: mudar cria nova versão com data de início (só de hoje em diante) e nunca recalcula ciclos já abertos. Valores atuais = minuta do decreto (pendente o texto final).</p>
          <NovaVersao atual={R[0]} aoSalvar={() => void regras.recarregar()} />
        </section>
      )}
    </>
  );
}

type Regra = { indicadores: { codigo: string; nome: string; maximo: number }[]; receitas: { codigo: string; nome: string; peso: number }[]; faixas: { de: number; ate: number; percentual: number }[];
  max_funcional: number; max_institucional: number; minimo_funcional: number; minimo_total: number; percentual_maximo: number; prazos: Record<string, number>; afastamentos_exercicio: Record<string, boolean> };
function NovaVersao({ atual, aoSalvar }: { atual: Record<string, unknown>; aoSalvar: () => void }) {
  const [aberto, setAberto] = useState(false);
  const [r, setR] = useState<Regra>(() => structuredClone(atual) as unknown as Regra);
  const [inicio, setInicio] = useState('');
  const [obs, setObs] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const n = (v: string) => Number(v.replace(',', '.'));
  const somaMax = r.indicadores.reduce((s, i) => s + Number(i.maximo), 0);
  const somaPeso = Math.round(r.receitas.reduce((s, x) => s + Number(x.peso), 0) * 10000) / 100;
  const salvar = async () => {
    setErro(null);
    const { error } = await supabase.rpc('prod_criar_regra', { p_dados: { ...r, max_funcional: somaMax, max_institucional: 100 - somaMax, inicio_vigencia: inicio, observacao: obs || null } });
    if (error) return setErro(mensagemErro(error));
    setAberto(false); aoSalvar();
  };
  const inp = (v: number, on: (x: number) => void, w = 70) => <input inputMode="decimal" style={{ width: w }} value={String(v)} onChange={(e) => on(n(e.target.value))} />;
  if (!aberto) return <button type="button" className="botao" onClick={() => setAberto(true)}>Criar nova versão das regras</button>;
  return (
    <div className="form" style={{ borderTop: '1px solid var(--cor-divisor)', paddingTop: 12 }}>
      {erro && <Aviso tom="critico">{erro}</Aviso>}
      <div className="form-linha"><Campo rotulo="Início da vigência"><input type="date" min={new Date().toISOString().slice(0, 10)} value={inicio} onChange={(e) => setInicio(e.target.value)} /></Campo>
        <Campo rotulo="Observação (ex.: decreto publicado)"><input maxLength={2000} value={obs} onChange={(e) => setObs(e.target.value)} /></Campo></div>
      <div className="grade-3" style={{ fontSize: 13, gap: 16, alignItems: 'start' }}>
        <div><strong>Máximos (soma {somaMax}; institucional {100 - somaMax})</strong>
          {r.indicadores.map((i, k) => <div key={i.codigo} className="acoes" style={{ gap: 6, marginTop: 4 }}>{i.codigo} {inp(i.maximo, (x) => { const c = structuredClone(r); c.indicadores[k].maximo = x; setR(c); })}</div>)}</div>
        <div><strong>Pesos % (soma {somaPeso}%, precisa ser 100)</strong>
          {r.receitas.map((x, k) => <div key={x.codigo} className="acoes" style={{ gap: 6, marginTop: 4 }}>{x.codigo} {inp(Math.round(x.peso * 10000) / 100, (v) => { const c = structuredClone(r); c.receitas[k].peso = v / 100; setR(c); })}</div>)}</div>
        <div><strong>Mínimos e faixas</strong>
          <div className="acoes" style={{ gap: 6, marginTop: 4 }}>Funcional ≥ {inp(r.minimo_funcional, (x) => setR({ ...r, minimo_funcional: x }))}</div>
          <div className="acoes" style={{ gap: 6, marginTop: 4 }}>Nota ≥ {inp(r.minimo_total, (x) => setR({ ...r, minimo_total: x }))}</div>
          {r.faixas.map((f, k) => <div key={k} className="acoes" style={{ gap: 4, marginTop: 4 }}>{inp(f.de, (x) => { const c = structuredClone(r); c.faixas[k].de = x; setR(c); }, 50)}a{inp(f.ate, (x) => { const c = structuredClone(r); c.faixas[k].ate = x; setR(c); }, 50)}={inp(f.percentual, (x) => { const c = structuredClone(r); c.faixas[k].percentual = x; setR(c); }, 50)}%</div>)}
          <strong style={{ display: 'block', marginTop: 8 }}>Prazos (dias úteis)</strong>
          {Object.entries(r.prazos).map(([k, v]) => <div key={k} className="acoes" style={{ gap: 6, marginTop: 4 }}>{k} {inp(v, (x) => setR({ ...r, prazos: { ...r.prazos, [k]: x } }), 50)}</div>)}
          <strong style={{ display: 'block', marginTop: 8 }}>Contam como exercício</strong>
          {Object.entries(r.afastamentos_exercicio).map(([k, v]) => <label key={k} className="acoes" style={{ gap: 6 }}><input type="checkbox" checked={v} onChange={(e) => setR({ ...r, afastamentos_exercicio: { ...r.afastamentos_exercicio, [k]: e.target.checked } })} />{k}</label>)}</div>
      </div>
      <div className="acoes"><button type="button" className="botao" onClick={() => setAberto(false)}>Cancelar</button><button type="button" className="botao botao-primario" disabled={!inicio} onClick={salvar}>Salvar nova versão</button></div>
      <p className="nota">O banco confere: soma dos máximos = funcional; pesos = 100%; faixas sem sobreposição e até 30%.</p>
    </div>
  );
}
