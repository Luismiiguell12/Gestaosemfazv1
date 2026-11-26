import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import pg from 'pg';

// recria banco de teste do zero: shim + migrations + seed + usuários de teste
export default async function setup() {
  const root = resolve(__dirname, '../..');
  execFileSync('bash', [resolve(root, 'scripts/db-test-setup.sh')], { stdio: 'inherit', env: process.env });
  const client = new pg.Client({ database: process.env.TEST_DB ?? 'gestao_semfaz_test' });
  await client.connect();
  await client.query(readFileSync(resolve(__dirname, 'fixtures.sql'), 'utf8'));
  await client.end();
}
