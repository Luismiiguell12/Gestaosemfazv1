# Prompt Gestão SEMFAZ – Rascunho v2 (consolidado)

## 1. Papel e forma de trabalho

Atue como engenheiro de software sênior e líder técnico responsável por projetar, implementar, testar e documentar o sistema Gestão SEMFAZ. Trabalhe por fases, uma de cada vez. Ao final de cada fase, pare, apresente um relatório (arquivos, tabelas, regras, testes executados e resultado real, pendências) e aguarde validação. Nunca declare como testado algo que não foi executado. Não invente regras de negócio: quando algo não estiver definido, adote a opção mais conservadora, deixe configurável e registre como pendente em docs/PROJECT\_STATUS.md.

## 2. Contexto

Plataforma interna da Secretaria Municipal da Fazenda (SEMFAZ) de Lagarto/SE para reunir, em um só lugar, o acompanhamento das unidades da secretaria (demandas, calendário, produtividade), os contratos de locação e suas despesas, a gestão de servidores (férias, licenças, folgas) e a organização das folhas de ponto. Cerca de 63 servidores. Interface em português, responsiva, acessível pela internet só para usuários autenticados. Deve funcionar como site e como aplicativo instalável no celular desde a primeira versão (ver 6.22); a publicação nas lojas fica para o futuro. Arquitetura modular: novos módulos devem poder ser incluídos sem refazer os existentes.

## 3. Estrutura organizacional

Baseada na minuta de reforma administrativa da SEMFAZ para 2027. O organograma deve ser cadastrável no sistema (não fixo no código), pois a lei pode mudar.

- Gabinete do Secretário
  - ASPLAN, ASTIN, Assessoria Jurídica e Coordenadoria do PAV e da Ordem Cronológica (ligadas direto ao Gabinete)
  - DAT – Diretoria de Administração Tributária: COACAM, COFIT, COAC, COCMI
  - DEFC – Diretoria de Execução Financeira e Contabilidade: CONTA, COEF

Cada servidor pertence a uma unidade e ocupa um cargo. Pode receber acesso adicional a outra unidade como permissão extra.

## 4. Perfis e permissões

| Perfil | Vê | Pode |
| --- | --- | --- |
| Administrador do sistema | Tudo, sem restrição | Manutenção geral; todas as ações ficam na auditoria |
| Secretário(a) | Todas as unidades | Editar todos os calendários; calendário geral próprio; conceder permissões |
| Diretor | Sua diretoria e coordenadorias | Criar e distribuir demandas; aprovar sugestões e férias; editar calendários da diretoria |
| Coordenador / chefe de assessoria | Sua unidade | Criar e distribuir demandas; aprovar sugestões e férias; editar calendário da unidade |
| Funcionário | Só suas demandas, sua produtividade e compromissos em que foi incluído | Sugerir demandas; pedir férias; calendário só leitura |

O módulo de contratos não pertence a nenhuma unidade: a secretária concede ou retira o acesso a quem designar. Permissões são aplicadas no backend, nunca só na interface.

**Pacote padrão de módulos e módulos extras por usuário:**

- Cada usuário recebe automaticamente, ao ter perfil e unidade definidos, um **pacote padrão de módulos** visíveis no menu lateral, de acordo com o perfil (Secretária, Diretor, Coordenador, Funcionário, Administrador do sistema) e a unidade. Os pacotes padrão são configuráveis no sistema.
- A Secretária (e o Administrador do sistema) pode **liberar ou retirar módulos extras** de um usuário específico (por exemplo, dar o módulo de Contratos de locação a um funcionário da COFIT), **sem alterar o perfil nem as demais permissões** dele.
- O módulo extra concede acesso ao módulo, mas continua respeitando as regras de escopo: o usuário só vê os dados que o módulo e o seu escopo permitem.
- Liberar ou retirar módulo extra feito pela Secretária ou pelo Administrador **vale na hora, sem passar pela Central de aprovações**, mas fica registrado na auditoria (quem, para quem, qual módulo, quando).
- Na tela de Unidades e usuários, cada usuário mostra o pacote padrão e, separadamente, os módulos extras, com botão para adicionar e remover.
- O controle é aplicado no backend (RLS e funções), não só escondendo itens do menu.

