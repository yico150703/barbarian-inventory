export interface InventarioRevisionItem {
  id_inventario_cierre: number
  fecha_inventario: string
  estado_inventario: string
  fecha_registro: string | null
  usuario_registro: number
  registrado_por: string
  usuario_revision: number | null
  revisado_por: string | null
  motivo_revision: string | null
  observacion: string | null
  productos_contados: number
  productos_no_contados: number
  productos_en_cero: number
  productos_con_existencia: number
  total_productos: number
  revisado: boolean
}

export interface ResumenRevisionInventarios {
  total_inventarios: number
  pendientes_revision: number
  inventarios_revisados: number
}

export interface RespuestaInventariosRevision {
  resumen: ResumenRevisionInventarios
  inventarios: InventarioRevisionItem[]
}

export interface ProductoRevisionInventario {
  id_producto: number
  codigo: string
  nombre: string
  categoria: string
  unidad: string
  stock_minimo: number
  stock_contado: number | null
  fue_contado: boolean
  producto_activo: boolean
}

export interface CabeceraDetalleRevision {
  id_inventario_cierre: number
  fecha_inventario: string
  estado_inventario: string
  fecha_registro: string | null
  registrado_por: string
  usuario_revision: number | null
  revisado_por: string | null
  motivo_revision: string | null
  observacion: string | null
  revisado: boolean
}

export interface ResumenDetalleRevision {
  total_productos: number
  productos_contados: number
  productos_no_contados: number
  productos_en_cero: number
}

export interface RespuestaDetalleRevision {
  mensaje?: string
  inventario: CabeceraDetalleRevision
  resumen: ResumenDetalleRevision
  productos: ProductoRevisionInventario[]
}

export interface DatosRegistrarRevision {
  motivo_revision: string
  observacion: string
}

export interface CambioCorreccionInventario {
  id_producto: number
  stock_nuevo: number | null
}

export interface DatosCorregirInventario {
  motivo_correccion: string
  observacion: string
  cambios: CambioCorreccionInventario[]
}

export interface CambioHistorialCorreccion {
  id_producto: number
  codigo: string
  producto: string
  unidad: string
  stock_anterior: number | null
  stock_nuevo: number | null
}

export interface HistorialCorreccion {
  id_correccion: number
  fecha_correccion: string
  motivo_correccion: string
  observacion: string
  corregido_por: string
  cambios: CambioHistorialCorreccion[]
}

export interface RespuestaHistorialCorrecciones {
  correcciones: HistorialCorreccion[]
}