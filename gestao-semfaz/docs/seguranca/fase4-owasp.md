# Revisão OWASP Top 10 (2021) — Fase 4

| Risco | Situação | Evidência |
|---|---|---|
| A01 Controle de acesso | Contratos, aditivos, aluguéis, documentos e histórico: RLS por `app.acesso_contratos()` (módulo contratos). UCs e faturas: módulo contratos **ou** unidades consumidoras (esse não abre os contratos). Sem INSERT/UPDATE/DELETE direto: tudo por RPC. Alterar contrato e aditivo passam pela aprovação (ninguém aprova o próprio pedido; pedido bloqueia se o contrato mudou) | `tests/db/fase4.test.ts` (coordenador, diretor, funcionário, funcionário com módulo extra, anônimo) |
| A02 Falhas criptográficas / dados pessoais | CPF, e-mail e telefone do locador sem GRANT de coluna; RPC devolve mascarado; completo só com o módulo `locadores_dados` e com registro na auditoria | teste "CPF/contato mascarados" |
| A03 Injeção | Planilhas tratadas como entrada não confiável: tipo real, tamanho, linhas e colunas conferidos no navegador e **revalidados no banco** (CPF/CNPJ com dígito verificador, datas, valores, unidade, matrícula); importação tudo-ou-nada. Busca escapa curingas | testes de importação |
| A04 Design inseguro | Histórico do contrato só cresce; documentos não são apagados; aluguel e fatura únicos por competência; renovação única por vigência; avisos únicos por marco | testes de renovação e unicidade |
| A05 Configuração | Bucket `contratos` privado, só PDF, até 30 MB; caminho conferido no banco; rotinas sem EXECUTE para usuários | `registrar_documento_contrato`, teste genérico de privilégios |
| A08 Integridade | PDF: assinatura `%PDF` conferida antes do envio | `ehPdf` |
| A09 Logs | Auditoria de todas as tabelas novas + histórico próprio do contrato; exibição de dado completo do locador auditada | testes |