**Pacote padrão por perfil — PENDENTE: a SEMFAZ vai elaborar e enviar a definição oficial das permissões por módulo. A tabela abaixo é só um rascunho de referência: não implementar como definitiva e não avançar nessa parte sem a definição oficial.**

| Módulo | Administrador do sistema | Secretária | Diretor | Coordenador | Funcionário |
| --- | --- | --- | --- | --- | --- |
| Painel | Geral | Geral | Da diretoria | Da unidade | Pessoal |
| Demandas | Tudo | Tudo | Diretoria: criar, distribuir, aprovar sugestões | Unidade: criar, distribuir, aprovar sugestões | Próprias; sugerir |
| Calendário | Tudo | Ver e editar todos + geral | Ver e editar da diretoria | Ver e editar da unidade | Só leitura, só onde foi incluído |
| Contratos de locação | Tudo | Tudo | Não (só como extra) | Não (só como extra) | Não (só como extra) |
| Unidades consumidoras e faturas | Tudo | Tudo | Não (só como extra) | Não (só como extra) | Não (só como extra) |
| Férias e folgas | Tudo | Todos; aprovar | Diretoria; aprovar | Unidade; aprovar | Próprias; solicitar |
| Folhas de ponto | Tudo; enviar PDF | Tudo; enviar PDF | Da diretoria: baixar, imprimir, entrega | Da unidade: baixar, imprimir, entrega | Não |
| Produtividade | Tudo | Todas as unidades | Da diretoria | Da unidade | Própria |
| Aprovações | Aprovar alterações | Aprovar alterações | Seus pedidos | Seus pedidos | Seus pedidos |
| Relatórios | Tudo | Tudo | Da diretoria | Da unidade | Próprios |
| Unidades e usuários | Tudo | Tudo; liberar módulos extras | Consulta da diretoria | Consulta da unidade | Não |
| Auditoria | Tudo | Tudo | Não | Não | Não |

Chefes de assessoria e da Coordenadoria do PAV usam o pacote de Coordenador. Qualquer célula "Não" pode ser liberada individualmente como módulo extra.

## 5. Autenticação

Login por e-mail e senha; sem cadastro público; novos usuários só por convite; recuperação de senha por e-mail; verificação em duas etapas obrigatória para administrador e secretária, recomendada para diretores; usuário desativado perde acesso imediatamente, mesmo com sessão aberta; primeiro administrador criado por script local.

## 5.1 Segurança e proteção de dados (obrigatório)

O sistema trata dados sigilosos da administração pública e dados pessoais de servidores. Toda proteção real fica no backend: a interface apenas esconde o que o usuário não pode fazer, mas nunca é a barreira de segurança.

**Banco de dados e API**

- Row Level Security habilitada em todas as tabelas, sem exceção; tabela sem política significa sem acesso.
- Funções de autorização no banco (por perfil, unidade e permissão extra), com search\_path fixo.
- No navegador, somente a URL pública e a chave pública (anon key). A chave administrativa (service-role) só em funções de servidor, scripts locais e secrets do GitHub Actions; nunca no código do frontend.
- Toda função de servidor valida o token do usuário, a permissão e os dados recebidos antes de agir.
- CORS restrito ao domínio oficial do sistema; limite de requisições nas funções sensíveis (login, convite, exportação, importação).
- Mensagens de erro ao usuário sem detalhes internos (sem SQL, sem stack trace, sem dados pessoais).
- Testes automáticos que tentam ler, criar, alterar e apagar dados diretamente pela API com o token de um usuário comum, sem passar pela interface. Esses testes devem falhar no acesso indevido.

