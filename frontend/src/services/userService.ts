import type {
  DatosUsuario,
  RespuestaUsuarios,
} from '../types/user'

const API_URL =
  import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'

async function procesar<T>(respuesta: Response): Promise<T> {
  const datos = (await respuesta.json().catch(() => ({}))) as T & {
    mensaje?: string
    msg?: string
  }

  if (!respuesta.ok) {
    throw new Error(
      datos.mensaje ?? datos.msg ?? 'No se pudo completar la operación.',
    )
  }

  return datos
}

function headers(token: string) {
  return {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  }
}

export async function obtenerUsuarios(token: string) {
  return procesar<RespuestaUsuarios>(
    await fetch(`${API_URL}/usuarios`, {
      headers: headers(token),
    }),
  )
}

export async function crearUsuario(
  token: string,
  datos: DatosUsuario,
) {
  return procesar<{ mensaje: string; id_usuario: number }>(
    await fetch(`${API_URL}/usuarios`, {
      method: 'POST',
      headers: headers(token),
      body: JSON.stringify(datos),
    }),
  )
}

export async function editarUsuario(
  token: string,
  idUsuario: number,
  datos: DatosUsuario,
) {
  return procesar<{ mensaje: string }>(
    await fetch(`${API_URL}/usuarios/${idUsuario}`, {
      method: 'PUT',
      headers: headers(token),
      body: JSON.stringify(datos),
    }),
  )
}

export async function cambiarEstadoUsuario(
  token: string,
  idUsuario: number,
  estado: number,
) {
  return procesar<{ mensaje: string }>(
    await fetch(`${API_URL}/usuarios/${idUsuario}/estado`, {
      method: 'PATCH',
      headers: headers(token),
      body: JSON.stringify({ estado_registro: estado }),
    }),
  )
}