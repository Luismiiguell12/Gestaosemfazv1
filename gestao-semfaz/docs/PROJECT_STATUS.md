# Gestão SEMFAZ — Situação do projeto

Ler no início de cada sessão. Atualizar ao fim de cada fase.

## Fase atual

**Fase 2 — Servidores, férias, folhas de ponto**: implementada, aguardando validação. A validação da Fase 1 foi adiada pelo responsável (vai testar depois), e a Fase 2 foi iniciada a pedido dele em 26/11/2026.

| Fase | Situação |
|---|---|
| 1. Fundação | Concluída e publicada (testes do responsável pendentes) |
| 2. Servidores, férias, folhas de ponto | Concluída (aguardando validação) |
| 3. Demandas, calendário, painéis | Não iniciada |
| 4. Contratos, UCs, faturas, aluguéis | Não iniciada |
| 5. Produtividade | Não iniciada (pendente material) |
| 6. Relatórios e exportações | Não iniciada |
| 7. Testes finais e implantação | Não iniciada |

## Ambiente de desenvolvimento (verificado em 26/11/2026, ambiente de nuvem do Claude Code)

| Ferramenta | Situação |
|---|---|
| Node.js | v22.23.5 (npm 10.9.9) |
| Git | 2.43.0 |
| Docker | 29.9.3 (daemon precisou ser iniciado manualmente) |
| Supabase CLI | **não instalada**. Download de imagens Supabase bloqueado neste ambiente (limite do registro), então `supabase start` não roda aqui |
| PostgreSQL | 16.15 local, usado nos testes de banco com o shim `tests/db/shim/supabase_shim.sql` |

No computador do projeto: instalar a Supabase CLI e rodar `supabase start` + `supabase db reset` para validar as migrations no Supabase real.

## Decisões tomadas

