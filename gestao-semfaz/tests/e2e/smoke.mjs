// Fumaça E2E: serve o export estático (out/) e simula a API do Supabase com dados FICTÍCIOS.
// Verifica: CSP presente e sem violações, guarda de login, MFA, telas principais, celular sem rolagem lateral.
// Uso: npm run build (com NEXT_PUBLIC_SUPABASE_URL=https://exemplo.supabase.co) && npm run test:e2e
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readFileSync, statSync } from 'node:fs';
import { extname, join } from 'node:path';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); } catch { ({ chromium } = require(process.env.PLAYWRIGHT_PATH ?? '/opt/node22/lib/node_modules/playwright')); }

const OUT = new URL('../../out/', import.meta.url).pathname;
const SHOTS = process.env.SHOTS_DIR ?? new URL('../../test-results/telas/', import.meta.url).pathname;
mkdirSync(SHOTS, { recursive: true });
const API = 'https://exemplo.supabase.co';
const TIPOS = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.woff2': 'font/woff2', '.woff': 'font/woff', '.webmanifest': 'application/manifest+json', '.txt': 'text/plain' };

const servidor = createServer((req, res) => {
  let p = join(OUT, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (existsSync(p) && statSync(p).isDirectory()) p = join(p, 'index.html');
  if (!existsSync(p)) { res.writeHead(404); res.end(readFileSync(join(OUT, '404.html'))); return; }
  res.writeHead(200, { 'content-type': TIPOS[extname(p)] ?? 'application/octet-stream' });
  res.end(readFileSync(p));
}).listen(4173);
const BASE = 'http://localhost:4173';

// ---------- dados fictícios ----------
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const jwt = (aal) => `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub: 'u-sec', role: 'authenticated', aal, exp: 4102444800 })}.assinatura`;
const sessao = (aal) => ({ access_token: jwt(aal), refresh_token: 'r', token_type: 'bearer', expires_in: 3600, expires_at: 4102444800, user: { id: 'u-sec', email: 'secretaria@exemplo.gov.br', aud: 'authenticated', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' } });
const UN = (id, sigla, nome, tipo, pai, ordem) => ({ id, sigla, nome, tipo, unidade_pai_id: pai, ordem, ativa: true });
const unidades = [
  UN('gab', 'Gabinete', 'Gabinete do Secretário', 'gabinete', null, 0), UN('asplan', 'ASPLAN', 'ASPLAN', 'assessoria', 'gab', 1),
  UN('astin', 'ASTIN', 'ASTIN', 'assessoria', 'gab', 2), UN('jur', 'Jurídica', 'Assessoria Jurídica', 'assessoria', 'gab', 3),
  UN('pav', 'PAV', 'Coordenadoria do PAV e da Ordem Cronológica', 'coordenadoria', 'gab', 4),
  UN('dat', 'DAT', 'Diretoria de Administração Tributária', 'diretoria', 'gab', 5), UN('defc', 'DEFC', 'Diretoria de Execução Financeira e Contabilidade', 'diretoria', 'gab', 6),
  UN('coacam', 'COACAM', 'COACAM', 'coordenadoria', 'dat', 1), UN('cofit', 'COFIT', 'Coordenadoria de Fiscalização e Tributos', 'coordenadoria', 'dat', 2),
  UN('coac', 'COAC', 'COAC', 'coordenadoria', 'dat', 3), UN('cocmi', 'COCMI', 'COCMI', 'coordenadoria', 'dat', 4),
  UN('conta', 'CONTA', 'CONTA', 'coordenadoria', 'defc', 1), UN('coef', 'COEF', 'COEF', 'coordenadoria', 'defc', 2),
];
const cargos = [{ id: 'c1', nome: 'Auditor Fiscal', ativo: true }, { id: 'c2', nome: 'Agente Administrativo', ativo: true }, { id: 'c3', nome: 'Coordenador(a)', ativo: true }];
const servidores = [
  ['s1', 'Coordenador da COFIT', '000106', 'c3', 'coordenador.cofit@exemplo.gov.br'], ['s2', 'Servidor A', '000101', 'c1', 'servidor.a@exemplo.gov.br'],
  ['s3', 'Servidor E', '000102', 'c1', 'servidor.e@exemplo.gov.br'], ['s4', 'Servidor F', '000103', 'c1', null], ['s5', 'Servidor G', '000104', 'c2', null],
].map(([id, nome_completo, matricula, cargo_id, email_institucional]) => ({ id, nome_completo, matricula, cargo_id, unidade_id: 'cofit', situacao: 'ativo', email_institucional }));
const usuarios = [{ id: 'u1', servidor_id: 's1', perfil: 'coordenador', ativo: true }, { id: 'u2', servidor_id: 's2', perfil: 'funcionario', ativo: true }, { id: 'u3', servidor_id: 's3', perfil: 'funcionario', ativo: true }];
const M = (codigo, nome, rota, icone, ordem, status) => ({ codigo, nome, rota, icone, ordem, status, no_menu: true });
const modulos = [
  M('painel', 'Painel', '/', 'painel', 10, 'ativo'), M('demandas', 'Demandas', '/demandas', 'demandas', 20, 'ativo'), M('calendario', 'Calendário', '/calendario', 'calendario', 30, 'ativo'),
  M('contratos', 'Contratos de locação', '/contratos', 'contratos', 40, 'ativo'), M('unidades_consumidoras', 'Unidades consumidoras', '/unidades-consumidoras', 'energia', 50, 'ativo'),
  M('ferias', 'Férias e folgas', '/ferias', 'ferias', 60, 'ativo'), M('folhas_ponto', 'Folhas de ponto', '/folhas-ponto', 'relogio', 70, 'ativo'),
  M('produtividade', 'Produtividade', '/produtividade', 'grafico', 80, 'em_definicao'), M('aprovacoes', 'Aprovações', '/aprovacoes', 'aprovacoes', 90, 'ativo'),
  M('relatorios', 'Relatórios', '/relatorios', 'relatorios', 100, 'ativo'), M('usuarios', 'Unidades e usuários', '/usuarios', 'usuarios', 110, 'ativo'),
  M('obrigacoes_fiscais', 'Obrigações fiscais', '/obrigacoes-fiscais', 'recibo', 120, 'em_breve'),
];
const pedidos = [
  { id: 'p1', tipo: 'servidor_alterar', resumo: 'Servidor Servidor G · matrícula', alvo_id: 's5', dados_antes: { matricula: '000104' }, dados_depois: { matricula: '000555' }, justificativa: 'Correção conforme portaria nº 000/2026.', anexo_path: null, status: 'pendente', criado_em: new Date(Date.now() - 86400000).toISOString(), solicitante_id: 'u1', solicitante_nome: 'Coordenador da COFIT', decidido_por_nome: null, decidido_em: null, comentario_decisao: null },
  { id: 'p2', tipo: 'unidade_criar', resumo: 'Nova unidade: Núcleo de IBS', alvo_id: null, dados_antes: {}, dados_depois: { sigla: 'NIBS', nome: 'Núcleo de IBS', tipo: 'coordenadoria', unidade_pai_id: 'dat' }, justificativa: 'Reforma 2027.', anexo_path: null, status: 'pendente', criado_em: '2026-11-24T13:00:00Z', solicitante_id: 'u9', solicitante_nome: 'Diretor da DAT', decidido_por_nome: null, decidido_em: null, comentario_decisao: null },
];
const info = (perfil, aal) => ({ autorizado: true, usuario_id: 'u-sec', servidor_id: perfil === 'funcionario' ? 's2' : 's9', perfil, nome: perfil === 'funcionario' ? 'Servidor A' : 'Secretária Exemplo', cargo: perfil === 'funcionario' ? 'Auditor Fiscal' : 'Secretário(a)', unidade_id: perfil === 'funcionario' ? 'cofit' : 'gab', unidade_sigla: 'Gabinete', mfa_exigida: perfil === 'secretaria', aal, sessao_ok: perfil !== 'secretaria' || aal === 'aal2', modulos: perfil === 'funcionario' ? ['painel', 'demandas', 'calendario', 'ferias', 'produtividade'] : [...modulos.map((m) => m.codigo), 'auditoria'] });

async function simularApi(page, perfil, aal) {
  await page.route(`${API}/**`, async (route) => {
    const u = new URL(route.request().url());
    const p = u.pathname;
    const json = (d) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(d) });
    if (p.endsWith('/rpc/minha_sessao')) return json(info(perfil, aal));
    if (p.endsWith('/rpc/minhas_unidades_escopo')) return json(unidades.map((x) => x.id));
    if (p.endsWith('/rpc/listar_solicitacoes')) return json(pedidos);
    if (p.endsWith('/rpc/ausencias_do_mes')) return json([{ afastamento_id: 'a1', servidor: 'Servidor A', unidade: 'COFIT', tipo: 'ferias', inicio: '2026-11-03', fim: '2026-11-22', substituto: 'Servidor F' }]);
    if (p.endsWith('/rpc/situacao_entregas')) return json([
      { unidade_id: 'cofit', sigla: 'COFIT', ordem: 2, situacao: 'enviada', enviada_em: '2026-11-03', recebida_por: 'Coordenador da COFIT', devolvida_em: null, devolvida_por: null, atrasada: true },
      { unidade_id: 'conta', sigla: 'CONTA', ordem: 1, situacao: 'devolvida', enviada_em: '2026-11-03', recebida_por: 'Servidor B', devolvida_em: '2026-11-06', devolvida_por: 'Servidor B', atrasada: false },
      { unidade_id: 'coac', sigla: 'COAC', ordem: 3, situacao: 'nao_enviada', enviada_em: null, recebida_por: null, devolvida_em: null, devolvida_por: null, atrasada: false }]);
    if (p.endsWith('/rpc/paginas_do_lote')) return json([
      { pagina: 1, matricula_lida: '000101', nome_lido: 'Servidor A', servidor_id: 's2', servidor: 'Servidor A', unidade_id: 'cofit', unidade: 'COFIT', ordem_unidade: 2 },
      { pagina: 2, matricula_lida: '000777', nome_lido: 'Servidor X', servidor_id: null, servidor: null, unidade_id: null, unidade: null, ordem_unidade: null }]);
    if (p.endsWith('/rpc/conflitos_mesmo_cargo')) return json([{ nome: 'Servidor A', inicio: '2026-07-05', fim: '2026-07-24', status: 'aprovado' }]);
    const hoje = new Date().toISOString().slice(0, 10);
    const dl = (id, numero, titulo, unidade, status, prioridade, dias, extra = {}) => ({ id, numero, titulo, origem: 'processo', numero_processo: null, unidade_id: unidade.toLowerCase(), unidade, prioridade, status, prazo: hoje, dias_uteis: dias, concluida_em: status === 'concluida' ? '2026-11-24T12:00:00Z' : null,
      responsaveis: [{ servidor_id: 's2', nome: 'Servidor A', papel: 'titular' }, { servidor_id: 's3', nome: 'Servidor E', papel: 'titular' }], etapas_total: 5, etapas_feitas: 3, criado_por: 'u1', sou_responsavel: true, ...extra });
    if (p.endsWith('/rpc/listar_demandas')) return json([
      dl('d1', 101, 'Parecer sobre impugnação de lançamento', 'COFIT', 'a_fazer', 'alta', 3),
      dl('d2', 102, 'Relatório de fiscalização ISS – lote 3', 'COFIT', 'em_andamento', 'critica', -2),
      dl('d3', 103, 'Retorno da PGM sobre dívida ativa', 'COFIT', 'aguardando_terceiros', 'media', 6),
      dl('d4', 104, 'Plano de ações 2027 – fiscalização', 'COFIT', 'em_revisao', 'alta', 15),
      dl('d5', 105, 'Inventário de processos de ISS', 'COACAM', 'concluida', 'media', 0),
      dl('d6', 106, 'Atualizar cadastro de imóveis', 'COFIT', 'sugerida', 'baixa', 8, { criado_por: 'u9' })]);
    if (p.endsWith('/rpc/demanda_detalhe')) return json({
      demanda: { id: 'd2', numero: 102, titulo: 'Relatório de fiscalização ISS – lote 3', descricao: 'Consolidar as autuações do lote 3.', origem: 'processo', numero_processo: '1234/2026', unidade_id: 'cofit', unidade: 'COFIT', prioridade: 'critica', status: 'em_andamento', prazo: hoje, dias_uteis: -2, concluida_em: null, criado_em: '2026-11-10T12:00:00Z', criado_por_nome: 'Coordenador da COFIT', recorrencia_id: null },
      permissoes: { gerir: true, responsavel: false, anexar: true, proprio_criador: false },
      responsaveis: [{ servidor_id: 's2', nome: 'Servidor A', papel: 'titular' }, { servidor_id: 's4', nome: 'Servidor F', papel: 'substituto' }],
      checklist: [{ id: 'c1', texto: 'Levantar dados', feito: true, responsavel: null, feito_por: 'Servidor A', feito_em: '2026-11-20T12:00:00Z' }, { id: 'c2', texto: 'Redigir', feito: false, responsavel: 'Servidor A', feito_por: null, feito_em: null }],
      mensagens: [{ id: 'm1', tipo: 'mensagem', texto: 'Lote 3 quase pronto, falta revisar @Servidor E', autor_id: 'u2', autor: 'Servidor A', criado_em: '2026-11-25T13:00:00Z', editado_em: null, feedback: 'ajustar', feedback_comentario: 'Detalhar autuações', feedback_por: 'Coordenador da COFIT', anexo: null },
        { id: 'm2', tipo: 'pedido_atualizacao', texto: 'Por favor, relate o andamento desta demanda.', autor_id: 'u-sec', autor: 'Secretária Exemplo', criado_em: '2026-11-26T13:00:00Z', editado_em: null, feedback: null, feedback_comentario: null, feedback_por: null, anexo: null }],
      anexos: [{ id: 'a1', nome: 'parecer.pdf', path: 'demandas/d2/x.pdf', tipo: 'pdf', tamanho: 1000, versao: 2, substitui_id: null, enviado_por: 'Servidor A', enviado_em: '2026-11-24T12:00:00Z' }],
      historico: [{ em: '2026-11-25T13:00:00Z', ator: 'Coordenador da COFIT', acao: 'feedback', detalhes: { feedback: 'Ajustar', comentario: 'Detalhar autuações' } }, { em: '2026-11-10T12:00:00Z', ator: 'Coordenador da COFIT', acao: 'criada', detalhes: {} }] });
    if (p.endsWith('/rpc/eventos_calendario')) return json([
      { tipo: 'compromisso', id: 'e1', titulo: 'Reunião de planejamento', inicio: `${hoje}T12:00:00Z`, fim: `${hoje}T13:30:00Z`, dia_inteiro: false, unidade_id: 'cofit', unidade: 'COFIT', local: 'Sala da DAT', descricao: null, participantes: [{ servidor_id: 's2', nome: 'Servidor A' }], editavel: true },
      { tipo: 'demanda', id: 'd2', titulo: '#102 Relatório de fiscalização', inicio: `${hoje}T00:00:00Z`, fim: `${hoje}T00:00:00Z`, dia_inteiro: true, unidade_id: 'cofit', unidade: 'COFIT', local: null, descricao: null, participantes: [], editavel: false }]);
    if (p.endsWith('/rpc/painel_unidades')) return json(unidades.map((u, i) => ({ unidade_id: u.id, a_fazer: 2, em_andamento: 3, concluidas: 4, atrasadas: i % 4 === 1 ? 2 : 0, apertadas: i % 4 === 2 ? 1 : 0, concluidas_90: 10, no_prazo_90: 8 })));
    if (p.endsWith('/rpc/meus_indicadores')) return json({ abertas: 4, atrasadas: 1, concluidas_mes: 7, no_prazo_pct: 86, por_mes: ['2026-06', '2026-07', '2026-08', '2026-09', '2026-10', '2026-11'].map((mes, i) => ({ mes, concluidas: [5, 6, 4, 8, 6, 7][i] })) });
    if (p.endsWith('/rpc/painel_contratos')) return json({ vencendo: 3, vencendo_30: 1, vencidos: 0, alugueis_pendentes: 2, alugueis_pendentes_valor: 7480, proximos: [{ id: 'ct1', numero: '014/2024', imovel_descricao: 'Imóvel da COAC', fim_vigencia: '2026-12-14', dias: 18 }] });
    if (p.endsWith('/rpc/listar_contratos')) return json([
      { id: 'ct1', numero: '014/2024', locador: 'Locador Exemplo 1', imovel: 'Imóvel da COAC', unidade: 'COFIT', fim_vigencia: '2026-12-14', dias_restantes: 18, valor_mensal: 3740, fiscal: 'Servidor A', encerrado: false, alugueis_atrasados: 1, aditivos: 1 },
      { id: 'ct2', numero: '022/2024', locador: 'Imobiliária Exemplo', imovel: 'Arquivo central', unidade: null, fim_vigencia: '2027-08-31', dias_restantes: 278, valor_mensal: 5200, fiscal: null, encerrado: false, alugueis_atrasados: 0, aditivos: 0 },
    ]);
    if (p.endsWith('/rpc/contrato_ficha')) return json({
      contrato: { id: 'ct1', numero: '014/2024', processo: '0000/2024', imovel_descricao: 'Imóvel da COAC', imovel_endereco: 'Rua Exemplo, 100 – Centro', unidade_ocupante_id: 'cofit', unidade: 'COFIT', inicio: '2024-12-15', fim_original: '2025-12-14', fim_vigencia: '2026-12-14', valor_mensal: 3740, valor_anual: 44880, dia_vencimento: 10, fiscal_servidor_id: 's2', fiscal: 'Servidor A', indice_reajuste: 'IPCA', mes_database: 12, encerrado: false, dias_restantes: 18 },
      locador: { id: 'l1', tipo: 'PF', nome: 'Locador Exemplo 1', documento: '***.982.247-**', email: 'lo***@exemplo.com', telefone: '(79) *****-1234', mascarado: true, pode_ver_completo: false },
      aditivos: [{ id: 'ad1', numero: 1, altera_prazo: true, altera_valor: true, novo_fim: '2026-12-14', novo_valor: 3740, data_assinatura: '2025-12-12', descricao: null }],
      alugueis: [['2026-09-01', '2026-09-08', 'pago'], ['2026-10-01', '2026-10-05', 'pago'], ['2026-11-01', null, 'atrasado'], ['2026-12-01', null, 'pendente']].map(([c, pg, s], i) => ({ id: `al${i}`, competencia: c, valor: 3740, vencimento: c.slice(0, 8) + '10', pago_em: pg, valor_pago: pg ? 3740 : null, situacao: s })),
      ucs: [{ id: 'uc1', fornecedor: 'energisa', numero: '0000001', descricao: null, ultima: { competencia: '2026-10-01', valor: 389.2, pago_em: '2026-11-18', vencimento: '2026-11-20' } }, { id: 'uc2', fornecedor: 'igua', numero: '000002', descricao: null, ultima: { competencia: '2026-10-01', valor: 142.7, pago_em: null, vencimento: '2026-12-30' } }],
      documentos: [{ id: 'doc1', nome: 'Contrato_014-2024.pdf', path: 'contratos/ct1/x.pdf', tamanho: 1000, aditivo_id: null, enviado_em: '2024-12-15T12:00:00Z', enviado_por: 'Servidor C' }],
      historico: [{ em: '2026-11-05T12:00:00Z', acao: 'pagamento', detalhes: { competencia: '10/2026', valor: 3740 }, ator: 'Servidor C' }, { em: '2025-12-12T12:00:00Z', acao: 'aditivo', detalhes: { numero: 1 }, ator: 'Administrador do sistema' }, { em: '2024-12-15T12:00:00Z', acao: 'importado', detalhes: {}, ator: 'Servidor C' }],
      renovacao: { demanda_id: 'd2', numero: 150, status: 'a_fazer' }, pendentes: 0,
    });
    if (p.endsWith('/rpc/ucs_competencia')) return json([
      { uc_id: 'uc1', fornecedor: 'energisa', numero: '0000001', descricao: null, contrato_id: 'ct1', contrato_numero: '014/2024', imovel: 'Imóvel da COAC', fatura_id: 'f1', consumo: 412, valor: 389.2, vencimento: '2026-11-20', pago_em: '2026-11-18', situacao: 'paga' },
      { uc_id: 'uc2', fornecedor: 'igua', numero: '000002', descricao: null, contrato_id: 'ct1', contrato_numero: '014/2024', imovel: 'Imóvel da COAC', fatura_id: 'f2', consumo: 18, valor: 142.7, vencimento: '2026-12-30', pago_em: null, situacao: 'pendente' },
      { uc_id: 'uc3', fornecedor: 'cercos', numero: '0000031', descricao: null, contrato_id: 'ct2', contrato_numero: '022/2024', imovel: 'Arquivo central', fatura_id: 'f3', consumo: 210, valor: 196.5, vencimento: '2026-11-12', pago_em: null, situacao: 'atrasada' },
      { uc_id: 'uc4', fornecedor: 'energisa', numero: '0000011', descricao: null, contrato_id: 'ct2', contrato_numero: '022/2024', imovel: 'Arquivo central', fatura_id: null, consumo: null, valor: null, vencimento: null, pago_em: null, situacao: 'sem_lancamento' },
    ]);
    if (p.endsWith('/rpc/relatorio_demandas_unidade')) return json([{ unidade: 'COFIT', abertas: 5, atrasadas: 2, criadas_periodo: 7, concluidas_periodo: 9, concluidas_no_prazo: 8, no_prazo_pct: 89 }, { unidade: 'CONTA', abertas: 3, atrasadas: 0, criadas_periodo: 2, concluidas_periodo: 4, concluidas_no_prazo: 4, no_prazo_pct: 100 }]);
    if (p.endsWith('/rpc/relatorio_alugueis')) return json([{ competencia: '2026-10-01', contrato: '014/2024', locador: 'Locador Exemplo 1', imovel: 'Imóvel da COAC', valor: 3740, vencimento: '2026-10-10', pago_em: '2026-10-05', valor_pago: 3740, situacao: 'pago' }]);
    if (p.endsWith('/rpc/registrar_exportacao')) return route.fulfill({ status: 204, body: '' });
    if (p.endsWith('/rpc/busca_geral')) return json([{ tipo: 'unidade', id: 'cofit', titulo: 'COFIT', subtitulo: 'Coordenadoria de Fiscalização e Tributos', rota: '/usuarios?unidade=cofit' }]);
    const t = p.split('/').pop();
    const ano = new Date().getFullYear();
    const afastamentos = [
      { id: 'af1', servidor_id: 's2', tipo: 'ferias', inicio: `${ano}-07-05`, fim: `${ano}-07-24`, status: 'aprovado', conflito_mesmo_cargo: false, substituto_id: 's4', observacao: null, solicitado_por: 'u2' },
      { id: 'af2', servidor_id: 's3', tipo: 'ferias', inicio: `${ano}-07-10`, fim: `${ano}-07-20`, status: 'solicitado', conflito_mesmo_cargo: true, substituto_id: null, observacao: null, solicitado_por: 'u3' },
      { id: 'af3', servidor_id: 's4', tipo: 'licenca_premio', inicio: `${ano}-10-01`, fim: `${ano}-10-31`, status: 'aprovado', conflito_mesmo_cargo: false, substituto_id: 's5', observacao: null, solicitado_por: 'u1' }];
    const saldos_servidor = servidores.map((sv, i) => ({ servidor_id: sv.id, ferias_dias: 30 - i * 5, licenca_premio_dias: i * 30, folgas: i, fonte: 'Levantamento do RH', atualizado_em: '2026-11-20T12:00:00Z' }));
    const folhas_lotes = [{ id: 'l1', competencia: '2026-11-01', arquivo_path: 'lotes/l1/original.pdf', total_paginas: 2, concluido: true, criado_em: '2026-11-26T13:42:00Z' }];
    const folhas_arquivos = [
      { id: 'f1', lote_id: 'l1', unidade_id: 'cofit', path: 'lotes/l1/unidades/cofit-1.pdf', paginas: 1, servidores: 1, criado_em: '2026-11-26T13:42:00Z' },
      { id: 'f2', lote_id: 'l1', unidade_id: null, path: 'lotes/l1/unidades/sem-unidade-1.pdf', paginas: 1, servidores: 1, criado_em: '2026-11-26T13:42:00Z' }];
    const tabelas = { recorrencias: [], afastamentos, saldos_servidor, folhas_lotes, folhas_arquivos, configuracoes: [], unidades, cargos, servidores, usuarios, modulos, pacotes_padrao: [], usuario_modulos_extras: [], usuario_unidades_extras: [], notificacoes: [], feriados: [{ id: 'f1', data: '2026-12-25', descricao: 'Natal', abrangencia: 'nacional' }], auditoria: [] };
    if (t in tabelas) return json(tabelas[t]);
    if (p.includes('/auth/v1/factors') || p.includes('/auth/v1/user')) return json({ id: 'u-sec', factors: [] });
    return json([]);
  });
}

const erros = [];
const browser = await chromium.launch();
const passos = [];
// cada passo tenta 2x (CI às vezes é lento); a 1ª falha aparece no log como "instável"
async function passo(nome, fn) {
  if (process.env.E2E_SO && !nome.includes(process.env.E2E_SO)) return;
  if (process.env.E2E_VERBOSE) console.log('> ' + nome);
  let primeira = null;
  for (let tentativa = 1; tentativa <= 2; tentativa++) {
    try {
      await fn();
      passos.push(['ok', nome, primeira ? `instável: passou na 2ª tentativa (1ª: ${primeira})` : '']);
      return;
    } catch (e) { primeira ??= e.message.split('\n')[0]; if (process.env.E2E_VERBOSE) console.log(e.message.split('\n').slice(0, 4).join(' | ')); }
  }
  passos.push(['FALHOU', nome, primeira]);
}
async function novaPagina({ mobile = false, perfil, aal = 'aal2' } = {}) {
  const ctx = await browser.newContext(mobile ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, isMobile: true, hasTouch: true } : { viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  page.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) erros.push(m.text()); });
  page.on('pageerror', (e) => erros.push(e.message));
  if (perfil) {
    await simularApi(page, perfil, aal);
    await ctx.addInitScript((s) => localStorage.setItem('sb-exemplo-auth-token', s), JSON.stringify(sessao(aal)));
  }
  return page;
}

