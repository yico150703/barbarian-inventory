import { SalonAccess } from '../components/SalonAccess'
import './SalonPage.css'
import { useState, type SyntheticEvent } from 'react'
import { Navigate, useNavigate } from 'react-router-dom'

import { useAuth } from '../context/AuthContext'

import loginBackground from '../assets/brand/login-background.png'
import barbarianLogo from '../assets/brand/barbarian-logo.png'
import barbarianWordmark from '../assets/brand/barbarian-wordmark.png'

import './LoginPage.css'

function LoginPage() {
  const navigate = useNavigate()
  const { login, token } = useAuth()

  const [area, setArea] = useState<'gestion' | 'salon'>('gestion')
  const [correo, setCorreo] = useState('')
  const [clave, setClave] = useState('')
  const [mostrarClave, setMostrarClave] = useState(false)
  const [cargando, setCargando] = useState(false)
  const [error, setError] = useState('')

  if (token) {
    return <Navigate to="/home" replace />
  }

  const enviarFormulario = async (
    evento: SyntheticEvent<HTMLFormElement>
  ) => {
    evento.preventDefault()
    setError('')

    if (!correo.trim() || !clave) {
      setError('Ingresa tu correo electrónico y contraseña.')
      return
    }

    try {
      setCargando(true)

      await login(correo.trim(), clave)

      navigate('/home', {
        replace: true,
      })
    } catch (errorDesconocido) {
      const mensaje =
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se pudo iniciar sesión.'

      setError(mensaje)
    } finally {
      setCargando(false)
    }
  }

  return (
    <main className="login-page">
      <section className="login-brand" aria-label="Barbarian">
        <img
          className="login-brand__background"
          src={loginBackground}
          alt=""
          aria-hidden="true"
        />

        <div className="login-brand__content">
          <img
            className="login-brand__logo"
            src={barbarianLogo}
            alt="Logo de Barbarian"
          />

          <img
            className="login-brand__wordmark"
            src={barbarianWordmark}
            alt="Barbarian"
          />

          <p className="login-brand__description">
            Sistema de Gestión de Inventario
          </p>
        </div>
      </section>

      <section className="login-access">
        <div className="login-card">
          <header className="login-card__header">
            <span className="login-card__eyebrow">
              ACCESO SEGURO
            </span>

            <h1>INICIAR SESIÓN</h1>

            <span className="login-card__line" />

            <p>
              Ingresa tus credenciales para acceder al sistema.
            </p>
          </header>

          <div className="login-area-selector" aria-label="?rea de trabajo">
            <button type="button" disabled={cargando} aria-pressed={area==='gestion'} onClick={() => {setArea('gestion');setError('')}}>Gestión e inventario</button>
            <button type="button" disabled={cargando} aria-pressed={area==='salon'} onClick={() => {setArea('salon');setError('');setClave('')}}>Salón</button>
          </div>
          {area === 'salon' ? <SalonAccess /> : <form
            className="login-form"
            onSubmit={enviarFormulario}
          >
            <div className="login-field">
              <label htmlFor="correo">
                Correo electrónico
              </label>

              <div className="login-input">
                <svg
                  aria-hidden="true"
                  viewBox="0 0 24 24"
                  fill="none"
                >
                  <path
                    d="M4 6h16v12H4V6Zm0 1 8 6 8-6"
                    stroke="currentColor"
                    strokeWidth="1.8"
                    strokeLinejoin="round"
                  />
                </svg>

                <input
                  id="correo"
                  name="correo"
                  type="email"
                  value={correo}
                  onChange={(evento) =>
                    setCorreo(evento.target.value)
                  }
                  placeholder="usuario@correo.com"
                  autoComplete="email"
                  disabled={cargando}
                />
              </div>
            </div>

            <div className="login-field">
              <label htmlFor="clave">
                Contraseña
              </label>

              <div className="login-input">
                <svg
                  aria-hidden="true"
                  viewBox="0 0 24 24"
                  fill="none"
                >
                  <path
                    d="M7 10V7a5 5 0 0 1 10 0v3m-11 0h12v10H6V10Z"
                    stroke="currentColor"
                    strokeWidth="1.8"
                    strokeLinejoin="round"
                  />
                </svg>

                <input
                  id="clave"
                  name="clave"
                  type={mostrarClave ? 'text' : 'password'}
                  value={clave}
                  onChange={(evento) =>
                    setClave(evento.target.value)
                  }
                  placeholder="Ingresa tu contraseña"
                  autoComplete="current-password"
                  disabled={cargando}
                />

                <button
                  className="login-input__toggle"
                  type="button"
                  onClick={() =>
                    setMostrarClave((valor) => !valor)
                  }
                  aria-label={
                    mostrarClave
                      ? 'Ocultar contraseña'
                      : 'Mostrar contraseña'
                  }
                >
                  {mostrarClave ? 'Ocultar' : 'Ver'}
                </button>
              </div>
            </div>

            {error && (
              <div className="login-error" role="alert">
                {error}
              </div>
            )}

            <button
              className="login-submit"
              type="submit"
              disabled={cargando}
            >
              {cargando ? 'INGRESANDO...' : 'INGRESAR'}
            </button>
          </form>}

          <div className="login-security">
            <span aria-hidden="true" />
            Acceso protegido y supervisado
          </div>
        </div>
      </section>
    </main>
  )
}

export default LoginPage