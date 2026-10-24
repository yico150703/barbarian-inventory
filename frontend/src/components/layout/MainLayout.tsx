import { useState } from 'react'
import { Outlet, Navigate, useLocation } from 'react-router-dom'

import { Sidebar } from './Sidebar'
import { Topbar } from './Topbar'
import { useAuth } from '../../context/AuthContext'

import './MainLayout.css'

export function MainLayout() {
  const { token, cambiandoLocal, cambiandoPerfil, perfilActivo } = useAuth()
  const { pathname } = useLocation()
  const bloqueado = ![2, 3, 4].includes(perfilActivo?.id_perfil ?? 0)
    && (pathname === '/home/stock' || ['/home/inventarios/', '/home/movimientos/', '/home/ordenes-compra/', '/home/recepciones/'].some(ruta => pathname.startsWith(ruta)))
  const [sidebarMovilAbierto, setSidebarMovilAbierto] =
    useState(false)

  return (
    <div className="main-layout">
      <Sidebar
        abiertoEnMovil={sidebarMovilAbierto}
        cerrarEnMovil={() => setSidebarMovilAbierto(false)}
      />

      <div className="main-layout__right">
        <Topbar
          abrirMenu={() => setSidebarMovilAbierto(true)}
        />

        <div className="main-layout__content">
          {cambiandoLocal || cambiandoPerfil ? (
            <p role="status">Cambiando sesión…</p>
          ) : (
            bloqueado ? <Navigate to="/home" replace /> : <Outlet key={token} />
          )}
        </div>
      </div>
    </div>
  )
}
