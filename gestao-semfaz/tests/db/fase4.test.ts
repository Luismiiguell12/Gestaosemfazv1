import { describe, expect, it } from 'vitest';
import { cenario, idServidor, idUnidade, U, type Ctx } from './helpers';

// documentos fictícios de exemplo (dígitos verificadores válidos)
const CPF = '52998224725';
const CNPJ = '11222333000181';

const LOCADOR_PF = { tipo: 'PF', nome: 'Locador Fictício', documento: '529.982.247-25', email: 'locador@exemplo.com', telefone: '(79) 99999-1234' };

async function novoContrato(c: Ctx, extra: Record<string, unknown> = {}, locador: Record<string, unknown> = LOCADOR_PF) {
  const dados = {
    numero: '012/2026', processo: 'PROC-1/2026', imovel_descricao: 'Sala comercial centro', imovel_endereco: 'Rua Fictícia, 100',
    unidade_ocupante_id: await idUnidade(c, 'COFIT'), inicio: '2026-01-01', fim: '2026-12-31', valor_mensal: 2500, dia_vencimento: 10,
    fiscal_servidor_id: await idServidor(c, '000101'), ...extra,
  };
  return (await c.q<{ id: string }>('select public.criar_contrato($1, $2) as id', [JSON.stringify(dados), JSON.stringify(locador)]))[0].id;
}
const n = async (c: Ctx, sql: string, p: unknown[] = []) => Number(Object.values((await c.q(sql, p))[0])[0]);

describe('contratos: acesso por módulo e LGPD do locador', () => {
  it('só quem tem o módulo contratos lê; CPF/contato mascarados; completo só com permissão específica (auditado)', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      const id = await novoContrato(c);
      expect(await n(c, 'select count(*) from public.alugueis where contrato_id = $1', [id])).toBe(12);
      const loc = (await c.q<{ locador_id: string }>('select locador_id from public.contratos where id = $1', [id]))[0].locador_id;
      // coluna sensível não sai pela API
      await c.falha('select documento from public.locadores', [], /permission denied/);
      await c.falha('select email from public.locadores', [], /permission denied/);
      const m = (await c.q<{ d: Record<string, unknown> }>('select public.locador_dados($1) as d', [loc]))[0].d;
      expect(m.documento).toBe('***.982.247-**');
      expect(m.telefone).toBe('(79) *****-1234');
      expect(m.email).toBe('lo***@exemplo.com');
      expect(m.pode_ver_completo).toBe(false);
      await c.falha('select public.locador_dados($1, true)', [loc], /permissão específica/);

      await c.sistema(`insert into public.usuario_modulos_extras values ($1, 'locadores_dados', $2, now())`, [U.sec, U.admin]);
      const comp = (await c.q<{ d: Record<string, unknown> }>('select public.locador_dados($1, true) as d', [loc]))[0].d;
      expect(comp.documento).toBe(CPF);
      expect(await n(c, `select count(*) from public.auditoria where acao = 'ver_dados_locador'`)).toBeGreaterThan(0);

      for (const q of ['coordCofit', 'dirDat', 'funcA'] as const) {
        await c.como(q);
        expect(await n(c, 'select count(*) from public.contratos')).toBe(0);
        await c.falha('select public.contrato_ficha($1)', [id], /Sem permissão/);
        await c.falha('select public.locador_dados($1)', [loc], /Acesso não permitido/);
      }
      // módulo extra libera o funcionário
      await c.sistema(`insert into public.usuario_modulos_extras values ($1, 'contratos', $2, now())`, [U.funcB, U.sec]);
      await c.como('funcB');
      expect(await n(c, 'select count(*) from public.contratos')).toBe(1);
      const f = (await c.q<{ f: { locador: { documento: string }; alugueis: unknown[]; contrato: { valor_anual: number } } }>('select public.contrato_ficha($1) as f', [id]))[0].f;
      expect(f.locador.documento).toBe('***.982.247-**');
      expect(f.alugueis).toHaveLength(12);
      expect(Number(f.contrato.valor_anual)).toBe(30000);
      await c.falha('update public.contratos set valor_mensal = 1 where id = $1', [id], /permission denied/);
      await c.como('anon');
      await c.falha('select * from public.contratos', [], /permission denied/);
    });
  });

  it('valida CPF/CNPJ; número único; pagamento de aluguel sem aprovação; desfazer só gestor', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      await c.falha('select public.criar_contrato($1, $2)', [JSON.stringify({ numero: 'X1', imovel_descricao: 'Sala', inicio: '2026-01-01', fim: '2026-06-30', valor_mensal: 10 }),
        JSON.stringify({ ...LOCADOR_PF, documento: '111.111.111-11' })], /Dados inválidos/);
      const id = await novoContrato(c);
      await c.falha('select public.criar_contrato($1, $2)', [JSON.stringify({ numero: '012/2026', imovel_descricao: 'Sala', inicio: '2026-01-01', fim: '2026-06-30', valor_mensal: 10 }),
        JSON.stringify({ tipo: 'PJ', nome: 'Empresa Fictícia', documento: CNPJ })], /Já existe/);
      const a = (await c.q<{ id: string }>(`select id from public.alugueis where contrato_id = $1 and competencia = '2026-01-01'`, [id]))[0].id;
      await c.q('select public.registrar_pagamento_aluguel($1, $2, $3)', [a, '2026-01-09', 2500]);
      await c.falha('select public.registrar_pagamento_aluguel($1, $2, $3)', [a, '2026-01-09', 2500], /já registrado/);
      await c.sistema(`insert into public.usuario_modulos_extras values ($1, 'contratos', $2, now())`, [U.funcB, U.sec]);
      await c.como('funcB');
      await c.falha('select public.desfazer_pagamento_aluguel($1, $2)', [a, 'lançado errado'], /Somente a Secretária/);
      await c.como('sec');
      await c.q('select public.desfazer_pagamento_aluguel($1, $2)', [a, 'lançado errado']);
      const h = await c.q<{ acao: string }>('select acao from public.contrato_historico where contrato_id = $1 order by id', [id]);
      expect(h.map((x) => x.acao)).toEqual(['cadastrado', 'pagamento', 'pagamento_desfeito']);
      await c.sistemaFalha('delete from public.contrato_historico', [], /não podem ser alterados/);
    });
  });
});

