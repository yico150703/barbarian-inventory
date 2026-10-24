export interface MotivoMovimiento {
  valor: string
  etiqueta: string
  tipo_movimiento: 'ENTRADA' | 'SALIDA'
  requiere_local: boolean
  requiere_proveedor: boolean
}

export interface ProductoMovimiento {
  id_producto: number
  codigo: string
  nombre: string
  unidad: string
  id_categoria: number
  categoria: string
}

export interface ProveedorMovimiento {
  id_proveedor: number
  nombre: string
}

export interface RespuestaFormularioMovimiento {
  locales: {id_local: number; nombre: string}[]
  motivos: MotivoMovimiento[]
  categorias: string[]
  productos: ProductoMovimiento[]
  proveedores: ProveedorMovimiento[]
}

export interface DetalleRegistrarMovimiento {
  id_producto: number
  cantidad: number
}

export interface DatosRegistrarMovimiento {
  motivo_movimiento: string
  fecha_movimiento: string
  id_local_destino?: number
  local_relacionado: string | null
  id_proveedor: number | null
  observacion: string | null
  detalles: DetalleRegistrarMovimiento[]
}

export interface MovimientoRegistrado {
  id_movimiento_inventario: number
  codigo: string
  tipo_movimiento: 'ENTRADA' | 'SALIDA'
  motivo_movimiento: string
  fecha_movimiento: string
  registrado_por: string
  id_local_destino?: number
  local_relacionado: string | null
  id_proveedor: number | null
  proveedor: string | null
  observacion: string | null
  detalles: Array<{
    id_producto: number
    codigo: string
    nombre: string
    unidad: string
    cantidad: number
  }>
}

export interface RespuestaRegistrarMovimiento {
  mensaje: string
  movimiento: MovimientoRegistrado
}

