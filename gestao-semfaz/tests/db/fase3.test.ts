import { describe, expect, it } from 'vitest';
import { cenario, contar, idServidor, idUnidade, U, type Ctx } from './helpers';

const criar = async (c: Ctx, dados: Record<string, unknown>, resp: string[], checklist: string[] = []) =>
  (await c.q<{ id: string }>('select public.criar_demanda($1, $2, $3) as id', [JSON.stringify(dados), resp, checklist]))[0].id;
const ve = async (c: Ctx, id: string) => (await c.q('select id from public.demandas where id = $1', [id])).length === 1;
const notif = async (c: Ctx, tipo: string) => (await c.q('select * from public.notificacoes where tipo = $1', [tipo])).length;

async function demandaCofit(c: Ctx, extra: Record<string, unknown> = {}) {
  await c.como('coordCofit');
  return criar(c, { titulo: 'Relatório de fiscalização ISS', unidade_id: await idUnidade(c, 'COFIT'), origem: 'processo', numero_processo: '1234/2026', prioridade: 'alta', prazo: '2027-01-29', ...extra },
    [await idServidor(c, '000101'), await idServidor(c, '000102')], ['Levantar dados', 'Redigir', 'Revisar']);
}

describe('demandas: criação e escopo', () => {
  it('chefia cria e distribui; responsáveis são avisados; fora do escopo é negado', async () => {
    await cenario(async (c) => {
      const id = await demandaCofit(c);
      await c.falha('select public.criar_demanda($1, $2)', [JSON.stringify({ titulo: 'X demanda', unidade_id: await idUnidade(c, 'COFIT') }), [await idServidor(c, '000201')]], /fora da sua unidade/);
      await c.como('coordConta');
      await c.falha('select public.criar_demanda($1, $2)', [JSON.stringify({ titulo: 'Outra', unidade_id: await idUnidade(c, 'COFIT') }), [await idServidor(c, '000101')]], /chefia da unidade/);
      expect(await ve(c, id)).toBe(false);
      await c.como('funcA');
      await c.falha('select public.criar_demanda($1, $2)', [JSON.stringify({ titulo: 'Minha', unidade_id: await idUnidade(c, 'COFIT') }), [await idServidor(c, '000101')]], /chefia da unidade/);
      expect(await ve(c, id)).toBe(true);
      expect(await notif(c, 'demanda_inclusao')).toBe(1);
      const l = await c.q<{ responsaveis: { nome: string }[]; etapas_total: number; dias_uteis: number }>('select * from public.listar_demandas() where id = $1', [id]);
      expect(l[0].responsaveis.map((r) => r.nome)).toEqual(['Servidor A', 'Servidor E']);
      expect(l[0].etapas_total).toBe(3);
      for (const q of ['funcB', 'dirDefc'] as const) { await c.como(q); expect(await ve(c, id)).toBe(false); }
      for (const q of ['dirDat', 'sec'] as const) { await c.como(q); expect(await ve(c, id)).toBe(true); }
      await c.como('anon');
      await c.falha('select * from public.demandas', [], /permission denied/);
    });
  });

  it('sugestão do funcionário só vale após aprovação da chefia', async () => {
    await cenario(async (c) => {
      await c.como('funcB');
      const id = (await c.q<{ id: string }>('select public.sugerir_demanda($1) as id', [JSON.stringify({ titulo: 'Conciliar receitas', origem: 'email' })]))[0].id;
      expect((await c.q<{ status: string }>('select status from public.demandas where id = $1', [id]))[0].status).toBe('sugerida');
      await c.falha('select public.decidir_sugestao($1, true, $2)', [id, [await idServidor(c, '000201')]], /chefia/);
      await c.falha('select public.mudar_status_demanda($1, $2)', [id, 'em_andamento'], /responsáveis ou a chefia/);
      await c.como('coordConta');
      expect(await notif(c, 'demanda_sugestao')).toBe(1);
      await c.falha('select public.decidir_sugestao($1, true, $2)', [id, []], /pelo menos um responsável/);
      await c.falha('select public.decidir_sugestao($1, false)', [id], /comentário/);
      await c.q('select public.decidir_sugestao($1, true, $2, $3)', [id, [await idServidor(c, '000201')], '2027-02-10']);
      await c.como('funcB');
      expect(await notif(c, 'demanda_sugestao_resultado')).toBe(1);
      expect((await c.q<{ status: string }>('select status from public.demandas where id = $1', [id]))[0].status).toBe('a_fazer');
    });
  });
});

