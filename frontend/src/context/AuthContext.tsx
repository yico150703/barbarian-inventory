import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from 'react'

import {
  cambiarLocalActivo as solicitarCambioLocal,
  cambiarPerfilActivo,
  iniciarSesion,
  obtenerSesion,
} from '../services/authService'
import type {
  LocalDisponible,
  OpcionMenu,
  PerfilDisponible,
  PuestoDisponible,
  RespuestaSesionActiva,
  Usuario,
} from '../types/auth'

interface AuthContextType {
  usuario: Usuario | null
  menu: OpcionMenu[]
  token: string | null
  perfilActivo: PerfilDisponible | null
  perfilesDisponibles: PerfilDisponible[]
  puestoActivo: PuestoDisponible | null
  puestosDisponibles: PuestoDisponible[]
  localActivo: LocalDisponible | null
  localesDisponibles: LocalDisponible[]
  cargando: boolean
  cambiandoPerfil: boolean
  cambiandoLocal: boolean
  login: (correo: string, clave: string) => Promise<void>
  cambiarPerfil: (
    idPerfil: number,
    idPuestoLaboral?: number,
  ) => Promise<void>
  cambiarLocal: (idLocal: number) => Promise<void>
  actualizarSesion: () => Promise<void>
  logout: () => void
}

export const AuthContext = createContext<AuthContextType | undefined>(
  undefined,
)

interface AuthProviderProps {
  children: ReactNode
}

export function AuthProvider({ children }: AuthProviderProps) {
  const [usuario, setUsuario] = useState<Usuario | null>(null)
  const [menu, setMenu] = useState<OpcionMenu[]>([])
  const [token, setToken] = useState<string | null>(null)
  const [perfilActivo, setPerfilActivo] =
    useState<PerfilDisponible | null>(null)
  const [perfilesDisponibles, setPerfilesDisponibles] =
    useState<PerfilDisponible[]>([])
  const [puestoActivo, setPuestoActivo] =
    useState<PuestoDisponible | null>(null)
  const [puestosDisponibles, setPuestosDisponibles] =
    useState<PuestoDisponible[]>([])
  const [localActivo, setLocalActivo] =
    useState<LocalDisponible | null>(null)
  const [localesDisponibles, setLocalesDisponibles] =
    useState<LocalDisponible[]>([])
  const [cargando, setCargando] = useState(true)
  const [cambiandoPerfil, setCambiandoPerfil] = useState(false)
  const [cambiandoLocal, setCambiandoLocal] = useState(false)

  function limpiarAlmacenamiento() {
    sessionStorage.removeItem('token')
    sessionStorage.removeItem('usuario')
    sessionStorage.removeItem('menu')
    sessionStorage.removeItem('perfil_activo')
    sessionStorage.removeItem('perfiles_disponibles')
    sessionStorage.removeItem('puesto_activo')
    sessionStorage.removeItem('puestos_disponibles')
    sessionStorage.removeItem('local_activo')
    sessionStorage.removeItem('locales_disponibles')
  }

  function limpiarSesion() {
    limpiarAlmacenamiento()
    setToken(null)
    setUsuario(null)
    setMenu([])
    setPerfilActivo(null)
    setPerfilesDisponibles([])
    setPuestoActivo(null)
    setPuestosDisponibles([])
    setLocalActivo(null)
    setLocalesDisponibles([])
  }

  function aplicarSesion(
    respuesta: RespuestaSesionActiva,
    tokenSesion: string,
  ) {
    sessionStorage.setItem('token', tokenSesion)
    sessionStorage.setItem('usuario', JSON.stringify(respuesta.usuario))
    sessionStorage.setItem('menu', JSON.stringify(respuesta.menu))
    sessionStorage.setItem(
      'perfil_activo',
      JSON.stringify(respuesta.perfil_activo),
    )
    sessionStorage.setItem(
      'perfiles_disponibles',
      JSON.stringify(respuesta.perfiles_disponibles),
    )
    sessionStorage.setItem(
      'puesto_activo',
      JSON.stringify(respuesta.puesto_activo),
    )
    sessionStorage.setItem(
      'puestos_disponibles',
      JSON.stringify(respuesta.puestos_disponibles),
    )
    sessionStorage.setItem(
      'local_activo',
      JSON.stringify(respuesta.local_activo),
    )
    sessionStorage.setItem(
      'locales_disponibles',
      JSON.stringify(respuesta.locales_disponibles),
    )

    setToken(tokenSesion)
    setUsuario(respuesta.usuario)
    setMenu(respuesta.menu)
    setPerfilActivo(respuesta.perfil_activo)
    setPerfilesDisponibles(respuesta.perfiles_disponibles)
    setPuestoActivo(respuesta.puesto_activo)
    setPuestosDisponibles(respuesta.puestos_disponibles)
    setLocalActivo(respuesta.local_activo)
    setLocalesDisponibles(respuesta.locales_disponibles)
  }

  useEffect(() => {
    async function restaurarSesion() {
      const tokenGuardado = sessionStorage.getItem('token')

      if (!tokenGuardado) {
        setCargando(false)
        return
      }

      try {
        const sesion = await obtenerSesion(tokenGuardado)
        aplicarSesion(sesion, tokenGuardado)
      } catch {
        limpiarSesion()
      } finally {
        setCargando(false)
      }
    }

    void restaurarSesion()
  }, [])

  async function login(correo: string, clave: string) {
    const respuesta = await iniciarSesion(correo, clave)

    if (!respuesta.token) {
      throw new Error('El servidor no devolvió un token de sesión')
    }

    aplicarSesion(respuesta, respuesta.token)
  }

  async function cambiarPerfil(
    idPerfil: number,
    idPuestoLaboral?: number,
  ) {
    if (!token) {
      throw new Error('No existe una sesión activa')
    }

    if (
      perfilActivo?.id_perfil === idPerfil &&
      (idPerfil !== 4 ||
        puestoActivo?.id_puesto_laboral === idPuestoLaboral)
    ) {
      return
    }

    try {
      setCambiandoPerfil(true)
      const respuesta = await cambiarPerfilActivo(
        token,
        idPerfil,
        idPuestoLaboral,
      )

      if (!respuesta.token) {
        throw new Error('El servidor no devolvió un token nuevo')
      }

      aplicarSesion(respuesta, respuesta.token)
    } finally {
      setCambiandoPerfil(false)
    }
  }

  async function cambiarLocal(idLocal: number) {
    if (!token) {
      throw new Error('No existe una sesión activa')
    }

    if (localActivo?.id_local === idLocal) return

    try {
      setCambiandoLocal(true)
      const respuesta = await solicitarCambioLocal(token, idLocal)

      if (!respuesta.token) {
        throw new Error('El servidor no devolvió un token nuevo')
      }

      aplicarSesion(respuesta, respuesta.token)
    } finally {
      setCambiandoLocal(false)
    }
  }

  function logout() {
    limpiarSesion()
  }

  async function actualizarSesion() {
    if (token) aplicarSesion(await obtenerSesion(token), token)
  }

  return (
    <AuthContext.Provider
      value={{
        usuario,
        menu,
        token,
        perfilActivo,
        perfilesDisponibles,
        puestoActivo,
        puestosDisponibles,
        localActivo,
        localesDisponibles,
        cargando,
        cambiandoPerfil,
        cambiandoLocal,
        login,
        cambiarPerfil,
        cambiarLocal,
        actualizarSesion,
        logout,
      }}
    >
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const contexto = useContext(AuthContext)

  if (!contexto) {
    throw new Error('useAuth debe utilizarse dentro de AuthProvider')
  }

  return contexto
}
