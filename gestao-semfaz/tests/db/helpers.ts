import pg from 'pg';
import { afterAll, expect } from 'vitest';

export const U = {
  admin: '00000000-0000-0000-0000-00000000a001',
  sec: '00000000-0000-0000-0000-00000000a002',
  dirDat: '00000000-0000-0000-0000-00000000a003',
  dirDefc: '00000000-0000-0000-0000-00000000a004',
  coordCofit: '00000000-0000-0000-0000-00000000a005',
  coordConta: '00000000-0000-0000-0000-00000000a006',
  funcA: '00000000-0000-0000-0000-00000000a007',
  funcE: '00000000-0000-0000-0000-00000000a008',
  funcB: '00000000-0000-0000-0000-00000000a009',
} as const;
export type Quem = keyof typeof U | 'anon' | 'estranho';

const pool = new pg.Pool({ database: process.env.TEST_DB ?? 'gestao_semfaz_test', max: 4 });
afterAll(async () => { await pool.end(); });

export interface Ctx {
  /** troca a identidade (como a API faz com o JWT) */
  como(quem: Quem, aal?: 'aal1' | 'aal2'): Promise<void>;
  q<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T[]>;
  /** espera erro; desfaz só este comando */
  falha(sql: string, params?: unknown[], msg?: RegExp): Promise<string>;
  /** comando como superusuário (preparo de cenário) */
  sistema(sql: string, params?: unknown[]): Promise<Record<string, unknown>[]>;
  /** espera erro como superusuário (constraints/triggers) */
  sistemaFalha(sql: string, params?: unknown[], msg?: RegExp): Promise<string>;
}

/** Executa tudo numa transação desfeita no final (testes isolados). */
export async function cenario(fn: (c: Ctx) => Promise<void>) {
  const client = await pool.connect();
  let papel = 'authenticated';
  let claims = '{}';
  const aplicar = async () => {
    await client.query(`set local role ${papel}`);
    await client.query(`select set_config('request.jwt.claims', $1, true)`, [claims]);
  };
  const ctx: Ctx = {
    async como(quem, aal = 'aal2') {
      if (quem === 'anon') { papel = 'anon'; claims = JSON.stringify({ role: 'anon' }); }
      else {
        papel = 'authenticated';
        const sub = quem === 'estranho' ? '00000000-0000-0000-0000-0000000000ff' : U[quem];
        claims = JSON.stringify({ sub, role: 'authenticated', aal });
      }
      await aplicar();
    },
    async q(sql, params) { return (await client.query(sql, params)).rows; },
    async falha(sql, params, msg) {
      await client.query('savepoint t');
      try {
        await client.query(sql, params);
      } catch (e) {
        await client.query('rollback to savepoint t');
        await aplicar();
        const m = (e as Error).message;
        if (msg) expect(m).toMatch(msg);
        return m;
      }
      await client.query('rollback to savepoint t');
      throw new Error(`Era esperado erro, mas executou: ${sql}`);
    },
    async sistema(sql, params) {
      await client.query('reset role');
      const r = (await client.query(sql, params)).rows;
      await aplicar();
      return r;
    },
    async sistemaFalha(sql, params, msg) {
      await client.query('reset role');
      try { return await ctx.falha(sql, params, msg); } finally { await aplicar(); }
    },
  };
  try {
    await client.query('begin');
    await ctx.como('anon');
    await fn(ctx);
  } finally {
    await client.query('rollback');
    client.release();
  }
}

export const contar = async (c: Ctx, tabela: string) =>
  Number((await c.q<{ n: string }>(`select count(*) as n from ${tabela}`))[0].n);

export const idUnidade = async (c: Ctx, sigla: string) =>
  (await c.sistema('select id from public.unidades where sigla = $1', [sigla]))[0].id as string;

export const idServidor = async (c: Ctx, matricula: string) =>
  (await c.sistema('select id from public.servidores where matricula = $1', [matricula]))[0].id as string;
