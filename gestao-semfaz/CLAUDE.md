# Gestão SEMFAZ — instruções para o Claude Code

1. A especificação completa do sistema está em `docs/PROMPT.md`. Leia o arquivo inteiro antes de qualquer ação e siga-o à risca. Em caso de conflito, `docs/PROMPT.md` prevalece.
2. Os protótipos das telas estão em `docs/prototipos/*.dc.html`. Eles são a referência visual obrigatória da seção 7.2 do prompt:
   - Leia o HTML/CSS de cada arquivo para reproduzir layout, blocos, campos, botões, textos de aviso, menu lateral com ícones, logo e cores.
   - Os trechos `{{ ... }}`, `<sc-for>` e `<sc-if>` são marcações do editor de protótipos. Os dados de exemplo ficam na função `renderVals()` no fim de cada arquivo. São dados fictícios: no sistema, tudo vem do banco.
   - O tema padrão é `indigo` (objeto `THEMES` em cada arquivo). Ignore `support.js` e o tema "marinho".
   - Mapa: Main = Painel da Secretária; Contrato = Ficha do contrato; Calendario; Ferias = Escala de férias; Funcionario = Painel do funcionário; FolhasPonto; Demandas; UnidadesConsumidoras; Aprovacoes; Relatorios; Usuarios = Unidades e usuários; Produtividade; Cores = referência da paleta.
3. Trabalhe por fases (seção 10 do prompt). Faça uma fase por vez. Ao fim de cada uma, pare, apresente o relatório e aguarde a minha validação.
4. Mantenha `docs/PROJECT_STATUS.md` atualizado e leia-o no início de cada nova sessão.
5. Itens pendentes (seção 9 do prompt): não implemente regras definitivas para eles. Crie a estrutura configurável e registre o item como pendente.
6. Repositório público: nunca faça commit de `.env`, senhas, chaves ou dados reais.