await passo('login: página renderiza com CSP e sem cadastro público', async () => {
  const page = await novaPagina();
  await page.goto(`${BASE}/login/`);
  await page.getByRole('heading', { name: 'Entrar' }).waitFor();
  const csp = await page.locator('meta[http-equiv="Content-Security-Policy"]').getAttribute('content');
  assert.match(csp, /script-src 'self' 'sha256-/);
  assert.doesNotMatch(csp, /script-src[^;]*unsafe-inline/);
  assert.match(csp, /object-src 'none'/);
  assert.equal(await page.getByText(/cadastre-se|criar conta/i).count(), 0);
  await page.screenshot({ path: `${SHOTS}/login.png` });
});

await passo('sem sessão: painel redireciona para login', async () => {
  const page = await novaPagina();
  await page.goto(`${BASE}/`);
  await page.waitForURL(/\/login\/?$/);
});

await passo('secretária sem MFA (aal1) vai para /mfa', async () => {
  const page = await novaPagina({ perfil: 'secretaria', aal: 'aal1' });
  await page.goto(`${BASE}/`);
  await page.waitForURL(/\/mfa\/?$/);
});

await passo('painel da secretária (desktop) segue o protótipo', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/`);
  await page.getByRole('heading', { name: 'Como estão as unidades' }).waitFor();
  for (const t of ['Aguardando sua aprovação', 'Contratos perto do vencimento', 'Próximos compromissos', 'Ausências neste mês', 'Ligadas ao Gabinete', 'DAT · Administração Tributária']) await page.getByText(t, { exact: true }).first().waitFor();
  assert.equal(await page.locator('nav[aria-label="Menu principal"] [aria-disabled="true"]').count(), 2);
  await page.getByText('1 em menos de 30 dias').waitFor();
  await page.getByText('Contrato 014/2024').first().waitFor();
  await page.getByText('Com atraso', { exact: true }).first().waitFor();
  await page.getByText('Reunião de planejamento').first().waitFor();
  await page.getByText('Folhas de ponto a devolver').waitFor();
  await page.getByText('substituto: Servidor F').waitFor();
  await page.getByText('Nova unidade: Núcleo de IBS').first().waitFor();
  await page.screenshot({ path: `${SHOTS}/painel-secretaria.png`, fullPage: true });
});

await passo('busca geral agrupa resultados', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/`);
  await page.getByLabel('Busca geral').fill('cofit');
  await page.getByText('Unidades administrativas').waitFor();
});

