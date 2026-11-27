'use client';
import { useSearchParams } from 'next/navigation';
import { Suspense, useEffect, useRef, useState } from 'react';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { Aviso, Campo, Dialogo, EstadoVazio, Selo } from '@/components/ui';
import { MIME_DEMANDA, validarAnexoDemanda } from '@/lib/arquivos';
import {
  ABERTOS, COLUNAS, COR_PRIORIDADE, mencoesNoTexto, ROTULO_ORIGEM_LONGO, ROTULO_PRIORIDADE, ROTULO_STATUS, textoPrazo, TOM_STATUS,
  type Origem, type Prioridade, type Responsavel, type StatusDemanda,
} from '@/lib/demandas';
import { mensagemErro } from '@/lib/erros';
import { dataCurta, dataHora } from '@/lib/formato';
import { useSessao } from '@/lib/sessao';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';

interface Detalhe {
  demanda: { id: string; numero: number; titulo: string; descricao: string | null; origem: Origem; numero_processo: string | null; unidade_id: string; unidade: string;
    prioridade: Prioridade; status: StatusDemanda; prazo: string | null; dias_uteis: number | null; concluida_em: string | null; criado_em: string; criado_por_nome: string; recorrencia_id: string | null };
  permissoes: { gerir: boolean; responsavel: boolean; anexar: boolean; proprio_criador: boolean };
  responsaveis: Responsavel[];
  checklist: { id: string; texto: string; feito: boolean; responsavel: string | null; feito_por: string | null; feito_em: string | null }[];
  mensagens: { id: string; tipo: 'mensagem' | 'pedido_atualizacao'; texto: string; autor_id: string; autor: string; criado_em: string; editado_em: string | null;
    feedback: 'aprovado' | 'ajustar' | 'refazer' | null; feedback_comentario: string | null; feedback_por: string | null; anexo: { id: string; nome: string; path: string } | null }[];
  anexos: { id: string; nome: string; path: string; tipo: string; tamanho: number; versao: number; substitui_id: string | null; enviado_por: string; enviado_em: string }[];
  historico: { em: string; ator: string | null; acao: string; detalhes: Record<string, unknown> }[];
}

const FEEDBACK = { aprovado: 'Aprovado', ajustar: 'Ajustar', refazer: 'Refazer' } as const;

function textoHistorico(h: Detalhe['historico'][number]) {
  const d = h.detalhes as Record<string, string | number | null>;
  switch (h.acao) {
    case 'criada': return 'Demanda criada';
    case 'criada_por_rotina': return `Criada automaticamente (modelo recorrente, referência ${d.referencia})`;
    case 'sugerida': return 'Sugestão enviada';
    case 'sugestao_aprovada': return 'Sugestão aprovada pela chefia';
    case 'sugestao_recusada': return `Sugestão recusada${d.comentario ? `: ${d.comentario}` : ''}`;
    case 'responsavel_incluido': return `${d.servidor} incluído(a) como responsável`;
    case 'status': return `Status: ${ROTULO_STATUS[d.de as StatusDemanda] ?? d.de} → ${ROTULO_STATUS[d.para as StatusDemanda] ?? d.para}`;
    case 'editada': return 'Dados da demanda alterados';
    case 'etapa_incluida': return `Etapa incluída: ${d.etapa}`;
    case 'etapa_marcada': return `Etapa feita: ${d.etapa}`;
    case 'etapa_desmarcada': return `Etapa desmarcada: ${d.etapa}`;
    case 'etapa_removida': return `Etapa removida: ${d.etapa}`;
    case 'mencao': return `${d.usuario} mencionado(a) na conversa`;
    case 'pedido_atualizacao': return 'Pedido de atualização';
    case 'feedback': return `Feedback: ${d.feedback}${d.comentario ? ` — ${d.comentario}` : ''}`;
    case 'anexo': return `Anexo: ${d.nome}`;
    case 'anexo_nova_versao': return `Nova versão (v${d.versao}): ${d.nome}`;
    case 'substituicao_inicio': return `${d.substituto} substitui ${d.titular} até ${dataCurta(String(d.ate))}`;
    case 'substituicao_fim': return `Fim da substituição: ${d.substituto} saiu da demanda`;
    default: return h.acao;
  }
}

