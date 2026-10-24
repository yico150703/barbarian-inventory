import {
  Pencil,
  Plus,
  Search,
  UserCheck,
  UserX,
  X,
} from 'lucide-react'
import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type FormEvent,
} from 'react'

import { useAuth } from '../context/AuthContext'
import {
  cambiarEstadoUsuario,
  crearUsuario,
  editarUsuario,
  obtenerUsuarios,
} from '../services/userService'
import type {
  DatosUsuario,
  PerfilGestionable,
  RespuestaUsuarios,
  UsuarioGestionable,
} from '../types/user'
import './UsersPage.css'

const ID_PERFIL_ADMINISTRADOR = 1
const ID_PERFIL_MIEMBRO_EQUIPO = 4
const DOMINIO_CORPORATIVO = '@barbarian.pe'

function obtenerNombreCorreo(correo: string): string {
  return correo
    .trim()
    .toLowerCase()
    .split('@')[0]
    .replace(/[^a-z0-9._-]/g, '')
}

const formularioVacio: DatosUsuario = {
  dni: '',
  nombres: '',
  apellido_paterno: '',
  apellido_materno: '',
  celular: '',
  correo_electronico: '',
  clave: '',
  ids_perfiles: [],
  ids_puestos_laborales: [],
  ids_locales: [],
}

