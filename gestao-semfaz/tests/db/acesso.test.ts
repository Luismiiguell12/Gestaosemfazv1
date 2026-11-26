import { describe, expect, it } from 'vitest';
import { cenario, contar, idServidor, idUnidade, U } from './helpers';

const TABELAS = [
  'unidades', 'cargos', 'servidores', 'usuarios', 'modulos', 'pacotes_padrao', 'usuario_modulos_extras',
  'usuario_unidades_extras', 'feriados', 'solicitacoes', 'notificacoes', 'auditoria', 'configuracoes', 'limites_requisicao',
];

describe('RLS habilitada em todas as tabelas', () => {
  it('nenhuma tabela pública sem RLS', async () => {
    await cenario(async (c) => {
      const r = await c.sistema(`select relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity`);
      expect(r).toEqual([]);
    });
  });
  it('funções SECURITY DEFINER têm search_path fixo', async () => {
    await cenario(async (c) => {
      const r = await c.sistema(`select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('public', 'app') and p.prosecdef
          and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) x where x like 'search_path=%')`);
      expect(r).toEqual([]);
    });
  });
});

describe('privilégios de funções', () => {
  it('nenhuma função executável por anon/PUBLIC', async () => {
    await cenario(async (c) => {
      const r = await c.sistema(`select n.nspname || '.' || p.proname as f from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('public', 'app') and has_function_privilege('anon', p.oid, 'execute')`);
      expect(r).toEqual([]);
    });
  });
  it('funções internas sensíveis não executáveis pela API', async () => {
    await cenario(async (c) => {
      const r = await c.sistema(`select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'app' and p.proname in ('registrar_evento', 'aplicar_solicitacao', 'atualizar_por_json', 'notificar')
          and has_function_privilege('authenticated', p.oid, 'execute')`);
      expect(r).toEqual([]);
    });
  });
});

describe('anon (sem login) não acessa nada', () => {
  for (const t of TABELAS) {
    it(`select em ${t} negado`, async () => {
      await cenario(async (c) => {
        await c.como('anon');
        await c.falha(`select * from public.${t}`, [], /permission denied/);
      });
    });
  }
  it('não executa RPCs', async () => {
    await cenario(async (c) => {
      await c.como('anon');
      await c.falha(`select public.minha_sessao()`, [], /permission denied/);
      await c.falha(`select * from public.busca_geral('cofit')`, [], /permission denied/);
      await c.falha(`select public.decidir_solicitacao(gen_random_uuid(), true, null)`, [], /permission denied/);
    });
  });
});

describe('token válido sem cadastro em usuarios', () => {
  it('não vê nada', async () => {
    await cenario(async (c) => {
      await c.como('estranho');
      for (const t of ['unidades', 'servidores', 'usuarios', 'feriados', 'solicitacoes']) {
        expect(await contar(c, `public.${t}`)).toBe(0);
      }
      const s = (await c.q<{ s: { autorizado: boolean } }>('select public.minha_sessao() as s'))[0].s;
      expect(s.autorizado).toBe(false);
    });
  });
});

