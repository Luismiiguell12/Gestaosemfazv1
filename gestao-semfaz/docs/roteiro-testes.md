# Gestão SEMFAZ — Roteiro geral de testes (Fases 1 a 6)

Para quem valida o sistema no site de testes: https://luismiiguell12.github.io/Gestaosemfazv1/

**Regras:** use só dados **fictícios** (nomes inventados, CPF de teste, PDFs de exemplo). Marque cada item com ✅ (funcionou) ou ❌ (problema). Em cada ❌, anote: o número do item, o que fez, o que esperava, o que apareceu e um print da tela. Os itens marcados ⏱ dependem da rotina diária (roda às 06:05) e só podem ser conferidos no dia seguinte.

---

## 0. Preparação (uma vez)

| # | Ação | Resultado esperado |
|---|---|---|
| 0.1 | Entrar com `admin@exemplo.gov.br` e com `secretaria@exemplo.gov.br` (senhas que você já criou) | Abre o Painel; o nome e o perfil aparecem no rodapé do menu |
| 0.2 | Escolher 3 e-mails **seus** para os outros perfis, usando apelido. Ex.: `seuemail+diretor@gmail.com`, `seuemail+coord@gmail.com`, `seuemail+func@gmail.com` | O Gmail entrega todos na mesma caixa |
| 0.3 | Como **administrador**: Unidades e usuários → "Diretor da DAT" → Solicitar alteração de dados → e-mail = `+diretor`; tipo de vínculo = Efetivo. Repetir para "Coordenador da COFIT" (`+coord`) e "Servidor A" (`+func`) | Cada pedido fica "Pendente" em Aprovações |
| 0.4 | Como **secretária**: Aprovações → aprovar os 3 pedidos | Os dados mudam na ficha do servidor |
| 0.5 | Como **secretária**: Unidades e usuários → + Convidar usuário → convidar os 3 (perfis Diretor, Coordenador, Funcionário) | Chega e-mail de convite; o link abre "Definir senha" |
| 0.6 | Definir as senhas (mín. 12 caracteres, com maiúscula, minúscula, número e símbolo) | Entra no sistema com o perfil certo |

> O envio de e-mails do Supabase de testes tem limite por hora. Se o convite não chegar, espere uns minutos e tente de novo.

Nos itens abaixo: **ADM** = administrador, **SEC** = secretária, **DIR** = diretor da DAT, **COO** = coordenador da COFIT, **FUN** = Servidor A (COFIT).

---

## 1. Acesso e segurança (Fase 1)

| # | Perfil | Passos | Esperado |
|---|---|---|---|
| 1.1 | — | Abrir o site sem estar logado | Vai para a tela de login; não existe "criar conta" |
| 1.2 | — | Errar a senha 1 vez | Mensagem genérica ("e-mail ou senha incorretos"), sem dizer qual errou |
| 1.3 | — | "Esqueci minha senha" com um e-mail convidado | Chega e-mail; o link permite definir nova senha |
| 1.4 | FUN | Tentar senha fraca (ex.: `12345678`) ao definir senha | Recusa e explica a regra |
| 1.5 | FUN | Ver o menu | Só Painel, Demandas, Calendário, Férias e folgas (e Produtividade "em definição") |
| 1.6 | FUN | Digitar na barra de endereço `/usuarios/` e `/aprovacoes/` | Mensagem de acesso não permitido; nenhum dado de outros aparece |
| 1.7 | SEC | Sair e entrar de novo; ficar 2 h sem usar | Pede login de novo depois do tempo de inatividade |
| 1.8 | ADM | Desativar o acesso do FUN (ficha do servidor) por pedido → SEC aprova → FUN tenta usar | FUN é desconectado e não consegue entrar. **Reativar depois** |
| 1.9 | — | No celular: abrir o site, menu ⋮ → "Instalar app" / "Adicionar à tela inicial" | Ícone Gestão SEMFAZ na tela inicial; abre em tela cheia |
| 1.10 | — | Celular: navegar por Painel, Demandas e Contratos | Menu em gaveta; nada corta na lateral; botões fáceis de tocar |

