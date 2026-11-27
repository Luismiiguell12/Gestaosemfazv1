# Revisão OWASP Top 10 (2021) — Fase 6

| Risco | Situação | Evidência |
|---|---|---|
| A01 Controle de acesso | Relatórios de dados como `security invoker`: valem as mesmas políticas de RLS das telas; cada um exige o módulo "relatorios" e o do assunto. Auditoria: `security definer` com checagem explícita de secretária/admin. Histórico de exportações: cada um só vê o seu; ninguém altera ou apaga | `tests/db/fase6.test.ts` |
| A03 Injeção | CSV/Excel: texto iniciado por `=`, `+`, `-`, `@` é neutralizado; Excel só com texto e números (nenhuma fórmula); XML escapado. PDF só com texto | `tests/unit/fase6.test.ts` |
| A04 Design inseguro | Arquivos não ficam guardados (nada de cópia de dados pessoais em servidor); "gerar de novo" consulta de novo com as permissões atuais | D50 |
| A05 Configuração | Limite de exportações por hora e de linhas configuráveis | `registrar_exportacao` |
| A09 Logs | Toda exportação na auditoria (quem, relatório, formato, filtros, nº de linhas) | teste "exportações" |

Limitação conhecida: o limite e a auditoria valem para o botão "Gerar relatório". Quem tem acesso aos dados pela tela também pode consultá-los pela API; a proteção real continua sendo a RLS.
