'use client';
import { useRouter } from 'next/navigation';
import { useEffect, useState, type FormEvent } from 'react';
import { AuthLayout } from '@/components/layout/AuthLayout';
import { Aviso, Campo } from '@/components/ui';
import { supabase } from '@/lib/supabase';
import { primeiroErro, senhaForte } from '@/lib/validacao';

// Usado pelo link de convite e pelo de recuperação de senha.
export default function DefinirSenhaPage() {
  const router = useRouter();
  const [pronto, setPronto] = useState<'carregando' | 'ok' | 'invalido'>('carregando');
  const [senha, setSenha] = useState('');
  const [confirma, setConfirma] = useState('');
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      const url = new URL(window.location.href);
      const code = url.searchParams.get('code');
      const hash = new URLSearchParams(url.hash.slice(1));
      if (code) await supabase.auth.exchangeCodeForSession(code);
      else if (hash.get('access_token') && hash.get('refresh_token')) {
        await supabase.auth.setSession({ access_token: hash.get('access_token')!, refresh_token: hash.get('refresh_token')! });
      }
      window.history.replaceState(null, '', url.pathname); // tira tokens da barra de endereço
      const { data } = await supabase.auth.getSession();
      setPronto(data.session ? 'ok' : 'invalido');
    })();
  }, []);

  const salvar = async (e: FormEvent) => {
    e.preventDefault();
    const r = senhaForte.safeParse(senha);
    if (!r.success) { setErro(primeiroErro(r)); return; }
    if (senha !== confirma) { setErro('As senhas não conferem.'); return; }
    const { error } = await supabase.auth.updateUser({ password: senha });
    if (error) { setErro('Não foi possível salvar a senha. Ela pode ser fraca ou já usada.'); return; }
    router.replace('/');
  };

  return (
    <AuthLayout>
      <form className="auth-cartao form" onSubmit={salvar} noValidate>
        <h1>Criar senha</h1>
        {pronto === 'carregando' && <p role="status">Validando link…</p>}
        {pronto === 'invalido' && <Aviso tom="critico">Link inválido ou expirado. Peça um novo convite ou use “Esqueci minha senha”.</Aviso>}
        {pronto === 'ok' && (
          <>
            {erro && <Aviso tom="critico">{erro}</Aviso>}
            <Campo rotulo="Nova senha" ajuda="Mínimo de 12 caracteres, com maiúscula, minúscula, número e símbolo.">
              <input type="password" autoComplete="new-password" value={senha} onChange={(e) => setSenha(e.target.value)} maxLength={72} />
            </Campo>
            <Campo rotulo="Confirme a senha"><input type="password" autoComplete="new-password" value={confirma} onChange={(e) => setConfirma(e.target.value)} maxLength={72} /></Campo>
            <button type="submit" className="botao botao-primario">Salvar senha</button>
          </>
        )}
      </form>
    </AuthLayout>
  );
}
