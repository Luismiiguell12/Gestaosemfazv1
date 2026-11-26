import { z } from 'zod';

// Validação no cliente (o banco valida de novo — obrigatório).
export const PERFIS = ['administrador', 'secretaria', 'diretor', 'coordenador', 'funcionario'] as const;
export type Perfil = (typeof PERFIS)[number];
export const ROTULO_PERFIL: Record<Perfil, string> = {
  administrador: 'Administrador do sistema',
  secretaria: 'Secretária',
  diretor: 'Diretor',
  coordenador: 'Coordenador',
  funcionario: 'Funcionário',
};

export const email = z.string().trim().toLowerCase().email('E-mail inválido.').max(254);

export const senhaForte = z
  .string()
  .min(12, 'Mínimo de 12 caracteres.')
  .max(72, 'Máximo de 72 caracteres.')
  .regex(/[a-z]/, 'Inclua letra minúscula.')
  .regex(/[A-Z]/, 'Inclua letra maiúscula.')
  .regex(/[0-9]/, 'Inclua número.')
  .regex(/[^A-Za-z0-9]/, 'Inclua símbolo.');

export const login = z.object({ email, senha: z.string().min(1, 'Informe a senha.').max(72) });

export const matricula = z.string().trim().regex(/^[0-9A-Za-z./-]{1,20}$/, 'Matrícula obrigatória: até 20 caracteres (números, letras, ponto, barra ou hífen).');

export const uuid = z.string().uuid('Selecione uma opção.');

export const servidorNovo = z.object({
  nome_completo: z.string().trim().min(1, 'Informe o nome.').max(200),
  matricula,
  cargo_id: uuid,
  unidade_id: uuid,
  email_institucional: z.union([email, z.literal('')]).optional().transform((v) => (v ? v : null)),
});

export const ABRANGENCIAS = ['nacional', 'estadual', 'municipal', 'ponto_facultativo'] as const;
export const ROTULO_ABRANGENCIA: Record<(typeof ABRANGENCIAS)[number], string> = {
  nacional: 'Nacional', estadual: 'Estadual', municipal: 'Municipal', ponto_facultativo: 'Ponto facultativo',
};
export const feriado = z.object({
  data: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Data inválida.'),
  descricao: z.string().trim().min(1, 'Informe a descrição.').max(120),
  abrangencia: z.enum(ABRANGENCIAS),
});

export const justificativa = z.string().trim().min(5, 'Justificativa: mínimo de 5 caracteres.').max(2000);

export const TIPOS_UNIDADE = ['diretoria', 'coordenadoria', 'assessoria'] as const;
export const unidadeNova = z.object({
  sigla: z.string().trim().min(1, 'Informe a sigla.').max(40),
  nome: z.string().trim().min(1, 'Informe o nome.').max(200),
  tipo: z.enum(TIPOS_UNIDADE),
  unidade_pai_id: uuid,
});

export const termoBusca = z.string().trim().min(2).max(100);

/** primeiro erro legível de um safeParse */
export function primeiroErro(r: { success: boolean; error?: { issues: { message: string }[] } }): string | null {
  return r.success ? null : (r.error?.issues[0]?.message ?? 'Dados inválidos.');
}