export default function FichaPage() {
  return <AppShell modulo="demandas"><Suspense><Ficha /></Suspense></AppShell>;
}

function Ficha() {
  const id = useSearchParams().get('id') ?? '';
  const { info } = useSessao();
  const [versao, setVersao] = useState(0);
  const recarregar = () => setVersao((v) => v + 1);
  const det = useConsulta(async () => supabase.rpc('demanda_detalhe', { p_id: id }), [id, versao]);
  const D = det.dados as Detalhe | null;
  const [erro, setErro] = useState<string | null>(null);
  const [editar, setEditar] = useState(false);
  const [resp, setResp] = useState(false);
  const [pedido, setPedido] = useState(false);

  if (det.carregando && !D) return <div className="carregando">Carregando…</div>;
  if (!D) return <><Cabecalho trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Demandas', href: '/demandas' }]} titulo="Demanda não encontrada" /><p className="nota">Ela não existe ou você não tem acesso.</p></>;

  const d = D.demanda;
  const p = textoPrazo(d);
  const podeStatus = D.permissoes.gerir || D.permissoes.responsavel;
  const rpc = async (fn: string, args: Record<string, unknown>) => {
    setErro(null);
    const { error } = await supabase.rpc(fn, args);
    if (error) { setErro(mensagemErro(error)); return false; }
    recarregar();
    return true;
  };
  const feitas = D.checklist.filter((c) => c.feito).length;

  return (
    <>
      <Cabecalho
        trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Demandas', href: '/demandas' }, { rotulo: `#${d.numero}` }]}
        titulo={`#${d.numero} · ${d.titulo}`}
        subtitulo={<span className="acoes" style={{ gap: 8, marginTop: 6 }}>
          <Selo tom={TOM_STATUS[d.status]}>{ROTULO_STATUS[d.status]}</Selo>
          <span className="selo" style={{ background: COR_PRIORIDADE[d.prioridade][0], color: COR_PRIORIDADE[d.prioridade][1] }}>{ROTULO_PRIORIDADE[d.prioridade]}</span>
          {d.prazo && <Selo tom={p.atrasada ? 'critico' : d.status === 'concluida' ? 'positivo' : 'info'}>{d.status === 'concluida' ? p.texto : `Prazo ${dataCurta(d.prazo)} · ${p.texto}`}</Selo>}
          {D.checklist.length > 0 && <Selo tom="neutro">{feitas} de {D.checklist.length} etapas</Selo>}
        </span>}
        acoes={<>
          {podeStatus && d.status !== 'sugerida' && d.status !== 'recusada' && (
            <label className="campo campo-leve">Mudar status
              <select value={d.status} onChange={(e) => void rpc('mudar_status_demanda', { p_id: d.id, p_status: e.target.value })}
                style={{ fontSize: 14, padding: '9px 10px', border: '1px solid var(--cor-borda-campo)', borderRadius: 8, background: '#fff', minHeight: 42 }}>
                {[...COLUNAS.map((c) => c.status), ...(D.permissoes.gerir ? ['cancelada' as StatusDemanda] : [])].map((s) => <option key={s} value={s}>{ROTULO_STATUS[s]}</option>)}
              </select>
            </label>
          )}
          {D.permissoes.gerir && ABERTOS.includes(d.status) && <button type="button" className="botao" onClick={() => setPedido(true)}>Pedir atualização</button>}
          {D.permissoes.gerir && <button type="button" className="botao" onClick={() => setResp(true)}>Responsáveis</button>}
          {D.permissoes.gerir && <button type="button" className="botao botao-primario" onClick={() => setEditar(true)}>Editar</button>}
        </>}
      />
      {erro && <Aviso tom="critico">{erro}</Aviso>}
      {d.status === 'sugerida' && <Aviso tom="alerta">Sugestão aguardando a aprovação da chefia da unidade.</Aviso>}

      <section aria-label="Resumo da demanda" className="cartao" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(170px, 1fr))', gap: '16px 20px' }}>
        {[
          ['Unidade', d.unidade], ['Origem', ROTULO_ORIGEM_LONGO[d.origem]], ['Nº do processo', d.numero_processo ?? '—'], ['Prazo', d.prazo ? dataCurta(d.prazo) : '—'],
          ['Responsáveis', D.responsaveis.map((r) => r.nome + (r.papel === 'substituto' ? ' (substituto)' : '')).join(', ') || '—'],
          ['Criada por', d.criado_por_nome], ['Criada em', dataHora(d.criado_em)], ['Concluída em', d.concluida_em ? dataHora(d.concluida_em) : '—'],
        ].map(([k, v]) => <div key={k}><div className="texto-suave">{k}</div><div style={{ fontSize: 15, fontWeight: 600, marginTop: 2 }}>{v}</div></div>)}
      </section>
      {d.descricao && <section className="cartao"><h2 style={{ marginBottom: 8 }}>Descrição</h2><p style={{ margin: 0, whiteSpace: 'pre-wrap', fontSize: 14 }}>{d.descricao}</p></section>}

      <div className="linha">
        <div className="col-principal" style={{ gap: 20 }}>
          <Checklist D={D} rpc={rpc} />
          <Conversa D={D} meuUsuario={info?.usuario_id} rpc={rpc} recarregar={recarregar} setErro={setErro} />
        </div>
        <aside className="col-lateral" style={{ gap: 20 }}>
          <Anexos D={D} recarregar={recarregar} setErro={setErro} />
          <section className="cartao">
            <h2 style={{ marginBottom: 8 }}>Histórico</h2>
            <div style={{ fontSize: 13, lineHeight: 1.6, color: 'var(--cor-texto-2)', maxHeight: 420, overflowY: 'auto' }}>
              {D.historico.map((h, i) => <div key={i} style={{ borderTop: i ? '1px solid var(--cor-divisor)' : 0, padding: '6px 0' }}><span className="texto-suave">{dataHora(h.em)}{h.ator ? ` · ${h.ator}` : ' · Sistema'}</span><br />{textoHistorico(h)}</div>)}
            </div>
          </section>
        </aside>
      </div>
      <p className="nota">Conversa visível aos responsáveis, à chefia da unidade, à Secretária e a quem for mencionado. Mensagens e anexos nunca são apagados.</p>

      {editar && <EditarDemanda D={D} fechar={() => setEditar(false)} aoSalvar={recarregar} />}
      {resp && <EditarResponsaveis D={D} fechar={() => setResp(false)} aoSalvar={recarregar} />}
      {pedido && <PedirAtualizacao id={d.id} fechar={() => setPedido(false)} aoSalvar={recarregar} />}
    </>
  );
}

