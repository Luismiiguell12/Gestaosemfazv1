import { createClient } from '@supabase/supabase-js';

// Só URL pública + anon key. Chave service-role NUNCA no frontend.
const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '';

export const supabaseConfigurado = Boolean(url && anonKey);

export const supabase = createClient(url || 'http://localhost:54321', anonKey || 'nao-configurado', {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false, flowType: 'pkce' },
});

export const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? '';
export const siteUrl = () => (typeof window === 'undefined' ? '' : window.location.origin + basePath);
