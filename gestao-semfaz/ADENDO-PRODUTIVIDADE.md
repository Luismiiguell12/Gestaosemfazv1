# Adendo 01 – Módulo de Produtividade (Adicional de Desempenho e Produtividade)

> **Para o Claude Code.** Este adendo **substitui a seção 6.4 (Produtividade)** do `docs/PROMPT.md` e acrescenta regras às seções 6.7 (Servidores), 6.12 (Auditoria) e 7.2 (Telas, item 12). Em caso de conflito com o `PROMPT.md`, **vale este adendo**.
>
> **Base legal:** minuta de Decreto Municipal que regulamenta o Adicional de Desempenho e Produtividade (arts. 15-A a 15-E da Lei Complementar Municipal nº 138/2025) no âmbito da SEMFAZ. Como o texto ainda é **minuta**, todo número (pontos, pesos, mínimos, faixas, prazos) deve ficar em **configuração versionada**, nunca fixo no código.

---

## 1. Objetivo

O módulo de Produtividade passa a ser o **sistema de avaliação mensal de desempenho** previsto no decreto. Ele cobre todo o ciclo: avaliação pela chefia → ciência do servidor → recurso → revisão → homologação → encaminhamento à Secretaria Municipal de Administração (SEMAD) para a folha.

As métricas de demandas que já estavam previstas (recebidas, concluídas, no prazo, atrasadas, tempo médio em dias úteis, demanda com vários responsáveis conta para cada um) **continuam existindo**. Elas passam a ser **subsídio e prova** para a avaliação, e não a nota em si.

---

## 2. Quem é avaliado (elegibilidade)

1. São elegíveis os servidores **efetivos** lotados ou em exercício na SEMFAZ, inclusive os que exercem cargo em comissão ou função de confiança na secretaria.
2. **Não são elegíveis:** quem ocupa **somente** cargo em comissão, os **contratados por tempo determinado** e os integrantes de carreiras excluídas pelo § 3º do art. 15-A da LC 138/2025.
3. Acrescentar ao cadastro de servidor (seção 6.7):
   - `tipo de vínculo`: efetivo | comissionado | temporário (obrigatório);
   - `exerce cargo em comissão/função de confiança`: sim/não;
   - `elegível ao adicional`: calculado pelo banco a partir do vínculo e do cargo. Não pode ser digitado livremente.
4. O cadastro de **cargos** ganha a marca `carreira excluída do adicional` (sim/não). **PENDENTE:** a lista oficial de carreiras excluídas (§ 3º do art. 15-A) ainda não foi enviada. Enquanto isso, nenhuma carreira vem marcada e o item fica registrado em `docs/PROJECT_STATUS.md`.
5. A planilha de importação de servidores passa a ter a coluna `tipo de vínculo`.

---

## 3. Desempenho funcional (mensal, até 70 pontos)

### 3.1 Indicadores (configuráveis, valores iniciais)

| Código | Indicador | Máximo |
|---|---|---|
| F1 | Qualidade e eficiência na execução das atividades | 20 |
| F2 | Cumprimento de prazos e metas de trabalho | 15 |
| F3 | Produtividade e entregas realizadas | 15 |
| F4 | Qualidade do atendimento ao contribuinte e ao público interno (quando compatível) | 10 |
| F5 | Organização, responsabilidade e cooperação institucional | 10 |
| | **Total** | **70** |

### 3.2 Regras obrigatórias

1. **Quem avalia:** a **chefia imediata** do servidor, conforme a estrutura cadastrada:
   - funcionário → coordenador da unidade (ou chefe da assessoria);
   - coordenador de coordenadoria subordinada a diretoria → diretor;
   - coordenador ou chefe de unidade ligada ao Gabinete → Secretário(a);
   - diretor → Secretário(a).

   Deve existir um campo de **chefia imediata substituta/designada por servidor** (para exceções e afastamentos da chefia), alterável pela Secretária ou pelo Administrador, com auditoria.
2. Cada indicador recebe uma nota entre 0 e o máximo, com até 2 casas decimais. O banco impede valor fora do limite (CHECK).
3. **Prova obrigatória (art. 6º):** cada indicador precisa de **justificativa em texto** e de **pelo menos um elemento comprobatório**, que pode ser:
   - um ou mais **registros do sistema**: demandas do mês (link direto), checklist, mensagens de feedback da chefia ("Aprovado", "Ajustar", "Refazer");
   - **anexo** (PDF, imagem, DOCX, XLSX), seguindo as regras de documentos do prompt;
   - **referência externa** em texto (número de processo, protocolo, relatório).

   Sem prova em todos os indicadores, o formulário **não pode ser enviado** (validação no banco, não só na tela).