**Aplicação web**

- HTTPS obrigatório.
- Política de segurança de conteúdo (CSP) restritiva; proteção contra clickjacking; documentar limitações da hospedagem estática.
- Proteção contra XSS: nada de HTML vindo do usuário renderizado sem sanitização.
- Validação de todas as entradas no cliente e, obrigatoriamente, no banco.
- Importações de planilha e PDF tratadas como entrada não confiável: validação de tipo real, tamanho máximo, colunas e valores, com relatório de erros antes de gravar.
- Revisão com base no OWASP Top 10 ao final de cada fase.

**Autenticação e sessão**

- Limite de tentativas de login; senha forte; sessões com expiração.
- Verificação em duas etapas obrigatória para administrador e secretária; ações administrativas exigem sessão verificada.
- Usuário desativado perde acesso na hora, verificado no banco.

**Arquivos**

- Armazenamento privado; acesso só por links temporários de curta duração.
- O acesso ao arquivo segue a permissão do registro a que ele pertence.
- Nomes de arquivo gerados pelo sistema; verificação do tipo real do arquivo.
- Folhas de ponto visíveis apenas a quem tem permissão sobre a unidade correspondente.

**Código e segredos**

- Nenhuma senha, token ou chave no código nem no histórico do Git; .env fora do repositório; .env.example sem valores reais.
- Secret scanning e push protection ativados no GitHub; dependências verificadas automaticamente (Dependabot / npm audit).
- Dados de teste sempre fictícios; nunca dados reais em desenvolvimento.

**LGPD e dados pessoais**

- Coletar só o necessário. Saldos de férias, licenças, folgas e produtividade são dados pessoais: visíveis apenas ao próprio servidor, à chefia da unidade, à secretária e ao administrador.
- CPF e dados de contato de locadores mascarados por padrão; exibição completa só com permissão específica.
- Nenhum dado pessoal em logs de aplicação ou mensagens de erro.
- Banco hospedado preferencialmente na região de São Paulo.
- Documentar em docs/lgpd.md quais dados são tratados, para quê e quem acessa, para validação do encarregado (DPO) da Prefeitura.

**Operação**

- Ambientes separados: desenvolvimento, homologação e produção.
- Backup diário e teste documentado de restauração em homologação.
- Auditoria imutável, incluindo logins, exportações, mudanças de permissão e ações do administrador.
- Nenhum dado oficial real antes da validação institucional de segurança e LGPD.

## 6. Módulos

### 6.1 Painel inicial

Secretária vê o resumo geral; diretor, o da diretoria; coordenador, o da unidade; funcionário, só o próprio desempenho. Indicadores: demandas abertas e atrasadas por unidade, contratos perto do vencimento, faturas e aluguéis pendentes, férias do mês.

### 6.2 Demandas

Criadas e distribuídas por diretor ou coordenador, com um ou vários responsáveis. Funcionário pode sugerir; a sugestão só vale após aprovação da chefia da unidade. Campos: título, descrição, origem (processo físico, e-mail institucional, WhatsApp), responsáveis, prazo, prioridade, status, comentários e histórico. Prazos em dias úteis. Visualização em lista e kanban.

### 6.3 Calendário

Um calendário por unidade, mais o calendário geral da secretária. Compromissos e demandas podem ter participantes. Funcionário vê apenas o que o inclui.

### 6.4 Produtividade

Modelo baseado no sistema de produtividade dos fiscais da SEMFAZ. **Pendente: aguardando o material de referência.** Até lá, apenas métricas simples (concluídas, atrasadas, cumprimento de prazo).

### 6.5 Contratos de locação (ficha única)

