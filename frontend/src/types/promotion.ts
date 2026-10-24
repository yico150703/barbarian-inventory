export interface OpcionPromocion {
  id_promocion_opcion: number
  id_presentacion_venta: number
  id_item_carta: number
  codigo_item: string
  item_carta: string
  tipo: string
  id_categoria_carta: number
  categoria_carta: string
  contenido: number
  unidad: string
  precio_individual: number
  presentacion_activa: boolean
}

export interface GrupoPromocion {
  id_promocion_grupo: number
  cantidad_elegir: number
  permite_repetir: boolean
  total_opciones: number
  opciones: OpcionPromocion[]
}

export interface PromocionDetalle {
  id_promocion: number
  codigo: string
  nombre: string
  precio: number
  hora_inicio: string | null
  hora_fin: string | null
  tiene_horario: boolean
  activo: boolean
  reposiciones: number[]
  total_grupos: number
  total_opciones: number
  grupos: GrupoPromocion[]
}

export interface ResumenPromociones {
  total_promociones: number
  promociones_activas: number
  promociones_inactivas: number
  promociones_con_horario: number
  promociones_sin_horario: number
}

export interface RespuestaPromociones {
  promociones: PromocionDetalle[]
  resumen: ResumenPromociones
}