import type { Metadata, Viewport } from 'next';
import '@fontsource/ibm-plex-sans/400.css';
import '@fontsource/ibm-plex-sans/500.css';
import '@fontsource/ibm-plex-sans/600.css';
import '@fontsource/ibm-plex-sans/700.css';
import './globals.css';
import { Providers } from './providers';

const base = process.env.NEXT_PUBLIC_BASE_PATH ?? '';

export const metadata: Metadata = {
  title: 'Gestão SEMFAZ',
  description: 'Gestão SEMFAZ — Prefeitura de Lagarto/SE',
  manifest: `${base}/manifest.webmanifest`,
  icons: { icon: `${base}/icons/logo.svg`, apple: `${base}/icons/icon-192.png` },
  appleWebApp: { capable: true, title: 'Gestão SEMFAZ', statusBarStyle: 'default' },
  robots: { index: false, follow: false },
  referrer: 'strict-origin-when-cross-origin',
};

export const viewport: Viewport = { themeColor: '#18215A', width: 'device-width', initialScale: 1 };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR">
      <head>
        {/* anti-clickjacking (GitHub Pages não envia frame-ancestors) */}
        <script src={`${base}/anti-frame.js`} />
      </head>
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
