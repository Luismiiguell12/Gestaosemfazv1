'use client';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useMemo, useState } from 'react';
import { AppShell, Cabecalho } from '@/components/layout/AppShell';
import { ImportarPlanilha } from '@/components/ImportarPlanilha';
import { SolicitarDialogo, type CampoForm } from '@/components/SolicitarDialogo';
import { COLUNAS_SERVIDORES } from '@/lib/planilha';
import { Aviso, Campo, Dialogo, EstadoVazio, Selo } from '@/components/ui';
import { mensagemErro } from '@/lib/erros';
import { arvore, caminho, type Unidade } from '@/lib/estrutura';
import { ehChefia, ehGestorGeral, temModulo, useSessao } from '@/lib/sessao';
import type { TipoSolicitacao } from '@/lib/solicitacoes';
import { supabase } from '@/lib/supabase';
import { useConsulta } from '@/lib/useConsulta';
import { PERFIS, primeiroErro, ROTULO_PERFIL, ROTULO_VINCULO, servidorNovo, TIPOS_VINCULO, type Perfil } from '@/lib/validacao';

interface Servidor { id: string; nome_completo: string; matricula: string; cargo_id: string; unidade_id: string; situacao: 'ativo' | 'inativo'; email_institucional: string | null; tipo_vinculo: 'efetivo' | 'comissionado' | 'temporario' | null; exerce_comissao: boolean; elegivel_adicional: boolean }
interface Usuario { id: string; servidor_id: string; perfil: Perfil; ativo: boolean }
interface Extra { usuario_id: string; modulo_codigo: string }
interface UnExtra { usuario_id: string; unidade_id: string }
interface Modulo { codigo: string; nome: string }
interface Pacote { perfil: Perfil; modulo_codigo: string }
interface Cargo { id: string; nome: string; ativo: boolean }

const PERFIS_TXT = [
  { t: 'Secretária', d: 'Vê e edita tudo; aprova alterações.' },
  { t: 'Diretor', d: 'A diretoria e todas as coordenadorias dela.' },
  { t: 'Coordenador', d: 'Só a própria unidade; cria demandas.' },
  { t: 'Funcionário', d: 'Só as próprias demandas, agenda e produtividade.' },
  { t: 'Administrador do sistema', d: 'Acesso total para manutenção; tudo auditado.' },
];

export default function UsuariosPage() {
  return <AppShell modulo="usuarios"><Suspense><Tela /></Suspense></AppShell>;
}

type Pedido = { tipo: TipoSolicitacao; titulo: string; alvo: string | null; campos: CampoForm[]; aviso?: string };

