'use client';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { Suspense, useEffect, useState } from 'react';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { Aviso, Campo, Dialogo, Selo } from '@/components/ui';
import { MIME_DEMANDA, validarAnexoDemanda } from '@/lib/arquivos';
import { mensagemErro } from '@/lib/erros';
import { baixar } from '@/lib/exportar';
import { dataCurta, dataHora } from '@/lib/formato';
import {
  HISTORICO_AV, nomeCompetencia, num, pct, pdfAnexoI, pdfAnexoII, ROTULO_STATUS_AV, TIPO_PROVA, TOM_STATUS_AV, type Demonstrativo, type Detalhe, type Nota,
} from '@/lib/produtividade';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';

interface Subsidios {
  recebidas: { id: string; numero: number; titulo: string }[];
  concluidas: { id: string; numero: number; titulo: string; no_prazo: boolean; dias_uteis: number }[];
  atrasadas: { id: string; numero: number; titulo: string; prazo: string }[];
  checklist: { id: string; demanda_id: string; texto: string }[];
  feedbacks: { id: string; demanda_id: string; feedback: string; comentario: string | null }[];
  afastamentos: { tipo: string; inicio: string; fim: string; dias: number }[];
}

export default function AvaliacaoPage() {
  return <AppShell modulo="produtividade"><Suspense><Avaliacao /></Suspense></AppShell>;
}

async function enviarArquivo(avId: string, arq: File): Promise<string> {
  const v = await validarAnexoDemanda(arq);
  if (!v.ok) throw new Error(v.erro);
  const path = `avaliacoes/${avId}/${crypto.randomUUID()}.${v.tipo}`;
  const up = await supabase.storage.from('produtividade').upload(path, arq, { contentType: MIME_DEMANDA[v.tipo], upsert: false });
  if (up.error) throw new Error('Não foi possível enviar o arquivo.');
  return path;
}

