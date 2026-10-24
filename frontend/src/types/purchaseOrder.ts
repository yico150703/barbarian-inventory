export interface ProductoCompra {
  id_producto: number
  codigo: string
  nombre: string
  unidad: string
  presentacion: number
  stock_minimo: number
  stock_actual: number | null
  id_categoria: number
  categoria: string
  id_proveedor: number
  proveedor: string
}

export interface ProductoSugerido extends ProductoCompra {
  cantidad_sugerida: number
}

export interface RespuestaFormularioOrden {
  productos: ProductoCompra[]
  categorias: string[]
  proveedores: string[]
}

export interface RespuestaPedidoSugerido {
  productos: ProductoSugerido[]
  total_productos: number
}

export interface DatosRegistrarOrden {
  accion: 'GUARDAR_BORRADOR' | 'ENVIAR'
  detalles: Array<{
    id_producto: number
    cantidad_solicitada: number
  }>
}

export type EstadoOrdenCompra =
  | 'BORRADOR'
  | 'ENVIADA'
  | 'RECEPCION_PARCIAL'
  | 'RECEPCIONADA'
  | 'CERRADA_INCOMPLETA'
  | 'CANCELADA'

export interface OrdenCompraHistorial {
  id_orden_compra: number
  codigo: string
  estado_orden_compra: EstadoOrdenCompra
  fecha_registro: string | null
  registrado_por: string
  total_productos: number
  productos_con_recepcion: number
  productos_completos: number
  productos_pendientes: number
  motivo_cierre: string | null
  fecha_modificacion: string | null
  modificado_por: string | null
}

export interface DetalleOrdenHistorial {
  id_orden_compra_detalle: number
  id_producto: number
  codigo: string
  nombre: string
  unidad: string
  id_proveedor: number
  proveedor: string
  cantidad_solicitada: number
  cantidad_recibida: number
  cantidad_pendiente: number
}

export interface RespuestaDetalleOrden {
  orden: {
    id_orden_compra: number
    codigo: string
    estado_orden_compra: EstadoOrdenCompra
    fecha_registro: string | null
    motivo_cierre: string | null
    detalles: DetalleOrdenHistorial[]
  }
}

export interface FiltrosOrdenes {
  fecha_desde?: string
  fecha_hasta?: string
  estado?: EstadoOrdenCompra | ''
}