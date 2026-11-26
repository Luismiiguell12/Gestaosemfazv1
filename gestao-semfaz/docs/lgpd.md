# Gestão SEMFAZ — Dados pessoais tratados (rascunho para o encarregado/DPO)

Situação: **rascunho da Fase 1**. Atualizar a cada fase. Nenhum dado real antes da validação institucional.

## Fase 1

| Dado | Titular | Finalidade | Base legal (a validar pelo DPO) | Quem acessa | Onde |
|---|---|---|---|---|---|
| Nome completo | Servidor | Identificação no sistema, lotação, responsáveis | Execução de políticas públicas / obrigação legal (art. 7º, II e III; art. 23) | O próprio; chefia da unidade/diretoria (escopo); Secretária; Administrador | `servidores` |
| Matrícula funcional | Servidor | Chave única do servidor; separação das folhas de ponto (Fase 2) | idem | idem | `servidores` |
| Cargo e unidade | Servidor | Estrutura e permissões | idem | idem | `servidores` |
| E-mail institucional | Servidor com login | Login, convite, recuperação de senha, notificações | idem | idem; Supabase Auth | `servidores`, `auth.users` |
| Perfil, situação do acesso, módulos extras | Usuário | Controle de acesso | idem | O próprio; chefia (escopo); Secretária; Administrador | `usuarios`, `usuario_modulos_extras`, `usuario_unidades_extras` |
| Fator TOTP (segredo do autenticador) | Usuário | Verificação em duas etapas | Segurança (art. 46) | Ninguém pelo sistema (guardado pelo Supabase Auth) | `auth.mfa_factors` |
| Registros de auditoria (quem, quando, antes/depois, logins) | Usuários | Rastreabilidade e segurança | Art. 46 e 37 | Secretária e Administrador | `auditoria` (imutável) |
| Pedidos de aprovação e anexos | Solicitante / servidor afetado | Controle de alterações | Execução de políticas públicas | Solicitante; Secretária; Administrador | `solicitacoes`, Storage privado |

## Fase 2

| Dado | Titular | Finalidade | Quem acessa | Onde |
|---|---|---|---|---|
| Saldos de férias, licença-prêmio e folgas (informados pelo RH) | Servidor | Planejar afastamentos | O próprio; chefia da unidade; secretária; administrador | `saldos_servidor` |
| Férias, licenças e folgas (períodos, situação, substituto, observação) | Servidor | Escala e substituição | O próprio; o substituto; chefia da unidade; secretária; administrador | `afastamentos` |
| Folhas de ponto (PDF do RH e PDFs por unidade) | Servidor | Distribuir e controlar a entrega das folhas | Secretária e administrador (todas); chefia (só a própria unidade) | bucket privado `folhas-ponto`, `folhas_*` |
| Registro de entrega (quem recebeu/devolveu, datas) | Servidor | Controle da devolução assinada | Chefia da unidade; secretária; administrador | `folhas_entregas` |

## Próximas fases (previsto pelo prompt)

- Saldos de férias, licenças-prêmio, folgas e produtividade: **dados pessoais**, visíveis só ao próprio servidor, à chefia da unidade, à Secretária e ao Administrador.
- Folhas de ponto: visíveis só a quem tem permissão sobre a unidade.
- Locadores (CPF e contato): mascarados por padrão; exibição completa só com permissão específica.

## Medidas

- RLS em todas as tabelas; escopo por perfil e unidade; testes automáticos de acesso indevido.
- Nada de dados pessoais em logs de aplicação ou mensagens de erro.
- Nenhum dado sigiloso guardado no aparelho além da sessão (service worker não guarda respostas da API).
- Banco hospedado preferencialmente na região de São Paulo.
- Retenção: a definir com o DPO (auditoria e histórico de pedidos).
