import { describe, expect, it } from 'vitest';
import { cenario, contar, idServidor, idUnidade, U, type Ctx } from './helpers';

const linha = (n: number, o: Record<string, string>) => ({ linha: n, nome: 'Fulano Teste', matricula: '', cargo: 'Auditor Fiscal', unidade: 'COFIT', email: '', ferias: '30', licenca_premio: '0', folgas: '2', tipo_vinculo: 'efetivo', ...o });
const previa = (c: Ctx, linhas: object[], fn = 'importar_servidores_previa') =>
  c.q<{ linha: number; campo: string; mensagem: string }>(`select * from public.${fn}($1)`, [JSON.stringify(linhas)]);

describe('importação de servidores por planilha', () => {
  it('prévia aponta matrícula vazia, duplicada, já cadastrada, unidade e cargo inexistentes', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      const erros = await previa(c, [
        linha(2, { matricula: '' }),
        linha(3, { matricula: '000900' }),
        linha(4, { matricula: '000900' }),
        linha(5, { matricula: '000101' }),
        linha(6, { matricula: '000901', unidade: 'XYZ' }),
        linha(7, { matricula: '000902', cargo: 'Astronauta' }),
        linha(8, { matricula: '000903', ferias: 'muito' }),
        linha(9, { matricula: '000904', email: 'servidor.a@exemplo.gov.br' }),
      ]);
      const m = erros.map((e) => `${e.linha}:${e.mensagem}`);
      expect(m).toEqual(expect.arrayContaining([
        '2:Matrícula vazia.', '3:Matrícula duplicada na planilha.', '4:Matrícula duplicada na planilha.',
        '5:Matrícula já cadastrada.', '6:Unidade inexistente.', '7:Cargo inexistente.',
        '8:Saldo inválido (use número, ex.: 30 ou 12,5).', '9:E-mail já cadastrado.',
      ]));
    });
  });
  it('não grava nada se houver erro; grava tudo (com saldos) se estiver certo', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      const antes = await contar(c, 'public.servidores');
      await c.falha('select public.importar_servidores($1)', [JSON.stringify([linha(2, { matricula: '000950' }), linha(3, { matricula: '' })])], /tem erros/);
      expect(await contar(c, 'public.servidores')).toBe(antes);
      const n = await c.q<{ n: number }>('select public.importar_servidores($1) as n', [JSON.stringify([
        linha(2, { matricula: '000950', nome: 'Novo Um', ferias: '12,5' }), linha(3, { matricula: '000951', nome: 'Novo Dois', unidade: 'cofit', cargo: 'auditor fiscal' }),
      ])]);
      expect(n[0].n).toBe(2);
      const s = await c.q<{ ferias_dias: string }>(`select ss.ferias_dias from public.saldos_servidor ss join public.servidores sv on sv.id = ss.servidor_id where sv.matricula = '000950'`);
      expect(Number(s[0].ferias_dias)).toBe(12.5);
      const aud = await c.q<{ contexto: { origem: string } }>(`select contexto from public.auditoria where tabela = 'servidores' and acao = 'insert' order by id desc limit 1`);
      expect(aud[0].contexto.origem).toBe('importacao_servidores');
    });
  });
  it('chefia e funcionário não importam', async () => {
    await cenario(async (c) => {
      for (const q of ['coordCofit', 'funcA'] as const) {
        await c.como(q);
        await c.falha('select * from public.importar_servidores_previa($1)', [JSON.stringify([linha(2, { matricula: '1' })])], /Somente a Secretária/);
        await c.falha('select public.importar_saldos($1)', [JSON.stringify([{ linha: 2, matricula: '000101', ferias: '1', licenca_premio: '1', folgas: '1' }])], /Somente a Secretária/);
      }
    });
  });
});

describe('saldos do RH (dado pessoal)', () => {
  const importarSaldos = async (c: Ctx) => {
    await c.como('sec');
    const linhas = ['000101', '000102', '000201'].map((m, i) => ({ linha: i + 2, matricula: m, ferias: '30', licenca_premio: '90', folgas: '2' }));
    expect(await previa(c, [...linhas, { linha: 9, matricula: '999999', ferias: '1', licenca_premio: '1', folgas: '1' }], 'importar_saldos_previa'))
      .toEqual([{ linha: 9, campo: 'matricula', mensagem: 'Matrícula não encontrada no cadastro.' }]);
    expect((await c.q<{ n: number }>('select public.importar_saldos($1) as n', [JSON.stringify(linhas)]))[0].n).toBe(3);
  };
  it('cada um vê o próprio; chefia vê a unidade; outra chefia não vê', async () => {
    await cenario(async (c) => {
      await importarSaldos(c);
      await c.como('funcA');
      expect(await contar(c, 'public.saldos_servidor')).toBe(1);
      await c.como('coordCofit');
      expect(await contar(c, 'public.saldos_servidor')).toBe(2);
      await c.como('coordConta');
      expect(await contar(c, 'public.saldos_servidor')).toBe(1);
      await c.como('anon');
      await c.falha('select * from public.saldos_servidor', [], /permission denied/);
    });
  });
});

