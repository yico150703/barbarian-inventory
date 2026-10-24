export interface CategoriaCarta {
  id_categoria_carta: number
  nombre: string
  prefijo: string
  siguiente_numero: number
  activo: boolean
  total_items: number
  items_activos: number
  items_inactivos: number
  total_presentaciones: number
  presentaciones_activas: number
  presentaciones_inactivas: number
}

export interface ResumenCategoriasCarta {
  total_categorias: number
  categorias_activas: number
  categorias_inactivas: number
  total_items: number
  total_presentaciones: number
}

export interface RespuestaCategoriasCarta {
  categorias: CategoriaCarta[]
  resumen: ResumenCategoriasCarta
}

export interface PresentacionVenta {
  id_presentacion_venta: number
  id_item_carta: number
  codigo_item: string
  item: string
  tipo: string
  id_categoria_carta: number
  categoria: string
  id_menaje: number
  menaje: string
  contenido: number
  unidad: string
  precio: number
  activo: boolean
}

export interface ResumenPresentacionesVenta {
  total_presentaciones: number
  presentaciones_activas: number
  presentaciones_inactivas: number
  total_items: number
  total_categorias: number
  total_menajes: number
}

export interface RespuestaPresentacionesVenta {
  presentaciones: PresentacionVenta[]
  resumen: ResumenPresentacionesVenta
}

export interface MenajeDetalle {
  id_menaje: number
  nombre: string
  activo: boolean
  total_presentaciones: number
  presentaciones_activas: number
  presentaciones_inactivas: number
  total_items: number
  items: string[]
}

export interface ResumenMenajes {
  total_menajes: number
  menajes_activos: number
  menajes_inactivos: number
  total_presentaciones: number
}

export interface RespuestaMenajes {
  menajes: MenajeDetalle[]
  resumen: ResumenMenajes
}