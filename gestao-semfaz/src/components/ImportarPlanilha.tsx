'use client';
import { useState } from 'react';
import { Aviso, Campo, Dialogo } from '@/components/ui';
import { mensagemErro } from '@/lib/erros';
import { lerPlanilha, modeloCsv, type ColunaPlanilha } from '@/lib/planilha';
import { supabase } from '@/lib/supabase';

interface ErroLinha { linha: number; campo: string; mensagem: string }

/** Importação em 2 passos: prévia (relatório de erros do banco) → confirmar. Nada é gravado com erro. */
export function ImportarPlanilha({ aberto, fechar, titulo, colunas, rpcPrevia, rpcImportar, nomeModelo, exemplo, aoImportar, explicacao }: {
  aberto: boolean; fechar: () => void; titulo: string; colunas: ColunaPlanilha[]; rpcPrevia: string; rpcImportar: string;
  nomeModelo: string; exemplo: string[]; aoImportar?: () => void; explicacao: string;
}) {
  const [linhas, setLinhas] = useState<Record<string, string>[] | null>(null);
  const [erros, setErros] = useState<ErroLinha[]>([]);
  const [falha, setFalha] = useState<string | null>(null);
  const [ok, setOk] = useState<number | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const limpar = () => { setLinhas(null); setErros([]); setFalha(null); setOk(null); };
  const baixarModelo = () => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(modeloCsv(colunas, exemplo));
    a.download = nomeModelo;
    a.click();
    URL.revokeObjectURL(a.href);
  };
  const escolher = async (f: File | undefined) => {
    limpar();
    if (!f) return;
    setOcupado(true);
    const r = await lerPlanilha(f, colunas);
    if (r.erro) { setFalha(r.erro); setOcupado(false); return; }
    if (r.faltando.length) { setFalha(`Colunas obrigatórias faltando: ${r.faltando.join(', ')}.`); setOcupado(false); return; }
    const payload = r.linhas.map((l) => ({ ...l, linha: Number(l.linha) }));
    const { data, error } = await supabase.rpc(rpcPrevia, { p_linhas: payload });
    setOcupado(false);
    if (error) { setFalha(mensagemErro(error)); return; }
    setLinhas(r.linhas);
    setErros((data as ErroLinha[]) ?? []);
  };
  const importar = async () => {
    if (!linhas) return;
    setOcupado(true);
    const { data, error } = await supabase.rpc(rpcImportar, { p_linhas: linhas.map((l) => ({ ...l, linha: Number(l.linha) })) });
    setOcupado(false);
    if (error) { setFalha(mensagemErro(error)); return; }
    setOk(Number(data));
    aoImportar?.();
  };

  return (
    <Dialogo aberto={aberto} fechar={() => { limpar(); fechar(); }} titulo={titulo} acoes={ok !== null
      ? <button type="button" className="botao" onClick={() => { limpar(); fechar(); }}>Fechar</button>
      : <>
          <button type="button" className="botao" onClick={() => { limpar(); fechar(); }}>Cancelar</button>
          <button type="button" className="botao botao-primario" disabled={!linhas || erros.length > 0 || ocupado} onClick={importar}>
            {linhas && !erros.length ? `Importar ${linhas.length} linha(s)` : 'Importar'}
          </button>
        </>}>
      {ok !== null ? <Aviso tom="sucesso">{ok} linha(s) importada(s). A operação ficou registrada na auditoria.</Aviso> : (
        <div className="form">
          <p className="nota" style={{ fontSize: 13 }}>{explicacao}</p>
          <button type="button" className="botao" onClick={baixarModelo}>Baixar modelo de planilha</button>
          <Campo rotulo="Planilha (.xlsx ou .csv, até 2 MB)">
            <input type="file" accept=".xlsx,.csv,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" onChange={(e) => void escolher(e.target.files?.[0])} />
          </Campo>
          {ocupado && <p role="status" className="nota">Conferindo…</p>}
          {falha && <Aviso tom="critico">{falha}</Aviso>}
          {linhas && erros.length === 0 && <Aviso tom="sucesso">{linhas.length} linha(s) sem erros. Confira e clique em importar.</Aviso>}
          {erros.length > 0 && (
            <section className="aviso aviso-critico" role="alert" style={{ display: 'block' }}>
              <strong>{erros.length} erro(s) encontrados. Nada será gravado até corrigir.</strong>
              <div className="tabela-rolagem" style={{ maxHeight: 260, overflowY: 'auto' }}>
                <table className="tabela" style={{ color: 'var(--cor-texto)' }}>
                  <thead><tr><th>Linha</th><th>Campo</th><th>Erro</th></tr></thead>
                  <tbody>{erros.map((e, i) => <tr key={i}><td>{e.linha}</td><td>{colunas.find((c) => c.chave === e.campo)?.rotulo ?? e.campo}</td><td>{e.mensagem}</td></tr>)}</tbody>
                </table>
              </div>
            </section>
          )}
        </div>
      )}
    </Dialogo>
  );
}
