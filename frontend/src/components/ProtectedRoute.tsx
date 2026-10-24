import type { ReactNode } from 'react'
import { Navigate } from 'react-router-dom'

import { useAuth } from '../context/AuthContext'


interface ProtectedRouteProps {
  children: ReactNode
}


export function ProtectedRoute({
  children,
}: ProtectedRouteProps) {
  const { usuario, cargando } = useAuth()

  if (cargando) {
    return <p>Verificando sesión...</p>
  }

  if (!usuario) {
    return <Navigate to="/login" replace />
  }

  return children
}