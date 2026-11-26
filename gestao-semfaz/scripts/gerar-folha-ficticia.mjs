// Gera um PDF FICTÍCIO no layout do relatório de folha de ponto do RH (para testar o envio).
// Uso: node scripts/gerar-folha-ficticia.mjs [saida.pdf]
import { writeFileSync } from 'node:fs';
import { PDFDocument, StandardFonts } from 'pdf-lib';

const servidores = [ // mesmos do supabase/seed.sql (fictícios) + 1 matrícula fora do cadastro
  ['000001', 'SECRETÁRIA EXEMPLO', 'SECRETÁRIO(A)'], ['000002', 'ADMINISTRADOR EXEMPLO', 'ANALISTA DE SISTEMAS'],
  ['000010', 'DIRETOR DA DAT', 'DIRETOR(A)'], ['000011', 'DIRETOR DA DEFC', 'DIRETOR(A)'],
  ['000106', 'COORDENADOR DA COFIT', 'COORDENADOR(A)'], ['000206', 'COORDENADOR DA CONTA', 'COORDENADOR(A)'],
  ['000101', 'SERVIDOR A', 'AUDITOR FISCAL'], ['000102', 'SERVIDOR E', 'AUDITOR FISCAL'], ['000103', 'SERVIDOR F', 'AUDITOR FISCAL'],
  ['000104', 'SERVIDOR G', 'AGENTE ADMINISTRATIVO'], ['000105', 'SERVIDOR H', 'AGENTE ADMINISTRATIVO'],
  ['000201', 'SERVIDOR B', 'AGENTE ADMINISTRATIVO'], ['000301', 'SERVIDOR I', 'AGENTE ADMINISTRATIVO'],
  ['000777', 'SERVIDOR X FORA DO CADASTRO', 'AGENTE ADMINISTRATIVO'],
];
const mes = 'NOVEMBRO/2026';
const doc = await PDFDocument.create();
const f = await doc.embedFont(StandardFonts.Helvetica);
const b = await doc.embedFont(StandardFonts.HelveticaBold);
const sem = ['DOM', 'SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB'];
servidores.forEach(([mat, nome, cargo], i) => {
  const p = doc.addPage([595.28, 841.89]);
  const t = (s, x, y, o = {}) => p.drawText(s, { x, y, size: o.size ?? 7, font: o.bold ? b : f });
  t('ESTADO DE SERGIPE', 82, 815, { bold: true }); t('PREFEITURA MUNICIPAL DE LAGARTO', 82, 800, { size: 9, bold: true });
  t('Endereço fictício - Lagarto - SE', 82, 789); t('DOCUMENTO DE TESTE - DADOS FICTÍCIOS', 82, 778); t(mes, 491, 774, { size: 9, bold: true });
  t('Matrícula', 35, 752, { bold: true }); t('Servidor', 136, 752, { bold: true });
  t(mat, 35, 741); t(nome, 136, 741);
  t('CPF', 35, 723, { bold: true }); t('Data de Nascimento', 136, 723, { bold: true }); t('Admissão', 227, 723, { bold: true }); t('Cargo', 318, 723, { bold: true });
  t('000.000.000-00', 35, 712); t('01/01/1990', 136, 712); t('01/01/2020', 227, 712); t(cargo, 318, 712);
  t('Unidade', 35, 694, { bold: true }); t('Função', 318, 694, { bold: true });
  t('SECRETARIA MUNICIPAL DA FAZENDA- SEMFAZ', 35, 683); t('-', 318, 683);
  t('DIA/MÊS', 36, 613, { bold: true }); t('SEM', 80, 613, { bold: true }); t('HORÁRIO', 108, 620, { bold: true }); t('ALMOÇO', 183, 620, { bold: true });
  t('ENTRADA', 108, 606); t('SAÍDA', 161, 606); t('RETORNO', 204, 606); t('SAÍDA', 261, 606); t('ASSINATURA', 446, 613, { bold: true });
  for (let d = 1; d <= 30; d++) {
    const y = 594 - d * 16.5;
    t(`${String(d).padStart(2, '0')}/11`, 36, y); t(sem[(d + 6) % 7], 80, y);
    p.drawLine({ start: { x: 30, y: y - 4 }, end: { x: 565, y: y - 4 }, thickness: 0.3 });
  }
  t('Chefia Imediata', 120, 50, { bold: true }); t('VISTO', 400, 50, { bold: true });
  t(`Página ${i + 1} de ${servidores.length}`, 480, 30);
});
writeFileSync(process.argv[2] ?? 'folha-ponto-ficticia-nov2026.pdf', await doc.save());
console.log(`PDF fictício gerado: ${servidores.length} páginas`);
