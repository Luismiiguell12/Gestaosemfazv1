import { describe, expect, it } from 'vitest';
import { cenario, idServidor, idUnidade, U, type Ctx } from './helpers';

const solicitar = async (c: Ctx, tipo: string, alvo: string | null, dados: object, just = 'Justificativa de teste') =>
  (await c.q<{ id: string }>('select public.solicitar($1, $2, $3, $4) as id', [tipo, alvo, JSON.stringify(dados), just]))[0].id;
const decidir = async (c: Ctx, id: string, aprovar: boolean, coment: string | null = null) =>
  (await c.q<{ s: string }>('select public.decidir_solicitacao($1, $2, $3) as s', [id, aprovar, coment]))[0].s;

describe('fluxo de aprovação', () => {
  it('coordenador pede troca de matrícula; secretária aprova; auditoria registra antes/depois', async () => {
    await cenario(async (c) => {
      const sv = await idServidor(c, '000105');
      await c.como('coordCofit');
      const id = await solicitar(c, 'servidor_alterar', sv, { matricula: '000555' }, 'Correção da matrícula');
      const [s] = await c.q<{ dados_antes: object; dados_depois: object; status: string; resumo: string }>(
        'select dados_antes, dados_depois, status, resumo from public.solicitacoes where id = $1', [id]);
      expect(s).toMatchObject({ dados_antes: { matricula: '000105' }, dados_depois: { matricula: '000555' }, status: 'pendente', resumo: 'Matrícula de Servidor H' });
      // não alterou ainda
      expect((await c.sistema('select matricula from public.servidores where id = $1', [sv]))[0].matricula).toBe('000105');

      await c.como('sec');
      const notif = await c.q('select * from public.notificacoes where tipo = $1', ['aprovacao_pedido']);
      expect(notif.length).toBe(1);
      expect(await decidir(c, id, true)).toBe('aprovada');
      expect((await c.sistema('select matricula from public.servidores where id = $1', [sv]))[0].matricula).toBe('000555');

      const aud = await c.q<{ ator_id: string; antes: { matricula: string }; depois: { matricula: string }; contexto: { solicitacao_id: string } }>(
        `select ator_id, antes, depois, contexto from public.auditoria where tabela = 'servidores' and registro_id = $1 and acao = 'update'`, [sv]);
      expect(aud.length).toBe(1);
      expect(aud[0]).toMatchObject({ ator_id: U.sec, antes: { matricula: '000105' }, depois: { matricula: '000555' }, contexto: { solicitacao_id: id } });

      await c.como('coordCofit');
      expect((await c.q('select * from public.notificacoes where tipo = $1', ['aprovacao_resultado'])).length).toBe(1);
    });
  });

  it('ninguém aprova o próprio pedido', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      const id = await solicitar(c, 'cargo_criar', null, { nome: 'Cargo Teste' });
      await c.falha('select public.decidir_solicitacao($1, true, null)', [id], /próprio pedido/);
      await c.como('admin');
      expect(await decidir(c, id, true)).toBe('aprovada');
      expect((await c.q(`select * from public.cargos where nome = 'Cargo Teste'`)).length).toBe(1);
    });
  });

  it('recusa exige comentário', async () => {
    await cenario(async (c) => {
      await c.como('dirDat');
      const id = await solicitar(c, 'unidade_criar', null,
        { sigla: 'NIBS', nome: 'Núcleo de IBS', tipo: 'coordenadoria', unidade_pai_id: await idUnidade(c, 'DAT') });
      await c.como('sec');
      await c.falha('select public.decidir_solicitacao($1, false, $2)', [id, '  '], /comentário/);
      expect(await decidir(c, id, false, 'Aguardar a lei')).toBe('recusada');
      expect((await c.sistema(`select * from public.unidades where sigla = 'NIBS'`)).length).toBe(0);
    });
  });

  it('pedido é bloqueado se o registro mudar antes da decisão', async () => {
    await cenario(async (c) => {
      const cofit = await idUnidade(c, 'COFIT');
      await c.como('sec');
      const id = await solicitar(c, 'unidade_alterar', cofit, { nome: 'Nome A' });
      await c.como('admin');
      const id2 = await solicitar(c, 'unidade_alterar', cofit, { nome: 'Nome B' });
      await c.como('sec');
      expect(await decidir(c, id2, true)).toBe('aprovada');
      await c.como('admin');
      expect(await decidir(c, id, true)).toBe('bloqueada');
      expect((await c.sistema('select nome from public.unidades where id = $1', [cofit]))[0].nome).toBe('Nome B');
    });
  });

  it('funcionário, diretor e coordenador não decidem', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      const id = await solicitar(c, 'cargo_criar', null, { nome: 'X1' });
      for (const q of ['funcA', 'coordCofit', 'dirDat'] as const) {
        await c.como(q);
        await c.falha('select public.decidir_solicitacao($1, true, null)', [id], /Somente a Secretária/);
      }
    });
  });

  it('escopo: coordenador não pede alteração de servidor de outra unidade; diretor não cria unidade fora da diretoria', async () => {
    await cenario(async (c) => {
      const b = await idServidor(c, '000201');
      const a = await idServidor(c, '000101');
      await c.como('coordCofit');
      await c.falha('select public.solicitar($1, $2, $3, $4)', ['servidor_alterar', b, '{"nome_completo":"X"}', 'Teste x'], /permissão/);
      // mover para unidade fora do escopo
      await c.falha('select public.solicitar($1, $2, $3, $4)',
        ['servidor_alterar', a, JSON.stringify({ unidade_id: await idUnidade(c, 'CONTA') }), 'Teste x'], /permissão/);
      await c.como('dirDat');
      await c.falha('select public.solicitar($1, $2, $3, $4)',
        ['unidade_criar', null, JSON.stringify({ sigla: 'X', nome: 'X', tipo: 'coordenadoria', unidade_pai_id: await idUnidade(c, 'DEFC') }), 'Teste x'],
        /permissão/);
      await c.como('funcA');
      await c.falha('select public.solicitar($1, $2, $3, $4)', ['servidor_alterar', a, '{"nome_completo":"Eu"}', 'Teste x'], /permissão/);
    });
  });

  it('campos fora da lista, dados inválidos e sem mudança são recusados', async () => {
    await cenario(async (c) => {
      const a = await idServidor(c, '000101');
      await c.como('sec');
      await c.falha('select public.solicitar($1, $2, $3, $4)', ['servidor_alterar', a, '{"id":"x"}', 'Teste x'], /Campo não permitido/);
      await c.falha('select public.solicitar($1, $2, $3, $4)', ['usuario_perfil', U.funcA, '{"perfil":"rei"}', 'Teste x'], /Dados inválidos/);
      await c.falha('select public.solicitar($1, $2, $3, $4)', ['servidor_alterar', a, '{"matricula":"000101"}', 'Teste x'], /Nenhuma alteração/);
      await c.falha('select public.solicitar($1, $2, $3, $4)', ['servidor_alterar', a, '{"matricula":"000102"}', 'Teste x'], /já cadastrada/);
      await c.falha('select public.solicitar($1, $2, $3, $4)', ['cargo_criar', null, '{"nome":"X"}', 'abc'], /check constraint/);
    });
  });

  it('perfil: secretária não promove a administrador; ninguém muda o próprio perfil', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      await c.falha('select public.solicitar($1, $2, $3, $4)', ['usuario_perfil', U.funcA, '{"perfil":"administrador"}', 'Teste x'], /permissão/);
      await c.falha('select public.solicitar($1, $2, $3, $4)', ['usuario_perfil', U.sec, '{"perfil":"diretor"}', 'Teste x'], /permissão/);
      const id = await solicitar(c, 'usuario_perfil', U.funcE, { perfil: 'coordenador' });
      await c.como('admin');
      await decidir(c, id, true);
      expect((await c.sistema('select perfil from public.usuarios where id = $1', [U.funcE]))[0].perfil).toBe('coordenador');
    });
  });

  it('acesso extra a outra unidade por aprovação', async () => {
    await cenario(async (c) => {
      const coef = await idUnidade(c, 'COEF');
      await c.como('dirDefc');
      const id = await solicitar(c, 'acesso_unidade_conceder', U.coordConta, { unidade_id: coef });
      await c.como('sec');
      await decidir(c, id, true);
      await c.como('coordConta');
      const siglas = (await c.q<{ sigla: string }>(
        `select distinct u.sigla from public.servidores s join public.unidades u on u.id = s.unidade_id`)).map((x) => x.sigla);
      expect(siglas).toEqual(expect.arrayContaining(['CONTA']));
      expect((await c.q('select * from public.usuario_unidades_extras')).length).toBe(1);
    });
  });

  it('estrutura: ciclo e tipo inválido barrados ao aplicar', async () => {
    await cenario(async (c) => {
      const dat = await idUnidade(c, 'DAT');
      const cofit = await idUnidade(c, 'COFIT');
      await c.como('sec');
      const id = await solicitar(c, 'unidade_alterar', dat, { unidade_pai_id: cofit });
      await c.como('admin');
      await c.falha('select public.decidir_solicitacao($1, true, null)', [id], /Diretoria deve estar ligada ao Gabinete/);
    });
  });

  it('feriado: alterar e excluir só por aprovação', async () => {
    await cenario(async (c) => {
      const f = (await c.sistema(`select id from public.feriados where data = '2026-12-25'`))[0].id as string;
      await c.como('sec');
      await c.falha(`update public.feriados set descricao = 'X' where id = $1`, [f], /permission denied/);
      const id = await solicitar(c, 'feriado_excluir', f, {});
      await c.como('admin');
      await decidir(c, id, true);
      expect((await c.sistema('select * from public.feriados where id = $1', [f])).length).toBe(0);
    });
  });

  it('listar_solicitacoes: secretária vê pendentes de todos; coordenador só os próprios', async () => {
    await cenario(async (c) => {
      await c.como('coordCofit');
      await solicitar(c, 'servidor_alterar', await idServidor(c, '000104'), { nome_completo: 'Servidor G Silva' });
      await c.como('dirDat');
      await solicitar(c, 'servidor_alterar', await idServidor(c, '000301'), { nome_completo: 'Servidor I Souza' });
      await c.como('sec');
      expect((await c.q(`select * from public.listar_solicitacoes('pendentes')`)).length).toBe(2);
      await c.como('coordCofit');
      const meus = await c.q<{ solicitante_nome: string }>(`select * from public.listar_solicitacoes('pendentes')`);
      expect(meus.length).toBe(1);
      expect(meus[0].solicitante_nome).toBe('Coordenador da COFIT');
    });
  });
});
