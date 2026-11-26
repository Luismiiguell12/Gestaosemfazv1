// Anti-clickjacking: GitHub Pages não permite o cabeçalho frame-ancestors.
(function () {
  if (window.top !== window.self) {
    document.documentElement.style.display = 'none';
    try { window.top.location = window.self.location.href; } catch (e) { /* bloqueado: segue oculto */ }
  }
})();
