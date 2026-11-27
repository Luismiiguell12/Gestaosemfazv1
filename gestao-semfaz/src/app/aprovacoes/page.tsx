'use client';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useMemo, useState } from 'react';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { Aviso, Campo, EstadoVazio, Selo } from '@/components/ui';
import { mensagemErro } from '@/lib/erros';
import { dataHora, quando } from '@/lib/formato';
import { ehGestorGeral, useSessao } from '@/lib/sessao';
import {
  formatarValor, ROTULO_CAMPO, ROTULO_STATUS, ROTULO_TIPO, ROTULO_TIPO_LONGO, TOM_STATUS, type Solicitacao,
} from '@/lib/solicitacoes';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';

type Aba = 'pendentes' | 'meus' | 'historico';

export default function AprovacoesPage() {
  return (
    <AppShell modulo="aprovacoes">
      <Suspense><Central /></Suspense>
    </AppShell>
  );
}

function Central() {
  const { info } = useSessao();
  const geral = ehGestorGeral(info);
  const params = useSearchParams();
  const router = useRouter();
  const [aba, setAba] = useState<Aba>('pendentes');
  const lista = useConsulta(async () => supabase.rpc('listar_solicitacoes', { p_aba: aba }), [aba]);
  const pendentes = useConsulta(async () => supabase.rpc('listar_solicitacoes', { p_aba: 'pendentes' }), [lista.dados]);
  const unidades = useConsulta(async () => supabase.from('unidades').select('id,sigla'), []);
  const cargos = useConsulta(async () => supabase.from('cargos').select('id,nome'), []);
  const servidores = useConsulta(async () => supabase.from('servidores').select('id,nome_completo'), []);
  const nomes = useMemo(() => ({
    servidores: new Map(((servidores.dados as { id: string; nome_completo: string }[] | null) ?? []).map((c) => [c.id, c.nome_completo])),
    unidades: new Map(((unidades.dados as { id: string; sigla: string }[] | null) ?? []).map((u) => [u.id, u.sigla])),
    cargos: new Map(((cargos.dados as { id: string; nome: string }[] | null) ?? []).map((c) => [c.id, c.nome])),
  }), [unidades.dados, cargos.dados, servidores.dados]);

  const itens = (lista.dados as Solicitacao[] | null) ?? [];
  const selecionadoId = params.get('id') ?? itens[0]?.id;
  const sel = itens.find((s) => s.id === selecionadoId) ?? itens[0];
  const nPend = ((pendentes.dados as Solicitacao[] | null) ?? []).length;

  const abas: { id: Aba; l: string }[] = [
    { id: 'pendentes', l: `Pendentes (${nPend})` }, { id: 'meus', l: 'Meus pedidos' }, { id: 'historico', l: 'Histórico' },
  ];

  return (
    <>
      <Cabecalho trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Aprovações' }]} titulo="Central de aprovações" />
      <div role="tablist" aria-label="Filtro" className="abas">
        {abas.map((t) => (
          <button key={t.id} type="button" role="tab" className="aba" aria-selected={aba === t.id} onClick={() => { setAba(t.id); router.replace('/aprovacoes'); }}>{t.l}</button>
        ))}
      </div>
      {lista.erro && <Aviso tom="critico">{lista.erro}</Aviso>}
      <div className="linha">
        <section aria-label="Pedidos" style={{ flex: '1 1 340px', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 10 }}>
          {!lista.carregando && itens.length === 0 && <div className="cartao"><EstadoVazio>Nenhum pedido aqui.</EstadoVazio></div>}
          {itens.map((r) => (
            <button key={r.id} type="button" className="pedido" aria-current={sel?.id === r.id} onClick={() => router.replace(`/aprovacoes?id=${r.id}`)}>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}><strong style={{ fontSize: 14 }}>{r.resumo}</strong><span className="texto-suave" style={{ whiteSpace: 'nowrap', fontSize: 13 }}>{quando(r.criado_em)}</span></div>
              <div className="texto-suave" style={{ marginTop: 2, fontSize: 13 }}>{ROTULO_TIPO[r.tipo]} · pedido por {r.solicitante_nome}{r.status !== 'pendente' && <> · <Selo tom={TOM_STATUS[r.status]}>{ROTULO_STATUS[r.status]}</Selo></>}</div>
            </button>
          ))}
        </section>
        {sel && <Detalhe s={sel} nomes={nomes} podeDecidir={geral && sel.status === 'pendente' && sel.solicitante_id !== info?.usuario_id} meu={sel.solicitante_id === info?.usuario_id} aoMudar={() => void lista.recarregar()} />}
      </div>
      <p className="nota">Registrar pagamentos não passa por aprovação; alterar dados já cadastrados e mexer na estrutura passam.</p>
    </>
  );
}