function Checklist({ D, rpc }: { D: Detalhe; rpc: (fn: string, a: Record<string, unknown>) => Promise<boolean> }) {
  const [novo, setNovo] = useState('');
  const pode = D.permissoes.gerir || D.permissoes.responsavel;
  const feitas = D.checklist.filter((c) => c.feito).length;
  return (
    <section className="cartao">
      <div className="cartao-topo"><h2>Checklist</h2>{D.checklist.length > 0 && <span className="texto-suave">{feitas} de {D.checklist.length}</span>}</div>
      {D.checklist.length > 0 && <div aria-hidden="true" className="barra" style={{ marginTop: 10 }}><div style={{ flex: feitas, background: 'var(--cor-positivo)' }} /><div style={{ flex: D.checklist.length - feitas, background: 'var(--cor-divisor)' }} /></div>}
      <div style={{ marginTop: 8 }}>
        {D.checklist.map((c) => (
          <label key={c.id} className="etapa-check">
            <input type="checkbox" checked={c.feito} disabled={!pode} onChange={(e) => void rpc('marcar_item_checklist', { p_item: c.id, p_feito: e.target.checked })} />
            <span style={{ flex: 1 }}><span style={{ textDecoration: c.feito ? 'line-through' : 'none' }}>{c.texto}</span>
              <br /><span className="texto-suave">{c.responsavel ? `Responsável: ${c.responsavel}` : ''}{c.feito && c.feito_por ? `${c.responsavel ? ' · ' : ''}feita por ${c.feito_por} em ${dataHora(c.feito_em)}` : ''}</span></span>
            {D.permissoes.gerir && <button type="button" aria-label={`Remover etapa ${c.texto}`} style={{ background: 'none', border: 0, color: 'var(--cor-texto-suave)', cursor: 'pointer', minWidth: 36, minHeight: 36 }} onClick={(e) => { e.preventDefault(); void rpc('remover_item_checklist', { p_item: c.id }); }}>×</button>}
          </label>
        ))}
        {!D.checklist.length && <EstadoVazio>Nenhuma etapa.</EstadoVazio>}
      </div>
      {pode && (
        <form className="acoes" style={{ marginTop: 10 }} onSubmit={async (e) => { e.preventDefault(); if (novo.trim() && await rpc('adicionar_item_checklist', { p_demanda: D.demanda.id, p_texto: novo })) setNovo(''); }}>
          <input aria-label="Nova etapa" placeholder="Nova etapa" maxLength={300} value={novo} onChange={(e) => setNovo(e.target.value)} style={{ flex: 1, minWidth: 0, minHeight: 44, border: '1px solid var(--cor-borda-campo)', borderRadius: 8, padding: '0 10px', font: 'inherit' }} />
          <button type="submit" className="botao">Adicionar</button>
        </form>
      )}
      <p className="nota" style={{ marginTop: 8 }}>Marcar todas as etapas não conclui a demanda: a conclusão é uma ação do responsável.</p>
    </section>
  );
}

