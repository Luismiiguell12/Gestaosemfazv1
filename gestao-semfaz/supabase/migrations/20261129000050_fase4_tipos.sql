-- Fase 4 · tipos (valores novos de enum precisam de migration própria antes de serem usados)
alter type public.tipo_solicitacao add value if not exists 'contrato_alterar';
alter type public.tipo_solicitacao add value if not exists 'contrato_aditivo';

create type public.tipo_pessoa as enum ('PF', 'PJ');
create type public.fornecedor_uc as enum ('energisa', 'igua', 'cercos');

-- permissão específica para ver CPF/CNPJ e contato completos do locador (LGPD).
-- Não entra em nenhum pacote padrão: só como módulo extra concedido pela Secretária/Admin.
insert into public.modulos (codigo, nome, rota, icone, ordem, status, fase, no_menu)
values ('locadores_dados', 'Dados completos de locadores', '/contratos', 'contratos', 140, 'ativo', 4, false)
on conflict (codigo) do nothing;
