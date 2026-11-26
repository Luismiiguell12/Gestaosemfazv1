'use client';
import Link from 'next/link';
import { useMemo, useState } from 'react';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { Aviso, Campo, Dialogo, EstadoVazio } from '@/components/ui';
import { mensagemErro } from '@/lib/erros';
import type { Unidade } from '@/lib/estrutura';
import { ehChefia, ehGestorGeral, useSessao } from '@/lib/sessao';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';

type Tipo = 'compromisso' | 'prazo' | 'demanda' | 'feriado';
interface Evento { tipo: Tipo; id: string; titulo: string; inicio: string; fim: string; dia_inteiro: boolean; unidade_id: string | null; unidade: string | null; local: string | null; descricao: string | null; participantes: { servidor_id: string; nome: string }[]; editavel: boolean }
type Visao = 'mes' | 'semana' | 'dia' | 'lista';

const TZ = 'America/Maceio';
const DOWS = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
const iso = (d: Date) => d.toISOString().slice(0, 10);
const somar = (d: Date, n: number) => new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + n));
const diaLocal = (ts: string) => new Intl.DateTimeFormat('en-CA', { timeZone: TZ }).format(new Date(ts));
const hora = (ts: string) => new Intl.DateTimeFormat('pt-BR', { timeZone: TZ, hour: '2-digit', minute: '2-digit' }).format(new Date(ts));
const diaDe = (e: Evento) => (e.dia_inteiro || e.tipo === 'demanda' || e.tipo === 'feriado' ? e.inicio.slice(0, 10) : diaLocal(e.inicio));
const LEGENDA: [Tipo, string][] = [['demanda', 'Demanda (prazo de entrega)'], ['compromisso', 'Compromisso / reunião'], ['prazo', 'Prazo interno ou legal'], ['feriado', 'Feriado (não conta como dia útil)']];

export default function CalendarioPage() {
  return <AppShell modulo="calendario"><Calendario /></AppShell>;
}

