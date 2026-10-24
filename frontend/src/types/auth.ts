export interface Permisos {
  consultar: boolean
  crear: boolean
  editar: boolean
  revisar: boolean
  cerrar: boolean
  desactivar: boolean
  reactivar: boolean
  eliminar: boolean
  configurar: boolean
}

export interface OpcionMenu {
  id_opcion_menu: number
  codigo: string
  nombre: string
  url_menu: string | null
  descripcion: string
  id_padre: number | null
  icono: string | null
  tipo_opcion: 'GRUPO' | 'ENLACE'
  es_configurable: boolean
  orden: number
  permisos: Permisos
}

export interface PerfilDisponible {
  id_perfil: number
  nombre: string
  descripcion: string
}

export interface PuestoDisponible {
  id_puesto_laboral: number
  nombre: string
  descripcion: string | null
}

export interface LocalDisponible {
  id_local: number
  codigo: string
  nombre: string
  direccion: string | null
}

export interface Usuario {
  id_usuario: number
  dni: string
  nombres: string
  apellido_paterno: string
  apellido_materno: string | null
  correo: string
  id_puesto_laboral: number | null
  puesto_laboral: string | null
  id_perfil: number
  perfil: string
}

export interface RespuestaSesionActiva {
  mensaje?: string
  requiere_seleccion_perfil: false
  token?: string
  usuario: Usuario
  perfil_activo: PerfilDisponible
  perfiles_disponibles: PerfilDisponible[]
  puesto_activo: PuestoDisponible | null
  puestos_disponibles: PuestoDisponible[]
  local_activo: LocalDisponible
  locales_disponibles: LocalDisponible[]
  menu: OpcionMenu[]
}

export type RespuestaLogin = RespuestaSesionActiva
export type RespuestaSesion = RespuestaSesionActiva