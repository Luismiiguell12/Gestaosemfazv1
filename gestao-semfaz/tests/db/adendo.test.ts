import { describe, expect, it } from 'vitest';
import { cenario, idServidor, idUnidade } from './helpers';

// Adendo 01, seção 2: campos de elegibilidade criados antes da Fase 5
describe('adendo produtividade · cadastro de servidores e cargos', () => {
  it('vínculo obrigatório em cadastro novo; elegibilidade calculada pelo banco', async () => {
    await cenario(async (c) => {
      const cofit = await idUnidade(c, 'COFIT');
      const cargo = (await c.sistema(`select id from public.cargos where nome = 'Auditor Fiscal'`))[0].id;
      await c.como('sec');
      const ins = (mat: string, v: string | null) => c.q(`insert into public.servidores (nome_completo, matricula, cargo_id, unidade_id, tipo_vinculo) values ('Novo', $1, $2, $3, $4::public.tipo_vinculo)`, [mat, cargo, cofit, v]);
      await c.falha(`insert into public.servidores (nome_completo, matricula, cargo_id, unidade_id) values ('Novo', '900001', $1, $2)`, [cargo, cofit], /tipo de vínculo/);
      await ins('900002', 'efetivo'); await ins('900003', 'comissionado'); await ins('900004', 'temporario');
      const el = await c.q<{ matricula: string; e: boolean }>(`select s.matricula, public.elegivel_adicional(s) e from public.servidores s where matricula like '90000%' order by 1`);
      expect(el.map((x) => `${x.matricula}:${x.e}`)).toEqual(['900002:true', '900003:false', '900004:false']);
      // carreira excluída tira a elegibilidade; elegível não pode ser digitado (não é coluna)
      await c.sistema(`update public.cargos set carreira_excluida = true where id = $1`, [cargo]);
      expect((await c.q<{ e: boolean }>(`select public.elegivel_adicional(s) e from public.servidores s where matricula = '900002'`))[0].e).toBe(false);
      await c.falha(`update public.servidores set tipo_vinculo = 'efetivo'`, [], /permission denied/);
      // servidor antigo sem vínculo: não elegível e não pode voltar a ficar vazio depois de informado
      await c.sistema(`set local session_replication_role = replica`); // simula cadastro anterior ao adendo
      await c.sistema(`update public.servidores set tipo_vinculo = null where matricula = '000102'`);
      await c.sistema(`set local session_replication_role = origin`);
      expect((await c.q<{ e: boolean }>(`select public.elegivel_adicional(s) e from public.servidores s where matricula = '000102'`))[0].e).toBe(false);
      await c.sistemaFalha(`update public.servidores set tipo_vinculo = null where matricula = '000101'`, [], /tipo de vínculo/);
    });
  });

  it('alterar vínculo, função de confiança e carreira excluída passa pela aprovação', async () => {
    await cenario(async (c) => {
      await c.como('coordCofit');
      const s = (await c.q<{ id: string }>(`select public.solicitar('servidor_alterar', $1, $2, 'Ajuste do vínculo conforme portaria') as id`,
        [await idServidor(c, '000102'), JSON.stringify({ tipo_vinculo: 'temporario', exerce_comissao: true })]))[0].id;
      await c.como('sec');
      await c.q('select public.decidir_solicitacao($1, true)', [s]);
      expect((await c.sistema(`select tipo_vinculo::text t, exerce_comissao from public.servidores where matricula = '000102'`))[0]).toEqual({ t: 'temporario', exerce_comissao: true });
      const cargo = (await c.sistema(`select id from public.cargos where nome = 'Auditor Fiscal'`))[0].id;
      const p = (await c.q<{ id: string }>(`select public.solicitar('cargo_alterar', $1, $2, 'Carreira excluída pelo § 3º') as id`, [cargo, JSON.stringify({ carreira_excluida: true })]))[0].id;
      const n = (await c.q<{ id: string }>(`select public.solicitar('cargo_criar', null, $1, 'Cargo novo de carreira excluída') as id`, [JSON.stringify({ nome: 'Cargo Exemplo X', carreira_excluida: true })]))[0].id;
      await c.como('admin');
      await c.q('select public.decidir_solicitacao($1, true)', [p]);
      await c.q('select public.decidir_solicitacao($1, true)', [n]);
      expect((await c.sistema(`select count(*)::int n from public.cargos where carreira_excluida`))[0].n).toBe(2);
    });
  });

  it('importação exige tipo de vínculo; função de confiança aceita sim/não', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      const base = { nome: 'Fulano Teste', cargo: 'Auditor Fiscal', unidade: 'COFIT', email: '', ferias: '0', licenca_premio: '0', folgas: '0' };
      const e = await c.q<{ linha: number; campo: string }>('select * from public.importar_servidores_previa($1)', [JSON.stringify([
        { linha: 2, ...base, matricula: '910001', tipo_vinculo: '' },
        { linha: 3, ...base, matricula: '910002', tipo_vinculo: 'Efetivo', exerce_comissao: 'talvez' },
        { linha: 4, ...base, matricula: '910003', tipo_vinculo: 'Temporário', exerce_comissao: 'Não' }])]);
      expect(e.map((x) => `${x.linha}:${x.campo}`)).toEqual(['2:tipo_vinculo', '3:exerce_comissao']);
      await c.q('select public.importar_servidores($1)', [JSON.stringify([{ linha: 2, ...base, matricula: '910004', tipo_vinculo: 'efetivo', exerce_comissao: 'sim' }])]);
      expect((await c.sistema(`select tipo_vinculo::text t, exerce_comissao from public.servidores where matricula = '910004'`))[0]).toEqual({ t: 'efetivo', exerce_comissao: true });
    });
  });
});
