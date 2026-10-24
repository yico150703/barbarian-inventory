export interface IngredienteSubproducto {
  id_producto: number
  codigo: string
  producto: string
  cantidad: number
  unidad: string
  activo: boolean
}

export interface SubproductoDetalle {
  id_subproducto: number
  codigo: string
  nombre: string
  rendimiento: number
  instruccion: string
  unidad: string
  activo: boolean
  total_ingredientes: number
  ingredientes: IngredienteSubproducto[]
}

export interface ResumenSubproductos {
  total_subproductos: number
  subproductos_activos: number
  subproductos_inactivos: number
  ingredientes_diferentes: number
}

export interface RespuestaSubproductos {
  subproductos: SubproductoDetalle[]
  resumen: ResumenSubproductos
}

export interface FormularioSubproducto {
  unidades_medida: import('./units').UnidadMedida[]
  unidades: string[]
  productos: import('./recipe').IngredienteDisponible[]
}

export interface SubproductoEntrada {
  nombre: string
  rendimiento: string
  unidad: string
  instruccion: string
  activo: boolean
  ingredientes: import('./recipe').IngredienteEntrada[]
}

export interface OpcionSalsa {
  id_producto: number | null
  codigo: string | null
  producto: string
  cantidad: number | null
  unidad: string | null
  es_sin_salsa: boolean
}

export interface GrupoSalsaDetalle {
  id_grupo_salsa: number
  id_presentacion_venta: number
  cantidad_maxima: number
  activo: boolean
  id_item_carta: number
  codigo_item: string
  item_carta: string
  categoria_carta: string
  contenido: number
  unidad_presentacion: string
  precio: number
  total_opciones: number
  opciones: OpcionSalsa[]
}

export interface ResumenGruposSalsa {
  total_grupos: number
  grupos_activos: number
  grupos_inactivos: number
  salsas_diferentes: number
}

export interface RespuestaGruposSalsa {
  grupos_salsa: GrupoSalsaDetalle[]
  resumen: ResumenGruposSalsa
}
