'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState, type FormEvent } from 'react';
import { AuthLayout } from '@/components/layout/AuthLayout';
import { Aviso, Campo } from '@/components/ui';
import { supabase } from '@/lib/supabase';
import { login, primeiroErro } from '@/lib/validacao';

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  const entrar = async (e: FormEvent) => {
    e.preventDefault();
    const r = login.safeParse({ email, senha });
    if (!r.success) { setErro(primeiroErro(r)); return; }
    setEnviando(true); setErro(null);
    const { error } = await supabase.auth.signInWithPassword({ email: r.data.email, password: r.data.senha });
    setEnviando(false);
    if (error) {
      // mensagem única: não revela se o e-mail existe
      setErro(error.status === 429 ? 'Muitas tentativas. Aguarde alguns minutos e tente de novo.' : 'E-mail ou senha incorretos, ou acesso não permitido.');
      return;
    }
    const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    router.replace(aal && aal.nextLevel === 'aal2' && aal.currentLevel !== 'aal2' ? '/mfa' : '/');
  };

  return (
    <AuthLayout>
      <form className="auth-cartao form" onSubmit={entrar} noValidate>
        <h1>Entrar</h1>
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        <Campo rotulo="E-mail institucional"><input type="email" autoComplete="username" value={email} onChange={(e) => setEmail(e.target.value)} required maxLength={254} /></Campo>
        <Campo rotulo="Senha"><input type="password" autoComplete="current-password" value={senha} onChange={(e) => setSenha(e.target.value)} required maxLength={72} /></Campo>
        <button type="submit" className="botao botao-primario" disabled={enviando}>{enviando ? 'Entrando…' : 'Entrar'}</button>
        <Link href="/recuperar-senha" style={{ fontSize: 13 }}>Esqueci minha senha</Link>
        <p className="nota">Não há cadastro público. Novos usuários entram somente por convite.</p>
      </form>
    </AuthLayout>
  );
}
