import { describe, expect, it } from 'vitest';
import { cenario, idServidor, U, type Ctx } from './helpers';

// Fase 5 · Adendo 01. Os números "Tn" referem-se aos testes obrigatórios da seção 11 do adendo.
const COMP = '2026-10-01';
const IND = ['F1', 'F2', 'F3', 'F4', 'F5'];
const MAX: Record<string, number> = { F1: 20, F2: 15, F3: 15, F4: 10, F5: 10 };

const um = async <T = Record<string, unknown>>(c: Ctx, sql: string, p: unknown[] = []) => (await c.q<T>(sql, p))[0];
const abrir = async (c: Ctx, comp = COMP) => { await c.como('sec'); return Number((await um<{ n: number }>(c, 'select public.prod_abrir_competencia($1) as n', [comp])).n); };
const avDe = async (c: Ctx, mat: string, comp = COMP) =>
  (await c.sistema(`select a.id from public.prod_avaliacoes a join public.servidores s on s.id = a.servidor_id where s.matricula = $1 and a.competencia = $2 and a.status <> 'retificada' order by a.periodo_inicio`, [mat, comp]))[0]?.id as string;
const notas = (v: Record<string, number>) => JSON.stringify(Object.entries(v).map(([indicador, nota]) => ({ indicador, nota, justificativa: `Justificativa do indicador ${indicador}` })));

/** chefia preenche tudo com prova (referência externa) e envia */
async function preencherEEnviar(c: Ctx, chefia: Parameters<Ctx['como']>[0], id: string, v: Record<string, number>) {
  await c.como(chefia);
  await c.q('select public.prod_salvar_avaliacao($1, $2)', [id, notas(v)]);
  for (const i of IND) await c.q(`select public.prod_adicionar_prova($1, $2, 'externa', null, 'Processo 123/2026')`, [id, i]);
  await c.q('select public.prod_enviar($1)', [id]);
}
const designar = async (c: Ctx, papel: string, quem: keyof typeof U) => { await c.como('sec'); await c.q('select public.prod_designar($1, $2)', [papel, U[quem]]); };

describe('elegibilidade e abertura do ciclo', () => {
  it('T16: comissionado puro, temporário e carreira excluída não entram; chefia imediata pela estrutura', async () => {
    await cenario(async (c) => {
      await c.sistema(`update public.servidores set tipo_vinculo = 'comissionado' where matricula = '000102'`);
      await c.sistema(`update public.servidores set tipo_vinculo = 'temporario' where matricula = '000103'`);
      await c.sistema(`insert into public.cargos (nome, carreira_excluida) values ('Carreira Excluída Exemplo', true)`);
      await c.sistema(`update public.servidores set cargo_id = (select id from public.cargos where nome = 'Carreira Excluída Exemplo') where matricula = '000104'`);
      await abrir(c);
      const mats = (await c.sistema(`select s.matricula from public.prod_avaliacoes a join public.servidores s on s.id = a.servidor_id where a.competencia = $1 order by 1`, [COMP])).map((x) => x.matricula);
      expect(mats).not.toContain('000102');
      expect(mats).not.toContain('000103');
      expect(mats).not.toContain('000104');
      expect(mats).not.toContain('000001'); // secretária: comissionado no seed
      expect(mats).toContain('000101');
      const chefia = async (mat: string) => (await c.sistema(`select s2.matricula from public.prod_avaliacoes a join public.servidores s on s.id = a.servidor_id
        join public.servidores s2 on s2.id = a.avaliador_id where s.matricula = $1 and a.competencia = $2`, [mat, COMP]))[0]?.matricula;
      expect(await chefia('000101')).toBe('000106'); // funcionário → coordenador
      expect(await chefia('000106')).toBe('000010'); // coordenador de coordenadoria da DAT → diretor
      expect(await chefia('000010')).toBe('000001'); // diretor → Secretária
      expect(await abrir(c)).toBe(0); // idempotente
      await c.como('coordCofit');
      await c.falha('select public.prod_abrir_competencia($1)', [COMP], /Somente a Secretária/);
    });
  });
});

