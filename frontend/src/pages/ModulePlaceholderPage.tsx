import { Construction } from 'lucide-react'
import { useLocation } from 'react-router-dom'

import { useAuth } from '../context/AuthContext'

export function ModulePlaceholderPage() {
  const location = useLocation()
  const { menu } = useAuth()

  const opcionActual = menu.find(
    (opcion) => opcion.url_menu === location.pathname
  )

  const titulo = opcionActual?.nombre ?? 'Módulo'
  const descripcion =
    opcionActual?.descripcion ??
    'Esta pantalla se encuentra en construcción.'

  return (
    <section className="module-placeholder">
      <div className="module-placeholder__icon">
        <Construction aria-hidden="true" />
      </div>

      <div>
        <span className="module-placeholder__label">
          MÓDULO DEL SISTEMA
        </span>

        <h1>{titulo}</h1>

        <p>{descripcion}</p>

        <small>
          La opción y sus permisos ya fueron cargados
          correctamente desde la base de datos.
        </small>
      </div>
    </section>
  )
}