async function enviarArquivo(demanda: string, arquivo: File, substitui?: string | null): Promise<string> {
  const v = await validarAnexoDemanda(arquivo);
  if (!v.ok) throw new Error(v.erro);
  const path = `demandas/${demanda}/${crypto.randomUUID()}.${v.tipo}`;
  const up = await supabase.storage.from('demandas').upload(path, arquivo, { contentType: MIME_DEMANDA[v.tipo], upsert: false });
  if (up.error) throw new Error('Não foi possível enviar o arquivo.');
  const { data, error } = await supabase.rpc('registrar_anexo', { p_demanda: demanda, p_path: path, p_nome: arquivo.name, p_tipo: v.tipo, p_tamanho: arquivo.size, p_substitui: substitui ?? null });
  if (error) throw new Error(mensagemErro(error));
  return data as string;
}

async function baixarAnexo(path: string, nome: string) {
  const { data, error } = await supabase.storage.from('demandas').download(path);
  if (error || !data) throw new Error('Não foi possível baixar o anexo.');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(data);
  a.download = nome;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 10000);
}

function Conversa({ D, meuUsuario, rpc, recarregar, setErro }: { D: Detalhe; meuUsuario?: string; rpc: (fn: string, a: Record<string, unknown>) => Promise<boolean>; recarregar: () => void; setErro: (e: string | null) => void }) {
  const [texto, setTexto] = useState('');
  const [arquivo, setArquivo] = useState<File | null>(null);
  const [sugestoes, setSugestoes] = useState<{ usuario_id: string; nome: string; unidade: string }[]>([]);
  const [escolhidas, setEscolhidas] = useState<{ usuario_id: string; nome: string }[]>([]);
  const [enviando, setEnviando] = useState(false);
  const [feedback, setFeedback] = useState<{ id: string; tipo: keyof typeof FEEDBACK } | null>(null);
  const [editando, setEditando] = useState<{ id: string; texto: string } | null>(null);
  const fim = useRef<HTMLDivElement>(null);
  useEffect(() => { fim.current?.scrollIntoView({ block: 'nearest' }); }, [D.mensagens.length]);

  useEffect(() => {
    const m = /@([\p{L}][\p{L} ]{0,30})$/u.exec(texto);
    if (!m) { setSugestoes([]); return; }
    const h = setTimeout(async () => {
      const { data } = await supabase.rpc('usuarios_mencionaveis', { p_termo: m[1].trim() });
      setSugestoes((data as typeof sugestoes) ?? []);
    }, 200);
    return () => clearTimeout(h);
  }, [texto]);

  const escolher = (u: { usuario_id: string; nome: string }) => {
    setTexto(texto.replace(/@([\p{L}][\p{L} ]{0,30})$/u, `@${u.nome} `));
    setEscolhidas([...escolhidas.filter((x) => x.usuario_id !== u.usuario_id), u]);
    setSugestoes([]);
  };
  const enviar = async () => {
    if (!texto.trim()) return;
    setEnviando(true); setErro(null);
    try {
      const anexo = arquivo ? await enviarArquivo(D.demanda.id, arquivo) : null;
      const { error } = await supabase.rpc('enviar_mensagem', { p_demanda: D.demanda.id, p_texto: texto, p_mencoes: mencoesNoTexto(texto, escolhidas), p_anexo: anexo });
      if (error) throw new Error(mensagemErro(error));
      setTexto(''); setArquivo(null); setEscolhidas([]);
      recarregar();
    } catch (e) { setErro((e as Error).message); } finally { setEnviando(false); }
  };

  return (
    <section className="cartao">
      <h2 style={{ marginBottom: 10 }}>Conversa</h2>
      <div className="chat" role="log" aria-label="Mensagens">
        {!D.mensagens.length && <EstadoVazio>Nenhuma mensagem ainda.</EstadoVazio>}
        {D.mensagens.map((m) => (
          <article key={m.id} className={`msg${m.autor_id === meuUsuario ? ' minha' : ''}${m.tipo === 'pedido_atualizacao' ? ' pedido' : ''}`}>
            <div className="msg-topo"><span><strong style={{ color: 'var(--cor-texto)' }}>{m.autor}</strong>{m.tipo === 'pedido_atualizacao' ? ' · pedido de atualização' : ''}</span><span>{dataHora(m.criado_em)}{m.editado_em ? ' · editada' : ''}</span></div>
            {editando?.id === m.id ? (
              <div className="form">
                <textarea rows={2} maxLength={4000} value={editando.texto} onChange={(e) => setEditando({ ...editando, texto: e.target.value })} style={{ font: 'inherit', padding: 8, borderRadius: 8, border: '1px solid var(--cor-borda-campo)' }} />
                <div className="acoes" style={{ gap: 8 }}><button type="button" className="botao" onClick={() => setEditando(null)}>Cancelar</button><button type="button" className="botao botao-primario" onClick={async () => { if (await rpc('editar_mensagem', { p_id: m.id, p_texto: editando.texto })) setEditando(null); }}>Salvar</button></div>
              </div>
            ) : <div className="msg-texto">{m.texto}</div>}
            {m.anexo && <button type="button" className="link-acao" style={{ background: 'none', border: 0, padding: 0, marginTop: 6, color: 'var(--cor-primaria)', cursor: 'pointer', textDecoration: 'underline' }} onClick={() => baixarAnexo(m.anexo!.path, m.anexo!.nome).catch((e) => setErro(e.message))}>📎 {m.anexo.nome}</button>}
            {m.feedback && <div className={`feedback ${m.feedback}`}>{FEEDBACK[m.feedback]}{m.feedback_por ? ` · ${m.feedback_por}` : ''}{m.feedback_comentario ? `: ${m.feedback_comentario}` : ''}</div>}
            <div className="acoes" style={{ gap: 4, marginTop: 6 }}>
              {m.autor_id === meuUsuario && !editando && <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-primaria)', cursor: 'pointer', fontSize: 12, minHeight: 32 }} onClick={() => setEditando({ id: m.id, texto: m.texto })}>Editar</button>}
              {D.permissoes.gerir && m.autor_id !== meuUsuario && m.tipo === 'mensagem' && (Object.keys(FEEDBACK) as (keyof typeof FEEDBACK)[]).map((f) => (
                <button key={f} type="button" className="link-acao" style={{ background: 'none', border: 0, color: f === 'aprovado' ? 'var(--cor-positivo)' : f === 'ajustar' ? 'var(--selo-alerta-fg)' : 'var(--cor-critico)', cursor: 'pointer', fontSize: 12, fontWeight: 600, minHeight: 32 }}
                  onClick={() => setFeedback({ id: m.id, tipo: f })}>{FEEDBACK[f]}</button>
              ))}
            </div>
          </article>
        ))}
        <div ref={fim} />
      </div>
      <div className="form" style={{ marginTop: 12, position: 'relative' }}>
        <textarea rows={3} maxLength={4000} aria-label="Escrever mensagem (use @ para mencionar)" placeholder="Escreva uma mensagem. Use @ para mencionar um colega." value={texto}
          onChange={(e) => setTexto(e.target.value)} style={{ font: 'inherit', fontSize: 14, padding: 10, borderRadius: 8, border: '1px solid var(--cor-borda-campo)', resize: 'vertical' }} />
        {sugestoes.length > 0 && (
          <div className="busca-resultados" role="listbox" aria-label="Colegas para mencionar" style={{ top: 'auto', bottom: '100%' }}>
            {sugestoes.map((s) => <button key={s.usuario_id} type="button" role="option" aria-selected="false" className="busca-item" style={{ width: '100%', textAlign: 'left', background: 'none', border: 0, cursor: 'pointer' }} onClick={() => escolher(s)}>{s.nome}<small>{s.unidade}</small></button>)}
          </div>
        )}
        <div className="acoes" style={{ justifyContent: 'space-between' }}>
          {D.permissoes.anexar ? <label className="campo campo-leve" style={{ flex: 1 }}>Anexo (opcional){arquivo ? `: ${arquivo.name}` : ''}<input type="file" accept=".pdf,.png,.jpg,.jpeg,.docx,.xlsx" onChange={(e) => setArquivo(e.target.files?.[0] ?? null)} /></label> : <span />}
          <button type="button" className="botao botao-primario" disabled={enviando || !texto.trim()} onClick={enviar}>{enviando ? 'Enviando…' : 'Enviar'}</button>
        </div>
      </div>
      {feedback && <DarFeedback alvo={feedback} fechar={() => setFeedback(null)} rpc={rpc} />}
    </section>
  );
}

