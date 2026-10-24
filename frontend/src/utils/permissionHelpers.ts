import type { OpcionMenu, Permisos } from '../types/auth'

const SIN_PERMISOS: Permisos = {
  consultar: false,
  crear: false,
  editar: false,
  revisar: false,
  cerrar: false,
  desactivar: false,
  reactivar: false,
  eliminar: false,
  configurar: false,
}

export function permisosDe(
  menu: OpcionMenu[],
  idOpcion: number,
): Permisos {
  return (
    menu.find(
      (opcion) => opcion.id_opcion_menu === idOpcion,
    )?.permisos ?? SIN_PERMISOS
  )
}