## 2. Estrutura, servidores e aprovações (Fase 1 e Adendo)

| # | Perfil | Passos | Esperado |
|---|---|---|---|
| 2.1 | SEC | Unidades e usuários: conferir a árvore (Gabinete → DAT, DEFC, assessorias e coordenadorias) | Estrutura igual à da SEMFAZ (fictícia por enquanto) |
| 2.2 | SEC | + Servidor na COFIT sem escolher "Tipo de vínculo" | Não salva; pede o vínculo |
| 2.3 | SEC | + Servidor com matrícula já usada (ex.: 000101) | Recusa: matrícula já cadastrada |
| 2.4 | SEC | + Servidor completo (vínculo Efetivo) | Aparece na lista; ficha mostra "elegível ao adicional" |
| 2.5 | SEC | Cadastrar outro como **Comissionado** e outro como **Temporário** | Ficha mostra "não elegível ao adicional" |
| 2.6 | SEC | Importar servidores: baixar modelo, preencher 3 linhas (1 com matrícula vazia, 1 com unidade inexistente, 1 certa), enviar | Prévia lista os erros por linha; botão Importar fica bloqueado |
| 2.7 | SEC | Corrigir a planilha e importar | Importa só quando não há erro; servidores aparecem com saldos |
| 2.8 | COO | Pedir alteração de dados de um servidor da COFIT (ex.: cargo) | Pedido "Pendente"; dado ainda não mudou |
| 2.9 | COO | Abrir Aprovações | Vê só os próprios pedidos; não tem botão de aprovar |
| 2.10 | SEC | Aprovações → abrir o pedido do COO | Mostra "como está" (riscado) e "como fica"; aprovar aplica a mudança |
| 2.11 | SEC | Recusar um pedido sem comentário | Exige comentário |
| 2.12 | ADM | Fazer um pedido e tentar aprová-lo com o próprio ADM | Não permite ("ninguém aprova o próprio pedido") |
| 2.13 | SEC | Pedido de alteração para um servidor; antes de aprovar, alterar o mesmo servidor por outro pedido aprovado; depois aprovar o primeiro | Primeiro pedido fica "Bloqueado" (o registro mudou) |
| 2.14 | SEC | Liberar módulo extra (ex.: Contratos) para o FUN | FUN passa a ver Contratos no menu |
| 2.15 | SEC | Calendário → Feriados: cadastrar um feriado municipal fictício; alterar outro (vai para aprovação) | Novo entra direto; alteração pede aprovação |
| 2.16 | qualquer | Busca geral (topo): digitar "COFIT", um nome de servidor, um nº de contrato | Resultados agrupados; só o que o perfil pode ver |
| 2.17 | SEC | Relatórios → Auditoria → Ver na tela (hoje) | Lista quem fez o quê (logins, pedidos, aprovações) |
| 2.18 | SEC | Sino de notificações | Avisos de pedidos de aprovação e resultados |

## 3. Férias, saldos e folhas de ponto (Fase 2)

