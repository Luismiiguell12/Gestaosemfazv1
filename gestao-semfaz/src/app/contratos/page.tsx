'use client';
import { useRouter } from 'next/navigation';
import { Suspense, useMemo, useState } from 'react';
import { ImportarPlanilha } from '@/components/ImportarPlanilha';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { Aviso, Campo, Dialogo, EstadoVazio, Selo } from '@/components/ui';
import { cnpjValido, cpfValido, digitos, lerValor, seloVigencia } from '@/lib/contratos';
import { mensagemErro } from '@/lib/erros';
import { dataCurta, moeda } from '@/lib/formato';
import { COLUNAS_CONTRATOS } from '@/lib/planilha';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';

interface ContratoLista {
  id: string; numero: string; locador: string; imovel: string; unidade: string | null; fim_vigencia: string; dias_restantes: number;
  valor_mensal: number; fiscal: string | null; encerrado: boolean; alugueis_atrasados: number; aditivos: number;
}

export default function ContratosPage() {
  return <AppShell modulo="contratos"><Suspense><Lista /></Suspense></AppShell>;
}

function Lista() {
  const router = useRouter();
  const [versao, setVersao] = useState(0);
  const lista = useConsulta(async () => supabase.rpc('listar_contratos'), [versao]);
  const [filtro, setFiltro] = useState<'vigentes' | 'vencendo' | 'atraso' | 'todos'>('vigentes');
  const [termo, setTermo] = useState('');
  const [novo, setNovo] = useState(false);
  const [importar, setImportar] = useState(false);
  const L = (lista.dados as ContratoLista[] | null) ?? [];
  const filtrados = useMemo(() => {
    const q = termo.trim().toLowerCase();
    return L.filter((c) => (filtro === 'todos' || (filtro === 'vigentes' && !c.encerrado) || (filtro === 'vencendo' && !c.encerrado && c.dias_restantes <= 90)
      || (filtro === 'atraso' && c.alugueis_atrasados > 0))
      && (!q || [c.numero, c.locador, c.imovel, c.unidade ?? ''].some((x) => x.toLowerCase().includes(q))));
  }, [L, filtro, termo]);
  const abas = [{ id: 'vigentes', l: 'Vigentes' }, { id: 'vencendo', l: 'Vencendo em 90 dias' }, { id: 'atraso', l: 'Aluguel em atraso' }, { id: 'todos', l: 'Todos' }] as const;

  return (
    <>
      <Cabecalho trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Contratos de locação' }]} titulo="Contratos de locação"
        acoes={<>
          <button type="button" className="botao" onClick={() => setImportar(true)}>Importar planilha</button>
          <button type="button" className="botao botao-primario" onClick={() => setNovo(true)}>Novo contrato</button>
        </>} />
      {lista.erro && <Aviso tom="critico">{lista.erro}</Aviso>}
      <section className="cartao">
        <div className="cartao-topo" style={{ flexWrap: 'wrap', gap: 10 }}>
          <div role="tablist" aria-label="Filtro" className="abas">
            {abas.map((a) => <button key={a.id} type="button" role="tab" className="aba" aria-selected={filtro === a.id} onClick={() => setFiltro(a.id)}>{a.l}</button>)}
          </div>
          <label className="campo campo-leve">Buscar<input value={termo} maxLength={100} onChange={(e) => setTermo(e.target.value)} placeholder="Número, locador, imóvel" style={{ minHeight: 40, border: '1px solid var(--cor-borda-campo)', borderRadius: 8, padding: '0 10px' }} /></label>
        </div>
        {lista.carregando && !L.length ? <div className="carregando">Carregando…</div> : !filtrados.length ? <EstadoVazio>Nenhum contrato neste filtro.</EstadoVazio> : (
          <div className="tabela-rolagem">
            <table className="tabela tabela-cartoes">
              <thead><tr><th>Contrato</th><th>Locador</th><th>Imóvel</th><th>Unidade</th><th>Valor mensal</th><th>Vigência até</th><th>Situação</th></tr></thead>
              <tbody>
                {filtrados.map((c) => {
                  const s = seloVigencia(c.dias_restantes, c.encerrado);
                  const abrir = () => router.push(`/contratos/ficha?id=${c.id}`);
                  return (
                    <tr key={c.id} className="clicavel" tabIndex={0} onClick={abrir} onKeyDown={(e) => e.key === 'Enter' && abrir()}>
                      <td data-rotulo="Contrato"><strong>{c.numero}</strong>{c.aditivos > 0 && <><br /><span className="texto-suave">{c.aditivos} aditivo(s)</span></>}</td>
                      <td data-rotulo="Locador">{c.locador}</td>
                      <td data-rotulo="Imóvel">{c.imovel}</td>
                      <td data-rotulo="Unidade">{c.unidade ?? '—'}</td>
                      <td data-rotulo="Valor mensal">{moeda(c.valor_mensal)}</td>
                      <td data-rotulo="Vigência até">{dataCurta(c.fim_vigencia)}</td>
                      <td data-rotulo="Situação"><span className="acoes" style={{ gap: 6 }}><Selo tom={s.tom}>{s.texto}</Selo>{c.alugueis_atrasados > 0 && <Selo tom="critico">{c.alugueis_atrasados} aluguel(is) vencido(s)</Selo>}</span></td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>
      <p className="nota">Cadastrar contrato novo não precisa de aprovação. Alterar dados de contrato já cadastrado ou registrar aditivo passa pela Secretária ou pelo Administrador do sistema.</p>
      {novo && <NovoContrato fechar={() => setNovo(false)} aoSalvar={(id) => router.push(`/contratos/ficha?id=${id}`)} />}
      {importar && (
        <ImportarPlanilha aberto={importar} fechar={() => setImportar(false)} titulo="Importar contratos (planilha)" colunas={COLUNAS_CONTRATOS}
          rpcPrevia="importar_contratos_previa" rpcImportar="importar_contratos" nomeModelo="modelo-contratos.csv"
          exemplo={['001/2026', '0000/2026', 'PF', 'Locador Exemplo', '000.000.000-00', '', '', 'Sala comercial', 'Rua Exemplo, 100', 'COFIT', '01/01/2026', '31/12/2026', '2.500,00', '10', '000101', 'IPCA', '12']}
          explicacao="Cadastro inicial dos contratos. Colunas provisórias: o modelo oficial ainda será definido pela SEMFAZ. CPF/CNPJ é conferido (dígitos verificadores), a unidade é a sigla e o fiscal é a matrícula. Os aluguéis mês a mês são gerados para toda a vigência. Antes de gravar o sistema mostra todos os erros e só importa se não houver nenhum."
          aoImportar={() => setVersao((v) => v + 1)} />
      )}
    </>
  );
}

function NovoContrato({ fechar, aoSalvar }: { fechar: () => void; aoSalvar: (id: string) => void }) {
  const unidades = useConsulta(async () => supabase.from('unidades').select('id,sigla').eq('ativa', true).order('sigla'), []);
  const servidores = useConsulta(async () => supabase.from('servidores').select('id,nome_completo').eq('situacao', 'ativo').order('nome_completo'), []);
  const [f, setF] = useState<Record<string, string>>({ tipo: 'PF', dia_vencimento: '10' });
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const set = (k: string) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });

  const salvar = async () => {
    setErro(null);
    const valor = lerValor(f.valor_mensal ?? '');
    const doc = digitos(f.documento ?? '');
    if (!f.numero?.trim()) return setErro('Informe o número do contrato.');
    if ((f.nome ?? '').trim().length < 2) return setErro('Informe o nome do locador.');
    if (f.tipo === 'PF' ? !cpfValido(doc) : !cnpjValido(doc)) return setErro(f.tipo === 'PF' ? 'CPF inválido.' : 'CNPJ inválido.');
    if ((f.imovel_descricao ?? '').trim().length < 2) return setErro('Descreva o imóvel.');
    if (!f.inicio || !f.fim || f.fim < f.inicio) return setErro('Confira o início e o fim da vigência.');
    if (!valor) return setErro('Valor mensal inválido.');
    const dia = Number(f.dia_vencimento);
    if (!Number.isInteger(dia) || dia < 1 || dia > 28) return setErro('Dia de vencimento deve ser de 1 a 28.');
    setSalvando(true);
    const { data, error } = await supabase.rpc('criar_contrato', {
      p_dados: { numero: f.numero, processo: f.processo, imovel_descricao: f.imovel_descricao, imovel_endereco: f.imovel_endereco, unidade_ocupante_id: f.unidade_ocupante_id || null,
        inicio: f.inicio, fim: f.fim, valor_mensal: valor, dia_vencimento: dia, fiscal_servidor_id: f.fiscal_servidor_id || null, indice_reajuste: f.indice_reajuste, mes_database: f.mes_database || null },
      p_locador: { tipo: f.tipo, nome: f.nome, documento: doc, email: f.email, telefone: f.telefone },
    });
    setSalvando(false);
    if (error) return setErro(mensagemErro(error));
    aoSalvar(data as string);
  };

  const U = (unidades.dados as { id: string; sigla: string }[] | null) ?? [];
  const S = (servidores.dados as { id: string; nome_completo: string }[] | null) ?? [];
  return (
    <Dialogo aberto fechar={fechar} titulo="Novo contrato de locação" acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" disabled={salvando} onClick={salvar}>{salvando ? 'Salvando…' : 'Cadastrar'}</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        <div className="form-linha">
          <Campo rotulo="Número do contrato"><input maxLength={30} value={f.numero ?? ''} onChange={set('numero')} /></Campo>
          <Campo rotulo="Processo (opcional)"><input maxLength={60} value={f.processo ?? ''} onChange={set('processo')} /></Campo>
        </div>
        <div className="form-linha">
          <Campo rotulo="Locador"><input maxLength={200} value={f.nome ?? ''} onChange={set('nome')} /></Campo>
          <Campo rotulo="Tipo"><select value={f.tipo} onChange={set('tipo')}><option value="PF">Pessoa física</option><option value="PJ">Pessoa jurídica</option></select></Campo>
        </div>
        <div className="form-linha">
          <Campo rotulo={f.tipo === 'PF' ? 'CPF' : 'CNPJ'} ajuda="Se o locador já estiver cadastrado, os dados dele não são alterados."><input inputMode="numeric" maxLength={18} autoComplete="off" value={f.documento ?? ''} onChange={set('documento')} /></Campo>
          <Campo rotulo="Telefone (opcional)"><input inputMode="tel" maxLength={16} autoComplete="off" value={f.telefone ?? ''} onChange={set('telefone')} /></Campo>
        </div>
        <Campo rotulo="E-mail do locador (opcional)"><input type="email" maxLength={254} autoComplete="off" value={f.email ?? ''} onChange={set('email')} /></Campo>
        <Campo rotulo="Imóvel"><input maxLength={200} value={f.imovel_descricao ?? ''} onChange={set('imovel_descricao')} placeholder="Ex.: Sala comercial do Centro" /></Campo>
        <Campo rotulo="Endereço (opcional)"><input maxLength={300} value={f.imovel_endereco ?? ''} onChange={set('imovel_endereco')} /></Campo>
        <div className="form-linha">
          <Campo rotulo="Unidade ocupante"><select value={f.unidade_ocupante_id ?? ''} onChange={set('unidade_ocupante_id')}><option value="">—</option>{U.map((u) => <option key={u.id} value={u.id}>{u.sigla}</option>)}</select></Campo>
          <Campo rotulo="Fiscal do contrato"><select value={f.fiscal_servidor_id ?? ''} onChange={set('fiscal_servidor_id')}><option value="">—</option>{S.map((s) => <option key={s.id} value={s.id}>{s.nome_completo}</option>)}</select></Campo>
        </div>
        <div className="form-linha">
          <Campo rotulo="Início da vigência"><input type="date" value={f.inicio ?? ''} onChange={set('inicio')} /></Campo>
          <Campo rotulo="Fim da vigência"><input type="date" value={f.fim ?? ''} onChange={set('fim')} /></Campo>
        </div>
        <div className="form-linha">
          <Campo rotulo="Valor mensal (R$)"><input inputMode="decimal" maxLength={15} value={f.valor_mensal ?? ''} onChange={set('valor_mensal')} placeholder="2.500,00" /></Campo>
          <Campo rotulo="Dia de vencimento"><input inputMode="numeric" maxLength={2} value={f.dia_vencimento ?? ''} onChange={set('dia_vencimento')} /></Campo>
        </div>
        <div className="form-linha">
          <Campo rotulo="Índice de reajuste (opcional)"><input maxLength={40} value={f.indice_reajuste ?? ''} onChange={set('indice_reajuste')} placeholder="IPCA" /></Campo>
          <Campo rotulo="Mês da data-base"><select value={f.mes_database ?? ''} onChange={set('mes_database')}><option value="">—</option>{['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'].map((m, i) => <option key={m} value={i + 1}>{m}</option>)}</select></Campo>
        </div>
      </div>
    </Dialogo>
  );
}
