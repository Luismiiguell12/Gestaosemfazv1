'use client';
import { useMemo, useState } from 'react';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { Aviso, Campo, EstadoVazio } from '@/components/ui';
import { mensagemErro } from '@/lib/erros';
import { baixar, gerarArquivo, nomeArquivo, textoCelula, type Formato } from '@/lib/exportar';
import { quando } from '@/lib/formato';
import { FORNECEDOR, podeRelatorio, prepararLinhas, RELATORIOS, type Relatorio, type Valores } from '@/lib/relatorios';
import { ehGestorGeral, useSessao } from '@/lib/sessao';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';

const TABELAS: Record<string, string> = {
  '': 'Todos', unidades: 'Unidades', cargos: 'Cargos', servidores: 'Servidores', usuarios: 'Usuários', usuario_modulos_extras: 'Módulos extras',
  usuario_unidades_extras: 'Acessos a unidades', feriados: 'Feriados', solicitacoes: 'Solicitações', auth: 'Logins', contratos: 'Contratos', locadores: 'Locadores',
  alugueis: 'Aluguéis', faturas: 'Faturas', afastamentos: 'Férias e folgas', saldos_servidor: 'Saldos', demandas: 'Demandas', relatorios: 'Exportações',
};
const FORMATOS: { f: Formato; l: string }[] = [{ f: 'pdf', l: 'PDF' }, { f: 'xlsx', l: 'Excel' }, { f: 'csv', l: 'CSV' }];
const GRUPOS = [...new Set(RELATORIOS.map((r) => r.grupo))];
const PREVIA = 50;
const iso = (d: Date) => d.toISOString().slice(0, 10);

interface Exportacao { id: string; relatorio: string; titulo: string; formato: Formato; filtros: Valores; linhas: number; em: string }

export default function RelatoriosPage() {
  return <AppShell modulo="relatorios"><Relatorios /></AppShell>;
}

