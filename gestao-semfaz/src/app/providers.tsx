'use client';
import { useEffect, type ReactNode } from 'react';
import { SessaoProvider } from '@/lib/sessao';
import { basePath } from '@/lib/supabase';

export function Providers({ children }: { children: ReactNode }) {
  useEffect(() => {
    if ('serviceWorker' in navigator && process.env.NODE_ENV === 'production') {
      navigator.serviceWorker.register(`${basePath}/sw.js`, { scope: `${basePath}/` }).catch(() => undefined);
    }
  }, []);
  return <SessaoProvider>{children}</SessaoProvider>;
}