describe('formulário: notas, justificativa e prova (validação no banco)', () => {
  it('T1 e T2: nota fora do limite e envio sem justificativa/prova são recusados', async () => {
    await cenario(async (c) => {
      await abrir(c);
      const id = await avDe(c, '000101');
      await c.como('coordCofit');
      await c.falha('select public.prod_salvar_avaliacao($1, $2)', [id, notas({ F1: 21 })], /entre 0 e 20/);
      await c.falha('select public.prod_salvar_avaliacao($1, $2)', [id, notas({ F2: -1 })], /entre 0 e 15|check/);
      await c.q('select public.prod_salvar_avaliacao($1, $2)', [id, notas({ F1: 18, F2: 12, F3: 12, F4: 8, F5: 8 })]);
      await c.falha('select public.prod_enviar($1)', [id], /F1: sem prova.*F5: sem prova/);
      for (const i of IND) await c.q(`select public.prod_adicionar_prova($1, $2, 'externa', null, 'Relatório 45/2026')`, [id, i]);
      await c.q('select public.prod_salvar_avaliacao($1, $2)', [id, JSON.stringify([{ indicador: 'F4', nota: 8, justificativa: 'curta' }])]);
      await c.falha('select public.prod_enviar($1)', [id], /F4: sem justificativa/);
      await c.q('select public.prod_salvar_avaliacao($1, $2)', [id, JSON.stringify([{ indicador: 'F4', nota: 8, justificativa: 'Não atende público externo', equivalente: true }])]);
      await c.falha('select public.prod_enviar($1)', [id], /critério equivalente sem justificativa/);
      await c.q('select public.prod_salvar_avaliacao($1, $2)', [id, JSON.stringify([{ indicador: 'F4', nota: 8, justificativa: 'Não atende público externo', equivalente: true, justificativa_equivalente: 'Atendimento interno às coordenadorias' }])]);
      // prova de demanda de outro servidor é recusada
      const dem = (await c.sistema(`insert into public.demandas (titulo, unidade_id, criado_por) values ('Outra', (select id from public.unidades where sigla = 'CONTA'), $1) returning id`, [U.sec]))[0].id;
      await c.falha(`select public.prod_adicionar_prova($1, 'F1', 'demanda', $2)`, [id, dem], /registro precisa ser do servidor/);
      await c.como('funcA');
      await c.falha('select public.prod_salvar_avaliacao($1, $2)', [id, notas({ F1: 20 })], /chefia imediata/);
      expect((await c.q('select * from public.prod_avaliacoes where id = $1', [id])).length).toBe(0); // rascunho invisível ao servidor
      await c.como('coordCofit');
      await c.q('select public.prod_enviar($1)', [id]);
      expect(Number((await c.sistema('select total_funcional t from public.prod_avaliacoes where id = $1', [id]))[0].t)).toBe(58);
    });
  });
});