function Tela() {
  const { info } = useSessao();
  const geral = ehGestorGeral(info);
  const params = useSearchParams();
  const router = useRouter();
  const [versao, setVersao] = useState(0);
  const recarregar = () => setVersao((v) => v + 1);

  const q = <T,>(fn: () => PromiseLike<{ data: T | null; error: unknown }>) => useConsulta(async () => fn(), [versao]);
  const unidades = q(() => supabase.from('unidades').select('id,sigla,nome,tipo,unidade_pai_id,ordem,ativa'));
  const escopo = q(() => supabase.rpc('minhas_unidades_escopo'));
  const servidores = q(() => supabase.from('servidores').select('id,nome_completo,matricula,cargo_id,unidade_id,situacao,email_institucional,tipo_vinculo,exerce_comissao,elegivel_adicional').order('nome_completo'));
  const usuarios = q(() => supabase.from('usuarios').select('id,servidor_id,perfil,ativo'));
  const extras = q(() => supabase.from('usuario_modulos_extras').select('usuario_id,modulo_codigo'));
  const unExtras = q(() => supabase.from('usuario_unidades_extras').select('usuario_id,unidade_id'));
  const modulos = q(() => supabase.from('modulos').select('codigo,nome').order('ordem'));
  const pacotes = q(() => supabase.from('pacotes_padrao').select('perfil,modulo_codigo'));
  const cargos = q(() => supabase.from('cargos').select('id,nome,ativo').order('nome'));

  const U = (unidades.dados as Unidade[] | null) ?? [];
  const S = (servidores.dados as Servidor[] | null) ?? [];
  const US = (usuarios.dados as Usuario[] | null) ?? [];
  const M = (modulos.dados as Modulo[] | null) ?? [];
  const C = (cargos.dados as Cargo[] | null) ?? [];
  const esc = useMemo(() => new Set(((escopo.dados as string[] | null) ?? []).map(String)), [escopo.dados]);
  const nomeModulo = (c: string) => M.find((m) => m.codigo === c)?.nome ?? c;
  const sigla = (id: string) => U.find((u) => u.id === id)?.sigla ?? '—';

  // árvore: escopo + ancestrais
  const visiveis = useMemo(() => {
    if (geral) return new Set(U.map((u) => u.id));
    const s = new Set<string>();
    for (const id of esc) caminho(U, id).forEach((u) => s.add(u.id));
    return s;
  }, [geral, U, esc]);
  const linhas = arvore(U).filter((l) => visiveis.has(l.u.id));

  const servidorParam = params.get('servidor');
  const unidadeSel = params.get('unidade') ?? S.find((s) => s.id === servidorParam)?.unidade_id ?? info?.unidade_id ?? linhas[0]?.u.id;
  const unidade = U.find((u) => u.id === unidadeSel);
  const daUnidade = S.filter((s) => s.unidade_id === unidadeSel);
  const [detalhe, setDetalhe] = useState<string | null>(null);
  const servidorDetalhe = S.find((s) => s.id === (detalhe ?? servidorParam));
  const [pedido, setPedido] = useState<Pedido | null>(null);
  const [novoServidor, setNovoServidor] = useState(false);
  const [convite, setConvite] = useState(false);
  const [importar, setImportar] = useState(false);

  const podePedirServidor = geral || (ehChefia(info) && temModulo(info, 'usuarios') && esc.has(unidadeSel ?? ''));
  const opUnidades = U.filter((u) => geral || esc.has(u.id)).map((u) => ({ valor: u.id, rotulo: u.sigla }));
  const opCargos = C.filter((c) => c.ativo).map((c) => ({ valor: c.id, rotulo: c.nome }));

  const pedirNovaUnidade = () => setPedido({
    tipo: 'unidade_criar', titulo: 'Nova unidade', alvo: null, aviso: 'Criar, mover ou renomear unidades passa por aprovação.',
    campos: [
      { chave: 'sigla', rotulo: 'Sigla', max: 40 }, { chave: 'nome', rotulo: 'Nome', max: 200 },
      { chave: 'tipo', rotulo: 'Tipo', tipo: 'select', opcoes: [{ valor: 'coordenadoria', rotulo: 'Coordenadoria' }, { valor: 'assessoria', rotulo: 'Assessoria' }, { valor: 'diretoria', rotulo: 'Diretoria' }] },
      { chave: 'unidade_pai_id', rotulo: 'Ligada a', tipo: 'select', opcoes: U.filter((u) => u.tipo !== 'coordenadoria' && u.tipo !== 'assessoria' && (geral || esc.has(u.id))).map((u) => ({ valor: u.id, rotulo: u.sigla })) },
    ],
  });
  const pedirAlterarUnidade = (u: Unidade) => setPedido({
    tipo: 'unidade_alterar', titulo: `Alterar unidade ${u.sigla}`, alvo: u.id, aviso: 'Criar, mover ou renomear unidades passa por aprovação.',
    campos: [
      { chave: 'sigla', rotulo: 'Sigla', inicial: u.sigla, max: 40 }, { chave: 'nome', rotulo: 'Nome', inicial: u.nome, max: 200 },
      ...(u.unidade_pai_id ? [{ chave: 'unidade_pai_id', rotulo: 'Ligada a', tipo: 'select' as const, inicial: u.unidade_pai_id, opcoes: U.filter((x) => x.id !== u.id && x.tipo !== 'coordenadoria' && x.tipo !== 'assessoria').map((x) => ({ valor: x.id, rotulo: x.sigla })) }] : []),
      { chave: 'ativa', rotulo: 'Situação', tipo: 'select', inicial: String(u.ativa), opcoes: [{ valor: 'true', rotulo: 'Ativa' }, { valor: 'false', rotulo: 'Inativa' }] },
    ],
  });

  return (
    <>
      <Cabecalho
        trilha={[{ rotulo: 'Início', href: '/' }, { rotulo: 'Unidades e usuários' }]}
        titulo="Unidades e usuários"
        acoes={<>
          {geral && <button type="button" className="botao" onClick={() => setImportar(true)}>Importar servidores (planilha)</button>}
          {geral && <button type="button" className="botao botao-primario" onClick={() => setConvite(true)}>+ Convidar usuário</button>}
        </>}
      />
      {servidores.erro && <Aviso tom="critico">{servidores.erro}</Aviso>}

      <div className="linha">
        <section aria-label="Estrutura da SEMFAZ" className="cartao col-estreita" style={{ padding: '16px 14px' }}>
          <div className="cartao-topo" style={{ padding: '0 6px 8px' }}>
            <h2 style={{ fontSize: 16 }}>Estrutura</h2>
            {(geral || info?.perfil === 'diretor') && <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-primaria)', cursor: 'pointer' }} onClick={pedirNovaUnidade}>+ Unidade</button>}
          </div>
          {linhas.map(({ u, nivel }) => (
            <button key={u.id} type="button" className="arvore-item" aria-current={u.id === unidadeSel}
              style={{ paddingLeft: 8 + nivel * 18, fontWeight: nivel < 2 ? 600 : 400, opacity: u.ativa ? 1 : 0.6 }}
              onClick={() => router.replace(`/usuarios?unidade=${u.id}`)}>
              <span>{u.tipo === 'gabinete' ? u.nome : u.sigla}{!u.ativa && ' (inativa)'}</span><span>{S.filter((s) => s.unidade_id === u.id).length}</span>
            </button>
          ))}
          <p className="nota" style={{ margin: '10px 6px 0' }}>Criar, mover ou renomear unidades passa por aprovação.</p>
        </section>

        <div className="col-principal" style={{ gap: 20 }}>
          <section className="cartao">
            <div className="cartao-topo">
              <h2>{unidade ? `${unidade.tipo === 'gabinete' ? 'Gabinete' : unidade.sigla} · ${daUnidade.length} servidores` : 'Selecione uma unidade'}</h2>
              <span style={{ fontSize: 13, color: 'var(--cor-texto-suave)' }}>{caminho(U, unidadeSel).filter((u) => u.tipo !== 'gabinete').map((u) => u.sigla).slice(0, -1).concat(unidade && unidade.tipo !== 'gabinete' ? [unidade.nome] : []).join(' › ')}</span>
            </div>
            <div className="acoes" style={{ marginTop: 6 }}>
              {geral && unidade && <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-primaria)', cursor: 'pointer', padding: 0 }} onClick={() => setNovoServidor(true)}>+ Servidor</button>}
              {unidade && (geral || (info?.perfil === 'diretor' && esc.has(unidade.id))) && <button type="button" className="link-acao" style={{ background: 'none', border: 0, color: 'var(--cor-primaria)', cursor: 'pointer', padding: 0 }} onClick={() => pedirAlterarUnidade(unidade)}>Solicitar alteração da unidade</button>}
            </div>
            <div className="tabela-rolagem">
              <table className="tabela tabela-cartoes" style={{ minWidth: 0 }}>
                <thead><tr><th>Servidor</th><th>Matrícula</th><th>Cargo</th><th>Perfil no sistema</th><th>Acessos extras</th><th>Situação</th></tr></thead>
                <tbody>
                  {daUnidade.map((s) => {
                    const us = US.find((u) => u.servidor_id === s.id);
                    const ex = [
                      ...((extras.dados as Extra[] | null) ?? []).filter((e) => e.usuario_id === us?.id).map((e) => nomeModulo(e.modulo_codigo)),
                      ...((unExtras.dados as UnExtra[] | null) ?? []).filter((e) => e.usuario_id === us?.id).map((e) => `Unidade ${sigla(e.unidade_id)}`),
                    ];
                    const sit = s.situacao === 'inativo' ? ['Inativo', 'neutro'] : us && !us.ativo ? ['Acesso desativado', 'critico'] : ['Ativo', 'positivo'];
                    return (
                      <tr key={s.id} className="clicavel" tabIndex={0} aria-selected={servidorDetalhe?.id === s.id}
                        onClick={() => setDetalhe(s.id)} onKeyDown={(e) => (e.key === 'Enter' || e.key === ' ') && setDetalhe(s.id)}>
                        <td data-rotulo="Servidor"><strong>{s.nome_completo}</strong><br /><span className="texto-suave">{s.email_institucional ?? 'sem e-mail institucional'}</span></td>
                        <td data-rotulo="Matrícula">{s.matricula}</td>
                        <td data-rotulo="Cargo">{C.find((c) => c.id === s.cargo_id)?.nome ?? '—'}</td>
                        <td data-rotulo="Perfil">{us ? ROTULO_PERFIL[us.perfil] : 'Sem acesso'}</td>
                        <td data-rotulo="Acessos extras">{ex.length ? ex.join(', ') : '—'}</td>
                        <td data-rotulo="Situação"><Selo tom={sit[1] as 'positivo'}>{sit[0]}</Selo></td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
              {!servidores.carregando && unidade && daUnidade.length === 0 && <EstadoVazio>Nenhum servidor visível nesta unidade.</EstadoVazio>}
            </div>
          </section>

          <section className="cartao">
            <h2 style={{ marginBottom: 10 }}>Perfis do sistema</h2>
            <div className="grade-perfis">
              {PERFIS_TXT.map((r) => <div key={r.t} className="perfil-cartao"><strong>{r.t}</strong>{r.d}</div>)}
            </div>
            <p className="nota" style={{ marginTop: 10 }}>Módulos extras (ex.: &quot;Contratos de locação&quot;): concedidos e retirados pela Secretária ou pelo Administrador, a qualquer servidor, de qualquer unidade, sem mudar o perfil. Pacote padrão por perfil provisório, aguardando a definição oficial da SEMFAZ.</p>
          </section>
        </div>
      </div>
      <p className="nota">A matrícula é obrigatória e única: é por ela que o sistema separa as folhas de ponto.</p>

      {servidorDetalhe && (
        <DetalheServidor
          s={servidorDetalhe} us={US.find((u) => u.servidor_id === servidorDetalhe.id)} geral={geral} podePedir={podePedirServidor}
          meuId={info?.usuario_id} modulos={M} pacotes={(pacotes.dados as Pacote[] | null) ?? []}
          extras={((extras.dados as Extra[] | null) ?? [])} unExtras={((unExtras.dados as UnExtra[] | null) ?? [])}
          sigla={sigla} cargo={C.find((c) => c.id === servidorDetalhe.cargo_id)?.nome ?? '—'}
          fechar={() => { setDetalhe(null); if (servidorParam) router.replace(`/usuarios?unidade=${servidorDetalhe.unidade_id}`); }}
          aoMudar={recarregar}
          pedir={(p) => { setDetalhe(null); setPedido(p); }}
          opUnidades={opUnidades} opCargos={opCargos} todasUnidades={U.map((u) => ({ valor: u.id, rotulo: u.sigla }))}
          perfilAtual={info?.perfil}
        />
      )}
      {pedido && <SolicitarDialogo aberto fechar={() => setPedido(null)} titulo={pedido.titulo} tipo={pedido.tipo} alvoId={pedido.alvo} campos={pedido.campos} aviso={pedido.aviso} />}
      {novoServidor && <NovoServidor fechar={() => setNovoServidor(false)} unidadeId={unidadeSel!} opUnidades={opUnidades} opCargos={opCargos} aoSalvar={recarregar} />}
      {geral && (
        <ImportarPlanilha aberto={importar} fechar={() => setImportar(false)} titulo="Importar servidores (planilha)" colunas={COLUNAS_SERVIDORES}
          rpcPrevia="importar_servidores_previa" rpcImportar="importar_servidores" nomeModelo="modelo-servidores.csv"
          exemplo={['Nome Completo Exemplo', '000999', 'Auditor Fiscal', 'COFIT', '', '30', '0', '0', 'efetivo', 'não']}
          explicacao="Cadastra servidores novos com os saldos do RH. Matrícula obrigatória e única; cargo e unidade devem existir (sigla da unidade). Antes de gravar, o sistema mostra todos os erros e só importa se não houver nenhum. Alterar servidor já cadastrado continua passando por aprovação."
          aoImportar={recarregar} />
      )}
      {convite && <Convite fechar={() => setConvite(false)} servidores={S.filter((s) => s.situacao === 'ativo' && s.email_institucional && !US.some((u) => u.servidor_id === s.id))} perfilAtual={info?.perfil} aoSalvar={recarregar} />}
    </>
  );
}

function DetalheServidor(p: {
  s: Servidor; us?: Usuario; geral: boolean; podePedir: boolean; meuId?: string; modulos: Modulo[]; pacotes: Pacote[];
  extras: Extra[]; unExtras: UnExtra[]; sigla: (id: string) => string; cargo: string; fechar: () => void; aoMudar: () => void;
  pedir: (p: Pedido) => void; opUnidades: { valor: string; rotulo: string }[]; opCargos: { valor: string; rotulo: string }[];
  todasUnidades: { valor: string; rotulo: string }[]; perfilAtual?: Perfil;
}) {
  const { s, us, geral } = p;
  const [erro, setErro] = useState<string | null>(null);
  const [novoModulo, setNovoModulo] = useState('');
  const pacote = us ? p.pacotes.filter((x) => x.perfil === us.perfil).map((x) => x.modulo_codigo) : [];
  const meusExtras = us ? p.extras.filter((e) => e.usuario_id === us.id).map((e) => e.modulo_codigo) : [];
  const minhasUnidades = us ? p.unExtras.filter((e) => e.usuario_id === us.id).map((e) => e.unidade_id) : [];
  const nome = (c: string) => p.modulos.find((m) => m.codigo === c)?.nome ?? c;
  const proprio = us?.id === p.meuId;

  const rpc = async (fn: string, args: Record<string, unknown>) => {
    setErro(null);
    const { error } = await supabase.rpc(fn, args);
    if (error) setErro(mensagemErro(error)); else p.aoMudar();
  };

  return (
    <Dialogo aberto fechar={p.fechar} titulo={s.nome_completo} acoes={<button type="button" className="botao" onClick={p.fechar}>Fechar</button>}>
      {erro && <Aviso tom="critico">{erro}</Aviso>}
      <div className="caixa-cinza">
        Matrícula <strong>{s.matricula}</strong> · {p.cargo} · {p.sigla(s.unidade_id)}<br />
        {s.email_institucional ?? 'Sem e-mail institucional'} · {s.situacao === 'ativo' ? 'Ativo' : 'Inativo'}<br />
        Vínculo: {s.tipo_vinculo ? ROTULO_VINCULO[s.tipo_vinculo] : <strong>não informado</strong>}{s.exerce_comissao ? ' · em cargo em comissão/função de confiança' : ''}
        {' · '}{s.elegivel_adicional ? 'elegível ao adicional de produtividade' : 'não elegível ao adicional de produtividade'}
      </div>
      {p.podePedir && !proprio && (
        <button type="button" className="botao" onClick={() => p.pedir({
          tipo: 'servidor_alterar', titulo: `Alterar dados de ${s.nome_completo}`, alvo: s.id,
          aviso: 'Alterar dados já cadastrados (inclusive a matrícula) passa por aprovação.',
          campos: [
            { chave: 'nome_completo', rotulo: 'Nome completo', inicial: s.nome_completo },
            { chave: 'matricula', rotulo: 'Matrícula', inicial: s.matricula, max: 20 },
            { chave: 'cargo_id', rotulo: 'Cargo', tipo: 'select', inicial: s.cargo_id, opcoes: p.opCargos },
            { chave: 'unidade_id', rotulo: 'Unidade', tipo: 'select', inicial: s.unidade_id, opcoes: p.opUnidades },
            { chave: 'email_institucional', rotulo: 'E-mail institucional', inicial: s.email_institucional ?? '', max: 254 },
            { chave: 'situacao', rotulo: 'Situação', tipo: 'select', inicial: s.situacao, opcoes: [{ valor: 'ativo', rotulo: 'Ativo' }, { valor: 'inativo', rotulo: 'Inativo' }] },
            { chave: 'tipo_vinculo', rotulo: 'Tipo de vínculo', tipo: 'select', inicial: s.tipo_vinculo ?? '', opcoes: TIPOS_VINCULO.map((v) => ({ valor: v, rotulo: ROTULO_VINCULO[v] })) },
            { chave: 'exerce_comissao', rotulo: 'Cargo em comissão/função de confiança', tipo: 'select', inicial: String(s.exerce_comissao), opcoes: [{ valor: 'false', rotulo: 'Não' }, { valor: 'true', rotulo: 'Sim' }] },
          ],
        })}>Solicitar alteração de dados</button>
      )}

      <h3 style={{ margin: 0, fontSize: 15 }}>Acesso ao sistema</h3>
      {!us ? <p className="nota">Sem usuário. {geral && s.email_institucional ? 'Use “+ Convidar usuário”.' : ''}</p> : (
        <>
          <div style={{ fontSize: 13 }}>Perfil: <strong>{ROTULO_PERFIL[us.perfil]}</strong> · {us.ativo ? <Selo tom="positivo">Acesso ativo</Selo> : <Selo tom="critico">Acesso desativado</Selo>}</div>
          <div>
            <div className="texto-suave" style={{ marginBottom: 4 }}>Pacote padrão do perfil (provisório)</div>
            <div className="acoes" style={{ gap: 6 }}>{pacote.map((c) => <Selo key={c} tom="neutro">{nome(c)}</Selo>)}</div>
          </div>
          <div>
            <div className="texto-suave" style={{ marginBottom: 4 }}>Módulos extras</div>
            <div className="acoes" style={{ gap: 6 }}>
              {meusExtras.length === 0 && <span className="texto-suave">Nenhum.</span>}
              {meusExtras.map((c) => (
                <span key={c} className="selo selo-info">{nome(c)}{geral && <button type="button" aria-label={`Retirar ${nome(c)}`} style={{ marginLeft: 6, background: 'none', border: 0, color: 'inherit', cursor: 'pointer' }} onClick={() => rpc('retirar_modulo_extra', { p_usuario: us.id, p_modulo: c })}>×</button>}</span>
              ))}
            </div>
            {geral && (
              <div className="acoes" style={{ marginTop: 8 }}>
                <select aria-label="Módulo extra" value={novoModulo} onChange={(e) => setNovoModulo(e.target.value)} style={{ minHeight: 44, borderRadius: 8, border: '1px solid var(--cor-borda-campo)', padding: '0 10px' }}>
                  <option value="">Adicionar módulo…</option>
                  {p.modulos.filter((m) => !pacote.includes(m.codigo) && !meusExtras.includes(m.codigo)).map((m) => <option key={m.codigo} value={m.codigo}>{m.nome}</option>)}
                </select>
                <button type="button" className="botao" disabled={!novoModulo} onClick={() => rpc('conceder_modulo_extra', { p_usuario: us.id, p_modulo: novoModulo }).then(() => setNovoModulo(''))}>Adicionar</button>
              </div>
            )}
            <p className="nota" style={{ marginTop: 6 }}>Vale na hora, sem aprovação, e fica na auditoria. O módulo extra não amplia o escopo de dados.</p>
          </div>
          <div>
            <div className="texto-suave" style={{ marginBottom: 4 }}>Acesso a outras unidades</div>
            <div className="acoes" style={{ gap: 6 }}>
              {minhasUnidades.length === 0 && <span className="texto-suave">Nenhum.</span>}
              {minhasUnidades.map((id) => <Selo key={id} tom="info">Unidade {p.sigla(id)}</Selo>)}
            </div>
          </div>
          {!proprio && (
            <div className="acoes">
              {geral && <button type="button" className="botao" onClick={() => p.pedir({
                tipo: 'usuario_perfil', titulo: `Alterar perfil de ${s.nome_completo}`, alvo: us.id, aviso: 'Mudança de permissão passa por aprovação.',
                campos: [{ chave: 'perfil', rotulo: 'Novo perfil', tipo: 'select', inicial: us.perfil, opcoes: PERFIS.filter((x) => x !== 'administrador' || p.perfilAtual === 'administrador').map((x) => ({ valor: x, rotulo: ROTULO_PERFIL[x] })) }],
              })}>Alterar perfil</button>}
              {p.podePedir && <button type="button" className="botao" onClick={() => p.pedir({
                tipo: 'acesso_unidade_conceder', titulo: `Acesso extra para ${s.nome_completo}`, alvo: us.id, aviso: 'Acesso a outra unidade passa por aprovação.',
                campos: [{ chave: 'unidade_id', rotulo: 'Unidade', tipo: 'select', opcoes: p.todasUnidades.filter((u) => !minhasUnidades.includes(u.valor) && u.valor !== s.unidade_id) }],
              })}>Acesso a outra unidade</button>}
              {p.podePedir && minhasUnidades.length > 0 && <button type="button" className="botao" onClick={() => p.pedir({
                tipo: 'acesso_unidade_retirar', titulo: `Retirar acesso de ${s.nome_completo}`, alvo: us.id,
                campos: [{ chave: 'unidade_id', rotulo: 'Unidade', tipo: 'select', opcoes: minhasUnidades.map((id) => ({ valor: id, rotulo: p.sigla(id) })) }],
              })}>Retirar acesso a unidade</button>}
              {geral && (us.ativo
                ? <button type="button" className="botao botao-critico" onClick={() => window.confirm('Desativar o acesso agora? O efeito é imediato.') && rpc('desativar_usuario', { p_usuario: us.id })}>Desativar acesso</button>
                : <button type="button" className="botao" onClick={() => rpc('reativar_usuario', { p_usuario: us.id })}>Reativar acesso</button>)}
            </div>
          )}
        </>
      )}
    </Dialogo>
  );
}

function NovoServidor({ fechar, unidadeId, opUnidades, opCargos, aoSalvar }: {
  fechar: () => void; unidadeId: string; opUnidades: { valor: string; rotulo: string }[]; opCargos: { valor: string; rotulo: string }[]; aoSalvar: () => void;
}) {
  const [f, setF] = useState({ nome_completo: '', matricula: '', cargo_id: '', unidade_id: unidadeId, email_institucional: '', tipo_vinculo: '', exerce_comissao: false });
  const [erro, setErro] = useState<string | null>(null);
  const salvar = async () => {
    const r = servidorNovo.safeParse(f);
    if (!r.success) { setErro(primeiroErro(r)); return; }
    const { error } = await supabase.from('servidores').insert(r.data);
    if (error) { setErro(error.code === '23505' ? 'Matrícula ou e-mail já cadastrado.' : mensagemErro(error)); return; }
    aoSalvar(); fechar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo="Cadastrar servidor" acoes={<><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" onClick={salvar}>Salvar</button></>}>
      <div className="form">
        {erro && <Aviso tom="critico">{erro}</Aviso>}
        <Campo rotulo="Nome completo"><input maxLength={200} value={f.nome_completo} onChange={(e) => setF({ ...f, nome_completo: e.target.value })} /></Campo>
        <Campo rotulo="Matrícula funcional" ajuda="Obrigatória e única. Separa as folhas de ponto."><input maxLength={20} value={f.matricula} onChange={(e) => setF({ ...f, matricula: e.target.value })} /></Campo>
        <div className="form-linha">
          <Campo rotulo="Cargo"><select value={f.cargo_id} onChange={(e) => setF({ ...f, cargo_id: e.target.value })}><option value="">Selecione…</option>{opCargos.map((o) => <option key={o.valor} value={o.valor}>{o.rotulo}</option>)}</select></Campo>
          <Campo rotulo="Unidade"><select value={f.unidade_id} onChange={(e) => setF({ ...f, unidade_id: e.target.value })}>{opUnidades.map((o) => <option key={o.valor} value={o.valor}>{o.rotulo}</option>)}</select></Campo>
        </div>
        <div className="form-linha">
          <Campo rotulo="Tipo de vínculo"><select value={f.tipo_vinculo} onChange={(e) => setF({ ...f, tipo_vinculo: e.target.value })}><option value="">Selecione…</option>{TIPOS_VINCULO.map((v) => <option key={v} value={v}>{ROTULO_VINCULO[v]}</option>)}</select></Campo>
          <Campo rotulo="Cargo em comissão/função de confiança"><select value={String(f.exerce_comissao)} onChange={(e) => setF({ ...f, exerce_comissao: e.target.value === 'true' })}><option value="false">Não</option><option value="true">Sim</option></select></Campo>
        </div>
        <Campo rotulo="E-mail institucional" ajuda="Obrigatório só para quem terá login."><input type="email" maxLength={254} value={f.email_institucional} onChange={(e) => setF({ ...f, email_institucional: e.target.value })} /></Campo>
        <p className="nota">Cadastro novo não passa por aprovação. Alterações depois de salvo passam.</p>
      </div>
    </Dialogo>
  );
}

function Convite({ fechar, servidores, perfilAtual, aoSalvar }: { fechar: () => void; servidores: Servidor[]; perfilAtual?: Perfil; aoSalvar: () => void }) {
  const [servidor, setServidor] = useState('');
  const [perfil, setPerfil] = useState<Perfil>('funcionario');
  const [erro, setErro] = useState<string | null>(null);
  const [ok, setOk] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const enviar = async () => {
    if (!servidor) { setErro('Selecione o servidor.'); return; }
    setEnviando(true); setErro(null);
    const { error } = await supabase.functions.invoke('convidar-usuario', { body: { servidor_id: servidor, perfil, redirect_to: `${window.location.origin}${process.env.NEXT_PUBLIC_BASE_PATH ?? ''}/definir-senha/` } });
    setEnviando(false);
    if (error) { setErro('Não foi possível enviar o convite.'); return; }
    setOk(true); aoSalvar();
  };
  return (
    <Dialogo aberto fechar={fechar} titulo="Convidar usuário" acoes={ok ? <button type="button" className="botao" onClick={fechar}>Fechar</button> : <><button type="button" className="botao" onClick={fechar}>Cancelar</button><button type="button" className="botao botao-primario" disabled={enviando} onClick={enviar}>Enviar convite</button></>}>
      {ok ? <Aviso tom="sucesso">Convite enviado para o e-mail institucional do servidor.</Aviso> : (
        <div className="form">
          {erro && <Aviso tom="critico">{erro}</Aviso>}
          <Campo rotulo="Servidor" ajuda="Só aparecem servidores ativos, com e-mail institucional e ainda sem usuário.">
            <select value={servidor} onChange={(e) => setServidor(e.target.value)}><option value="">Selecione…</option>{servidores.map((s) => <option key={s.id} value={s.id}>{s.nome_completo} · {s.matricula}</option>)}</select>
          </Campo>
          <Campo rotulo="Perfil">
            <select value={perfil} onChange={(e) => setPerfil(e.target.value as Perfil)}>{PERFIS.filter((x) => x !== 'administrador' || perfilAtual === 'administrador').map((x) => <option key={x} value={x}>{ROTULO_PERFIL[x]}</option>)}</select>
          </Campo>
        </div>
      )}
    </Dialogo>
  );
}
