import { describe, expect, it } from 'vitest';
import { cenario, contar, U } from './helpers';

describe('auditoria imutável', () => {
  it('nem o superusuário altera ou apaga registros', async () => {
    await cenario(async (c) => {
      await c.sistemaFalha(`update public.auditoria set acao = 'x'`, [], /não podem ser alterados/);
      await c.sistemaFalha(`delete from public.auditoria`, [], /não podem ser alterados/);
      await c.sistemaFalha(`truncate public.auditoria`, [], /não podem ser alterados/);
    });
  });
  it('service_role também não altera', async () => {
    await cenario(async (c) => {
      await c.sistemaFalha(`set local role service_role; update public.auditoria set acao = 'x'`, [], /permission denied/);
    });
  });
  it('só secretária/admin leem; diretor e coordenador não', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      expect(await contar(c, 'public.auditoria')).toBeGreaterThan(0);
      await c.como('dirDat');
      expect(await contar(c, 'public.auditoria')).toBe(0);
    });
  });
});

describe('módulos: pacote padrão + extras', () => {
  it('extra vale na hora, é auditado e não muda o perfil', async () => {
    await cenario(async (c) => {
      await c.como('funcA');
      const antes = (await c.q<{ s: { modulos: string[]; perfil: string } }>('select public.minha_sessao() as s'))[0].s;
      expect(antes.modulos).not.toContain('contratos');
      await c.como('sec');
      await c.q(`select public.conceder_modulo_extra($1, 'contratos')`, [U.funcA]);
      const aud = await c.q<{ ator_id: string }>(`select ator_id from public.auditoria where tabela = 'usuario_modulos_extras' and acao = 'insert'`);
      expect(aud.map((a) => a.ator_id)).toEqual([U.sec]);
      expect((await c.q(`select * from public.solicitacoes`)).length).toBe(0);
      await c.como('funcA');
      const depois = (await c.q<{ s: { modulos: string[]; perfil: string } }>('select public.minha_sessao() as s'))[0].s;
      expect(depois.modulos).toContain('contratos');
      expect(depois.perfil).toBe('funcionario');
      // módulo extra não amplia escopo de dados
      expect(await contar(c, 'public.servidores')).toBe(1);
      await c.como('sec');
      await c.q(`select public.retirar_modulo_extra($1, 'contratos')`, [U.funcA]);
      await c.como('funcA');
      expect((await c.q<{ s: { modulos: string[] } }>('select public.minha_sessao() as s'))[0].s.modulos).not.toContain('contratos');
    });
  });
  it('pacote padrão é provisório (pendente definição oficial)', async () => {
    await cenario(async (c) => {
      const r = await c.sistema('select count(*)::int n from public.pacotes_padrao where not provisorio');
      expect(r[0].n).toBe(0);
    });
  });
  it('funcionário com módulo "usuarios" extra continua vendo só o próprio registro', async () => {
    await cenario(async (c) => {
      await c.sistema(`insert into public.usuario_modulos_extras values ($1, 'usuarios', $2, now())`, [U.funcA, U.sec]);
      await c.como('funcA');
      expect(await contar(c, 'public.servidores')).toBe(1);
    });
  });
});

describe('cadastro direto (sem aprovação)', () => {
  it('secretária cadastra feriado novo; diretor não', async () => {
    await cenario(async (c) => {
      await c.como('dirDat');
      await c.falha(`insert into public.feriados (data, descricao, abrangencia) values ('2027-07-08', 'Emancipação de Sergipe', 'estadual')`,
        [], /row-level security/);
      await c.como('sec');
      await c.q(`insert into public.feriados (data, descricao, abrangencia) values ('2027-07-08', 'Emancipação de Sergipe', 'estadual')`);
      await c.falha(`insert into public.feriados (data, descricao, abrangencia) values ('2027-07-08', 'Dup', 'estadual')`, [], /duplicate/);
    });
  });
});

