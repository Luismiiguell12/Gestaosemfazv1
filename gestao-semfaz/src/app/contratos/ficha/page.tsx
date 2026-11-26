'use client';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { Suspense, useState } from 'react';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { SolicitarDialogo, type CampoForm } from '@/components/SolicitarDialogo';
import { Aviso, Campo, Dialogo, EstadoVazio, Selo } from '@/components/ui';
import { ehGestorGeral, useSessao } from '@/lib/sessao';
import { COR_FORNECEDOR, lerValor, ROTULO_FORNECEDOR, ROTULO_NUMERO_UC, seloVigencia, SITUACAO, UNIDADE_CONSUMO, type Fornecedor, type SituacaoPagamento } from '@/lib/contratos';
import { ehPdf } from '@/lib/folhas';
import { mensagemErro } from '@/lib/erros';
import { competencia, dataCurta, dataHora, moeda } from '@/lib/formato';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';

interface Ficha {
  contrato: { id: string; numero: string; processo: string | null; imovel_descricao: string; imovel_endereco: string | null; unidade_ocupante_id: string | null; unidade: string | null;
    inicio: string; fim_original: string; fim_vigencia: string; valor_mensal: number; valor_anual: number; dia_vencimento: number; fiscal_servidor_id: string | null; fiscal: string | null;
    indice_reajuste: string | null; mes_database: number | null; encerrado: boolean; dias_restantes: number };
  locador: { id: string; tipo: 'PF' | 'PJ'; nome: string; documento: string; email: string | null; telefone: string | null; mascarado: boolean; pode_ver_completo: boolean };
  aditivos: { id: string; numero: number; altera_prazo: boolean; altera_valor: boolean; novo_fim: string | null; novo_valor: number | null; data_assinatura: string | null; descricao: string | null }[];
  alugueis: { id: string; competencia: string; valor: number; vencimento: string; pago_em: string | null; valor_pago: number | null; situacao: SituacaoPagamento }[];
  ucs: { id: string; fornecedor: Fornecedor; numero: string; descricao: string | null; ultima: { competencia: string; valor: number; pago_em: string | null; vencimento: string } | null }[];
  documentos: { id: string; nome: string; path: string; tamanho: number; aditivo_id: string | null; enviado_em: string; enviado_por: string }[];
  historico: { em: string; acao: string; detalhes: Record<string, unknown>; ator: string | null }[];
  renovacao: { demanda_id: string; numero: number; status: string } | null;
  pendentes: number;
}

const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
const ordinal = (n: number) => `${n}º`;

function textoHistorico(h: Ficha['historico'][number]) {
  const d = h.detalhes as Record<string, string | number>;
  switch (h.acao) {
    case 'cadastrado': return 'Contrato cadastrado';
    case 'importado': return 'Contrato importado por planilha';
    case 'pagamento': return `Pagamento de ${d.competencia} registrado (${moeda(d.valor)})`;
    case 'pagamento_desfeito': return `Pagamento de ${d.competencia} desfeito: ${d.motivo}`;
    case 'documento': return `PDF anexado: ${d.nome}`;
    case 'uc_vinculada': return `Unidade consumidora vinculada: ${ROTULO_FORNECEDOR[d.fornecedor as Fornecedor] ?? d.fornecedor} ${d.numero}`;
    case 'pedido_aprovacao': return `Pedido enviado para aprovação: ${d.resumo}`;
    case 'alterado': return `Alteração aprovada: ${d.resumo}`;
    case 'aditivo': return `${ordinal(Number(d.numero))} aditivo aprovado`;
    case 'renovacao_criada': return 'Demanda de renovação criada automaticamente';
    default: return h.acao;
  }
}

export default function FichaContratoPage() {
  return <AppShell modulo="contratos"><Suspense><FichaContrato /></Suspense></AppShell>;
}