| # | Decisão | Motivo | Precisa de aprovação? |
|---|---|---|---|
| D1 | `docs/Prompt Gestão SEMFAZ – Rascunho v2 (consolidado).md` renomeado para `docs/PROMPT.md` | CLAUDE.md referencia esse nome | Não |
| D2 | Projeto dentro de `gestao-semfaz/` (onde está o CLAUDE.md); workflows do GitHub na raiz do repositório | Estrutura recebida | Não |
| D3 | Tabela `servidores` criada já na Fase 1, só com o núcleo (nome, matrícula obrigatória e única, cargo, unidade, situação, e-mail) | Usuários precisam de unidade e cargo; a regra da matrícula já fica garantida no banco | Não |
| D4 | Organograma e cargos podem ser lidos por qualquer usuário ativo | Necessário para mostrar lotação (ex.: "COFIT · DAT"); não é dado pessoal | **Sim** |
| D5 | Ações imediatas (sem aprovação, auditadas): liberar/retirar módulo extra; desativar/reativar usuário; cadastrar servidor novo; cadastrar feriado novo; convidar usuário | Prompt 4 (módulo extra na hora) + segurança (desativação imediata). Cadastro novo não é "alteração de dado já cadastrado" | **Sim** |
| D6 | Passam por aprovação: criar/alterar/mover/desativar unidade; criar/alterar cargo; alterar dados de servidor (inclui matrícula e situação); alterar perfil de usuário; conceder/retirar acesso a outra unidade; alterar/excluir feriado | Prompt 6.9 e 7.2 | **Sim** (principalmente feriados) |
| D7 | Feriados: na Fase 1 ficam no item de menu "Calendário" (tela "Calendário › Feriados"). A grade do calendário entra na Fase 3 | Prompt 7.2: telas sem protótipo dentro das telas existentes | **Sim** (desvio de layout provisório) |
| D8 | Auditoria: consulta na tela "Relatórios" (cartão "Auditoria" do protótipo). Demais relatórios aparecem como "em breve" até a Fase 6 | Protótipo Relatórios já tem o cartão Auditoria | **Sim** |
| D9 | Sem MFA (aal1), administrador e secretária não acessam nenhum dado: só a tela de configurar/verificar o MFA | Prompt 5 e 5.1 (MFA obrigatório, ações administrativas com sessão verificada) | Não |
| D10 | Fonte IBM Plex Sans servida pelo próprio site (pacote @fontsource), não pelo Google Fonts | CSP restritiva e LGPD (sem requisição a terceiros) | Não |
| D11 | Notificações internas mínimas (tabela `notificacoes`) já na Fase 1, usadas pelas aprovações. E-mail e push: fases seguintes | Pedido de aprovação precisa avisar quem aprova | Não |
| D12 | Indicadores de módulos futuros no painel (demandas, contratos, aluguéis, compromissos, ausências) aparecem com o mesmo layout do protótipo e estado vazio "disponível na Fase X" | Protótipo obrigatório + não inventar dados | Não |
| D13 | Acesso extra a outra unidade amplia o escopo de gestão de diretor/coordenador. Para funcionário, a concessão é registrada, mas o efeito (ver demandas da outra unidade) será definido na Fase 3 | Regra não definida no prompt | **Sim** |
| D14 | Somente administrador pode convidar outro administrador | Opção conservadora | **Sim** |
| D16 | Desvios de layout em "Unidades e usuários": links "+ Servidor" e "Solicitar alteração da unidade" no cartão da unidade; detalhes do servidor (pacote padrão, módulos extras com adicionar/remover, acessos, desativar) em janela ao clicar na linha | O prompt exige cadastrar servidor e mostrar pacote padrão e extras, e o protótipo não tem lugar para isso | **Sim** |
| D17 | No celular, o botão do menu (gaveta) fica acima do título | Protótipo só tem versão desktop | **Sim** |
| D18 | Testes de banco rodam em PostgreSQL 16 puro com shim do Supabase (`tests/db/shim`), assumindo o papel `authenticated` e as claims do JWT, como a API faz | Supabase local indisponível neste ambiente | Não |
| D19 | MFA obrigatória virou configuração (`configuracoes.auth.mfa_obrigatoria`, padrão `true`). **Desligada no Supabase de testes** (`uacgmmuycbfxeigxgtla`) a pedido do responsável, em 26/11/2026, só com dados fictícios | Facilitar os testes iniciais | **Religar antes de qualquer dado real** (`update public.configuracoes set valor = 'true' where chave = 'auth.mfa_obrigatoria'`) |
| D20 | Fase 2 iniciada antes da validação da Fase 1, a pedido do responsável | Decisão do responsável | Não |
| D21 | Saldos do RH **não** são descontados automaticamente ao aprovar; o pedido mostra dias corridos/úteis e avisa quando passa do saldo | Regra de desconto não definida | **Sim** (pendente) |
| D22 | Saldos do RH importados direto pela secretária/admin (auditado, sem aprovação). Importação de servidores só cria novos; alterar servidor existente continua pela aprovação | Saldo é dado informado pelo RH; prompt 6.7 | **Sim** |
| D23 | Chefia (diretor/coordenador no escopo) aprova, remarca e cancela férias/licenças/folgas direto ("escala editável"), tudo auditado. Funcionário pede só para si. Ninguém aprova o próprio | Prompt 6.7 | **Sim** |
| D24 | Substituto: obrigatório na aprovação, da mesma unidade, não pode estar afastado no período; ele e a chefia são notificados. Passar demandas ao substituto no 1º dia útil e devolver no retorno: Fase 3 (depende de demandas) | Prompt 6.14 | Não |
| D25 | PDF do RH lido no navegador de quem envia (pdf.js); o cruzamento matrícula → servidor → unidade é feito no banco. Expressão da matrícula configurável (`folhas.regex_matricula`). PDF escaneado (sem texto) é recusado com aviso | Prompt 6.8; hospedagem estática | **Sim** |
| D26 | Controle de entrega: secretária/admin e chefia da unidade registram envio e devolução; "quem recebeu/devolveu" é servidor da unidade. Aviso de atraso diário (pg_cron, 08:00 de Brasília em dias úteis) | Prompt 6.18 | **Sim** |
| D27 | Painel ganhou o bloco "Folhas de ponto a devolver" na coluna direita (não está no protótipo; exigido pela 6.18) | Prompt 6.18 | **Sim** (desvio de layout) |
| D28 | Férias: seletor de ano; pedido pendente **sem** conflito aparece em cartão azul com Recusar/Aprovar (o protótipo só mostra o caso com conflito) | Completar o fluxo | **Sim** (desvio de layout) |
| D15 | Repositório público e GitHub Pages nesta fase (só dados fictícios). **Rever antes de qualquer dado real** (repositório privado / Cloudflare Pages / Netlify) | Prompt 7 | Rever antes de dados reais |

