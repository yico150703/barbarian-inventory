import type { UnidadMedida } from '../types/units'

// El catálogo y los códigos de intercambio proceden del backend.
// Este formato mantiene legibles las respuestas históricas y las sesiones abiertas.
export function formatearUnidad(valor: unknown): string {
  const unidad = typeof valor === 'string' ? valor : ''
  return ({ KGM: 'kg', LTR: 'L', C62: 'unidad', GRM: 'g', MLT: 'mL', Kg: 'kg', UNI: 'unidad', 'PORCIÓN': 'porción', PORCION: 'porción' } as Record<string, string>)[unidad] ?? unidad
}

export function unidadesCompatibles(unidades: UnidadMedida[], valor: string): UnidadMedida[] {
  const base = unidades.find((u) => u.valor === valor)?.codigo_base
  return base ? unidades.filter((u) => u.codigo_base === base) : []
}

export function etiquetaUnidad(unidades: UnidadMedida[], valor: string): string {
  const unidad = unidades.find((u) => u.valor === valor)
  return unidad ? `${unidad.nombre} (${unidad.simbolo})` : formatearUnidad(valor)
}

export function convertirCantidadVisible(cantidad: string, origen: string, destino: string, unidades: UnidadMedida[]): string {
  const anterior = unidades.find((u) => u.valor === origen)
  const nueva = unidades.find((u) => u.valor === destino)
  if (!anterior || !nueva || anterior.codigo_base !== nueva.codigo_base || cantidad.trim() === '') return cantidad
  const valor = Number(cantidad) * Number(anterior.factor_a_base) / Number(nueva.factor_a_base)
  // Solo para editar el formulario; el backend valida y calcula con Decimal.
  return Number.isFinite(valor) ? String(Number(valor.toFixed(6))) : cantidad
}
