import type { OpcionMenu, Permisos } from '../types/auth'


export interface OpcionMenuConHijos extends OpcionMenu {
  hijos: OpcionMenuConHijos[]
}

export function construirArbolMenu(
  opciones: OpcionMenu[]
): OpcionMenuConHijos[] {
  const opcionesPorId = new Map<number, OpcionMenuConHijos>()
  const opcionesPrincipales: OpcionMenuConHijos[] = []

  const ordenInventario: Record<number, number> = { 15: 1, 33: 2, 36: 3, 37: 4, 38: 5 }
  const opcionesAgrupadas = opciones.filter(o => ![17,18].includes(o.id_opcion_menu)).map(opcion => {
    if (opcion.id_opcion_menu === 16) {
      return { ...opcion, nombre: 'Inventario', tipo_opcion: 'GRUPO' as const, url_menu: null }
    }
    if (opcion.id_opcion_menu in ordenInventario) {
      return { ...opcion, id_padre: 16, orden: ordenInventario[opcion.id_opcion_menu] }
    }
    return opcion
  })
  // Un perfil puede consultar stock sin tener asignado el antiguo grupo de cierres.
  // Crear solo el contenedor visual; sus hijos mantienen sus permisos originales.
  if (!opcionesAgrupadas.some(opcion => opcion.id_opcion_menu === 16)) {
    const hijo = opcionesAgrupadas.find(opcion => opcion.id_padre === 16)
    if (hijo) {
      opcionesAgrupadas.push({ ...hijo, id_opcion_menu: 16, codigo: 'INVENTARIO',
        nombre: 'Inventario', id_padre: null, tipo_opcion: 'GRUPO', url_menu: null,
        orden: opciones.find(opcion => opcion.id_opcion_menu === hijo.id_opcion_menu)?.orden ?? 16 })
    }
  }

  for (const opcion of opcionesAgrupadas) {
    // Las opciones de salsa se administran dentro de cada receta.
    // Filtrar tambien menus de sesiones anteriores al cambio del backend.
    if (opcion.url_menu?.replace(/\/+$/, '') === '/home/grupos-salsa') {
      continue
    }
    opcionesPorId.set(opcion.id_opcion_menu, {
      ...opcion,
      hijos: [],
    })
  }

  for (const opcion of opcionesPorId.values()) {
    const idPadre = opcion.id_padre

    if (idPadre !== null && opcionesPorId.has(idPadre)) {
      const padre = opcionesPorId.get(idPadre)

      padre?.hijos.push(opcion)
    } else {
      /*
       * Si no tiene padre o el padre no fue autorizado,
       * se muestra como una opción principal.
       */
      opcionesPrincipales.push(opcion)
    }
  }

  const ordenarOpciones = (
    elementos: OpcionMenuConHijos[]
  ): OpcionMenuConHijos[] => {
    elementos.sort(
      (primera, segunda) =>
        (primera.orden ?? 0) - (segunda.orden ?? 0)
    )

    for (const elemento of elementos) {
      ordenarOpciones(elemento.hijos)
    }

    return elementos
  }

  return ordenarOpciones(opcionesPrincipales)
}

const SIN_PERMISOS: Permisos = {
  consultar: false, crear: false, editar: false,
  revisar: false, cerrar: false, desactivar: false,
  reactivar: false, eliminar: false, configurar: false,
}

export function permisosDe(menu: OpcionMenu[], idOpcion: number): Permisos {
  return menu.find((opcion) => opcion.id_opcion_menu === idOpcion)?.permisos
    ?? SIN_PERMISOS
}
