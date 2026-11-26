'use client';
import { Suspense, useEffect, useMemo, useState } from 'react';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { Icone } from '@/components/layout/Icone';
import { ImportarPlanilha } from '@/components/ImportarPlanilha';
import { Aviso, Campo, Dialogo, EstadoVazio } from '@/components/ui';
import { mensagemErro } from '@/lib/erros';
import type { Unidade } from '@/lib/estrutura';
import { dataCurta } from '@/lib/formato';
import { COLUNAS_SALDOS } from '@/lib/planilha';
import { ehGestorGeral, useSessao } from '@/lib/sessao';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';

type Tipo = 'ferias' | 'licenca_premio' | 'folga';
type Status = 'solicitado' | 'aprovado' | 'recusado' | 'cancelado';
interface Servidor { id: string; nome_completo: string; matricula: string; cargo_id: string; unidade_id: string; situacao: string }
interface Afastamento { id: string; servidor_id: string; tipo: Tipo; inicio: string; fim: string; status: Status; conflito_mesmo_cargo: boolean; substituto_id: string | null; observacao: string | null; solicitado_por: string }
interface Saldo { servidor_id: string; ferias_dias: number; licenca_premio_dias: number; folgas: number; fonte: string; atualizado_em: string }
interface Conflito { nome: string; inicio: string; fim: string; status: Status }

const TIPO: Record<Tipo, string> = { ferias: 'Férias', licenca_premio: 'Licença-prêmio', folga: 'Folga' };
const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
const dd = (iso: string) => iso.slice(8, 10);
const ddmm = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;
const diasCorridos = (a: string, b: string) => Math.round((Date.parse(b) - Date.parse(a)) / 86400000) + 1;

export default function FeriasPage() {
  return <AppShell modulo="ferias"><Suspense><Escala /></Suspense></AppShell>;
}

