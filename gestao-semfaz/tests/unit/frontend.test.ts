import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { detectarTipo } from '@/lib/arquivos';
import { mensagemErro } from '@/lib/erros';
import { agruparParaPainel, arvore, caminho, type Unidade } from '@/lib/estrutura';
import { dataCurta, iniciais } from '@/lib/formato';
import { feriado, login, matricula, senhaForte, servidorNovo } from '@/lib/validacao';

describe('validação no cliente', () => {
  it('senha forte', () => {
    expect(senhaForte.safeParse('curta').success).toBe(false);
    expect(senhaForte.safeParse('semsimbolo12345A').success).toBe(false);
    expect(senhaForte.safeParse('Senha-Forte-2026').success).toBe(true);
  });
  it('matrícula obrigatória no formato do banco', () => {
    expect(matricula.safeParse('').success).toBe(false);
    expect(matricula.safeParse('   ').success).toBe(false);
    expect(matricula.safeParse('12 34').success).toBe(false);
    expect(matricula.safeParse('000101').success).toBe(true);
    expect(matricula.safeParse('1'.repeat(21)).success).toBe(false);
  });
  it('servidor novo: e-mail opcional vira null', () => {
    const base = { nome_completo: ' X ', matricula: '1', cargo_id: crypto.randomUUID(), unidade_id: crypto.randomUUID(), email_institucional: '', exerce_comissao: false };
    const r = servidorNovo.safeParse({ ...base, tipo_vinculo: 'efetivo' });
    expect(r.success && r.data.email_institucional).toBe(null);
    expect(servidorNovo.safeParse({ ...base, tipo_vinculo: '' }).success).toBe(false); // vínculo obrigatório (adendo 01)
  });
  it('login e feriado', () => {
    expect(login.safeParse({ email: 'nao-email', senha: 'x' }).success).toBe(false);
    expect(feriado.safeParse({ data: '2026-12-25', descricao: 'Natal', abrangencia: 'nacional' }).success).toBe(true);
    expect(feriado.safeParse({ data: '25/12/2026', descricao: 'Natal', abrangencia: 'nacional' }).success).toBe(false);
  });
});

describe('tipo real do arquivo (assinatura)', () => {
  const b = (...n: number[]) => new Uint8Array(n);
  it('reconhece PDF, PNG e JPG', () => {
    expect(detectarTipo(new TextEncoder().encode('%PDF-1.7'))).toBe('pdf');
    expect(detectarTipo(b(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))).toBe('png');
    expect(detectarTipo(b(0xff, 0xd8, 0xff, 0xe0))).toBe('jpg');
  });
  it('recusa executável/HTML renomeado', () => {
    expect(detectarTipo(new TextEncoder().encode('MZ\x90\x00'))).toBeNull();
    expect(detectarTipo(new TextEncoder().encode('<html><script>'))).toBeNull();
  });
});

describe('mensagens de erro sem detalhes internos', () => {
  it('esconde SQL/constraint', () => {
    expect(mensagemErro({ message: 'duplicate key value violates unique constraint "servidores_matricula_uk"', code: '23505' })).toBe('Já existe um registro com esses dados.');
    expect(mensagemErro({ message: 'permission denied for table servidores', code: '42501' })).toBe('Você não tem permissão para esta ação.');
    expect(mensagemErro(new Error('TypeError: x is undefined'))).toBe('Não foi possível concluir. Tente novamente.');
  });
  it('mostra mensagens próprias do sistema', () => {
    expect(mensagemErro({ message: 'Ninguém aprova o próprio pedido.', code: '42501' })).toBe('Ninguém aprova o próprio pedido.');
  });
});

describe('estrutura organizacional', () => {
  const U = (id: string, sigla: string, tipo: Unidade['tipo'], pai: string | null, ordem = 0): Unidade => ({ id, sigla, nome: sigla, tipo, unidade_pai_id: pai, ordem, ativa: true });
  const todas = [U('g', 'Gabinete', 'gabinete', null), U('a', 'ASPLAN', 'assessoria', 'g', 1), U('d', 'DAT', 'diretoria', 'g', 5), U('c', 'COFIT', 'coordenadoria', 'd', 1)];
  it('agrupa como o painel', () => {
    const g = agruparParaPainel(todas);
    expect(g.map((x) => x.nome)).toEqual(['DAT · DAT', 'Ligadas ao Gabinete']);
    expect(g[1].unidades.map((u) => u.sigla)).toEqual(['Gabinete', 'ASPLAN']);
  });
  it('respeita escopo', () => {
    expect(agruparParaPainel(todas, new Set(['c'])).map((x) => x.unidades.map((u) => u.sigla))).toEqual([['COFIT']]);
  });
  it('árvore e caminho', () => {
    expect(arvore(todas).map((l) => `${l.nivel}${l.u.sigla}`)).toEqual(['0Gabinete', '1ASPLAN', '1DAT', '2COFIT']);
    expect(caminho(todas, 'c').map((u) => u.sigla)).toEqual(['Gabinete', 'DAT', 'COFIT']);
  });
  it('formatos', () => {
    expect(dataCurta('2026-12-25')).toBe('25/12/2026');
    expect(iniciais('Servidor Alfa Beta')).toBe('SB');
  });
});

describe('segurança do código do frontend', () => {
  const raiz = resolve(__dirname, '../..');
  const arquivos = (d: string): string[] => readdirSync(d).flatMap((n) => {
    const p = join(d, n);
    return statSync(p).isDirectory() ? arquivos(p) : [p];
  });
  const codigo = [...arquivos(join(raiz, 'src')), ...arquivos(join(raiz, 'public'))].filter((f) => /\.(tsx?|js|json|webmanifest)$/.test(f));
  it('sem service-role, segredos ou HTML não sanitizado no frontend', () => {
    for (const f of codigo) {
      const t = readFileSync(f, 'utf8');
      expect(t, f).not.toMatch(/service_role|SERVICE_ROLE|sb_secret_|eyJhbGciOi/);
      expect(t, f).not.toMatch(/dangerouslySetInnerHTML|innerHTML\s*=/);
    }
  });
  it('.env fora do Git', () => {
    expect(readFileSync(join(raiz, '.gitignore'), 'utf8')).toMatch(/^\.env$/m);
  });
});

import { qrCodeSrc } from '@/lib/qrcode';
describe('QR code do MFA', () => {
  const svg = '<svg xmlns="http://www.w3.org/2000/svg"><path fill="#000" d="M0 0h1"/></svg>';
  const esperado = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
  it('aceita SVG puro', () => expect(qrCodeSrc(svg)).toBe(esperado));
  it('aceita data URL já pronta (formato atual do Supabase), sem prefixo duplicado', () => {
    expect(qrCodeSrc(`data:image/svg+xml;utf-8,${svg}`)).toBe(esperado);
    expect(qrCodeSrc(`data:image/svg+xml;utf-8,${encodeURIComponent(svg)}`)).toBe(esperado);
  });
});