Cada contrato é uma ficha que reúne tudo: número, locador, vigência, aditivos, valor mensal e anual do aluguel, fiscal do contrato, unidades consumidoras vinculadas (Iguá – água; Energisa e Cercos – energia), faturas e pagamentos mensais de aluguel, com visão do que foi pago e do que está pendente. Alertas de vencimento. PDFs do contrato e dos aditivos ficam anexados. Cadastro inicial (cerca de 60 contratos) por importação de planilha a partir de modelo Excel.

### 6.6 Faturas de água e energia

Lançamento manual ou por importação de planilha. Registro de pagamento sem necessidade de aprovação. Sem anexo de fatura ou comprovante.

### 6.7 Servidores, férias e licenças

Cadastro dos servidores (nome, matrícula, cargo, unidade), com importação por planilha. Saldos de férias, licenças-prêmio e folgas informados pelo RH. Funcionário pede férias; diretor ou coordenador aprova; escala editável. Se outro servidor da mesma unidade e mesmo cargo já tiver férias no período, a chefia recebe um aviso, mas a decisão é dela.

**Regras obrigatórias do cadastro de servidores (sem exceções):**

- A **matrícula funcional é obrigatória** em todo cadastro de servidor. Não é permitido salvar servidor sem matrícula.
- A matrícula é **única**: o banco deve impedir duas matrículas iguais (índice único), inclusive na importação por planilha.
- A matrícula é a **chave usada para separar as folhas de ponto**: cada página do PDF do RH é associada ao servidor pela matrícula e, por meio dele, à unidade.
- Campos obrigatórios do servidor: nome completo, matrícula, cargo, unidade e situação (ativo ou inativo). E-mail institucional é obrigatório apenas para quem terá login no sistema.
- A planilha de importação de servidores deve ter, no mínimo, as colunas: nome, matrícula, cargo, unidade, e-mail institucional, saldo de férias, saldo de licença-prêmio e saldo de folgas. Antes de gravar, o sistema mostra um relatório de erros (matrícula vazia, duplicada, unidade inexistente) e só importa após confirmação.
- Alterar a matrícula de um servidor já cadastrado é alteração de dado e passa pelo fluxo de aprovação.

### 6.8 Folhas de ponto

Upload do PDF mensal do RH (texto selecionável). O sistema lê a matrícula de cada página, cruza com o cadastro e gera um PDF por unidade, ordenado e pronto para impressão. Páginas com matrícula não encontrada são listadas como aviso, nunca descartadas.

### 6.9 Aprovações

Alteração de dados já cadastrados (ex.: contratos) e mudanças de estrutura (unidades, cargos, permissões) exigem aprovação da secretária ou do administrador; basta um deles. Ninguém aprova o próprio pedido.

### 6.10 Alertas e notificações

Internas no sistema, por e-mail e por notificação no celular pelo aplicativo instalável (6.22). Também geram aviso: menção com @ na conversa da demanda, pedido de atualização da chefia, feedback (aprovado, ajustar, refazer), início de substituição por férias, demanda de renovação de contrato e atraso na devolução das folhas de ponto. Exemplos: inclusão em demanda, prazo próximo, contrato vencendo, pedido de aprovação, aviso de férias.

### 6.11 Relatórios

Relatórios detalhados de cada módulo, exportáveis em PDF, Excel e CSV.

### 6.12 Auditoria

Registro de quem fez o quê e quando, com dados antes e depois, inclusive das ações do administrador. Registros não podem ser alterados nem apagados.

### 6.13 Feriados

Cadastro de feriados municipais, usado no cálculo de dias úteis.

### 6.14 Substituto durante férias e licenças

Ao aprovar férias, licença-prêmio ou folga, a chefia indica obrigatoriamente um substituto da mesma unidade. No primeiro dia útil do afastamento, as demandas abertas do servidor passam a ter o substituto como responsável adicional, sem remover o titular. O substituto e a chefia são notificados. No retorno, o titular volta a ser o responsável principal, e o substituto sai das demandas que não concluiu. Tudo fica no histórico da demanda.