await passo('central de aprovações: antes/depois e botões', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/aprovacoes/`);
  await page.getByRole('button', { name: 'Aprovar alteração' }).waitFor();
  await page.getByText('000104').waitFor();
  await page.getByText('000555').waitFor();
  await page.screenshot({ path: `${SHOTS}/aprovacoes.png`, fullPage: true });
});

await passo('unidades e usuários: árvore, tabela e perfis', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/usuarios/?unidade=cofit`);
  await page.getByRole('heading', { name: 'COFIT · 5 servidores' }).waitFor();
  await page.getByText('Perfis do sistema').waitFor();
  await page.screenshot({ path: `${SHOTS}/usuarios.png`, fullPage: true });
  await page.getByText('Servidor A', { exact: true }).click();
  await page.getByRole('dialog').getByText('Módulos extras').waitFor();
  await page.screenshot({ path: `${SHOTS}/usuarios-detalhe.png` });
});

await passo('feriados e relatórios (prévia e exportação Excel/PDF)', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/calendario/feriados/`);
  await page.getByText('Natal').waitFor();
  await page.screenshot({ path: `${SHOTS}/feriados.png`, fullPage: true });
  await page.goto(`${BASE}/relatorios/`);
  await page.getByRole('heading', { name: 'Demandas por unidade' }).waitFor();
  assert.equal(await page.getByRole('button', { name: /Produtividade/ }).isDisabled(), true);
  await page.getByRole('button', { name: 'Ver na tela' }).click();
  await page.getByRole('cell', { name: '89%' }).waitFor();
  await page.screenshot({ path: `${SHOTS}/relatorios.png`, fullPage: true });
  await page.getByRole('button', { name: /Aluguéis/ }).first().click();
  await page.getByLabel('Excel').check();
  const [arq] = await Promise.all([page.waitForEvent('download'), page.getByRole('button', { name: 'Gerar relatório' }).click()]);
  assert.match(arq.suggestedFilename(), /^alugueis-\d{4}-\d{2}-\d{2}\.xlsx$/);
  const bytes = readFileSync(await arq.path());
  assert.equal(bytes.subarray(0, 2).toString(), 'PK');
  await page.getByLabel('PDF').check();
  const [pdf] = await Promise.all([page.waitForEvent('download'), page.getByRole('button', { name: 'Gerar relatório' }).click()]);
  assert.equal(readFileSync(await pdf.path()).subarray(0, 5).toString(), '%PDF-');
});

await passo('férias: escala, aviso de mesmo cargo, saldos', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/ferias/`);
  await page.getByText('Atenção para a chefia:').waitFor();
  await page.getByRole('button', { name: 'Aprovar mesmo assim' }).waitFor();
  await page.getByText('Saldos por servidor').waitFor();
  await page.getByText('Fonte: levantamento do RH, importado em 20/11/2026').waitFor();
  await page.screenshot({ path: `${SHOTS}/ferias.png`, fullPage: true });
  await page.getByRole('button', { name: 'Aprovar mesmo assim' }).click();
  await page.getByText('Substituto (mesma unidade, obrigatório)').waitFor();
});