4. **Critério equivalente (art. 6º, § 1º):** se um indicador não for compatível com as atribuições do servidor (por exemplo, F4 para quem não atende público), a chefia marca "critério equivalente" e escreve a justificativa, que é obrigatória. A nota continua no mesmo indicador e com o mesmo máximo.
5. **Condições de trabalho (art. 6º, § 2º):** campo opcional "limitações estruturais ou operacionais" no formulário, que aparece no demonstrativo.
6. **Proibido nota automática (art. 4º, § 2º):** o sistema **não preenche nem sugere pontos**. Ele mostra, ao lado do formulário, um **painel de subsídios do mês** do servidor, só com fatos:
   - demandas recebidas, concluídas, concluídas no prazo, atrasadas;
   - tempo médio em dias úteis;
   - itens de checklist concluídos;
   - feedbacks da chefia no mês;
   - dias de afastamento.

   Cada número leva à lista de registros correspondente, e a chefia pode anexar qualquer um como prova com um clique.
7. **Mudança de unidade ou de atribuições no mês (art. 14, § 2º):** o servidor recebe **uma avaliação parcial por período**, cada uma feita pela chefia do período. A pontuação funcional do mês é a **média ponderada pelos dias de exercício elegível** de cada período. O banco calcula; ninguém digita.

---

## 4. Desempenho institucional (quadrimestral, até 30 pontos)

### 4.1 Receitas e pesos (configuráveis, valores iniciais)

| Código | Receita | Peso |
|---|---|---|
| R1 | IPTU | 25% |
| R2 | ISSQN | 30% |
| R3 | ITBI | 10% |
| R4 | Taxas (poder de polícia e serviços específicos e divisíveis) | 10% |
| R5 | Recuperação de créditos tributários inscritos em dívida ativa (com juros e multas) | 25% |

A soma dos pesos deve ser 100% (o banco valida).

### 4.2 Cálculo (no banco, em `numeric`, nunca em ponto flutuante)

```
indice_receita = LEAST(1, arrecadado_quadrimestre / meta_quadrimestre)
pontos_institucionais = LEAST(30, SUM(indice_receita × peso) × 30)
```

- Guardar o resultado com 4 casas decimais e a **memória de cálculo** completa: meta, arrecadado, índice, peso e contribuição de cada receita.
- Meta igual a zero ou ausente → o quadrimestre **não pode ser apurado** (erro claro, nunca divisão por zero).
- A dívida ativa (R5) é lançada **separada** das demais receitas. A tela de lançamento exibe o aviso "não somar dívida ativa nas outras receitas".

### 4.3 Metas e arrecadação

1. **Metas** por quadrimestre (jan–abr, mai–ago, set–dez) e por receita, com **memória de cálculo** e **fonte** (texto + anexo opcional).
2. As metas devem ser **publicadas antes do início do quadrimestre**. Depois que o quadrimestre começa, a meta fica **travada no banco** (trigger): nenhuma alteração, nem pelo Administrador. Correção só por novo registro de "retificação" com justificativa, que **não vale para o ciclo já iniciado** (art. 11, § 2º, e art. 24).
3. **Arrecadação realizada** por receita e quadrimestre, lançada **manualmente ou por importação de planilha** (XLSX/CSV) com validação e relatório de erros antes de gravar, como nas demais importações. Cada lançamento registra a fonte (relatório contábil oficial) e permite anexo.
4. Permissão própria: `produtividade.institucional.gerir`. **PENDENTE:** definir oficialmente quem recebe essa permissão. Sugestão: ASPLAN para metas e COACAM/CONTA para arrecadação. Por padrão, só a Secretária e o Administrador têm a permissão e podem concedê-la como módulo extra.
5. Apurar o quadrimestre gera o **resultado institucional**, que só fica disponível depois de **homologado** (mesma regra de segregação da seção 6).

### 4.4 Qual resultado institucional vale para cada mês

**PENDENTE de definição oficial.** Padrão a implementar, deixando a regra **configurável**:
- Cada mês avaliado usa o **último resultado institucional homologado** até a data de fechamento do mês.
- Enquanto não existir nenhum resultado institucional homologado, aplica-se a **regra de transição** (seção 5.2).
- O demonstrativo sempre mostra qual quadrimestre foi usado.

---

## 5. Nota total, mínimos e percentual

### 5.1 Regra normal

```
nota_total = pontos_funcionais (≤ 70) + pontos_institucionais (≤ 30)
```

### 5.2 Regra de transição (até o primeiro resultado institucional)

