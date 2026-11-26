-- Dados FICTÍCIOS de desenvolvimento. Nunca usar dados reais aqui.
-- Estrutura conforme minuta da reforma (prompt seção 3). Nomes completos das coordenadorias: pendentes.

with gab as (
  insert into public.unidades (sigla, nome, tipo, ordem) values ('Gabinete', 'Gabinete do Secretário', 'gabinete', 0) returning id
), ligadas as (
  insert into public.unidades (sigla, nome, tipo, unidade_pai_id, ordem)
  select v.sigla, v.nome, v.tipo::public.tipo_unidade, gab.id, v.ordem from gab, (values
    ('ASPLAN', 'ASPLAN', 'assessoria', 1),
    ('ASTIN', 'ASTIN', 'assessoria', 2),
    ('Jurídica', 'Assessoria Jurídica', 'assessoria', 3),
    ('PAV', 'Coordenadoria do PAV e da Ordem Cronológica', 'coordenadoria', 4),
    ('DAT', 'Diretoria de Administração Tributária', 'diretoria', 5),
    ('DEFC', 'Diretoria de Execução Financeira e Contabilidade', 'diretoria', 6)
  ) v(sigla, nome, tipo, ordem) returning id, sigla
)
insert into public.unidades (sigla, nome, tipo, unidade_pai_id, ordem)
select v.sigla, v.nome, 'coordenadoria', l.id, v.ordem from ligadas l join (values
  ('DAT', 'COACAM', 'COACAM', 1),
  ('DAT', 'COFIT', 'Coordenadoria de Fiscalização e Tributos', 2),
  ('DAT', 'COAC', 'COAC', 3),
  ('DAT', 'COCMI', 'COCMI', 4),
  ('DEFC', 'CONTA', 'CONTA', 1),
  ('DEFC', 'COEF', 'COEF', 2)
) v(pai, sigla, nome, ordem) on v.pai = l.sigla;

-- cargos de EXEMPLO (lista oficial pendente)
insert into public.cargos (nome) values
  ('Secretário(a)'), ('Diretor(a)'), ('Coordenador(a)'), ('Assessor(a)'),
  ('Auditor Fiscal'), ('Agente Administrativo'), ('Analista de Sistemas');

insert into public.servidores (nome_completo, matricula, cargo_id, unidade_id, email_institucional)
select v.nome, v.mat, c.id, u.id, v.email
  from (values
    ('Secretária Exemplo', '000001', 'Secretário(a)', 'Gabinete', 'secretaria@exemplo.gov.br'),
    ('Administrador Exemplo', '000002', 'Analista de Sistemas', 'ASTIN', 'admin@exemplo.gov.br'),
    ('Diretor da DAT', '000010', 'Diretor(a)', 'DAT', 'diretor.dat@exemplo.gov.br'),
    ('Diretor da DEFC', '000011', 'Diretor(a)', 'DEFC', 'diretor.defc@exemplo.gov.br'),
    ('Coordenador da COFIT', '000106', 'Coordenador(a)', 'COFIT', 'coordenador.cofit@exemplo.gov.br'),
    ('Coordenador da CONTA', '000206', 'Coordenador(a)', 'CONTA', 'coordenador.conta@exemplo.gov.br'),
    ('Servidor A', '000101', 'Auditor Fiscal', 'COFIT', 'servidor.a@exemplo.gov.br'),
    ('Servidor E', '000102', 'Auditor Fiscal', 'COFIT', 'servidor.e@exemplo.gov.br'),
    ('Servidor F', '000103', 'Auditor Fiscal', 'COFIT', null),
    ('Servidor G', '000104', 'Agente Administrativo', 'COFIT', null),
    ('Servidor H', '000105', 'Agente Administrativo', 'COFIT', null),
    ('Servidor B', '000201', 'Agente Administrativo', 'CONTA', 'servidor.b@exemplo.gov.br'),
    ('Servidor I', '000301', 'Agente Administrativo', 'COAC', null)
  ) v(nome, mat, cargo, sigla, email)
  join public.cargos c on c.nome = v.cargo
  join public.unidades u on u.sigla = v.sigla;

-- feriados nacionais (públicos). Municipais de Lagarto e estaduais: cadastrar pela tela (pendente lista oficial).
insert into public.feriados (data, descricao, abrangencia) values
  ('2026-01-01', 'Confraternização Universal', 'nacional'),
  ('2026-04-03', 'Sexta-feira Santa', 'nacional'),
  ('2026-04-21', 'Tiradentes', 'nacional'),
  ('2026-05-01', 'Dia do Trabalho', 'nacional'),
  ('2026-09-07', 'Independência do Brasil', 'nacional'),
  ('2026-10-12', 'Nossa Senhora Aparecida', 'nacional'),
  ('2026-11-02', 'Finados', 'nacional'),
  ('2026-11-15', 'Proclamação da República', 'nacional'),
  ('2026-11-20', 'Dia Nacional de Zumbi e da Consciência Negra', 'nacional'),
  ('2026-12-25', 'Natal', 'nacional'),
  ('2027-01-01', 'Confraternização Universal', 'nacional'),
  ('2027-03-26', 'Sexta-feira Santa', 'nacional'),
  ('2027-04-21', 'Tiradentes', 'nacional'),
  ('2027-05-01', 'Dia do Trabalho', 'nacional'),
  ('2027-09-07', 'Independência do Brasil', 'nacional'),
  ('2027-10-12', 'Nossa Senhora Aparecida', 'nacional'),
  ('2027-11-02', 'Finados', 'nacional'),
  ('2027-11-15', 'Proclamação da República', 'nacional'),
  ('2027-11-20', 'Dia Nacional de Zumbi e da Consciência Negra', 'nacional'),
  ('2027-12-25', 'Natal', 'nacional');
