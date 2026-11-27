'use client';
import { useEffect, useMemo, useState } from 'react';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { Aviso, Campo, Dialogo, EstadoVazio, Selo } from '@/components/ui';
import { ROTULO_PRIORIDADE, type Prioridade } from '@/lib/demandas';
import { mensagemErro } from '@/lib/erros';
import type { Unidade } from '@/lib/estrutura';
import { dataCurta } from '@/lib/formato';
import { ehGestorGeral, useSessao } from '@/lib/sessao';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';

type Periodicidade = 'mensal' | 'trimestral' | 'semestral' | 'anual';
interface Modelo { id: string; titulo: string; descricao: string | null; unidade_id: string; periodicidade: Periodicidade; prazo_dias_uteis: number; prioridade: Prioridade; responsaveis: string[]; checklist: string[]; situacao: 'ativa' | 'pausada' | 'encerrada'; proxima_em: string }
const PER: Record<Periodicidade, string> = { mensal: 'Mensal', trimestral: 'Trimestral', semestral: 'Semestral', anual: 'Anual' };
const SIT = { ativa: ['Ativa', 'positivo'], pausada: ['Pausada', 'alerta'], encerrada: ['Encerrada', 'neutro'] } as const;

export default function RecorrentesPage() {
  return <AppShell modulo="demandas"><Recorrentes /></AppShell>;
}

