'use client';
import type { Session } from '@supabase/supabase-js';
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { supabase } from './supabase';
import type { Perfil } from './validacao';

export interface InfoSessao {
  autorizado: boolean;
  motivo?: 'sem_cadastro' | 'desativado';
  usuario_id?: string;
  servidor_id?: string;
  perfil?: Perfil;
  nome?: string;
  cargo?: string;
  unidade_id?: string;
  unidade_sigla?: string;
  mfa_exigida?: boolean;
  aal?: 'aal1' | 'aal2';
  sessao_ok?: boolean;
  modulos?: string[];
}

interface Ctx {
  carregando: boolean;
  session: Session | null;
  info: InfoSessao | null;
  recarregar: () => Promise<void>;
  sair: () => Promise<void>;
}

const SessaoCtx = createContext<Ctx | null>(null);

export function SessaoProvider({ children }: { children: ReactNode }) {
  const [carregando, setCarregando] = useState(true);
  const [session, setSession] = useState<Session | null>(null);
  const [info, setInfo] = useState<InfoSessao | null>(null);

  const carregarInfo = useCallback(async (s: Session | null) => {
    setSession(s);
    if (!s) { setInfo(null); setCarregando(false); return; }
    const { data, error } = await supabase.rpc('minha_sessao');
    setInfo(error ? { autorizado: false } : (data as InfoSessao));
    setCarregando(false);
  }, []);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => carregarInfo(data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((evento, s) => {
      if (evento === 'TOKEN_REFRESHED') { setSession(s); return; }
      void carregarInfo(s);
    });
    return () => sub.subscription.unsubscribe();
  }, [carregarInfo]);

  const valor = useMemo<Ctx>(() => ({
    carregando, session, info,
    recarregar: async () => { const { data } = await supabase.auth.getSession(); await carregarInfo(data.session); },
    sair: async () => { await supabase.auth.signOut(); setInfo(null); setSession(null); },
  }), [carregando, session, info, carregarInfo]);

  return <SessaoCtx.Provider value={valor}>{children}</SessaoCtx.Provider>;
}

export function useSessao() {
  const c = useContext(SessaoCtx);
  if (!c) throw new Error('SessaoProvider ausente');
  return c;
}

export const ehGestorGeral = (i: InfoSessao | null) => i?.perfil === 'administrador' || i?.perfil === 'secretaria';
export const ehChefia = (i: InfoSessao | null) => i?.perfil === 'diretor' || i?.perfil === 'coordenador';
export const temModulo = (i: InfoSessao | null, m: string) => Boolean(i?.modulos?.includes(m));
