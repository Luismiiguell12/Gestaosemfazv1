import Link from 'next/link';

export default function NaoEncontrado() {
  return (
    <div className="auth-form" style={{ minHeight: '100vh' }}>
      <div className="auth-cartao"><h1>Página não encontrada</h1><Link href="/">Voltar ao painel</Link></div>
    </div>
  );
}
