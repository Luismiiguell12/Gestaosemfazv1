'use client';
import { useEffect, useState } from 'react';
import { Aviso, Campo, Dialogo } from '@/components/ui';
import { caminhoAnexoAprovacao, MIME, validarAnexo } from '@/lib/arquivos';
import { mensagemErro } from '@/lib/erros';
import { useSessao } from '@/lib/sessao';
import type { TipoSolicitacao } from '@/lib/solicitacoes';
import { supabase } from '@/lib/supabase';
import { justificativa as justSchema, primeiroErro } from '@/lib/validacao';

export interface CampoForm {
  chave: string;
  rotulo: string;
  tipo?: 'texto' | 'data' | 'select';
  opcoes?: { valor: string; rotulo: string }[];
  inicial?: string;
  max?: number;
}

/** Monta o pedido de aprovação. Só envia campos alterados; o banco revalida tudo. */
export function SolicitarDialogo({ aberto, fechar, titulo, tipo, alvoId, campos, aviso, aoEnviar }: {
  aberto: boolean; fechar: () => void; titulo: string; tipo: TipoSolicitacao; alvoId: string | null;
  campos: CampoForm[]; aviso?: string; aoEnviar?: () => void;
}) {
  const { info } = useSessao();
  const [valores, setValores] = useState<Record<string, string>>({});
  const [just, setJust] = useState('');
  const [arquivo, setArquivo] = useState<File | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ok, setOk] = useState(false);
  const [enviando, setEnviando] = useState(false);

  useEffect(() => {
    if (aberto) {
      setValores(Object.fromEntries(campos.map((c) => [c.chave, c.inicial ?? ''])));
      setJust(''); setArquivo(null); setErro(null); setOk(false);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [aberto]);

  const enviar = async () => {
    setErro(null);
    const dados: Record<string, string | boolean | null> = {};
    for (const c of campos) {
      const v = (valores[c.chave] ?? '').trim();
      if (alvoId && tipo !== 'acesso_unidade_conceder' && tipo !== 'acesso_unidade_retirar' && v === (c.inicial ?? '')) continue;
      dados[c.chave] = v === '' ? null : v === 'true' ? true : v === 'false' ? false : v;
    }
    if (tipo !== 'feriado_excluir' && Object.keys(dados).length === 0) { setErro('Nenhuma alteração informada.'); return; }
    const j = justSchema.safeParse(just);
    if (!j.success) { setErro(primeiroErro(j)); return; }

    setEnviando(true);
    let anexo: string | null = null;
    if (arquivo) {
      const v = await validarAnexo(arquivo);
      if (!v.ok) { setErro(v.erro); setEnviando(false); return; }
      anexo = caminhoAnexoAprovacao(info!.usuario_id!, v.tipo);
      const up = await supabase.storage.from('anexos').upload(anexo, arquivo, { contentType: MIME[v.tipo], upsert: false });
      if (up.error) { setErro('Não foi possível enviar o anexo.'); setEnviando(false); return; }
    }
    const { error } = await supabase.rpc('solicitar', { p_tipo: tipo, p_alvo_id: alvoId, p_dados: dados, p_justificativa: j.data, p_anexo_path: anexo });
    setEnviando(false);
    if (error) { setErro(mensagemErro(error)); return; }
    setOk(true);
    aoEnviar?.();
  };

  return (
    <Dialogo aberto={aberto} fechar={fechar} titulo={titulo} acoes={ok
      ? <button type="button" className="botao" onClick={fechar}>Fechar</button>
      : <><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" disabled={enviando} onClick={enviar}>{enviando ? 'Enviando…' : 'Enviar para aprovação'}</button></>}>
      {ok ? <Aviso tom="sucesso">Pedido enviado. A Secretária ou o Administrador do sistema vai decidir.</Aviso> : (
        <div className="form">
          {aviso && <Aviso tom="info">{aviso}</Aviso>}
          {erro && <Aviso tom="critico">{erro}</Aviso>}
          {campos.map((c) => (
            <Campo key={c.chave} rotulo={c.rotulo}>
              {c.tipo === 'select' ? (
                <select value={valores[c.chave] ?? ''} onChange={(e) => setValores({ ...valores, [c.chave]: e.target.value })}>
                  <option value="">Selecione…</option>
                  {c.opcoes?.map((o) => <option key={o.valor} value={o.valor}>{o.rotulo}</option>)}
                </select>
              ) : (
                <input type={c.tipo === 'data' ? 'date' : 'text'} maxLength={c.max ?? 200} value={valores[c.chave] ?? ''} onChange={(e) => setValores({ ...valores, [c.chave]: e.target.value })} />
              )}
            </Campo>
          ))}
          <Campo rotulo="Justificativa"><textarea rows={3} maxLength={2000} value={just} onChange={(e) => setJust(e.target.value)} /></Campo>
          <Campo rotulo="Anexo (opcional)" ajuda="PDF, PNG ou JPG até 10 MB.">
            <input type="file" accept="application/pdf,image/png,image/jpeg" onChange={(e) => setArquivo(e.target.files?.[0] ?? null)} />
          </Campo>
        </div>
      )}
    </Dialogo>
  );
}
