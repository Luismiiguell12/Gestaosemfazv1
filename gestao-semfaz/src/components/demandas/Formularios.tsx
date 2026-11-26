'use client';
import { useEffect, useMemo, useState } from 'react';
import { Aviso, Campo, Dialogo } from '@/components/ui';
import { ROTULO_ORIGEM_LONGO, ROTULO_PRIORIDADE, type Origem, type Prioridade } from '@/lib/demandas';
import { mensagemErro } from '@/lib/erros';
import type { Unidade } from '@/lib/estrutura';
import { ehGestorGeral, useSessao } from '@/lib/sessao';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';

const ORIGENS: Origem[] = ['processo', 'email', 'whatsapp', 'outra'];
const PRIORIDADES: Prioridade[] = ['baixa', 'media', 'alta', 'critica'];

/** prazo por data ou por "N dias úteis" (calculado no banco, com feriados) */
function CampoPrazo({ valor, mudar }: { valor: { modo: 'dias' | 'data'; dias: string; data: string }; mudar: (v: { modo: 'dias' | 'data'; dias: string; data: string }) => void }) {
  const [previa, setPrevia] = useState<string | null>(null);
  useEffect(() => {
    setPrevia(null);
    const n = Number(valor.dias);
    if (valor.modo !== 'dias' || !Number.isInteger(n) || n < 1 || n > 365) return;
    void supabase.rpc('somar_dias_uteis', { inicio: new Date().toISOString().slice(0, 10), n }).then(({ data }) => setPrevia(data as string));
  }, [valor.modo, valor.dias]);
  return (
    <fieldset style={{ border: 0, padding: 0, margin: 0 }}>
      <legend style={{ fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Prazo</legend>
      <div className="acoes" style={{ gap: 14, fontSize: 14 }}>
        <label style={{ display: 'flex', gap: 6, alignItems: 'center', minHeight: 36 }}><input type="radio" checked={valor.modo === 'dias'} onChange={() => mudar({ ...valor, modo: 'dias' })} />Em dias úteis</label>
        <label style={{ display: 'flex', gap: 6, alignItems: 'center', minHeight: 36 }}><input type="radio" checked={valor.modo === 'data'} onChange={() => mudar({ ...valor, modo: 'data' })} />Data</label>
      </div>
      {valor.modo === 'dias'
        ? <div className="campo"><input type="number" min={1} max={365} aria-label="Dias úteis" value={valor.dias} onChange={(e) => mudar({ ...valor, dias: e.target.value })} /><span className="ajuda">{previa ? `Vence em ${previa.split('-').reverse().join('/')} (sem fins de semana e feriados)` : 'Informe de 1 a 365 dias úteis'}</span></div>
        : <div className="campo"><input type="date" aria-label="Data do prazo" value={valor.data} onChange={(e) => mudar({ ...valor, data: e.target.value })} /></div>}
    </fieldset>
  );
}

async function resolverPrazo(v: { modo: 'dias' | 'data'; dias: string; data: string }): Promise<string | null> {
  if (v.modo === 'data') return v.data || null;
  const n = Number(v.dias);
  if (!Number.isInteger(n) || n < 1) return null;
  const { data } = await supabase.rpc('somar_dias_uteis', { inicio: new Date().toISOString().slice(0, 10), n });
  return (data as string) ?? null;
}

export function NovaDemanda({ fechar, aoSalvar, unidadeInicial }: { fechar: () => void; aoSalvar: (id: string) => void; unidadeInicial?: string }) {
  const { info } = useSessao();
  const unidades = useConsulta(async () => supabase.from('unidades').select('id,sigla,nome,tipo,unidade_pai_id,ordem,ativa').order('ordem'), []);
  const escopo = useConsulta(async () => supabase.rpc('minhas_unidades_escopo'), []);
  const opcoes = useMemo(() => {
    const ids = new Set(((escopo.dados as string[] | null) ?? []).map(String));
    return ((unidades.dados as Unidade[] | null) ?? []).filter((u) => u.ativa && (ehGestorGeral(info) || ids.has(u.id)));
  }, [unidades.dados, escopo.dados, info]);
  const [f, setF] = useState({ titulo: '', descricao: '', unidade_id: unidadeInicial ?? info?.unidade_id ?? '', origem: 'processo' as Origem, numero_processo: '', prioridade: 'media' as Prioridade, checklist: '' });
  const [prazo, setPrazo] = useState({ modo: 'dias' as 'dias' | 'data', dias: '5', data: '' });
  const [resp, setResp] = useState<string[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  useEffect(() => { if (!f.unidade_id && opcoes[0]) setF((x) => ({ ...x, unidade_id: opcoes[0].id })); }, [opcoes, f.unidade_id]);
  const servidores = useConsulta(async () => supabase.from('servidores').select('id,nome_completo').eq('unidade_id', f.unidade_id || '00000000-0000-0000-0000-000000000000').eq('situacao', 'ativo').order('nome_completo'), [f.unidade_id]);

  const salvar = async () => {
    setErro(null);
    if (f.titulo.trim().length < 3) { setErro('Título com pelo menos 3 caracteres.'); return; }
    if (!resp.length) { setErro('Indique pelo menos um responsável.'); return; }
    setSalvando(true);
    const p = await resolverPrazo(prazo);
    const { data, error } = await supabase.rpc('criar_demanda', {
      p_dados: { titulo: f.titulo, descricao: f.descricao, unidade_id: f.unidade_id, origem: f.origem, numero_processo: f.numero_processo, prioridade: f.prioridade, prazo: p },
      p_responsaveis: resp, p_checklist: f.checklist.split('\n').map((x) => x.trim()).filter(Boolean).slice(0, 50),
    });
    setSalvando(false);
    if (error) { setErro(mensagemErro(error)); return; }
    aoSalvar(data as string);
  };

  return (
    <Dialogo aberto fechar={fechar} titulo="Nova demanda" acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" disabled={salvando} onClick={salvar}>Criar e distribuir</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        <Campo rotulo="Título"><input maxLength={200} value={f.titulo} onChange={(e) => setF({ ...f, titulo: e.target.value })} /></Campo>
        <Campo rotulo="Descrição"><textarea rows={3} maxLength={5000} value={f.descricao} onChange={(e) => setF({ ...f, descricao: e.target.value })} /></Campo>
        <div className="form-linha">
          <Campo rotulo="Unidade"><select value={f.unidade_id} onChange={(e) => { setF({ ...f, unidade_id: e.target.value }); setResp([]); }}>{opcoes.map((u) => <option key={u.id} value={u.id}>{u.tipo === 'gabinete' ? 'Gabinete' : u.sigla}</option>)}</select></Campo>
          <Campo rotulo="Urgência"><select value={f.prioridade} onChange={(e) => setF({ ...f, prioridade: e.target.value as Prioridade })}>{PRIORIDADES.map((p) => <option key={p} value={p}>{ROTULO_PRIORIDADE[p]}</option>)}</select></Campo>
        </div>
        <div className="form-linha">
          <Campo rotulo="Origem"><select value={f.origem} onChange={(e) => setF({ ...f, origem: e.target.value as Origem })}>{ORIGENS.map((o) => <option key={o} value={o}>{ROTULO_ORIGEM_LONGO[o]}</option>)}</select></Campo>
          <Campo rotulo="Nº do processo (opcional)"><input maxLength={60} value={f.numero_processo} onChange={(e) => setF({ ...f, numero_processo: e.target.value })} /></Campo>
        </div>
        <CampoPrazo valor={prazo} mudar={setPrazo} />
        <fieldset style={{ border: 0, padding: 0, margin: 0 }}>
          <legend style={{ fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Responsáveis (um ou vários)</legend>
          <div style={{ maxHeight: 180, overflowY: 'auto' }}>
            {((servidores.dados as { id: string; nome_completo: string }[] | null) ?? []).map((s) => (
              <label key={s.id} style={{ display: 'flex', gap: 8, alignItems: 'center', minHeight: 36, fontSize: 14 }}>
                <input type="checkbox" checked={resp.includes(s.id)} onChange={(e) => setResp(e.target.checked ? [...resp, s.id] : resp.filter((x) => x !== s.id))} />{s.nome_completo}
              </label>
            ))}
          </div>
        </fieldset>
        <Campo rotulo="Checklist (opcional, uma etapa por linha)"><textarea rows={3} value={f.checklist} onChange={(e) => setF({ ...f, checklist: e.target.value })} /></Campo>
      </div>
    </Dialogo>
  );
}

export function SugerirDemanda({ fechar, aoSalvar }: { fechar: () => void; aoSalvar: () => void }) {
  const [f, setF] = useState({ titulo: '', descricao: '', origem: 'email' as Origem, numero_processo: '', prioridade: 'media' as Prioridade, prazo: '' });
  const [erro, setErro] = useState<string | null>(null);
  const [ok, setOk] = useState(false);
  const salvar = async () => {
    setErro(null);
    if (f.titulo.trim().length < 3) { setErro('Título com pelo menos 3 caracteres.'); return; }
    const { error } = await supabase.rpc('sugerir_demanda', { p_dados: { ...f, prazo: f.prazo || null } });
    if (error) { setErro(mensagemErro(error)); return; }
    setOk(true); aoSalvar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo="Sugerir demanda" acoes={ok ? <button type="button" className="botao" onClick={fechar}>Fechar</button>
      : <><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={salvar}>Enviar sugestão</button></>}>
      {ok ? <Aviso tom="sucesso">Sugestão enviada. Ela só vale depois da aprovação da chefia da sua unidade.</Aviso> : (
        <div className="form">
          {erro && <Aviso tom="critico">{erro}</Aviso>}
          <Campo rotulo="Título"><input maxLength={200} value={f.titulo} onChange={(e) => setF({ ...f, titulo: e.target.value })} /></Campo>
          <Campo rotulo="Descrição"><textarea rows={3} maxLength={5000} value={f.descricao} onChange={(e) => setF({ ...f, descricao: e.target.value })} /></Campo>
          <div className="form-linha">
            <Campo rotulo="Origem"><select value={f.origem} onChange={(e) => setF({ ...f, origem: e.target.value as Origem })}>{ORIGENS.map((o) => <option key={o} value={o}>{ROTULO_ORIGEM_LONGO[o]}</option>)}</select></Campo>
            <Campo rotulo="Urgência"><select value={f.prioridade} onChange={(e) => setF({ ...f, prioridade: e.target.value as Prioridade })}>{PRIORIDADES.map((p) => <option key={p} value={p}>{ROTULO_PRIORIDADE[p]}</option>)}</select></Campo>
          </div>
          <div className="form-linha">
            <Campo rotulo="Nº do processo (opcional)"><input maxLength={60} value={f.numero_processo} onChange={(e) => setF({ ...f, numero_processo: e.target.value })} /></Campo>
            <Campo rotulo="Prazo sugerido (opcional)"><input type="date" value={f.prazo} onChange={(e) => setF({ ...f, prazo: e.target.value })} /></Campo>
          </div>
        </div>
      )}
    </Dialogo>
  );
}
