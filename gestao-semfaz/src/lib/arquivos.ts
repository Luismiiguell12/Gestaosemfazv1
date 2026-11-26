// Checa o tipo REAL do arquivo pela assinatura (não pela extensão/nome).
export type TipoArquivo = 'pdf' | 'png' | 'jpg';
export const TAMANHO_MAX = 10 * 1024 * 1024;
export const MIME: Record<TipoArquivo, string> = { pdf: 'application/pdf', png: 'image/png', jpg: 'image/jpeg' };

export function detectarTipo(b: Uint8Array): TipoArquivo | null {
  if (b.length >= 5 && b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46 && b[4] === 0x2d) return 'pdf'; // %PDF-
  if (b.length >= 8 && [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((v, i) => b[i] === v)) return 'png';
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'jpg';
  return null;
}

export async function validarAnexo(arquivo: File): Promise<{ ok: true; tipo: TipoArquivo } | { ok: false; erro: string }> {
  if (arquivo.size === 0) return { ok: false, erro: 'Arquivo vazio.' };
  if (arquivo.size > TAMANHO_MAX) return { ok: false, erro: 'Arquivo maior que 10 MB.' };
  const tipo = detectarTipo(new Uint8Array(await arquivo.slice(0, 16).arrayBuffer()));
  if (!tipo) return { ok: false, erro: 'Tipo não aceito. Envie PDF, PNG ou JPG.' };
  return { ok: true, tipo };
}

/** nome gerado pelo sistema, nunca o nome original */
export const caminhoAnexoAprovacao = (usuarioId: string, tipo: TipoArquivo) =>
  `aprovacoes/${usuarioId}/${crypto.randomUUID()}.${tipo}`;
