import { useMemo } from 'react'
import { NavLink } from 'react-router-dom'
import { X, LayoutGrid, Bot, Store } from 'lucide-react'

import { useAuth } from '../../context/AuthContext'
import {
  construirArbolMenu,
  type OpcionMenuConHijos,
} from '../../utils/menuHelpers'

import barbarianLogo from '../../assets/brand/barbarian-logo.png'
import barbarianWordmark from '../../assets/brand/barbarian-wordmark.png'

import { SidebarItem } from './SidebarItem'

interface SidebarProps {
  abiertoEnMovil: boolean
  cerrarEnMovil: () => void
}

export function Sidebar({
  abiertoEnMovil,
  cerrarEnMovil,
}: SidebarProps) {
  const { menu, perfilActivo } = useAuth()

  const menuJerarquico: OpcionMenuConHijos[] = useMemo(
    () => {
      const opciones = menu.filter(o => [2, 3, 4].includes(perfilActivo?.id_perfil ?? 0) || ![15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 31, 32, 36, 37, 38].includes(o.id_opcion_menu))
      const movimientos = opciones.find(o => o.id_opcion_menu === 20 && o.permisos.consultar)
      if (movimientos) opciones.push({...movimientos, id_opcion_menu: -20, codigo: 'SEGUIMIENTO_MOVIMIENTOS', nombre: 'Prestamos y devoluciones', url_menu: '/home/movimientos/seguimiento', orden: movimientos.orden + 1})
      return construirArbolMenu(opciones)
    },
    [menu, perfilActivo]
  )

  return (
    <>
      <div
        className={`sidebar-overlay ${
          abiertoEnMovil ? 'sidebar-overlay--visible' : ''
        }`}
        onClick={cerrarEnMovil}
        aria-hidden="true"
      />

      <aside
        className={`sidebar ${
          abiertoEnMovil ? 'sidebar--mobile-open' : ''
        }`}
      >
        <header className="sidebar-brand">
          <div className="sidebar-brand__images">
            <img
              className="sidebar-brand__logo"
              src={barbarianLogo}
              alt=""
              aria-hidden="true"
            />

            <img
              className="sidebar-brand__wordmark"
              src={barbarianWordmark}
              alt="Barbarian"
            />
          </div>

          <button
            className="sidebar-brand__close"
            type="button"
            onClick={cerrarEnMovil}
            aria-label="Cerrar menú"
          >
            <X aria-hidden="true" />
          </button>
        </header>

        <nav
          className="sidebar-navigation"
          aria-label="Menú principal"
        >
          {menuJerarquico.length > 0 || perfilActivo ? (
            <ul className="sidebar-menu">
              {perfilActivo?.id_perfil === 1 && menu.some(m => m.id_opcion_menu === 2 && m.permisos.consultar) &&
                <li className="sidebar-item"><NavLink to="/home/tiendas" onClick={cerrarEnMovil} className={({ isActive }) => `sidebar-link ${isActive ? 'sidebar-link--active' : ''}`}><span className="sidebar-link__main"><Store className="sidebar-link__icon" aria-hidden="true" /><span className="sidebar-link__text">Tiendas</span></span></NavLink></li>}
              {perfilActivo && <li className="sidebar-item"><NavLink to="/home/asistente-ia" onClick={cerrarEnMovil} className={({isActive})=>`sidebar-link ${isActive?'sidebar-link--active':''}`}><span className="sidebar-link__main"><Bot className="sidebar-link__icon" aria-hidden="true"/><span className="sidebar-link__text">Asistente IA</span></span></NavLink></li>}
              {perfilActivo?.id_perfil===2 && <li className="sidebar-item"><NavLink to="/home/opciones-salon" onClick={cerrarEnMovil} className={({isActive})=>`sidebar-link ${isActive?'sidebar-link--active':''}`}><span className="sidebar-link__main"><LayoutGrid className="sidebar-link__icon" aria-hidden="true"/><span className="sidebar-link__text">Opciones de salón</span></span></NavLink></li>}
              {menuJerarquico.map((opcion) => (
                <SidebarItem
                  key={opcion.id_opcion_menu}
                  opcion={opcion}
                  alNavegar={cerrarEnMovil}
                />
              ))}
            </ul>
          ) : (
            <p className="sidebar-empty">
              No tienes opciones disponibles.
            </p>
          )}
        </nav>

        <footer className="sidebar-footer">
          <span className="sidebar-footer__indicator" />

          <div>
            <strong>Sistema conectado</strong>
            <small>Barbarian Inventory</small>
          </div>
        </footer>
      </aside>
    </>
  )
}