function Relatorios() {
  const { info } = useSessao();
  const modulos = info?.modulos ?? [];
  const gestor = ehGestorGeral(info);
  const disponiveis = RELATORIOS.filter((r) => podeRelatorio(r, modulos, gestor));
  const [selId, setSelId] = useState(disponiveis[0]?.id ?? '');
  const sel = RELATORIOS.find((r) => r.id === selId) ?? null;
  const hoje = new Date();
  const [v, setV] = useState<Valores>({
    de: iso(new Date(hoje.getFullYear(), hoje.getMonth() - 2, 1)), ate: iso(hoje), unidade: '', situacao: '', dias: '90', ano: String(hoje.getFullYear()), fornecedor: '', tabela: '',
  });
  const [formato, setFormato] = useState<Formato>('xlsx');
  const [dados, setDados] = useState<{ rel: Relatorio; linhas: Record<string, unknown>[]; filtros: string[] } | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [versao, setVersao] = useState(0);
  const unidades = useConsulta(async () => supabase.from('unidades').select('id,sigla,ordem').eq('ativa', true).order('ordem'), []);
  const U = (unidades.dados as { id: string; sigla: string }[] | null) ?? [];
  const recentes = useConsulta(async () => supabase.from('exportacoes').select('id,relatorio,titulo,formato,filtros,linhas,em').order('em', { ascending: false }).limit(5), [versao]);
  const R = (recentes.dados as Exportacao[] | null) ?? [];

  const set = (k: keyof Valores) => (e: { target: { value: string } }) => setV({ ...v, [k]: e.target.value });
  const meses = sel?.filtros.includes('meses') || sel?.filtros.includes('competencia');
  const descricaoFiltros = (r: Relatorio, x: Valores) => {
    const f: string[] = [];
    if (r.filtros.includes('periodo')) f.push(`Período: ${textoCelula(x.de, 'data')} a ${textoCelula(x.ate, 'data')}`);
    if (r.filtros.includes('competencia')) f.push(`Competência: ${x.de.slice(5, 7)}/${x.de.slice(0, 4)}`);
    if (r.filtros.includes('meses')) f.push(`Competências: ${x.de.slice(5, 7)}/${x.de.slice(0, 4)} a ${x.ate.slice(5, 7)}/${x.ate.slice(0, 4)}`);
    if (r.filtros.includes('ano')) f.push(`Ano: ${x.ano}`);
    if (r.filtros.includes('dias')) f.push(`Próximos ${x.dias} dias`);
    if (r.filtros.includes('unidade')) f.push(`Unidade: ${U.find((u) => u.id === x.unidade)?.sigla ?? 'todas que você pode ver'}`);
    if (r.filtros.includes('fornecedor')) f.push(`Fornecedor: ${FORNECEDOR[x.fornecedor] ?? 'todos'}`);
    if (r.filtros.includes('situacaoContrato')) f.push(`Situação: ${{ vigentes: 'vigentes', encerrados: 'encerrados', todos: 'todos' }[x.situacao || 'vigentes']}`);
    if (r.filtros.includes('situacaoAluguel')) f.push(`Situação: ${{ pagos: 'pagos', pendentes: 'não pagos', vencidos: 'vencidos', todos: 'todos' }[x.situacao || 'todos']}`);
    if (r.filtros.includes('tabela')) f.push(`Registro: ${TABELAS[x.tabela] ?? x.tabela}`);
    return f;
  };

  const consultar = async (r: Relatorio, x: Valores) => {
    setErro(null);
    if (!r.rpc) return null;
    if ((r.filtros.includes('periodo') || r.filtros.includes('meses')) && (!x.de || !x.ate || x.de > x.ate)) { setErro('Confira o período.'); return null; }
    const { data, error } = await supabase.rpc(r.rpc, r.params(x));
    if (error) { setErro(mensagemErro(error)); return null; }
    const linhas = prepararLinhas(r.id, (data as Record<string, unknown>[]) ?? []);
    const res = { rel: r, linhas, filtros: descricaoFiltros(r, x) };
    setDados(res);
    return res;
  };

  const gerar = async (r: Relatorio, x: Valores, f: Formato) => {
    setOcupado(true);
    try {
      const res = await consultar(r, x);
      if (!res) return;
      const { error } = await supabase.rpc('registrar_exportacao', { p_relatorio: r.id, p_titulo: r.titulo, p_formato: f, p_filtros: x, p_linhas: res.linhas.length });
      if (error) { setErro(mensagemErro(error)); return; }
      const blob = await gerarArquivo(f, { titulo: r.titulo, filtros: res.filtros, colunas: r.colunas, linhas: res.linhas, geradoPor: info?.nome ?? '', geradoEm: new Date() });
      baixar(blob, nomeArquivo(r.titulo, f));
      setVersao((n) => n + 1);
    } catch {
      setErro('Não foi possível gerar o arquivo.');
    } finally { setOcupado(false); }
  };

  const escolher = (r: Relatorio) => {
    setSelId(r.id); setDados(null); setErro(null);
    const ehMes = (y: Relatorio) => y.filtros.includes('meses') || y.filtros.includes('competencia');
    const mudaPeriodo = ehMes(r) !== (sel ? ehMes(sel) : false);
    setV((x) => ({ ...x, situacao: '', ...(mudaPeriodo && ehMes(r) ? { de: x.de.slice(0, 7), ate: x.ate.slice(0, 7) } : {}),
      ...(mudaPeriodo && !ehMes(r) ? { de: `${x.de.slice(0, 7)}-01`, ate: iso(hoje) } : {}) }));
  };

  const valoresMes = useMemo(() => (meses ? { ...v, de: v.de.slice(0, 7), ate: v.ate.slice(0, 7) } : v), [meses, v]);

  return (
    <>
      <Cabecalho trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Relatórios' }]} titulo="Relatórios" />
      <div className="linha">
        <section aria-label="Escolha o relatório" className="col-principal" style={{ gap: 18 }}>
          {GRUPOS.map((g) => (
            <div key={g}>
              <h2 style={{ margin: '0 0 8px', fontSize: 15 }}>{g}</h2>
              <div className="grade-3">
                {RELATORIOS.filter((r) => r.grupo === g).map((r) => {
                  const pode = podeRelatorio(r, modulos, gestor);
                  return (
                    <button key={r.id} type="button" className="cartao-relatorio" aria-pressed={selId === r.id} disabled={!pode} onClick={() => escolher(r)}
                      title={r.pendente ?? (pode ? undefined : 'Seu perfil não tem acesso a este relatório.')}>
                      <strong>{r.titulo}</strong><span>{r.pendente ? `${r.descricao} · em definição` : r.descricao}</span>
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
        </section>
        <aside className="col-lateral" style={{ gap: 20 }}>
          <section className="cartao" style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <div className="texto-suave">Relatório escolhido</div>
            <h2 style={{ fontSize: 18 }}>{sel && podeRelatorio(sel, modulos, gestor) ? sel.titulo : 'Nenhum disponível'}</h2>
            {sel && podeRelatorio(sel, modulos, gestor) && (
              <>
                {sel.filtros.includes('periodo') && <div className="form-linha">
                  <Campo rotulo="De"><input type="date" value={v.de} max={v.ate} onChange={set('de')} /></Campo>
                  <Campo rotulo="Até"><input type="date" value={v.ate} min={v.de} onChange={set('ate')} /></Campo>
                </div>}
                {sel.filtros.includes('competencia') && <Campo rotulo="Competência"><input type="month" value={v.de.slice(0, 7)} onChange={(e) => setV({ ...v, de: e.target.value, ate: e.target.value })} /></Campo>}
                {meses && <div className="form-linha">
                  <Campo rotulo="Competência de"><input type="month" value={v.de.slice(0, 7)} onChange={(e) => setV({ ...v, de: e.target.value })} /></Campo>
                  <Campo rotulo="até"><input type="month" value={v.ate.slice(0, 7)} onChange={(e) => setV({ ...v, ate: e.target.value })} /></Campo>
                </div>}
                {sel.filtros.includes('ano') && <Campo rotulo="Ano"><select value={v.ano} onChange={set('ano')}>{[0, 1, 2, -1].map((d) => hoje.getFullYear() - d).sort().map((a) => <option key={a} value={a}>{a}</option>)}</select></Campo>}
                {sel.filtros.includes('dias') && <Campo rotulo="Vencendo nos próximos"><select value={v.dias} onChange={set('dias')}>{['30', '60', '90', '180'].map((d) => <option key={d} value={d}>{d} dias</option>)}</select></Campo>}
                {sel.filtros.includes('unidade') && <Campo rotulo="Unidade"><select value={v.unidade} onChange={set('unidade')}><option value="">Todas que você pode ver</option>{U.map((u) => <option key={u.id} value={u.id}>{u.sigla}</option>)}</select></Campo>}
                {sel.filtros.includes('fornecedor') && <Campo rotulo="Fornecedor"><select value={v.fornecedor} onChange={set('fornecedor')}><option value="">Todos</option>{Object.entries(FORNECEDOR).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Campo>}
                {sel.filtros.includes('situacaoContrato') && <Campo rotulo="Situação"><select value={v.situacao || 'vigentes'} onChange={set('situacao')}><option value="vigentes">Vigentes</option><option value="encerrados">Encerrados</option><option value="todos">Todos</option></select></Campo>}
                {sel.filtros.includes('situacaoAluguel') && <Campo rotulo="Situação"><select value={v.situacao || 'todos'} onChange={set('situacao')}><option value="todos">Todos</option><option value="pagos">Pagos</option><option value="pendentes">Não pagos</option><option value="vencidos">Vencidos</option></select></Campo>}
                {sel.filtros.includes('tabela') && <Campo rotulo="Registro"><select value={v.tabela} onChange={set('tabela')}>{Object.entries(TABELAS).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Campo>}
                <fieldset style={{ border: 0, margin: 0, padding: 0 }}>
                  <legend style={{ fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Formato</legend>
                  <div className="grade-3" style={{ gap: 8 }}>
                    {FORMATOS.map((x) => <label key={x.f} className="botao" style={{ minHeight: 42, borderColor: formato === x.f ? 'var(--cor-primaria)' : undefined, background: formato === x.f ? 'var(--selo-primaria-bg)' : undefined }}>
                      <input type="radio" name="formato" checked={formato === x.f} onChange={() => setFormato(x.f)} />{x.l}</label>)}
                  </div>
                </fieldset>
                <div className="acoes">
                  <button type="button" className="botao" style={{ flex: 1 }} disabled={ocupado} onClick={() => void consultar(sel, valoresMes)}>Ver na tela</button>
                  <button type="button" className="botao botao-primario" style={{ flex: 2, minHeight: 46, fontSize: 15 }} disabled={ocupado} onClick={() => void gerar(sel, valoresMes, formato)}>{ocupado ? 'Gerando…' : 'Gerar relatório'}</button>
                </div>
              </>
            )}
            {erro && <Aviso tom="critico">{erro}</Aviso>}
            <p className="nota">O relatório só traz o que o seu perfil pode ver. Toda exportação fica registrada na auditoria.</p>
          </section>
          <section className="cartao">
            <h2 style={{ fontSize: 16, marginBottom: 6 }}>Gerados recentemente</h2>
            {!R.length && <EstadoVazio>Nenhum relatório gerado por você.</EstadoVazio>}
            {R.map((x) => {
              const rel = RELATORIOS.find((r) => r.id === x.relatorio);
              return (
                <div key={x.id} style={{ display: 'flex', justifyContent: 'space-between', gap: 8, padding: '9px 0', borderTop: '1px solid var(--cor-divisor)', fontSize: 13 }}>
                  <span>{x.titulo}<br /><span className="texto-suave">por você, {quando(x.em)} · {x.linhas} linha(s)</span></span>
                  {rel && podeRelatorio(rel, modulos, gestor)
                    ? <button type="button" className="botao-link" title="Gera de novo com os mesmos filtros (o arquivo não fica guardado)" onClick={() => { setSelId(rel.id); setV({ ...v, ...x.filtros }); setFormato(x.formato); void gerar(rel, { ...v, ...x.filtros }, x.formato); }}>{FORMATOS.find((f) => f.f === x.formato)?.l}</button>
                    : <span className="texto-suave">{FORMATOS.find((f) => f.f === x.formato)?.l}</span>}
                </div>
              );
            })}
          </section>
        </aside>
      </div>
      {dados && <Previa dados={dados} />}
      <p className="nota">Os arquivos são gerados no seu aparelho e não ficam guardados no sistema. Em "Gerados recentemente", clicar no formato gera o relatório de novo com os mesmos filtros e os dados atuais.</p>
    </>
  );
}

function Previa({ dados }: { dados: { rel: Relatorio; linhas: Record<string, unknown>[]; filtros: string[] } }) {
  const { rel, linhas, filtros } = dados;
  const cols = rel.colunas.filter((c) => c.chave !== 'antes' && c.chave !== 'depois');
  return (
    <section className="cartao">
      <div className="cartao-topo" style={{ flexWrap: 'wrap', gap: 8 }}>
        <h2>{rel.titulo}</h2>
        <span className="texto-suave">{linhas.length} linha(s){linhas.length > PREVIA ? ` · mostrando as ${PREVIA} primeiras; o arquivo traz todas` : ''}</span>
      </div>
      <p className="texto-suave" style={{ margin: '4px 0 0' }}>{filtros.join(' · ')}</p>
      {!linhas.length ? <EstadoVazio>Nenhum registro para esses filtros.</EstadoVazio> : (
        <div className="tabela-rolagem">
          <table className="tabela tabela-cartoes">
            <thead><tr>{cols.map((c) => <th key={c.chave} style={{ textAlign: c.tipo && c.tipo !== 'texto' && c.tipo !== 'data' && c.tipo !== 'dataHora' ? 'right' : 'left' }}>{c.rotulo}</th>)}</tr></thead>
            <tbody>
              {linhas.slice(0, PREVIA).map((l, i) => (
                <tr key={i}>{cols.map((c) => <td key={c.chave} data-rotulo={c.rotulo} style={{ textAlign: c.tipo && c.tipo !== 'texto' && c.tipo !== 'data' && c.tipo !== 'dataHora' ? 'right' : 'left' }}>{textoCelula(l[c.chave], c.tipo) || '—'}</td>)}</tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
