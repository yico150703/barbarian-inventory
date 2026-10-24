export interface ProductoPendienteRecepcion {
  id_producto: number
  codigo: string
  nombre: string
  categoria: string
  unidad: string
  presentacion: number
  cantidad_solicitada: number
  cantidad_recibida: number
  cantidad_pendiente: number
}

export interface PendienteRecepcion {
  id_orden_compra: number
  codigo_orden: string
  estado_orden_compra: string
  fecha_registro: string | null
  id_proveedor: number
  proveedor: string
  productos: ProductoPendienteRecepcion[]
}

export interface RespuestaPendientesRecepcion {
  resumen: {
    ordenes_pendientes: number
    recepciones_pendientes: number
    productos_pendientes: number
  }
  pendientes: PendienteRecepcion[]
}

export interface DatosRegistrarRecepcion {
  id_proveedor: number
  numero_factura: string
  fecha_recepcion: string
  detalles: Array<{
    id_producto: number
    cantidad_recibida: number
  }>
}

export interface RecepcionHistorial {
  id_factura_recepcion: number
  id_orden_compra: number
  codigo_orden: string
  estado_orden_compra: string
  numero_factura: string
  fecha_recepcion: string
  id_proveedor: number
  proveedor: string
  recibido_por: string
  productos_recibidos: number
  cantidad_total: number
}

export interface DetalleRecepcionHistorial {
  id_factura_recepcion_detalle: number
  id_producto: number
  codigo: string
  nombre: string
  unidad: string
  cantidad_recibida: number
  cantidad_solicitada: number
  recibido_otras_facturas: number
  maximo_permitido: number
}

export interface RespuestaDetalleRecepcion {
  recepcion: {
    id_factura_recepcion: number
    id_orden_compra: number
    codigo_orden: string
    estado_orden_compra: string
    id_proveedor: number
    proveedor: string
    numero_factura: string
    fecha_recepcion: string
    recibido_por: string
    detalles: DetalleRecepcionHistorial[]
  }
}

export interface DatosCorregirRecepcion {
  numero_factura: string
  fecha_recepcion: string
  motivo_correccion:
    | 'ERROR_DIGITACION'
    | 'MAL_CONTADO'
    | 'PRODUCTO_DANADO'
    | 'PRODUCTO_RECHAZADO'
    | 'ERROR_FACTURA'
    | 'OTRO'
  observacion: string
  detalles: Array<{
    id_factura_recepcion_detalle: number
    cantidad_recibida: number
  }>
}