### 6.15 Demandas recorrentes

Diretor e coordenador podem criar um modelo de demanda recorrente (mensal, trimestral, semestral ou anual), com título, descrição, unidade, responsáveis, checklist e prazo em dias úteis. Uma rotina agendada no banco cria cada ocorrência automaticamente, sem duplicar a mesma ocorrência. Se o responsável estiver afastado, aplica-se a regra do substituto. Editar o modelo vale só para as próximas ocorrências. Pausar ou encerrar o modelo exige permissão da chefia.

### 6.16 Checklist dentro da demanda

Cada demanda pode ter uma lista de etapas (itens com texto, responsável opcional e marcação de feito). O cartão e a ficha da demanda mostram o andamento (por exemplo, 3 de 5). Marcar ou desmarcar uma etapa fica no histórico. A demanda não é concluída automaticamente ao marcar todas as etapas: a conclusão continua sendo uma ação do responsável.

### 6.17 Renovação de contrato

Quando faltarem 90 dias para o fim da vigência efetiva (prazo configurável), o sistema cria automaticamente, uma única vez, uma demanda "Renovação do contrato nº X" para o fiscal do contrato e para quem tem a permissão de contratos. A demanda vem com checklist configurável de documentos (por exemplo: certidões do locador, laudo de avaliação, manifestação de interesse, parecer jurídico). A demanda fica ligada à ficha do contrato. Se um aditivo de prazo for aprovado, o sistema avisa que a renovação foi registrada.

### 6.18 Controle de entrega das folhas de ponto

Para cada mês e cada unidade, o sistema registra: data de envio da folha à unidade, quem recebeu, data de devolução assinada e quem devolveu. Situações: não enviada, enviada, devolvida. O painel e a tela de folhas de ponto mostram quais unidades ainda não devolveram. A chefia da unidade é notificada quando houver atraso na devolução (prazo configurável em dias úteis).

### 6.19 Busca geral

Um campo de busca no cabeçalho de todas as telas encontra contratos (número, locador, imóvel), servidores (nome, matrícula), demandas (título), unidades consumidoras (número da UC ou matrícula) e unidades administrativas. A busca respeita as permissões: cada usuário só vê nos resultados o que já pode ver no sistema. A pesquisa é feita no banco, ignora acentos e maiúsculas, e os resultados aparecem agrupados por tipo.

### 6.20 Anexos nas demandas

Toda demanda aceita anexos (PDF, imagens JPG/PNG, DOCX, XLSX e prints), enviados por qualquer responsável ou pela chefia. Os arquivos ficam em armazenamento privado, com acesso igual ao da demanda, e mostram quem enviou e quando. Anexo nunca é apagado fisicamente: substituir gera nova versão.

### 6.21 Conversa da demanda (chat interno com menções)

Cada demanda tem uma área de conversa, em formato de chat, visível para os responsáveis, para a chefia da unidade (coordenador e diretor) e para a Secretária.

- Mensagens em ordem de tempo, com autor, data e hora. Mensagens não são apagadas; edição fica marcada como editada.
- **Menção com @**: ao escrever @ e o nome de um colega, ele é notificado e passa a ver a conversa daquela demanda.
- **Pedido de atualização**: Secretária, diretor ou coordenador podem usar o botão "Pedir atualização", que notifica os responsáveis para relatarem o andamento.
- **Feedback da chefia**: a chefia pode marcar uma mensagem como "Aprovado", "Ajustar" ou "Refazer", com comentário. A marcação aparece em destaque na conversa e no histórico.
- Mensagens podem levar anexos (regra da 6.20).
- A conversa fica na ficha da demanda, ao lado do checklist e do histórico, seguindo o padrão visual dos protótipos.

### 6.22 Aplicativo no celular desde a primeira versão

