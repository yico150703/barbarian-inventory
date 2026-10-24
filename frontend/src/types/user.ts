export interface PerfilGestionable {
  id_perfil: number
  nombre: string
  puede_crear: boolean
  puede_editar: boolean
}

export interface PerfilUsuario {
  id_perfil: number
  nombre: string
}

export interface PuestoLaboral {
  id_puesto_laboral: number
  nombre: string
  descripcion: string | null
}

export interface LocalGestionable {
  id_local: number
  codigo: string
  nombre: string
  direccion: string | null
}

export interface LocalUsuario {
  id_local: number
  codigo: string
  nombre: string
}

export interface UsuarioGestionable {
  id_usuario: number
  dni: string
  nombres: string
  apellido_paterno: string
  apellido_materno: string | null
  celular: string
  correo_electronico: string
  estado_registro: number
  fecha_creacion: string
  ids_perfiles: number[]
  perfiles: PerfilUsuario[]
  ids_puestos_laborales: number[]
  puestos_laborales: PuestoLaboral[]
  ids_locales: number[]
  locales: LocalUsuario[]
}

export interface RespuestaUsuarios {
  usuarios: UsuarioGestionable[]
  perfiles_permitidos: PerfilGestionable[]
  puestos_laborales: PuestoLaboral[]
  locales: LocalGestionable[]
  id_local_activo: number
  resumen: {
    total: number
    activos: number
    inactivos: number
  }
}

export interface DatosUsuario {
  pin_salon?: string
  revocar_pin_salon?: boolean
  dni: string
  nombres: string
  apellido_paterno: string
  apellido_materno: string
  celular: string
  correo_electronico: string
  clave: string
  ids_perfiles: number[]
  ids_puestos_laborales: number[]
  ids_locales: number[]
}