function Escala() {
  const { info } = useSessao();
  const geral = ehGestorGeral(info);
  const chefia = geral || info?.perfil === 'diretor' || info?.perfil === 'coordenador';
  const anoAtual = new Date().getFullYear();
  const [ano, setAno] = useState(anoAtual);
  const [versao, setVersao] = useState(0);
  const recarregar = () => setVersao((v) => v + 1);

  const unidades = useConsulta(async () => supabase.from('unidades').select('id,sigla,nome,tipo,unidade_pai_id,ordem,ativa').order('ordem'), []);
  const escopo = useConsulta(async () => supabase.rpc('minhas_unidades_escopo'), []);
  const opcoes = useMemo(() => {
    const ids = new Set(((escopo.dados as string[] | null) ?? []).map(String));
    return ((unidades.dados as Unidade[] | null) ?? []).filter((u) => u.ativa && (ids.has(u.id) || u.id === info?.unidade_id));
  }, [unidades.dados, escopo.dados, info?.unidade_id]);
  const [unidadeId, setUnidadeId] = useState<string>('');
  useEffect(() => { if (!unidadeId && info?.unidade_id) setUnidadeId(info.unidade_id); }, [info?.unidade_id, unidadeId]);
  const unidade = opcoes.find((u) => u.id === unidadeId);

  const servidores = useConsulta(async () => supabase.from('servidores').select('id,nome_completo,matricula,cargo_id,unidade_id,situacao')
    .eq('unidade_id', unidadeId || '00000000-0000-0000-0000-000000000000').eq('situacao', 'ativo').order('nome_completo'), [unidadeId, versao]);
  const S = (servidores.dados as Servidor[] | null) ?? [];
  const ids = S.map((s) => s.id);
  const cargos = useConsulta(async () => supabase.from('cargos').select('id,nome'), []);
  const nomeCargo = (id: string) => ((cargos.dados as { id: string; nome: string }[] | null) ?? []).find((c) => c.id === id)?.nome ?? '—';
  const afast = useConsulta(async () => supabase.from('afastamentos').select('id,servidor_id,tipo,inicio,fim,status,conflito_mesmo_cargo,substituto_id,observacao,solicitado_por')
    .in('servidor_id', ids.length ? ids : ['00000000-0000-0000-0000-000000000000']).in('status', ['solicitado', 'aprovado'])
    .lte('inicio', `${ano}-12-31`).gte('fim', `${ano}-01-01`).order('inicio'), [ids.join(','), ano, versao]);
  const A = (afast.dados as Afastamento[] | null) ?? [];
  const saldos = useConsulta(async () => supabase.from('saldos_servidor').select('servidor_id,ferias_dias,licenca_premio_dias,folgas,fonte,atualizado_em')
    .in('servidor_id', ids.length ? ids : ['00000000-0000-0000-0000-000000000000']), [ids.join(','), versao]);
  const SAL = (saldos.dados as Saldo[] | null) ?? [];
  const ultimaImportacao = SAL.reduce<string | null>((m, s) => (!m || s.atualizado_em > m ? s.atualizado_em : m), null);

  const nome = (id: string | null) => S.find((s) => s.id === id)?.nome_completo ?? '—';
  const pendentes = A.filter((a) => a.status === 'solicitado');
  const [solicitar, setSolicitar] = useState(false);
  const [importar, setImportar] = useState(false);
  const [decidir, setDecidir] = useState<{ a: Afastamento; aprovar: boolean } | null>(null);
  const [detalhe, setDetalhe] = useState<Afastamento | null>(null);

  const visao = info?.perfil === 'funcionario' ? 'Minhas férias e folgas' : `Escala de férias ${ano} · ${unidade?.sigla ?? ''}`;

  return (
    <>
      <Cabecalho
        trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Férias e folgas' }]}
        titulo={visao}
        acoes={<>
          {chefia && opcoes.length > 1 && (
            <label className="campo campo-leve">Unidade
              <select value={unidadeId} onChange={(e) => setUnidadeId(e.target.value)} style={{ fontSize: 14, padding: '9px 10px', border: '1px solid var(--cor-borda-campo)', borderRadius: 8, background: '#fff', minHeight: 42 }}>
                {opcoes.map((u) => <option key={u.id} value={u.id}>{u.tipo === 'gabinete' ? 'Gabinete' : u.sigla}</option>)}
              </select>
            </label>
          )}
          <label className="campo campo-leve">Ano
            <select value={ano} onChange={(e) => setAno(Number(e.target.value))} style={{ fontSize: 14, padding: '9px 10px', border: '1px solid var(--cor-borda-campo)', borderRadius: 8, background: '#fff', minHeight: 42 }}>
              {[anoAtual - 1, anoAtual, anoAtual + 1].map((a) => <option key={a} value={a}>{a}</option>)}
            </select>
          </label>
          {geral && <button type="button" className="botao" onClick={() => setImportar(true)}>Importar saldos do RH</button>}
          <button type="button" className="botao botao-primario" onClick={() => setSolicitar(true)}>+ Solicitar férias</button>
        </>}
      />

      {chefia && pendentes.filter((p) => p.servidor_id !== info?.servidor_id).map((p) => (
        <PedidoPendente key={p.id} a={p} nome={nome(p.servidor_id)} cargo={nomeCargo(S.find((s) => s.id === p.servidor_id)?.cargo_id ?? '')}
          aoDecidir={(aprovar) => setDecidir({ a: p, aprovar })} />
      ))}

      <section className="cartao">
        <h2 style={{ marginBottom: 12 }}>Quem está fora em cada mês</h2>
        {afast.erro && <Aviso tom="critico">{afast.erro}</Aviso>}
        <div style={{ overflowX: 'auto' }}>
          <div style={{ minWidth: 900 }}>
            <div className="grade-escala cabeca"><div>Servidor · cargo</div>{MESES.map((m) => <div key={m} style={{ textAlign: 'center' }}>{m}</div>)}</div>
            {S.map((s) => (
              <div key={s.id} className="grade-escala">
                <div style={{ padding: '8px 4px', fontSize: 13 }}><strong>{s.nome_completo}</strong><br /><span className="texto-suave">{nomeCargo(s.cargo_id)}</span></div>
                {MESES.map((_, m) => {
                  const ini = `${ano}-${String(m + 1).padStart(2, '0')}-01`;
                  const fimMes = new Date(Date.UTC(ano, m + 1, 0)).toISOString().slice(0, 10);
                  const doMes = A.filter((a) => a.servidor_id === s.id && a.inicio <= fimMes && a.fim >= ini);
                  return (
                    <div key={m} className="celula-escala">
                      {doMes.map((a) => {
                        const de = a.inicio < ini ? '01' : dd(a.inicio);
                        const ate = a.fim > fimMes ? dd(fimMes) : dd(a.fim);
                        const classe = a.conflito_mesmo_cargo ? 'conflito' : a.status === 'solicitado' ? 'pendente' : a.tipo === 'licenca_premio' ? 'licenca' : 'aprovado';
                        const rotulo = a.tipo === 'licenca_premio' && de === '01' && ate === dd(fimMes) ? 'LP' : `${a.tipo === 'folga' ? 'F ' : ''}${de}–${ate}`;
                        return (
                          <button key={a.id} type="button" className={`marca-escala ${classe}`} onClick={() => setDetalhe(a)}
                            aria-label={`${TIPO[a.tipo]} de ${s.nome_completo}, ${dataCurta(a.inicio)} a ${dataCurta(a.fim)}, ${a.status}`}>{rotulo}</button>
                        );
                      })}
                    </div>
                  );
                })}
              </div>
            ))}
            {!servidores.carregando && S.length === 0 && <EstadoVazio>Nenhum servidor visível nesta unidade.</EstadoVazio>}
          </div>
        </div>
        <div className="legenda" style={{ marginTop: 12 }}>
          <span><span aria-hidden="true" className="amostra aprovado" /> Férias aprovadas</span>
          <span><span aria-hidden="true" className="amostra pendente" /> Pedido pendente</span>
          <span><span aria-hidden="true" className="amostra licenca" /> Licença-prêmio</span>
          <span><span aria-hidden="true" className="amostra conflito" /> Mesmo cargo no mesmo período</span>
        </div>
      </section>

      <section className="cartao">
        <div className="cartao-topo"><h2>Saldos por servidor</h2><span className="texto-suave">{ultimaImportacao ? `Fonte: levantamento do RH, importado em ${dataCurta(ultimaImportacao)}` : 'Saldos ainda não importados'}</span></div>
        <div className="tabela-rolagem">
          <table className="tabela tabela-cartoes">
            <thead><tr><th>Servidor</th><th>Matrícula</th><th>Cargo</th><th>Férias (dias)</th><th>Licença-prêmio (dias)</th><th>Folgas</th></tr></thead>
            <tbody>
              {S.map((s) => {
                const sal = SAL.find((x) => x.servidor_id === s.id);
                const fmt = (v?: number) => (v === undefined ? '—' : String(Number(v)).replace('.', ','));
                return (
                  <tr key={s.id}>
                    <td data-rotulo="Servidor"><strong>{s.nome_completo}</strong></td><td data-rotulo="Matrícula">{s.matricula}</td><td data-rotulo="Cargo">{nomeCargo(s.cargo_id)}</td>
                    <td data-rotulo="Férias">{fmt(sal?.ferias_dias)}</td><td data-rotulo="Licença-prêmio">{fmt(sal?.licenca_premio_dias)}</td><td data-rotulo="Folgas">{fmt(sal?.folgas)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>
      <p className="nota">Ao aprovar, a chefia indica obrigatoriamente um substituto da mesma unidade. Os saldos são os informados pelo RH; o sistema não desconta automaticamente (regra pendente).</p>

      {solicitar && <Solicitar fechar={() => setSolicitar(false)} servidores={chefia ? S : S.filter((s) => s.id === info?.servidor_id)} saldos={SAL} aoSalvar={recarregar} />}
      {decidir && <Decidir alvo={decidir.a} aprovar={decidir.aprovar} nome={nome(decidir.a.servidor_id)} servidores={S} fechar={() => setDecidir(null)} aoSalvar={recarregar} />}
      {detalhe && <Detalhe a={detalhe} nome={nome(detalhe.servidor_id)} substituto={nome(detalhe.substituto_id)} chefia={chefia} meuPedido={detalhe.solicitado_por === info?.usuario_id} servidores={S} fechar={() => setDetalhe(null)} aoSalvar={recarregar} />}
      {geral && (
        <ImportarPlanilha aberto={importar} fechar={() => setImportar(false)} titulo="Importar saldos do RH" colunas={COLUNAS_SALDOS}
          rpcPrevia="importar_saldos_previa" rpcImportar="importar_saldos" nomeModelo="modelo-saldos-rh.csv" exemplo={['000101', '30', '0', '2']}
          explicacao="Atualiza os saldos de férias, licença-prêmio e folgas pela matrícula. Antes de gravar, o sistema mostra os erros (matrícula vazia, não encontrada ou duplicada). Modelo provisório: será ajustado às colunas da planilha oficial do RH."
          aoImportar={recarregar} />
      )}
    </>
  );
}

function PedidoPendente({ a, nome, cargo, aoDecidir }: { a: Afastamento; nome: string; cargo: string; aoDecidir: (aprovar: boolean) => void }) {
  const [conflitos, setConflitos] = useState<Conflito[]>([]);
  useEffect(() => {
    if (!a.conflito_mesmo_cargo) return;
    void supabase.rpc('conflitos_mesmo_cargo', { p_servidor: a.servidor_id, p_inicio: a.inicio, p_fim: a.fim, p_ignorar: a.id })
      .then(({ data }) => setConflitos((data as Conflito[]) ?? []));
  }, [a]);
  const periodo = `${ddmm(a.inicio)}–${ddmm(a.fim)}`;
  return a.conflito_mesmo_cargo ? (
    <section role="alert" className="aviso aviso-alerta">
      <Icone nome="alerta" tamanho={22} cor="var(--aviso-alerta-icone)" traco={2} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <strong>Atenção para a chefia:</strong> o pedido de {nome} ({cargo}, {periodo}) coincide com {conflitos.length ? conflitos.map((c) => `${c.status === 'aprovado' ? 'as férias já aprovadas' : 'o pedido'} de ${c.nome}`).join(' e ') : 'férias de outro servidor'}, que tem o mesmo cargo. O pedido segue para a sua decisão.
      </div>
      <div className="acoes" style={{ gap: 8 }}>
        <button type="button" className="botao" style={{ minHeight: 40 }} onClick={() => aoDecidir(false)}>Recusar</button>
        <button type="button" className="botao botao-escuro" style={{ minHeight: 40 }} onClick={() => aoDecidir(true)}>Aprovar mesmo assim</button>
      </div>
    </section>
  ) : (
    <section className="aviso aviso-info" style={{ alignItems: 'center' }}>
      <div style={{ flex: 1, minWidth: 0, fontSize: 14 }}><strong>Pedido de {TIPO[a.tipo].toLowerCase()}:</strong> {nome} ({cargo}), {periodo}{a.observacao ? ` · ${a.observacao}` : ''}</div>
      <div className="acoes" style={{ gap: 8 }}>
        <button type="button" className="botao" style={{ minHeight: 40 }} onClick={() => aoDecidir(false)}>Recusar</button>
        <button type="button" className="botao botao-escuro" style={{ minHeight: 40 }} onClick={() => aoDecidir(true)}>Aprovar</button>
      </div>
    </section>
  );
}

function Solicitar({ fechar, servidores, saldos, aoSalvar }: { fechar: () => void; servidores: Servidor[]; saldos: Saldo[]; aoSalvar: () => void }) {
  const [f, setF] = useState({ servidor: servidores[0]?.id ?? '', tipo: 'ferias' as Tipo, inicio: '', fim: '', obs: '' });
  const [uteis, setUteis] = useState<number | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ok, setOk] = useState(false);
  useEffect(() => { if (!f.servidor && servidores[0]) setF((x) => ({ ...x, servidor: servidores[0].id })); }, [servidores, f.servidor]);
  useEffect(() => {
    setUteis(null);
    if (!f.inicio || !f.fim || f.fim < f.inicio) return;
    const antes = new Date(Date.parse(f.inicio) - 86400000).toISOString().slice(0, 10);
    void supabase.rpc('dias_uteis_entre', { inicio: antes, fim: f.fim }).then(({ data }) => setUteis(data as number));
  }, [f.inicio, f.fim]);
  const sal = saldos.find((s) => s.servidor_id === f.servidor);
  const corridos = f.inicio && f.fim && f.fim >= f.inicio ? diasCorridos(f.inicio, f.fim) : null;
  const disponivel = sal ? Number(f.tipo === 'ferias' ? sal.ferias_dias : f.tipo === 'licenca_premio' ? sal.licenca_premio_dias : sal.folgas) : null;
  const salvar = async () => {
    setErro(null);
    if (!f.servidor || !f.inicio || !f.fim) { setErro('Preencha servidor e período.'); return; }
    if (f.fim < f.inicio) { setErro('O fim deve ser depois do início.'); return; }
    const { error } = await supabase.rpc('solicitar_afastamento', { p_servidor: f.servidor, p_tipo: f.tipo, p_inicio: f.inicio, p_fim: f.fim, p_observacao: f.obs || null });
    if (error) { setErro(mensagemErro(error)); return; }
    setOk(true); aoSalvar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo="Solicitar férias, licença ou folga" acoes={ok ? <button type="button" className="botao" onClick={fechar}>Fechar</button>
      : <><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={salvar}>Enviar pedido</button></>}>
      {ok ? <Aviso tom="sucesso">Pedido enviado. A chefia da unidade foi avisada.</Aviso> : (
        <div className="form">
          {erro && <Aviso tom="critico">{erro}</Aviso>}
          {servidores.length > 1 && (
            <Campo rotulo="Servidor"><select value={f.servidor} onChange={(e) => setF({ ...f, servidor: e.target.value })}>{servidores.map((s) => <option key={s.id} value={s.id}>{s.nome_completo}</option>)}</select></Campo>
          )}
          <Campo rotulo="Tipo"><select value={f.tipo} onChange={(e) => setF({ ...f, tipo: e.target.value as Tipo })}>{(Object.keys(TIPO) as Tipo[]).map((t) => <option key={t} value={t}>{TIPO[t]}</option>)}</select></Campo>
          <div className="form-linha">
            <Campo rotulo="Início"><input type="date" value={f.inicio} onChange={(e) => setF({ ...f, inicio: e.target.value })} /></Campo>
            <Campo rotulo="Fim"><input type="date" value={f.fim} min={f.inicio} onChange={(e) => setF({ ...f, fim: e.target.value })} /></Campo>
          </div>
          {corridos !== null && (
            <p className="nota" style={{ fontSize: 13 }}>{corridos} dia(s) corrido(s){uteis !== null ? ` · ${uteis} dia(s) útil(eis)` : ''}{disponivel !== null ? ` · saldo informado pelo RH: ${String(disponivel).replace('.', ',')}` : ''}</p>
          )}
          {disponivel !== null && corridos !== null && f.tipo !== 'folga' && corridos > disponivel && <Aviso tom="alerta">O período passa do saldo informado pelo RH. A chefia decide.</Aviso>}
          <Campo rotulo="Observação (opcional)"><textarea rows={2} maxLength={1000} value={f.obs} onChange={(e) => setF({ ...f, obs: e.target.value })} /></Campo>
        </div>
      )}
    </Dialogo>
  );
}

function Decidir({ alvo, aprovar, nome, servidores, fechar, aoSalvar }: { alvo: Afastamento; aprovar: boolean; nome: string; servidores: Servidor[]; fechar: () => void; aoSalvar: () => void }) {
  const [sub, setSub] = useState('');
  const [coment, setComent] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const salvar = async () => {
    setErro(null);
    if (aprovar && !sub) { setErro('Indique o substituto (obrigatório).'); return; }
    if (!aprovar && !coment.trim()) { setErro('Informe o comentário para recusar.'); return; }
    const { error } = await supabase.rpc('decidir_afastamento', { p_id: alvo.id, p_aprovar: aprovar, p_substituto: aprovar ? sub : null, p_comentario: coment.trim() || null });
    if (error) { setErro(mensagemErro(error)); return; }
    aoSalvar(); fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo={`${aprovar ? 'Aprovar' : 'Recusar'}: ${TIPO[alvo.tipo].toLowerCase()} de ${nome}`}
      acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className={`botao ${aprovar ? 'botao-positivo' : 'botao-critico'}`} onClick={salvar}>{aprovar ? 'Aprovar' : 'Recusar'}</button></>}>
      <div className="form">
        <p style={{ margin: 0, fontSize: 14 }}>{dataCurta(alvo.inicio)} a {dataCurta(alvo.fim)} · {diasCorridos(alvo.inicio, alvo.fim)} dia(s)</p>
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        {aprovar && (
          <Campo rotulo="Substituto (mesma unidade, obrigatório)" ajuda="O substituto e a chefia são avisados. A partir da Fase 3, ele passa a responder pelas demandas abertas no período.">
            <select value={sub} onChange={(e) => setSub(e.target.value)}><option value="">Selecione…</option>{servidores.filter((s) => s.id !== alvo.servidor_id).map((s) => <option key={s.id} value={s.id}>{s.nome_completo}</option>)}</select>
          </Campo>
        )}
        <Campo rotulo={aprovar ? 'Comentário (opcional)' : 'Comentário (obrigatório)'}><textarea rows={2} maxLength={1000} value={coment} onChange={(e) => setComent(e.target.value)} /></Campo>
      </div>
    </Dialogo>
  );
}

function Detalhe({ a, nome, substituto, chefia, meuPedido, servidores, fechar, aoSalvar }: {
  a: Afastamento; nome: string; substituto: string; chefia: boolean; meuPedido: boolean; servidores: Servidor[]; fechar: () => void; aoSalvar: () => void;
}) {
  const [modo, setModo] = useState<'ver' | 'remarcar'>('ver');
  const [f, setF] = useState({ inicio: a.inicio, fim: a.fim, sub: a.substituto_id ?? '' });
  const [erro, setErro] = useState<string | null>(null);
  const exec = async (fn: string, args: Record<string, unknown>) => {
    setErro(null);
    const { error } = await supabase.rpc(fn, args);
    if (error) { setErro(mensagemErro(error)); return; }
    aoSalvar(); fechar();
  };
  const podeChefia = chefia && !meuPedido;
  return (
    <Dialogo aberto fechar={fechar} titulo={`${TIPO[a.tipo]} · ${nome}`} acoes={<>
      <button type="button" className="botao" onClick={fechar}>Fechar</button>
      {modo === 'ver' && (podeChefia || (meuPedido && a.status === 'solicitado')) && (
        <button type="button" className="botao botao-critico" onClick={() => window.confirm('Cancelar este registro?') && exec('cancelar_afastamento', { p_id: a.id, p_motivo: null })}>Cancelar</button>
      )}
      {modo === 'ver' && podeChefia && <button type="button" className="botao" onClick={() => setModo('remarcar')}>Remarcar</button>}
      {modo === 'remarcar' && <button type="button" className="botao botao-primario" onClick={() => exec('remarcar_afastamento', { p_id: a.id, p_inicio: f.inicio, p_fim: f.fim, p_substituto: f.sub || null })}>Salvar</button>}
    </>}>
      {erro && <Aviso tom="critico">{erro}</Aviso>}
      {modo === 'ver' ? (
        <div className="caixa-cinza">
          {dataCurta(a.inicio)} a {dataCurta(a.fim)} · {diasCorridos(a.inicio, a.fim)} dia(s)<br />
          Situação: <strong>{a.status === 'aprovado' ? 'Aprovado' : 'Pedido pendente'}</strong>{a.status === 'aprovado' ? ` · substituto: ${substituto}` : ''}
          {a.conflito_mesmo_cargo && <><br />Mesmo cargo no mesmo período</>}
          {a.observacao && <><br />{a.observacao}</>}
        </div>
      ) : (
        <div className="form">
          <div className="form-linha">
            <Campo rotulo="Início"><input type="date" value={f.inicio} onChange={(e) => setF({ ...f, inicio: e.target.value })} /></Campo>
            <Campo rotulo="Fim"><input type="date" value={f.fim} min={f.inicio} onChange={(e) => setF({ ...f, fim: e.target.value })} /></Campo>
          </div>
          {a.status === 'aprovado' && (
            <Campo rotulo="Substituto"><select value={f.sub} onChange={(e) => setF({ ...f, sub: e.target.value })}>{servidores.filter((s) => s.id !== a.servidor_id).map((s) => <option key={s.id} value={s.id}>{s.nome_completo}</option>)}</select></Campo>
          )}
          <p className="nota">A remarcação fica registrada na auditoria.</p>
        </div>
      )}
    </Dialogo>
  );
}
