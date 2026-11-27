# Gestão SEMFAZ — Situação do projeto

Ler no início de cada sessão. Atualizar ao fim de cada fase.

## Fase atual

**Fase 5 — Produtividade (Adendo 01)**: implementada, aplicada no Supabase de testes e publicada em 27/11/2026 (PR #17); aguardando validação. Fase 7 (parte técnica) concluída antes. Próximo: roteiro geral de testes com o responsável (`docs/roteiro-testes.md`, inclui a seção 7 de produtividade). **Sistema não liberado para dados reais.**

| Fase | Situação |
|---|---|
| 1. Fundação | Concluída e publicada (testes do responsável pendentes) |
| 2. Servidores, férias, folhas de ponto | Concluída e publicada (testes do responsável pendentes) |
| 3. Demandas, calendário, painéis | Concluída, aplicada e publicada (aguardando validação) |
| 4. Contratos, UCs, faturas, aluguéis | Concluída, aplicada e publicada (aguardando validação) |
| 5. Produtividade | Concluída conforme o **Adendo 01**, aplicada e publicada (aguardando validação) |
| 6. Relatórios e exportações | Concluída, aplicada no Supabase de testes e publicada (aguardando validação) |
| 7. Testes finais e implantação | Parte técnica concluída; aguardando o roteiro de testes do responsável e as decisões de produção |

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
| D29 | Fase 3 iniciada antes da validação das Fases 1 e 2, a pedido do responsável | Decisão do responsável | Não |
| D30 | Origem da demanda: além de processo físico, e-mail e WhatsApp (prompt), há "recorrente" (criada pela rotina) e "outra" | Demandas recorrentes e internas | **Sim** |
| D31 | Status: as 5 colunas do protótipo; "sugerida", "recusada" e "cancelada" ficam fora do quadro. Cancelar é só para a chefia | Protótipo Demandas | **Sim** |
| D32 | Criar, editar, distribuir e mudar responsáveis da demanda é feito direto pela chefia (diretor/coordenador no escopo, secretária, admin), com histórico. Não passa pela central de aprovações (não é dado cadastral) | Prompt 6.2 | **Sim** |
| D33 | Quem vê a demanda: responsáveis, chefia do escopo, secretária/admin, quem sugeriu e quem foi mencionado (passa a ver a ficha e a conversa) | Prompt 6.2 e 6.21 | **Sim** |
| D34 | Anexos: responsáveis e chefia; até 20 MB; tipo real conferido (DOCX/XLSX = ZIP + extensão); nova versão nunca apaga a anterior | Prompt 6.20 | Não |
| D35 | Substituto nas demandas: rotina diária às 06:05 (Brasília), a partir do 1º dia útil do afastamento; no retorno o substituto sai das demandas não concluídas (continua registrado nas concluídas) | Prompt 6.14 | Não |
| D36 | Aviso de prazo: no dia útil anterior e no dia do prazo, uma vez por dia. "Prazo apertado" no painel = prazo em até 2 dias úteis (configurável) | Prompt 6.10 e protótipo | **Sim** |
| D37 | Calendário: o compromisso pode ter participantes de qualquer unidade; o funcionário vê só onde é participante ou responsável. O calendário "Geral do Gabinete" é da secretária/admin. Feriados ficaram em Calendário › Feriados (resolve a D7) | Prompt 6.3 | **Sim** |
| D38 | Painel: "% no prazo" considera as demandas concluídas nos últimos 90 dias; a barra mostra a fazer, em andamento (inclui aguardando e revisão) e concluídas nos últimos 30 dias | Protótipo Main | **Sim** |
| D39 | Contratos: acesso por **módulo** (`contratos`), não por unidade. Quem tem o módulo vê todos os contratos | Prompt 4 (permissão de contratos) | **Sim** |
| D40 | CPF/CNPJ e contato do locador: as colunas não saem pela API; a RPC devolve mascarado (`***.982.247-**`, `(79) *****-1234`, `lo***@dominio`). Completo só com o módulo extra `locadores_dados`, que **não entra em nenhum pacote padrão** (nem da secretária); cada exibição completa vai para a auditoria. CNPJ de PJ aparece completo (não é dado pessoal) | Prompt 5.1 | **Sim** |
| D41 | Cadastrar contrato novo, vincular UC, lançar fatura e registrar pagamentos: sem aprovação (registro novo). Alterar contrato cadastrado e aditivo: aprovação da secretária/admin. Só um pedido pendente por contrato. Desfazer pagamento errado: só secretária/admin, com motivo | Prompt 6.6 e 6.9 | **Sim** |
| D42 | Vigência: `fim_original` (contrato) e `fim_vigencia` (efetiva, muda só por aditivo de prazo aprovado). Encerrar contrato = pedido de alteração | Prompt 6.5 e 6.17 | **Sim** |
| D43 | Aluguéis gerados mês a mês para toda a vigência, com vencimento no dia escolhido (1–28, padrão 10). Novo valor ou dia valem só para os aluguéis não pagos a partir do mês corrente | Prompt 6.5 | **Sim** |
| D44 | Renovação: aos 90 dias (`contratos.dias_renovacao`) cria uma vez por vigência a demanda "Renovação do contrato nº X" — responsável = fiscal; quem tem o módulo contratos entra como participante e é avisado; unidade = do fiscal (ou a ocupante, ou o Gabinete); prazo = 30 dias úteis sem passar do fim da vigência; prioridade alta; checklist em `contratos.checklist_renovacao` (provisório) | Prompt 6.17 | **Sim** |
| D45 | Aviso "contrato vencendo" aos 90, 60, 30 e 15 dias (configurável), uma vez por marco, para o fiscal e quem tem o módulo contratos | Prompt 6.10 | **Sim** |
| D46 | Toda UC fica ligada a um contrato; fornecedores fixos: Energisa e Cercos (energia), Iguá (água). Uma fatura por UC e competência. Quem tem o módulo `unidades_consumidoras` vê as faturas mas não os contratos | Prompt 6.6 e protótipo | **Sim** |
| D47 | Tela de lista de contratos (`/contratos`) não tem protótipo: segue o padrão da lista de demandas (abas de filtro + tabela). A ficha segue o protótipo Contrato, com o botão extra "Registrar aditivo" | Desvio de layout registrado | **Sim** |
| D48 | Relatórios de dados usam as **mesmas regras de acesso das telas** (funções `security invoker` + RLS): secretária/admin tudo, diretor a diretoria, coordenador a unidade. Cada relatório exige o módulo "relatorios" e o módulo do assunto (contratos, férias, folhas...). Auditoria: só secretária/admin | Prompt 4 (linha Relatórios) | **Sim** |
| D49 | O pacote padrão (provisório) do funcionário não tem o módulo "relatorios"; quando tiver, ele verá só os próprios dados pela mesma regra | Seção 9 (permissões pendentes) | **Sim** |
| D50 | Arquivos (PDF, Excel, CSV) são gerados no navegador e **não ficam guardados** no sistema. "Gerados recentemente" guarda só título, filtros, formato e nº de linhas; clicar gera de novo com os dados atuais | Prompt 5.1 (mínimo necessário) | **Sim** |
| D51 | Toda exportação vai para a auditoria (relatório, formato, filtros, linhas). Limite: 60 exportações por usuário por hora (`relatorios.exportacoes_por_hora`); até 20.000 linhas na auditoria (`relatorios.linhas_max`) | Prompt 5.1 (limite em exportação) | **Sim** |
| D52 | CSV com `;` e acentos (abre direto no Excel brasileiro); texto que começa com `=`, `+`, `-` ou `@` recebe `'` na frente (proteção contra fórmula maliciosa). Excel com números e datas de verdade, filtro e cabeçalho fixo. PDF em A4 paisagem com filtros, autor, data e páginas numeradas | Prompt 6.11 | Não |
| D53 | Relatório extra "Entrega das folhas de ponto" (não está no protótipo); "Produtividade" fica visível e desabilitado ("em definição") | Prompt 6.11 ("cada módulo") | **Sim** |
| D54 | **Adendo 01 – Produtividade** (`docs/ADENDO-PRODUTIVIDADE.md`) substitui a seção 6.4 do prompt e acrescenta regras às seções 6.7, 6.12 e 7.2 (tela 12). Em conflito, vale o adendo. Base: **minuta** de decreto (LC 138/2025, arts. 15-A a 15-E) → todo número fica em configuração versionada | Adendo 01 | Não |
| D55 | Campos da seção 2 do adendo criados já agora (migration `20261130000200_adendo_servidores_cargos.sql`, só acrescenta colunas): `servidores.tipo_vinculo` (efetivo/comissionado/temporário), `servidores.exerce_comissao` (sim/não), `cargos.carreira_excluida` (sim/não, nenhum marcado) e `elegivel_adicional`, **calculado** pelo banco (efetivo e carreira não excluída), sem coluna digitável | Adendo 01, seção 2 e 12 | Não |
| D56 | Vínculo obrigatório para cadastro novo e na importação de servidores (coluna "tipo de vínculo"; "cargo em comissão/função de confiança" opcional, sim/não). Servidores **já cadastrados ficam sem vínculo** até alguém informar por pedido de alteração — enquanto isso são **não elegíveis** (opção mais conservadora). Depois de informado, o vínculo não pode voltar a ficar vazio | Adendo 01, seção 2 | **Sim** |
| D57 | Alterar vínculo e função de confiança do servidor e a marca de carreira excluída do cargo passa pela central de aprovações (dados já cadastrados) | Prompt 6.9 | Não |
| D58 | Backup próprio diário (03:17 Brasília) pelo GitHub Actions: dados do banco (`public`, `app` e usuários do Auth) + arquivos do Storage, **cifrados com AES-256** antes de sair do runner; artefato por 30 dias. Estrutura não entra no backup (vem das migrations). Complementa o backup/PITR do plano pago do Supabase | Prompt 7 / Fase 7 | **Sim** |
| D59 | Restauração só em banco **sem servidores cadastrados** (projeto novo), com gatilhos desligados durante a carga (auditoria não duplica). Testada a cada mudança no CI com dados fictícios | Fase 7 | Não |
| D60 | `scripts/verificar-seguranca.sql` (somente leitura) é o portão de implantação: o CI reprova com qualquer FALHA; produção só sobe sem FALHA | Fase 7 | Não |
| D61 | Chefia imediata calculada pela estrutura: chefia designada (se houver) → coordenador/chefe da unidade → se o próprio for o chefe, a chefia da unidade superior (diretor; Gabinete = Secretária). Secretária sem chefia: precisa de designação se for elegível | Adendo 3.2.1 | **Sim** |
| D62 | Abertura da competência (Secretária/Admin) cria uma avaliação por servidor **elegível, ativo e em exercício na SEMFAZ no mês** (datas de entrada/saída novas no cadastro; vazias = mês inteiro). Pode rodar de novo para incluir servidores novos | Adendo 6.1 | **Sim** |
| D63 | Mudança no mês = "dividir período" (Secretária/Admin) com outra chefia; funcional do mês = **média ponderada pelos dias elegíveis, truncada em 2 casas** (nunca arredonda para cima) | Adendo 3.2.7 | **Sim** |
| D64 | Prova obrigatória por indicador: demanda, etapa de checklist ou mensagem/feedback **do próprio servidor**, anexo (bucket privado `produtividade`) ou referência externa. Justificativa mín. 10 caracteres. O servidor só vê a avaliação depois de enviada | Adendo 3.2.3 | **Sim** |
| D65 | Revisora: o recurso vai para a primeira autoridade revisora designada sem conflito; sem designação, a Secretária é avisada para designar. Homologação: só pela instância designada (Secretária/Admin não homologam por serem gestores; precisam estar designados) | Adendo 6.5–6.8 | **Sim** |
| D66 | Demonstrativo "congelado" (memória de cálculo) quando todos os períodos do servidor são homologados; retificação gera nova versão. Encaminhamento SEMAD só com tudo homologado; cada geração é uma versão | Adendo 6.9 e 9 | Não |
| D67 | Valor anual de meta/arrecadação por quadrimestre; arrecadação editável até a homologação do resultado; reapurar apaga só o resultado ainda não homologado | Adendo 4.3 | **Sim** |
| D68 | Permissão `produtividade.institucional.gerir` = módulo extra "prod_institucional" (fora dos pacotes); Secretária/Admin sempre têm | Adendo 4.3.4 | **Sim** |
| D15 | Repositório público e GitHub Pages nesta fase (só dados fictícios). **Rever antes de qualquer dado real** (repositório privado / Cloudflare Pages / Netlify) | Prompt 7 | Rever antes de dados reais |

## Pendências (seção 9 do prompt)

| Pendência | O que foi feito | Situação |
|---|---|---|
| Regras de produtividade (material dos fiscais) | **Recebidas em 27/11/2026: Adendo 01** (`docs/ADENDO-PRODUTIVIDADE.md`), baseado na minuta do decreto do Adicional de Desempenho e Produtividade. Substitui a seção 6.4 do prompt e prevalece em caso de conflito. Implementação completa na Fase 5. Pendências próprias do adendo na seção "Adendo 01" abaixo | Recebidas (minuta; números configuráveis) |
| Lista oficial de cargos | Tabela `cargos` configurável (via aprovação). Seed só com cargos fictícios de exemplo | Aguardando SEMFAZ |
| Modelo das planilhas de importação | Fase 2: servidores e saldos. Fase 4: contratos (~60) e faturas, com colunas **provisórias** (modelo CSV baixável; aceita .xlsx e .csv; datas dd/mm/aaaa ou célula de data; valores 1.234,56). Cabeçalhos aceitam variações | Ajustar quando chegar o modelo oficial |
| Permissões padrão por módulo e perfil | Tabela `pacotes_padrao` configurável, com coluna `provisorio = true`. Seed copia **o rascunho** da seção 4 só para decidir quais itens aparecem no menu. O acesso a dados é controlado pelas políticas de escopo de cada tabela | **Aguardando definição oficial. Não tratar como definitivo** |
| Planilha do RH (saldos de férias, licença-prêmio, folgas) | Importação de saldos pronta (matrícula + 3 saldos), com prévia de erros | Ajustar colunas ao arquivo real do RH |

## Adendo 01 – Produtividade (recebido em 27/11/2026)

Arquivo: `docs/ADENDO-PRODUTIVIDADE.md`. Transforma o módulo de Produtividade na **avaliação mensal de desempenho** do decreto: avaliação pela chefia imediata (5 indicadores, até 70 pontos, com justificativa e prova obrigatórias), desempenho institucional quadrimestral por arrecadação (até 30 pontos), nota, mínimos, faixas e proporcionalidade, ciência, recurso, revisão, homologação com segregação de funções, encaminhamento à SEMAD (Anexos I e II) e dossiê para o Controle Interno.

**Já feito (sem interromper a fase atual):** campos da seção 2 no cadastro (D55–D57). Testes: `tests/db/adendo.test.ts`. Aplicado no Supabase de testes e publicado em 27/11/2026 (PR #16); os 13 servidores de teste estão sem vínculo informado (não elegíveis) até alguém preencher.

**Implementado na Fase 5 (27/11/2026):** tudo da lista abaixo, com as decisões D61–D68.

**Escopo da Fase 5 (implementação completa do adendo, seção 12):**
- Tabela de regras versionada (indicadores, máximos, pesos, mínimos, faixas, transição, prazos) e cada ciclo gravando a versão usada.
- Chefia imediata calculada pela estrutura + chefia substituta/designada por servidor; designações da autoridade revisora e da instância de homologação.
- Ciclo mensal (máquina de estados no banco): abertura, avaliação com provas (registros do sistema, anexos, referência externa), painel de subsídios só com fatos (sem nota sugerida), avaliação parcial por período com média ponderada, ciência, recurso em dias úteis, revisão, homologação individual/lote, devolução, retificação.
- Institucional: metas travadas após o início do quadrimestre, arrecadação manual e por planilha, apuração em `numeric` com memória de cálculo, permissão `produtividade.institucional.gerir`.
- Nota total, regra de transição, enquadramento sem fração, mínimos cumulativos, faixas, proporcionalidade por dias corridos e afastamentos configuráveis; valor em R$ desligado por configuração.
- Documentos e saídas: Anexo I, Anexo II, arquivo SEMAD (XLSX/CSV) e Dossiê do ciclo — entram também na tela de Relatórios (complemento da Fase 6).
- Telas: Produtividade da equipe com as 7 abas da seção 10; bloco "Minha produtividade" no painel do funcionário.
- Os 16 testes obrigatórios da seção 11, mais LGPD (`docs/lgpd.md`) e auditoria.
- Data de entrada/saída na SEMFAZ (necessária para os dias elegíveis) será acrescentada ao cadastro de servidores na Fase 5.

### Pendências do Adendo 01 (seção 13)

| # | Pendência | Padrão adotado até a definição oficial |
|---|---|---|
| 1 | Lista de carreiras excluídas (§ 3º do art. 15-A da LC 138/2025) | Nenhum cargo marcado como carreira excluída |
| 2 | Se o sistema calcula valor em R$ | Não calcula; entrega nota, percentual, fator e percentual efetivo. Campo de vencimento básico preparado e **desligado** |
| 3 | Qual resultado institucional vale para cada mês | Último resultado homologado até o fechamento do mês; sem nenhum, regra de transição (configurável) |
| 4 | Quem lança metas e arrecadação | Só Secretária e Administrador, que concedem a permissão `produtividade.institucional.gerir` (sugestão: ASPLAN metas; COACAM/CONTA arrecadação) |
| 5 | Autoridade revisora e instância de homologação | Designação configurável (pessoas ou grupo), com início/fim, auditada |
| 6 | Quais afastamentos contam como efetivo exercício | Férias, licença-prêmio e folga contam; tipos novos não contam até alguém configurar |
| 7 | Prazo e forma de ciência quando o servidor não acessa o sistema | 3 dias úteis + registro da ciência por outro meio pela chefia (com anexo) |
| 8 | Texto final do decreto (é minuta) | Todos os números configuráveis e versionados |
| — | Vínculo dos servidores já cadastrados | Ficam "não informado" e não elegíveis até alguém informar (D56) |

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

## Testes da Fase 4 (executados em 27/11/2026, resultado real)

| Suíte | Resultado |
|---|---|
| Tipos (`npm run typecheck`) | ok |
| Banco, Fases 1–4 (`npm run test:db`) | 96/96 (8 novos: módulo e máscara LGPD, CPF/CNPJ, pagamento e desfazer, aprovação de alteração e aditivo, renovação única e aviso, bloqueio por versão, importação de contratos, UCs e faturas, painel e busca) |
| Todos (`npm test`, unitários + banco) | 118/118 |
| SQL único aplicado num banco vazio (com o shim) | ok |
| Build + CSP (com as variáveis do CI) | ok, 21 páginas |
| E2E de fumaça | 20/20 |
| `npm audit --omit=dev` | 0 vulnerabilidades |

**Não executado:** Supabase real (Fases 3 e 4 ainda não aplicadas), envio real de PDF ao Storage e pg_cron real da rotina de contratos.

## Testes da Fase 6 (executados em 27/11/2026, resultado real)

| Suíte | Resultado |
|---|---|
| Tipos (`npm run typecheck`) | ok |
| Banco, Fases 1–4 e 6 | 100/100 (4 novos: escopo por perfil nos relatórios, módulo exigido, auditoria só gestor, exportação auditada, histórico próprio e limite por hora) |
| Todos (`npm test`) | 130/130 (unitários novos: CSV com proteção de fórmula, Excel válido, PDF com várias páginas, catálogo e permissões) |
| Build + CSP | ok, 21 páginas |
| E2E de fumaça | 20/20 (inclui baixar Excel e PDF de verdade e conferir o arquivo) |

**Não executado:** Supabase real (Fase 6 ainda não aplicada); abrir os arquivos no Excel/LibreOffice de verdade (conferido só a estrutura do arquivo).

## Testes da Fase 5 (executados em 27/11/2026, resultado real)

| Suíte | Resultado |
|---|---|
| Banco (`tests/db/fase5.test.ts`): os **16 testes obrigatórios** do adendo (T1–T16) + fluxo completo (ciência, recurso, revisão, homologação, demonstrativo, SEMAD, retificação), relatórios, LGPD e rotina | 12 cenários, todos ok |
| Todos (`npm test`) | 148/148 |
| E2E | 21/21 (tela da equipe, formulário com subsídios, Anexo I baixado e conferido, painel do funcionário) |
| Build + CSP | ok, 23 páginas |

Mapa dos testes obrigatórios: T1–T2 formulário; T3–T4 institucional 25,65 e índice ≤ 1; T5–T8 enquadramento, mínimos, transição (56 → 80 → 24%) e proporcionalidade (20/30 → 0,6667); T9 média ponderada; T10 recurso fora do prazo com feriado; T11–T12 segregação (inclusive Administrador); T13 meta travada; T14 homologada imutável; T15 servidor não lê a de outro; T16 não elegíveis fora do ciclo.

**Não executado:** Supabase real; envio real de arquivos ao bucket `produtividade`; rotina diária no pg_cron real.

## Carga de demonstração (27/11/2026)

`supabase/demo/dados-demonstracao.sql` aplicado no Supabase **de testes** a pedido do responsável, para visualização. Tudo fictício: 10 servidores extras (23 no total, todos com vínculo), 7 afastamentos, 19 demandas (3 de renovação criadas pela rotina), conversa e checklist, compromissos, 6 contratos com aluguéis/UCs/faturas (alguns vencidos), entregas de folhas, 2 pedidos de aprovação e um ciclo de produtividade do mês passado com 20 avaliações em todas as situações (resultado institucional homologado de 25,65). Designações de teste: administrador = autoridade revisora e instância de homologação. **Nunca rodar em produção.** Verificação de segurança depois da carga: 0 FALHA.

## Pendências da Fase 5

- ~~Aplicar a Fase 5 no Supabase de testes e republicar~~ **Feito em 27/11/2026** (PR #17). Verificação no banco real: 0 FALHA; bucket `produtividade` privado; rotina diária executada sem erro.
- Pendências do Adendo 01 (seção 13): continuam valendo os padrões da tabela acima.
- Designar, no ambiente de testes, a autoridade revisora e a instância de homologação para testar o ciclo inteiro.
- Os 13 servidores de teste estão sem vínculo: informar o vínculo antes de abrir uma competência de teste (senão ninguém é elegível).

## Fase 7 (executado em 27/11/2026, resultado real)

| Item | Resultado |
|---|---|
| `scripts/verificar-seguranca.sql` no Supabase de testes | **0 FALHA**; 3 ATENÇÃO esperadas (MFA desligada nos testes, permissões provisórias, servidores sem vínculo) |
| `scripts/testar-restauracao.sh` (local e no CI) | ok: 43 tabelas idênticas, 331 linhas; numeração das demandas continua; arquivo cifrado sem texto legível |
| `scripts/backup-storage.mjs` contra Storage simulado | ok: buckets e pastas aninhadas; chave errada recusada |
| CI com os passos novos (restauração + verificação) | verde |
| Workflow `backup.yml` real | **não executado**: faltam os secrets `SUPABASE_DB_URL`, `SUPABASE_SERVICE_ROLE_KEY` e `BACKUP_PASSPHRASE` |

Documentos: `docs/implantacao.md` (passo a passo e checklist de produção), `docs/seguranca/fase7-revisao-final.md` (OWASP consolidado, riscos R1–R8, LGPD), `docs/roteiro-testes.md` (roteiro geral para o responsável).

## Pendências da Fase 7

- **Roteiro geral de testes** pelo responsável (`docs/roteiro-testes.md`) e correções do que aparecer.
- **Secrets do backup** no GitHub (ver `docs/implantacao.md`, seção 4) e uma execução manual com sucesso.
- Decisões de produção: hospedagem com cabeçalhos HTTP, repositório privado, SMTP institucional, plano do Supabase com backup/PITR (riscos R1–R8 da revisão final).
- Parecer do DPO sobre `docs/lgpd.md` (bases legais, retenção, aviso de privacidade).
- Fase 5 (Produtividade / Adendo 01).

## Pendências da Fase 6

- **Relatório de produtividade**: depende da Fase 5.
- ~~Aplicar a Fase 6 no Supabase de testes e republicar~~ **Feito em 27/11/2026** (PR #14). Conferido: 42 tabelas, todas com RLS; nada liberado para `anon`; 11 funções de relatório; site republicado com a tela nova.
- Abrir os arquivos gerados no Excel e no LibreOffice e conferir a aparência (validação manual).

## Pendências da Fase 4

- **Modelo oficial das planilhas de contratos e faturas** (seção 9): as colunas atuais são provisórias.
- **Checklist de renovação**: os 4 itens são o exemplo do prompt; validar com a SEMFAZ (`contratos.checklist_renovacao`).
- **Corrigir dados de locador** (nome, e-mail, telefone) ainda não tem tela; hoje só por pedido de alteração do contrato com justificativa. Criar fluxo de aprovação próprio para o locador.
- **Reajuste automático** pelo índice na data-base: não implementado (só registro do índice e do mês). O reajuste entra por aditivo ou alteração de valor aprovada.
- Valor anual mostrado = valor mensal × 12 (o protótipo diz "anual (vigência)"; confirmar se deve ser o total da vigência).
- ~~Aplicar as Fases 3 e 4 no Supabase de testes~~ **Feito em 27/11/2026** (PR #13 juntado; 8 migrations aplicadas em ordem). Conferido no banco real: 41 tabelas, todas com RLS; nada liberado para `anon`; buckets privados (anexos, contratos, demandas, folhas-ponto); CPF do locador sem acesso pela API; pg_cron com `rotinas-diarias-demandas` e `avisar-atrasos-folhas`; rotina diária executada sem erro.
- ~~Republicar o site com as Fases 3 e 4~~ **Feito em 27/11/2026**.

## Pendências da Fase 3

- **Notificações por e-mail e no celular (push)** (6.10): as notificações internas funcionam. E-mail depende de SMTP próprio no Supabase; push depende de chaves VAPID e de uma Edge Function. Fica para quando o SMTP estiver configurado.
- Arrastar cartões no quadro funciona com mouse e toque; pelo teclado, o status muda na ficha da demanda.

## Pendências da Fase 2

- ~~Modelo real do PDF de folhas de ponto do RH~~ **Validado em 26/11/2026** com o relatório de novembro/2026 (59 páginas): texto selecionável, 1 página por servidor, matrícula numérica de 4 a 6 dígitos logo abaixo do rótulo "Matrícula" e nome abaixo de "Servidor". A leitura passou a ser por posição: 59/59 matrículas e nomes lidos. O cruzamento ignora zeros à esquerda; se houver ambiguidade, a página vai para conferência. O teste usa um PDF **fictício** no mesmo layout; o arquivo real não foi guardado nem versionado, e as cópias foram apagadas. CPF e demais dados da folha não são lidos.
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