function Recorrentes() {
  const { info } = useSessao();
  const [versao, setVersao] = useState(0);
  const lista = useConsulta(async () => supabase.from('recorrencias').select('*').order('situacao').order('titulo'), [versao]);
  const unidades = useConsulta(async () => supabase.from('unidades').select('id,sigla,nome,tipo,unidade_pai_id,ordem,ativa').order('ordem'), []);
  const nomes = useConsulta(async () => supabase.from('servidores').select('id,nome_completo'), [versao]);
  const sigla = (id: string) => ((unidades.dados as Unidade[] | null) ?? []).find((u) => u.id === id)?.sigla ?? '—';
  const nome = (id: string) => ((nomes.dados as { id: string; nome_completo: string }[] | null) ?? []).find((s) => s.id === id)?.nome_completo ?? '—';
  const [form, setForm] = useState<Modelo | 'novo' | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const M = (lista.dados as Modelo[] | null) ?? [];
  const situacao = async (id: string, s: Modelo['situacao']) => {
    setErro(null);
    const { error } = await supabase.rpc('mudar_situacao_recorrencia', { p_id: id, p_situacao: s });
    if (error) setErro(mensagemErro(error)); else setVersao((v) => v + 1);
  };

  return (
    <>
      <Cabecalho trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Demandas', href: '/demandas' }, { rotulo: 'Recorrentes' }]} titulo="Demandas recorrentes"
        acoes={<button type="button" className="botao botao-primario" onClick={() => setForm('novo')}>+ Novo modelo</button>} />
      {erro && <Aviso tom="critico">{erro}</Aviso>}
      <section className="cartao">
        <div className="tabela-rolagem">
          <table className="tabela tabela-cartoes">
            <thead><tr><th>Modelo</th><th>Unidade</th><th>Periodicidade</th><th>Prazo</th><th>Responsáveis</th><th>Próxima</th><th>Situação</th><th style={{ textAlign: 'right' }}>Ações</th></tr></thead>
            <tbody>
              {M.map((m) => (
                <tr key={m.id}>
                  <td data-rotulo="Modelo"><strong>{m.titulo}</strong>{m.checklist.length > 0 && <><br /><span className="texto-suave">{m.checklist.length} etapas</span></>}</td>
                  <td data-rotulo="Unidade">{sigla(m.unidade_id)}</td><td data-rotulo="Periodicidade">{PER[m.periodicidade]}</td>
                  <td data-rotulo="Prazo">{m.prazo_dias_uteis} dias úteis</td><td data-rotulo="Responsáveis">{m.responsaveis.map(nome).join(', ')}</td>
                  <td data-rotulo="Próxima">{m.situacao === 'ativa' ? dataCurta(m.proxima_em) : '—'}</td>
                  <td data-rotulo="Situação"><Selo tom={SIT[m.situacao][1]}>{SIT[m.situacao][0]}</Selo></td>
                  <td data-rotulo="Ações" style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
                    {m.situacao !== 'encerrada' && <>
                      <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-primaria)', cursor: 'pointer', minHeight: 36 }} onClick={() => setForm(m)}>Editar</button>
                      <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-primaria)', cursor: 'pointer', minHeight: 36 }} onClick={() => situacao(m.id, m.situacao === 'ativa' ? 'pausada' : 'ativa')}>{m.situacao === 'ativa' ? 'Pausar' : 'Retomar'}</button>
                      <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-critico)', cursor: 'pointer', minHeight: 36 }} onClick={() => window.confirm('Encerrar este modelo? Não será possível reabrir.') && situacao(m.id, 'encerrada')}>Encerrar</button>
                    </>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {!lista.carregando && !M.length && <EstadoVazio>Nenhum modelo recorrente.</EstadoVazio>}
        </div>
      </section>
      <p className="nota">Uma rotina no banco cria cada ocorrência automaticamente (todo dia às 06:05), sem duplicar. Editar o modelo vale só para as próximas. Responsável afastado: o substituto entra na demanda. Diretor e coordenador {ehGestorGeral(info) ? 'e a Secretária ' : ''}gerenciam os modelos.</p>
      {form && <FormModelo modelo={form === 'novo' ? null : form} fechar={() => setForm(null)} aoSalvar={() => setVersao((v) => v + 1)} />}
    </>
  );
}

function FormModelo({ modelo, fechar, aoSalvar }: { modelo: Modelo | null; fechar: () => void; aoSalvar: () => void }) {
  const { info } = useSessao();
  const unidades = useConsulta(async () => supabase.from('unidades').select('id,sigla,nome,tipo,unidade_pai_id,ordem,ativa').order('ordem'), []);
  const escopo = useConsulta(async () => supabase.rpc('minhas_unidades_escopo'), []);
  const opcoes = useMemo(() => {
    const ids = new Set(((escopo.dados as string[] | null) ?? []).map(String));
    return ((unidades.dados as Unidade[] | null) ?? []).filter((u) => u.ativa && (ehGestorGeral(info) || ids.has(u.id)));
  }, [unidades.dados, escopo.dados, info]);
  const [f, setF] = useState({
    titulo: modelo?.titulo ?? '', descricao: modelo?.descricao ?? '', unidade_id: modelo?.unidade_id ?? info?.unidade_id ?? '', periodicidade: modelo?.periodicidade ?? 'mensal' as Periodicidade,
    prazo_dias_uteis: String(modelo?.prazo_dias_uteis ?? 5), prioridade: modelo?.prioridade ?? 'media' as Prioridade, proxima_em: modelo?.proxima_em ?? new Date().toISOString().slice(0, 10),
    checklist: (modelo?.checklist ?? []).join('\n'),
  });
  const [resp, setResp] = useState<string[]>(modelo?.responsaveis ?? []);
  const [erro, setErro] = useState<string | null>(null);
  useEffect(() => { if (!f.unidade_id && opcoes[0]) setF((x) => ({ ...x, unidade_id: opcoes[0].id })); }, [opcoes, f.unidade_id]);
  const servidores = useConsulta(async () => supabase.from('servidores').select('id,nome_completo').eq('unidade_id', f.unidade_id || '00000000-0000-0000-0000-000000000000').eq('situacao', 'ativo').order('nome_completo'), [f.unidade_id]);
  const salvar = async () => {
    setErro(null);
    const { error } = await supabase.rpc('salvar_recorrencia', {
      p_id: modelo?.id ?? null,
      p_dados: { titulo: f.titulo, descricao: f.descricao, unidade_id: f.unidade_id, periodicidade: f.periodicidade, prazo_dias_uteis: Number(f.prazo_dias_uteis), prioridade: f.prioridade, proxima_em: f.proxima_em },
      p_responsaveis: resp, p_checklist: f.checklist.split('\n').map((x) => x.trim()).filter(Boolean).slice(0, 50),
    });
    if (error) { setErro(mensagemErro(error)); return; }
    aoSalvar(); fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo={modelo ? 'Editar modelo recorrente' : 'Novo modelo recorrente'} acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={salvar}>Salvar</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        {modelo && <Aviso tom="info">As alterações valem só para as próximas ocorrências.</Aviso>}
        <Campo rotulo="Título"><input maxLength={200} value={f.titulo} onChange={(e) => setF({ ...f, titulo: e.target.value })} /></Campo>
        <Campo rotulo="Descrição"><textarea rows={2} maxLength={5000} value={f.descricao} onChange={(e) => setF({ ...f, descricao: e.target.value })} /></Campo>
        <div className="form-linha">
          <Campo rotulo="Unidade"><select value={f.unidade_id} disabled={Boolean(modelo)} onChange={(e) => { setF({ ...f, unidade_id: e.target.value }); setResp([]); }}>{opcoes.map((u) => <option key={u.id} value={u.id}>{u.tipo === 'gabinete' ? 'Gabinete' : u.sigla}</option>)}</select></Campo>
          <Campo rotulo="Periodicidade"><select value={f.periodicidade} onChange={(e) => setF({ ...f, periodicidade: e.target.value as Periodicidade })}>{(Object.keys(PER) as Periodicidade[]).map((p) => <option key={p} value={p}>{PER[p]}</option>)}</select></Campo>
        </div>
        <div className="form-linha">
          <Campo rotulo="Próxima ocorrência"><input type="date" value={f.proxima_em} min={new Date().toISOString().slice(0, 10)} onChange={(e) => setF({ ...f, proxima_em: e.target.value })} /></Campo>
          <Campo rotulo="Prazo (dias úteis)"><input type="number" min={1} max={120} value={f.prazo_dias_uteis} onChange={(e) => setF({ ...f, prazo_dias_uteis: e.target.value })} /></Campo>
          <Campo rotulo="Urgência"><select value={f.prioridade} onChange={(e) => setF({ ...f, prioridade: e.target.value as Prioridade })}>{(Object.keys(ROTULO_PRIORIDADE) as Prioridade[]).map((p) => <option key={p} value={p}>{ROTULO_PRIORIDADE[p]}</option>)}</select></Campo>
        </div>
        <fieldset style={{ border: 0, padding: 0, margin: 0 }}>
          <legend style={{ fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Responsáveis</legend>
          {((servidores.dados as { id: string; nome_completo: string }[] | null) ?? []).map((s) => (
            <label key={s.id} style={{ display: 'flex', gap: 8, alignItems: 'center', minHeight: 36, fontSize: 14 }}>
              <input type="checkbox" checked={resp.includes(s.id)} onChange={(e) => setResp(e.target.checked ? [...resp, s.id] : resp.filter((x) => x !== s.id))} />{s.nome_completo}
            </label>
          ))}
        </fieldset>
        <Campo rotulo="Checklist (uma etapa por linha)"><textarea rows={3} value={f.checklist} onChange={(e) => setF({ ...f, checklist: e.target.value })} /></Campo>
      </div>
    </Dialogo>
  );
}
