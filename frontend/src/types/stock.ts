export type EstadoStock =
  | 'DISPONIBLE'
  | 'STOCK_BAJO'
  | 'AGOTADO'
  | 'SIN_CONTEO'

export interface ProductoStock {
  id_producto: number
  codigo: string
  nombre: string
  id_categoria: number
  categoria: string
  unidad: string
  stock_minimo: number
  stock_maximo?: number | null
  fecha_ultimo_conteo: string | null
  stock_ultimo_conteo: number | null
  entradas_recepcion: number
  entradas_movimiento: number
  salidas_movimiento: number
  stock_actual: number | null
  estado_stock: EstadoStock
}

export interface ResumenStock {
  total: number
  disponibles: number
  stock_bajo: number
  agotados: number
  sin_conteo: number
}

export interface RespuestaStock {
  resumen: ResumenStock
  categorias: string[]
  productos: ProductoStock[]
}
