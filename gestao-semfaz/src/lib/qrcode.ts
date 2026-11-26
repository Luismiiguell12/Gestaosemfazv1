/**
 * Monta o src da imagem do QR code do TOTP.
 * O Supabase pode devolver o SVG puro ou já como data URL (versões novas);
 * aceita os dois e sempre codifica o SVG (evita quebrar com '#', '%' etc.).
 */
export function qrCodeSrc(qr: string): string {
  const svg = qr.startsWith('data:') ? decodeSvg(qr.slice(qr.indexOf(',') + 1)) : qr;
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
}

function decodeSvg(p: string): string {
  try { return decodeURIComponent(p); } catch { return p; }
}
