export interface ResumenInventarioItem {
  id_inventario_cierre: number
  fecha_inventario: string
  estado_inventario: string
  fecha_registro: string | null
  observacion: string | null
  productos_contados: number
  usuario: string
}

export interface ResumenInventario {
  total_productos: number
  productos_contados_hoy: number
  porcentaje_avance: number
  inventario_hoy: ResumenInventarioItem | null
  ultimo_inventario_cerrado: ResumenInventarioItem | null
  ultimos_inventarios: ResumenInventarioItem[]
}

export interface CabeceraInventarioActual {
  id_inventario_cierre: number
  fecha_inventario: string
  estado_inventario: string
  usuario_registro: number
  usuario: string
  fecha_registro: string | null
  observacion: string | null
}

export interface ResumenInventarioActual {
  total_productos: number
  productos_contados: number
  productos_pendientes: number
  porcentaje_avance: number
}

export interface ProductoInventarioActual {
  id_producto: number
  codigo: string
  nombre: string
  unidad: string
  id_categoria: number
  categoria: string
  stock_contado: number | null
}

export interface RespuestaInventarioActual {
  inventario: CabeceraInventarioActual | null
  fechas_disponibles: string[]
  resumen: ResumenInventarioActual
  productos: ProductoInventarioActual[]
  mensaje?: string
}

/* Iniciar */

export interface SolicitudIniciarInventario {
  fecha_inventario: string
}

export interface RespuestaIniciarInventario {
  mensaje: string
  id_inventario_cierre?: number
  fecha_inventario?: string
}

/* Guardar borrador */

export interface ConteoInventario {
  id_producto: number
  stock_contado: number | null
}

export interface SolicitudGuardarInventario {
  conteos: ConteoInventario[]
}

export type RespuestaGuardarInventario =
  RespuestaInventarioActual

/* Cerrar */

export type SolicitudCerrarInventario =
  Record<string, never>

export interface RespuestaCerrarInventario {
  mensaje: string
  id_inventario_cierre: number
  fecha_inventario: string
  estado_inventario: 'CERRADO'
}