describe('status, checklist e histórico', () => {
  it('responsável move; outro servidor não; concluir é ação explícita; histórico imutável', async () => {
    await cenario(async (c) => {
      const id = await demandaCofit(c);
      await c.como('funcB');
      await c.falha('select public.mudar_status_demanda($1, $2)', [id, 'em_andamento'], /responsáveis ou a chefia/);
      await c.como('funcA');
      await c.q('select public.mudar_status_demanda($1, $2)', [id, 'em_andamento']);
      await c.falha('select public.mudar_status_demanda($1, $2)', [id, 'cancelada'], /chefia cancela/);
      const itens = await c.q<{ id: string }>('select id from public.demanda_checklist where demanda_id = $1 order by ordem', [id]);
      for (const it of itens) await c.q('select public.marcar_item_checklist($1, true)', [it.id]);
      expect((await c.q<{ status: string }>('select status from public.demandas where id = $1', [id]))[0].status).toBe('em_andamento'); // não conclui sozinha
      await c.q('select public.marcar_item_checklist($1, false)', [itens[2].id]);
      await c.q('select public.mudar_status_demanda($1, $2)', [id, 'concluida']);
      const h = await c.q<{ acao: string }>('select acao from public.demanda_historico where demanda_id = $1 order by id', [id]);
      expect(h.map((x) => x.acao)).toEqual(['criada', 'responsavel_incluido', 'responsavel_incluido', 'status', 'etapa_marcada', 'etapa_marcada', 'etapa_marcada', 'etapa_desmarcada', 'status']);
      await c.sistemaFalha('delete from public.demanda_historico', [], /não podem ser alterados/);
      await c.falha('update public.demandas set status = $1 where id = $2', ['a_fazer', id], /permission denied/);
    });
  });
});

describe('conversa: menções, pedido de atualização, feedback', () => {
  it('menção dá acesso à conversa e avisa; só a chefia pede atualização e dá feedback; nada é apagado', async () => {
    await cenario(async (c) => {
      const id = await demandaCofit(c);
      await c.como('funcA');
      await c.falha('select public.enviar_mensagem($1, $2)', [id, '   '], /vazia/);
      const m = (await c.q<{ id: string }>('select public.enviar_mensagem($1, $2, $3) as id', [id, 'Preciso de ajuda @Servidor B', [U.funcB]]))[0].id;
      await c.como('funcB');
      expect(await notif(c, 'demanda_mencao')).toBe(1);
      expect(await ve(c, id)).toBe(true);
      expect((await c.q('select * from public.demanda_mensagens where demanda_id = $1', [id])).length).toBe(1);
      await c.falha('select public.editar_mensagem($1, $2)', [m, 'alterado'], /autor/);
      await c.falha('select public.pedir_atualizacao($1)', [id], /chefia/);
      await c.como('funcA');
      await c.q('select public.editar_mensagem($1, $2)', [m, 'Preciso de ajuda (editado)']);
      expect((await c.q<{ editado_em: string | null }>('select editado_em from public.demanda_mensagens where id = $1', [m]))[0].editado_em).not.toBeNull();
      await c.falha('select public.dar_feedback($1, $2)', [m, 'aprovado'], /chefia/);
      await c.como('coordCofit');
      await c.q('select public.pedir_atualizacao($1)', [id]);
      await c.q('select public.dar_feedback($1, $2, $3)', [m, 'ajustar', 'Detalhar o lote 3']);
      await c.como('funcE');
      expect(await notif(c, 'demanda_pedido_atualizacao')).toBe(1);
      await c.como('funcA');
      expect(await notif(c, 'demanda_feedback')).toBe(1);
      const d = (await c.q<{ d: { mensagens: { feedback: string }[]; historico: { acao: string }[] } }>('select public.demanda_detalhe($1) as d', [id]))[0].d;
      expect(d.mensagens.map((x) => x.feedback)).toEqual(['ajustar', null]);
      expect(d.historico.map((x) => x.acao)).toContain('feedback');
      await c.sistemaFalha('delete from public.demanda_mensagens', [], /não podem ser alterados/);
      await c.como('funcB');
      const nada = await c.q<{ d: unknown }>('select public.demanda_detalhe(gen_random_uuid()) as d');
      expect(nada[0].d).toBeNull();
    });
  });
});