function Avaliacao() {
  const id = useSearchParams().get('id') ?? '';
  const [versao, setVersao] = useState(0);
  const recarregar = () => setVersao((v) => v + 1);
  const det = useConsulta(async () => supabase.rpc('prod_avaliacao_detalhe', { p_id: id }), [id, versao]);
  const D = det.dados as Detalhe | null;
  const sub = useConsulta(async () => (D?.permissoes.editar || D?.permissoes.gerir || D?.permissoes.homologar || D?.permissoes.decidir_recurso
    ? supabase.rpc('prod_subsidios', { p_id: id }) : Promise.resolve({ data: null, error: null })), [id, D?.permissoes.editar, D?.permissoes.homologar]);
  const dem = useConsulta(async () => (D ? supabase.rpc('prod_demonstrativo', { p_comp: D.avaliacao.competencia, p_servidor: D.avaliacao.servidor_id }) : Promise.resolve({ data: null, error: null })), [D?.avaliacao.id, versao]);
  const [notas, setNotas] = useState<Record<string, Nota>>({});
  const [limitacoes, setLimitacoes] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [dialogo, setDialogo] = useState<null | 'recurso' | 'decidir' | 'devolver' | 'retificar' | 'outro_meio' | 'prova'>(null);
  const [provaInicial, setProvaInicial] = useState<{ tipo: string; ref?: string; titulo?: string } | null>(null);
  const [sujo, setSujo] = useState(false);

  useEffect(() => {
    if (!D) return;
    setNotas(Object.fromEntries(D.regra.indicadores.map((i) => [i.codigo, D.notas.find((n) => n.indicador === i.codigo)
      ?? { indicador: i.codigo, nota: null, justificativa: '', equivalente: false, justificativa_equivalente: '' }])));
    setLimitacoes(D.avaliacao.limitacoes ?? '');
    setSujo(false);
  }, [D]);

  if (det.carregando && !D) return <div className="carregando">Carregando…</div>;
  if (!D) return <><Cabecalho trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Produtividade', href: '/produtividade' }]} titulo="Avaliação não encontrada" /><p className="nota">{det.erro ?? 'Ela não existe ou você não tem acesso.'}</p></>;

  const a = D.avaliacao; const P = D.permissoes; const S = sub.dados as Subsidios | null; const DM = dem.dados as Demonstrativo | null;
  const total = Object.values(notas).reduce((s, n) => s + Number(n.nota ?? 0), 0);
  const rpc = async (fn: string, args: Record<string, unknown>, msg?: string) => {
    setErro(null); setOk(null);
    const { error } = await supabase.rpc(fn, args);
    if (error) { setErro(mensagemErro(error)); return false; }
    if (msg) setOk(msg);
    recarregar();
    return true;
  };
  const salvar = () => rpc('prod_salvar_avaliacao', { p_id: id, p_notas: Object.values(notas), p_limitacoes: limitacoes }, 'Rascunho salvo.');
  const enviar = async () => { if (await salvar()) await rpc('prod_enviar', { p_id: id }, 'Avaliação enviada ao servidor para ciência.'); };
  const setNota = (c: string, p: Partial<Nota>) => { setNotas({ ...notas, [c]: { ...notas[c], ...p } }); setSujo(true); };
  const usarComoProva = (tipo: string, ref: string, titulo: string) => { setProvaInicial({ tipo, ref, titulo }); setDialogo('prova'); };
  const baixarAnexo = async (path: string) => {
    const { data } = await supabase.storage.from('produtividade').download(path);
    if (data) baixar(data, path.split('/').pop() ?? 'anexo');
  };

  return (
    <>
      <Cabecalho trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Produtividade', href: `/produtividade?comp=${a.competencia}` }, { rotulo: a.servidor }]}
        titulo={`Avaliação de ${a.servidor} · ${nomeCompetencia(a.competencia)}`}
        subtitulo={<span className="acoes" style={{ gap: 8, marginTop: 6 }}>
          <Selo tom={TOM_STATUS_AV[a.status]}>{ROTULO_STATUS_AV[a.status]}</Selo>
          <Selo tom="neutro">{dataCurta(a.periodo_inicio)} a {dataCurta(a.periodo_fim)}</Selo>
          <Selo tom="neutro">Chefia: {a.avaliador ?? 'não definida'}</Selo>
          {a.retifica_id && <Selo tom="alerta">Retificação</Selo>}
        </span>}
        acoes={<>
          <button type="button" className="botao" onClick={async () => baixar(await pdfAnexoI(D), `anexo-i-${a.matricula}-${a.competencia.slice(0, 7)}.pdf`)}>Anexo I (PDF)</button>
          {DM && <button type="button" className="botao" onClick={async () => baixar(await pdfAnexoII(DM, { recursos: D.recursos, homologacao: a.homologada_em ? `${dataHora(a.homologada_em)} por ${a.homologada_por_nome ?? ''}` : undefined }), `anexo-ii-${a.matricula}-${a.competencia.slice(0, 7)}.pdf`)}>Anexo II (PDF)</button>}
          {P.ciencia && <button type="button" className="botao botao-primario" onClick={() => void rpc('prod_dar_ciencia', { p_id: id }, 'Ciência registrada. O prazo de recurso começou.')}>Dar ciência</button>}
          {P.recorrer && <button type="button" className="botao" onClick={() => setDialogo('recurso')}>Recorrer</button>}
          {P.ciencia_outro_meio && <button type="button" className="botao" onClick={() => setDialogo('outro_meio')}>Registrar ciência por outro meio</button>}
          {P.decidir_recurso && <button type="button" className="botao botao-primario" onClick={() => setDialogo('decidir')}>Decidir recurso</button>}
          {P.homologar && <><button type="button" className="botao" onClick={() => setDialogo('devolver')}>Devolver à chefia</button>
            <button type="button" className="botao botao-positivo" onClick={() => void rpc('prod_homologar', { p_ids: [id] }, 'Avaliação homologada.')}>Homologar</button></>}
          {P.retificar && <button type="button" className="botao" onClick={() => setDialogo('retificar')}>Retificar</button>}
        </>} />
      {erro && <Aviso tom="critico">{erro}</Aviso>}
      {ok && <Aviso tom="sucesso">{ok}</Aviso>}
      {a.devolucao_motivo && a.status === 'rascunho' && <Aviso tom="alerta" titulo="Devolvida pela homologação">{a.devolucao_motivo}</Aviso>}
      {a.retificacao_justificativa && <Aviso tom="info" titulo="Retificação">{a.retificacao_justificativa} · <Link href={`/produtividade/avaliacao?id=${a.retifica_id}`}>ver original</Link></Aviso>}
      {a.status === 'enviada' && P.ciencia && <Aviso tom="info">Leia a avaliação completa (notas, justificativas e provas) e clique em "Dar ciência". Depois da ciência você tem {D.regra.prazos.recurso} dias úteis para recorrer.</Aviso>}
      {a.status === 'ciente' && a.prazo_recurso && <Aviso tom="info">Ciência em {dataHora(a.ciente_em)}{a.ciencia_meio === 'outro_meio' ? ' (registrada por outro meio)' : ''}. Prazo de recurso até {dataCurta(a.prazo_recurso)}.</Aviso>}

      <div className="linha">
        <section className="cartao col-principal" aria-label="Indicadores">
          <div className="cartao-topo"><h2>Desempenho funcional</h2><span className="texto-suave">regra versão {D.regra.versao}</span></div>
          {D.regra.indicadores.map((i) => {
            const n = notas[i.codigo]; if (!n) return null;
            const provas = D.provas.filter((p) => p.indicador === i.codigo);
            return (
              <fieldset key={i.codigo} style={{ border: 0, borderTop: '1px solid var(--cor-divisor)', margin: 0, padding: '12px 0' }}>
                <legend style={{ fontWeight: 600, fontSize: 14 }}>{i.codigo} · {i.nome} <span className="texto-suave">(até {i.maximo})</span></legend>
                {P.editar ? (
                  <div className="form" style={{ gap: 8 }}>
                    <div className="form-linha">
                      <Campo rotulo={`Nota (0 a ${i.maximo})`}><input inputMode="decimal" value={n.nota ?? ''} onChange={(e) => setNota(i.codigo, { nota: e.target.value === '' ? null : Number(e.target.value.replace(',', '.')) })} /></Campo>
                      <label className="acoes" style={{ gap: 6, alignSelf: 'end', minHeight: 44 }}><input type="checkbox" checked={n.equivalente} onChange={(e) => setNota(i.codigo, { equivalente: e.target.checked })} />Critério equivalente (indicador não compatível com as atribuições)</label>
                    </div>
                    <Campo rotulo="Justificativa"><textarea rows={2} maxLength={4000} value={n.justificativa ?? ''} onChange={(e) => setNota(i.codigo, { justificativa: e.target.value })} /></Campo>
                    {n.equivalente && <Campo rotulo="Justificativa do critério equivalente"><textarea rows={2} maxLength={2000} value={n.justificativa_equivalente ?? ''} onChange={(e) => setNota(i.codigo, { justificativa_equivalente: e.target.value })} /></Campo>}
                  </div>
                ) : (
                  <div style={{ fontSize: 14 }}><strong>{num(n.nota)}</strong> / {i.maximo}<br /><span style={{ whiteSpace: 'pre-wrap' }}>{n.justificativa ?? '—'}</span>
                    {n.equivalente && <><br /><span className="texto-suave">Critério equivalente: {n.justificativa_equivalente}</span></>}</div>
                )}
                <div style={{ marginTop: 6, fontSize: 13 }}>
                  <span className="texto-suave">Provas: </span>{!provas.length && <Selo tom={P.editar ? 'critico' : 'neutro'}>nenhuma</Selo>}
                  {provas.map((p) => <span key={p.id} className="selo selo-neutro" style={{ marginRight: 6, display: 'inline-flex', gap: 6 }}>
                    {TIPO_PROVA[p.tipo]}: {p.demanda_id ? <Link href={`/demandas/ficha?id=${p.demanda_id}`}>{p.titulo}</Link> : p.path ? <button type="button" className="botao-link" onClick={() => void baixarAnexo(p.path!)}>{p.titulo}</button> : p.titulo}
                    {P.editar && <button type="button" aria-label="Remover prova" className="botao-link" onClick={() => void rpc('prod_remover_prova', { p_prova: p.id })}>×</button>}</span>)}
                  {P.editar && <button type="button" className="botao-link" onClick={() => { setProvaInicial({ tipo: 'externa' }); setDialogo('prova'); }}>+ prova</button>}
                </div>
              </fieldset>
            );
          })}
          {P.editar ? <Campo rotulo="Limitações estruturais ou operacionais (opcional)"><textarea rows={2} maxLength={3000} value={limitacoes} onChange={(e) => { setLimitacoes(e.target.value); setSujo(true); }} /></Campo>
            : a.limitacoes && <p style={{ fontSize: 13 }}><strong>Limitações estruturais ou operacionais:</strong> {a.limitacoes}</p>}
          <div className="cartao-topo" style={{ borderTop: '1px solid var(--cor-borda)', paddingTop: 12, marginTop: 8, flexWrap: 'wrap', gap: 10 }}>
            <strong style={{ fontSize: 18 }}>Total: {num(P.editar ? total : a.total_funcional)} / {D.regra.max_funcional}</strong>
            {P.editar && <span className="acoes"><button type="button" className="botao" onClick={() => void salvar()}>Salvar rascunho</button>
              <button type="button" className="botao botao-primario" onClick={() => void enviar()}>Enviar ao servidor</button></span>}
          </div>
          {P.editar && D.pendencias_envio.length > 0 && !sujo && <p className="nota">Falta para enviar: {D.pendencias_envio.join('; ')}.</p>}
        </section>

        <aside className="col-lateral" style={{ gap: 20 }}>
          {S && (
            <section className="cartao" aria-label="Subsídios do mês">
              <h2 style={{ marginBottom: 4 }}>Subsídios do período</h2>
              <p className="texto-suave" style={{ margin: '0 0 8px' }}>Só fatos registrados no sistema; o sistema não sugere nota.{P.editar ? ' Clique em "usar" para anexar como prova.' : ''}</p>
              <Bloco titulo={`Demandas recebidas (${S.recebidas.length})`} itens={S.recebidas.map((d) => ({ id: d.id, t: `#${d.numero} ${d.titulo}`, link: `/demandas/ficha?id=${d.id}`, tipo: 'demanda' }))} usar={P.editar ? usarComoProva : undefined} />
              <Bloco titulo={`Concluídas (${S.concluidas.length}; no prazo ${S.concluidas.filter((d) => d.no_prazo).length}; tempo médio ${S.concluidas.length ? num(Math.round((S.concluidas.reduce((s, d) => s + d.dias_uteis, 0) / S.concluidas.length) * 10) / 10) : '—'} dias úteis)`}
                itens={S.concluidas.map((d) => ({ id: d.id, t: `#${d.numero} ${d.titulo}${d.no_prazo ? '' : ' (fora do prazo)'}`, link: `/demandas/ficha?id=${d.id}`, tipo: 'demanda' }))} usar={P.editar ? usarComoProva : undefined} />
              <Bloco titulo={`Atrasadas (${S.atrasadas.length})`} itens={S.atrasadas.map((d) => ({ id: d.id, t: `#${d.numero} ${d.titulo} · prazo ${dataCurta(d.prazo)}`, link: `/demandas/ficha?id=${d.id}`, tipo: 'demanda' }))} usar={P.editar ? usarComoProva : undefined} />
              <Bloco titulo={`Etapas de checklist concluídas (${S.checklist.length})`} itens={S.checklist.map((c) => ({ id: c.id, t: c.texto, link: `/demandas/ficha?id=${c.demanda_id}`, tipo: 'checklist' }))} usar={P.editar ? usarComoProva : undefined} />
              <Bloco titulo={`Feedbacks da chefia (${S.feedbacks.length})`} itens={S.feedbacks.map((m) => ({ id: m.id, t: `${{ aprovado: 'Aprovado', ajustar: 'Ajustar', refazer: 'Refazer' }[m.feedback] ?? m.feedback}${m.comentario ? `: ${m.comentario}` : ''}`, link: `/demandas/ficha?id=${m.demanda_id}`, tipo: 'mensagem' }))} usar={P.editar ? usarComoProva : undefined} />
              <div style={{ fontSize: 13, marginTop: 8 }}><strong>Afastamentos no período:</strong> {S.afastamentos.length ? S.afastamentos.map((x) => `${x.tipo} ${dataCurta(x.inicio)}–${dataCurta(x.fim)} (${x.dias} d)`).join('; ') : 'nenhum'}</div>
            </section>
          )}
          {DM && (
            <section className="cartao" aria-label="Demonstrativo">
              <h2 style={{ marginBottom: 6 }}>Demonstrativo {DM.provisorio ? '(provisório)' : ''}</h2>
              <div style={{ fontSize: 13, lineHeight: 1.8 }}>
                Funcional: <strong>{num(DM.pontos_funcionais)}</strong>{DM.periodos.length > 1 ? ' (média ponderada dos períodos)' : ''}<br />
                Institucional: <strong>{DM.transicao ? 'regra de transição – § 12 do art. 15-B' : `${num(DM.pontos_institucionais)} (${DM.institucional?.quadrimestre}º/${DM.institucional?.ano})`}</strong><br />
                Nota total: <strong>{num(DM.nota_total)}</strong> → enquadramento <strong>{DM.nota_enquadramento}</strong><br />
                Mínimos: funcional {DM.minimo_funcional_atingido ? 'Sim' : 'Não'} · nota {DM.minimo_total_atingido ? 'Sim' : 'Não'}<br />
                Percentual: <strong>{pct(DM.percentual)}</strong>{DM.motivo_zero ? ` (${DM.motivo_zero})` : ''}<br />
                Dias elegíveis: {DM.dias_elegiveis}/{DM.dias_mes} · fator {num(DM.fator)} · <strong>efetivo {pct(DM.percentual_efetivo)}</strong>
              </div>
            </section>
          )}
          {D.recursos.length > 0 && (
            <section className="cartao"><h2 style={{ marginBottom: 6 }}>Recurso</h2>
              {D.recursos.map((r) => <div key={r.id} style={{ fontSize: 13 }}><strong>Razões ({dataHora(r.criado_em)}):</strong> {r.razoes}
                {r.anexo_path && <> · <button type="button" className="botao-link" onClick={() => void baixarAnexo(r.anexo_path!)}>anexo</button></>}<br />
                {r.decidido_em ? <><strong>Decisão de {r.revisor} ({dataHora(r.decidido_em)}):</strong> {r.fundamentacao}</> : <span className="texto-suave">Aguardando decisão até {dataCurta(r.prazo_revisao)}{r.revisor ? ` · ${r.revisor}` : ' · revisora não designada'}</span>}</div>)}
            </section>
          )}
          <section className="cartao"><h2 style={{ marginBottom: 6 }}>Histórico</h2>
            <div style={{ fontSize: 13, lineHeight: 1.6, maxHeight: 300, overflowY: 'auto' }}>{D.historico.map((h, i) => <div key={i}><span className="texto-suave">{dataHora(h.em)} · {h.ator ?? 'Sistema'}</span><br />{HISTORICO_AV[h.acao] ?? h.acao}</div>)}</div>
          </section>
        </aside>
      </div>
      <p className="nota">Avaliação de desempenho é dado pessoal: visível ao servidor, à chefia que avalia, à diretoria (leitura), à revisora (se houver recurso), à homologação e à Secretária. Nada é apagado: depois de homologada, correção só por retificação.</p>

      {dialogo === 'prova' && <NovaProva avId={id} indicadores={D.regra.indicadores.map((i) => i.codigo)} inicial={provaInicial} fechar={() => setDialogo(null)} aoSalvar={recarregar} />}
      {dialogo === 'recurso' && <Texto titulo="Recorrer da avaliação" rotulo="Razões do recurso" min={10} anexo avId={id} acao="Enviar recurso" fechar={() => setDialogo(null)}
        enviar={(t, path) => rpc('prod_recorrer', { p_id: id, p_razoes: t, p_anexo: path }, 'Recurso enviado à autoridade revisora.')} />}
      {dialogo === 'devolver' && <Texto titulo="Devolver à chefia" rotulo="Motivo" min={10} acao="Devolver" fechar={() => setDialogo(null)} enviar={(t) => rpc('prod_devolver', { p_id: id, p_motivo: t }, 'Devolvida à chefia.')} />}
      {dialogo === 'retificar' && <Texto titulo="Retificar avaliação homologada" rotulo="Justificativa (o original é preservado)" min={10} acao="Abrir retificação" fechar={() => setDialogo(null)}
        enviar={async (t) => { setErro(null); const { data, error } = await supabase.rpc('prod_retificar', { p_id: id, p_justificativa: t }); if (error) { setErro(mensagemErro(error)); return false; } window.location.href = `${window.location.pathname}?id=${data}`; return true; }} />}
      {dialogo === 'outro_meio' && <OutroMeio avId={id} fechar={() => setDialogo(null)} enviar={(d, p) => rpc('prod_ciencia_outro_meio', { p_id: id, p_data: d, p_anexo: p }, 'Ciência registrada.')} />}
      {dialogo === 'decidir' && <Decidir D={D} fechar={() => setDialogo(null)} enviar={(f, n) => rpc('prod_decidir_recurso', { p_id: id, p_fundamentacao: f, p_notas: n }, 'Recurso decidido.')} />}
    </>
  );
}

