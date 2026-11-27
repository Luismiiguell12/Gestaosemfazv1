'use client';
import { useState } from 'react';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { SolicitarDialogo, type CampoForm } from '@/components/SolicitarDialogo';
import { Aviso, Campo, Dialogo, EstadoVazio, Selo } from '@/components/ui';
import { mensagemErro } from '@/lib/erros';
import { dataCurta, diaSemana } from '@/lib/formato';
import { ehGestorGeral, useSessao } from '@/lib/sessao';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';
import { ABRANGENCIAS, feriado as feriadoSchema, primeiroErro, ROTULO_ABRANGENCIA } from '@/lib/validacao';

interface Feriado { id: string; data: string; descricao: string; abrangencia: (typeof ABRANGENCIAS)[number] }
const TOM = { nacional: 'info', estadual: 'neutro', municipal: 'positivo', ponto_facultativo: 'alerta' } as const;

export default function FeriadosPage() {
  return <AppShell modulo="calendario"><Feriados /></AppShell>;
}

function Feriados() {
  const { info } = useSessao();
  const geral = ehGestorGeral(info);
  const anoAtual = new Date().getFullYear();
  const [ano, setAno] = useState(anoAtual);
  const lista = useConsulta(async () => supabase.from('feriados').select('id,data,descricao,abrangencia')
    .gte('data', `${ano}-01-01`).lte('data', `${ano}-12-31`).order('data'), [ano]);
  const [novo, setNovo] = useState(false);
  const [pedido, setPedido] = useState<{ f: Feriado; excluir: boolean } | null>(null);
  const opAbr = ABRANGENCIAS.map((a) => ({ valor: a, rotulo: ROTULO_ABRANGENCIA[a] }));
  const camposAlterar = (f: Feriado): CampoForm[] => [
    { chave: 'data', rotulo: 'Data', tipo: 'data', inicial: f.data },
    { chave: 'descricao', rotulo: 'Descrição', inicial: f.descricao, max: 120 },
    { chave: 'abrangencia', rotulo: 'Abrangência', tipo: 'select', inicial: f.abrangencia, opcoes: opAbr },
  ];
  const itens = (lista.dados as Feriado[] | null) ?? [];

  return (
    <>
      <Cabecalho
        trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Calendário', href: '/calendario' }, { rotulo: 'Feriados' }]}
        titulo={`Feriados · ${ano}`}
        acoes={<>
          <div role="group" aria-label="Ano" style={{ display: 'flex', border: '1px solid var(--cor-borda-campo)', borderRadius: 10, overflow: 'hidden', background: '#fff' }}>
            {[anoAtual, anoAtual + 1].map((a) => (
              <button key={a} type="button" aria-pressed={a === ano} onClick={() => setAno(a)}
                style={{ height: 42, padding: '0 14px', border: 0, fontSize: 14, cursor: 'pointer', background: a === ano ? 'var(--cor-texto-forte)' : '#fff', color: a === ano ? '#fff' : 'var(--cor-texto-forte)' }}>{a}</button>
            ))}
          </div>
          {geral && <button type="button" className="botao botao-primario" onClick={() => setNovo(true)}>+ Novo feriado</button>}
        </>}
      />
      <div className="linha">
        <section className="cartao col-principal" style={{ gap: 0 }}>
          <h2>Feriados cadastrados</h2>
          {lista.erro && <Aviso tom="critico">{lista.erro}</Aviso>}
          <div className="tabela-rolagem">
            <table className="tabela tabela-cartoes">
              <thead><tr><th>Data</th><th>Dia</th><th>Descrição</th><th>Abrangência</th>{geral && <th style={{ textAlign: 'right' }}>Ações</th>}</tr></thead>
              <tbody>
                {itens.map((f) => (
                  <tr key={f.id}>
                    <td data-rotulo="Data"><strong>{dataCurta(f.data)}</strong></td>
                    <td data-rotulo="Dia">{diaSemana(f.data)}</td>
                    <td data-rotulo="Descrição">{f.descricao}</td>
                    <td data-rotulo="Abrangência"><Selo tom={TOM[f.abrangencia]}>{ROTULO_ABRANGENCIA[f.abrangencia]}</Selo></td>
                    {geral && (
                      <td data-rotulo="Ações" style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
                        <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-primaria)', cursor: 'pointer', minHeight: 36 }} onClick={() => setPedido({ f, excluir: false })}>Alterar</button>
                        <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-critico)', cursor: 'pointer', minHeight: 36 }} onClick={() => setPedido({ f, excluir: true })}>Excluir</button>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
            {!lista.carregando && itens.length === 0 && <EstadoVazio>Nenhum feriado cadastrado para {ano}.</EstadoVazio>}
          </div>
        </section>
        <aside className="col-lateral">
          <section className="aviso aviso-info" style={{ display: 'block' }}>
            <strong>Para que servem</strong><br />Os feriados cadastrados não contam como dia útil nos prazos das demandas, das férias e da devolução das folhas de ponto.
          </section>
          <p className="nota">Cadastrar feriado novo: Secretária ou Administrador. Alterar ou excluir passa por aprovação.</p>
        </aside>
      </div>
      <p className="nota">Feriados nacionais já cadastrados. Feriados municipais de Lagarto e estaduais: cadastrar conforme o calendário oficial.</p>

      {novo && <NovoFeriado fechar={() => setNovo(false)} aoSalvar={() => void lista.recarregar()} />}
      {pedido && (
        <SolicitarDialogo aberto fechar={() => setPedido(null)} alvoId={pedido.f.id}
          tipo={pedido.excluir ? 'feriado_excluir' : 'feriado_alterar'}
          titulo={`${pedido.excluir ? 'Excluir' : 'Alterar'} feriado de ${dataCurta(pedido.f.data)}`}
          campos={pedido.excluir ? [] : camposAlterar(pedido.f)} aviso="Alterar ou excluir feriado passa por aprovação." />
      )}
    </>
  );
}

function NovoFeriado({ fechar, aoSalvar }: { fechar: () => void; aoSalvar: () => void }) {
  const [f, setF] = useState({ data: '', descricao: '', abrangencia: 'municipal' });
  const [erro, setErro] = useState<string | null>(null);
  const salvar = async () => {
    const r = feriadoSchema.safeParse(f);
    if (!r.success) { setErro(primeiroErro(r)); return; }
    const { error } = await supabase.from('feriados').insert(r.data);
    if (error) { setErro(error.code === '23505' ? 'Já existe feriado nesta data.' : mensagemErro(error)); return; }
    aoSalvar(); fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo="Novo feriado" acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={salvar}>Salvar</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        <Campo rotulo="Data"><input type="date" value={f.data} onChange={(e) => setF({ ...f, data: e.target.value })} /></Campo>
        <Campo rotulo="Descrição"><input maxLength={120} value={f.descricao} onChange={(e) => setF({ ...f, descricao: e.target.value })} /></Campo>
        <Campo rotulo="Abrangência"><select value={f.abrangencia} onChange={(e) => setF({ ...f, abrangencia: e.target.value })}>{ABRANGENCIAS.map((a) => <option key={a} value={a}>{ROTULO_ABRANGENCIA[a]}</option>)}</select></Campo>
      </div>
    </Dialogo>
  );
}