await passo('folhas de ponto: etapas, separação, pendências e entrega', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/folhas-ponto/`);
  await page.getByText('Separado por unidade').waitFor();
  await page.getByText('1 página(s) sem servidor no cadastro').waitFor();
  await page.getByText('Controle de entrega').first().waitFor();
  await page.getByText('Atrasada').first().waitFor();
  await page.screenshot({ path: `${SHOTS}/folhas-ponto.png`, fullPage: true });
});

await passo('importação de servidores: dialogo com modelo e prévia', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/usuarios/?unidade=cofit`);
  await page.getByRole('button', { name: 'Importar servidores (planilha)' }).click();
  await page.getByRole('button', { name: 'Baixar modelo de planilha' }).waitFor();
  await page.screenshot({ path: `${SHOTS}/importar-servidores.png` });
});

await passo('demandas: quadro com 5 colunas, cartões e sugestões', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/demandas/`);
  for (const c of ['A fazer', 'Em andamento', 'Aguardando terceiros', 'Em revisão', 'Concluída']) await page.getByRole('heading', { name: c }).waitFor();
  await page.getByText('atrasada 2 dias úteis').waitFor();
  await page.getByText('3 de 5 etapas').first().waitFor();
  await page.getByText('1 demanda sugerida por funcionários').waitFor();
  await page.screenshot({ path: `${SHOTS}/demandas.png`, fullPage: true });
  await page.getByRole('button', { name: 'Lista' }).click();
  await page.getByRole('cell', { name: '#102' }).waitFor();
});

await passo('ficha da demanda: checklist, conversa com feedback, anexos e histórico', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/demandas/ficha/?id=d2`);
  await page.getByRole('heading', { name: 'Conversa' }).waitFor();
  await page.getByText('1 de 2 etapas').waitFor();
  await page.getByText('Ajustar · Coordenador da COFIT: Detalhar autuações').waitFor();
  await page.getByText('Servidor F (substituto)').first().waitFor();
  await page.getByText('v2').waitFor();
  await page.getByRole('button', { name: 'Pedir atualização' }).waitFor();
  await page.screenshot({ path: `${SHOTS}/demanda-ficha.png`, fullPage: true });
});

