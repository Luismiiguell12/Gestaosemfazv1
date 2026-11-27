import { PDFDocument } from 'pdf-lib';
import { describe, expect, it } from 'vitest';
import { linhaSemad, nomeCompetencia, pdfAnexoI, pdfAnexoII, type Demonstrativo, type Detalhe } from '@/lib/produtividade';

const IND = [['F1', 'Qualidade e eficiência', 20], ['F2', 'Prazos e metas', 15], ['F3', 'Produtividade e entregas', 15], ['F4', 'Atendimento', 10], ['F5', 'Organização', 10]] as const;
const detalhe = (): Detalhe => ({
  avaliacao: { id: 'a1', competencia: '2026-10-01', servidor_id: 's1', servidor: 'Servidor Fictício', matricula: '000101', cargo: 'Auditor Fiscal', exerce_comissao: false, unidade: 'COFIT',
    avaliador: 'Coordenador Fictício', avaliador_id: 's2', periodo_inicio: '2026-10-01', periodo_fim: '2026-10-31', status: 'homologada', limitacoes: 'Sistema fora do ar 3 dias',
    total_funcional: 58, enviada_em: '2026-11-03T12:00:00Z', ciente_em: '2026-11-04T12:00:00Z', ciencia_meio: 'sistema', ciencia_anexo: null, ciencia_registrada_por_nome: 'Servidor Fictício',
    prazo_recurso: '2026-11-11', homologada_em: '2026-11-20T12:00:00Z', homologada_por_nome: 'Homologação Fictícia', devolucao_motivo: null, retifica_id: null, retificacao_justificativa: null },
  regra: { versao: 1, indicadores: IND.map(([codigo, nome, maximo]) => ({ codigo, nome, maximo })), max_funcional: 70, prazos: { recurso: 5 } },
  notas: IND.map(([c, , m]) => ({ indicador: c, nota: m - 2, justificativa: `Justificativa ${c} com acentuação – ok`, equivalente: c === 'F4', justificativa_equivalente: c === 'F4' ? 'Atende só público interno' : null })),
  provas: [{ id: 'p1', indicador: 'F1', tipo: 'externa', ref_id: null, path: null, nome: null, descricao: 'Processo 123/2026', titulo: 'Processo 123/2026', demanda_id: null, criado_em: '' }],
  recursos: [], historico: [], pendencias_envio: [],
  permissoes: { editar: false, ciencia: false, ciencia_outro_meio: false, recorrer: false, decidir_recurso: false, homologar: false, retificar: false, gerir: false },
});
const demo = (inst: boolean): Demonstrativo => ({
  servidor: 'Servidor Fictício', matricula: '000101', cargo: 'Auditor Fiscal', unidade: 'COFIT', competencia: '2026-10-01', regra_versao: 1, transicao: !inst,
  pontos_funcionais: 56, pontos_institucionais: inst ? 25.65 : null, nota_total: inst ? 81.65 : 80, nota_enquadramento: inst ? 81 : 80, minimo_funcional_atingido: true, minimo_total_atingido: true,
  motivo_zero: null, percentual: 24, dias_elegiveis: 20, dias_mes: 30, fator: 0.6667, percentual_efetivo: 16,
  periodos: [{ avaliacao_id: 'a1', inicio: '2026-10-01', fim: '2026-10-31', status: 'homologada', pontos: 56, dias_elegiveis: 20, avaliador: 'Coordenador Fictício' }],
  institucional: inst ? { ano: 2026, quadrimestre: 2, pontos: 25.65, homologado_em: '2026-09-10T12:00:00Z', memoria: { pontos: 25.65, soma_contribuicoes: 0.855, max_institucional: 30, regra_versao: 1,
    receitas: [{ receita: 'R1', nome: 'IPTU', meta: 100, arrecadado: 90, indice: 0.9, peso: 0.25, contribuicao: 0.225 }] } } : null,
});

describe('documentos da produtividade', () => {
  it('Anexo I: PDF válido com título do formulário', async () => {
    const pdf = await PDFDocument.load(new Uint8Array(await (await pdfAnexoI(detalhe())).arrayBuffer()));
    expect(pdf.getTitle()).toMatch(/ANEXO I/);
    expect(pdf.getPageCount()).toBeGreaterThanOrEqual(1);
  });
  it('Anexo II: normal e transição', async () => {
    for (const inst of [true, false]) {
      const pdf = await PDFDocument.load(new Uint8Array(await (await pdfAnexoII(demo(inst), { encaminhamento: 'v1' })).arrayBuffer()));
      expect(pdf.getTitle()).toMatch(/ANEXO II/);
    }
  });
  it('linha do arquivo SEMAD indica o quadrimestre ou a regra de transição', () => {
    expect(linhaSemad(demo(true)).quadrimestre_ref).toBe('2º/2026');
    expect(linhaSemad(demo(false)).quadrimestre_ref).toMatch(/Transição/);
    expect(nomeCompetencia('2026-10-01')).toBe('outubro de 2026');
  });
});
