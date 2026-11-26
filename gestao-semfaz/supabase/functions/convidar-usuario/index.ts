// Convida usuário (sem cadastro público). Valida token, permissão, corpo e limite de requisições.
// A gravação em public.usuarios é feita pela RPC registrar_convite COM O TOKEN de quem convida
// (auditoria registra o autor real). service-role só aqui, no servidor.
import { createClient } from 'npm:@supabase/supabase-js@2.119.2';
import { cabecalhosCors, ehUuid, falha, lerJson, ORIGEM_PERMITIDA, resposta } from '../_shared/http.ts';

const URL_SUPA = Deno.env.get('SUPABASE_URL')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const PERFIS = ['administrador', 'secretaria', 'diretor', 'coordenador', 'funcionario'];

Deno.serve(async (req) => {
  const cors = cabecalhosCors(req);
  if (!cors) return falha(403, null, 'Origem não permitida.');
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (req.method !== 'POST') return falha(405, cors);

  const auth = req.headers.get('authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return falha(401, cors, 'Sessão inválida.');

  const usuario = createClient(URL_SUPA, ANON, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const admin = createClient(URL_SUPA, SERVICE, { auth: { persistSession: false } });

  const { data: quem, error: eUser } = await usuario.auth.getUser();
  if (eUser || !quem.user) return falha(401, cors, 'Sessão inválida.');

  const { data: pode } = await usuario.rpc('pode_convidar'); // exige secretária/admin ativo com MFA (aal2)
  if (pode !== true) return falha(403, cors, 'Sem permissão para convidar.');

  const { data: dentroDoLimite } = await admin.rpc('consumir_limite', { p_chave: `convite:${quem.user.id}`, p_maximo: 20, p_janela_segundos: 3600 });
  if (dentroDoLimite !== true) return falha(429, cors, 'Muitos convites em pouco tempo. Tente mais tarde.');

  const corpo = await lerJson(req);
  const servidorId = corpo?.servidor_id;
  const perfil = corpo?.perfil;
  const redirect = typeof corpo?.redirect_to === 'string' ? corpo.redirect_to : '';
  if (!ehUuid(servidorId) || typeof perfil !== 'string' || !PERFIS.includes(perfil) || !redirect.startsWith(ORIGEM_PERMITIDA + '/')) {
    return falha(400, cors, 'Dados inválidos.');
  }

  const { data: sv } = await admin.from('servidores').select('email_institucional, situacao').eq('id', servidorId).maybeSingle();
  if (!sv?.email_institucional || sv.situacao !== 'ativo') return falha(400, cors, 'Servidor inválido para convite.');

  const { data: convite, error: eConv } = await admin.auth.admin.inviteUserByEmail(sv.email_institucional, { redirectTo: redirect });
  if (eConv || !convite.user) return falha(400, cors, 'Não foi possível enviar o convite.');

  const { error: eReg } = await usuario.rpc('registrar_convite', { p_auth_id: convite.user.id, p_servidor: servidorId, p_perfil: perfil });
  if (eReg) {
    await admin.auth.admin.deleteUser(convite.user.id); // não deixa conta órfã
    return falha(400, cors, 'Não foi possível registrar o convite.');
  }
  return resposta(200, { ok: true }, cors);
});