await passo('calendário: mês, abas e detalhe do compromisso', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/calendario/`);
  await page.getByRole('tab', { name: 'Geral do Gabinete' }).waitFor();
  await page.getByRole('button', { name: /Reunião de planejamento/ }).first().click();
  await page.getByText('Sala da DAT').waitFor();
  await page.screenshot({ path: `${SHOTS}/calendario.png`, fullPage: true });
  await page.goto(`${BASE}/calendario/feriados/`);
  await page.getByText('Natal').waitFor();
});

await passo('contratos: lista com filtros, ficha conforme protótipo, dados do locador mascarados', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/contratos/`);
  await page.getByRole('cell', { name: /014\/2024/ }).waitFor();
  await page.getByText('1 aluguel(is) vencido(s)').waitFor();
  await page.getByRole('tab', { name: 'Vencendo em 90 dias' }).click();
  assert.equal(await page.getByRole('cell', { name: /022\/2024/ }).count(), 0);
  await page.getByRole('button', { name: 'Novo contrato' }).click();
  await page.getByRole('dialog').getByText('Número do contrato').waitFor();
  await page.getByRole('button', { name: 'Cancelar' }).click();
  await page.goto(`${BASE}/contratos/ficha/?id=ct1`);
  await page.getByRole('heading', { name: 'Contrato 014/2024 · Imóvel da COAC' }).waitFor();
  for (const t of ['Vigente', 'Vence em 18 dia(s) (14/12/2026)', '1 aditivo(s)', 'R$ 44.880,00', 'Aluguéis mês a mês', 'Unidades consumidoras', 'Documentos', 'Histórico', 'Contrato_014-2024.pdf']) await page.getByText(t, { exact: true }).first().waitFor();
  await page.getByText(/1º aditivo \(prazo e valor\)/).waitFor();
  await page.getByText('Vencido', { exact: true }).first().waitFor();
  await page.getByText('demanda #150').waitFor();
  await page.screenshot({ path: `${SHOTS}/contrato-ficha.png`, fullPage: true });
  await page.getByRole('button', { name: 'dados' }).click();
  await page.getByText('***.982.247-**').waitFor();
  assert.equal(await page.getByRole('button', { name: 'Exibir dados completos' }).count(), 0);
  await page.getByRole('button', { name: 'Fechar' }).click();
  await page.getByRole('button', { name: 'Solicitar alteração' }).click();
  await page.getByRole('button', { name: 'Enviar para aprovação' }).waitFor();
  await page.getByRole('button', { name: 'Cancelar' }).click();
  await page.getByRole('button', { name: 'Registrar pagamento' }).click();
  await page.getByRole('dialog').getByText('Data do pagamento').waitFor();
  assert.match(await page.getByRole('dialog').locator('select option').first().textContent(), /nov\/2026 · vence 10\/11\/2026 · vencido/);
});

