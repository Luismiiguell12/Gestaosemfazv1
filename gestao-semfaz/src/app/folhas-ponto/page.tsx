'use client';
import { Suspense, useMemo, useState } from 'react';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { Aviso, Campo, Dialogo, EstadoVazio, Selo } from '@/components/ui';
import { mensagemErro } from '@/lib/erros';
import {
  agruparPorUnidade, ehPdf, juntarPdfs, lerPaginas, montarPdfUnidade, nomeArquivoUnidade,
  PDF_TAMANHO_MAX, REGEX_MATRICULA_PADRAO, type PaginaMapeada,
} from '@/lib/folhas';
import { dataCurta, dataHora } from '@/lib/formato';
import { ehGestorGeral, useSessao } from '@/lib/sessao';
import { basePath, supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';

interface Lote { id: string; competencia: string; arquivo_path: string | null; total_paginas: number; concluido: boolean; criado_em: string }
interface Arquivo { id: string; lote_id: string; unidade_id: string | null; path: string; paginas: number; servidores: number; criado_em: string }
interface Entrega { unidade_id: string; sigla: string; ordem: number; situacao: 'nao_enviada' | 'enviada' | 'devolvida'; enviada_em: string | null; recebida_por: string | null; devolvida_em: string | null; devolvida_por: string | null; atrasada: boolean }
interface UnidadeMin { id: string; sigla: string; nome: string; ordem: number; tipo: string }

const BUCKET = 'folhas-ponto';
const hojeMes = () => new Date().toISOString().slice(0, 7);
const mesExtenso = (ym: string) => new Intl.DateTimeFormat('pt-BR', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(new Date(`${ym}-01T00:00:00Z`));
const mmYYYY = (ym: string) => `${ym.slice(5, 7)}/${ym.slice(0, 4)}`;

function salvarArquivo(bytes: Uint8Array | Blob, nome: string, tipo = 'application/pdf') {
  const blob = bytes instanceof Blob ? bytes : new Blob([bytes as BlobPart], { type: tipo });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = nome;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 10000);
}
function abrirParaImprimir(bytes: Uint8Array | Blob) {
  const blob = bytes instanceof Blob ? bytes : new Blob([bytes as BlobPart], { type: 'application/pdf' });
  const url = URL.createObjectURL(blob);
  window.open(url, '_blank', 'noopener');
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}
async function pdfjs() {
  const lib = await import('pdfjs-dist');
  lib.GlobalWorkerOptions.workerSrc = `${basePath}/pdf.worker.min.mjs`;
  return lib;
}
const pdflib = () => import('pdf-lib');

export default function FolhasPontoPage() {
  return <AppShell modulo="folhas_ponto"><Suspense><Folhas /></Suspense></AppShell>;
}

function Folhas() {
  const { info } = useSessao();
  const geral = ehGestorGeral(info);
  const [mes, setMes] = useState(hojeMes());
  const competencia = `${mes}-01`;
  const [versao, setVersao] = useState(0);
  const recarregar = () => setVersao((v) => v + 1);

  const unidades = useConsulta(async () => supabase.from('unidades').select('id,sigla,nome,ordem,tipo'), []);
  const U = (unidades.dados as UnidadeMin[] | null) ?? [];
  const nomeUnidade = (id: string | null) => {
    const u = U.find((x) => x.id === id);
    return !id ? 'Não identificadas' : u?.tipo === 'gabinete' ? u.nome : u?.sigla ?? '—';
  };
  const lotes = useConsulta(async () => supabase.from('folhas_lotes').select('id,competencia,arquivo_path,total_paginas,concluido,criado_em')
    .eq('competencia', competencia).eq('concluido', true).order('criado_em', { ascending: false }).limit(1), [competencia, versao]);
  const lote = ((lotes.dados as Lote[] | null) ?? [])[0];
  const arquivos = useConsulta(async () => supabase.from('folhas_arquivos').select('id,lote_id,unidade_id,path,paginas,servidores,criado_em')
    .eq('lote_id', lote?.id ?? '00000000-0000-0000-0000-000000000000').order('criado_em', { ascending: false }), [lote?.id, versao]);
  const atuais = useMemo(() => {
    const vistos = new Set<string>();
    return ((arquivos.dados as Arquivo[] | null) ?? []).filter((a) => {
      const k = a.unidade_id ?? 'sem';
      if (vistos.has(k)) return false;
      vistos.add(k);
      return true;
    }).sort((a, b) => (a.unidade_id ? (U.find((u) => u.id === a.unidade_id)?.ordem ?? 0) : 1e9) - (b.unidade_id ? (U.find((u) => u.id === b.unidade_id)?.ordem ?? 0) : 1e9));
  }, [arquivos.dados, U]);
  const paginas = useConsulta(async () => (geral && lote ? supabase.rpc('paginas_do_lote', { p_lote: lote.id }) : Promise.resolve({ data: [], error: null })), [lote?.id, geral, versao]);
  const P = (paginas.dados as PaginaMapeada[] | null) ?? [];
  const semServidor = P.filter((p) => !p.unidade_id);
  const entregas = useConsulta(async () => supabase.rpc('situacao_entregas', { p_competencia: competencia }), [competencia, versao]);
  const E = (entregas.dados as Entrega[] | null) ?? [];

  const [enviando, setEnviando] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [vincular, setVincular] = useState<PaginaMapeada | null>(null);
  const [entrega, setEntrega] = useState<{ e: Entrega; etapa: 'envio' | 'devolucao' } | null>(null);

  const baixar = async (path: string) => {
    const { data, error } = await supabase.storage.from(BUCKET).download(path);
    if (error || !data) throw new Error('download');
    return new Uint8Array(await data.arrayBuffer());
  };

  /** monta e envia os PDFs das unidades indicadas (ou de todas) */
  async function gerarArquivos(loteId: string, original: Uint8Array, apenas?: Set<string>) {
    const { data, error } = await supabase.rpc('paginas_do_lote', { p_lote: loteId });
    if (error) throw error;
    const grupos = agruparPorUnidade(data as PaginaMapeada[]).filter((g) => !apenas || apenas.has(g.unidade_id ?? 'sem-unidade'));
    const lib = await pdflib();
    const registros = [];
    for (const g of grupos) {
      setEnviando(`Gerando PDF de ${g.unidade}…`);
      const bytes = await montarPdfUnidade(lib as never, original, g, mmYYYY(mes));
      const path = `lotes/${loteId}/unidades/${g.unidade_id ?? 'sem-unidade'}-${Date.now()}.pdf`;
      const up = await supabase.storage.from(BUCKET).upload(path, new Blob([bytes as BlobPart], { type: 'application/pdf' }), { contentType: 'application/pdf', upsert: false });
      if (up.error) throw up.error;
      registros.push({ unidade_id: g.unidade_id, path, paginas: g.paginas.length, servidores: g.servidores });
    }
    return registros;
  }

  async function enviarPdf(arquivo: File | undefined) {
    if (!arquivo) return;
    setErro(null);
    try {
      if (arquivo.size > PDF_TAMANHO_MAX) throw new Error('Arquivo maior que 50 MB.');
      const bytes = new Uint8Array(await arquivo.arrayBuffer());
      if (!ehPdf(bytes)) throw new Error('O arquivo não é um PDF.');
      setEnviando('Lendo as páginas do PDF…');
      const cfg = await supabase.from('configuracoes').select('valor').eq('chave', 'folhas.regex_matricula').maybeSingle();
      const regex = typeof cfg.data?.valor === 'string' ? cfg.data.valor : REGEX_MATRICULA_PADRAO;
      const lidas = await lerPaginas(await pdfjs() as never, bytes, regex, (n, t) => setEnviando(`Lendo página ${n} de ${t}…`));
      if (lidas.every((l) => !l.matricula)) throw new Error('Nenhuma matrícula encontrada. O PDF precisa ter texto selecionável (não pode ser imagem escaneada).');
      setEnviando('Cruzando matrículas com o cadastro…');
      const r = await supabase.rpc('criar_lote_folhas', { p_competencia: competencia, p_paginas: lidas });
      if (r.error) throw r.error;
      const loteId = r.data as string;
      setEnviando('Guardando o PDF original…');
      const original = `lotes/${loteId}/original.pdf`;
      const up = await supabase.storage.from(BUCKET).upload(original, arquivo, { contentType: 'application/pdf', upsert: false });
      if (up.error) throw up.error;
      const registros = await gerarArquivos(loteId, bytes);
      const reg = await supabase.rpc('registrar_arquivos_folhas', { p_lote: loteId, p_original: original, p_arquivos: registros });
      if (reg.error) throw reg.error;
      recarregar();
    } catch (e) {
      setErro(e instanceof Error && !('code' in e) ? e.message : mensagemErro(e));
    } finally { setEnviando(null); }
  }

  async function confirmarVinculo(p: PaginaMapeada, servidor: string) {
    if (!lote?.arquivo_path) return;
    setErro(null);
    try {
      setEnviando('Vinculando página…');
      const v = await supabase.rpc('vincular_pagina_folha', { p_lote: lote.id, p_pagina: p.pagina, p_servidor: servidor });
      if (v.error) throw v.error;
      const original = await baixar(lote.arquivo_path);
      const registros = await gerarArquivos(lote.id, original, new Set([v.data as string, 'sem-unidade']));
      const reg = await supabase.rpc('registrar_arquivos_folhas', { p_lote: lote.id, p_original: null, p_arquivos: registros });
      if (reg.error) throw reg.error;
      setVincular(null);
      recarregar();
    } catch (e) { setErro(mensagemErro(e)); } finally { setEnviando(null); }
  }

  const baixarUm = async (a: Arquivo, imprimir = false) => {
    try {
      const b = await baixar(a.path);
      if (imprimir) abrirParaImprimir(b); else salvarArquivo(b, `Folhas_${nomeArquivoUnidade(nomeUnidade(a.unidade_id))}_${mes}.pdf`);
    } catch { setErro('Não foi possível baixar o arquivo.'); }
  };
  const baixarZip = async () => {
    setEnviando('Preparando ZIP…');
    try {
      const { zipSync } = await import('fflate');
      const conteudo: Record<string, Uint8Array> = {};
      for (const a of atuais) conteudo[`Folhas_${nomeArquivoUnidade(nomeUnidade(a.unidade_id))}_${mes}.pdf`] = await baixar(a.path);
      salvarArquivo(new Blob([zipSync(conteudo) as BlobPart], { type: 'application/zip' }), `Folhas_ponto_${mes}.zip`, 'application/zip');
    } catch { setErro('Não foi possível gerar o ZIP.'); } finally { setEnviando(null); }
  };
  const pdfUnico = async () => {
    setEnviando('Juntando as unidades…');
    try {
      const lib = await pdflib();
      abrirParaImprimir(await juntarPdfs(lib as never, await Promise.all(atuais.filter((a) => a.unidade_id).map((a) => baixar(a.path)))));
    } catch { setErro('Não foi possível gerar o PDF único.'); } finally { setEnviando(null); }
  };

  const separadas = P.length - semServidor.length;
  const servidores = new Set(P.filter((p) => p.unidade_id).map((p) => p.servidor)).size;
  const etapa = !lote ? 1 : semServidor.length ? 2 : 3;
  const etapas = [
    { n: 1, t: 'Enviar o PDF do RH', d: lote ? 'Concluído' : 'Aguardando o arquivo' },
    { n: 2, t: 'Conferir pendências', d: !lote ? '—' : semServidor.length ? `${semServidor.length} página(s) para conferir` : 'Nenhuma pendência' },
    { n: 3, t: 'Baixar ou imprimir', d: 'Por unidade ou tudo junto' },
  ];

  return (
    <>
      <Cabecalho
        trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Folhas de ponto' }]}
        titulo={`Folhas de ponto · ${mesExtenso(mes)}`}
        acoes={<>
          <label className="campo campo-leve">Competência
            <input type="month" value={mes} onChange={(e) => e.target.value && setMes(e.target.value)} style={{ fontSize: 14, padding: '9px 10px', border: '1px solid var(--cor-borda-campo)', borderRadius: 8, minHeight: 42 }} />
          </label>
          {geral && (
            <label className="botao" style={{ cursor: enviando ? 'wait' : 'pointer' }}>
              {lote ? 'Enviar outro PDF' : 'Enviar PDF do RH'}
              <input type="file" accept="application/pdf" className="sr-only" disabled={Boolean(enviando)} onChange={(e) => { void enviarPdf(e.target.files?.[0]); e.target.value = ''; }} />
            </label>
          )}
        </>}
      />
      {enviando && <Aviso tom="info" role="status">{enviando}</Aviso>}
      {erro && <Aviso tom="critico">{erro}</Aviso>}

      {geral && (
        <ol aria-label="Etapas" className="etapas">
          {etapas.map((s) => (
            <li key={s.n} className="etapa" data-feita={s.n < etapa || (s.n === 1 && Boolean(lote))} data-atual={s.n === etapa && !(s.n === 1 && lote)}>
              <span className="etapa-num">{s.n < etapa || (s.n === 1 && lote) ? '✓' : s.n}</span>
              <span style={{ fontSize: 14 }}><strong>{s.t}</strong><br /><span className="texto-suave">{s.d}</span></span>
            </li>
          ))}
        </ol>
      )}

      {geral && lote && (
        <section className="cartao" style={{ display: 'flex', flexWrap: 'wrap', gap: 20, alignItems: 'center' }}>
          <div aria-hidden="true" style={{ width: 48, height: 56, borderRadius: 6, background: 'var(--selo-critico-bg)', color: 'var(--cor-critico)', fontWeight: 700, fontSize: 12, display: 'flex', alignItems: 'flex-end', justifyContent: 'center', paddingBottom: 8 }}>PDF</div>
          <div style={{ flex: '1 1 260px', minWidth: 0 }}>
            <div style={{ fontWeight: 600 }}>PDF do RH · {mmYYYY(mes)}</div>
            <div className="texto-suave" style={{ fontSize: 13 }}>{lote.total_paginas} páginas · lido em {dataHora(lote.criado_em).replace(', ', ' às ')}</div>
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 24, fontSize: 13 }}>
            <div><div style={{ fontSize: 26, fontWeight: 700, color: 'var(--cor-positivo)' }}>{separadas}</div>páginas separadas</div>
            <div><div style={{ fontSize: 26, fontWeight: 700, color: 'var(--cor-texto-forte)' }}>{servidores}</div>servidores</div>
            <div><div style={{ fontSize: 26, fontWeight: 700, color: 'var(--cor-critico)' }}>{semServidor.length}</div>para conferir</div>
          </div>
        </section>
      )}

      <div className="linha">
        <section className="cartao col-principal" style={{ gap: 0 }}>
          <div className="cartao-topo" style={{ alignItems: 'center' }}>
            <h2>Separado por unidade</h2>
            <div className="acoes" style={{ gap: 8 }}>
              <button type="button" className="botao" style={{ minHeight: 40 }} disabled={!atuais.length || Boolean(enviando)} onClick={baixarZip}>Baixar todas (ZIP)</button>
              <button type="button" className="botao botao-primario" style={{ minHeight: 40 }} disabled={!atuais.length || Boolean(enviando)} onClick={pdfUnico}>PDF único para imprimir</button>
            </div>
          </div>
          <p className="nota" style={{ marginTop: 8 }}>O PDF único sai na ordem das unidades, com uma folha de rosto antes de cada uma. Dentro da unidade, servidores em ordem alfabética.</p>
          <div className="tabela-rolagem">
            <table className="tabela tabela-cartoes">
              <thead><tr><th>Unidade</th><th>Servidores</th><th>Páginas</th><th style={{ textAlign: 'right' }}>Ações</th></tr></thead>
              <tbody>
                {atuais.map((a) => (
                  <tr key={a.id}>
                    <td data-rotulo="Unidade" style={{ fontWeight: 600 }}>{nomeUnidade(a.unidade_id)}</td>
                    <td data-rotulo="Servidores">{a.servidores}</td><td data-rotulo="Páginas">{a.paginas}</td>
                    <td data-rotulo="Ações" style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
                      <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-primaria)', cursor: 'pointer', minHeight: 36, padding: '0 10px' }} onClick={() => baixarUm(a)}>Baixar</button>
                      <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-primaria)', cursor: 'pointer', minHeight: 36, padding: '0 10px' }} onClick={() => baixarUm(a, true)}>Imprimir</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {!arquivos.carregando && !atuais.length && <EstadoVazio>{geral ? 'Nenhum PDF enviado para esta competência.' : 'As folhas desta competência ainda não foram separadas.'}</EstadoVazio>}
          </div>
        </section>

        <aside className="col-lateral">
          {geral && semServidor.length > 0 && (
            <section role="alert" className="cartao" style={{ borderColor: 'var(--aviso-critico-borda)' }}>
              <h2 style={{ fontSize: 16, color: 'var(--cor-critico)', marginBottom: 4 }}>{semServidor.length} página(s) sem servidor no cadastro</h2>
              <p style={{ margin: '0 0 10px', fontSize: 13, color: 'var(--cor-texto-2)' }}>Nenhuma página é descartada. Vincule a um servidor ou deixe em &quot;Não identificadas&quot;.</p>
              {semServidor.map((p) => (
                <div key={p.pagina} style={{ borderTop: '1px solid var(--cor-divisor)', padding: '10px 0', fontSize: 13 }}>
                  <div><strong>Página {p.pagina}</strong> · matrícula {p.matricula_lida ?? 'não encontrada'}</div>
                  <div className="texto-suave" style={{ fontSize: 13 }}>Nome na folha: {p.nome_lido ?? '—'}</div>
                  <button type="button" className="botao botao-bloco" style={{ marginTop: 8, minHeight: 40 }} disabled={Boolean(enviando)} onClick={() => setVincular(p)}>Vincular a um servidor</button>
                </div>
              ))}
            </section>
          )}
          <section className="aviso aviso-info" style={{ display: 'block' }}>
            <strong>Como funciona</strong><br />O sistema lê a matrícula em cada página do PDF do RH e cruza com o cadastro de servidores para saber a unidade. O arquivo original fica guardado junto com o resultado.
          </section>
        </aside>
      </div>

      <section className="cartao">
        <div className="cartao-topo"><h2>Controle de entrega · {mmYYYY(mes)}</h2><span className="texto-suave">Unidades que ainda não devolveram aparecem no painel.</span></div>
        {entregas.erro && <Aviso tom="critico">{entregas.erro}</Aviso>}
        <div className="tabela-rolagem">
          <table className="tabela tabela-cartoes">
            <thead><tr><th>Unidade</th><th>Situação</th><th>Enviada em</th><th>Quem recebeu</th><th>Devolvida em</th><th>Quem devolveu</th><th style={{ textAlign: 'right' }}>Registrar</th></tr></thead>
            <tbody>
              {E.map((e) => (
                <tr key={e.unidade_id}>
                  <td data-rotulo="Unidade" style={{ fontWeight: 600 }}>{nomeUnidade(e.unidade_id)}</td>
                  <td data-rotulo="Situação">
                    {e.situacao === 'devolvida' ? <Selo tom="positivo">Devolvida</Selo> : e.situacao === 'enviada' ? (e.atrasada ? <Selo tom="critico">Atrasada</Selo> : <Selo tom="alerta">Enviada</Selo>) : <Selo tom="neutro">Não enviada</Selo>}
                  </td>
                  <td data-rotulo="Enviada em">{e.enviada_em ? dataCurta(e.enviada_em) : '—'}</td><td data-rotulo="Quem recebeu">{e.recebida_por ?? '—'}</td>
                  <td data-rotulo="Devolvida em">{e.devolvida_em ? dataCurta(e.devolvida_em) : '—'}</td><td data-rotulo="Quem devolveu">{e.devolvida_por ?? '—'}</td>
                  <td data-rotulo="Registrar" style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
                    <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-primaria)', cursor: 'pointer', minHeight: 36 }} onClick={() => setEntrega({ e, etapa: 'envio' })}>Envio</button>
                    {e.enviada_em && <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-primaria)', cursor: 'pointer', minHeight: 36 }} onClick={() => setEntrega({ e, etapa: 'devolucao' })}>Devolução</button>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {!entregas.carregando && !E.length && <EstadoVazio>Nenhuma unidade no seu escopo.</EstadoVazio>}
        </div>
      </section>
      <p className="nota">Folhas de cada unidade visíveis só a quem tem permissão sobre ela. Prazo de devolução configurável (dias úteis); a chefia é avisada quando atrasa.</p>

      {vincular && <Vincular p={vincular} fechar={() => setVincular(null)} confirmar={(s) => void confirmarVinculo(vincular, s)} ocupado={Boolean(enviando)} />}
      {entrega && <RegistrarEntrega competencia={competencia} alvo={entrega.e} etapa={entrega.etapa} nome={nomeUnidade(entrega.e.unidade_id)} fechar={() => setEntrega(null)} aoSalvar={recarregar} />}
    </>
  );
}

function Vincular({ p, fechar, confirmar, ocupado }: { p: PaginaMapeada; fechar: () => void; confirmar: (servidor: string) => void; ocupado: boolean }) {
  const [busca, setBusca] = useState(p.nome_lido ?? '');
  const [sel, setSel] = useState('');
  const lista = useConsulta(async () => supabase.from('servidores').select('id,nome_completo,matricula').ilike('nome_completo', `%${busca.replace(/[%_]/g, '')}%`).order('nome_completo').limit(20), [busca]);
  const L = (lista.dados as { id: string; nome_completo: string; matricula: string }[] | null) ?? [];
  return (
    <Dialogo aberto fechar={fechar} titulo={`Vincular a página ${p.pagina}`} acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" disabled={!sel || ocupado} onClick={() => confirmar(sel)}>Vincular</button></>}>
      <div className="form">
        <p style={{ margin: 0, fontSize: 13 }}>Matrícula lida: <strong>{p.matricula_lida ?? '—'}</strong> · nome na folha: {p.nome_lido ?? '—'}</p>
        <Campo rotulo="Buscar servidor"><input value={busca} maxLength={100} onChange={(e) => setBusca(e.target.value)} /></Campo>
        <Campo rotulo="Servidor"><select value={sel} onChange={(e) => setSel(e.target.value)} size={Math.min(8, Math.max(L.length, 2))}>{L.map((s) => <option key={s.id} value={s.id}>{s.nome_completo} · {s.matricula}</option>)}</select></Campo>
        <p className="nota">Se a matrícula do cadastro estiver errada, corrija pelo pedido de alteração (passa por aprovação).</p>
      </div>
    </Dialogo>
  );
}

function RegistrarEntrega({ competencia, alvo, etapa, nome, fechar, aoSalvar }: { competencia: string; alvo: Entrega; etapa: 'envio' | 'devolucao'; nome: string; fechar: () => void; aoSalvar: () => void }) {
  const [data, setData] = useState(new Date().toISOString().slice(0, 10));
  const [pessoa, setPessoa] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const pessoas = useConsulta(async () => supabase.from('servidores').select('id,nome_completo').eq('unidade_id', alvo.unidade_id).eq('situacao', 'ativo').order('nome_completo'), [alvo.unidade_id]);
  const salvar = async () => {
    setErro(null);
    if (!pessoa) { setErro(etapa === 'envio' ? 'Informe quem recebeu.' : 'Informe quem devolveu.'); return; }
    const { error } = await supabase.rpc('registrar_entrega_folha', { p_competencia: competencia, p_unidade: alvo.unidade_id, p_etapa: etapa, p_data: data, p_pessoa: pessoa });
    if (error) { setErro(mensagemErro(error)); return; }
    aoSalvar(); fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo={`${etapa === 'envio' ? 'Envio' : 'Devolução'} das folhas · ${nome}`} acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={salvar}>Registrar</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        <Campo rotulo={etapa === 'envio' ? 'Data de envio à unidade' : 'Data da devolução assinada'}><input type="date" value={data} max={new Date().toISOString().slice(0, 10)} onChange={(e) => setData(e.target.value)} /></Campo>
        <Campo rotulo={etapa === 'envio' ? 'Quem recebeu' : 'Quem devolveu'}>
          <select value={pessoa} onChange={(e) => setPessoa(e.target.value)}><option value="">Selecione…</option>{((pessoas.dados as { id: string; nome_completo: string }[] | null) ?? []).map((s) => <option key={s.id} value={s.id}>{s.nome_completo}</option>)}</select>
        </Campo>
      </div>
    </Dialogo>
  );
}
