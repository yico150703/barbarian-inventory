import type {
  DatosRegistrarMovimiento,
  RespuestaFormularioMovimiento,
  RespuestaRegistrarMovimiento,
} from '../types/movement'


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
  let datos: T | RespuestaError

  try {
    datos = (await respuesta.json()) as
      | T
      | RespuestaError
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

export async function obtenerFormularioMovimiento(
  token: string,
): Promise<RespuestaFormularioMovimiento> {
  const respuesta = await fetch(
    `${API_URL}/movimientos/formulario`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  )

  return procesarRespuesta<RespuestaFormularioMovimiento>(
    respuesta,
  )
}

export async function registrarMovimiento(
  token: string,
  datos: DatosRegistrarMovimiento,
): Promise<RespuestaRegistrarMovimiento> {
  const respuesta = await fetch(
    `${API_URL}/movimientos`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(datos),
    },
  )

  return procesarRespuesta<RespuestaRegistrarMovimiento>(
    respuesta,
  )
}