await passo('unidades consumidoras: KPIs, abas por fornecedor e situação', async () => {
  const page = await novaPagina({ perfil: 'secretaria' });
  await page.goto(`${BASE}/unidades-consumidoras/`);
  await page.getByRole('heading', { name: 'Unidades consumidoras e faturas' }).waitFor();
  for (const t of ['Energia no mês', 'Água no mês', 'Faturas pendentes', 'Faturas vencidas', 'R$ 585,70', 'R$ 142,70']) await page.getByText(t, { exact: true }).first().waitFor();
  await page.getByText('Sem lançamento').waitFor();
  await page.getByRole('button', { name: 'Lançar' }).waitFor();
  await page.screenshot({ path: `${SHOTS}/unidades-consumidoras.png`, fullPage: true });
  await page.getByRole('tab', { name: 'Iguá' }).click();
  assert.equal(await page.locator('tbody tr').count(), 1);
  await page.getByRole('button', { name: 'Importar faturas do mês' }).click();
  await page.getByText('Colunas provisórias', { exact: false }).waitFor();
});

await passo('painel do funcionário: menu reduzido', async () => {
  const page = await novaPagina({ perfil: 'funcionario', aal: 'aal1' });
  await page.goto(`${BASE}/`);
  await page.getByText('Minhas férias e folgas').waitFor();
  await page.getByText('86%').waitFor();
  await page.getByRole('button', { name: '+ Sugerir demanda' }).waitFor();
  assert.equal(await page.locator('nav[aria-label="Menu principal"] .menu-item').count(), 5);
  await page.screenshot({ path: `${SHOTS}/painel-funcionario.png`, fullPage: true });
});

