import type {
  RespuestaPromociones,
} from '../types/promotion'

const API_URL =
  import.meta.env.VITE_API_URL ??
  'http://127.0.0.1:5000/api'

export interface PresentacionPromocion {
  id_presentacion_venta: number; codigo: string; nombre: string; contenido: number; unidad: string; menaje: string; activo: boolean;
}
export interface PromocionEntrada {
  nombre: string; precio: string; activo: boolean; hora_inicio: string | null; hora_fin: string | null;
  grupos: { id_promocion_grupo?: number; cantidad_elegir: number; permite_repetir: boolean; opciones: number[] }[];
  reposiciones: number[];
}
export async function formularioPromocion(token: string): Promise<{ presentaciones: PresentacionPromocion[] }> {
  return procesarRespuesta(await fetch(`${API_URL}/promociones/formulario`, { headers: { Authorization: `Bearer ${token}` } }))
}
export async function guardarPromocion(token: string, datos: PromocionEntrada, id?: number): Promise<{ mensaje: string }> {
  return procesarRespuesta(await fetch(`${API_URL}/promociones${id ? `/${id}` : ''}`, {
    method: id ? 'PUT' : 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(datos),
  }))
}

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

export async function obtenerPromociones(
  token: string,
): Promise<RespuestaPromociones> {
  const respuesta = await fetch(
    `${API_URL}/promociones`,
    {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  )

  return procesarRespuesta<RespuestaPromociones>(
    respuesta,
  )
}
