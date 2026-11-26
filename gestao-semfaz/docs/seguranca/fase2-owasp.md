# Revisão OWASP Top 10 (2021) — Fase 2

| Risco | Situação | Evidência |
|---|---|---|
| A01 Controle de acesso | Saldos e afastamentos só para o próprio, o substituto, a chefia do escopo e secretária/admin; folhas de ponto da unidade só para a chefia dela (tabela e Storage); importações e envio de PDF só secretária/admin; decisões só pela chefia, nunca o próprio | `tests/db/fase2.test.ts` (escopo, outra diretoria, funcionário, anônimo) |
| A03 Injeção | Planilhas e leitura do PDF chegam como JSON e são revalidadas no banco (tipos, formatos, limites); caminhos de arquivo conferidos por expressão regular e prefixo do lote | `validar_planilha_servidores`, `criar_lote_folhas`, `registrar_arquivos_folhas`, políticas do bucket |
| A04 Design inseguro | Importação em 2 passos (prévia → confirmar) e tudo-ou-nada; nenhuma página do PDF é descartada; arquivos nunca sobrescritos (versão nova por vínculo) | testes de importação e de lote |
| A05 Configuração | Funções novas sem EXECUTE para anon; bucket privado limitado a PDF de até 50 MB | teste genérico de privilégios |
| A08 Integridade | Planilha e PDF tratados como entrada não confiável: tipo real (assinatura), tamanho, nº de linhas/páginas, colunas obrigatórias; pdf.js com `isEvalSupported: false`; worker servido pelo próprio site (CSP) | `src/lib/planilha.ts`, `src/lib/folhas.ts`, testes unitários |
| A09 Logs | Importações, decisões, remarcações, cancelamentos, vínculos e entregas na auditoria, com a origem da operação | testes de auditoria |

Limitação: a leitura do PDF roda no navegador de quem envia (secretária/admin, usuários confiáveis). O banco revalida o cruzamento matrícula → servidor → unidade; um arquivo de unidade montado errado por um cliente adulterado ainda dependeria de um usuário com perfil de gestão.
