import type {
  DatosRegistrarOrden,
  EstadoOrdenCompra,
  FiltrosOrdenes,
  OrdenCompraHistorial,
  RespuestaDetalleOrden,
  RespuestaFormularioOrden,
  RespuestaPedidoSugerido,
} from '../types/purchaseOrder'

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

const autorizacion = (token: string) => ({
  Authorization: `Bearer ${token}`,
})

export async function obtenerFormularioOrden(token: string) {
  return procesar<RespuestaFormularioOrden>(
    await fetch(`${API_URL}/ordenes-compra/formulario`, {
      headers: autorizacion(token),
    }),
  )
}

export async function obtenerPedidoSugerido(token: string) {
  return procesar<RespuestaPedidoSugerido>(
    await fetch(`${API_URL}/ordenes-compra/pedido-sugerido`, {
      headers: autorizacion(token),
    }),
  )
}

export async function registrarOrdenCompra(
  token: string,
  datos: DatosRegistrarOrden,
) {
  return procesar<{
    mensaje: string
    orden: {
      id_orden_compra: number
      codigo: string
      estado_orden_compra: EstadoOrdenCompra
    }
  }>(
    await fetch(`${API_URL}/ordenes-compra`, {
      method: 'POST',
      headers: {
        ...autorizacion(token),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(datos),
    }),
  )
}

export async function obtenerHistorialOrdenes(
  token: string,
  filtros: FiltrosOrdenes = {},
) {
  const parametros = new URLSearchParams()
  if (filtros.fecha_desde) parametros.set('fecha_desde', filtros.fecha_desde)
  if (filtros.fecha_hasta) parametros.set('fecha_hasta', filtros.fecha_hasta)
  if (filtros.estado) parametros.set('estado', filtros.estado)

  const consulta = parametros.toString()
  const url = `${API_URL}/ordenes-compra/historial${
    consulta ? `?${consulta}` : ''
  }`

  return procesar<{ ordenes: OrdenCompraHistorial[] }>(
    await fetch(url, { headers: autorizacion(token) }),
  )
}

export async function obtenerDetalleOrden(token: string, idOrden: number) {
  return procesar<RespuestaDetalleOrden>(
    await fetch(`${API_URL}/ordenes-compra/${idOrden}`, {
      headers: autorizacion(token),
    }),
  )
}

export async function cambiarEstadoOrden(
  token: string,
  idOrden: number,
  accion: 'CANCELAR' | 'CERRAR_INCOMPLETA',
  motivo: string,
) {
  return procesar<{
    mensaje: string
    estado_orden_compra: EstadoOrdenCompra
  }>(
    await fetch(`${API_URL}/ordenes-compra/${idOrden}/estado`, {
      method: 'PATCH',
      headers: {
        ...autorizacion(token),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ accion, motivo }),
    }),
  )
}