describe('contratos: alteração e aditivo passam por aprovação', () => {
  it('alterar valor: pendente até aprovar; solicitante não aprova; aluguéis abertos reajustados', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      const id = await novoContrato(c, { inicio: '2026-01-01', fim: '2027-12-31' });
      await c.falha('select public.solicitar($1, $2, $3, $4)', ['contrato_alterar', id, JSON.stringify({ valor_mensal: 3000 }), 'Reajuste anual'], /não permitido/);
      await c.falha('select public.solicitar_contrato($1, $2, $3, $4)', ['contrato_alterar', id, JSON.stringify({ fim_vigencia: '2030-01-01' }), 'Prorrogar'], /não permitido/);
      const s = (await c.q<{ id: string }>('select public.solicitar_contrato($1, $2, $3, $4) as id', ['contrato_alterar', id, JSON.stringify({ valor_mensal: 3000 }), 'Reajuste anual']))[0].id;
      await c.falha('select public.solicitar_contrato($1, $2, $3, $4)', ['contrato_alterar', id, JSON.stringify({ processo: 'P2' }), 'Outro pedido'], /pendente/);
      expect(await n(c, 'select valor_mensal from public.contratos where id = $1', [id])).toBe(2500);
      await c.falha('select public.decidir_solicitacao($1, true)', [s], /próprio pedido/);
      await c.como('admin');
      await c.q('select public.decidir_solicitacao($1, true)', [s]);
      expect(await n(c, 'select valor_mensal from public.contratos where id = $1', [id])).toBe(3000);
      expect(await n(c, `select count(*) from public.alugueis where contrato_id = $1 and valor = 3000`, [id])).toBeGreaterThan(0);
      expect(await n(c, `select valor from public.alugueis where contrato_id = $1 and competencia = '2026-01-01'`, [id])).toBe(2500); // passado mantém
    });
  });

  it('aditivo de prazo: estende a vigência, gera aluguéis e avisa a demanda de renovação', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      const fim = (await c.q<{ d: string }>(`select to_char(current_date + 60, 'YYYY-MM-DD') as d`))[0].d;
      const id = await novoContrato(c, { inicio: '2026-01-01', fim });
      // rotina diária: < 90 dias → demanda de renovação, uma única vez
      await c.sistema('select app.rotina_contratos()');
      await c.sistema('select app.rotina_contratos()');
      const dem = await c.sistema(`select id, titulo, unidade_id from public.demandas where contrato_id = $1`, [id]);
      expect(dem).toHaveLength(1);
      expect(dem[0].titulo).toBe('Renovação do contrato nº 012/2026');
      expect(await n(c, 'select count(*) from public.demanda_checklist where demanda_id = $1', [dem[0].id])).toBe(4);
      expect(await n(c, `select count(*) from public.contrato_avisos where contrato_id = $1`, [id])).toBe(1);
      await c.como('funcA'); // fiscal: responsável pela demanda
      expect(await n(c, `select count(*) from public.notificacoes where tipo in ('demanda_inclusao', 'contrato_vencendo')`)).toBe(2);
      expect(await n(c, 'select count(*) from public.demandas where id = $1', [dem[0].id])).toBe(1);
      await c.como('sec');
      expect(await n(c, `select count(*) from public.notificacoes where tipo = 'contrato_renovacao'`)).toBe(1);

      const novo = (await c.q<{ d: string }>(`select to_char(current_date + 425, 'YYYY-MM-DD') as d`))[0].d;
      await c.falha('select public.solicitar_contrato($1, $2, $3, $4)', ['contrato_aditivo', id, JSON.stringify({ novo_fim: '2026-02-01' }), 'Prorrogação'], /depois do fim atual/);
      const s = (await c.q<{ id: string }>('select public.solicitar_contrato($1, $2, $3, $4) as id',
        ['contrato_aditivo', id, JSON.stringify({ novo_fim: novo, data_assinatura: '2026-11-20', descricao: '1º termo aditivo' }), 'Prorrogação por 12 meses']))[0].id;
      const antes = await n(c, 'select count(*) from public.alugueis where contrato_id = $1', [id]);
      await c.como('admin');
      await c.q('select public.decidir_solicitacao($1, true)', [s]);
      const ct = (await c.sistema('select fim_vigencia::text as f, fim_original::text as o from public.contratos where id = $1', [id]))[0];
      expect(ct.f).toBe(novo);
      expect(ct.o).toBe(fim);
      expect(await n(c, 'select count(*) from public.alugueis where contrato_id = $1', [id])).toBeGreaterThan(antes);
      expect(await n(c, 'select count(*) from public.aditivos where contrato_id = $1 and numero = 1 and altera_prazo', [id])).toBe(1);
      await c.como('funcA');
      expect(await n(c, `select count(*) from public.notificacoes where titulo = 'Renovação registrada'`)).toBe(1);
      // nova vigência longe: rotina não recria
      await c.sistema('select app.rotina_contratos()');
      expect((await c.sistema('select count(*)::int as n from public.contrato_renovacoes where contrato_id = $1', [id]))[0].n).toBe(1);
    });
  });

  it('pedido bloqueia se o contrato mudou depois', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      const id = await novoContrato(c);
      const s = (await c.q<{ id: string }>('select public.solicitar_contrato($1, $2, $3, $4) as id', ['contrato_alterar', id, JSON.stringify({ processo: 'P-99' }), 'Corrigir processo']))[0].id;
      await c.sistema(`update public.contratos set imovel_endereco = 'Outro' where id = $1`, [id]);
      await c.como('admin');
      expect((await c.q<{ r: string }>('select public.decidir_solicitacao($1, true) as r', [s]))[0].r).toBe('bloqueada');
    });
  });
});