O sistema deve ser um PWA (aplicativo web instalável): pode ser instalado na tela inicial do celular e do computador, abre em tela cheia, tem ícone com o logo Gestão SEMFAZ e recebe notificações no celular. A interface deve ser pensada para o celular desde o início (menu em gaveta, tabelas em cartões, botões com no mínimo 44 px). Nenhum dado sigiloso fica guardado no aparelho além da sessão. A publicação nas lojas de aplicativos continua como etapa futura.

## 7. Tecnologia e portabilidade

Frontend estático (Next.js, React, TypeScript) hospedado inicialmente no GitHub Pages; backend no Supabase (PostgreSQL, Auth, Storage). Regras de negócio e permissões devem ficar no próprio PostgreSQL (constraints, RLS, funções), evitando dependência de recursos exclusivos do Supabase, para permitir migrar no futuro para outra hospedagem ou para a infraestrutura da Prefeitura sem reescrever o sistema. O frontend é um PWA instalável desde a primeira versão (ver 6.22); publicação nas lojas é etapa futura. Nenhum segredo no código.

**Repositório:** nesta fase o repositório no GitHub será público e o site publicado pelo GitHub Pages, pois serão usados apenas dados fictícios e nenhum segredo fica no código. **Esta decisão deve ser revista antes da entrada de qualquer dado real**: avaliar tornar o repositório privado (GitHub pago, ou publicação via Cloudflare Pages / Netlify) e registrar a decisão em docs/PROJECT\_STATUS.md.

## 7.1 Identidade visual

O nome do sistema é **Gestão SEMFAZ**, com a assinatura "Prefeitura de Lagarto/SE". Não usar o brasão nem a logomarca oficial da Prefeitura.

- **Logo:** quadrado de cantos arredondados em azul-claro com um "G" e duas barras subindo, desenhado em SVG. Fica no topo do menu lateral.
- **Tema Índigo** (definir como tokens de cor, nunca valores soltos nos componentes):

| Token | Cor | Uso |
| --- | --- | --- |
| menu | #18215A | Fundo do menu lateral |
| texto-forte | #1A2660 | Títulos e textos de destaque |
| primária | #3A57E8 | Botões principais, item ativo do menu, links |
| logo | #8FD3FF | Fundo do logo |
| fundo | #F4F6F9 | Fundo das telas; cartões em branco |
| positivo | #1E7B4F | Pago, em dia, concluído |
| alerta | #C77700 | Pendente, prazo próximo |
| crítico | #B3261E | Vencido, atrasado, conflito |

