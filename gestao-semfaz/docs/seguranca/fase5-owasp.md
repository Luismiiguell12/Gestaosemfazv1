# Revisão OWASP Top 10 (2021) — Fase 5 (Produtividade)

| Risco | Situação | Evidência |
|---|---|---|
| A01 Controle de acesso | Uma regra (`app.pode_ver_avaliacao`) para tabelas, Storage e RPCs. Servidor só vê a própria e só depois de enviada; chefia só as que avalia; diretor só leitura da diretoria; revisora e homologação por designação vigente. Escrita só por RPC | `tests/db/fase5.test.ts` (T15, diretor de outra diretoria, anônimo) |
| A04 Design inseguro | **Segregação no banco** por trigger: ninguém avalia/revisa/homologa a própria; quem avaliou não revisa nem homologa; quem revisou não homologa — inclusive o Administrador e escrita direta. Homologada imutável; retificação gera novo registro. Metas travadas por trigger após o início do quadrimestre. Prazos em dias úteis com feriados | T10–T14 |
| A03 Injeção / integridade de cálculo | Cálculo em `numeric` no banco; nada de nota sugerida; CHECK de nota + trigger com o máximo da versão da regra; regras versionadas e imutáveis | T1, T3–T9 |
| A05 Configuração | Bucket `produtividade` privado, tipos e 20 MB; caminho com o id da avaliação conferido; funções internas sem EXECUTE para usuários; conversão segura de UUID nas políticas do Storage | `verificar-seguranca.sql` sem FALHA |
| A09 Logs | Auditoria em todas as tabelas; histórico próprio da avaliação; exportações (SEMAD, Anexos) registradas | testes |

Correção encontrada pelos testes: o demonstrativo liberava o acesso quando o id do servidor vinha nulo (condição virava NULL). Corrigido com `coalesce(..., false)` e teste de regressão.
