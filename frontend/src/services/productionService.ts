import type {
  FormularioSubproducto,
  SubproductoEntrada,
  RespuestaGruposSalsa,
  RespuestaSubproductos,
} from '../types/production'

export async function obtenerFormularioSubproducto(token: string): Promise<FormularioSubproducto> {
  return procesarRespuesta(await fetch(`${API_URL}/produccion/subproductos/formulario`, {
    headers: { Authorization: `Bearer ${token}` },
  }))
}

export async function guardarSubproducto(token: string, datos: SubproductoEntrada, id?: number): Promise<{ mensaje: string }> {
  return procesarRespuesta(await fetch(`${API_URL}/produccion/subproductos${id ? `/${id}` : ''}`, {
    method: id ? 'PUT' : 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(datos),
  }))
}

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
        'No se pudo completar la consulta.',
    )
  }

  return datos as T
}

export async function obtenerSubproductos(
  token: string,
): Promise<RespuestaSubproductos> {
  const respuesta = await fetch(
    `${API_URL}/produccion/subproductos`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  )

  return procesarRespuesta<RespuestaSubproductos>(
    respuesta,
  )
}

export async function obtenerGruposSalsa(
  token: string,
): Promise<RespuestaGruposSalsa> {
  const respuesta = await fetch(
    `${API_URL}/produccion/grupos-salsa`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  )

  return procesarRespuesta<RespuestaGruposSalsa>(
    respuesta,
  )
}