function Bloco({ titulo, itens, usar }: { titulo: string; itens: { id: string; t: string; link: string; tipo: string }[]; usar?: (tipo: string, ref: string, t: string) => void }) {
  return (
    <details style={{ fontSize: 13, borderTop: '1px solid var(--cor-divisor)', padding: '6px 0' }}>
      <summary style={{ cursor: 'pointer', minHeight: 32 }}>{titulo}</summary>
      {!itens.length && <span className="texto-suave">nenhum</span>}
      {itens.map((x) => <div key={x.id} className="acoes" style={{ justifyContent: 'space-between', gap: 6, padding: '3px 0' }}>
        <Link href={x.link}>{x.t}</Link>{usar && <button type="button" className="botao-link" onClick={() => usar(x.tipo, x.id, x.t)}>usar</button>}</div>)}
    </details>
  );
}

function NovaProva({ avId, indicadores, inicial, fechar, aoSalvar }: { avId: string; indicadores: string[]; inicial: { tipo: string; ref?: string; titulo?: string } | null; fechar: () => void; aoSalvar: () => void }) {
  const [ind, setInd] = useState(indicadores[0]);
  const [tipo, setTipo] = useState(inicial?.tipo ?? 'externa');
  const [desc, setDesc] = useState('');
  const [arq, setArq] = useState<File | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const salvar = async () => {
    setErro(null);
    try {
      let path: string | null = null;
      if (tipo === 'anexo') { if (!arq) return setErro('Escolha o arquivo.'); path = await enviarArquivo(avId, arq); }
      const { error } = await supabase.rpc('prod_adicionar_prova', { p_id: avId, p_indicador: ind, p_tipo: tipo, p_ref: inicial?.ref ?? null, p_descricao: tipo === 'externa' ? desc : null, p_path: path, p_nome: arq?.name ?? null });
      if (error) return setErro(mensagemErro(error));
      aoSalvar(); fechar();
    } catch (e) { setErro((e as Error).message); }
  };
  return (
    <Dialogo aberto fechar={fechar} titulo="Adicionar prova" acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={salvar}>Adicionar</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        <Campo rotulo="Indicador"><select value={ind} onChange={(e) => setInd(e.target.value)}>{indicadores.map((i) => <option key={i}>{i}</option>)}</select></Campo>
        {inicial?.ref ? <p style={{ margin: 0 }}><strong>{TIPO_PROVA[tipo]}:</strong> {inicial.titulo}</p> : (
          <>
            <Campo rotulo="Tipo"><select value={tipo} onChange={(e) => setTipo(e.target.value)}><option value="externa">Referência externa (processo, protocolo, relatório)</option><option value="anexo">Anexo (PDF, imagem, DOCX, XLSX)</option></select></Campo>
            {tipo === 'externa' ? <Campo rotulo="Referência"><input maxLength={1000} value={desc} onChange={(e) => setDesc(e.target.value)} placeholder="Ex.: Processo nº 123/2026" /></Campo>
              : <Campo rotulo="Arquivo" ajuda="Até 20 MB"><input type="file" accept=".pdf,.png,.jpg,.jpeg,.docx,.xlsx" onChange={(e) => setArq(e.target.files?.[0] ?? null)} /></Campo>}
          </>
        )}
      </div>
    </Dialogo>
  );
}