function DarFeedback({ alvo, fechar, rpc }: { alvo: { id: string; tipo: keyof typeof FEEDBACK }; fechar: () => void; rpc: (fn: string, a: Record<string, unknown>) => Promise<boolean> }) {
  const [coment, setComent] = useState('');
  return (
    <Dialogo aberto fechar={fechar} titulo={`Feedback: ${FEEDBACK[alvo.tipo]}`} acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={async () => { if (await rpc('dar_feedback', { p_mensagem: alvo.id, p_feedback: alvo.tipo, p_comentario: coment || null })) fechar(); }}>Registrar</button></>}>
      <Campo rotulo="Comentário"><textarea rows={3} maxLength={1000} value={coment} onChange={(e) => setComent(e.target.value)} /></Campo>
      <p className="nota">O feedback aparece em destaque na conversa, entra no histórico e avisa o autor.</p>
    </Dialogo>
  );
}

function Anexos({ D, recarregar, setErro }: { D: Detalhe; recarregar: () => void; setErro: (e: string | null) => void }) {
  const [ocupado, setOcupado] = useState(false);
  const atuais = D.anexos.filter((a) => !D.anexos.some((x) => x.substitui_id === a.id));
  const enviar = async (f: File | undefined, substitui?: string) => {
    if (!f) return;
    setOcupado(true); setErro(null);
    try { await enviarArquivo(D.demanda.id, f, substitui); recarregar(); } catch (e) { setErro((e as Error).message); } finally { setOcupado(false); }
  };
  return (
    <section className="cartao">
      <h2 style={{ marginBottom: 8 }}>Anexos</h2>
      {!atuais.length && <EstadoVazio>Nenhum anexo.</EstadoVazio>}
      {atuais.map((a) => (
        <div key={a.id} style={{ borderTop: '1px solid var(--cor-divisor)', padding: '8px 0', fontSize: 13 }}>
          <button type="button" className="link-acao" style={{ background: 'none', border: 0, padding: 0, color: 'var(--cor-primaria)', cursor: 'pointer', textDecoration: 'underline', textAlign: 'left' }} onClick={() => baixarAnexo(a.path, a.nome).catch((e) => setErro(e.message))}>{a.nome}</button>
          {a.versao > 1 && <Selo tom="info">v{a.versao}</Selo>}
          <div className="texto-suave">{a.enviado_por} · {dataHora(a.enviado_em)}</div>
          {D.permissoes.anexar && <label className="link-acao" style={{ color: 'var(--cor-primaria)', cursor: 'pointer', fontSize: 12 }}>Enviar nova versão<input type="file" className="sr-only" accept=".pdf,.png,.jpg,.jpeg,.docx,.xlsx" disabled={ocupado} onChange={(e) => void enviar(e.target.files?.[0], a.id)} /></label>}
        </div>
      ))}
      {D.permissoes.anexar && (
        <label className="botao botao-tracejado" style={{ marginTop: 8, cursor: ocupado ? 'wait' : 'pointer' }}>
          {ocupado ? 'Enviando…' : 'Anexar arquivo'}
          <input type="file" className="sr-only" accept=".pdf,.png,.jpg,.jpeg,.docx,.xlsx" disabled={ocupado} onChange={(e) => { void enviar(e.target.files?.[0]); e.target.value = ''; }} />
        </label>
      )}
      <p className="nota" style={{ marginTop: 8 }}>PDF, imagens (JPG/PNG), DOCX e XLSX até 20 MB. Anexo nunca é apagado: substituir gera nova versão.</p>
    </section>
  );
}