describe('funcionário: leitura, criação, alteração e exclusão diretas pela API', () => {
  it('vê só o próprio servidor e o próprio usuário', async () => {
    await cenario(async (c) => {
      await c.como('funcA');
      const sv = await c.q<{ matricula: string }>('select matricula from public.servidores');
      expect(sv.map((x) => x.matricula)).toEqual(['000101']);
      const us = await c.q<{ id: string }>('select id from public.usuarios');
      expect(us.map((x) => x.id)).toEqual([U.funcA]);
    });
  });
  it('não cria servidor, unidade, cargo, usuário, feriado, notificação ou auditoria', async () => {
    await cenario(async (c) => {
      const cofit = await idUnidade(c, 'COFIT');
      const cargo = (await c.sistema(`select id from public.cargos limit 1`))[0].id;
      await c.como('funcA');
      await c.falha(`insert into public.servidores (nome_completo, matricula, cargo_id, unidade_id) values ('X', '999999', $1, $2)`,
        [cargo, cofit], /row-level security|permission denied/);
      await c.falha(`insert into public.unidades (sigla, nome, tipo, unidade_pai_id) values ('NOVA', 'Nova', 'coordenadoria', $1)`,
        [cofit], /permission denied/);
      await c.falha(`insert into public.cargos (nome) values ('Novo')`, [], /permission denied/);
      await c.falha(`insert into public.usuarios (id, servidor_id, perfil) values ($1, $2, 'administrador')`,
        [U.funcA, cofit], /permission denied/);
      await c.falha(`insert into public.feriados (data, descricao, abrangencia) values ('2027-08-01', 'X', 'municipal')`,
        [], /row-level security/);
      await c.falha(`insert into public.notificacoes (usuario_id, tipo, titulo) values ($1, 'x', 'x')`, [U.funcA], /permission denied/);
      await c.falha(`insert into public.auditoria (acao) values ('x')`, [], /permission denied/);
      await c.falha(`insert into public.usuario_modulos_extras (usuario_id, modulo_codigo, concedido_por) values ($1, 'contratos', $1)`,
        [U.funcA], /permission denied/);
    });
  });
  it('não altera nem apaga (inclusive o próprio perfil)', async () => {
    await cenario(async (c) => {
      await c.como('funcA');
      await c.falha(`update public.usuarios set perfil = 'administrador' where id = $1`, [U.funcA], /permission denied/);
      await c.falha(`update public.servidores set matricula = '123' where matricula = '000101'`, [], /permission denied/);
      await c.falha(`delete from public.servidores`, [], /permission denied/);
      await c.falha(`update public.unidades set nome = 'X'`, [], /permission denied/);
      await c.falha(`delete from public.feriados`, [], /permission denied/);
      await c.falha(`update public.solicitacoes set status = 'aprovada'`, [], /permission denied/);
      await c.falha(`delete from public.auditoria`, [], /permission denied/);
    });
  });
  it('não usa RPCs administrativas', async () => {
    await cenario(async (c) => {
      await c.como('funcA');
      await c.falha(`select public.conceder_modulo_extra($1, 'contratos')`, [U.funcA], /Somente a Secretária/);
      await c.falha(`select public.desativar_usuario($1)`, [U.funcE], /Somente a Secretária/);
      await c.falha(`select public.registrar_convite($1, $2, 'administrador')`, [U.funcA, U.funcA], /Somente a Secretária/);
      await c.falha(`select public.consumir_limite('x', 1, 1)`, [], /permission denied/);
      await c.falha(`select public.custom_access_token_hook('{}'::jsonb)`, [], /permission denied/);
      await c.falha(`select app.registrar_evento('x', null, null, null, null, null)`, [], /permission denied/);
    });
  });
  it('não lê auditoria nem solicitações de outros', async () => {
    await cenario(async (c) => {
      await c.como('funcA');
      expect(await contar(c, 'public.auditoria')).toBe(0);
      expect(await contar(c, 'public.solicitacoes')).toBe(0);
    });
  });
});

describe('usuário desativado perde acesso na hora (mesmo com token válido)', () => {
  it('desativação pela secretária corta leitura no próximo comando', async () => {
    await cenario(async (c) => {
      await c.como('coordCofit');
      expect(await contar(c, 'public.servidores')).toBeGreaterThan(1);
      await c.como('sec');
      await c.q('select public.desativar_usuario($1)', [U.coordCofit]);
      await c.como('coordCofit');
      expect(await contar(c, 'public.servidores')).toBe(0);
      expect(await contar(c, 'public.unidades')).toBe(0);
      const s = (await c.q<{ s: { autorizado: boolean; motivo: string } }>('select public.minha_sessao() as s'))[0].s;
      expect(s).toMatchObject({ autorizado: false, motivo: 'desativado' });
    });
  });
  it('servidor inativo também perde acesso', async () => {
    await cenario(async (c) => {
      await c.sistema(`update public.servidores set situacao = 'inativo' where matricula = '000101'`);
      await c.como('funcA');
      expect(await contar(c, 'public.unidades')).toBe(0);
    });
  });
  it('hook de token recusa usuário inativo e audita login', async () => {
    await cenario(async (c) => {
      const ok = await c.sistema(`select public.custom_access_token_hook(
        jsonb_build_object('user_id', $1::text, 'authentication_method', 'password', 'claims', '{"aal":"aal1"}'::jsonb)) as r`, [U.funcA]);
      expect((ok[0].r as { claims: { app_perfil: string } }).claims.app_perfil).toBe('funcionario');
      const log = await c.sistema(`select count(*)::int n from public.auditoria where acao = 'login' and ator_id = $1`, [U.funcA]);
      expect(log[0].n).toBe(1);
      await c.sistema(`update public.usuarios set ativo = false where id = $1`, [U.funcA]);
      const neg = await c.sistema(`select public.custom_access_token_hook(
        jsonb_build_object('user_id', $1::text, 'authentication_method', 'token_refresh', 'claims', '{}'::jsonb)) as r`, [U.funcA]);
      expect((neg[0].r as { error: { http_code: number } }).error.http_code).toBe(403);
    });
  });
  it('ninguém desativa a si mesmo; secretária não desativa administrador', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      await c.falha('select public.desativar_usuario($1)', [U.sec], /próprio usuário/);
      await c.falha('select public.desativar_usuario($1)', [U.admin], /Somente um administrador/);
    });
  });
});