describe('férias, licenças e folgas', () => {
  const pedir = async (c: Ctx, mat: string, ini: string, fim: string, tipo = 'ferias') =>
    (await c.q<{ id: string }>('select public.solicitar_afastamento($1, $2, $3, $4) as id', [await idServidor(c, mat), tipo, ini, fim]))[0].id;
  const decidir = (c: Ctx, id: string, aprovar: boolean, sub: string | null, coment: string | null = null) =>
    c.q('select public.decidir_afastamento($1, $2, $3, $4)', [id, aprovar, sub, coment]);

  it('funcionário pede; chefia é avisada; aprovar exige substituto da mesma unidade', async () => {
    await cenario(async (c) => {
      await c.como('funcA');
      const id = await pedir(c, '000101', '2027-07-05', '2027-07-24');
      await c.falha('select public.solicitar_afastamento($1, $2, $3, $4)', [await idServidor(c, '000102'), 'ferias', '2027-07-01', '2027-07-02'], /só pode pedir/);
      await c.falha('select public.decidir_afastamento($1, true, $2, null)', [id, await idServidor(c, '000103')], /Somente a chefia/);
      await c.como('coordCofit');
      expect((await c.q(`select * from public.notificacoes where tipo = 'afastamento_pedido'`)).length).toBe(1);
      await c.falha('select public.decidir_afastamento($1, true, null, null)', [id], /substituto/);
      await c.falha('select public.decidir_afastamento($1, true, $2, null)', [id, await idServidor(c, '000201')], /mesma unidade/);
      await decidir(c, id, true, await idServidor(c, '000103'));
      const a = await c.sistema('select status from public.afastamentos where id = $1', [id]);
      expect(a[0].status).toBe('aprovado');
      await c.como('funcA');
      expect((await c.q(`select * from public.notificacoes where tipo = 'afastamento_resultado'`)).length).toBe(1);
    });
  });

  it('aviso de mesmo cargo no período não bloqueia; substituto afastado bloqueia', async () => {
    await cenario(async (c) => {
      await c.como('coordCofit');
      const a = await pedir(c, '000101', '2027-07-05', '2027-07-24');
      await decidir(c, a, true, await idServidor(c, '000103'));
      const e = await pedir(c, '000102', '2027-07-10', '2027-07-20');
      expect((await c.sistema('select conflito_mesmo_cargo from public.afastamentos where id = $1', [e]))[0].conflito_mesmo_cargo).toBe(true);
      const conf = await c.q<{ nome: string }>('select * from public.conflitos_mesmo_cargo($1, $2, $3, $4)', [await idServidor(c, '000102'), '2027-07-10', '2027-07-20', e]);
      expect(conf.map((x) => x.nome)).toEqual(['Servidor A']);
      await c.falha('select public.decidir_afastamento($1, true, $2, null)', [e, await idServidor(c, '000101')], /também estará afastado/);
      await decidir(c, e, true, await idServidor(c, '000104'));
    });
  });

  it('sem sobreposição para o mesmo servidor; recusa exige comentário; ninguém aprova o próprio', async () => {
    await cenario(async (c) => {
      await c.como('funcA');
      const id = await pedir(c, '000101', '2027-08-01', '2027-08-10', 'folga');
      await c.falha('select public.solicitar_afastamento($1, $2, $3, $4)', [await idServidor(c, '000101'), 'ferias', '2027-08-05', '2027-08-20'], /nesse período/);
      await c.como('coordCofit');
      await c.falha('select public.decidir_afastamento($1, false, null, null)', [id], /comentário/);
      await decidir(c, id, false, null, 'Período de fechamento');
      const meu = await pedir(c, '000106', '2027-09-01', '2027-09-10');
      await c.falha('select public.decidir_afastamento($1, true, $2, null)', [meu, await idServidor(c, '000103')], /próprio/);
      await c.como('dirDat');
      await decidir(c, meu, true, await idServidor(c, '000103'));
    });
  });

  it('escopo: outra diretoria não vê nem decide; funcionário vê só o seu; substituto vê o que substitui', async () => {
    await cenario(async (c) => {
      await c.como('funcE');
      const id = await pedir(c, '000102', '2027-10-01', '2027-10-10');
      await c.como('dirDefc');
      expect(await contar(c, 'public.afastamentos')).toBe(0);
      await c.falha('select public.decidir_afastamento($1, true, $2, null)', [id, await idServidor(c, '000101')], /Somente a chefia/);
      await c.como('coordCofit');
      await decidir(c, id, true, await idServidor(c, '000101'));
      await c.como('funcA');
      expect(await contar(c, 'public.afastamentos')).toBe(1);
      expect((await c.q('select * from public.ausencias_do_mes($1)', ['2027-10-15'])).length).toBe(1);
      await c.como('funcB');
      expect(await contar(c, 'public.afastamentos')).toBe(0);
    });
  });

  it('chefia remarca e cancela (escala editável), com auditoria', async () => {
    await cenario(async (c) => {
      await c.como('coordCofit');
      const id = await pedir(c, '000104', '2027-11-03', '2027-11-12');
      await decidir(c, id, true, await idServidor(c, '000105'));
      await c.q('select public.remarcar_afastamento($1, $2, $3, null)', [id, '2027-11-08', '2027-11-19']);
      await c.q('select public.cancelar_afastamento($1, $2)', [id, 'Necessidade do serviço']);
      const aud = await c.sistema(`select count(*)::int n from public.auditoria where tabela = 'afastamentos' and registro_id = $1`, [id]);
      expect(aud[0].n).toBe(4);
      await c.como('funcA');
      await c.falha('select public.cancelar_afastamento($1, null)', [id], /não pode cancelar/);
    });
  });
});

