import type { UnidadMedida, MedidaConUnidad } from './units'

export type UnidadProducto = 'KGM' | 'LTR' | 'C62'

export interface ProductoCatalogo extends MedidaConUnidad {
  id_producto: number
  codigo: string
  nombre: string
  id_categoria: number
  categoria: string
  id_proveedor: number
  proveedor: string
  unidad: UnidadProducto
  presentacion: number
  activo: boolean
}

export interface CategoriaProducto {
  id_categoria: number
  nombre: string
  prefijo: string
  siguiente_numero: number
  activo: boolean
}

export interface ProveedorCatalogo {
  ids_categorias: number[]
  id_proveedor: number
  nombre: string
  activo: boolean
}

export interface ResumenCatalogoProductos {
  total_productos: number
  productos_activos: number
  productos_inactivos: number
  total_categorias: number
  total_proveedores: number
}

export interface RespuestaCatalogoProductos {
  categorias_proveedor_configurables: boolean
  unidades_medida: UnidadMedida[]
  productos: ProductoCatalogo[]
  categorias: CategoriaProducto[]
  proveedores: ProveedorCatalogo[]
  resumen: ResumenCatalogoProductos
}

export interface CategoriaProductoDetalle
  extends CategoriaProducto {
  total_productos: number
  productos_activos: number
  productos_inactivos: number
}

export interface RespuestaCategoriasProducto {
  categorias: CategoriaProductoDetalle[]
  resumen: {
    total_categorias: number
    categorias_activas: number
    categorias_inactivas: number
    total_productos_asociados: number
  }
}

export interface ProveedorDetalle
  extends ProveedorCatalogo {
  total_productos: number
  productos_activos: number
  productos_inactivos: number
  total_categorias: number
  categorias: string[]
}

export interface RespuestaProveedores {
  categorias_proveedor_configurables: boolean
  categorias: CategoriaProducto[]
  proveedores: ProveedorDetalle[]
  resumen: {
    total_proveedores: number
    proveedores_activos: number
    proveedores_inactivos: number
    total_productos_asociados: number
  }
}

export interface ProductoRelacionado {
  id_producto: number
  codigo: string
  nombre: string
  activo: boolean
  id_categoria?: number
}

export interface DependenciasCategoria {
  categoria: CategoriaProducto
  productos: ProductoRelacionado[]
  productos_activos: number
  puede_desactivar: boolean
}

export interface DependenciasProveedor {
  proveedor: ProveedorCatalogo
  productos: ProductoRelacionado[]
  productos_activos: number
  puede_desactivar: boolean
}

export interface DependenciasProducto {
  producto: ProductoCatalogo
  dependencias: {
    recetas: number
    subproductos: number
    salsas_activas: number
    ordenes: number
    recepciones: number
    inventarios: number
    movimientos: number
  }
  puede_desactivar: boolean
}

export interface ProductoEntrada {
  unidad_presentacion?: string
  nombre: string
  id_categoria: number
  id_proveedor: number
  unidad: UnidadProducto
  presentacion: number
  motivo?: string
}

export interface CategoriaEntrada {
  nombre: string
  prefijo: string
}

export interface ProveedorEntrada {
  ids_categorias: number[]
  nombre: string
}

export interface ReasignacionEntrada {
  ids_productos: number[]
  motivo: string
  id_categoria_nueva?: number
  id_proveedor_nuevo?: number
}

export interface MensajeRespuesta {
  mensaje: string
  total?: number
  id_producto?: number
  id_categoria?: number
  id_proveedor?: number
  codigo?: string
}
