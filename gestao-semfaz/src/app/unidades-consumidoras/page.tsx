'use client';
import Link from 'next/link';
import { Suspense, useMemo, useState } from 'react';
import { ImportarPlanilha } from '@/components/ImportarPlanilha';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { Aviso, Campo, Dialogo, EstadoVazio, Selo } from '@/components/ui';
import { COR_FORNECEDOR, lerValor, ROTULO_FORNECEDOR, ROTULO_NUMERO_UC, SITUACAO, UNIDADE_CONSUMO, type Fornecedor, type SituacaoPagamento } from '@/lib/contratos';
import { mensagemErro } from '@/lib/erros';
import { dataCurta, moeda } from '@/lib/formato';
import { COLUNAS_FATURAS, modeloCsv } from '@/lib/planilha';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';

interface LinhaUc {
  uc_id: string; fornecedor: Fornecedor; numero: string; descricao: string | null; contrato_id: string; contrato_numero: string; imovel: string;
  fatura_id: string | null; consumo: number | null; valor: number | null; vencimento: string | null; pago_em: string | null; situacao: SituacaoPagamento;
}

const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
const isoMes = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;

export default function UcsPage() {
  return <AppShell modulo="unidades_consumidoras"><Suspense><Ucs /></Suspense></AppShell>;
}

