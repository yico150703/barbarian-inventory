export interface ComponenteReceta {
  id_receta_detalle: number
  tipo_componente: 'PRODUCTO' | 'SUBPRODUCTO'
  id_producto: number | null
  producto_codigo: string | null
  producto_nombre: string | null
  id_subproducto: number | null
  subproducto_codigo: string | null
  subproducto_nombre: string | null
  nombre_componente: string
  codigo_componente: string
  cantidad: number
  unidad: string
}

export interface OpcionSalsa {
  id_grupo_salsa_opcion: number
  id_producto: number
  codigo: string
  nombre: string
  cantidad: number
  unidad: string
  activo: boolean
}

export interface GrupoSalsaReceta {
  id_grupo_salsa: number
  cantidad_maxima: number
  permite_repetir: boolean
  activo: boolean
  opciones: OpcionSalsa[]
}

export interface Receta {
  id_receta: number
  id_presentacion_venta: number
  instrucciones: string
  activo: boolean
  id_item_carta: number
  codigo_item: string
  item_carta: string
  tipo_item: string
  categoria_carta: string
  id_categoria_carta: number
  id_menaje: number
  contenido: number
  unidad_presentacion: string
  precio: number
  total_componentes: number
  componentes: ComponenteReceta[]
  grupo_salsa: GrupoSalsaReceta | null
}

export interface ResumenRecetas {
  total_recetas: number
  recetas_activas: number
  recetas_inactivas: number
  total_categorias: number
}

export interface RespuestaRecetas {
  recetas: Receta[]
  categorias: string[]
  resumen: ResumenRecetas
}

export interface IngredienteDisponible {
  id: number
  codigo: string
  nombre: string
  unidad: string
  activo: boolean
}

export interface FormularioReceta {
  unidades_medida: import('./units').UnidadMedida[]
  tipos: string[]
  unidades_presentacion: string[]
  categorias: { id_categoria_carta: number; nombre: string; activo: boolean }[]
  menajes: { id_menaje: number; nombre: string; activo: boolean }[]
  items: { id_item_carta: number; codigo: string; nombre: string; id_categoria_carta: number; tipo: string; activo: boolean }[]
  presentaciones: { id_presentacion_venta: number; id_item_carta: number; id_menaje: number; contenido: number; unidad: string; activo: boolean; id_receta: number | null }[]
  productos: IngredienteDisponible[]
  subproductos: IngredienteDisponible[]
}

export interface IngredienteEntrada {
  unidad_cantidad?: string
  tipo_componente: 'PRODUCTO' | 'SUBPRODUCTO'
  id: number
  cantidad: string
}

export interface RecetaEntrada {
  id_presentacion_venta: number
  instrucciones: string
  activo?: boolean
  componentes: IngredienteEntrada[]
  grupo_salsa: { cantidad_maxima: number; permite_repetir: boolean; opciones: IngredienteEntrada[] } | null
}
