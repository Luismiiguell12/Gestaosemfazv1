import { describe, expect, it } from 'vitest';
import { cenario, idServidor, idUnidade, U, type Ctx } from './helpers';

const n = async (c: Ctx, sql: string, p: unknown[] = []) => Number(Object.values((await c.q(sql, p))[0])[0]);

async function demanda(c: Ctx, sigla: string, mat: string, titulo: string) {
  await c.como(sigla === 'COFIT' ? 'coordCofit' : 'coordConta');
  return (await c.q<{ id: string }>('select public.criar_demanda($1, $2) as id',
    [JSON.stringify({ titulo, unidade_id: await idUnidade(c, sigla), prazo: '2026-01-15' }), [await idServidor(c, mat)]]))[0].id;
}

describe('relatórios: escopo igual ao das telas', () => {
  it('demandas: secretária vê tudo; coordenador só a unidade; funcionário sem módulo relatórios não vê', async () => {
    await cenario(async (c) => {
      await demanda(c, 'COFIT', '000101', 'Demanda COFIT');
      await demanda(c, 'COFIT', '000102', 'Outra COFIT');
      await demanda(c, 'CONTA', '000201', 'Demanda CONTA');
      await c.como('sec');
      const tudo = await c.q<{ unidade: string; abertas: number; atrasadas: number; criadas_periodo: number }>(
        `select * from public.relatorio_demandas_unidade(current_date - 1, current_date)`);
      expect(tudo.map((x) => `${x.unidade}:${x.abertas}`).sort()).toEqual(['COFIT:2', 'CONTA:1']);
      expect(tudo.every((x) => x.atrasadas === x.abertas && x.criadas_periodo === x.abertas)).toBe(true);
      await c.como('coordCofit');
      expect((await c.q<{ unidade: string }>(`select * from public.relatorio_demandas_unidade(current_date - 1, current_date)`)).map((x) => x.unidade)).toEqual(['COFIT']);
      const ps = await c.q<{ servidor: string; abertas: number }>(`select * from public.relatorio_demandas_servidor(current_date - 1, current_date)`);
      expect(ps.map((x) => x.servidor).sort()).toEqual(['Servidor A', 'Servidor E']);
      await c.como('funcA'); // pacote provisório do funcionário não inclui relatórios
      expect(await n(c, `select count(*) from public.relatorio_demandas_unidade(current_date - 1, current_date)`)).toBe(0);
      await c.falha(`select public.registrar_exportacao('demandas_unidade', 'X', 'csv', '{}', 1)`, [], /Sem permissão/);
      await c.como('anon');
      await c.falha(`select * from public.relatorio_demandas_unidade(current_date, current_date)`, [], /permission denied/);
    });
  });

  it('contratos e faturas exigem o módulo; auditoria só secretária/admin', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      const id = (await c.q<{ id: string }>('select public.criar_contrato($1, $2) as id', [
        JSON.stringify({ numero: '1/2026', imovel_descricao: 'Sala', inicio: '2026-01-01', fim: (await c.q<{ d: string }>(`select (current_date + 40)::text d`))[0].d, valor_mensal: 1000 }),
        JSON.stringify({ tipo: 'PF', nome: 'Locador Fictício', documento: '52998224725' })]))[0].id;
      const uc = (await c.q<{ id: string }>(`select public.criar_uc('igua', '998877', $1) as id`, [id]))[0].id;
      await c.q(`select public.lancar_fatura($1, '2026-02-01', 80, '2026-02-20', 10)`, [uc]);
      expect(await n(c, `select count(*) from public.relatorio_contratos()`)).toBe(1);
      expect(await n(c, `select count(*) from public.relatorio_contratos_vencer(30)`)).toBe(0);
      expect(await n(c, `select count(*) from public.relatorio_contratos_vencer(60)`)).toBe(1);
      expect(await n(c, `select count(*) from public.relatorio_alugueis('2026-01-01', '2026-03-01', 'vencidos')`)).toBe(3);
      expect(await n(c, `select count(*) from public.relatorio_faturas('2026-01-01', '2026-12-01', null, true)`)).toBe(1);
      const g = (await c.q<{ aluguel: string; agua: string; total: string }>(`select * from public.relatorio_gasto_contrato('2026-02-01', '2026-02-01')`))[0];
      expect([Number(g.aluguel), Number(g.agua), Number(g.total)]).toEqual([1000, 80, 1080]);
      const aud = await c.q<{ autor: string }>(`select * from public.relatorio_auditoria(current_date - 1, current_date + 1, 'contratos')`);
      expect(aud.length).toBeGreaterThan(0);
      expect(aud[0].autor).toBe('Secretária Exemplo');
      for (const q of ['coordCofit', 'dirDat'] as const) {
        await c.como(q);
        expect(await n(c, `select count(*) from public.relatorio_contratos('todos')`)).toBe(0);
        expect(await n(c, `select count(*) from public.relatorio_faturas('2026-01-01', '2026-12-01')`)).toBe(0);
        await c.falha(`select * from public.relatorio_auditoria(current_date, current_date)`, [], /Somente a Secretária/);
      }
    });
  });

  it('férias e saldos: escopo da unidade; folhas por competência', async () => {
    await cenario(async (c) => {
      await c.sistema(`insert into public.saldos_servidor (servidor_id, ferias_dias) select id, 30 from public.servidores where situacao = 'ativo'`);
      await c.como('coordCofit');
      const s = await c.q<{ unidade: string }>(`select * from public.relatorio_saldos()`);
      expect(s.length).toBeGreaterThan(0);
      expect(new Set(s.map((x) => x.unidade))).toEqual(new Set(['COFIT']));
      await c.como('sec');
      expect(new Set((await c.q<{ unidade: string }>(`select * from public.relatorio_saldos()`)).map((x) => x.unidade)).size).toBeGreaterThan(1);
      expect(await n(c, `select count(*) from public.relatorio_folhas('2026-10-01', '2026-11-01')`)).toBeGreaterThan(0);
      expect(await n(c, `select count(*) from public.relatorio_escala_ferias(2026)`)).toBeGreaterThanOrEqual(0);
    });
  });
});

describe('exportações: auditadas, histórico próprio e limite por hora', () => {
  it('registra na auditoria e no histórico; outro usuário não vê; respeita o limite', async () => {
    await cenario(async (c) => {
      await c.como('coordCofit');
      await c.q(`select public.registrar_exportacao('saldos', 'Saldos de férias e folgas', 'xlsx', '{"unidade":"COFIT"}', 5)`);
      expect(await n(c, 'select count(*) from public.exportacoes')).toBe(1);
      await c.falha(`select public.registrar_exportacao('saldos', 'X', 'docx', '{}', 5)`, [], /inválidos/);
      await c.falha(`update public.exportacoes set linhas = 0`, [], /permission denied/);
      await c.como('sec');
      expect(await n(c, 'select count(*) from public.exportacoes')).toBe(0);
      expect(await n(c, `select count(*) from public.auditoria where acao = 'exportacao' and ator_id = $1`, [U.coordCofit])).toBe(1);
      await c.sistema(`update public.configuracoes set valor = '2' where chave = 'relatorios.exportacoes_por_hora'`);
      await c.q(`select public.registrar_exportacao('contratos', 'Contratos', 'pdf', '{}', 0)`);
      await c.q(`select public.registrar_exportacao('contratos', 'Contratos', 'csv', '{}', 0)`);
      await c.falha(`select public.registrar_exportacao('contratos', 'Contratos', 'csv', '{}', 0)`, [], /Limite de exportações/);
    });
  });
});
