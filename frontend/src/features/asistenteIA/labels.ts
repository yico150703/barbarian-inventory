import { revisionVisible } from './reviewDisplay'

const labels: Record<string, string> = {
  stock: 'Stock actual', conteos: 'Conteos del equipo', asignaciones_conteo: 'Asignación por puesto',
  revision_conteo: 'Revisión del conteo', diferencias_conteo: 'Diferencias de inventario',
  jornadas: 'Jornadas operativas', mix_ventas: 'Mix de ventas', operacion: 'Operación',
  teorico: 'Cantidad del sistema', contado: 'Cantidad contada', corregido: 'Cantidad revisada',
  productos_aceptados: 'Productos incluidos en el cierre', referencia: 'Referencia del cálculo',
  nombre_item: 'Nombre del artículo', tipo_item: 'Tipo de artículo', id_categoria_carta: 'Categoría de carta',
  id_item_carta: 'Artículo existente', id_menaje: 'Menaje', id_presentacion_venta: 'Presentación',
  id_categoria: 'Categoría de producto', id_proveedor: 'Proveedor', grupo_salsa: 'Opciones elegibles',
  ids_categorias: 'Categorías del proveedor', presentacion: 'Contenido por presentación',
  unidad: 'Unidad de medida', unidad_presentacion: 'Unidad de compra',
  cantidad_maxima: 'Cantidad máxima', permite_repetir: 'Permite repetir', cantidad_elegir: 'Cantidad a elegir',
  hora_inicio: 'Hora de inicio', hora_fin: 'Hora de fin', tipo_componente: 'Tipo de ingrediente',
  id_promocion_grupo: 'Grupo existente (ID)', activo: 'Activo', instruccion: 'Instrucciones',
}
export const etiqueta = (key: string) => labels[key] ?? key.replaceAll('_', ' ').replace(/^./, c => c.toUpperCase())

export function textoRevision(value: unknown, depth = 0): string {
  if (depth === 0) value = revisionVisible(value)
  if (value === null || value === undefined) return 'Sin asignar'
  if (typeof value === 'boolean') return value ? 'Sí' : 'No'
  if (Array.isArray(value)) return value.map((v, i) => `\n${'  '.repeat(depth)}${i + 1}. ${textoRevision(v, depth + 1)}`).join('')
  if (typeof value === 'object') return Object.entries(value).map(([k, v]) =>
    `${'  '.repeat(depth)}${etiqueta(k)}: ${textoRevision(v, depth + 1)}`).join('\n')
  return String(value)
}