describe('anexos', () => {
  it('responsável anexa; quem não vê a demanda não baixa; substituir gera nova versão', async () => {
    await cenario(async (c) => {
      const id = await demandaCofit(c);
      const p1 = `demandas/${id}/11111111-1111-1111-1111-111111111111.pdf`;
      const p2 = `demandas/${id}/22222222-2222-2222-2222-222222222222.pdf`;
      await c.como('funcB');
      await c.falha(`insert into storage.objects (bucket_id, name) values ('demandas', $1)`, [p1], /row-level security/);
      await c.como('funcA');
      await c.q(`insert into storage.objects (bucket_id, name) values ('demandas', $1), ('demandas', $2)`, [p1, p2]);
      await c.falha(`insert into storage.objects (bucket_id, name) values ('demandas', $1)`, [`demandas/${id}/../x.pdf`], /row-level security/);
      const a1 = (await c.q<{ id: string }>('select public.registrar_anexo($1, $2, $3, $4, $5) as id', [id, p1, 'parecer.pdf', 'pdf', 1000]))[0].id;
      await c.q('select public.registrar_anexo($1, $2, $3, $4, $5, $6)', [id, p2, 'parecer v2.pdf', 'pdf', 1200, a1]);
      expect((await c.q<{ versao: number }>('select versao from public.demanda_anexos where demanda_id = $1 order by versao', [id])).map((x) => x.versao)).toEqual([1, 2]);
      await c.falha('select public.registrar_anexo($1, $2, $3, $4, $5)', [id, 'demandas/outra/x.pdf', 'x', 'pdf', 1], /inválido/);
      await c.como('funcB');
      expect(await contar(c, `storage.objects where bucket_id = 'demandas'`)).toBe(0);
      await c.como('dirDat');
      expect(await contar(c, `storage.objects where bucket_id = 'demandas'`)).toBe(2);
    });
  });
});

