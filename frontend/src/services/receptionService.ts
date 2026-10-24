import type {
  DatosRegistrarRecepcion,
  RespuestaPendientesRecepcion,
  DatosCorregirRecepcion,
  RecepcionHistorial,
  RespuestaDetalleRecepcion,
} from '../types/reception'

const API_URL =
  import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'

async function procesar<T>(respuesta: Response): Promise<T> {
  const datos = await respuesta.json().catch(() => ({})) as {
    mensaje?: string
    msg?: string
  } & T
  if (!respuesta.ok) {
    throw new Error(
      datos.mensaje ?? datos.msg ?? 'No se pudo completar la operación.',
    )
  }
  return datos
}

export async function obtenerPendientesRecepcion(token: string) {
  return procesar<RespuestaPendientesRecepcion>(
    await fetch(`${API_URL}/recepciones/pendientes`, {
      headers: { Authorization: `Bearer ${token}` },
    }),
  )
}

export async function registrarRecepcion(
  token: string,
  idOrden: number,
  datos: DatosRegistrarRecepcion,
) {
  return procesar<{
    mensaje: string
    id_factura_recepcion: number
    estado_orden_compra: string
  }>(
    await fetch(
      `${API_URL}/recepciones/ordenes/${idOrden}/recepciones`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(datos),
      },
    ),
  )
}

export async function obtenerHistorialRecepciones(
  token: string,
  filtros: {
    fecha_desde?: string
    fecha_hasta?: string
    id_proveedor?: number
  } = {},
) {
  const parametros = new URLSearchParams()
  if (filtros.fecha_desde) parametros.set('fecha_desde', filtros.fecha_desde)
  if (filtros.fecha_hasta) parametros.set('fecha_hasta', filtros.fecha_hasta)
  if (filtros.id_proveedor) {
    parametros.set('id_proveedor', String(filtros.id_proveedor))
  }

  const consulta = parametros.toString()
  const url = `${API_URL}/recepciones/historial${
    consulta ? `?${consulta}` : ''
  }`

  return procesar<{ recepciones: RecepcionHistorial[] }>(
    await fetch(url, {
      headers: { Authorization: `Bearer ${token}` },
    }),
  )
}

export async function obtenerDetalleRecepcion(
  token: string,
  idFactura: number,
) {
  return procesar<RespuestaDetalleRecepcion>(
    await fetch(`${API_URL}/recepciones/${idFactura}`, {
      headers: { Authorization: `Bearer ${token}` },
    }),
  )
}

export async function corregirRecepcion(
  token: string,
  idFactura: number,
  datos: DatosCorregirRecepcion,
) {
  return procesar<{
    mensaje: string
    estado_orden_compra: string
  }>(
    await fetch(`${API_URL}/recepciones/${idFactura}`, {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(datos),
    }),
  )
}