```
nota_total = (pontos_funcionais / 70) × 100
```

O demonstrativo indica "regra de transição – § 12 do art. 15-B".

### 5.3 Enquadramento

1. **Desprezar a fração:** `nota_enquadramento = FLOOR(nota_total)`. Exemplo: 69,99 vira 69. Nunca arredondar para cima.
2. **Mínimos cumulativos:** `pontos_funcionais ≥ 42` **e** `nota_enquadramento ≥ 60`. Se não atingir os dois, o percentual é 0% e o motivo aparece no demonstrativo.
3. **Faixas (configuráveis, valores iniciais):**

| Nota (já sem fração) | Percentual |
|---|---|
| 60 a 69 | 12% |
| 70 a 79 | 18% |
| 80 a 89 | 24% |
| 90 a 100 | 30% |

4. Percentual máximo: 30%. O banco valida que nenhuma faixa ultrapasse esse limite.

### 5.4 Proporcionalidade (art. 14)

```
fator = dias_de_exercicio_elegivel / dias_corridos_da_competencia
percentual_efetivo = percentual × fator
```

- Atenção: aqui são **dias corridos do mês**, ao contrário dos prazos do sistema, que são em dias úteis.
- Os dias elegíveis consideram a data de entrada e de saída na SEMFAZ e os afastamentos cadastrados.
- Cada **tipo de afastamento** (férias, licença-prêmio, folga etc.) tem a configuração "conta como efetivo exercício para o adicional: sim/não". **PENDENTE de validação jurídica.** Padrão inicial: **férias, licença-prêmio e folga contam como exercício**. Tipos novos entram como "não conta" até alguém configurar.

### 5.5 Valor em R$

**PENDENTE de decisão da SEMFAZ.** Padrão a implementar: o sistema **não guarda vencimento básico** e **não calcula valor em R$**. Ele entrega à SEMAD a nota, o percentual, o fator de proporcionalidade e o percentual efetivo, e a folha aplica sobre o vencimento.

Deixar preparado, **desligado por configuração**, um campo opcional de vencimento básico por competência, com acesso restrito (LGPD). Quando ligado, o sistema calcula `valor = vencimento_basico × percentual_efetivo` e preenche o campo de R$ do Anexo II.

### 5.6 Versionamento das regras

Indicadores, máximos, pesos, mínimos, faixas e regra de transição ficam em uma **tabela de regras versionada** com data de início de vigência. Cada ciclo grava **qual versão usou**. Mudar as regras nunca recalcula ciclos já abertos ou fechados.

---

## 6. Fluxo do ciclo mensal (máquina de estados no banco)

```
Rascunho → Enviada ao servidor → Ciente
   Ciente → (prazo de recurso corre)
      → Sem recurso (prazo esgotado) ─────────────┐
      → Em recurso → Recurso decidido ────────────┤
                                                  ↓
                                   Aguardando homologação
                                     → Homologada → Encaminhada à SEMAD
                                     → Devolvida à chefia (volta para Rascunho, com motivo)
```

Regras:

1. **Abertura do ciclo:** a competência (mês/ano) é aberta pela Secretária ou pelo Administrador. O sistema cria uma avaliação em Rascunho para cada servidor elegível, já ligada à chefia imediata.
2. **Envio:** a chefia só envia com todos os indicadores pontuados e provados (seção 3.2).
3. **Ciência (art. 16):** o servidor vê a avaliação completa (notas, justificativas, provas, demonstrativo) e clica em "Dar ciência". A data e a hora ficam registradas.
   - Se não der ciência em **3 dias úteis** (configurável), a chefia e a Secretária são notificadas. A chefia pode registrar a ciência por outro meio (presencial, assinatura em papel com anexo obrigatório).
   - **PENDENTE de validação.**
4. **Recurso:** **5 dias úteis** a partir da ciência (configurável), contados com o cadastro de feriados. O servidor escreve as razões e pode anexar documentos. Depois do prazo, o botão some e o banco recusa recursos fora do prazo.
5. **Revisão:** a **autoridade revisora** decide em até **10 dias úteis** (configurável), com **decisão fundamentada obrigatória**: mantém ou altera indicadores, sempre com justificativa. A partir do 8º dia útil, o sistema alerta a revisora e a Secretária.
6. **Homologação (art. 17):** feita por uma **instância de homologação** diferente de quem avaliou. A instância confere a regularidade formal, as provas, os critérios e os cálculos, e pode:
   - **homologar**, individualmente ou em lote;
   - **devolver** à chefia com motivo.