function FichaContrato() {
  const id = useSearchParams().get('id') ?? '';
  const { info } = useSessao();
  const [versao, setVersao] = useState(0);
  const recarregar = () => setVersao((v) => v + 1);
  const r = useConsulta(async () => supabase.rpc('contrato_ficha', { p_id: id }), [id, versao]);
  const F = r.dados as Ficha | null;
  const [dialogo, setDialogo] = useState<null | 'alterar' | 'aditivo' | 'pagar' | 'uc' | 'locador'>(null);
  const [erro, setErro] = useState<string | null>(null);

  if (r.carregando && !F) return <div className="carregando">Carregando…</div>;
  if (!F) return <><Cabecalho trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Contratos de locação', href: '/contratos' }]} titulo="Contrato não encontrado" /><p className="nota">Ele não existe ou você não tem acesso.</p></>;

  const c = F.contrato;
  const vig = seloVigencia(c.dias_restantes, c.encerrado);
  const ano = String(new Date().getFullYear());
  const pagoAno = F.alugueis.filter((a) => a.pago_em && a.competencia.startsWith(ano)).reduce((s, a) => s + Number(a.valor_pago ?? a.valor), 0);
  const pendente = F.alugueis.filter((a) => !a.pago_em && a.situacao === 'atrasado').reduce((s, a) => s + Number(a.valor), 0);
  const abertos = F.alugueis.filter((a) => !a.pago_em);
  // aluguéis do mais recente para o mais antigo, sem meses muito à frente
  const limite = new Date(); limite.setMonth(limite.getMonth() + 2);
  const visiveis = [...F.alugueis].filter((a) => a.competencia <= limite.toISOString().slice(0, 10)).reverse();

  const fatos: [string, React.ReactNode][] = [
    ['Locador', <>{F.locador.nome} ({F.locador.tipo}){' '}<button type="button" className="botao-link" onClick={() => setDialogo('locador')}>dados</button></>],
    ['Processo', c.processo ?? '—'],
    ['Imóvel', c.imovel_endereco ? `${c.imovel_descricao} · ${c.imovel_endereco}` : c.imovel_descricao],
    ['Unidade ocupante', c.unidade ?? '—'],
    ['Valor mensal atual', moeda(c.valor_mensal)],
    ['Valor anual', moeda(c.valor_anual)],
    ['Fiscal do contrato', c.fiscal ?? '—'],
    ['Índice de reajuste', [c.indice_reajuste, c.mes_database ? `data-base ${MESES[c.mes_database - 1]}` : null].filter(Boolean).join(' · ') || '—'],
  ];

  // linha de vigência: original + cada aditivo de prazo (proporcional à duração)
  const trechos: { rotulo: string; ini: string; fim: string }[] = [{ rotulo: `Contrato original · ${dataCurta(c.inicio)} a ${dataCurta(c.fim_original)}`, ini: c.inicio, fim: c.fim_original }];
  let fimAnt = c.fim_original;
  for (const a of F.aditivos.filter((x) => x.altera_prazo && x.novo_fim)) {
    trechos.push({ rotulo: `${ordinal(a.numero)} aditivo (${a.altera_valor ? 'prazo e valor' : 'prazo'}) · até ${dataCurta(a.novo_fim)}`, ini: fimAnt, fim: a.novo_fim! });
    fimAnt = a.novo_fim!;
  }
  const dur = (t: { ini: string; fim: string }) => Math.max(1, (Date.parse(t.fim) - Date.parse(t.ini)) / 86400000);

  const camposAlterar: CampoForm[] = [
    { chave: 'numero', rotulo: 'Número do contrato', inicial: c.numero, max: 30 },
    { chave: 'processo', rotulo: 'Processo', inicial: c.processo ?? '', max: 60 },
    { chave: 'imovel_descricao', rotulo: 'Imóvel', inicial: c.imovel_descricao },
    { chave: 'imovel_endereco', rotulo: 'Endereço', inicial: c.imovel_endereco ?? '', max: 300 },
    { chave: 'valor_mensal', rotulo: 'Valor mensal (use ponto para centavos: 2500.00)', inicial: String(c.valor_mensal), tipo: 'numero', max: 15 },
    { chave: 'dia_vencimento', rotulo: 'Dia de vencimento (1 a 28)', inicial: String(c.dia_vencimento), tipo: 'numero', max: 2 },
    { chave: 'indice_reajuste', rotulo: 'Índice de reajuste', inicial: c.indice_reajuste ?? '', max: 40 },
    { chave: 'mes_database', rotulo: 'Mês da data-base', inicial: c.mes_database ? String(c.mes_database) : '', tipo: 'select', opcoes: MESES.map((m, i) => ({ valor: String(i + 1), rotulo: m })) },
    { chave: 'encerrado', rotulo: 'Situação', inicial: String(c.encerrado), tipo: 'select', opcoes: [{ valor: 'false', rotulo: 'Ativo' }, { valor: 'true', rotulo: 'Encerrado' }] },
  ];
  const camposAditivo: CampoForm[] = [
    { chave: 'novo_fim', rotulo: 'Nova vigência até (aditivo de prazo)', tipo: 'data' },
    { chave: 'novo_valor', rotulo: 'Novo valor mensal (aditivo de valor; use ponto: 2750.00)', tipo: 'numero', max: 15 },
    { chave: 'data_assinatura', rotulo: 'Data de assinatura', tipo: 'data' },
    { chave: 'descricao', rotulo: 'Descrição', max: 2000 },
  ];

  return (
    <>
      <Cabecalho
        trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Contratos de locação', href: '/contratos' }, { rotulo: c.numero }]}
        titulo={`Contrato ${c.numero} · ${c.imovel_descricao}`}
        subtitulo={<span className="acoes" style={{ gap: 8, marginTop: 6 }}>
          <Selo tom={c.encerrado ? 'neutro' : c.dias_restantes < 0 ? 'critico' : 'positivo'}>{c.encerrado ? 'Encerrado' : c.dias_restantes < 0 ? 'Vencido' : 'Vigente'}</Selo>
          {!c.encerrado && c.dias_restantes >= 0 && vig.tom !== 'positivo' && <Selo tom={vig.tom}>{vig.texto} ({dataCurta(c.fim_vigencia)})</Selo>}
          {F.aditivos.length > 0 && <Selo tom="info">{F.aditivos.length} aditivo(s)</Selo>}
          {F.pendentes > 0 && <Selo tom="alerta">Pedido aguardando aprovação</Selo>}
        </span>}
        acoes={<>
          <button type="button" className="botao" onClick={() => setDialogo('alterar')}>Solicitar alteração</button>
          <button type="button" className="botao" onClick={() => setDialogo('aditivo')}>Registrar aditivo</button>
          <button type="button" className="botao botao-primario" disabled={!abertos.length} onClick={() => setDialogo('pagar')}>Registrar pagamento</button>
        </>}
      />
      {erro && <Aviso tom="critico">{erro}</Aviso>}
      {F.renovacao && <Aviso tom="info">Renovação em andamento: <Link href={`/demandas/ficha?id=${F.renovacao.demanda_id}`}>demanda #{F.renovacao.numero}</Link>.</Aviso>}

      <section aria-label="Resumo do contrato" className="cartao" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(190px, 1fr))', gap: '16px 20px' }}>
        {fatos.map(([k, v]) => <div key={k}><div className="texto-suave">{k}</div><div style={{ fontSize: 15, fontWeight: 600, marginTop: 2 }}>{v}</div></div>)}
      </section>

      <section className="cartao">
        <h2 style={{ marginBottom: 12 }}>Vigência e aditivos</h2>
        <div style={{ display: 'flex', minHeight: 30, borderRadius: 8, overflow: 'hidden', fontSize: 12, color: '#fff', fontWeight: 600 }}>
          {trechos.map((t, i) => <div key={i} style={{ flex: dur(t), background: i === 0 ? 'var(--cor-texto-forte)' : 'var(--cor-primaria)', display: 'flex', alignItems: 'center', padding: '4px 10px', minWidth: 0 }}>{t.rotulo}</div>)}
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, color: 'var(--cor-texto-suave)', marginTop: 6 }}>
          <span>{competencia(c.inicio)}</span><span>hoje: {dataCurta(new Date().toISOString().slice(0, 10))}</span><span>{competencia(c.fim_vigencia)}</span>
        </div>
        {F.aditivos.filter((a) => !a.altera_prazo).map((a) => <p key={a.id} className="texto-suave" style={{ margin: '8px 0 0' }}>{ordinal(a.numero)} aditivo (valor): {moeda(a.novo_valor)}{a.data_assinatura ? ` · assinado em ${dataCurta(a.data_assinatura)}` : ''}</p>)}
      </section>

      <div className="linha">
        <section className="cartao col-principal">
          <div className="cartao-topo" style={{ flexWrap: 'wrap', gap: 8 }}>
            <h2>Aluguéis mês a mês</h2>
            <span className="texto-suave" style={{ fontSize: 13 }}>Pago no ano: <strong style={{ color: 'var(--cor-positivo)' }}>{moeda(pagoAno)}</strong> · Vencido: <strong style={{ color: 'var(--selo-alerta-fg)' }}>{moeda(pendente)}</strong></span>
          </div>
          <div className="tabela-rolagem" style={{ maxHeight: 520, overflowY: 'auto' }}>
            <table className="tabela tabela-cartoes">
              <thead><tr><th>Competência</th><th>Valor</th><th>Vencimento</th><th>Pagamento</th><th>Situação</th>{ehGestorGeral(info) && <th><span className="sr-only">Ações</span></th>}</tr></thead>
              <tbody>
                {visiveis.map((a) => (
                  <tr key={a.id}>
                    <td data-rotulo="Competência">{competencia(a.competencia)}</td>
                    <td data-rotulo="Valor">{moeda(a.valor)}</td>
                    <td data-rotulo="Vencimento">{dataCurta(a.vencimento)}</td>
                    <td data-rotulo="Pagamento">{a.pago_em ? `${dataCurta(a.pago_em)}${Number(a.valor_pago) !== Number(a.valor) ? ` · ${moeda(a.valor_pago)}` : ''}` : '—'}</td>
                    <td data-rotulo="Situação"><Selo tom={SITUACAO[a.situacao].tom}>{SITUACAO[a.situacao].r}</Selo></td>
                    {ehGestorGeral(info) && <td>{a.pago_em && <DesfazerPagamento id={a.id} rotulo={competencia(a.competencia)} aoSalvar={recarregar} setErro={setErro} />}</td>}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
        <aside className="col-lateral" style={{ gap: 20 }}>
          <section className="cartao">
            <div className="cartao-topo"><h2>Unidades consumidoras</h2><button type="button" className="botao-link" onClick={() => setDialogo('uc')}>Vincular</button></div>
            {!F.ucs.length && <EstadoVazio>Nenhuma vinculada.</EstadoVazio>}
            {F.ucs.map((u) => {
              const s: SituacaoPagamento | null = !u.ultima ? null : u.ultima.pago_em ? 'paga' : u.ultima.vencimento < new Date().toISOString().slice(0, 10) ? 'atrasada' : 'pendente';
              return (
                <div key={u.id} style={{ borderTop: '1px solid var(--cor-divisor)', padding: '10px 0', marginTop: 8, fontSize: 13 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}>
                    <strong><span aria-hidden="true" style={{ display: 'inline-block', width: 8, height: 8, borderRadius: '50%', background: COR_FORNECEDOR[u.fornecedor], marginRight: 6 }} />{ROTULO_FORNECEDOR[u.fornecedor]} · {ROTULO_NUMERO_UC[u.fornecedor]} {u.numero}</strong>
                    {s && <Selo tom={s === 'paga' ? 'positivo' : SITUACAO[s].tom}>{s === 'paga' ? 'Em dia' : SITUACAO[s].r}</Selo>}
                  </div>
                  <div className="texto-suave" style={{ marginTop: 2 }}>{u.ultima ? `${competencia(u.ultima.competencia)} · ${moeda(u.ultima.valor)} · ${u.ultima.pago_em ? 'paga' : `vence ${dataCurta(u.ultima.vencimento)}`}` : 'Sem fatura lançada'}</div>
                </div>
              );
            })}
            <p className="nota" style={{ marginTop: 8 }}><Link href="/unidades-consumidoras">Ver faturas</Link></p>
          </section>
          <Documentos F={F} recarregar={recarregar} setErro={setErro} />
          <section className="cartao">
            <h2 style={{ marginBottom: 8 }}>Histórico</h2>
            <div style={{ fontSize: 13, lineHeight: 1.6, color: 'var(--cor-texto-2)', maxHeight: 360, overflowY: 'auto' }}>
              {F.historico.map((h, i) => <div key={i} style={{ borderTop: i ? '1px solid var(--cor-divisor)' : 0, padding: '6px 0' }}><span className="texto-suave">{dataHora(h.em)}{h.ator ? ` · ${h.ator}` : ' · Sistema'}</span><br />{textoHistorico(h)}</div>)}
            </div>
          </section>
        </aside>
      </div>
      <p className="nota">Registrar pagamento não precisa de aprovação. Alterar dados do contrato e aditivos passam pela Secretária ou pelo Administrador do sistema. CPF e contato do locador ficam mascarados; a exibição completa exige permissão específica e fica registrada na auditoria.</p>

      <SolicitarDialogo aberto={dialogo === 'alterar'} fechar={() => setDialogo(null)} titulo={`Solicitar alteração · contrato ${c.numero}`} tipo="contrato_alterar" alvoId={c.id}
        campos={camposAlterar} aviso="Altere só o que precisa mudar. Novo valor e dia de vencimento valem para os aluguéis ainda não pagos a partir deste mês. Prazo de vigência muda por aditivo." aoEnviar={recarregar} />
      <SolicitarDialogo aberto={dialogo === 'aditivo'} fechar={() => setDialogo(null)} titulo={`Registrar aditivo · contrato ${c.numero}`} tipo="contrato_aditivo" alvoId={c.id}
        campos={camposAditivo} aviso="Informe a nova vigência, o novo valor ou os dois. Depois de aprovado, anexe o PDF do aditivo na seção Documentos." aoEnviar={recarregar} />
      {dialogo === 'pagar' && <RegistrarPagamento abertos={abertos} fechar={() => setDialogo(null)} aoSalvar={recarregar} />}
      {dialogo === 'uc' && <VincularUc contrato={c.id} fechar={() => setDialogo(null)} aoSalvar={recarregar} />}
      {dialogo === 'locador' && <DadosLocador locador={F.locador} fechar={() => setDialogo(null)} />}
    </>
  );
}

function RegistrarPagamento({ abertos, fechar, aoSalvar }: { abertos: Ficha['alugueis']; fechar: () => void; aoSalvar: () => void }) {
  const hoje = new Date().toISOString().slice(0, 10);
  const padrao = abertos.find((a) => a.situacao === 'atrasado') ?? abertos[0];
  const [id, setId] = useState(padrao?.id ?? '');
  const sel = abertos.find((a) => a.id === id);
  const [data, setData] = useState(hoje);
  const [valor, setValor] = useState(sel ? String(sel.valor).replace('.', ',') : '');
  const [erro, setErro] = useState<string | null>(null);
  const salvar = async () => {
    const v = lerValor(valor);
    if (!v) return setErro('Valor inválido.');
    if (!data || data > hoje) return setErro('Data de pagamento inválida.');
    const { error } = await supabase.rpc('registrar_pagamento_aluguel', { p_id: id, p_data: data, p_valor: v });
    if (error) return setErro(mensagemErro(error));
    aoSalvar(); fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo="Registrar pagamento de aluguel" acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={salvar}>Registrar</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        <Campo rotulo="Competência">
          <select value={id} onChange={(e) => { setId(e.target.value); const a = abertos.find((x) => x.id === e.target.value); if (a) setValor(String(a.valor).replace('.', ',')); }}>
            {abertos.map((a) => <option key={a.id} value={a.id}>{competencia(a.competencia)} · vence {dataCurta(a.vencimento)}{a.situacao === 'atrasado' ? ' · vencido' : ''}</option>)}
          </select>
        </Campo>
        <div className="form-linha">
          <Campo rotulo="Data do pagamento"><input type="date" max={hoje} value={data} onChange={(e) => setData(e.target.value)} /></Campo>
          <Campo rotulo="Valor pago (R$)"><input inputMode="decimal" maxLength={15} value={valor} onChange={(e) => setValor(e.target.value)} /></Campo>
        </div>
      </div>
    </Dialogo>
  );
}

function DesfazerPagamento({ id, rotulo, aoSalvar, setErro }: { id: string; rotulo: string; aoSalvar: () => void; setErro: (e: string | null) => void }) {
  const [aberto, setAberto] = useState(false);
  const [motivo, setMotivo] = useState('');
  const salvar = async () => {
    const { error } = await supabase.rpc('desfazer_pagamento_aluguel', { p_id: id, p_motivo: motivo });
    setAberto(false);
    if (error) return setErro(mensagemErro(error));
    aoSalvar();
  };
  return (
    <>
      <button type="button" className="botao-link" onClick={() => setAberto(true)}>Desfazer</button>
      <Dialogo aberto={aberto} fechar={() => setAberto(false)} titulo={`Desfazer pagamento de ${rotulo}`} acoes={<><button type="button" className="botao" onClick={() => setAberto(false)}>Cancelar</button><button type="button" className="botao botao-critico" disabled={motivo.trim().length < 5} onClick={salvar}>Desfazer</button></>}>
        <Campo rotulo="Motivo" ajuda="Fica registrado no histórico do contrato."><textarea rows={3} maxLength={500} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></Campo>
      </Dialogo>
    </>
  );
}

function VincularUc({ contrato, fechar, aoSalvar }: { contrato: string; fechar: () => void; aoSalvar: () => void }) {
  const [forn, setForn] = useState<Fornecedor>('energisa');
  const [numero, setNumero] = useState('');
  const [desc, setDesc] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const salvar = async () => {
    if (!/^[0-9A-Za-z./-]{3,30}$/.test(numero.trim())) return setErro('Número inválido (3 a 30 caracteres: números, letras, ponto, barra ou hífen).');
    const { error } = await supabase.rpc('criar_uc', { p_fornecedor: forn, p_numero: numero.trim(), p_contrato: contrato, p_descricao: desc || null });
    if (error) return setErro(mensagemErro(error));
    aoSalvar(); fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo="Vincular unidade consumidora" acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={salvar}>Vincular</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        <Campo rotulo="Fornecedor"><select value={forn} onChange={(e) => setForn(e.target.value as Fornecedor)}>{(Object.keys(ROTULO_FORNECEDOR) as Fornecedor[]).map((f) => <option key={f} value={f}>{ROTULO_FORNECEDOR[f]} ({f === 'igua' ? 'água' : 'energia'})</option>)}</select></Campo>
        <Campo rotulo={`${ROTULO_NUMERO_UC[forn]} (${UNIDADE_CONSUMO[forn]})`}><input maxLength={30} value={numero} onChange={(e) => setNumero(e.target.value)} /></Campo>
        <Campo rotulo="Descrição (opcional)"><input maxLength={120} value={desc} onChange={(e) => setDesc(e.target.value)} placeholder="Ex.: medidor do térreo" /></Campo>
      </div>
    </Dialogo>
  );
}

function DadosLocador({ locador, fechar }: { locador: Ficha['locador']; fechar: () => void }) {
  const [dados, setDados] = useState(locador);
  const [erro, setErro] = useState<string | null>(null);
  const verCompleto = async () => {
    const { data, error } = await supabase.rpc('locador_dados', { p_locador: locador.id, p_completo: true });
    if (error) return setErro(mensagemErro(error));
    setDados(data as Ficha['locador']);
  };
  return (
    <Dialogo aberto fechar={fechar} titulo={`Locador · ${dados.nome}`} acoes={<>
      {dados.mascarado && dados.pode_ver_completo && <button type="button" className="botao" onClick={verCompleto}>Exibir dados completos</button>}
      <button type="button" className="botao botao-primario" onClick={fechar}>Fechar</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        {[['Tipo', dados.tipo === 'PF' ? 'Pessoa física' : 'Pessoa jurídica'], [dados.tipo === 'PF' ? 'CPF' : 'CNPJ', dados.documento], ['E-mail', dados.email ?? '—'], ['Telefone', dados.telefone ?? '—']].map(([k, v]) =>
          <div key={k}><div className="texto-suave">{k}</div><div style={{ fontSize: 15, fontWeight: 600 }}>{v}</div></div>)}
        {dados.mascarado && <p className="nota">{dados.pode_ver_completo ? 'Dados mascarados (LGPD). Exibir os dados completos fica registrado na auditoria.' : 'Dados mascarados (LGPD). A exibição completa exige permissão específica, concedida pela Secretária ou pelo Administrador.'}</p>}
        <p className="nota">Corrigir dados do locador: registre um pedido de alteração do contrato com a justificativa (cadastro do locador ainda sem tela própria).</p>
      </div>
    </Dialogo>
  );
}

function Documentos({ F, recarregar, setErro }: { F: Ficha; recarregar: () => void; setErro: (e: string | null) => void }) {
  const [enviando, setEnviando] = useState(false);
  const [aditivo, setAditivo] = useState('');
  const enviar = async (arq: File | undefined) => {
    if (!arq) return;
    setErro(null);
    if (arq.size > 30 * 1024 * 1024) return setErro('PDF maior que 30 MB.');
    if (!ehPdf(new Uint8Array(await arq.slice(0, 8).arrayBuffer()))) return setErro('Envie um arquivo PDF.');
    setEnviando(true);
    const path = `contratos/${F.contrato.id}/${crypto.randomUUID()}.pdf`;
    const up = await supabase.storage.from('contratos').upload(path, arq, { contentType: 'application/pdf', upsert: false });
    if (up.error) { setEnviando(false); return setErro('Não foi possível enviar o PDF.'); }
    const { error } = await supabase.rpc('registrar_documento_contrato', { p_contrato: F.contrato.id, p_path: path, p_nome: arq.name, p_tamanho: arq.size, p_aditivo: aditivo || null });
    setEnviando(false);
    if (error) return setErro(mensagemErro(error));
    recarregar();
  };
  const baixar = async (path: string, nome: string) => {
    const { data, error } = await supabase.storage.from('contratos').download(path);
    if (error || !data) return setErro('Não foi possível baixar o PDF.');
    const a = document.createElement('a'); a.href = URL.createObjectURL(data); a.download = nome; a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 10000);
  };
  return (
    <section className="cartao">
      <h2 style={{ marginBottom: 8 }}>Documentos</h2>
      <div style={{ fontSize: 13, lineHeight: 2 }}>
        {!F.documentos.length && <EstadoVazio>Nenhum PDF anexado.</EstadoVazio>}
        {F.documentos.map((d) => {
          const ad = F.aditivos.find((a) => a.id === d.aditivo_id);
          return <div key={d.id}><button type="button" className="botao-link" onClick={() => void baixar(d.path, d.nome)}>{d.nome}</button>{ad && <span className="texto-suave"> · {ordinal(ad.numero)} aditivo</span>}</div>;
        })}
      </div>
      {F.aditivos.length > 0 && (
        <label className="campo campo-leve" style={{ marginTop: 8 }}>Refere-se a
          <select value={aditivo} onChange={(e) => setAditivo(e.target.value)}><option value="">Contrato</option>{F.aditivos.map((a) => <option key={a.id} value={a.id}>{ordinal(a.numero)} aditivo</option>)}</select>
        </label>
      )}
      <label className="botao botao-tracejado botao-bloco" style={{ marginTop: 8 }}>
        {enviando ? 'Enviando…' : 'Anexar PDF do contrato ou aditivo'}
        <input type="file" accept="application/pdf" className="sr-only" disabled={enviando} onChange={(e) => { void enviar(e.target.files?.[0]); e.target.value = ''; }} />
      </label>
    </section>
  );
}
