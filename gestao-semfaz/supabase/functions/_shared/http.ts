// Utilitários das Edge Functions: CORS restrito, respostas e erros genéricos.
export const ORIGEM_PERMITIDA = Deno.env.get('ALLOWED_ORIGIN') ?? '';

export function cabecalhosCors(req: Request): Record<string, string> | null {
  const origem = req.headers.get('origin') ?? '';
  if (!ORIGEM_PERMITIDA || origem !== ORIGEM_PERMITIDA) return null;
  return {
    'Access-Control-Allow-Origin': ORIGEM_PERMITIDA,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '600',
    Vary: 'Origin',
  };
}

export function resposta(status: number, corpo: Record<string, unknown>, cors: Record<string, string> | null) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...(cors ?? {}) },
  });
}

/** erro genérico: nunca devolve detalhes internos nem dados pessoais */
export const falha = (status: number, cors: Record<string, string> | null, mensagem = 'Não foi possível concluir.') =>
  resposta(status, { erro: mensagem }, cors);

export async function lerJson(req: Request, limiteBytes = 2048): Promise<Record<string, unknown> | null> {
  const texto = await req.text();
  if (texto.length > limiteBytes) return null;
  try {
    const v = JSON.parse(texto);
    return v && typeof v === 'object' && !Array.isArray(v) ? v : null;
  } catch {
    return null;
  }
}

export const ehUuid = (v: unknown): v is string =>
  typeof v === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