| # | Perfil | Passos | Esperado |
|---|---|---|---|
| 3.1 | FUN | Painel → "Minhas férias e folgas": ver saldos | Mostra os saldos do RH |
| 3.2 | FUN | Férias e folgas → pedir férias de 15 dias | Pedido "Solicitado"; COO recebe aviso |
| 3.3 | FUN | Pedir férias sobrepondo o pedido anterior | Recusa (sobreposição) |
| 3.4 | COO | Aprovar o pedido **sem** substituto | Exige substituto da mesma unidade |
| 3.5 | COO | Aprovar com substituto | Escala mostra o período; substituto é avisado |
| 3.6 | COO | Pedir férias para 2 servidores do **mesmo cargo** no mesmo período | Aviso de mesmo cargo (não bloqueia) |
| 3.7 | DIR | Abrir a escala | Vê as coordenadorias da DAT; não vê a DEFC |
| 3.8 | SEC | Importar saldos (planilha: matrícula + 3 saldos) com 1 matrícula inexistente | Prévia aponta o erro; corrigida, atualiza os saldos |
| 3.9 | SEC | Folhas de ponto → enviar o PDF fictício (arquivo `folha-ponto-ficticia.pdf` enviado junto com este roteiro) | Lê as páginas, cruza as matrículas e mostra a separação por unidade |
| 3.10 | SEC | Conferir "páginas sem servidor" (matrícula inexistente) | Listadas como aviso, nunca descartadas; dá para vincular manualmente |
| 3.11 | SEC | Gerar os PDFs por unidade; baixar ZIP e PDF único | Um PDF por unidade com folha de rosto e servidores em ordem alfabética |
| 3.12 | COO | Folhas de ponto | Baixa só o PDF da COFIT |
| 3.13 | SEC | Registrar a entrega da folha à COFIT; depois a devolução | Situação muda: Não entregue → Entregue → Devolvida |
| 3.14 | ⏱ SEC | Deixar uma entrega sem devolução além do prazo | Aviso de atraso no sino (dias úteis, conta feriados) |

## 4. Demandas, calendário e painéis (Fase 3)

| # | Perfil | Passos | Esperado |
|---|---|---|---|
| 4.1 | COO | Demandas → Nova demanda (COFIT), 2 responsáveis, prazo e checklist de 3 etapas | Aparece em "A fazer"; responsáveis avisados |
| 4.2 | COO | Tentar criar demanda para a CONTA | Não permite (fora da unidade) |
| 4.3 | FUN | Ver o quadro | Só as demandas em que é responsável |
| 4.4 | FUN | Arrastar o cartão para "Em andamento" (no celular, tocar e arrastar) | Status muda; histórico registra |
| 4.5 | FUN | Marcar as 3 etapas do checklist | Barra completa; **não** conclui sozinha |
| 4.6 | FUN | Conversa: escrever com `@` mencionando o COO | COO recebe aviso; mensagem não pode ser apagada |
| 4.7 | FUN | Anexar um PDF; depois "nova versão" do mesmo anexo | Duas versões; a anterior continua disponível |
| 4.8 | COO | "Pedir atualização" | Responsáveis recebem aviso |
| 4.9 | COO | Dar feedback "Ajustar" numa mensagem | Selo de feedback aparece; FUN é avisado |
| 4.10 | FUN | "+ Sugerir demanda" no Painel | Fica "Sugerida"; COO aprova ou recusa (recusa exige comentário) |
| 4.11 | COO | Demandas recorrentes → modelo mensal | ⏱ Ocorrência criada no dia certo, uma vez só |
| 4.12 | SEC | Férias aprovadas de um responsável (item 3.5) | ⏱ No 1º dia útil do afastamento o substituto entra nas demandas e é avisado; no retorno sai das não concluídas |
| 4.13 | qualquer | ⏱ Demanda com prazo amanhã | Aviso de prazo próximo |
| 4.14 | COO | Calendário → novo compromisso com participantes | Aparece em mês, semana, dia e lista; participantes veem |
| 4.15 | FUN | Calendário | Vê só onde participa, prazos das suas demandas e feriados |
| 4.16 | SEC | Painel | Cartões por unidade (em dia / prazo apertado / com atraso), aprovações, ausências, compromissos, folhas a devolver |
| 4.17 | FUN | Painel | Indicadores próprios (abertas, atrasadas, concluídas no mês, % no prazo) |

## 5. Contratos, unidades consumidoras e faturas (Fase 4)