export function UsersPage() {
  const { token, perfilActivo } = useAuth()
  const puedeAsignarLocales = perfilActivo?.id_perfil === ID_PERFIL_ADMINISTRADOR
  const [datos, setDatos] = useState<RespuestaUsuarios | null>(null)
  const [formulario, setFormulario] =
    useState<DatosUsuario>(formularioVacio)
  const [editando, setEditando] =
    useState<UsuarioGestionable | null>(null)
  const [modal, setModal] = useState(false)
  const [busqueda, setBusqueda] = useState('')
  const [error, setError] = useState('')
  const [mensaje, setMensaje] = useState('')
  const [cargando, setCargando] = useState(true)
  const [guardando, setGuardando] = useState(false)

  const cargar = useCallback(async () => {
    if (!token) return

    try {
      setCargando(true)
      setError('')
      setDatos(await obtenerUsuarios(token))
    } catch (errorDesconocido) {
      setError(
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se cargaron los usuarios.',
      )
    } finally {
      setCargando(false)
    }
  }, [token])

  useEffect(() => {
    void cargar()
  }, [cargar])

  const usuarios = useMemo(() => {
    const texto = busqueda.trim().toLowerCase()

    return (datos?.usuarios ?? []).filter((usuario) => {
      const perfiles = usuario.perfiles
        .map((perfil) => perfil.nombre)
        .join(' ')
        .toLowerCase()

      return (
        !texto ||
        usuario.dni.includes(texto) ||
        usuario.nombres.toLowerCase().includes(texto) ||
        usuario.apellido_paterno.toLowerCase().includes(texto) ||
        usuario.correo_electronico.toLowerCase().includes(texto) ||
        perfiles.includes(texto) ||
        usuario.puestos_laborales.some((puesto) =>
          puesto.nombre.toLowerCase().includes(texto),
        )
      )
    })
  }, [busqueda, datos])

  const perfilesDisponibles = useMemo(() => {
    const perfiles = datos?.perfiles_permitidos ?? []

    return perfiles.filter((perfil) =>
      editando ? perfil.puede_editar : perfil.puede_crear,
    )
  }, [datos, editando])

  const tienePerfilMiembro = formulario.ids_perfiles.includes(
    ID_PERFIL_MIEMBRO_EQUIPO,
  )

  const permiteSalon = formulario.ids_perfiles.some(id => [2,3].includes(id)) || tienePerfilMiembro && (datos?.puestos_laborales ?? []).some(
    puesto => formulario.ids_puestos_laborales.includes(puesto.id_puesto_laboral)
      && ['mesero', 'bartender'].includes(puesto.nombre.trim().toLowerCase()),
  )

  const cerrarModal = () => {
    if (guardando) return

    setModal(false)
    setEditando(null)
  }

  const abrirNuevo = () => {
    setEditando(null)
    setError('')
    setMensaje('')
    setFormulario({
      ...formularioVacio,
      ids_locales: datos ? [datos.id_local_activo] : [],
    })
    setModal(true)
  }

  const abrirEditar = (usuario: UsuarioGestionable) => {
    setEditando(usuario)
    setError('')
    setMensaje('')
    setFormulario({
      dni: usuario.dni,
      nombres: usuario.nombres,
      apellido_paterno: usuario.apellido_paterno,
      apellido_materno: usuario.apellido_materno ?? '',
      celular: usuario.celular,
      correo_electronico: obtenerNombreCorreo(
        usuario.correo_electronico,
      ),
      clave: '',
      ids_perfiles: [...usuario.ids_perfiles],
      ids_puestos_laborales: [...usuario.ids_puestos_laborales],
      ids_locales: [...usuario.ids_locales],
    })
    setModal(true)
  }

  const cambiarSeleccionPerfil = (perfil: PerfilGestionable) => {
    const seleccionado = formulario.ids_perfiles.includes(
      perfil.id_perfil,
    )

    const idsPerfiles = seleccionado
      ? formulario.ids_perfiles.filter(
          (idPerfil) => idPerfil !== perfil.id_perfil,
        )
      : [...formulario.ids_perfiles, perfil.id_perfil].sort(
          (primero, segundo) => primero - segundo,
        )

    setFormulario({
      ...formulario,
      ids_perfiles: idsPerfiles,
      ids_puestos_laborales:
        perfil.id_perfil === ID_PERFIL_MIEMBRO_EQUIPO && seleccionado
          ? []
          : formulario.ids_puestos_laborales,
    })
  }

  const cambiarSeleccionPuesto = (idPuesto: number) => {
    const seleccionado = formulario.ids_puestos_laborales.includes(idPuesto)
    setFormulario({
      ...formulario,
      ids_puestos_laborales: seleccionado
        ? formulario.ids_puestos_laborales.filter((id) => id !== idPuesto)
        : [...formulario.ids_puestos_laborales, idPuesto].sort((a, b) => a - b),
    })
  }

  const cambiarSeleccionLocal = (idLocal: number) => {
    if (!puedeAsignarLocales) return

    setFormulario((actual) => ({
      ...actual,
      ids_locales: actual.ids_locales.includes(idLocal)
        ? actual.ids_locales.filter((id) => id !== idLocal)
        : [...actual.ids_locales, idLocal].sort((a, b) => a - b),
    }))
  }

  const guardar = async (evento: FormEvent) => {
    evento.preventDefault()

    if (!token) return

    if (formulario.ids_locales.length === 0) {
      setError('Selecciona al menos un local.')
      return
    }

    if (formulario.ids_perfiles.length === 0) {
      setError('Selecciona al menos un perfil.')
      return
    }

    if (tienePerfilMiembro && formulario.ids_puestos_laborales.length === 0) {
      setError('Selecciona al menos un puesto del miembro de equipo.')
      return
    }
    const nombreCorreo = obtenerNombreCorreo(
      formulario.correo_electronico,
    )

    if (!/^[a-z0-9][a-z0-9._-]*$/.test(nombreCorreo)) {
      setError(
        'El usuario del correo debe comenzar con una letra o número.',
      )
      return
    }

    const datosParaEnviar: DatosUsuario = {
      ...formulario,
      pin_salon: permiteSalon ? formulario.pin_salon : '',
      revocar_pin_salon: permiteSalon ? formulario.revocar_pin_salon : false,
      correo_electronico:
        `${nombreCorreo}${DOMINIO_CORPORATIVO}`,
    }
    try {
      setGuardando(true)
      setError('')
      setMensaje('')

      const respuesta = editando
        ? await editarUsuario(
            token,
            editando.id_usuario,
            datosParaEnviar,
          )
        : await crearUsuario(
            token,
            datosParaEnviar,
          )

      setMensaje(respuesta.mensaje)
      setModal(false)
      setEditando(null)
      await cargar()
    } catch (errorDesconocido) {
      setError(
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se guardó el usuario.',
      )
    } finally {
      setGuardando(false)
    }
  }

  const cambiarEstado = async (usuario: UsuarioGestionable) => {
    if (!token) return

    const accion = usuario.estado_registro === 1
      ? 'desactivar'
      : 'activar'

    if (
      !window.confirm(
        `¿Confirmas que deseas ${accion} a ${usuario.nombres} ${usuario.apellido_paterno}?`,
      )
    ) {
      return
    }

    try {
      setError('')
      setMensaje('')

      const nuevoEstado = usuario.estado_registro === 1 ? 0 : 1
      const respuesta = await cambiarEstadoUsuario(
        token,
        usuario.id_usuario,
        nuevoEstado,
      )

      setMensaje(respuesta.mensaje)
      await cargar()
    } catch (errorDesconocido) {
      setError(
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se actualizó el estado.',
      )
    }
  }

  return (
    <section className="users-page">
      <header className="users-header">
        <span>GESTIÓN DE PERSONAL</span>
        <h1>Usuarios</h1>
        <p>Administra perfiles de acceso, puestos laborales y locales.</p>
      </header>

      {error && <div className="users-alert error">{error}</div>}
      {mensaje && <div className="users-alert ok">{mensaje}</div>}

      <div className="users-summary">
        <article>
          <b>{datos?.resumen.total ?? 0}</b>
          <span>Total</span>
        </article>
        <article>
          <b>{datos?.resumen.activos ?? 0}</b>
          <span>Activos</span>
        </article>
        <article>
          <b>{datos?.resumen.inactivos ?? 0}</b>
          <span>Inactivos</span>
        </article>
      </div>

      <section className="users-card">
        <div className="users-tools">
          <label>
            <Search />
            <input
              value={busqueda}
              onChange={(evento) => setBusqueda(evento.target.value)}
              placeholder="Buscar por DNI, nombre, perfil o puesto"
            />
          </label>

          <button type="button" onClick={abrirNuevo} disabled={cargando || !datos}>
            <Plus />
            Nuevo usuario
          </button>
        </div>

        <div className="users-table">
          <table>
            <thead>
              <tr>
                <th>DNI</th>
                <th>Usuario</th>
                <th>Correo</th>
                <th>Perfiles</th>
                <th>Puesto</th>
                <th>Estado</th>
                <th>Acciones</th>
              </tr>
            </thead>

            <tbody>
              {usuarios.map((usuario) => (
                <tr key={usuario.id_usuario}>
                  <td>{usuario.dni}</td>
                  <td>
                    <b>
                      {usuario.nombres} {usuario.apellido_paterno}
                    </b>
                    <small className="users-mobile-detail">
                      {usuario.celular}
                    </small>
                  </td>
                  <td>{usuario.correo_electronico}</td>
                  <td>
                    <div className="users-profile-tags">
                      {usuario.perfiles.map((perfil) => (
                        <span key={perfil.id_perfil}>{perfil.nombre}</span>
                      ))}
                    </div>
                  </td>
                  <td>
                    {usuario.puestos_laborales.length
                      ? usuario.puestos_laborales.map((puesto) => puesto.nombre).join(', ')
                      : 'No aplica'}
                  </td>
                  <td>
                    <span
                      className={`users-status ${
                        usuario.estado_registro === 1
                          ? 'is-active'
                          : 'is-inactive'
                      }`}
                    >
                      {usuario.estado_registro === 1
                        ? 'Activo'
                        : 'Inactivo'}
                    </span>
                  </td>
                  <td>
                    <div className="users-actions">
                      <button
                        type="button"
                        onClick={() => abrirEditar(usuario)}
                        title="Editar"
                      >
                        <Pencil />
                      </button>
                      <button
                        type="button"
                        onClick={() => void cambiarEstado(usuario)}
                        title={
                          usuario.estado_registro === 1
                            ? 'Desactivar'
                            : 'Activar'
                        }
                      >
                        {usuario.estado_registro === 1
                          ? <UserX />
                          : <UserCheck />}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}

              {!cargando && usuarios.length === 0 && (
                <tr>
                  <td colSpan={7} className="empty">
                    No se encontraron usuarios.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

      {modal && (
        <div className="users-modal-backdrop">
          <form
            className="users-modal users-modal--wide"
            onSubmit={(evento) => void guardar(evento)}
          >
            <div className="users-modal-title">
              <div>
                <h2>{editando ? 'Editar usuario' : 'Nuevo usuario'}</h2>
                <p>
                  Asigna sus datos, perfiles de acceso, puestos laborales y locales.
                </p>
              </div>

              <button type="button" onClick={cerrarModal}>
                <X />
              </button>
            </div>

            {error && <div className="users-alert error" role="alert">{error}</div>}

            <div className="users-form">
              <label>
                DNI
                <input
                  value={formulario.dni}
                  maxLength={8}
                  inputMode="numeric"
                  onChange={(evento) =>
                    setFormulario({
                      ...formulario,
                      dni: evento.target.value.replace(/\D/g, ''),
                    })
                  }
                  required
                />
              </label>

              <label>
                Nombres
                <input
                  value={formulario.nombres}
                  onChange={(evento) =>
                    setFormulario({
                      ...formulario,
                      nombres: evento.target.value,
                    })
                  }
                  required
                />
              </label>

              <label>
                Apellido paterno
                <input
                  value={formulario.apellido_paterno}
                  onChange={(evento) =>
                    setFormulario({
                      ...formulario,
                      apellido_paterno: evento.target.value,
                    })
                  }
                  required
                />
              </label>

              <label>
                Apellido materno
                <input
                  value={formulario.apellido_materno}
                  onChange={(evento) =>
                    setFormulario({
                      ...formulario,
                      apellido_materno: evento.target.value,
                    })
                  }
                />
              </label>

              <label>
                Celular
                <input
                  value={formulario.celular}
                  inputMode="numeric"
                  onChange={(evento) =>
                    setFormulario({
                      ...formulario,
                      celular: evento.target.value.replace(/\D/g, ''),
                    })
                  }
                  required
                />
              </label>

              <label>
                Correo corporativo

                <div className="users-corporate-email">
                  <input
                    type="text"
                    value={formulario.correo_electronico}
                    maxLength={40}
                    autoComplete="off"
                    spellCheck={false}
                    placeholder="crodriguez"
                    onChange={(evento) =>
                      setFormulario({
                        ...formulario,
                        correo_electronico: obtenerNombreCorreo(
                          evento.target.value,
                        ),
                      })
                    }
                    required
                  />

                  <span>{DOMINIO_CORPORATIVO}</span>
                </div>
              </label>

              {permiteSalon && <fieldset className="users-form-password">
                <legend>Acceso rápido a Salón</legend>
                <label>PIN de 4 dígitos
                  <input type="password" inputMode="numeric" autoComplete="new-password" pattern="[0-9]{4}" maxLength={4}
                    value={formulario.pin_salon ?? ''} disabled={formulario.revocar_pin_salon}
                    placeholder={editando ? 'Vacío para conservar el PIN actual' : 'Opcional: asignar PIN de Salón'}
                    onChange={e => setFormulario({...formulario,pin_salon:e.target.value.replace(/[^0-9]/g,'')})} />
                </label>
                <p>Para gerente, supervisor, meseros y bartender. Independiente del acceso de gestión.</p>
                {editando && <label><input type="checkbox" checked={formulario.revocar_pin_salon ?? false}
                  onChange={e => setFormulario({...formulario,revocar_pin_salon:e.target.checked,pin_salon:''})} /> Revocar acceso por PIN</label>}
              </fieldset>}

              <label className="users-form-password">
                Contraseña
                <input
                  type="password"
                  value={formulario.clave}
                  onChange={(evento) =>
                    setFormulario({
                      ...formulario,
                      clave: evento.target.value,
                    })
                  }
                  required={!editando}
                  placeholder={
                    editando
                      ? 'Vacío para conservar la contraseña'
                      : 'Mínimo 8 caracteres'
                  }
                />
              </label>

              <fieldset className="users-profile-fieldset">
                <legend>Perfiles de acceso</legend>
                <p>
                  Puedes seleccionar uno o varios perfiles para esta persona.
                </p>

                <div className="users-profile-options">
                  {perfilesDisponibles.map((perfil) => (
                    <label key={perfil.id_perfil}>
                      <input
                        type="checkbox"
                        checked={formulario.ids_perfiles.includes(
                          perfil.id_perfil,
                        )}
                        onChange={() => cambiarSeleccionPerfil(perfil)}
                      />
                      <span>{perfil.nombre}</span>
                    </label>
                  ))}
                </div>
              </fieldset>

              <fieldset className="users-profile-fieldset" disabled={guardando}>
                <legend>Locales asignados</legend>
                <p>
                  {puedeAsignarLocales
                    ? 'Selecciona uno o varios locales para esta persona.'
                    : 'Solo puedes asignar usuarios al local activo. Para cambiar otros locales, solicita a un administrador.'}
                </p>
                <div className="users-profile-options">
                  {datos?.locales.filter((local) =>
                    puedeAsignarLocales ||
                    local.id_local === datos.id_local_activo ||
                    formulario.ids_locales.includes(local.id_local),
                  ).map((local) => (
                    <label key={local.id_local}>
                      <input
                        type="checkbox"
                        checked={formulario.ids_locales.includes(local.id_local)}
                        disabled={!puedeAsignarLocales}
                        onChange={() => cambiarSeleccionLocal(local.id_local)}
                      />
                      <span>{local.nombre}</span>
                    </label>
                  ))}
                </div>
              </fieldset>

              {tienePerfilMiembro && (
                <fieldset className="users-profile-fieldset">
                  <legend>Puestos de miembro de equipo</legend>
                  <p>Puedes seleccionar uno o varios puestos.</p>
                  <div className="users-profile-options">
                    {datos?.puestos_laborales.map((puesto) => (
                      <label key={puesto.id_puesto_laboral}>
                        <input
                          type="checkbox"
                          checked={formulario.ids_puestos_laborales.includes(
                            puesto.id_puesto_laboral,
                          )}
                          onChange={() =>
                            cambiarSeleccionPuesto(puesto.id_puesto_laboral)
                          }
                        />
                        <span>{puesto.nombre}</span>
                      </label>
                    ))}
                  </div>
                </fieldset>
              )}
            </div>

            <div className="users-modal-buttons">
              <button type="button" onClick={cerrarModal}>
                Cancelar
              </button>
              <button className="save" disabled={guardando}>
                {guardando ? 'Guardando...' : 'Guardar usuario'}
              </button>
            </div>
          </form>
        </div>
      )}
    </section>
  )
}
