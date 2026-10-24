import { formatearUnidad } from '../../utils/unitHelpers'

// Solo presentación. Los IDs, códigos y factores originales siguen en el borrador.
export function revisionVisible(value: unknown, key = ''): unknown {
  if (Array.isArray(value)) return value.map(v => revisionVisible(v, key))
  if (value === null || typeof value !== 'object') {
    if (typeof value === 'string' && (key.startsWith('id_') || key.startsWith('ids_') || key === 'ingrediente')) {
      return value.replace(/\s*\(#\d+\)$/, '')
    }
    return value
  }
  const row = value as Record<string, unknown>
  const result: Record<string, unknown> = {}
  const unit = typeof row.unidad === 'string' ? formatearUnidad(row.unidad) : ''
  const hasPresentation = unit && row.presentacion !== null && row.presentacion !== undefined
  for (const [field, item] of Object.entries(row)) {
    if (field.endsWith('_medida') && item && typeof item === 'object') {
      const base = field.slice(0, -7)
      if (base in row) continue
      const measure = item as Record<string, unknown>
      result[base] = measure.simbolo ?? measure.nombre ?? 'Sin unidad'
    } else if (field === 'unidad') {
      if (!hasPresentation) result[field] = unit || item
    } else if (field === 'unidad_presentacion') {
      result[field] = formatearUnidad(item)
    } else if (field === 'presentacion' && hasPresentation) {
      const amount = typeof item === 'number' ? item.toLocaleString('es-PE', { maximumFractionDigits: 3 }) : String(item)
      result[field] = `${amount} ${unit === 'unidad' && Number(item) !== 1 ? 'unidades' : unit}`
    } else {
      result[field] = revisionVisible(item, field)
    }
  }
  return result
}
