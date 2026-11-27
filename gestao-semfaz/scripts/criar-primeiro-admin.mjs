#!/usr/bin/env node
// Cria o PRIMEIRO administrador (uso local, uma vez). Recusa se já existir administrador.
// Requer no ambiente (nunca em arquivo versionado): SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY.
// Uso: node scripts/criar-primeiro-admin.mjs --email admin@... --nome "Nome" --matricula 000000 --cargo "Analista de Sistemas" --unidade ASTIN --vinculo efetivo
// A senha é pedida no terminal (não aparece no histórico do shell).
import { createClient } from '@supabase/supabase-js';
import { createInterface } from 'node:readline';
import { parseArgs } from 'node:util';

const { values: a } = parseArgs({ options: { email: { type: 'string' }, nome: { type: 'string' }, matricula: { type: 'string' }, cargo: { type: 'string' }, unidade: { type: 'string' } } });
const url = process.env.SUPABASE_URL;
const chave = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !chave) { console.error('Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no ambiente.'); process.exit(1); }
for (const k of ['email', 'nome', 'matricula', 'cargo', 'unidade', 'vinculo']) if (!a[k]) { console.error(`Informe --${k}`); process.exit(1); }
if (!['efetivo', 'comissionado', 'temporario'].includes(a.vinculo)) { console.error('--vinculo deve ser efetivo, comissionado ou temporario'); process.exit(1); }

const perguntarSenha = () => new Promise((ok) => {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  rl._writeToOutput = (s) => { if (s.includes('Senha')) process.stdout.write(s); };
  rl.question('Senha (mín. 12, maiúscula, minúscula, número e símbolo): ', (s) => { rl.close(); process.stdout.write('\n'); ok(s); });
});

const db = createClient(url, chave, { auth: { persistSession: false } });
const { count } = await db.from('usuarios').select('id', { count: 'exact', head: true }).eq('perfil', 'administrador');
if (count) { console.error('Já existe administrador. Use o convite pelo sistema.'); process.exit(1); }

const senha = await perguntarSenha();
if (!/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{12,72}$/.test(senha)) { console.error('Senha fraca.'); process.exit(1); }

const { data: un } = await db.from('unidades').select('id').eq('sigla', a.unidade).single();
const { data: cg } = await db.from('cargos').select('id').eq('nome', a.cargo).single();
if (!un || !cg) { console.error('Unidade ou cargo não encontrado.'); process.exit(1); }

const { data: sv, error: e1 } = await db.from('servidores')
  .insert({ nome_completo: a.nome, matricula: a.matricula, cargo_id: cg.id, unidade_id: un.id, email_institucional: a.email.toLowerCase(), tipo_vinculo: a.vinculo })
  .select('id').single();
if (e1) { console.error('Falha ao criar servidor (matrícula ou e-mail já existe?).'); process.exit(1); }

const { data: au, error: e2 } = await db.auth.admin.createUser({ email: a.email.toLowerCase(), password: senha, email_confirm: true });
if (e2) { await db.from('servidores').delete().eq('id', sv.id); console.error('Falha ao criar login.'); process.exit(1); }

const { error: e3 } = await db.from('usuarios').insert({ id: au.user.id, servidor_id: sv.id, perfil: 'administrador' });
if (e3) { console.error('Falha ao vincular usuário.'); process.exit(1); }
console.log('Administrador criado. No primeiro acesso, configure a verificação em duas etapas (obrigatória).');