describe('folhas de ponto', () => {
  const comp = '2026-11-01';
  const criarLote = async (c: Ctx) => {
    await c.como('sec');
    const paginas = [['000101', 'Servidor A'], ['000201', 'Servidor B'], ['999999', 'Servidor X'], ['000102', 'Servidor E']]
      .map(([matricula, nome], i) => ({ pagina: i + 1, matricula, nome }));
    return (await c.q<{ id: string }>('select public.criar_lote_folhas($1, $2) as id', [comp, JSON.stringify(paginas)]))[0].id;
  };

  it('cruza matrícula → servidor → unidade no banco; página sem cadastro fica listada', async () => {
    await cenario(async (c) => {
      const lote = await criarLote(c);
      const p = await c.q<{ pagina: number; servidor: string | null; unidade: string | null }>('select * from public.paginas_do_lote($1)', [lote]);
      expect(p.map((x) => `${x.pagina}:${x.servidor ?? '-'}:${x.unidade ?? '-'}`)).toEqual(['1:Servidor A:COFIT', '2:Servidor B:CONTA', '3:-:-', '4:Servidor E:COFIT']);
      await c.q('select public.vincular_pagina_folha($1, 3, $2)', [lote, await idServidor(c, '000103')]);
      expect((await c.q<{ unidade: string }>('select unidade from public.paginas_do_lote($1) where pagina = 3', [lote]))[0].unidade).toBe('COFIT');
    });
  });

  it('só secretária/admin envia; chefia baixa só a própria unidade; funcionário não vê', async () => {
    await cenario(async (c) => {
      const lote = await criarLote(c);
      const cofit = await idUnidade(c, 'COFIT');
      const conta = await idUnidade(c, 'CONTA');
      const arq = (u: string) => `lotes/${lote}/unidades/${u}-1764160000000.pdf`;
      await c.q(`insert into storage.objects (bucket_id, name) values ('folhas-ponto', $1), ('folhas-ponto', $2), ('folhas-ponto', $3)`,
        [`lotes/${lote}/original.pdf`, arq(cofit), arq(conta)]);
      await c.falha(`insert into storage.objects (bucket_id, name) values ('folhas-ponto', 'outro/x.pdf')`, [], /row-level security/);
      await c.q('select public.registrar_arquivos_folhas($1, $2, $3)', [lote, `lotes/${lote}/original.pdf`, JSON.stringify([
        { unidade_id: cofit, path: arq(cofit), paginas: 2, servidores: 2 }, { unidade_id: conta, path: arq(conta), paginas: 1, servidores: 1 },
      ])]);
      expect((await c.sistema('select concluido from public.folhas_lotes where id = $1', [lote]))[0].concluido).toBe(true);
      await c.falha('select public.registrar_arquivos_folhas($1, null, $2)', [lote, JSON.stringify([{ unidade_id: cofit, path: 'lotes/x/unidades/y.pdf', paginas: 1, servidores: 1 }])], /inválido/);

      await c.como('coordCofit');
      expect((await c.q<{ path: string }>('select path from public.folhas_arquivos')).map((x) => x.path)).toEqual([arq(cofit)]);
      expect((await c.q<{ name: string }>(`select name from storage.objects where bucket_id = 'folhas-ponto'`)).map((x) => x.name)).toEqual([arq(cofit)]);
      expect(await contar(c, 'public.folhas_paginas')).toBe(0);
      await c.falha('select public.criar_lote_folhas($1, $2)', [comp, '[{"pagina":1,"matricula":"1"}]'], /Somente a Secretária/);
      await c.como('dirDefc');
      expect((await c.q<{ path: string }>('select path from public.folhas_arquivos')).map((x) => x.path)).toEqual([arq(conta)]);
      await c.como('funcA');
      expect(await contar(c, 'public.folhas_arquivos')).toBe(0);
      expect(await contar(c, 'public.folhas_lotes')).toBe(0);
    });
  });

  it('casa matrícula ignorando zeros à esquerda; ambígua fica para conferência', async () => {
    await cenario(async (c) => {
      const cofit = await idUnidade(c, 'COFIT');
      const cargo = (await c.sistema(`select id from public.cargos limit 1`))[0].id;
      await c.sistema(`insert into public.servidores (nome_completo, matricula, cargo_id, unidade_id, tipo_vinculo) values ('Dup Um', '0777', $1, $2, 'efetivo'), ('Dup Dois', '777', $1, $2, 'efetivo')`, [cargo, cofit]);
      await c.como('sec');
      const lote = (await c.q<{ id: string }>('select public.criar_lote_folhas($1, $2) as id', ['2026-11-01', JSON.stringify([{ pagina: 1, matricula: '101' }, { pagina: 2, matricula: '777' }])]))[0].id;
      const p = await c.q<{ servidor: string | null }>('select servidor from public.paginas_do_lote($1)', [lote]);
      expect(p.map((x) => x.servidor)).toEqual(['Servidor A', null]);
    });
  });

  it('leitura inconsistente do PDF é recusada', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      await c.falha('select public.criar_lote_folhas($1, $2)', ['2026-11-15', '[{"pagina":1}]'], /Competência/);
      await c.falha('select public.criar_lote_folhas($1, $2)', [comp, '[{"pagina":1},{"pagina":1}]'], /duplicate|inválida/);
      await c.falha('select public.criar_lote_folhas($1, $2)', [comp, '[{"pagina":1},{"pagina":5}]'], /inválida/);
    });
  });
});

