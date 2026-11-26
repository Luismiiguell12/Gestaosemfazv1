export interface Unidade { id: string; sigla: string; nome: string; tipo: 'gabinete' | 'diretoria' | 'coordenadoria' | 'assessoria'; unidade_pai_id: string | null; ordem: number; ativa: boolean }

export interface GrupoUnidades { id: string; nome: string; unidades: Unidade[] }

const porOrdem = (a: Unidade, b: Unidade) => a.ordem - b.ordem || a.sigla.localeCompare(b.sigla, 'pt-BR');

/** Agrupa como no Painel: uma faixa por diretoria + "Ligadas ao Gabinete". */
export function agruparParaPainel(todas: Unidade[], visiveis?: Set<string>): GrupoUnidades[] {
  const ok = (u: Unidade) => u.ativa && (!visiveis || visiveis.has(u.id));
  const gab = todas.find((u) => u.tipo === 'gabinete');
  const grupos: GrupoUnidades[] = todas
    .filter((u) => u.tipo === 'diretoria' && u.ativa)
    .sort(porOrdem)
    .map((d) => ({
      id: d.id,
      nome: `${d.sigla} · ${d.nome.replace(/^Diretoria de /i, '')}`,
      unidades: todas.filter((u) => u.unidade_pai_id === d.id && ok(u)).sort(porOrdem),
    }));
  // diretor sem coordenadoria visível ainda vê o cartão da própria diretoria
  for (const g of grupos) {
    const d = todas.find((u) => u.id === g.id)!;
    if (g.unidades.length === 0 && ok(d)) g.unidades = [d];
  }
  const ligadas = [gab, ...todas.filter((u) => gab && u.unidade_pai_id === gab.id && u.tipo !== 'diretoria').sort(porOrdem)]
    .filter((u): u is Unidade => Boolean(u) && ok(u!));
  if (gab) grupos.push({ id: gab.id, nome: 'Ligadas ao Gabinete', unidades: ligadas });
  return grupos.filter((g) => g.unidades.length > 0);
}

/** árvore achatada (pré-ordem) com nível p/ indentação */
export function arvore(todas: Unidade[]): { u: Unidade; nivel: number }[] {
  const filhos = (pai: string | null) => todas.filter((u) => u.unidade_pai_id === pai).sort(porOrdem);
  const out: { u: Unidade; nivel: number }[] = [];
  const visitar = (u: Unidade, nivel: number) => {
    out.push({ u, nivel });
    // diretorias por último, como no protótipo
    const f = filhos(u.id);
    [...f.filter((x) => x.tipo !== 'diretoria'), ...f.filter((x) => x.tipo === 'diretoria')].forEach((x) => visitar(x, nivel + 1));
  };
  filhos(null).forEach((r) => visitar(r, 0));
  return out;
}

export function caminho(todas: Unidade[], id: string | null | undefined): Unidade[] {
  const out: Unidade[] = [];
  let atual = todas.find((u) => u.id === id);
  while (atual) { out.unshift(atual); atual = todas.find((u) => u.id === atual!.unidade_pai_id); }
  return out;
}