await passo('celular: menu em gaveta, sem rolagem lateral, toques ≥ 44px', async () => {
  const page = await novaPagina({ perfil: 'secretaria', mobile: true });
  for (const rota of ['/', '/usuarios/?unidade=cofit', '/aprovacoes/']) {
    await page.goto(`${BASE}${rota}`);
    await page.getByRole('button', { name: 'Abrir menu' }).waitFor();
    const largura = await page.evaluate(() => document.documentElement.scrollWidth);
    assert.ok(largura <= 390, `${rota}: rolagem lateral (${largura}px)`);
  }
  await page.goto(`${BASE}/`);
  await page.screenshot({ path: `${SHOTS}/celular-painel.png`, fullPage: true });
  await page.getByRole('button', { name: 'Abrir menu' }).click();
  const menu = page.locator('nav[aria-label="Menu principal"]');
  await menu.getByText('Aprovações').waitFor();
  const alturas = await menu.locator('.menu-item').evaluateAll((els) => els.map((e) => e.getBoundingClientRect().height));
  assert.ok(alturas.every((h) => h >= 44), `itens do menu < 44px: ${alturas}`);
  await page.waitForTimeout(400); // fim da animação da gaveta
  await page.screenshot({ path: `${SHOTS}/celular-menu.png` });
});

await passo('PWA: manifest e service worker publicados', async () => {
  const page = await novaPagina();
  const r = await page.goto(`${BASE}/manifest.webmanifest`);
  const m = await r.json();
  assert.equal(m.display, 'standalone');
  assert.ok(m.icons.some((i) => i.sizes === '512x512'));
  const sw = await (await page.goto(`${BASE}/sw.js`)).text();
  assert.match(sw, /Nunca guarda respostas da API/);
});

await browser.close();
servidor.close();
const cspViolacoes = erros.filter((e) => /Content Security Policy/i.test(e));
passos.push([cspViolacoes.length ? 'FALHOU' : 'ok', `sem violações de CSP no console (${cspViolacoes.length})`, cspViolacoes[0] ?? '']);
for (const [s, n, d] of passos) console.log(`${s === 'ok' ? '✓' : '✗'} ${n}${d ? ` — ${d}` : ''}`);
const falhas = passos.filter((p) => p[0] !== 'ok').length;
console.log(`\n${passos.length - falhas} passaram, ${falhas} falharam`);
if (erros.length) console.log('Erros de console:', [...new Set(erros)].slice(0, 5));
process.exit(falhas ? 1 : 0);