describe('demandas recorrentes', () => {
  it('rotina cria cada ocorrência uma vez; editar vale para as próximas; funcionário não vê modelos', async () => {
    await cenario(async (c) => {
      await c.como('coordCofit');
      const hoje = (await c.sistema(`select current_date::text as d`))[0].d as string;
      const r = (await c.q<{ id: string }>('select public.salvar_recorrencia(null, $1, $2, $3) as id', [JSON.stringify({
        titulo: 'Relatório mensal de arrecadação', unidade_id: await idUnidade(c, 'COFIT'), periodicidade: 'mensal', prazo_dias_uteis: 5, proxima_em: hoje,
      }), [await idServidor(c, '000101')], ['Extrair dados', 'Enviar à DAT']]))[0].id;
      expect((await c.sistema('select app.gerar_ocorrencias() as n'))[0].n).toBe(1);
      expect((await c.sistema('select app.gerar_ocorrencias() as n'))[0].n).toBe(0);
      await c.sistema(`update public.recorrencias set proxima_em = $2 where id = $1`, [r, hoje]); // forçar mesma referência
      expect((await c.sistema('select app.gerar_ocorrencias() as n'))[0].n).toBe(0);           // não duplica
      const d = await c.sistema(`select d.titulo, d.origem, d.prazo, (select count(*)::int from public.demanda_checklist where demanda_id = d.id) etapas
                                   from public.demandas d where recorrencia_id = $1`, [r]);
      expect(d).toHaveLength(1);
      expect(d[0]).toMatchObject({ origem: 'recorrente', etapas: 2 });
      await c.q('select public.salvar_recorrencia($1, $2, $3)', [r, JSON.stringify({ titulo: 'Novo título', periodicidade: 'mensal', prazo_dias_uteis: 3 }), [await idServidor(c, '000101')]]);
      expect((await c.sistema('select titulo from public.demandas where recorrencia_id = $1', [r]))[0].titulo).toBe('Relatório mensal de arrecadação');
      await c.como('funcA');
      expect(await contar(c, 'public.recorrencias')).toBe(0);
      await c.falha('select public.mudar_situacao_recorrencia($1, $2)', [r, 'pausada'], /chefia/);
      await c.como('coordCofit');
      await c.q('select public.mudar_situacao_recorrencia($1, $2)', [r, 'encerrada']);
    });
  });
});

describe('substituto nas demandas durante o afastamento', () => {
  it('entra como responsável adicional (titular fica) e sai no retorno das não concluídas', async () => {
    await cenario(async (c) => {
      const id = await demandaCofit(c);
      const outra = await demandaCofit(c, { titulo: 'Já concluída depois' });
      const a = await idServidor(c, '000101');
      const g = await idServidor(c, '000104');
      const af = (await c.sistema(`insert into public.afastamentos (servidor_id, tipo, inicio, fim, status, substituto_id, solicitado_por)
        values ($1, 'ferias', current_date - 7, current_date + 10, 'aprovado', $2, $3) returning id`, [a, g, U.funcA]))[0].id;
      await c.sistema('select app.aplicar_substituicoes()');
      const resp = await c.sistema(`select servidor_id, papel from public.demanda_responsaveis where demanda_id = $1 and ativo order by papel`, [id]);
      expect(resp.map((r) => r.papel)).toEqual(['titular', 'titular', 'substituto']);
      expect((await c.sistema(`select count(*)::int n from public.demanda_historico where demanda_id = $1 and acao = 'substituicao_inicio'`, [id]))[0].n).toBe(1);
      await c.sistema('select app.aplicar_substituicoes()'); // idempotente
      expect((await c.sistema(`select count(*)::int n from public.demanda_historico where demanda_id = $1 and acao = 'substituicao_inicio'`, [id]))[0].n).toBe(1);
      await c.como('coordCofit');
      expect(await notif(c, 'substituicao_inicio')).toBe(1);
      await c.sistema(`update public.demandas set status = 'concluida', concluida_em = now() where id = $1`, [outra]);
      await c.sistema(`update public.afastamentos set fim = current_date - 1 where id = $1`, [af]);
      await c.sistema('select app.aplicar_substituicoes()');
      expect((await c.sistema(`select count(*)::int n from public.demanda_responsaveis where demanda_id = $1 and servidor_id = $2 and ativo`, [id, g]))[0].n).toBe(0);
      expect((await c.sistema(`select count(*)::int n from public.demanda_responsaveis where demanda_id = $1 and servidor_id = $2 and ativo`, [outra, g]))[0].n).toBe(1);
    });
  });
});

describe('aviso de prazo', () => {
  it('avisa responsáveis uma vez por dia', async () => {
    await cenario(async (c) => {
      const hoje = (await c.sistema(`select current_date::text as d`))[0].d as string;
      await demandaCofit(c, { prazo: hoje });
      await c.sistema('select app.avisar_prazos()');
      await c.sistema('select app.avisar_prazos()');
      await c.como('funcA');
      expect(await notif(c, 'demanda_prazo')).toBe(1);
    });
  });
});