function EditarDemanda({ D, fechar, aoSalvar }: { D: Detalhe; fechar: () => void; aoSalvar: () => void }) {
  const d = D.demanda;
  const [f, setF] = useState({ titulo: d.titulo, descricao: d.descricao ?? '', origem: d.origem, numero_processo: d.numero_processo ?? '', prioridade: d.prioridade, prazo: d.prazo ?? '' });
  const [erro, setErro] = useState<string | null>(null);
  const salvar = async () => {
    const mud: Record<string, string | null> = {};
    (Object.keys(f) as (keyof typeof f)[]).forEach((k) => { const antes = (d[k as keyof typeof d] ?? '') as string; if (f[k] !== antes) mud[k] = f[k] === '' ? null : f[k]; });
    if (!Object.keys(mud).length) { fechar(); return; }
    const { error } = await supabase.rpc('atualizar_demanda', { p_id: d.id, p_dados: mud });
    if (error) { setErro(mensagemErro(error)); return; }
    aoSalvar(); fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo={`Editar #${d.numero}`} acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={salvar}>Salvar</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        <Campo rotulo="Título"><input maxLength={200} value={f.titulo} onChange={(e) => setF({ ...f, titulo: e.target.value })} /></Campo>
        <Campo rotulo="Descrição"><textarea rows={3} maxLength={5000} value={f.descricao} onChange={(e) => setF({ ...f, descricao: e.target.value })} /></Campo>
        <div className="form-linha">
          <Campo rotulo="Origem"><select value={f.origem} onChange={(e) => setF({ ...f, origem: e.target.value as Origem })}>{(Object.keys(ROTULO_ORIGEM_LONGO) as Origem[]).map((o) => <option key={o} value={o}>{ROTULO_ORIGEM_LONGO[o]}</option>)}</select></Campo>
          <Campo rotulo="Urgência"><select value={f.prioridade} onChange={(e) => setF({ ...f, prioridade: e.target.value as Prioridade })}>{(Object.keys(ROTULO_PRIORIDADE) as Prioridade[]).map((p) => <option key={p} value={p}>{ROTULO_PRIORIDADE[p]}</option>)}</select></Campo>
        </div>
        <div className="form-linha">
          <Campo rotulo="Nº do processo"><input maxLength={60} value={f.numero_processo} onChange={(e) => setF({ ...f, numero_processo: e.target.value })} /></Campo>
          <Campo rotulo="Prazo"><input type="date" value={f.prazo} onChange={(e) => setF({ ...f, prazo: e.target.value })} /></Campo>
        </div>
        <p className="nota">Toda alteração fica no histórico com o antes e o depois.</p>
      </div>
    </Dialogo>
  );
}