describe('importação de contratos (prévia → tudo ou nada)', () => {
  it('aponta erros por linha e só importa planilha limpa', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      const base = { numero: '100/2025', locador_tipo: 'PJ', locador_nome: 'Imobiliária Fictícia', locador_documento: '11.222.333/0001-81', imovel_descricao: 'Galpão',
        unidade: 'COFIT', inicio: '01/03/2025', fim: '28/02/2027', valor_mensal: '4.200,50', dia_vencimento: '5', fiscal_matricula: '101' };
      const ruim = [{ linha: 2, ...base }, { linha: 3, ...base, locador_tipo: 'PF', locador_documento: '123', fim: '01/01/2020', valor_mensal: 'abc', unidade: 'XYZ' }];
      const erros = await c.q<{ linha: number; campo: string }>('select * from public.importar_contratos_previa($1)', [JSON.stringify(ruim)]);
      const campos3 = erros.filter((e) => e.linha === 3).map((e) => e.campo);
      expect(campos3).toEqual(expect.arrayContaining(['numero', 'locador_documento', 'fim', 'valor_mensal', 'unidade']));
      await c.falha('select public.importar_contratos($1)', [JSON.stringify(ruim)], /tem erros/);
      expect(await n(c, 'select count(*) from public.contratos')).toBe(0);
      const ok = [{ linha: 2, ...base }, { linha: 3, ...base, numero: '101/2025', imovel_descricao: 'Sala 2' }];
      expect(await n(c, 'select public.importar_contratos($1)', [JSON.stringify(ok)])).toBe(2);
      expect(await n(c, 'select count(*) from public.locadores')).toBe(1); // mesmo CNPJ = mesmo locador
      expect(await n(c, `select valor_mensal from public.contratos where numero = '100/2025'`)).toBe(4200.5);
      expect(await n(c, `select count(*) from public.alugueis a join public.contratos ct on ct.id = a.contrato_id where ct.numero = '100/2025'`)).toBe(24);
      const pj = (await c.q<{ d: { documento: string } }>(`select public.locador_dados(locador_id) as d from public.contratos where numero = '100/2025'`))[0].d;
      expect(pj.documento).toBe('11.222.333/0001-81'); // CNPJ não é dado pessoal
    });
  });
});