describe('cálculo (numeric, no banco)', () => {
  it('T3 e T4: exemplo do adendo = 25,65; arrecadação acima da meta limita o índice a 1', async () => {
    await cenario(async (c) => {
      // metas de quadrimestre passado: carga direta (simula metas publicadas antes do início)
      await c.sistema(`set local session_replication_role = replica`);
      for (const [r, arr] of [['R1', 90], ['R2', 150], ['R3', 80], ['R4', 100], ['R5', 60]] as const) {
        await c.sistema(`insert into public.prod_metas (ano, quadrimestre, receita, valor, memoria, fonte) values (2026, 1, $1, 100, 'Média 3 anos + 5%', 'LOA 2026')`, [r]);
        await c.sistema(`insert into public.prod_arrecadacao (ano, quadrimestre, receita, valor, fonte) values (2026, 1, $1, $2, 'Balancete')`, [r, arr]);
      }
      await c.sistema(`set local session_replication_role = origin`);
      await c.como('sec');
      const v = (await um<{ v: { pontos: number; receitas: { receita: string; indice: number }[] } }>(c, 'select public.prod_apurar_institucional(2026, 1) as v')).v;
      expect(Number(v.pontos)).toBe(25.65);
      expect(Number(v.receitas.find((x) => x.receita === 'R2')!.indice)).toBe(1);
      // meta ausente → não apura (sem divisão por zero)
      await c.falha('select public.prod_apurar_institucional(2026, 2)', [], /meta ausente ou zero/);
      await c.falha('select public.prod_apurar_institucional(2026, 3)', [], /ainda não terminou/);
    });
  });

  it('T5–T8: fração desprezada, mínimos cumulativos, transição e proporcionalidade', async () => {
    await cenario(async (c) => {
      const regra = (await c.sistema(`select app.regra_vigente('2026-10-01') r`))[0].r;
      const enq = async (f: number, i: number | null, d = 30, m = 30) =>
        (await c.sistema('select app.prod_enquadrar($1, $2, $3, $4, $5) v', [regra, f, i, d, m]))[0].v as Record<string, unknown>;
      let r = await enq(50, 19.99);
      expect([r.nota_enquadramento, Number(r.percentual)]).toEqual([69, 12]);
      r = await enq(45, 14.99);
      expect([r.nota_enquadramento, Number(r.percentual)]).toEqual([59, 0]);
      r = await enq(41, 34);
      expect([Number(r.nota_total), Number(r.percentual), r.minimo_funcional_atingido]).toEqual([75, 0, false]);
      expect(r.motivo_zero).toMatch(/funcional abaixo de 42/);
      r = await enq(56, null);
      expect([Number(r.nota_total), r.nota_enquadramento, Number(r.percentual), r.transicao]).toEqual([80, 80, 24, true]);
      r = await enq(56, 25.65, 20, 30);
      expect([r.nota_enquadramento, Number(r.percentual), Number(r.fator), Number(r.percentual_efetivo)]).toEqual([81, 24, 0.6667, 16]);
    });
  });

  it('T9: mudança de unidade no mês → média ponderada pelos dias elegíveis; afastamento configurável', async () => {
    await cenario(async (c) => {
      await abrir(c, '2026-09-01');
      const id = await avDe(c, '000101', '2026-09-01');
      await c.como('sec');
      const id2 = (await um<{ id: string }>(c, `select public.prod_dividir_periodo($1, '2026-09-21', $2) as id`, [id, await idServidor(c, '000010')])).id;
      await c.sistema(`insert into public.prod_notas (avaliacao_id, indicador, nota) select $1, x.c, x.n from (values ('F1',20),('F2',15),('F3',15),('F4',5),('F5',5)) x(c, n)`, [id]);   // 60
      await c.sistema(`insert into public.prod_notas (avaliacao_id, indicador, nota) select $1, x.c, x.n from (values ('F1',15),('F2',10),('F3',10),('F4',5),('F5',5)) x(c, n)`, [id2]); // 45
      const ap = async () => (await c.sistema(`select app.prod_apurar('2026-09-01', s.id) v from public.servidores s where matricula = '000101'`))[0].v as Record<string, unknown>;
      let v = await ap();
      expect([Number(v.pontos_funcionais), v.dias_elegiveis, v.dias_mes]).toEqual([55, 30, 30]); // (60×20 + 45×10) / 30
      // afastamento: conta ou não conforme a configuração da regra (tipo ausente = não conta)
      await c.sistema(`insert into public.afastamentos (servidor_id, tipo, inicio, fim, status, solicitado_por, substituto_id)
        select s.id, 'ferias', '2026-09-01', '2026-09-10', 'aprovado', $1, (select id from public.servidores where matricula = '000102') from public.servidores s where s.matricula = '000101'`, [U.sec]);
      v = await ap();
      expect(v.dias_elegiveis).toBe(30); // férias contam (padrão inicial)
      const dias = async (cfg: string) => (await c.sistema(`select app.prod_dias_elegiveis(id, '2026-09-01', '2026-09-30', $1::jsonb) d from public.servidores where matricula = '000101'`, [cfg]))[0].d;
      expect(await dias('{"ferias": false}')).toBe(20);
      expect(await dias('{}')).toBe(20);
      await c.sistema(`update public.servidores set data_entrada_semfaz = '2026-09-26' where matricula = '000101'`);
      expect(await dias('{"ferias": true}')).toBe(5);
    });
  });
});

