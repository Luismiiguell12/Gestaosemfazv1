'use client';
import { useCallback, useEffect, useState } from 'react';
import { mensagemErro } from './erros';

/** carrega dados com estado de carregamento/erro; `recarregar` refaz a consulta */
export function useConsulta<T>(fn: () => Promise<{ data: T | null; error: unknown }>, deps: unknown[] = []) {
  const [dados, setDados] = useState<T | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(true);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const executar = useCallback(fn, deps);

  const recarregar = useCallback(async () => {
    setCarregando(true);
    const { data, error } = await executar();
    if (error) { setErro(mensagemErro(error)); setDados(null); } else { setErro(null); setDados(data); }
    setCarregando(false);
  }, [executar]);

  useEffect(() => { void recarregar(); }, [recarregar]);
  return { dados, erro, carregando, recarregar };
}