## Pendências (seção 9 do prompt)

| Pendência | O que foi feito | Situação |
|---|---|---|
| Regras de produtividade (material dos fiscais) | Nada implementado. Item do menu marcado "em definição" | Aguardando SEMFAZ |
| Lista oficial de cargos | Tabela `cargos` configurável (via aprovação). Seed só com cargos fictícios de exemplo | Aguardando SEMFAZ |
| Modelo das planilhas de importação | Fase 2: importação de servidores e de saldos com as colunas mínimas do prompt 6.7 (modelo CSV baixável; aceita .xlsx e .csv). Cabeçalhos aceitam variações | Ajustar quando chegar o modelo oficial |
| Permissões padrão por módulo e perfil | Tabela `pacotes_padrao` configurável, com coluna `provisorio = true`. Seed copia **o rascunho** da seção 4 só para decidir quais itens aparecem no menu. O acesso a dados é controlado pelas políticas de escopo de cada tabela | **Aguardando definição oficial. Não tratar como definitivo** |
| Planilha do RH (saldos de férias, licença-prêmio, folgas) | Importação de saldos pronta (matrícula + 3 saldos), com prévia de erros | Ajustar colunas ao arquivo real do RH |

## Testes da Fase 1 (executados em 26/11/2026, resultado real)

| Suíte | Comando | Resultado |
|---|---|---|
| Tipos | `npm run typecheck` | ok |
| Banco (RLS, aprovações, auditoria, busca, dias úteis, storage) | `npm run test:db` | 62/62 |
| Unitários (validação, tipo real de arquivo, erros, segredos no frontend) | `npm run test:unit` | 14/14 |
| Build estático + CSP | `npm run build` | ok, CSP em 12 páginas |
| E2E de fumaça (API simulada) | `npm run test:e2e` | 12/12 |
| Dependências | `npm audit --omit=dev` | 0 vulnerabilidades |

**Não executados:** Supabase real (Auth, hook de token, Storage, Edge Function `convidar-usuario`, e-mails de convite e recuperação, MFA real) e CI do GitHub Actions.

## Pendências da Fase 2

- **Modelo real do PDF de folhas de ponto do RH**: confirmar onde e como a matrícula aparece e ajustar `folhas.regex_matricula`; testar com um PDF fictício no mesmo formato.
- **Regras de saldo**: descontar ou não ao aprovar; férias/licença contam dias corridos ou úteis; folga em dias ou horas.
- **pg_cron** no Supabase: habilitar a extensão para o aviso diário de atraso das folhas (sem ela o aviso não roda sozinho).
- **Aplicar a Fase 2 no Supabase de testes e republicar o site** (aguardando autorização).

## Outras pendências técnicas

- Validar as migrations no Supabase real, que não rodou neste ambiente. Pode ser pela web: colar `supabase/deploy/banco-completo.sql` no SQL Editor de um projeto novo (arquivo gerado por `scripts/gerar-sql-unico.mjs`; um teste garante que está em dia).
- Ativar no GitHub: secret scanning, push protection e Dependabot alerts (configuração do repositório, não por código).
- Criar projetos Supabase de homologação e produção (região São Paulo) e configurar SMTP próprio para os e-mails de convite e recuperação.
- Configurar no painel do Supabase o hook `custom_access_token_hook` (no local já está no `config.toml`).
- Notificações por e-mail e push (PWA): Fase 3, com as demandas.
- Verificação do tipo real dos arquivos no servidor (Edge Function): na Fase 1 a checagem é feita no navegador, junto com limite de tipo e tamanho no bucket. A validação no servidor entra na Fase 2 (folhas de ponto).
- `docs/lgpd.md`: rascunho inicial para o DPO; completar a cada fase.
- Backup diário e teste de restauração: Fase 7.
- Ícones PNG do PWA gerados a partir do SVG do logo.