function Texto({ titulo, rotulo, min, acao, anexo, avId, fechar, enviar }: { titulo: string; rotulo: string; min: number; acao: string; anexo?: boolean; avId?: string; fechar: () => void; enviar: (t: string, path: string | null) => Promise<boolean> }) {
  const [t, setT] = useState('');
  const [arq, setArq] = useState<File | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const ir = async () => {
    try { const path = arq && avId ? await enviarArquivo(avId, arq) : null; if (await enviar(t, path)) fechar(); } catch (e) { setErro((e as Error).message); }
  };
  return (
    <Dialogo aberto fechar={fechar} titulo={titulo} acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" disabled={t.trim().length < min} onClick={ir}>{acao}</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        <Campo rotulo={rotulo} ajuda={`Mínimo de ${min} caracteres.`}><textarea rows={4} maxLength={6000} value={t} onChange={(e) => setT(e.target.value)} /></Campo>
        {anexo && <Campo rotulo="Documento (opcional)"><input type="file" accept=".pdf,.png,.jpg,.jpeg,.docx,.xlsx" onChange={(e) => setArq(e.target.files?.[0] ?? null)} /></Campo>}
      </div>
    </Dialogo>
  );
}

function OutroMeio({ avId, fechar, enviar }: { avId: string; fechar: () => void; enviar: (data: string, path: string) => Promise<boolean> }) {
  const hoje = new Date().toISOString().slice(0, 10);
  const [d, setD] = useState(hoje);
  const [arq, setArq] = useState<File | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const ir = async () => { try { if (!arq) return setErro('Anexe o documento assinado.'); if (await enviar(d, await enviarArquivo(avId, arq))) fechar(); } catch (e) { setErro((e as Error).message); } };
  return (
    <Dialogo aberto fechar={fechar} titulo="Registrar ciência por outro meio" acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={ir}>Registrar</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        <p style={{ margin: 0 }}>Use quando o servidor deu ciência presencialmente ou em papel. O anexo da ciência assinada é obrigatório.</p>
        <Campo rotulo="Data da ciência"><input type="date" max={hoje} value={d} onChange={(e) => setD(e.target.value)} /></Campo>
        <Campo rotulo="Documento assinado"><input type="file" accept=".pdf,.png,.jpg,.jpeg" onChange={(e) => setArq(e.target.files?.[0] ?? null)} /></Campo>
      </div>
    </Dialogo>
  );
}