function Detalhe({ s, nomes, podeDecidir, meu, aoMudar }: {
  s: Solicitacao; nomes: Parameters<typeof formatarValor>[2]; podeDecidir: boolean; meu: boolean; aoMudar: () => void;
}) {
  const [comentario, setComentario] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);
  const campos = Array.from(new Set([...Object.keys(s.dados_antes ?? {}), ...Object.keys(s.dados_depois ?? {})]));
  const criacao = s.tipo === 'unidade_criar' || s.tipo === 'cargo_criar';

  const decidir = async (aprovar: boolean) => {
    setErro(null); setOk(null);
    if (!aprovar && comentario.trim().length === 0) { setErro('Informe o comentário para recusar.'); return; }
    setEnviando(true);
    const { data, error } = await supabase.rpc('decidir_solicitacao', { p_id: s.id, p_aprovar: aprovar, p_comentario: comentario.trim() || null });
    setEnviando(false);
    if (error) { setErro(mensagemErro(error)); return; }
    setOk(data === 'bloqueada' ? 'O registro mudou depois do pedido: pedido bloqueado. O solicitante precisa refazê-lo.' : aprovar ? 'Alteração aprovada e aplicada.' : 'Pedido recusado.');
    setComentario('');
    aoMudar();
  };
  const cancelar = async () => {
    const { error } = await supabase.rpc('cancelar_solicitacao', { p_id: s.id });
    if (error) setErro(mensagemErro(error)); else aoMudar();
  };
  const abrirAnexo = async () => {
    if (!s.anexo_path) return;
    const { data, error } = await supabase.storage.from('anexos').createSignedUrl(s.anexo_path, 60);
    if (error || !data) { setErro('Não foi possível abrir o anexo.'); return; }
    window.open(data.signedUrl, '_blank', 'noopener,noreferrer');
  };

  return (
    <section className="cartao" style={{ flex: '999 1 560px', minWidth: 0, padding: '20px 22px', display: 'flex', flexDirection: 'column', gap: 16 }}>
      <div>
        <div className="texto-suave">{ROTULO_TIPO_LONGO[s.tipo]} · pedido em {dataHora(s.criado_em).replace(', ', ' às ')}</div>
        <h2 style={{ margin: '4px 0 0', fontSize: 20 }}>{s.resumo}</h2>
        <div style={{ fontSize: 13, marginTop: 4 }}>Solicitante: <strong>{s.solicitante_nome}</strong> · <Selo tom={TOM_STATUS[s.status]}>{ROTULO_STATUS[s.status]}</Selo></div>
      </div>
      {campos.length > 0 && (
        <div className="tabela-rolagem" style={{ marginTop: 0 }}>
          <table className="tabela tabela-cartoes" style={{ fontSize: 14 }}>
            <thead><tr><th>Campo</th><th>Como está</th><th>Como fica</th></tr></thead>
            <tbody>
              {campos.map((k) => (
                <tr key={k}>
                  <td data-rotulo="Campo" style={{ padding: '10px 6px' }}>{ROTULO_CAMPO[k] ?? k}</td>
                  <td data-rotulo="Como está" style={{ padding: '10px 6px' }}>{criacao || !(k in (s.dados_antes ?? {})) ? '—' : <span className="diff-antes">{formatarValor(k, s.dados_antes[k], nomes)}</span>}</td>
                  <td data-rotulo="Como fica" style={{ padding: '10px 6px' }}>{s.tipo === 'feriado_excluir' ? <span className="diff-antes">excluído</span> : <span className="diff-depois">{formatarValor(k, s.dados_depois[k], nomes)}</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <div className="caixa-cinza"><strong>Justificativa do solicitante</strong><br />{s.justificativa}</div>
      {s.anexo_path && <div style={{ fontSize: 13 }}><button type="button" className="link-acao" style={{ background: 'none', border: 0, padding: 0, color: 'var(--cor-primaria)', textDecoration: 'underline', cursor: 'pointer' }} onClick={abrirAnexo}>Abrir anexo ({s.anexo_path.split('.').pop()?.toUpperCase()})</button></div>}
      {s.status !== 'pendente' && (
        <div className="caixa-cinza"><strong>Decisão</strong><br />{ROTULO_STATUS[s.status]}{s.decidido_por_nome ? ` por ${s.decidido_por_nome}` : ''}{s.decidido_em ? ` em ${dataHora(s.decidido_em)}` : ''}{s.comentario_decisao ? <><br />{s.comentario_decisao}</> : null}</div>
      )}
      {erro && <Aviso tom="critico">{erro}</Aviso>}
      {ok && <Aviso tom="sucesso">{ok}</Aviso>}
      {podeDecidir && (
        <>
          <Campo rotulo="Comentário (obrigatório se recusar)"><textarea rows={3} maxLength={2000} value={comentario} onChange={(e) => setComentario(e.target.value)} /></Campo>
          <div className="dialogo-acoes">
            <button type="button" className="botao botao-critico" disabled={enviando} onClick={() => decidir(false)}>Recusar</button>
            <button type="button" className="botao botao-positivo" disabled={enviando} onClick={() => decidir(true)}>Aprovar alteração</button>
          </div>
        </>
      )}
      {meu && s.status === 'pendente' && <div className="dialogo-acoes"><button type="button" className="botao" onClick={cancelar}>Cancelar pedido</button></div>}
      <p className="nota">Basta a aprovação da Secretária ou do Administrador do sistema. Ninguém aprova o próprio pedido. Se o registro mudar antes da decisão, o pedido é bloqueado e precisa ser refeito.</p>
    </section>
  );
}