describe('controle de entrega das folhas', () => {
  const comp = '2026-10-01';
  it('envio → devolução; chefia registra só na própria unidade; atraso avisa a chefia uma vez por dia', async () => {
    await cenario(async (c) => {
      const cofit = await idUnidade(c, 'COFIT');
      const conta = await idUnidade(c, 'CONTA');
      await c.como('sec');
      await c.falha('select public.registrar_entrega_folha($1, $2, $3, $4, $5)', [comp, cofit, 'devolucao', '2026-10-20', await idServidor(c, '000101')], /envio antes/);
      await c.falha('select public.registrar_entrega_folha($1, $2, $3, $4, $5)', [comp, cofit, 'envio', '2026-10-05', await idServidor(c, '000201')], /servidor da unidade/);
      await c.q('select public.registrar_entrega_folha($1, $2, $3, $4, $5)', [comp, cofit, 'envio', '2026-10-05', await idServidor(c, '000106')]);
      await c.q('select public.registrar_entrega_folha($1, $2, $3, $4, $5)', [comp, conta, 'envio', '2026-10-05', await idServidor(c, '000206')]);
      const sit = await c.q<{ sigla: string; situacao: string; atrasada: boolean }>('select * from public.situacao_entregas($1)', [comp]);
      expect(sit.find((s) => s.sigla === 'COFIT')).toMatchObject({ situacao: 'enviada', atrasada: true });
      expect(sit.find((s) => s.sigla === 'COAC')).toMatchObject({ situacao: 'nao_enviada', atrasada: false });

      await c.sistema('select app.avisar_atrasos_folhas()');
      await c.sistema('select app.avisar_atrasos_folhas()');
      await c.como('coordCofit');
      expect((await c.q(`select * from public.notificacoes where tipo = 'folha_atrasada'`)).length).toBe(1);
      await c.como('dirDat');
      expect((await c.q(`select * from public.notificacoes where tipo = 'folha_atrasada'`)).length).toBe(1);

      await c.como('coordCofit');
      await c.q('select public.registrar_entrega_folha($1, $2, $3, $4, $5)', [comp, cofit, 'devolucao', '2026-10-20', await idServidor(c, '000106')]);
      await c.falha('select public.registrar_entrega_folha($1, $2, $3, $4, $5)', [comp, conta, 'devolucao', '2026-10-20', await idServidor(c, '000206')], /Sem permissão/);
      const minhas = await c.q<{ sigla: string; situacao: string }>('select * from public.situacao_entregas($1)', [comp]);
      expect(minhas).toEqual([expect.objectContaining({ sigla: 'COFIT', situacao: 'devolvida' })]);
      await c.como('funcA');
      expect(await c.q('select * from public.situacao_entregas($1)', [comp])).toEqual([]);
      await c.falha('select public.registrar_entrega_folha($1, $2, $3, $4, $5)', [comp, cofit, 'envio', '2026-10-05', null], /Sem permissão/);
    });
  });
});
