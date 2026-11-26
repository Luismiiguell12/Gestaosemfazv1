// Service worker do Gestão SEMFAZ.
// Guarda SÓ arquivos estáticos do próprio site. Nunca guarda respostas da API (dados sigilosos).
const VERSAO = 'semfaz-v1';
const ESTATICO = /\/(_next\/static|icons|fonts)\/|\.(css|js|woff2?|png|svg|webmanifest)$/;

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== VERSAO).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
  const req = e.request;
  const url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== self.location.origin) return; // API/Supabase: sempre rede, sem cache
  if (req.mode === 'navigate') {
    // páginas: rede primeiro; offline mostra a página guardada (casca sem dados)
    e.respondWith(fetch(req).then((r) => { const c = r.clone(); caches.open(VERSAO).then((x) => x.put(req, c)); return r; }).catch(() => caches.match(req)));
    return;
  }
  if (ESTATICO.test(url.pathname)) {
    e.respondWith(caches.match(req).then((hit) => hit || fetch(req).then((r) => { if (r.ok) { const c = r.clone(); caches.open(VERSAO).then((x) => x.put(req, c)); } return r; })));
  }
});
