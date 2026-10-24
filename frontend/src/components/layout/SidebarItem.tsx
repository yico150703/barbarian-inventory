import { useEffect, useState } from 'react'
import { NavLink, useLocation } from 'react-router-dom'
import {
  BadgePercent,
  BarChart3,
  Boxes,
  ChevronDown,
  Circle,
  ClipboardCheck,
  ClipboardList,
  CookingPot,
  History,
  House,
  PackageCheck,
  PackageOpen,
  ShoppingCart,
  Users,
  Utensils,
  Warehouse,
  SlidersHorizontal,
  ArrowLeftRight,
  type LucideIcon,
} from 'lucide-react'

import type { OpcionMenuConHijos } from '../../utils/menuHelpers'

interface SidebarItemProps {
  opcion: OpcionMenuConHijos
  nivel?: number
  alNavegar?: () => void
}

const iconosPorOpcion: Record<number, LucideIcon> = {
  1: House,
  2: Users,
  3: Boxes,
  4: PackageOpen,
  7: Utensils,
  11: CookingPot,
  14: BadgePercent,
  15: Warehouse,
  16: ClipboardList,
  17: ClipboardCheck,
  19: ArrowLeftRight,
  21: ShoppingCart,
  23: PackageCheck,
  25: BarChart3,
  26: History,
  33: SlidersHorizontal,
}

function rutaPerteneceAOpcion(
  opcion: OpcionMenuConHijos,
  rutaActual: string
): boolean {
  if (
    opcion.url_menu &&
    (
      rutaActual === opcion.url_menu ||
      rutaActual.startsWith(`${opcion.url_menu}/`)
    )
  ) {
    return true
  }

  return opcion.hijos.some((hijo) =>
    rutaPerteneceAOpcion(hijo, rutaActual)
  )
}

export function SidebarItem({
  opcion,
  nivel = 0,
  alNavegar,
}: SidebarItemProps) {
  const location = useLocation()
  const tieneHijos = opcion.hijos.length > 0

  const perteneceARutaActual = rutaPerteneceAOpcion(
    opcion,
    location.pathname
  )

  const [desplegado, setDesplegado] = useState(
    perteneceARutaActual
  )

  useEffect(() => {
    if (perteneceARutaActual) {
      setDesplegado(true)
    }
  }, [perteneceARutaActual])

  const Icono = iconosPorOpcion[opcion.id_opcion_menu] ?? Circle

  if (tieneHijos) {
    return (
      <li className="sidebar-item">
        <button
          className={`sidebar-link sidebar-link--button ${
            perteneceARutaActual ? 'sidebar-link--branch-active' : ''
          }`}
          type="button"
          onClick={() => setDesplegado((estado) => !estado)}
          aria-expanded={desplegado}
        >
          <span className="sidebar-link__main">
            <Icono
              className="sidebar-link__icon"
              aria-hidden="true"
            />

            <span className="sidebar-link__text">
              {opcion.nombre}
            </span>
          </span>

          <ChevronDown
            className={`sidebar-link__chevron ${
              desplegado
                ? 'sidebar-link__chevron--open'
                : ''
            }`}
            aria-hidden="true"
          />
        </button>

        <div
          className={`sidebar-submenu ${
            desplegado ? 'sidebar-submenu--open' : ''
          }`}
        >
          <ul>
            {opcion.hijos.map((hijo) => (
              <SidebarItem
                key={hijo.id_opcion_menu}
                opcion={hijo}
                nivel={nivel + 1}
                alNavegar={alNavegar}
              />
            ))}
          </ul>
        </div>
      </li>
    )
  }

  if (!opcion.url_menu) {
    return null
  }

  return (
    <li className="sidebar-item">
      <NavLink
        to={opcion.url_menu}
        end
        onClick={alNavegar}
        className={({ isActive }) =>
          `sidebar-link ${
            isActive ? 'sidebar-link--active' : ''
          } ${nivel > 0 ? 'sidebar-link--child' : ''}`
        }
      >
        <span className="sidebar-link__main">
          <Icono
            className="sidebar-link__icon"
            aria-hidden="true"
          />

          <span className="sidebar-link__text">
            {opcion.nombre}
          </span>
        </span>
      </NavLink>
    </li>
  )
}
