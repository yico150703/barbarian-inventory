import type {
  RespuestaCerrarInventario,
  RespuestaGuardarInventario,
  RespuestaIniciarInventario,
  RespuestaInventarioActual,
  ResumenInventario,
  SolicitudCerrarInventario,
  SolicitudGuardarInventario,
  SolicitudIniciarInventario,
} from '../types/inventory'

import type { RespuestaStock } from '../types/stock'

import type {
  DatosRegistrarRevision,
  RespuestaDetalleRevision,
  RespuestaInventariosRevision,
    DatosCorregirInventario,
  RespuestaHistorialCorrecciones,
} from '../types/inventoryReview'



const API_URL =
  import.meta.env.VITE_API_URL ??
  'http://127.0.0.1:5000/api'

interface RespuestaError {
  mensaje?: string
  msg?: string
}

async function procesarRespuesta<T>(
  respuesta: Response,
): Promise<T> {
  const datos = (await respuesta.json()) as
    | T
    | RespuestaError

  if (!respuesta.ok) {
    const error = datos as RespuestaError

    throw new Error(
      error.mensaje ??
        error.msg ??
        'No se pudo completar la consulta.',
    )
  }

  return datos as T
}

export async function obtenerResumenInventario(
  token: string,
): Promise<ResumenInventario> {
  const respuesta = await fetch(
    `${API_URL}/inventarios/resumen`,
    {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  )

  return procesarRespuesta<ResumenInventario>(respuesta)
}

export async function obtenerStockActual(
  token: string,
): Promise<RespuestaStock> {
  const respuesta = await fetch(
    `${API_URL}/inventarios/stock`,
    {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  )

  return procesarRespuesta<RespuestaStock>(respuesta)
}

export async function obtenerInventarioActual(
  token: string,
): Promise<RespuestaInventarioActual> {
  const respuesta = await fetch(
    `${API_URL}/inventarios/actual`,
    {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  )

  return procesarRespuesta<RespuestaInventarioActual>(
    respuesta,
  )
}

export async function iniciarInventarioActual(
  token: string,
  datos: SolicitudIniciarInventario,
): Promise<RespuestaIniciarInventario> {
  const respuesta = await fetch(
    `${API_URL}/inventarios/actual/iniciar`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(datos),
    },
  )

  return procesarRespuesta<RespuestaIniciarInventario>(
    respuesta,
  )
}

export async function guardarInventarioActual(
  token: string,
  datos: SolicitudGuardarInventario,
): Promise<RespuestaGuardarInventario> {
  const respuesta = await fetch(
    `${API_URL}/inventarios/actual/guardar`,
    {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(datos),
    },
  )

  return procesarRespuesta<RespuestaGuardarInventario>(
    respuesta,
  )
}

export async function cerrarInventarioActual(
  token: string,
  datos: SolicitudCerrarInventario,
): Promise<RespuestaCerrarInventario> {
  const respuesta = await fetch(
    `${API_URL}/inventarios/actual/cerrar`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(datos),
    },
  )

  return procesarRespuesta<RespuestaCerrarInventario>(
    respuesta,
  )
}

export async function obtenerInventariosRevision(
  token: string,
): Promise<RespuestaInventariosRevision> {
  const respuesta = await fetch(
    `${API_URL}/inventarios/revisiones`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  )

  return procesarRespuesta<RespuestaInventariosRevision>(
    respuesta,
  )
}

export async function obtenerDetalleRevision(
  token: string,
  idInventario: number,
): Promise<RespuestaDetalleRevision> {
  const respuesta = await fetch(
    `${API_URL}/inventarios/revisiones/${idInventario}`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  )

  return procesarRespuesta<RespuestaDetalleRevision>(
    respuesta,
  )
}

export async function guardarRevisionInventario(
  token: string,
  idInventario: number,
  datos: DatosRegistrarRevision,
): Promise<RespuestaDetalleRevision> {
  const respuesta = await fetch(
    `${API_URL}/inventarios/revisiones/${idInventario}`,
    {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(datos),
    },
  )

  return procesarRespuesta<RespuestaDetalleRevision>(
    respuesta,
  )
}

export async function corregirInventario(
  token: string,
  idInventario: number,
  datos: DatosCorregirInventario,
): Promise<RespuestaDetalleRevision> {
  const respuesta = await fetch(
    `${API_URL}/inventarios/revisiones/${idInventario}/corregir`,
    {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(datos),
    },
  )

  return procesarRespuesta<RespuestaDetalleRevision>(
    respuesta,
  )
}


export async function obtenerHistorialCorrecciones(
  token: string,
  idInventario: number,
): Promise<RespuestaHistorialCorrecciones> {
  const respuesta = await fetch(
    `${API_URL}/inventarios/revisiones/${idInventario}/correcciones`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  )

  return procesarRespuesta<RespuestaHistorialCorrecciones>(
    respuesta,
  )
}