| # | Perfil | Passos | Esperado |
|---|---|---|---|
| 5.1 | SEC | Contratos → Novo contrato com CPF inválido (ex.: 111.111.111-11) | Recusa: CPF inválido |
| 5.2 | SEC | Novo contrato com CPF de teste `529.982.247-25`, vigência terminando daqui a ~60 dias, valor 2.500,00 | Abre a ficha; aluguéis mês a mês gerados |
| 5.3 | SEC | Na ficha, clicar em "dados" do locador | CPF e telefone **mascarados**; sem botão "exibir completo" |
| 5.4 | SEC | ADM concede o módulo extra "Dados completos de locadores" à SEC; abrir de novo | Botão "Exibir dados completos"; ao usar, fica na auditoria |
| 5.5 | SEC | Registrar pagamento de um aluguel vencido | Situação "Pago"; não pede aprovação |
| 5.6 | SEC | Desfazer o pagamento (com motivo) | Volta a "Vencido"; histórico registra o motivo |
| 5.7 | FUN (com módulo Contratos do item 2.14) | Solicitar alteração do valor mensal | Pedido pendente; só SEC/ADM aprova |
| 5.8 | SEC | Aprovar | Valor novo vale para os aluguéis não pagos a partir deste mês |
| 5.9 | SEC | Registrar aditivo de prazo (+12 meses) | Pendente; ADM aprova → vigência estendida e aluguéis gerados |
| 5.10 | SEC | Anexar PDF do contrato; tentar anexar um arquivo que não é PDF | PDF entra; o outro é recusado |
| 5.11 | ⏱ | Contrato com fim em ≤ 90 dias (item 5.2) | Demanda "Renovação do contrato nº X" criada uma vez, com checklist; aviso de vencimento |
| 5.12 | COO | Tentar abrir Contratos | Sem acesso (a não ser com módulo extra) |
| 5.13 | SEC | Importar contratos: modelo, 1 linha com CNPJ inválido e 1 certa | Prévia aponta o erro; importação só sem erros |
| 5.14 | SEC | Ficha → Vincular UC: Energisa e Iguá | Aparecem na ficha e em Unidades consumidoras |
| 5.15 | SEC | Unidades consumidoras → competência → Lançar fatura; Registrar pagamento | KPIs e situação atualizam; sem aprovação |
| 5.16 | SEC | Lançar duas faturas da mesma UC no mesmo mês | Recusa a segunda |
| 5.17 | SEC | Importar faturas (modelo) com 1 fornecedor inválido | Prévia aponta o erro |
| 5.18 | SEC | Painel | "Contratos vencendo" e "Aluguéis pendentes" com números; lista de contratos perto do vencimento |

## 6. Relatórios e exportações (Fase 6)

| # | Perfil | Passos | Esperado |
|---|---|---|---|
| 6.1 | SEC | Abrir cada relatório e clicar "Ver na tela" | Tabela com os dados; "Produtividade" desabilitado (em definição) |
| 6.2 | SEC | Gerar "Contratos" em **Excel** | Abre no Excel/LibreOffice: números e datas formatados, filtro no cabeçalho |
| 6.3 | SEC | Gerar "Aluguéis" em **PDF** | A4 deitado, título, filtros, autor, data e páginas numeradas |
| 6.4 | SEC | Gerar "Demandas por unidade" em **CSV** e abrir no Excel | Colunas separadas e acentos corretos |
| 6.5 | SEC | "Gerados recentemente" → clicar no formato | Gera de novo com os mesmos filtros |
| 6.6 | COO | Relatórios | Só relatórios dos módulos que tem; dados só da COFIT; sem Auditoria |
| 6.7 | DIR | "Demandas por unidade" | Só unidades da DAT |
| 6.8 | SEC | Relatórios → Auditoria filtrando "Exportações" | Cada exportação registrada (quem, formato, filtros) |

## 8. Produtividade — Adendo 01 (Fase 5)