describe('ciência, recurso, homologação e segregação', () => {
  it('T10: recurso fora do prazo (dias úteis com feriado no meio) é recusado', async () => {
    await cenario(async (c) => {
      await abrir(c);
      const id = await avDe(c, '000101');
      await preencherEEnviar(c, 'coordCofit', id, { F1: 18, F2: 12, F3: 12, F4: 8, F5: 8 });
      const amanha = (await c.sistema(`select public.somar_dias_uteis(current_date, 1)::text d`))[0].d;
      await c.sistema(`insert into public.feriados (data, descricao, abrangencia) values ($1, 'Feriado fictício', 'municipal') on conflict do nothing`, [amanha]);
      await c.como('funcA');
      await c.q('select public.prod_dar_ciencia($1)', [id]);
      const a = (await c.sistema(`select prazo_recurso::text p, public.dias_uteis_entre(current_date, prazo_recurso) du, prazo_recurso - current_date corridos from public.prod_avaliacoes where id = $1`, [id]))[0];
      expect(a.du).toBe(5);                          // 5 dias úteis, contando o cadastro de feriados
      expect(Number(a.corridos)).toBeGreaterThan(5);  // o feriado empurrou o prazo
      await c.sistema(`update public.prod_avaliacoes set prazo_recurso = current_date - 1 where id = $1`, [id]);
      await c.falha('select public.prod_recorrer($1, $2)', [id, 'Discordo da nota do indicador F1'], /Fora do prazo/);
    });
  });

  it('fluxo completo: ciência, recurso, revisão fundamentada, homologação, demonstrativo, SEMAD e retificação', async () => {
    await cenario(async (c) => {
      await abrir(c);
      const id = await avDe(c, '000101');
      await preencherEEnviar(c, 'coordCofit', id, { F1: 18, F2: 12, F3: 12, F4: 8, F5: 8 });
      await designar(c, 'revisora', 'dirDefc');
      await designar(c, 'homologacao', 'admin');
      await c.como('funcB');
      expect((await c.q('select * from public.prod_avaliacoes where id = $1', [id])).length).toBe(0); // T15
      await c.falha(`select public.prod_demonstrativo($1, $2)`, [COMP, await idServidor(c, '000101')], /Acesso não permitido/);
      await c.falha(`select public.prod_demonstrativo($1, null)`, [COMP], /Acesso não permitido/);
      await c.como('funcA');
      expect((await c.q('select * from public.prod_avaliacoes where id = $1', [id])).length).toBe(1);
      await c.falha('select public.prod_recorrer($1, $2)', [id, 'Discordo da nota'], /Fora do prazo/); // antes da ciência
      await c.q('select public.prod_dar_ciencia($1)', [id]);
      await c.q('select public.prod_recorrer($1, $2)', [id, 'Discordo da nota do indicador F1 porque entreguei tudo']);
      await c.como('coordCofit');
      await c.falha('select public.prod_decidir_recurso($1, $2)', [id, 'Mantenho a avaliação por completo'], /autoridade revisora/);
      await c.como('dirDefc');
      await c.falha('select public.prod_decidir_recurso($1, $2)', [id, 'curta'], /fundamentada/);
      await c.falha('select public.prod_decidir_recurso($1, $2, $3)', [id, 'Recurso parcialmente provido conforme provas', JSON.stringify([{ indicador: 'F1', nota: 20, justificativa: '' }])], /justificativa/);
      await c.q('select public.prod_decidir_recurso($1, $2, $3)', [id, 'Recurso parcialmente provido conforme provas', JSON.stringify([{ indicador: 'F1', nota: 20, justificativa: 'Entregas comprovadas no processo 123' }])]);
      await c.como('admin');
      expect(await c.q('select public.prod_homologar($1) as n', [[id]])).toEqual([{ n: 1 }]);
      const dem = (await c.sistema(`select dados d from public.prod_apuracoes where competencia = $1 and servidor_id = (select id from public.servidores where matricula = '000101')`, [COMP]))[0].d;
      expect([Number(dem.pontos_funcionais), dem.transicao, dem.nota_enquadramento, Number(dem.percentual)]).toEqual([60, true, 85, 24]); // 60/70×100 = 85,71
      // T14: homologada não muda; só retificação
      await c.sistemaFalha(`update public.prod_avaliacoes set total_funcional = 70 where id = $1`, [id], /homologada não pode ser alterada/);
      await c.sistemaFalha(`update public.prod_notas set nota = 1 where avaliacao_id = $1 and indicador = 'F1'`, [id], /só mudam com a avaliação em rascunho/);
      await c.sistemaFalha(`delete from public.prod_avaliacoes where id = $1`, [id], /não podem ser alterados/);
      // SEMAD: só com tudo homologado
      await c.como('sec');
      await c.falha('select public.prod_encaminhar_semad($1)', [COMP], /não homologadas/);
      await c.sistema(`update public.prod_avaliacoes set status = 'aguardando_homologacao' where competencia = $1 and status = 'rascunho' and id <> $2`, [COMP, id]);
      await c.como('admin');
      const outros = (await c.sistema(`select a.id from public.prod_avaliacoes a join public.servidores s on s.id = a.servidor_id where a.competencia = $1 and a.status = 'aguardando_homologacao' and s.matricula <> '000002'`, [COMP])).map((x) => x.id);
      await c.q('select public.prod_homologar($1)', [outros]);
      await c.sistema(`update public.prod_avaliacoes a set status = 'homologada' from public.servidores s where s.id = a.servidor_id and s.matricula = '000002' and a.competencia = $1`, [COMP]);
      await c.como('sec');
      const enc = (await um<{ id: string }>(c, 'select public.prod_encaminhar_semad($1) as id', [COMP])).id;
      const linhas = (await c.q<{ linhas: Record<string, unknown>[] }>('select linhas from public.prod_encaminhamentos where id = $1', [enc]))[0].linhas;
      expect(linhas.find((l) => l.matricula === '000101')).toMatchObject({ nota_enquadramento: 85, cargo: 'Auditor Fiscal' });
      // retificação: original preservado e ligado
      const nova = (await um<{ id: string }>(c, 'select public.prod_retificar($1, $2, $3) as id', [id, 'Inconsistência apontada pela SEMAD', 'SEMAD: matrícula divergente na folha'])).id;
      expect((await c.sistema('select status from public.prod_avaliacoes where id = $1', [id]))[0].status).toBe('retificada');
      expect((await c.sistema('select status, retifica_id from public.prod_avaliacoes where id = $1', [nova]))[0]).toEqual({ status: 'rascunho', retifica_id: id });
      expect((await c.sistema('select count(*)::int n from public.prod_notas where avaliacao_id = $1', [nova]))[0].n).toBe(5);
      expect((await c.sistema('select count(*)::int n from public.prod_correcoes where nova_avaliacao_id = $1', [nova]))[0].n).toBe(1);
    });
  });

  it('T11 e T12: autoavaliação, autorrevisão, auto-homologação e avaliador homologando são recusados (inclusive Administrador)', async () => {
    await cenario(async (c) => {
      await abrir(c);
      const idAdm = await avDe(c, '000002');      // administrador: avaliado pela Secretária
      const idFun = await avDe(c, '000101');
      await c.como('sec');
      await c.falha('select public.prod_trocar_avaliador($1, $2)', [idAdm, await idServidor(c, '000002')], /Ninguém avalia a si mesmo/);
      await c.sistemaFalha(`update public.prod_avaliacoes set avaliador_id = servidor_id where id = $1`, [idAdm], /prod_av_autoavaliacao/);
      await designar(c, 'revisora', 'admin');
      await designar(c, 'homologacao', 'admin');
      await designar(c, 'homologacao', 'coordCofit');
      await preencherEEnviar(c, 'sec', idAdm, { F1: 18, F2: 12, F3: 12, F4: 8, F5: 8 });
      await c.como('admin');
      await c.q('select public.prod_dar_ciencia($1)', [idAdm]);
      await c.q('select public.prod_recorrer($1, $2)', [idAdm, 'Discordo da avaliação recebida no mês']);
      expect((await c.sistema('select revisor_id from public.prod_recursos where avaliacao_id = $1', [idAdm]))[0].revisor_id).toBeNull(); // não se autodesigna
      await c.falha('select public.prod_decidir_recurso($1, $2)', [idAdm, 'Mantenho integralmente a avaliação'], /Segregação/);         // autorrevisão
      await c.sistema(`update public.prod_avaliacoes set status = 'aguardando_homologacao' where id = $1`, [idAdm]);
      await c.falha('select public.prod_homologar($1)', [[idAdm]], /Segregação/);                                                        // auto-homologação
      // avaliador (coordenador) designado para homologar a avaliação que ele mesmo fez
      await preencherEEnviar(c, 'coordCofit', idFun, { F1: 18, F2: 12, F3: 12, F4: 8, F5: 8 });
      await c.sistema(`update public.prod_avaliacoes set status = 'aguardando_homologacao' where id = $1`, [idFun]);
      await c.como('coordCofit');
      await c.falha('select public.prod_homologar($1)', [[idFun]], /Segregação/);
      await c.falha('select public.prod_devolver($1, $2)', [idFun, 'Faltou anexar provas'], /Segregação/);
    });
  });

  it('T13: meta travada depois do início do quadrimestre (nem o Administrador, nem direto no banco)', async () => {
    await cenario(async (c) => {
      await c.sistema(`set local session_replication_role = replica`);
      const m = (await c.sistema(`insert into public.prod_metas (ano, quadrimestre, receita, valor, memoria, fonte) values (2026, 3, 'R1', 100, 'Memória fictícia', 'LOA') returning id`))[0].id;
      await c.sistema(`set local session_replication_role = origin`);
      await c.como('admin');
      await c.falha(`select public.prod_salvar_meta(2026, 3, 'R1', 200, 'Nova memória', 'LOA')`, [], /publicada antes do início|travada/);
      await c.sistemaFalha(`update public.prod_metas set valor = 1 where id = $1`, [m], /travada/);
      await c.sistemaFalha(`delete from public.prod_metas where id = $1`, [m], /travada/);
      // retificação é registro que não vale para o ciclo já iniciado
      await c.q(`select public.prod_salvar_meta(2026, 3, 'R1', 200, 'Nova memória', 'LOA', null, 'Erro de digitação na meta publicada')`);
      expect((await c.sistema(`select vale_para_ciclo from public.prod_metas where retificacao`))[0].vale_para_ciclo).toBe(false);
      // meta futura pode ser publicada e ajustada antes do início
      await c.q(`select public.prod_salvar_meta(2027, 1, 'R1', 100, 'Memória 2027', 'LOA 2027')`);
      await c.q(`select public.prod_salvar_meta(2027, 1, 'R1', 110, 'Memória 2027 revista', 'LOA 2027')`);
      await c.como('coordCofit');
      await c.falha(`select public.prod_salvar_meta(2027, 1, 'R2', 100, 'Memória', 'LOA')`, [], /Sem permissão/);
    });
  });
});

