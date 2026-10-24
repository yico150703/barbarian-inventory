import type {
  RespuestaLogin,
  RespuestaSesion,
  RespuestaSesionActiva,
} from '../types/auth'

const API_URL =
  import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'

interface RespuestaError {
  mensaje?: string
  msg?: string
}

async function procesarRespuesta<T>(respuesta: Response): Promise<T> {
  const datos = await respuesta.json().catch(() => ({})) as T | RespuestaError

  if (!respuesta.ok) {
    const error = datos as RespuestaError
    throw new Error(
      error.mensaje ?? error.msg ?? 'No se pudo completar la operación',
    )
  }

  return datos as T
}

export async function iniciarSesion(
  correo: string,
  clave: string,
): Promise<RespuestaLogin> {
  const respuesta = await fetch(`${API_URL}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ correo, clave }),
  })

  return procesarRespuesta<RespuestaLogin>(respuesta)
}

export async function cambiarPerfilActivo(
  token: string,
  idPerfil: number,
  idPuestoLaboral?: number,
): Promise<RespuestaSesionActiva> {
  const respuesta = await fetch(`${API_URL}/auth/cambiar-perfil`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      id_perfil: idPerfil,
      id_puesto_laboral: idPuestoLaboral ?? null,
    }),
  })

  return procesarRespuesta<RespuestaSesionActiva>(respuesta)
}

export async function cambiarLocalActivo(
  token: string,
  idLocal: number,
): Promise<RespuestaSesionActiva> {
  const respuesta = await fetch(`${API_URL}/auth/cambiar-local`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ id_local: idLocal }),
  })

  return procesarRespuesta<RespuestaSesionActiva>(respuesta)
}

export async function obtenerSesion(
  token: string,
): Promise<RespuestaSesion> {
  const respuesta = await fetch(`${API_URL}/auth/me`, {
    headers: { Authorization: `Bearer ${token}` },
  })

  return procesarRespuesta<RespuestaSesion>(respuesta)
}