Antes: informe o **tipo de vínculo** dos servidores de teste (pedido de alteração → aprovação); só efetivos entram. Em Produtividade › Configuração, designe a **autoridade revisora** (ex.: DIR) e a **instância de homologação** (ex.: ADM).

| # | Perfil | Passos | Esperado |
|---|---|---|---|
| 8.1 | SEC | Produtividade → competência do mês passado → "Abrir" | Uma avaliação por servidor elegível, com a chefia imediata (FUN → COO; COO → DIR; DIR → SEC) |
| 8.2 | SEC | Conferir que comissionado/temporário não aparecem | Fora do ciclo |
| 8.3 | COO | Abrir a avaliação do FUN; nota 25 em F1 | Recusa (máximo 20) |
| 8.4 | COO | Preencher notas e justificativas sem provas; "Enviar ao servidor" | Recusa e lista o que falta |
| 8.5 | COO | No painel de subsídios, "usar" uma demanda como prova; adicionar referência externa e um anexo | Provas aparecem no indicador; o sistema não sugere nota |
| 8.6 | COO | Marcar "critério equivalente" em F4 sem justificar | Não envia até justificar |
| 8.7 | COO | Enviar | FUN recebe aviso |
| 8.8 | FUN | Painel → "Minha produtividade" → Dar ciência | Prazo de recurso (5 dias úteis) aparece |
| 8.9 | FUN | Recorrer com razões | Vai para a revisora; DIR recebe aviso |
| 8.10 | DIR | Decidir o recurso sem fundamentação / alterando nota sem justificativa | Recusa; com fundamentação, registra e vai para homologação |
| 8.11 | COO | Tentar homologar a avaliação que fez (se estiver designado) | Recusa (segregação) |
| 8.12 | ADM | Homologação → marcar e homologar em lote; devolver uma com motivo | Homologadas ficam travadas; a devolvida volta a rascunho com o motivo |
| 8.13 | ADM | Abrir uma homologada e tentar editar | Não há edição; só "Retificar" (SEC/ADM) |
| 8.14 | SEC | Retificar com justificativa | Original preservado; nova avaliação em rascunho ligada |
| 8.15 | SEC | Encaminhamento SEMAD → gerar; baixar Excel, CSV e Anexo II (PDF) | Arquivos com nota, %, fator e percentual efetivo; versão registrada |
| 8.16 | SEC | Institucional: lançar metas de um quadrimestre **futuro**; tentar alterar meta do quadrimestre atual | Futuro: aceita; atual: só retificação (não vale para o ciclo) |
| 8.17 | SEC | Lançar/importar arrecadação de um quadrimestre encerrado e "Apurar" | Memória de cálculo por receita; índice nunca passa de 1; pontos ≤ 30 |
| 8.18 | ADM | Homologar o resultado institucional (não pode ser quem apurou) | Próximas competências usam esse resultado; antes disso, "regra de transição" |
| 8.19 | FUN | Tentar abrir a avaliação de outro servidor pelo endereço | Acesso não permitido |
| 8.20 | SEC | Relatórios → Produtividade e Dossiê do ciclo (PDF/Excel) | Dossiê com ciência, recurso, homologação, retificação e encaminhamentos |
| 8.21 | ⏱ | Avaliação "ciente" sem recurso após o prazo | Vai sozinha para "Aguardando homologação" |

## 7. Encerramento

| # | Verificação | Esperado |
|---|---|---|
| 7.1 | Reativar usuários e desfazer testes que deixaram dados estranhos | Ambiente limpo para a próxima rodada |
| 7.2 | Juntar todos os ❌ com prints e mandar de uma vez | Correções feitas em lote |
| 7.3 | Indicar textos, nomes ou telas que queira mudar | Ajustes registrados |

Itens que **não** estão neste roteiro porque dependem de definição: Produtividade (Fase 5 / Adendo 01), envio de avisos por e-mail e push, e o ambiente de produção (ver `docs/implantacao.md`).
