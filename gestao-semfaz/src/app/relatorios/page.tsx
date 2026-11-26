'use client';
import { useState } from 'react';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { Aviso, Campo, EstadoVazio } from '@/components/ui';
import { dataHora } from '@/lib/formato';
import { temModulo, useSessao } from '@/lib/sessao';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';

const GRUPOS = [
  { nome: 'Demandas e produtividade', itens: [['Demandas por unidade', 'Abertas, atrasadas e concluídas'], ['Demandas por servidor', 'Recebidas, concluídas e prazos'], ['Produtividade', 'Indicadores por período']] },
  { nome: 'Contratos de locação', itens: [['Contratos', 'Vigência, valores e aditivos'], ['Contratos a vencer', 'Próximos 30, 60 ou 90 dias'], ['Aluguéis', 'Pagos e pendentes por mês']] },
  { nome: 'Água e energia', itens: [['Faturas por fornecedor', 'Energisa, Iguá e Cercos'], ['Faturas vencidas', 'Sem pagamento registrado'], ['Gasto por contrato', 'Aluguel + água + energia']] },
  { nome: 'Pessoas e controle', itens: [['Escala de férias', 'Por unidade e cargo'], ['Saldos de férias e folgas', 'Por servidor'], ['Auditoria', 'Quem fez o quê e quando']] },
];

const TABELAS: Record<string, string> = {
  '': 'Todas', unidades: 'Unidades', cargos: 'Cargos', servidores: 'Servidores', usuarios: 'Usuários', usuario_modulos_extras: 'Módulos extras',
  usuario_unidades_extras: 'Acessos a unidades', feriados: 'Feriados', solicitacoes: 'Solicitações', auth: 'Logins',
};

interface Registro { id: number; em: string; ator_id: string | null; ator_perfil: string | null; acao: string; tabela: string | null; registro_id: string | null; antes: unknown; depois: unknown; contexto: unknown }

export default function RelatoriosPage() {
  return <AppShell modulo="relatorios"><Relatorios /></AppShell>;
}

function Relatorios() {
  const { info } = useSessao();
  const podeAuditoria = temModulo(info, 'auditoria');
  const hoje = new Date().toISOString().slice(0, 10);
  const [de, setDe] = useState(new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10));
  const [ate, setAte] = useState(hoje);
  const [tabela, setTabela] = useState('');
  const [consulta, setConsulta] = useState(0);

  return (
    <>
      <Cabecalho trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Relatórios' }]} titulo="Relatórios" />
      <div className="linha">
        <section aria-label="Escolha o relatório" className="col-principal" style={{ gap: 18 }}>
          {GRUPOS.map((g) => (
            <div key={g.nome}>
              <h2 style={{ margin: '0 0 8px', fontSize: 15 }}>{g.nome}</h2>
              <div className="grade-3">
                {g.itens.map(([t, d]) => {
                  const auditoria = t === 'Auditoria';
                  return (
                    <button key={t} type="button" className="cartao-relatorio" aria-pressed={auditoria && podeAuditoria} disabled={!auditoria || !podeAuditoria}
                      title={auditoria ? undefined : 'Disponível na Fase 6'}>
                      <strong>{t}</strong><span>{auditoria ? d : `${d} · em breve`}</span>
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
        </section>
        <aside className="col-lateral">
          <section className="cartao" style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <div className="texto-suave">Relatório escolhido</div>
            <h2 style={{ fontSize: 18 }}>{podeAuditoria ? 'Auditoria' : 'Nenhum disponível'}</h2>
            {podeAuditoria ? (
              <>
                <div className="form-linha">
                  <Campo rotulo="De"><input type="date" value={de} max={ate} onChange={(e) => setDe(e.target.value)} /></Campo>
                  <Campo rotulo="Até"><input type="date" value={ate} min={de} max={hoje} onChange={(e) => setAte(e.target.value)} /></Campo>
                </div>
                <Campo rotulo="Registro"><select value={tabela} onChange={(e) => setTabela(e.target.value)}>{Object.entries(TABELAS).map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select></Campo>
                <fieldset style={{ border: 0, margin: 0, padding: 0 }}>
                  <legend style={{ fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Formato</legend>
                  <div className="grade-3" style={{ gap: 8 }}>
                    {['PDF', 'Excel', 'CSV'].map((f) => <label key={f} className="botao" style={{ minHeight: 42, opacity: .55 }} title="Exportação na Fase 6"><input type="radio" name="fmt" disabled />{f}</label>)}
                  </div>
                </fieldset>
                <button type="button" className="botao botao-primario" style={{ minHeight: 46, fontSize: 15 }} onClick={() => setConsulta((c) => c + 1)}>Consultar</button>
              </>
            ) : <p className="nota">Os relatórios dos módulos chegam na Fase 6.</p>}
            <p className="nota">O relatório só traz o que o seu perfil pode ver. Toda exportação fica registrada na auditoria.</p>
          </section>
        </aside>
      </div>
      {podeAuditoria && consulta > 0 && <ResultadoAuditoria de={de} ate={ate} tabela={tabela} chave={consulta} />}
      <p className="nota">Exportação em PDF, Excel e CSV e os demais relatórios: Fase 6.</p>
    </>
  );
}

function ResultadoAuditoria({ de, ate, tabela, chave }: { de: string; ate: string; tabela: string; chave: number }) {
  const r = useConsulta(async () => {
    let q = supabase.from('auditoria').select('id,em,ator_id,ator_perfil,acao,tabela,registro_id,antes,depois,contexto')
      .gte('em', `${de}T00:00:00-03:00`).lte('em', `${ate}T23:59:59-03:00`).order('em', { ascending: false }).limit(200);
    if (tabela) q = q.eq('tabela', tabela);
    return q;
  }, [de, ate, tabela, chave]);
  const itens = (r.dados as Registro[] | null) ?? [];
  const [aberto, setAberto] = useState<number | null>(null);
  return (
    <section className="cartao">
      <div className="cartao-topo"><h2>Auditoria</h2><span className="texto-suave">até 200 registros mais recentes · registros imutáveis</span></div>
      {r.erro && <Aviso tom="critico">{r.erro}</Aviso>}
      <div className="tabela-rolagem">
        <table className="tabela tabela-cartoes">
          <thead><tr><th>Quando</th><th>Quem</th><th>Ação</th><th>Registro</th><th>Detalhes</th></tr></thead>
          <tbody>
            {itens.map((a) => (
              <tr key={a.id}>
                <td data-rotulo="Quando">{dataHora(a.em)}</td>
                <td data-rotulo="Quem">{a.ator_id ? `${a.ator_perfil ?? '—'} · ${a.ator_id.slice(0, 8)}` : 'Sistema'}</td>
                <td data-rotulo="Ação">{a.acao}</td>
                <td data-rotulo="Registro">{TABELAS[a.tabela ?? ''] ?? a.tabela}</td>
                <td data-rotulo="Detalhes">
                  <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-primaria)', cursor: 'pointer' }} onClick={() => setAberto(aberto === a.id ? null : a.id)}>{aberto === a.id ? 'Ocultar' : 'Antes e depois'}</button>
                  {aberto === a.id && <pre style={{ whiteSpace: 'pre-wrap', fontSize: 11, maxWidth: 520, overflow: 'auto' }}>{JSON.stringify({ antes: a.antes, depois: a.depois, contexto: a.contexto }, null, 2)}</pre>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {!r.carregando && itens.length === 0 && <EstadoVazio>Nenhum registro no período.</EstadoVazio>}
      </div>
    </section>
  );
}
