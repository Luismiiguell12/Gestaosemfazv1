// Copia o worker do pdf.js para public/ (servido pelo próprio site; CSP worker-src 'self').
import { copyFileSync } from 'node:fs';
copyFileSync(new URL('../node_modules/pdfjs-dist/build/pdf.worker.min.mjs', import.meta.url), new URL('../public/pdf.worker.min.mjs', import.meta.url));