function EditarResponsaveis({ D, fechar, aoSalvar }: { D: Detalhe; fechar: () => void; aoSalvar: () => void }) {
  const servidores = useConsulta(async () => supabase.from('servidores').select('id,nome_completo').eq('unidade_id', D.demanda.unidade_id).eq('situacao', 'ativo').order('nome_completo'), [D.demanda.unidade_id]);
  const [sel, setSel] = useState(D.responsaveis.filter((r) => r.papel === 'titular').map((r) => r.servidor_id));
  const [erro, setErro] = useState<string | null>(null);
  const salvar = async () => {
    const { error } = await supabase.rpc('definir_responsaveis', { p_id: D.demanda.id, p_servidores: sel });
    if (error) { setErro(mensagemErro(error)); return; }
    aoSalvar(); fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo="Responsáveis" acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={salvar}>Salvar</button></>}>
      {erro && <Aviso tom="critico">{erro}</Aviso>}
      {((servidores.dados as { id: string; nome_completo: string }[] | null) ?? []).map((s) => (
        <label key={s.id} style={{ display: 'flex', gap: 8, alignItems: 'center', minHeight: 36, fontSize: 14 }}>
          <input type="checkbox" checked={sel.includes(s.id)} onChange={(e) => setSel(e.target.checked ? [...sel, s.id] : sel.filter((x) => x !== s.id))} />{s.nome_completo}
        </label>
      ))}
      <p className="nota">Substitutos por férias entram e saem automaticamente. Quem entra é avisado.</p>
    </Dialogo>
  );
}

function PedirAtualizacao({ id, fechar, aoSalvar }: { id: string; fechar: () => void; aoSalvar: () => void }) {
  const [texto, setTexto] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const salvar = async () => {
    const { error } = await supabase.rpc('pedir_atualizacao', { p_demanda: id, p_texto: texto || null });
    if (error) { setErro(mensagemErro(error)); return; }
    aoSalvar(); fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo="Pedir atualização" acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={salvar}>Enviar pedido</button></>}>
      {erro && <Aviso tom="critico">{erro}</Aviso>}
      <Campo rotulo="Mensagem (opcional)" ajuda="Os responsáveis são avisados para relatar o andamento."><textarea rows={3} maxLength={4000} value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Por favor, relate o andamento desta demanda." /></Campo>
    </Dialogo>
  );
}
