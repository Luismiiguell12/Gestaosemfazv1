import type { ReactNode } from 'react';
import { Logo } from './Icone';

export function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <div className="auth-pagina">
      <aside className="auth-marca">
        <div className="menu-marca" style={{ padding: 0 }}>
          <Logo tamanho={44} />
          <div><div className="menu-marca-nome">Gestão SEMFAZ</div><div className="menu-marca-sub">Prefeitura de Lagarto/SE</div></div>
        </div>
        <p style={{ margin: 0, fontSize: 13, color: 'var(--cor-texto-menu-suave)' }}>Acesso restrito a servidores convidados da Secretaria Municipal da Fazenda.</p>
      </aside>
      <main className="auth-form">{children}</main>
    </div>
  );
}