function Decidir({ D, fechar, enviar }: { D: Detalhe; fechar: () => void; enviar: (f: string, notas: { indicador: string; nota: number; justificativa: string }[]) => Promise<boolean> }) {
  const [f, setF] = useState('');
  const [alt, setAlt] = useState<Record<string, { nota: string; justificativa: string }>>({});
  const ir = async () => {
    const notas = Object.entries(alt).filter(([, v]) => v.nota !== '').map(([indicador, v]) => ({ indicador, nota: Number(v.nota.replace(',', '.')), justificativa: v.justificativa }));
    if (await enviar(f, notas)) fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo="Decidir recurso" acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" disabled={f.trim().length < 20} onClick={ir}>Registrar decisão</button></>}>
      <div className="form">
        <p style={{ margin: 0, fontSize: 13 }}><strong>Razões do servidor:</strong> {D.recursos.at(-1)?.razoes}</p>
        <Campo rotulo="Decisão fundamentada" ajuda="Obrigatória (mín. 20 caracteres). Mantém ou altera indicadores."><textarea rows={4} maxLength={6000} value={f} onChange={(e) => setF(e.target.value)} /></Campo>
        <strong style={{ fontSize: 13 }}>Alterar indicadores (opcional; cada alteração exige justificativa)</strong>
        {D.regra.indicadores.map((i) => {
          const atual = D.notas.find((n) => n.indicador === i.codigo)?.nota;
          return <div key={i.codigo} className="form-linha">
            <Campo rotulo={`${i.codigo} (atual ${num(atual ?? null)} de ${i.maximo})`}><input inputMode="decimal" value={alt[i.codigo]?.nota ?? ''} onChange={(e) => setAlt({ ...alt, [i.codigo]: { nota: e.target.value, justificativa: alt[i.codigo]?.justificativa ?? '' } })} placeholder="manter" /></Campo>
            <Campo rotulo="Justificativa"><input maxLength={2000} value={alt[i.codigo]?.justificativa ?? ''} onChange={(e) => setAlt({ ...alt, [i.codigo]: { nota: alt[i.codigo]?.nota ?? '', justificativa: e.target.value } })} /></Campo>
          </div>;
        })}
      </div>
    </Dialogo>
  );
}