describe('dias úteis', () => {
  it('ignora fins de semana e feriados cadastrados', async () => {
    await cenario(async (c) => {
      await c.como('funcA');
      // 24/12/2026 qui → 28/12 seg: 25 (Natal) e fim de semana não contam
      expect((await c.q<{ n: number }>(`select public.dias_uteis_entre('2026-12-24', '2026-12-28') as n`))[0].n).toBe(1);
      expect((await c.q<{ d: Date }>(`select public.somar_dias_uteis('2026-12-24', 1)::text as d`))[0].d).toBe('2026-12-28');
      expect((await c.q<{ d: string }>(`select public.somar_dias_uteis('2026-12-28', -1)::text as d`))[0].d).toBe('2026-12-24');
      expect((await c.q<{ n: number }>(`select public.dias_uteis_entre('2026-11-23', '2026-11-30') as n`))[0].n).toBe(5); // 24..27 + 30
    });
  });
});

describe('busca geral', () => {
  it('ignora acentos/maiúsculas e respeita permissões', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      const r = await c.q<{ tipo: string; titulo: string }>(`select * from public.busca_geral('juridica')`);
      expect(r.map((x) => x.titulo)).toContain('Jurídica');
      expect((await c.q(`select * from public.busca_geral('SERVIDOR b')`)).length).toBe(1);
      await c.como('coordCofit');
      expect((await c.q(`select * from public.busca_geral('servidor b')`)).length).toBe(0); // CONTA fora do escopo
      expect((await c.q(`select * from public.busca_geral('000101')`)).length).toBe(1);
      await c.como('funcA');
      const f = await c.q<{ tipo: string }>(`select * from public.busca_geral('servidor')`);
      expect(f.filter((x) => x.tipo === 'servidor').length).toBe(1); // só ele mesmo
    });
  });
  it('trata curingas como texto', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      expect((await c.q(`select * from public.busca_geral('%%')`)).length).toBe(0);
      expect((await c.q(`select * from public.busca_geral('__')`)).length).toBe(0);
    });
  });
});

describe('notificações', () => {
  it('cada um vê e marca só as próprias', async () => {
    await cenario(async (c) => {
      await c.sistema(`insert into public.notificacoes (usuario_id, tipo, titulo) values ($1, 't', 'A'), ($2, 't', 'B')`, [U.funcA, U.funcE]);
      await c.como('funcA');
      expect(await contar(c, 'public.notificacoes')).toBe(1);
      await c.q('select public.marcar_notificacoes_lidas(null)');
      const r = await c.sistema('select usuario_id, lida_em from public.notificacoes order by titulo');
      expect(r[0].lida_em).not.toBeNull();
      expect(r[1].lida_em).toBeNull();
    });
  });
});

describe('storage: anexos privados', () => {
  it('envio só na própria pasta; leitura segue a solicitação', async () => {
    await cenario(async (c) => {
      const arq = `aprovacoes/${U.coordCofit}/11111111-1111-1111-1111-111111111111.pdf`;
      await c.como('coordCofit');
      await c.falha(`insert into storage.objects (bucket_id, name) values ('anexos', $1)`,
        [`aprovacoes/${U.funcA}/11111111-1111-1111-1111-111111111111.pdf`], /row-level security/);
      await c.falha(`insert into storage.objects (bucket_id, name) values ('anexos', $1)`,
        [`aprovacoes/${U.coordCofit}/../x.pdf`], /row-level security/);
      await c.q(`insert into storage.objects (bucket_id, name) values ('anexos', $1)`, [arq]);
      const sv = (await c.sistema(`select id from public.servidores where matricula = '000104'`))[0].id;
      await c.q(`select public.solicitar('servidor_alterar', $1, '{"nome_completo":"G 2"}', 'Teste anexo', $2)`, [sv, arq]);
      await c.como('funcA');
      expect(await contar(c, 'storage.objects')).toBe(0);
      await c.como('sec');
      expect(await contar(c, 'storage.objects')).toBe(1);
      await c.como('coordCofit');
      await c.falha(`select public.solicitar('servidor_alterar', $1, '{"nome_completo":"G 3"}', 'Teste anexo', $2)`,
        [sv, `aprovacoes/${U.funcA}/11111111-1111-1111-1111-111111111111.pdf`], /Anexo inválido/);
    });
  });
});
