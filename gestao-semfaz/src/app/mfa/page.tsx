'use client';
import { useRouter } from 'next/navigation';
import { useEffect, useState, type FormEvent } from 'react';
import { AuthLayout } from '@/components/layout/AuthLayout';
import { Aviso, Campo } from '@/components/ui';
import { supabase } from '@/lib/supabase';
import { useSessao } from '@/lib/sessao';

// Verificação em duas etapas (TOTP). Obrigatória p/ administrador e secretária (aplicado no banco).
export default function MfaPage() {
  const router = useRouter();
  const { session, carregando, info, recarregar, sair } = useSessao();
  const [fator, setFator] = useState<string | null>(null);
  const [qr, setQr] = useState<string | null>(null);
  const [segredo, setSegredo] = useState<string | null>(null);
  const [codigo, setCodigo] = useState('');
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    if (carregando) return;
    if (!session) { router.replace('/login'); return; }
    (async () => {
      const { data } = await supabase.auth.mfa.listFactors();
      const verificado = data?.totp?.find((f) => f.status === 'verified');
      if (verificado) { setFator(verificado.id); return; }
      for (const f of data?.all ?? []) if (f.status !== 'verified') await supabase.auth.mfa.unenroll({ factorId: f.id });
      const { data: novo, error } = await supabase.auth.mfa.enroll({ factorType: 'totp', friendlyName: 'Gestão SEMFAZ' });
      if (error || !novo?.totp) { setErro('Não foi possível iniciar a configuração.'); return; }
      setFator(novo.id);
      setQr(`data:image/svg+xml;utf-8,${encodeURIComponent(novo.totp.qr_code)}`);
      setSegredo(novo.totp.secret);
    })();
  }, [carregando, session, router]);

  const verificar = async (e: FormEvent) => {
    e.preventDefault();
    if (!fator || !/^\d{6}$/.test(codigo)) { setErro('Informe o código de 6 dígitos.'); return; }
    const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId: fator, code: codigo });
    if (error) { setErro('Código inválido ou expirado.'); return; }
    await recarregar();
    router.replace('/');
  };

  return (
    <AuthLayout>
      <form className="auth-cartao form" onSubmit={verificar} noValidate>
        <h1>Verificação em duas etapas</h1>
        {info?.mfa_exigida
          ? <Aviso tom="info">Obrigatória para o seu perfil. Sem ela, nenhum dado é liberado.</Aviso>
          : <Aviso tom="info">Recomendada para o seu perfil.</Aviso>}
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        {qr && (
          <>
            <p style={{ margin: 0, fontSize: 13 }}>Leia o QR code com um aplicativo autenticador (Google Authenticator, Microsoft Authenticator, Aegis…).</p>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <div className="qr"><img src={qr} alt="QR code para o aplicativo autenticador" width={180} height={180} /></div>
            <p className="nota">Sem câmera? Digite a chave: <code>{segredo}</code></p>
          </>
        )}
        <Campo rotulo="Código de 6 dígitos">
          <input inputMode="numeric" autoComplete="one-time-code" pattern="\d{6}" maxLength={6} value={codigo} onChange={(e) => setCodigo(e.target.value.replace(/\D/g, ''))} />
        </Campo>
        <button type="submit" className="botao botao-primario" disabled={!fator}>Verificar</button>
        <button type="button" className="botao" onClick={() => void sair().then(() => router.replace('/login'))}>Sair</button>
      </form>
    </AuthLayout>
  );
}
