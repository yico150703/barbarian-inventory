import type {
  RespuestaCategoriasCarta,
  RespuestaMenajes,
  RespuestaPresentacionesVenta,
} from '../types/carta'
import type { FormularioReceta } from '../types/recipe'

export type FormularioPresentacion = Pick<FormularioReceta, 'items' | 'categorias' | 'menajes' | 'tipos' | 'unidades_medida'> & { unidades: string[] }
export interface EntradaPresentacion {
  id_item_carta: number | null; nombre_item: string; id_categoria_carta: number;
  tipo_item: string; contenido: string; unidad: string; id_menaje: number; precio: string; activo: boolean;
}

export async function formularioPresentacion(token: string): Promise<FormularioPresentacion> {
  return procesarRespuesta(await fetch(`${API_URL}/carta/presentaciones/formulario`, { headers: { Authorization: `Bearer ${token}` } }))
}

export async function guardarPresentacion(token: string, datos: EntradaPresentacion, id?: number): Promise<{ mensaje: string }> {
  return procesarRespuesta(await fetch(`${API_URL}/carta/presentaciones${id ? `/${id}` : ''}`, {
    method: id ? 'PUT' : 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(datos),
  }))
}

const API_URL =
  import.meta.env.VITE_API_URL ??
  'http://127.0.0.1:5000/api'

interface RespuestaError {
  mensaje?: string
  msg?: string
}

export type AccionMenaje = 'crear' | 'editar' | 'desactivar' | 'reactivar' | 'eliminar'
export async function administrarMenaje(token: string, accion: AccionMenaje, nombre: string, id?: number): Promise<{ mensaje: string }> {
  return procesarRespuesta(await fetch(`${API_URL}/carta/menajes${accion === 'crear' ? '' : `/${id}/${accion}`}`, {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ nombre }),
  }))
}

export async function administrarCategoriaCarta(
  token: string, id: number, accion: 'crear' | 'editar' | 'reasignar' | 'desactivar' | 'reactivar',
  datos: { nombre?: string; prefijo?: string; id_categoria_nueva?: number },
): Promise<{ mensaje: string }> {
  return procesarRespuesta(await fetch(`${API_URL}/carta/categorias${accion === 'crear' ? '' : `/${id}/${accion}`}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(datos),
  }))
}

async function procesarRespuesta<T>(
  respuesta: Response,
): Promise<T> {
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
        'No se pudo completar la consulta.',
    )
  }

  return datos as T
}

export async function obtenerCategoriasCarta(
  token: string,
): Promise<RespuestaCategoriasCarta> {
  const respuesta = await fetch(
    `${API_URL}/carta/categorias`,
    {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  )

  return procesarRespuesta<RespuestaCategoriasCarta>(
    respuesta,
  )
}

export async function obtenerPresentacionesVenta(
  token: string,
): Promise<RespuestaPresentacionesVenta> {
  const respuesta = await fetch(
    `${API_URL}/carta/presentaciones`,
    {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  )

  return procesarRespuesta<RespuestaPresentacionesVenta>(
    respuesta,
  )
}

export async function obtenerMenajes(
  token: string,
): Promise<RespuestaMenajes> {
  const respuesta = await fetch(
    `${API_URL}/carta/menajes`,
    {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  )

  return procesarRespuesta<RespuestaMenajes>(respuesta)
}