function Ucs() {
  // competências: mês atual + 12 anteriores; padrão = mês anterior (a fatura chega depois)
  const opcoes = useMemo(() => {
    const h = new Date(); h.setDate(1);
    return Array.from({ length: 13 }, (_, i) => { const d = new Date(h); d.setMonth(h.getMonth() - i); return isoMes(d); });
  }, []);
  const [comp, setComp] = useState(opcoes[1]);
  const [aba, setAba] = useState<Fornecedor | 'todos'>('todos');
  const [versao, setVersao] = useState(0);
  const [importar, setImportar] = useState(false);
  const [lancar, setLancar] = useState<LinhaUc | null>(null);
  const [pagar, setPagar] = useState<LinhaUc | null>(null);
  const r = useConsulta(async () => supabase.rpc('ucs_competencia', { p_competencia: comp }), [comp, versao]);
  const L = (r.dados as LinhaUc[] | null) ?? [];
  const linhas = aba === 'todos' ? L : L.filter((x) => x.fornecedor === aba);
  const soma = (f: (x: LinhaUc) => boolean) => L.filter(f).reduce((s, x) => s + Number(x.valor ?? 0), 0);
  const energia = L.filter((x) => x.fornecedor !== 'igua');
  const agua = L.filter((x) => x.fornecedor === 'igua');
  const [ano, mes] = comp.split('-');
  const nomeMes = `${MESES[Number(mes) - 1]} de ${ano}`;
  const kpis = [
    { l: 'Energia no mês', v: moeda(soma((x) => x.fornecedor !== 'igua')), s: `Energisa + Cercos · ${energia.length} UCs`, cor: 'var(--cor-texto-forte)' },
    { l: 'Água no mês', v: moeda(soma((x) => x.fornecedor === 'igua')), s: `Iguá · ${agua.length} matrículas`, cor: 'var(--cor-texto-forte)' },
    { l: 'Faturas pendentes', v: String(L.filter((x) => x.situacao === 'pendente').length), s: 'a vencer', cor: 'var(--selo-alerta-fg)' },
    { l: 'Faturas vencidas', v: String(L.filter((x) => x.situacao === 'atrasada').length), s: 'sem pagamento registrado', cor: 'var(--cor-critico)' },
  ];
  const baixarModelo = () => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(modeloCsv(COLUNAS_FATURAS, ['Energisa', '0000001', `${mes}/${ano}`, '412', '389,20', `20/${mes}/${ano}`, '']));
    a.download = 'modelo-faturas.csv'; a.click(); URL.revokeObjectURL(a.href);
  };

  return (
    <>
      <Cabecalho trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Unidades consumidoras' }]} titulo="Unidades consumidoras e faturas"
        acoes={<>
          <button type="button" className="botao" onClick={baixarModelo}>Baixar modelo de planilha</button>
          <button type="button" className="botao botao-primario" onClick={() => setImportar(true)}>Importar faturas do mês</button>
        </>} />
      {r.erro && <Aviso tom="critico">{r.erro}</Aviso>}
      <section aria-label={`Resumo de ${nomeMes}`} className="kpis">
        {kpis.map((k) => <div key={k.l} className="kpi-simples"><div className="rotulo">{k.l}</div><div className="valor" style={{ color: k.cor, fontSize: 26 }}>{k.v}</div><div className="texto-suave">{k.s}</div></div>)}
      </section>
      <section className="cartao">
        <div className="cartao-topo" style={{ flexWrap: 'wrap', gap: 10 }}>
          <div role="tablist" aria-label="Fornecedor" className="abas">
            {(['todos', 'energisa', 'igua', 'cercos'] as const).map((f) => <button key={f} type="button" role="tab" className="aba" aria-selected={aba === f} style={{ height: 36 }} onClick={() => setAba(f)}>{f === 'todos' ? 'Todos' : ROTULO_FORNECEDOR[f]}</button>)}
          </div>
          <label className="campo campo-leve">Competência
            <select value={comp} onChange={(e) => setComp(e.target.value)} style={{ fontSize: 14, padding: '7px 10px', border: '1px solid var(--cor-borda-campo)', borderRadius: 8, background: '#fff' }}>
              {opcoes.map((o) => { const [a, m] = o.split('-'); return <option key={o} value={o}>{MESES[Number(m) - 1]} de {a}</option>; })}
            </select>
          </label>
        </div>
        {r.carregando && !L.length ? <div className="carregando">Carregando…</div> : !linhas.length ? <EstadoVazio>Nenhuma unidade consumidora. Vincule pela ficha do contrato.</EstadoVazio> : (
          <div className="tabela-rolagem" style={{ marginTop: 14 }}>
            <table className="tabela tabela-cartoes" style={{ minWidth: 900 }}>
              <thead><tr><th>Fornecedor</th><th>UC / matrícula</th><th>Contrato e imóvel</th><th>Consumo</th><th>Valor</th><th>Vencimento</th><th>Situação</th><th><span className="sr-only">Ações</span></th></tr></thead>
              <tbody>
                {linhas.map((x) => (
                  <tr key={x.uc_id}>
                    <td data-rotulo="Fornecedor"><span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}><span aria-hidden="true" style={{ width: 8, height: 8, borderRadius: '50%', background: COR_FORNECEDOR[x.fornecedor] }} />{ROTULO_FORNECEDOR[x.fornecedor]}</span></td>
                    <td data-rotulo="UC / matrícula" style={{ fontWeight: 600 }}>{x.fornecedor === 'igua' ? 'Mat.' : 'UC'} {x.numero}</td>
                    <td data-rotulo="Contrato e imóvel"><Link href={`/contratos/ficha?id=${x.contrato_id}`}>Contrato {x.contrato_numero}</Link><br /><span className="texto-suave">{x.imovel}</span></td>
                    <td data-rotulo="Consumo">{x.consumo !== null ? `${Number(x.consumo).toLocaleString('pt-BR')} ${UNIDADE_CONSUMO[x.fornecedor]}` : '—'}</td>
                    <td data-rotulo="Valor">{x.valor !== null ? moeda(x.valor) : '—'}</td>
                    <td data-rotulo="Vencimento">{x.vencimento ? dataCurta(x.vencimento) : '—'}</td>
                    <td data-rotulo="Situação"><Selo tom={SITUACAO[x.situacao].tom}>{SITUACAO[x.situacao].r}</Selo></td>
                    <td>
                      {!x.fatura_id && <button type="button" className="botao-link" onClick={() => setLancar(x)}>Lançar</button>}
                      {x.fatura_id && !x.pago_em && <button type="button" className="botao-link" onClick={() => setPagar(x)}>Registrar pagamento</button>}
                      {x.pago_em && <span className="texto-suave">paga em {dataCurta(x.pago_em)}</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
      <p className="nota">Toda unidade consumidora fica ligada a um contrato; ao abrir o contrato, as faturas aparecem junto com os aluguéis. Lançar fatura e registrar pagamento não precisam de aprovação. Sem anexo de fatura ou comprovante.</p>

      {importar && (
        <ImportarPlanilha aberto={importar} fechar={() => setImportar(false)} titulo="Importar faturas (planilha)" colunas={COLUNAS_FATURAS}
          rpcPrevia="importar_faturas_previa" rpcImportar="importar_faturas" nomeModelo="modelo-faturas.csv"
          exemplo={['Energisa', '0000001', `${mes}/${ano}`, '412', '389,20', `20/${mes}/${ano}`, '']}
          explicacao="Colunas provisórias (modelo oficial pendente). Fornecedor: Energisa, Iguá ou Cercos. A UC precisa estar vinculada a um contrato. Fatura já lançada na mesma competência não é sobrescrita. O sistema mostra todos os erros antes e só importa se não houver nenhum."
          aoImportar={() => setVersao((v) => v + 1)} />
      )}
      {lancar && <LancarFatura uc={lancar} competencia={comp} nomeMes={nomeMes} fechar={() => setLancar(null)} aoSalvar={() => setVersao((v) => v + 1)} />}
      {pagar && <PagarFatura uc={pagar} fechar={() => setPagar(null)} aoSalvar={() => setVersao((v) => v + 1)} />}
    </>
  );
}

function LancarFatura({ uc, competencia, nomeMes, fechar, aoSalvar }: { uc: LinhaUc; competencia: string; nomeMes: string; fechar: () => void; aoSalvar: () => void }) {
  const [valor, setValor] = useState('');
  const [consumo, setConsumo] = useState('');
  const [venc, setVenc] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const salvar = async () => {
    const v = lerValor(valor);
    if (!v) return setErro('Valor inválido.');
    if (!venc) return setErro('Informe o vencimento.');
    const c = consumo.trim() ? Number(consumo.replace(/\./g, '').replace(',', '.')) : null;
    if (c !== null && (!Number.isFinite(c) || c < 0)) return setErro('Consumo inválido.');
    const { error } = await supabase.rpc('lancar_fatura', { p_uc: uc.uc_id, p_competencia: competencia, p_valor: v, p_vencimento: venc, p_consumo: c });
    if (error) return setErro(mensagemErro(error));
    aoSalvar(); fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo={`Lançar fatura · ${ROTULO_FORNECEDOR[uc.fornecedor]} ${ROTULO_NUMERO_UC[uc.fornecedor]} ${uc.numero}`} acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={salvar}>Lançar</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        <p className="texto-suave" style={{ margin: 0 }}>Competência: {nomeMes}</p>
        <div className="form-linha">
          <Campo rotulo="Valor (R$)"><input inputMode="decimal" maxLength={15} value={valor} onChange={(e) => setValor(e.target.value)} /></Campo>
          <Campo rotulo={`Consumo (${UNIDADE_CONSUMO[uc.fornecedor]}, opcional)`}><input inputMode="decimal" maxLength={12} value={consumo} onChange={(e) => setConsumo(e.target.value)} /></Campo>
        </div>
        <Campo rotulo="Vencimento"><input type="date" value={venc} onChange={(e) => setVenc(e.target.value)} /></Campo>
      </div>
    </Dialogo>
  );
}

function PagarFatura({ uc, fechar, aoSalvar }: { uc: LinhaUc; fechar: () => void; aoSalvar: () => void }) {
  const hoje = new Date().toISOString().slice(0, 10);
  const [data, setData] = useState(hoje);
  const [erro, setErro] = useState<string | null>(null);
  const salvar = async () => {
    if (!data || data > hoje) return setErro('Data de pagamento inválida.');
    const { error } = await supabase.rpc('registrar_pagamento_fatura', { p_id: uc.fatura_id, p_data: data });
    if (error) return setErro(mensagemErro(error));
    aoSalvar(); fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo="Registrar pagamento da fatura" acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={salvar}>Registrar</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        <p style={{ margin: 0 }}>{ROTULO_FORNECEDOR[uc.fornecedor]} {ROTULO_NUMERO_UC[uc.fornecedor]} {uc.numero} · {moeda(uc.valor)} · vence {dataCurta(uc.vencimento)}</p>
        <Campo rotulo="Data do pagamento"><input type="date" max={hoje} value={data} onChange={(e) => setData(e.target.value)} /></Campo>
      </div>
    </Dialogo>
  );
}