describe('acesso (LGPD) e alertas', () => {
  it('T15 e painel: servidor não lê avaliação de outro; diretor só lê a diretoria; resumo sem nomes', async () => {
    await cenario(async (c) => {
      await abrir(c);
      const id = await avDe(c, '000101');
      await preencherEEnviar(c, 'coordCofit', id, { F1: 18, F2: 12, F3: 12, F4: 8, F5: 8 });
      await c.como('funcE');
      expect((await c.q('select * from public.prod_avaliacoes')).length).toBe(0); // a dele está em rascunho; a do outro, invisível
      expect((await c.q('select * from public.prod_notas')).length).toBe(0);
      await c.falha('select public.prod_avaliacao_detalhe($1)', [id], /Acesso não permitido/);
      await c.como('dirDat');
      expect((await c.q('select * from public.prod_avaliacoes where id = $1', [id])).length).toBe(1);
      await c.falha('select public.prod_salvar_avaliacao($1, $2)', [id, notas({ F1: 1 })], /chefia imediata/);
      await c.como('dirDefc');
      expect((await c.q('select * from public.prod_avaliacoes where id = $1', [id])).length).toBe(0);
      const r = await c.q<Record<string, unknown>>('select * from public.prod_resumo($1)', [COMP]);
      expect(Object.keys(r[0] ?? {})).not.toContain('servidor');
      await c.como('anon');
      await c.falha('select * from public.prod_avaliacoes', [], /permission denied/);
    });
  });

  it('rotina: sem recurso no prazo → aguardando homologação; alertas uma vez', async () => {
    await cenario(async (c) => {
      await abrir(c);
      const id = await avDe(c, '000101');
      await preencherEEnviar(c, 'coordCofit', id, { F1: 18, F2: 12, F3: 12, F4: 8, F5: 8 });
      await c.como('funcA');
      await c.q('select public.prod_dar_ciencia($1)', [id]);
      await c.sistema(`update public.prod_avaliacoes set prazo_recurso = current_date - 1 where id = $1`, [id]);
      await c.sistema('select app.rotina_produtividade()');
      await c.sistema('select app.rotina_produtividade()');
      expect((await c.sistema('select status, sem_recurso_em is not null s from public.prod_avaliacoes where id = $1', [id]))[0]).toEqual({ status: 'aguardando_homologacao', s: true });
      expect((await c.sistema(`select count(*)::int n from public.prod_historico where avaliacao_id = $1 and acao = 'sem_recurso'`, [id]))[0].n).toBe(1);
    });
  });
});
