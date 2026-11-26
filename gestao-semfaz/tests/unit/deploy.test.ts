import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
// @ts-expect-error script .mjs sem tipos
import { gerar } from '../../scripts/gerar-sql-unico.mjs';

describe('arquivo único p/ SQL Editor (web)', () => {
  it('está em dia com as migrations (rode: node scripts/gerar-sql-unico.mjs)', () => {
    expect(readFileSync(resolve(__dirname, '../../supabase/deploy/banco-completo.sql'), 'utf8')).toBe(gerar());
  });
});
