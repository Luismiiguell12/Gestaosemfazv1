-- Usuários FICTÍCIOS de teste (um por perfil). IDs fixos.
insert into auth.users (id, email)
select v.id::uuid, s.email_institucional from (values
  ('00000000-0000-0000-0000-00000000a001', '000002'),
  ('00000000-0000-0000-0000-00000000a002', '000001'),
  ('00000000-0000-0000-0000-00000000a003', '000010'),
  ('00000000-0000-0000-0000-00000000a004', '000011'),
  ('00000000-0000-0000-0000-00000000a005', '000106'),
  ('00000000-0000-0000-0000-00000000a006', '000206'),
  ('00000000-0000-0000-0000-00000000a007', '000101'),
  ('00000000-0000-0000-0000-00000000a008', '000102'),
  ('00000000-0000-0000-0000-00000000a009', '000201')
) v(id, mat) join public.servidores s on s.matricula = v.mat;

insert into public.usuarios (id, servidor_id, perfil)
select au.id, s.id, v.perfil::public.perfil_usuario
  from (values
    ('000002', 'administrador'), ('000001', 'secretaria'), ('000010', 'diretor'), ('000011', 'diretor'),
    ('000106', 'coordenador'), ('000206', 'coordenador'), ('000101', 'funcionario'), ('000102', 'funcionario'),
    ('000201', 'funcionario')
  ) v(mat, perfil)
  join public.servidores s on s.matricula = v.mat
  join auth.users au on lower(au.email) = s.email_institucional;