describe('MFA obrigatória para administrador e secretária', () => {
  it('sem aal2 não vê dados nem decide', async () => {
    await cenario(async (c) => {
      for (const quem of ['sec', 'admin'] as const) {
        await c.como(quem, 'aal1');
        expect(await contar(c, 'public.unidades')).toBe(0);
        expect(await contar(c, 'public.servidores')).toBe(0);
        await c.falha('select public.decidir_solicitacao(gen_random_uuid(), true, null)', [], /Somente a Secretária/);
        await c.falha('select public.conceder_modulo_extra($1, $2)', [U.funcA, 'contratos'], /Somente a Secretária/);
        const s = (await c.q<{ s: { sessao_ok: boolean; mfa_exigida: boolean } }>('select public.minha_sessao() as s'))[0].s;
        expect(s).toMatchObject({ sessao_ok: false, mfa_exigida: true });
      }
    });
  });
  it('diretor sem aal2 continua com acesso (MFA recomendada)', async () => {
    await cenario(async (c) => {
      await c.como('dirDat', 'aal1');
      expect(await contar(c, 'public.unidades')).toBeGreaterThan(0);
    });
  });
});

describe('escopo por perfil', () => {
  const matriculasVisiveis = async (c: Parameters<Parameters<typeof cenario>[0]>[0]) =>
    (await c.q<{ matricula: string }>('select matricula from public.servidores order by matricula')).map((x) => x.matricula);

  it('coordenador vê só a própria unidade', async () => {
    await cenario(async (c) => {
      await c.como('coordCofit');
      expect(await matriculasVisiveis(c)).toEqual(['000101', '000102', '000103', '000104', '000105', '000106']);
    });
  });
  it('diretor vê a diretoria e as coordenadorias dela', async () => {
    await cenario(async (c) => {
      await c.como('dirDat');
      const m = await matriculasVisiveis(c);
      expect(m).toContain('000010');
      expect(m).toContain('000101');
      expect(m).toContain('000301');
      expect(m).not.toContain('000201'); // CONTA (DEFC)
      expect(m).not.toContain('000001'); // Gabinete
    });
  });
  it('secretária vê todos', async () => {
    await cenario(async (c) => {
      await c.como('sec');
      expect((await matriculasVisiveis(c)).length).toBe(13);
    });
  });
  it('acesso extra a outra unidade amplia o escopo do coordenador', async () => {
    await cenario(async (c) => {
      const coac = await idUnidade(c, 'COAC');
      await c.sistema('insert into public.usuario_unidades_extras (usuario_id, unidade_id) values ($1, $2)', [U.coordCofit, coac]);
      await c.como('coordCofit');
      expect(await matriculasVisiveis(c)).toContain('000301');
    });
  });
  it('usuários e módulos extras seguem o mesmo escopo', async () => {
    await cenario(async (c) => {
      await c.sistema(`insert into public.usuario_modulos_extras values ($1, 'contratos', $2, now())`, [U.funcB, U.sec]);
      await c.como('coordCofit');
      expect(await contar(c, 'public.usuario_modulos_extras')).toBe(0);
      const ids = (await c.q<{ id: string }>('select id from public.usuarios')).map((x) => x.id).sort();
      expect(ids).toEqual([U.coordCofit, U.funcA, U.funcE].sort());
      await c.como('coordConta');
      expect(await contar(c, 'public.usuario_modulos_extras')).toBe(1);
    });
  });
});

describe('matrícula obrigatória e única', () => {
  it('banco rejeita matrícula vazia, nula, inválida ou duplicada', async () => {
    await cenario(async (c) => {
      const cofit = await idUnidade(c, 'COFIT');
      const cargo = (await c.sistema(`select id from public.cargos limit 1`))[0].id;
      await c.como('sec');
      const ins = `insert into public.servidores (nome_completo, matricula, cargo_id, unidade_id) values ('Novo', $1, $2, $3)`;
      await c.falha(ins, [null, cargo, cofit], /null value/);
      await c.falha(ins, ['', cargo, cofit], /check constraint/);
      await c.falha(ins, ['   ', cargo, cofit], /check constraint/);
      await c.falha(ins, ['000101', cargo, cofit], /duplicate key/);
      await c.falha(ins, ['12 34', cargo, cofit], /check constraint/);
      await c.q(ins, ['000999', cargo, cofit]);
      await c.falha(ins, ['000999', cargo, cofit], /duplicate key/);
    });
  });
  it('usuário com login exige e-mail institucional', async () => {
    await cenario(async (c) => {
      const f = await idServidor(c, '000103');
      await c.sistema(`insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000f1', 'x@exemplo.gov.br')`);
      await c.falha(`insert into public.usuarios (id, servidor_id, perfil) values ('00000000-0000-0000-0000-0000000000f1', $1, 'funcionario')`,
        [f], /permission denied/);
      await c.sistemaFalha(`insert into public.usuarios (id, servidor_id, perfil) values ('00000000-0000-0000-0000-0000000000f1', $1, 'funcionario')`,
        [f], /e-mail institucional/);
      await c.sistemaFalha(`update public.servidores set email_institucional = null where matricula = '000101'`, [], /obrigatório para quem tem login/);
    });
  });
});