7. **Segregação de funções (arts. 16 §3º, 17 e 18), garantida no banco:**
   - ninguém avalia, revisa ou homologa a **própria** avaliação;
   - quem avaliou não pode revisar nem homologar a mesma avaliação;
   - quem revisou não pode homologar a mesma avaliação.
8. **Autoridade revisora e instância de homologação** são definidas por ato do Secretário. No sistema, são **designações configuráveis** (pessoas ou grupo), com data de início e fim, alteráveis pela Secretária ou pelo Administrador e auditadas. **PENDENTE:** nomes oficiais.
9. **Encaminhamento à SEMAD (art. 19):** depois de homologada, a competência gera o **arquivo de encaminhamento** (XLSX e CSV) e o **PDF do Anexo II** por servidor, com:
   - nome, matrícula, cargo efetivo e unidade;
   - competência;
   - pontuação funcional, pontuação institucional aplicada e quadrimestre de referência;
   - nota total, nota de enquadramento, percentual, dias elegíveis/dias do mês, fator e percentual efetivo;
   - (valor em R$ só se a opção da seção 5.5 estiver ligada).

   O encaminhamento registra data, responsável e versão do arquivo. **Inconsistência apontada pela SEMAD** gera um registro de correção ligado à avaliação; nada é apagado.
10. **Alertas:** chefia com avaliações em Rascunho perto do fechamento; servidor com ciência pendente; prazo de recurso terminando; revisão perto do prazo; competência pronta para homologar.

---

## 7. Documentos gerados

1. **Anexo I – Formulário de Avaliação Mensal do Desempenho Funcional (PDF):** servidor, cargo efetivo, função exercida, unidade, mês/ano, tabela dos 5 indicadores (máximo e atribuído), registros e provas, justificativa e critérios equivalentes, total /70, ciência do servidor (data/hora) e chefia (nome, data/hora).
2. **Anexo II – Demonstrativo de Apuração (PDF):** todos os blocos do modelo da minuta (I a V), incluindo a memória de cálculo institucional, os dois mínimos ("Sim/Não"), o percentual, os dias elegíveis, a homologação, o recurso e o encaminhamento.
3. Os modelos dos anexos ficam como **modelos editáveis** (art. 25), sem mudar os campos obrigatórios.

---

## 8. Permissões e LGPD

| Quem | Vê | Pode |
|---|---|---|
| Servidor | Só as próprias avaliações e demonstrativos | Dar ciência, recorrer |
| Chefia imediata | As avaliações das pessoas que avalia | Preencher, enviar, registrar ciência por outro meio |
| Diretor | Avaliações das coordenadorias da diretoria (leitura) | — |
| Autoridade revisora | Só as avaliações com recurso dirigido a ela | Decidir recurso |
| Instância de homologação | Avaliações da competência em homologação | Homologar, devolver |
| Secretária / Administrador | Tudo | Abrir ciclo, designar revisora e homologação, configurar regras, encaminhar à SEMAD |
| Quem tem `produtividade.institucional.gerir` | Metas e arrecadação | Lançar e importar metas e arrecadação |

- Avaliação de desempenho é **dado pessoal**: tudo protegido por RLS, nada em logs de aplicação, exportações auditadas.
- Os resultados **agregados** (por unidade, sem nome) podem aparecer nos painéis. Notas individuais só para os perfis acima.
- Atualizar `docs/lgpd.md` com esse tratamento.

---

## 9. Auditoria e arquivo (arts. 21 a 23)

- Tudo fica guardado **para sempre** e é imutável depois de homologado: formulários, provas, justificativas, ciências, recursos, decisões, homologações, memórias de cálculo, metas, arrecadação, versões de regras e encaminhamentos.
- Correção depois da homologação = **novo registro de retificação** ligado ao original, com justificativa e nova homologação. Nunca editar o registro original.
- Relatório "Dossiê do ciclo" por competência, para o **Controle Interno**: lista completa, com links para todos os documentos e memórias de cálculo.

---

## 10. Telas (seguir o padrão visual dos protótipos, tema Índigo)

Não há protótipo próprio para estas telas. Elas seguem exatamente o padrão dos protótipos existentes (seção 7.2 do prompt). A tela 12 (Produtividade da equipe) vira o ponto de entrada do módulo, com abas:

1. **Avaliações do mês:** lista dos servidores da competência com o estado de cada um (Rascunho, Enviada, Ciente, Em recurso, Aguardando homologação, Homologada), filtro por unidade e chefia, e indicadores de pendência. É a tela de trabalho da chefia.
2. **Formulário de avaliação:** à esquerda, os 5 indicadores com nota, justificativa, critério equivalente e provas. À direita, o **painel de subsídios do mês** (seção 3.2, item 6). No rodapé, total /70 e o botão "Enviar ao servidor".
3. **Institucional:** metas e arrecadação por quadrimestre, a memória de cálculo e o resultado com os pontos /30. Botões para lançar, importar planilha e apurar.
4. **Recursos:** fila da autoridade revisora, com prazo em dias úteis.
5. **Homologação:** competência inteira, com conferência e homologação individual ou em lote, e devolução com motivo.
6. **Encaminhamento SEMAD:** gerar e baixar o arquivo e os PDFs, com o histórico de envios e correções.
7. **Configuração** (Secretária/Administrador): versões das regras, designações da revisora e da homologação, tipos de afastamento e prazos.

**Painel do funcionário (tela 5):** o bloco "Minha produtividade" passa a mostrar:
- a avaliação do último mês: nota, faixa e estado;
- os botões **"Dar ciência"** e **"Recorrer"** (dentro do prazo);
- o histórico dos meses anteriores.

Os números de demandas continuam lá como informação. O aviso "os critérios seguirão o modelo dos fiscais" sai e entra o texto: "Avaliação conforme o Decreto do Adicional de Desempenho e Produtividade".

---

## 11. Testes obrigatórios (além dos do prompt)

1. Nota de indicador acima do máximo ou negativa → recusada pelo banco.
2. Envio sem justificativa ou sem prova em algum indicador → recusado pelo banco.
3. Cálculo institucional com os valores do exemplo abaixo → 25,65 pontos.
4. Arrecadação acima da meta → índice limitado a 1.
5. Nota 69,99 → enquadramento 69 → 12%. Nota 59,99 → 59 → 0%.
6. Funcional 41 com total 75 → 0% (mínimo funcional não atingido).
7. Regra de transição: funcional 56 sem resultado institucional → nota 80 → 24%.
8. Proporcionalidade: 20 dias elegíveis em mês de 30 → fator 0,6667.
9. Mudança de unidade no mês → média ponderada correta.
10. Recurso fora do prazo (dias úteis com feriado no meio) → recusado.
11. Autoavaliação, autorrevisão e autohomologação → recusadas pelo banco, inclusive para o Administrador.
12. Avaliador tentando homologar a avaliação que fez → recusado.
13. Alteração de meta depois do início do quadrimestre → recusada pelo banco.
14. Alteração de avaliação homologada → recusada; só retificação.
15. Servidor tentando ler a avaliação de outro servidor pela API → recusado.
16. Servidor não elegível (comissionado puro, temporário, carreira excluída) → não entra no ciclo.

**Exemplo de referência para o teste 3:**

| Receita | Índice | Peso | Contribuição |
|---|---|---|---|
| IPTU | 0,90 | 25% | 0,225 |
| ISS | 1,00 | 30% | 0,300 |
| ITBI | 0,80 | 10% | 0,080 |
| Taxas | 1,00 | 10% | 0,100 |
| Dívida ativa | 0,60 | 25% | 0,150 |
| **Soma** | | | **0,855** |

- 0,855 × 30 = **25,65**.
- Com funcional 56: total 81,65 → enquadramento 81 → **24%**.

---

## 12. Onde entra nas fases

- **Fase em andamento:** não interromper. Apenas:
  - registrar este adendo em `docs/PROJECT_STATUS.md` e nas decisões;
  - se o cadastro de servidores e cargos já estiver sendo modelado, incluir agora os campos da seção 2 (tipo de vínculo, cargo em comissão/função, carreira excluída), para evitar migração destrutiva depois.
- **Fase 5 (Produtividade):** implementar este adendo completo.
- **Fase 6 (Relatórios):** incluir Anexo I, Anexo II, arquivo SEMAD e Dossiê do ciclo nos relatórios.

---

## 13. Pendências deste adendo (registrar em `docs/PROJECT_STATUS.md`)

1. Lista de carreiras excluídas (§ 3º do art. 15-A da LC 138/2025).
2. Se o sistema calcula valor em R$ (padrão: não).
3. Qual resultado institucional vale para cada mês (padrão: último homologado).
4. Quem lança metas e arrecadação (padrão: só Secretária e Administrador, que concedem a permissão).
5. Autoridade revisora e instância de homologação (padrão: designação configurável).
6. Quais afastamentos contam como efetivo exercício (padrão: férias, licença-prêmio e folga contam).
7. Prazo e forma de ciência quando o servidor não acessa o sistema (padrão: 3 dias úteis + registro por outro meio).
8. Texto final do decreto: a minuta pode mudar, por isso todos os números ficam configuráveis.