function Calendario() {
  const { info } = useSessao();
  const geral = ehGestorGeral(info);
  const editor = geral || ehChefia(info);
  const hoje = new Date(Date.UTC(new Date().getFullYear(), new Date().getMonth(), new Date().getDate()));
  const [ref, setRef] = useState(hoje);
  const [visao, setVisao] = useState<Visao>('mes');
  const [aba, setAba] = useState<string>('todos');
  const [sel, setSel] = useState<Evento | null>(null);
  const [form, setForm] = useState<Evento | 'novo' | null>(null);
  const [versao, setVersao] = useState(0);

  // intervalo visível
  const [ini, fim] = useMemo(() => {
    if (visao === 'dia') return [ref, ref];
    if (visao === 'semana') { const s = somar(ref, -ref.getUTCDay()); return [s, somar(s, 6)]; }
    const primeiro = new Date(Date.UTC(ref.getUTCFullYear(), ref.getUTCMonth(), 1));
    if (visao === 'lista') return [primeiro, new Date(Date.UTC(ref.getUTCFullYear(), ref.getUTCMonth() + 1, 0))];
    const s = somar(primeiro, -primeiro.getUTCDay());
    return [s, somar(s, 41)];
  }, [ref, visao]);

  const eventos = useConsulta(async () => supabase.rpc('eventos_calendario', { p_inicio: iso(ini), p_fim: iso(fim) }), [iso(ini), iso(fim), versao]);
  const unidades = useConsulta(async () => supabase.from('unidades').select('id,sigla,nome,tipo,unidade_pai_id,ordem,ativa').order('ordem'), []);
  const escopo = useConsulta(async () => supabase.rpc('minhas_unidades_escopo'), []);
  const abas = useMemo(() => {
    const ids = new Set(((escopo.dados as string[] | null) ?? []).map(String));
    const us = ((unidades.dados as Unidade[] | null) ?? []).filter((u) => u.ativa && u.tipo !== 'gabinete' && (geral || ids.has(u.id)));
    return [{ id: 'todos', l: 'Todos' }, ...(geral ? [{ id: 'geral', l: 'Geral do Gabinete' }] : []), ...us.map((u) => ({ id: u.id, l: u.sigla }))];
  }, [unidades.dados, escopo.dados, geral]);

  const E = ((eventos.dados as Evento[] | null) ?? []).filter((e) => aba === 'todos' || e.tipo === 'feriado' || (aba === 'geral' ? e.unidade_id === null : e.unidade_id === aba));
  const doDia = (d: string) => E.filter((e) => diaDe(e) <= d && (e.dia_inteiro || e.tipo !== 'compromisso' ? (e.fim ?? e.inicio).slice(0, 10) : diaLocal(e.fim)) >= d);

  const mudar = (n: number) => {
    if (visao === 'dia') setRef(somar(ref, n));
    else if (visao === 'semana') setRef(somar(ref, 7 * n));
    else setRef(new Date(Date.UTC(ref.getUTCFullYear(), ref.getUTCMonth() + n, 1)));
  };
  const tituloPeriodo = visao === 'dia'
    ? new Intl.DateTimeFormat('pt-BR', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' }).format(ref)
    : new Intl.DateTimeFormat('pt-BR', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(ref);

  const chip = (e: Evento) => (
    <button key={e.tipo + e.id + diaDe(e)} type="button" className={`cal-ev ${e.tipo}`} onClick={() => setSel(e)} aria-label={`${e.titulo}${e.unidade ? ` · ${e.unidade}` : ''}`}>
      {!e.dia_inteiro && e.tipo === 'compromisso' ? `${hora(e.inicio)} ` : ''}{e.titulo}
    </button>
  );

  return (
    <>
      <Cabecalho
        trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Calendário' }]}
        titulo={`Calendário · ${tituloPeriodo}`}
        acoes={<>
          <div role="group" aria-label="Período" style={{ display: 'flex', gap: 6 }}>
            <button type="button" className="botao" aria-label="Anterior" onClick={() => mudar(-1)}>‹</button>
            <button type="button" className="botao" onClick={() => setRef(hoje)}>Hoje</button>
            <button type="button" className="botao" aria-label="Próximo" onClick={() => mudar(1)}>›</button>
          </div>
          <div role="group" aria-label="Visualização" style={{ display: 'flex', border: '1px solid var(--cor-borda-campo)', borderRadius: 10, overflow: 'hidden', background: '#fff' }}>
            {([['mes', 'Mês'], ['semana', 'Semana'], ['dia', 'Dia'], ['lista', 'Lista']] as [Visao, string][]).map(([v, l]) => (
              <button key={v} type="button" aria-pressed={visao === v} onClick={() => setVisao(v)}
                style={{ height: 42, padding: '0 14px', border: 0, fontSize: 14, cursor: 'pointer', background: visao === v ? 'var(--cor-texto-forte)' : '#fff', color: visao === v ? '#fff' : 'var(--cor-texto-forte)' }}>{l}</button>
            ))}
          </div>
          {editor && <button type="button" className="botao botao-primario" onClick={() => setForm('novo')}>+ Novo compromisso</button>}
        </>}
      />

      {abas.length > 1 && (
        <div role="tablist" aria-label="Calendários" className="abas">
          {abas.map((a) => <button key={a.id} type="button" role="tab" aria-selected={aba === a.id} className="aba" style={{ height: 36, fontSize: 13 }} onClick={() => setAba(a.id)}>{a.l}</button>)}
        </div>
      )}
      {eventos.erro && <Aviso tom="critico">{eventos.erro}</Aviso>}

      <div className="linha">
        <section aria-label="Calendário" className="cartao" style={{ flex: '999 1 600px', minWidth: 0, padding: 0, overflow: 'hidden' }}>
          {visao === 'mes' && (
            <div style={{ overflowX: 'auto' }}>
              <div style={{ minWidth: 640 }}>
                <div className="cal-dias cal-cab">{DOWS.map((d) => <div key={d}>{d}</div>)}</div>
                <div className="cal-dias">
                  {Array.from({ length: 42 }, (_, i) => somar(ini, i)).map((d) => {
                    const k = iso(d);
                    const fora = d.getUTCMonth() !== ref.getUTCMonth();
                    const ev = doDia(k);
                    return (
                      <div key={k} className={`cal-cel${fora ? ' fora' : ''}${d.getUTCDay() % 6 === 0 && !fora ? ' fds' : ''}${k === iso(hoje) ? ' hoje' : ''}`}>
                        <div className="cal-num" style={{ color: fora ? '#A3ACBA' : undefined }}>{d.getUTCDate()}</div>
                        {ev.slice(0, 4).map(chip)}
                        {ev.length > 4 && <button type="button" className="link-acao" style={{ background: 'none', border: 0, fontSize: 11, color: 'var(--cor-primaria)', cursor: 'pointer', textAlign: 'left' }} onClick={() => { setRef(d); setVisao('dia'); }}>+{ev.length - 4} mais</button>}
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
          )}
          {(visao === 'semana' || visao === 'dia' || visao === 'lista') && (
            <div style={{ padding: '8px 18px 16px' }}>
              {Array.from({ length: Math.round((fim.getTime() - ini.getTime()) / 86400000) + 1 }, (_, i) => somar(ini, i)).map((d) => {
                const ev = doDia(iso(d));
                if (visao === 'lista' && !ev.length) return null;
                return (
                  <div key={iso(d)} style={{ display: 'flex', gap: 12, padding: '10px 0', borderTop: '1px solid var(--cor-divisor)' }}>
                    <div style={{ width: 56, textAlign: 'center', color: 'var(--cor-primaria)', fontWeight: 700, lineHeight: 1.1, flex: 'none' }}>{String(d.getUTCDate()).padStart(2, '0')}<br /><span style={{ fontSize: 11, fontWeight: 500 }}>{DOWS[d.getUTCDay()]}</span></div>
                    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 4 }}>{ev.length ? ev.map(chip) : <span className="texto-suave">Nada marcado</span>}</div>
                  </div>
                );
              })}
              {visao === 'lista' && !E.length && <EstadoVazio>Nada neste mês.</EstadoVazio>}
            </div>
          )}
        </section>

        <aside className="col-lateral" style={{ flex: '1 1 280px' }}>
          {sel ? (
            <section className="cartao">
              <div className="texto-suave">{({ compromisso: 'Compromisso', prazo: 'Prazo', demanda: 'Prazo de demanda', feriado: 'Feriado' } as const)[sel.tipo]}{sel.unidade ? ` · ${sel.unidade}` : ''}</div>
              <h2 style={{ margin: '4px 0 6px' }}>{sel.titulo}</h2>
              <div style={{ fontSize: 13, color: 'var(--cor-texto-2)', lineHeight: 1.6 }}>
                {new Intl.DateTimeFormat('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit', timeZone: sel.dia_inteiro || sel.tipo !== 'compromisso' ? 'UTC' : TZ }).format(new Date(sel.inicio))}
                {!sel.dia_inteiro && sel.tipo === 'compromisso' ? ` · ${hora(sel.inicio)}–${hora(sel.fim)}` : ''}
                {sel.local && <><br />{sel.local}</>}
                {sel.descricao && <><br />{sel.descricao}</>}
              </div>
              {sel.participantes.length > 0 && <><div className="texto-suave" style={{ marginTop: 12 }}>{sel.tipo === 'demanda' ? 'Responsáveis' : 'Participantes'}</div><div style={{ fontSize: 13, lineHeight: 1.8 }}>{sel.participantes.map((p) => p.nome).join(' · ')}</div></>}
              <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
                {sel.tipo === 'demanda' && <Link href={`/demandas/ficha?id=${sel.id}`} className="botao" style={{ flex: 1 }}>Abrir demanda</Link>}
                {sel.editavel && <button type="button" className="botao" style={{ flex: 1 }} onClick={() => setForm(sel)}>Editar</button>}
                {sel.editavel && <button type="button" className="botao" style={{ flex: 1 }} onClick={() => setForm(sel)}>Participantes</button>}
              </div>
            </section>
          ) : <section className="cartao"><EstadoVazio>Clique num item do calendário para ver os detalhes.</EstadoVazio></section>}
          <section className="cartao" style={{ fontSize: 13, lineHeight: 1.9 }}>
            <h2 style={{ margin: '0 0 6px', fontSize: 15 }}>Legenda</h2>
            {LEGENDA.map(([t, l]) => <div key={t} style={{ display: 'flex', alignItems: 'center', gap: 8 }}><span aria-hidden="true" className={`cal-ev ${t}`} style={{ width: 12, height: 12, padding: 0, borderRadius: 3, borderLeftWidth: 12 }} />{l}</div>)}
            <Link href="/calendario/feriados" style={{ fontSize: 13 }}>Cadastro de feriados</Link>
          </section>
          <section className="aviso aviso-info" style={{ display: 'block' }}>
            <strong>O que cada perfil vê aqui</strong><br />Secretária: todos os calendários e o geral.<br />Diretor: as coordenadorias da diretoria.<br />Coordenador: a própria unidade.<br />Funcionário: só o que o inclui, sem editar.
          </section>
        </aside>
      </div>
      <p className="nota">Feriados municipais vêm do cadastro de feriados.</p>

      {form && <FormCompromisso ev={form === 'novo' ? null : form} abas={abas} geral={geral} fechar={() => setForm(null)} aoSalvar={() => { setVersao((v) => v + 1); setSel(null); }} />}
    </>
  );
}

function FormCompromisso({ ev, abas, geral, fechar, aoSalvar }: { ev: Evento | null; abas: { id: string; l: string }[]; geral: boolean; fechar: () => void; aoSalvar: () => void }) {
  const opcoes = abas.filter((a) => a.id !== 'todos' && (a.id !== 'geral' || geral));
  const [f, setF] = useState({
    unidade: ev ? (ev.unidade_id ?? 'geral') : (opcoes[0]?.id ?? ''), titulo: ev?.titulo ?? '', tipo: (ev?.tipo === 'prazo' ? 'prazo' : 'compromisso') as 'compromisso' | 'prazo',
    data: ev ? diaDe(ev) : new Date().toISOString().slice(0, 10), inicio: ev && !ev.dia_inteiro ? hora(ev.inicio) : '09:00', fim: ev && !ev.dia_inteiro ? hora(ev.fim) : '10:00',
    dia_inteiro: ev?.dia_inteiro ?? false, local: ev?.local ?? '', descricao: ev?.descricao ?? '',
  });
  const [part, setPart] = useState<string[]>(ev?.participantes.map((p) => p.servidor_id) ?? []);
  const [erro, setErro] = useState<string | null>(null);
  const servidores = useConsulta(async () => supabase.from('servidores').select('id,nome_completo,unidade_id').eq('situacao', 'ativo').order('nome_completo'), []);
  const S = ((servidores.dados as { id: string; nome_completo: string; unidade_id: string }[] | null) ?? []);
  const salvar = async () => {
    setErro(null);
    if (f.titulo.trim().length < 2) { setErro('Informe o título.'); return; }
    const inicio = f.dia_inteiro ? `${f.data}T00:00:00-03:00` : `${f.data}T${f.inicio}:00-03:00`;
    const fimTs = f.dia_inteiro ? `${f.data}T23:59:00-03:00` : `${f.data}T${f.fim}:00-03:00`;
    if (fimTs < inicio) { setErro('O fim deve ser depois do início.'); return; }
    const { error } = await supabase.rpc('salvar_compromisso', {
      p_id: ev?.id ?? null,
      p_dados: { unidade_id: f.unidade === 'geral' ? null : f.unidade, titulo: f.titulo, tipo: f.tipo, inicio, fim: fimTs, dia_inteiro: f.dia_inteiro, local: f.local, descricao: f.descricao },
      p_participantes: part,
    });
    if (error) { setErro(mensagemErro(error)); return; }
    aoSalvar(); fechar();
  };
  const cancelar = async () => {
    if (!ev || !window.confirm('Cancelar este compromisso?')) return;
    const { error } = await supabase.rpc('cancelar_compromisso', { p_id: ev.id });
    if (error) { setErro(mensagemErro(error)); return; }
    aoSalvar(); fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo={ev ? 'Editar compromisso' : 'Novo compromisso'} acoes={<>
      {ev && <button type="button" className="botao botao-critico" onClick={cancelar}>Cancelar compromisso</button>}
      <button type="button" className="botao" onClick={fechar}>Fechar</button><button type="button" className="botao botao-primario" onClick={salvar}>Salvar</button>
    </>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        <div className="form-linha">
          <Campo rotulo="Calendário"><select value={f.unidade} disabled={Boolean(ev)} onChange={(e) => setF({ ...f, unidade: e.target.value })}>{opcoes.map((a) => <option key={a.id} value={a.id}>{a.l}</option>)}</select></Campo>
          <Campo rotulo="Tipo"><select value={f.tipo} onChange={(e) => setF({ ...f, tipo: e.target.value as 'compromisso' | 'prazo' })}><option value="compromisso">Compromisso / reunião</option><option value="prazo">Prazo interno ou legal</option></select></Campo>
        </div>
        <Campo rotulo="Título"><input maxLength={200} value={f.titulo} onChange={(e) => setF({ ...f, titulo: e.target.value })} /></Campo>
        <div className="form-linha">
          <Campo rotulo="Data"><input type="date" value={f.data} onChange={(e) => setF({ ...f, data: e.target.value })} /></Campo>
          {!f.dia_inteiro && <Campo rotulo="Início"><input type="time" value={f.inicio} onChange={(e) => setF({ ...f, inicio: e.target.value })} /></Campo>}
          {!f.dia_inteiro && <Campo rotulo="Fim"><input type="time" value={f.fim} onChange={(e) => setF({ ...f, fim: e.target.value })} /></Campo>}
        </div>
        <label style={{ display: 'flex', gap: 8, alignItems: 'center', fontSize: 14, minHeight: 36 }}><input type="checkbox" checked={f.dia_inteiro} onChange={(e) => setF({ ...f, dia_inteiro: e.target.checked })} />Dia inteiro</label>
        <Campo rotulo="Local"><input maxLength={200} value={f.local} onChange={(e) => setF({ ...f, local: e.target.value })} /></Campo>
        <Campo rotulo="Descrição"><textarea rows={2} maxLength={2000} value={f.descricao} onChange={(e) => setF({ ...f, descricao: e.target.value })} /></Campo>
        <fieldset style={{ border: 0, padding: 0, margin: 0 }}>
          <legend style={{ fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Participantes (são avisados)</legend>
          <div style={{ maxHeight: 200, overflowY: 'auto' }}>
            {S.map((s) => (
              <label key={s.id} style={{ display: 'flex', gap: 8, alignItems: 'center', minHeight: 34, fontSize: 14 }}>
                <input type="checkbox" checked={part.includes(s.id)} onChange={(e) => setPart(e.target.checked ? [...part, s.id] : part.filter((x) => x !== s.id))} />{s.nome_completo}
              </label>
            ))}
          </div>
        </fieldset>
      </div>
    </Dialogo>
  );
}