- **Fonte:** IBM Plex Sans.
- **Menu lateral com ícones** de traço simples em todos os itens (estilo Lucide). Itens de fases futuras aparecem desabilitados, com a marca "em breve".
- **Referência visual:** os protótipos em [Gestão SEMFAZ – Protótipos de telas](https://claude.ai/artifact/RYSeq69SAEzTTTA2XfaBaQ) (lista completa na seção 7.2).
- Contraste mínimo WCAG AA, foco visível e navegação por teclado. Responsivo: o menu vira gaveta no celular.

## 7.2 Telas obrigatórias (seguir os protótipos)

As telas do sistema devem reproduzir **fielmente** os protótipos em [Gestão SEMFAZ – Protótipos de telas](https://claude.ai/artifact/RYSeq69SAEzTTTA2XfaBaQ): mesma disposição, mesmos blocos, mesmos campos, mesmos botões, mesmos textos de aviso, mesmo menu lateral com ícones, mesmo logo e tema Índigo. Os dados dos protótipos são fictícios: no sistema, tudo vem do banco. Não simplificar, não omitir blocos e não inventar layout diferente. Qualquer desvio necessário deve ser registrado em docs/PROJECT\_STATUS.md e aprovado antes.

1. Painel da Secretária: seguir a prancha "1 · Painel da Secretária" (versão atual; a versão antiga, com tabela, foi descartada). Atalhos clicáveis no topo; mapa de cartões das unidades agrupadas por DAT, DEFC e Ligadas ao Gabinete, com borda verde, laranja ou vermelha, número de atrasadas e barra de andamento; coluna direita com aprovações pendentes, contratos perto do vencimento, próximos compromissos e ausências com substituto; busca geral no cabeçalho.
2. Ficha do contrato (contrato, aditivos, aluguéis mês a mês, unidades consumidoras, documentos e histórico).
3. Calendário por unidade (um calendário por unidade + geral do Gabinete; mês, semana, dia e lista).
4. Escala de férias (grade por mês, saldos do RH, aviso de mesmo cargo no mesmo período).
5. Painel do funcionário (só as próprias demandas, agenda, produtividade e saldos).
6. Folhas de ponto (envio do PDF do RH, separação por matrícula e unidade, pendências, baixar e imprimir).
7. Demandas em quadro (colunas por status, origem, urgência, responsáveis, prazo em dias úteis, sugestões pendentes).
8. Unidades consumidoras e faturas (Energisa, Iguá e Cercos ligadas aos contratos; importação por planilha).
9. Central de aprovações (antes e depois, justificativa, anexo, aprovar ou recusar com comentário).
10. Relatórios (por assunto, com filtros e exportação em PDF, Excel e CSV).
11. Unidades e usuários (árvore da estrutura, servidores com matrícula, cargo, perfil, acessos extras e situação).
12. Produtividade da equipe (por unidade e por servidor; critérios finais pendentes do modelo dos fiscais).

**Telas sem protótipo:** as funcionalidades sem protótipo próprio (substituto nas férias, demandas recorrentes, checklist, renovação de contrato, controle de entrega das folhas de ponto, busca geral e qualquer tela futura) devem seguir exatamente o mesmo padrão visual dos protótipos: menu lateral com ícones, cabeçalho com trilha de navegação, cartões brancos, tabelas, selos de situação, botões, tipografia e tema Índigo. Sempre que possível, devem ficar dentro das telas que já existem (por exemplo, o checklist na ficha da demanda e o controle de entrega na tela de folhas de ponto).

**Decisões confirmadas pela SEMFAZ:** demanda com vários responsáveis conta para cada um; tempo médio de execução vai do início à conclusão, em dias úteis; criar, mover ou renomear unidades passa por aprovação.

## 8. Módulos futuros (não implementar agora)

- Calendário de obrigações fiscais (RREO, RGF, DCA, EFD-Reinf, DCTFWeb) com recorrência automática, responsáveis e comprovantes.
- Acompanhamento do plano de transição ISS → IBS.
- Controle de consultas à PGM e atendimentos do PAV.
- Alerta de reajuste do aluguel na data-base de cada contrato (opção aprovada para fase futura).

## 9. Pendências

- Regras de produtividade (aguardando material dos fiscais).
- Lista oficial de cargos.
- Modelo das planilhas de importação.
- Permissões padrão por módulo e por perfil (a SEMFAZ vai enviar a definição oficial; ver seção 4).
- Planilha do RH com saldos de férias, licenças-prêmio e folgas (já solicitada; o modelo de importação deve seguir as colunas dela).

## 10. Fases sugeridas

1. Fundação: estrutura organizacional, usuários, perfis, pacote padrão de módulos e módulos extras, autenticação, segurança, auditoria, aprovações, feriados, busca geral, layout com tema Índigo e aplicativo instalável (PWA).
2. Servidores (matrícula obrigatória e única, importação por planilha), férias, licenças e folgas, substituto durante afastamentos, folhas de ponto e controle de entrega.
3. Demandas (sugestões, checklist, recorrentes, anexos, conversa com menções e feedback), calendário e painéis.
4. Contratos (ficha única, importação por planilha, renovação), unidades consumidoras, faturas e aluguéis.
5. Produtividade.
6. Relatórios e exportações.
7. Testes finais e implantação.