describe('unidades consumidoras e faturas', () => {
  it('módulo UCs vê faturas; lançamento e pagamento sem aprovação; importação valida', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      const id = await novoContrato(c);
      const uc = (await c.q<{ id: string }>(`select public.criar_uc('energisa', '123456', $1, 'Medidor principal') as id`, [id]))[0].id;
      await c.q(`select public.criar_uc('igua', '998877', $1)`, [id]);
      await c.falha(`select public.criar_uc('energisa', '123456', $1)`, [id], /já cadastrada/);
      await c.q(`select public.lancar_fatura($1, '2026-10-01', 350.20, '2026-10-20', 410)`, [uc]);
      await c.falha(`select public.lancar_fatura($1, '2026-10-15', 10, '2026-10-20')`, [uc], /nessa competência/);
      // funcionário só com o módulo UCs
      await c.sistema(`insert into public.usuario_modulos_extras values ($1, 'unidades_consumidoras', $2, now())`, [U.funcB, U.sec]);
      await c.como('funcB');
      const l = await c.q<{ situacao: string; numero: string }>(`select * from public.ucs_competencia('2026-10-01')`);
      expect(l.map((x) => `${x.numero}:${x.situacao}`).sort()).toEqual(['123456:atrasada', '998877:sem_lancamento']);
      await c.falha('select public.criar_uc($1, $2, $3)', ['cercos', '555', id], /Sem permissão para contratos/);
      expect(await n(c, 'select count(*) from public.contratos')).toBe(0); // UCs não abre contratos
      const f = (await c.q<{ id: string }>('select id from public.faturas'))[0].id;
      await c.q(`select public.registrar_pagamento_fatura($1, '2026-10-18')`, [f]);
      await c.falha(`select public.registrar_pagamento_fatura($1, '2026-10-18')`, [f], /já paga/);
      const linhas = [
        { linha: 2, fornecedor: 'Iguá', uc: '998877', competencia: '10/2026', consumo: '12', valor: '89,90', vencimento: '25/10/2026', pago_em: '' },
        { linha: 3, fornecedor: 'Energisa', uc: '123456', competencia: '10/2026', valor: '1,00', vencimento: '25/10/2026' },
        { linha: 4, fornecedor: 'Light', uc: '1', competencia: '13-2026', valor: '0', vencimento: 'x' },
      ];
      const e = await c.q<{ linha: number; campo: string }>('select * from public.importar_faturas_previa($1)', [JSON.stringify(linhas)]);
      expect(e.filter((x) => x.linha === 2)).toHaveLength(0);
      expect(e.filter((x) => x.linha === 3).map((x) => x.campo)).toEqual(['competencia']);
      expect(e.filter((x) => x.linha === 4).map((x) => x.campo).sort()).toEqual(['competencia', 'fornecedor', 'valor', 'vencimento']);
      expect(await n(c, 'select public.importar_faturas($1)', [JSON.stringify([linhas[0]])])).toBe(1);
      await c.como('coordCofit');
      expect(await n(c, 'select count(*) from public.faturas')).toBe(0);
    });
  });
});

describe('painel e busca', () => {
  it('KPIs de contratos só para quem tem o módulo; busca encontra contrato pelo locador', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      const fim = (await c.q<{ d: string }>(`select to_char(current_date + 30, 'YYYY-MM-DD') as d`))[0].d;
      await novoContrato(c, { inicio: '2026-01-01', fim });
      const p = (await c.q<{ p: { vencendo: number; alugueis_pendentes: number; proximos: unknown[] } }>('select public.painel_contratos() as p'))[0].p;
      expect(p.vencendo).toBe(1);
      expect(p.alugueis_pendentes).toBeGreaterThan(0);
      expect(p.proximos).toHaveLength(1);
      const b = await c.q<{ tipo: string }>(`select * from public.busca_geral('locador fict')`);
      expect(b.map((x) => x.tipo)).toContain('contrato');
      await c.como('coordCofit');
      expect((await c.q<{ p: unknown }>('select public.painel_contratos() as p'))[0].p).toBeNull();
      expect((await c.q<{ tipo: string }>(`select * from public.busca_geral('locador fict')`)).map((x) => x.tipo)).not.toContain('contrato');
    });
  });
});