describe('calendário', () => {
  it('cada um edita o calendário do escopo; funcionário só vê o que o inclui', async () => {
    await cenario(async (c) => {
      await c.como('coordCofit');
      const dados = (u: string | null, t = 'Reunião de planejamento') => JSON.stringify({ unidade_id: u, titulo: t, inicio: '2026-12-10T12:00:00Z', fim: '2026-12-10T13:30:00Z', local: 'Sala da DAT' });
      const id = (await c.q<{ id: string }>('select public.salvar_compromisso(null, $1, $2) as id', [dados(await idUnidade(c, 'COFIT')), [await idServidor(c, '000101')]]))[0].id;
      await c.falha('select public.salvar_compromisso(null, $1)', [dados(await idUnidade(c, 'CONTA'))], /sua unidade/);
      await c.falha('select public.salvar_compromisso(null, $1)', [dados(null)], /sua unidade/);
      await c.como('sec');
      await c.q('select public.salvar_compromisso(null, $1)', [dados(null, 'Reunião de diretores')]);
      const ev = (q: Ctx) => q.q<{ tipo: string; titulo: string }>(`select tipo, titulo from public.eventos_calendario('2026-12-01', '2026-12-31')`);
      expect((await ev(c)).map((e) => e.titulo)).toEqual(expect.arrayContaining(['Reunião de planejamento', 'Reunião de diretores', 'Natal']));
      await c.como('funcA');
      expect(await notif(c, 'compromisso')).toBe(1);
      const meus = await ev(c);
      expect(meus.map((e) => e.titulo)).toContain('Reunião de planejamento');
      expect(meus.map((e) => e.titulo)).not.toContain('Reunião de diretores');
      await c.falha('select public.cancelar_compromisso($1)', [id], /Sem permissão/);
      await c.como('funcE');
      expect((await ev(c)).filter((e) => e.tipo === 'compromisso')).toEqual([]);
      await c.como('coordConta');
      expect((await ev(c)).filter((e) => e.tipo === 'compromisso')).toEqual([]);
    });
  });
});

describe('painel e busca', () => {
  it('indicadores por unidade no escopo; funcionário só os próprios números; busca respeita acesso', async () => {
    await cenario(async (c) => {
      const id = await demandaCofit(c, { prazo: '2026-01-05' }); // atrasada
      await c.como('coordCofit');
      const p = await c.q<{ unidade_id: string; atrasadas: number; a_fazer: number }>('select * from public.painel_unidades()');
      expect(p).toEqual([expect.objectContaining({ unidade_id: await idUnidade(c, 'COFIT'), atrasadas: 1, a_fazer: 1 })]);
      await c.como('sec');
      expect((await c.q('select * from public.painel_unidades()')).length).toBe(13);
      await c.como('funcA');
      expect(await c.q('select * from public.painel_unidades()')).toEqual([]);
      const ind = (await c.q<{ i: { abertas: number; atrasadas: number; por_mes: unknown[] } }>('select public.meus_indicadores() as i'))[0].i;
      expect(ind).toMatchObject({ abertas: 1, atrasadas: 1 });
      expect(ind.por_mes).toHaveLength(6);
      const num = (await c.sistema('select numero from public.demandas where id = $1', [id]))[0].numero;
      expect((await c.q(`select * from public.busca_geral($1) where tipo = 'demanda'`, [`#${num}`])).length).toBe(1);
      expect((await c.q(`select * from public.busca_geral('1234/2026') where tipo = 'demanda'`)).length).toBe(1);
      await c.como('funcB');
      expect((await c.q(`select * from public.busca_geral($1) where tipo = 'demanda'`, [`#${num}`])).length).toBe(0);
    });
  });
});
