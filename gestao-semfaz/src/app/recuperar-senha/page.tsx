'use client';
import Link from 'next/link';
import { useState, type FormEvent } from 'react';
import { AuthLayout } from '@/components/layout/AuthLayout';
import { Aviso, Campo } from '@/components/ui';
import { siteUrl, supabase } from '@/lib/supabase';
import { email as emailSchema } from '@/lib/validacao';

export default function RecuperarSenhaPage() {
  const [email, setEmail] = useState('');
  const [enviado, setEnviado] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  const enviar = async (e: FormEvent) => {
    e.preventDefault();
    const r = emailSchema.safeParse(email);
    if (!r.success) { setErro('E-mail inválido.'); return; }
    await supabase.auth.resetPasswordForEmail(r.data, { redirectTo: `${siteUrl()}/definir-senha/` });
    setEnviado(true); // mesma resposta exista ou não o e-mail
  };

  return (
    <AuthLayout>
      <form className="auth-cartao form" onSubmit={enviar} noValidate>
        <h1>Recuperar senha</h1>
        {enviado ? (
          <Aviso tom="sucesso">Se o e-mail estiver cadastrado, você receberá um link para criar nova senha.</Aviso>
        ) : (
          <>
            {erro && <Aviso tom="critico">{erro}</Aviso>}
            <Campo rotulo="E-mail institucional"><input type="email" autoComplete="username" value={email} onChange={(e) => setEmail(e.target.value)} maxLength={254} /></Campo>
            <button type="submit" className="botao botao-primario">Enviar link</button>
          </>
        )}
        <Link href="/login" style={{ fontSize: 13 }}>Voltar ao login</Link>
      </form>
    </AuthLayout>
  );
}
