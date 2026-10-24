import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Building2,
  ChevronDown,
  LogOut,
  Menu,
  Settings,
  UserRound,
} from 'lucide-react'

import { useAuth } from '../../context/AuthContext'

interface TopbarProps {
  abrirMenu: () => void
}

export function Topbar({ abrirMenu }: TopbarProps) {
  const navigate = useNavigate()
  const {
    usuario,
    perfilActivo,
    perfilesDisponibles,
    puestoActivo,
    puestosDisponibles,
    localActivo,
    localesDisponibles,
    cambiandoPerfil,
    cambiandoLocal,
    cambiarPerfil,
    cambiarLocal,
    logout,
  } = useAuth()

  const [menuUsuarioAbierto, setMenuUsuarioAbierto] = useState(false)
  const [errorCambio, setErrorCambio] = useState('')
  const contenedorUsuario = useRef<HTMLDivElement>(null)

  const nombres = usuario?.nombres ?? ''
  const apellido = usuario?.apellido_paterno ?? ''
  const perfil = perfilActivo?.nombre ?? usuario?.perfil ?? ''
  const iniciales = `${nombres.charAt(0)}${apellido.charAt(0)}`
    .toUpperCase()
    .trim()

  useEffect(() => {
    const cerrarAlPulsarFuera = (evento: MouseEvent) => {
      if (
        contenedorUsuario.current &&
        !contenedorUsuario.current.contains(evento.target as Node)
      ) {
        setMenuUsuarioAbierto(false)
      }
    }

    document.addEventListener('mousedown', cerrarAlPulsarFuera)
    return () => document.removeEventListener('mousedown', cerrarAlPulsarFuera)
  }, [])

  const seleccionarOtroPerfil = async (
    idPerfil: number,
    idPuestoLaboral?: number,
  ) => {
    try {
      setErrorCambio('')
      await cambiarPerfil(idPerfil, idPuestoLaboral)
      setMenuUsuarioAbierto(false)
      navigate('/home', { replace: true })
    } catch (errorDesconocido) {
      setErrorCambio(
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se pudo cambiar el perfil',
      )
    }
  }

  const seleccionarOtroLocal = async (idLocal: number) => {
    if (!idLocal || idLocal === localActivo?.id_local) return

    try {
      setErrorCambio('')
      await cambiarLocal(idLocal)
      setMenuUsuarioAbierto(false)
      navigate('/home', { replace: true })
    } catch (errorDesconocido) {
      setErrorCambio(
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se pudo cambiar el local',
      )
    }
  }

  const cerrarSesion = () => {
    setMenuUsuarioAbierto(false)
    logout()
    navigate('/login', { replace: true })
  }

  return (
    <header className="topbar">
      <div className="topbar__left">
        <button
          className="topbar__menu-button"
          type="button"
          onClick={abrirMenu}
          aria-label="Abrir menú principal"
        >
          <Menu aria-hidden="true" />
        </button>

        <div className="topbar__title">
          <span>Sistema de gestión e inventario</span>
        </div>
      </div>

      {perfilesDisponibles.length > 1 && (
        <div className="topbar-role-tabs" aria-label="Perfil de trabajo">
          {perfilesDisponibles.map((opcion) => {
            const activo = opcion.id_perfil === perfilActivo?.id_perfil

            if (opcion.id_perfil === 4) {
              return (
                <label
                  key={opcion.id_perfil}
                  className={`topbar-role-tabs__member ${
                    activo ? 'is-active' : ''
                  }`}
                >
                  <span>Miembro</span>
                  <select
                    value={activo ? puestoActivo?.id_puesto_laboral ?? '' : ''}
                    disabled={cambiandoPerfil || cambiandoLocal}
                    onChange={(evento) => {
                      const idPuesto = Number(evento.target.value)
                      if (idPuesto) void seleccionarOtroPerfil(4, idPuesto)
                    }}
                  >
                    <option value="">Elegir puesto</option>
                    {puestosDisponibles.map((puesto) => (
                      <option
                        key={puesto.id_puesto_laboral}
                        value={puesto.id_puesto_laboral}
                      >
                        {puesto.nombre}
                      </option>
                    ))}
                  </select>
                </label>
              )
            }

            return (
              <button
                key={opcion.id_perfil}
                type="button"
                className={activo ? 'is-active' : ''}
                disabled={cambiandoPerfil || cambiandoLocal || activo}
                onClick={() => void seleccionarOtroPerfil(opcion.id_perfil)}
              >
                {opcion.nombre}
              </button>
            )
          })}
        </div>
      )}

      {[1, 2, 3, 4].includes(perfilActivo?.id_perfil ?? 0) && <label className="topbar-local-selector">
        <Building2 aria-hidden="true" />
        <span className="topbar-local-selector__label">Local</span>
        <select
          value={localActivo?.id_local ?? ''}
          disabled={
            cambiandoLocal ||
            cambiandoPerfil ||
            localesDisponibles.length <= 1
          }
          onChange={(evento) =>
            void seleccionarOtroLocal(Number(evento.target.value))
          }
          aria-label="Local de trabajo"
        >
          {localesDisponibles.length === 0 && (
            <option value="">Sin local</option>
          )}
          {localesDisponibles.map((local) => (
            <option key={local.id_local} value={local.id_local}>
              {local.nombre}
            </option>
          ))}
        </select>
      </label>}

      <div className="topbar-user" ref={contenedorUsuario}>
        <button
          className="topbar-user__button"
          type="button"
          onClick={() => setMenuUsuarioAbierto((estado) => !estado)}
          aria-expanded={menuUsuarioAbierto}
          aria-haspopup="menu"
        >
          <div className="topbar-user__information">
            <strong>{nombres} {apellido}</strong>
            <span>
              {perfil}
              {[2, 3, 4].includes(perfilActivo?.id_perfil ?? 0) && localActivo ? ` · ${localActivo.nombre}` : ''}
            </span>
          </div>

          <div className="topbar-user__avatar">
            {iniciales || <UserRound aria-hidden="true" />}
          </div>

          <ChevronDown
            className={`topbar-user__arrow ${
              menuUsuarioAbierto ? 'topbar-user__arrow--open' : ''
            }`}
            aria-hidden="true"
          />
        </button>

        {menuUsuarioAbierto && (
          <div className="topbar-user__dropdown" role="menu">
            <div className="topbar-user__summary">
              <div className="topbar-user__avatar topbar-user__avatar--large">
                {iniciales || <UserRound aria-hidden="true" />}
              </div>
              <div>
                <strong>{nombres} {apellido}</strong>
                <span>{usuario?.correo}</span>
                {[2, 3, 4].includes(perfilActivo?.id_perfil ?? 0) && localActivo && <small>Local: {localActivo.nombre}</small>}
              </div>
            </div>

            {errorCambio && (
              <p className="topbar-profile-selector__error">
                {errorCambio}
              </p>
            )}

            <div className="topbar-user__separator" />

            <button
              type="button"
              role="menuitem"
              onClick={() => {
                setMenuUsuarioAbierto(false)
                navigate('/home/configuracion')
              }}
            >
              <Settings aria-hidden="true" />
              Configuración
            </button>

            <button
              className="topbar-user__logout"
              type="button"
              role="menuitem"
              onClick={cerrarSesion}
            >
              <LogOut aria-hidden="true" />
              Cerrar sesión
            </button>
          </div>
        )}
      </div>
    </header>
  )
}
