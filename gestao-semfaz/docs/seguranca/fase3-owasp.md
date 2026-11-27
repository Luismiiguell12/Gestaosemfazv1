# Revisão OWASP Top 10 (2021) — Fase 3

| Risco | Situação | Evidência |
|---|---|---|
| A01 Controle de acesso | Uma regra só (`app.pode_ver_demanda`) para tabela, Storage e RPCs: responsável, chefia do escopo, secretária/admin, quem sugeriu e quem foi mencionado. Só a chefia cria, edita, distribui, cancela, pede atualização e dá feedback; status e checklist são do responsável ou da chefia; ninguém aprova a própria sugestão. Calendário: edição só no escopo, e o funcionário vê só onde participa | `tests/db/fase3.test.ts` (outra unidade, outra diretoria, funcionário, anônimo, menção) |
| A03 Injeção | Texto das mensagens é exibido como texto (React escapa; sem HTML); menções são ids validados no banco; busca escapa curingas; campos editáveis em lista fixa | RPCs e teste da busca |
| A04 Design inseguro | Histórico só cresce; mensagens e anexos não são apagados; versão nova não sobrescreve; ocorrência recorrente única por constraint; rotinas idempotentes | testes de histórico, recorrência e substituição |
| A05 Configuração | Funções da rotina sem EXECUTE para usuários; bucket privado com tipos e tamanho limitados | teste genérico de privilégios |
| A08 Integridade | Anexo: tipo real (assinatura) e tamanho conferidos antes do envio; caminho gerado pelo sistema e conferido no banco | `validarAnexoDemanda`, `registrar_anexo` |
| A09 Logs | Toda mudança vai para o histórico da demanda e para a auditoria | testes |
