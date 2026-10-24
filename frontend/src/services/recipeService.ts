import type { FormularioReceta, RecetaEntrada, RespuestaRecetas } from '../types/recipe'

const API_BASE_URL =
  import.meta.env.VITE_API_URL ?? 'http://localhost:5000/api'

export async function obtenerRecetas(
  token: string,
): Promise<RespuestaRecetas> {
  const respuesta = await fetch(`${API_BASE_URL}/recetas`, {
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  })

  if (!respuesta.ok) {
    const errorData = (await respuesta.json().catch(() => ({}))) as {
      mensaje?: string
    }
    throw new Error(
      errorData.mensaje ?? 'Error al cargar el catálogo de recetas.',
    )
  }

  return (await respuesta.json()) as RespuestaRecetas
}

async function solicitar<T>(token: string, ruta: string, opciones: RequestInit = {}): Promise<T> {
  const respuesta = await fetch(`${API_BASE_URL}/recetas${ruta}`, {
    ...opciones,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  })
  const datos = await respuesta.json().catch(() => ({}))
  if (!respuesta.ok) throw new Error(datos.mensaje ?? datos.msg ?? 'No se pudo completar la operación.')
  return datos as T
}

export const obtenerFormularioReceta = (token: string) => solicitar<FormularioReceta>(token, '/formulario')

export const guardarReceta = (token: string, datos: RecetaEntrada, id?: number) =>
  solicitar<{ mensaje: string; id_receta: number }>(token, id === undefined ? '' : `/${id}`, {
    method: id === undefined ? 'POST' : 'PUT', body: JSON.stringify(datos),
  })
