import type {
  CategoriaEntrada,
  DependenciasCategoria,
  DependenciasProducto,
  DependenciasProveedor,
  MensajeRespuesta,
  ProductoEntrada,
  ProveedorEntrada,
  ReasignacionEntrada,
  RespuestaCatalogoProductos,
  RespuestaCategoriasProducto,
  RespuestaProveedores,
} from '../types/catalog'

const API_URL =
  import.meta.env.VITE_API_URL ??
  'http://127.0.0.1:5000/api'

interface RespuestaError {
  mensaje?: string
  msg?: string
}

async function solicitud<T>(
  ruta: string,
  token: string,
  opciones: RequestInit = {},
): Promise<T> {
  const respuesta = await fetch(`${API_URL}${ruta}`, {
    ...opciones,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(opciones.body
        ? { 'Content-Type': 'application/json' }
        : {}),
      ...opciones.headers,
    },
  })

  let datos: T | RespuestaError

  try {
    datos = (await respuesta.json()) as T | RespuestaError
  } catch {
    throw new Error(
      'El servidor devolvió una respuesta no válida.',
    )
  }

  if (!respuesta.ok) {
    const error = datos as RespuestaError
    throw new Error(
      error.mensaje ??
        error.msg ??
        'No se pudo completar la operación.',
    )
  }

  return datos as T
}

const cuerpo = (datos: unknown) => JSON.stringify(datos)

export interface ProductoLimitesStock {
  id_producto: number
  codigo: string
  nombre: string
  categoria: string
  unidad: string
  stock_minimo: number
  stock_maximo: number | null
  activo: boolean
}

export const obtenerLimitesStock = (token: string) =>
  solicitud<{ id_local: number; productos: ProductoLimitesStock[] }>('/catalogos/limites-stock', token)

export const guardarLimitesStock = (
  token: string, id: number, stock_minimo: number, stock_maximo: number,
) => solicitud<MensajeRespuesta>(`/catalogos/limites-stock/${id}`, token, {
  method: 'PUT', body: cuerpo({ stock_minimo, stock_maximo }),
})

export const obtenerProductosCatalogo = (token: string) =>
  solicitud<RespuestaCatalogoProductos>(
    '/catalogos/productos',
    token,
  )

export const obtenerCategoriasProducto = (token: string) =>
  solicitud<RespuestaCategoriasProducto>(
    '/catalogos/categorias-productos',
    token,
  )

export const obtenerProveedores = (token: string) =>
  solicitud<RespuestaProveedores>(
    '/catalogos/proveedores',
    token,
  )

export const crearProducto = (
  token: string,
  datos: ProductoEntrada,
) =>
  solicitud<MensajeRespuesta>('/catalogos/productos', token, {
    method: 'POST',
    body: cuerpo(datos),
  })

export const editarProducto = (
  token: string,
  id: number,
  datos: ProductoEntrada,
) =>
  solicitud<MensajeRespuesta>(
    `/catalogos/productos/${id}`,
    token,
    { method: 'PUT', body: cuerpo(datos) },
  )

export const consultarDependenciasProducto = (
  token: string,
  id: number,
) =>
  solicitud<DependenciasProducto>(
    `/catalogos/productos/${id}/dependencias`,
    token,
  )

export const cambiarEstadoProducto = (
  token: string,
  id: number,
  activo: boolean,
  motivo: string,
) =>
  solicitud<MensajeRespuesta>(
    `/catalogos/productos/${id}/${
      activo ? 'reactivar' : 'desactivar'
    }`,
    token,
    { method: 'PATCH', body: cuerpo({ motivo }) },
  )

export const crearCategoria = (
  token: string,
  datos: CategoriaEntrada,
) =>
  solicitud<MensajeRespuesta>(
    '/catalogos/categorias-productos',
    token,
    { method: 'POST', body: cuerpo(datos) },
  )

export const editarCategoria = (
  token: string,
  id: number,
  datos: CategoriaEntrada,
) =>
  solicitud<MensajeRespuesta>(
    `/catalogos/categorias-productos/${id}`,
    token,
    { method: 'PUT', body: cuerpo(datos) },
  )

export const consultarDependenciasCategoria = (
  token: string,
  id: number,
) =>
  solicitud<DependenciasCategoria>(
    `/catalogos/categorias-productos/${id}/dependencias`,
    token,
  )

export const reasignarCategoria = (
  token: string,
  id: number,
  datos: ReasignacionEntrada,
) =>
  solicitud<MensajeRespuesta>(
    `/catalogos/categorias-productos/${id}/reasignar`,
    token,
    { method: 'POST', body: cuerpo(datos) },
  )

export const cambiarEstadoCategoria = (
  token: string,
  id: number,
  activo: boolean,
  motivo: string,
) =>
  solicitud<MensajeRespuesta>(
    `/catalogos/categorias-productos/${id}/${
      activo ? 'reactivar' : 'desactivar'
    }`,
    token,
    { method: 'PATCH', body: cuerpo({ motivo }) },
  )

export const crearProveedor = (
  token: string,
  datos: ProveedorEntrada,
) =>
  solicitud<MensajeRespuesta>('/catalogos/proveedores', token, {
    method: 'POST',
    body: cuerpo(datos),
  })

export const editarProveedor = (
  token: string,
  id: number,
  datos: ProveedorEntrada,
) =>
  solicitud<MensajeRespuesta>(
    `/catalogos/proveedores/${id}`,
    token,
    { method: 'PUT', body: cuerpo(datos) },
  )

export const consultarDependenciasProveedor = (
  token: string,
  id: number,
) =>
  solicitud<DependenciasProveedor>(
    `/catalogos/proveedores/${id}/dependencias`,
    token,
  )

export const reasignarProveedor = (
  token: string,
  id: number,
  datos: ReasignacionEntrada,
) =>
  solicitud<MensajeRespuesta>(
    `/catalogos/proveedores/${id}/reasignar`,
    token,
    { method: 'POST', body: cuerpo(datos) },
  )

export const cambiarEstadoProveedor = (
  token: string,
  id: number,
  activo: boolean,
  motivo: string,
) =>
  solicitud<MensajeRespuesta>(
    `/catalogos/proveedores/${id}/${
      activo ? 'reactivar' : 'desactivar'
    }`,
    token,
    { method: 'PATCH', body: cuerpo({ motivo }) },
  )
