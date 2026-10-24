import { DeleteRecordButton } from '../components/catalogs/DeleteRecordButton'
import {
  AlertTriangle,
  CheckCircle2,
  CircleOff,
  Hash,
  Layers3,
  RefreshCw,
  Search,
  ShoppingBag,
} from 'lucide-react'
import {
  useCallback,
  useEffect,
  useMemo,
  useState,
} from 'react'

import { useAuth } from '../context/AuthContext'
import { CatalogDialog } from '../components/catalogs/CatalogDialog'
import { permisosDe } from '../utils/permissionHelpers'
import {
  obtenerCategoriasCarta,
  administrarCategoriaCarta,
} from '../services/cartaService'
import type {
  RespuestaCategoriasCarta,
  CategoriaCarta,
} from '../types/carta'

import './MenuCategoriesPage.css'

type FiltroEstado = 'todas' | 'activas' | 'inactivas'

function generarSiguienteCodigo(
  prefijo: string,
  siguienteNumero: number,
) {
  return `${prefijo}-${String(siguienteNumero).padStart(
    3,
    '0',
  )}`
}

export function MenuCategoriesPage() {
  const { token, menu, perfilActivo } = useAuth()
  const permisos = permisosDe(menu, 8)
  const administrador = perfilActivo?.id_perfil === 1
  const [operacion, setOperacion] = useState<{
    categoria: CategoriaCarta | null; accion: 'crear' | 'editar' | 'reasignar' | 'desactivar' | 'reactivar'
  } | null>(null)
  const [nombre, setNombre] = useState('')
  const [prefijo, setPrefijo] = useState('')
  const [destino, setDestino] = useState('')
  const [guardando, setGuardando] = useState(false)
  const [errorModal, setErrorModal] = useState('')
  const [mensaje, setMensaje] = useState('')

  function abrir(categoria: CategoriaCarta | null, accion: NonNullable<typeof operacion>['accion']) {
    setOperacion({ categoria, accion })
    setNombre(categoria?.nombre ?? '')
    setPrefijo(categoria?.prefijo ?? '')
    setDestino('')
    setErrorModal('')
    setMensaje('')
  }

  async function guardar() {
    if (!token || !operacion || guardando) return
    setGuardando(true)
    setErrorModal('')
    try {
      const respuesta = await administrarCategoriaCarta(token, (operacion.categoria?.id_categoria_carta ?? 0),
        operacion.accion, ['crear', 'editar'].includes(operacion.accion) ? { nombre, prefijo }
          : operacion.accion === 'reasignar' ? { id_categoria_nueva: Number(destino) } : {})
      setOperacion(null)
      setMensaje(respuesta.mensaje)
      await cargarCategorias(true)
    } catch (error) {
      setErrorModal(error instanceof Error ? error.message : 'No se pudo guardar el cambio.')
    } finally {
      setGuardando(false)
    }
  }

  const [datos, setDatos] =
    useState<RespuestaCategoriasCarta | null>(null)

  const [busqueda, setBusqueda] = useState('')
  const [estado, setEstado] =
    useState<FiltroEstado>('todas')

  const [cargando, setCargando] = useState(true)
  const [actualizando, setActualizando] = useState(false)
  const [error, setError] = useState('')

  const cargarCategorias = useCallback(
    async (esActualizacion = false) => {
      if (!token) {
        setError('No existe una sesión válida.')
        setCargando(false)
        return
      }

      try {
        setError('')

        if (esActualizacion) {
          setActualizando(true)
        } else {
          setCargando(true)
        }

        const respuesta =
          await obtenerCategoriasCarta(token)

        setDatos(respuesta)
      } catch (errorDesconocido) {
        const mensaje =
          errorDesconocido instanceof Error
            ? errorDesconocido.message
            : 'No se pudieron cargar las categorías.'

        setError(mensaje)
      } finally {
        setCargando(false)
        setActualizando(false)
      }
    },
    [token],
  )

  useEffect(() => {
    void cargarCategorias()
  }, [cargarCategorias])

  const categoriasFiltradas = useMemo(() => {
    if (!datos) {
      return []
    }

    const texto = busqueda
      .trim()
      .toLocaleLowerCase('es')

    return datos.categorias.filter((categoria) => {
      const coincideBusqueda =
        texto === '' ||
        categoria.nombre
          .toLocaleLowerCase('es')
          .includes(texto) ||
        categoria.prefijo
          .toLocaleLowerCase('es')
          .includes(texto)

      const coincideEstado =
        estado === 'todas' ||
        (estado === 'activas' && categoria.activo) ||
        (estado === 'inactivas' && !categoria.activo)

      return coincideBusqueda && coincideEstado
    })
  }, [busqueda, datos, estado])

  function limpiarFiltros() {
    setBusqueda('')
    setEstado('todas')
  }

  if (cargando) {
    return (
      <section className="menu-categories-state">
        <RefreshCw
          className="menu-categories-spinner"
          aria-hidden="true"
        />

        <div>
          <h1>Cargando categorías de carta</h1>
          <p>Consultando la información registrada.</p>
        </div>
      </section>
    )
  }

  if (error && !datos) {
    return (
      <section className="menu-categories-state menu-categories-state--error">
        <AlertTriangle aria-hidden="true" />

        <div>
          <h1>No se pudieron cargar las categorías</h1>
          <p>{error}</p>

          <button
            type="button"
            onClick={() => void cargarCategorias()}
          >
            Intentar nuevamente
          </button>
        </div>
      </section>
    )
  }

  if (!datos) {
    return null
  }

  const hayFiltros =
    busqueda.trim() !== '' || estado !== 'todas'

  return (
    <section className="menu-categories-page">
      <header className="menu-categories-header">
        <div className="menu-categories-header__content">
          <span className="menu-categories-header__eyebrow">
            CATÁLOGO DE VENTA
          </span>

          <h1>Categorías de carta</h1>

          <p>
            Consulta la organización de bebidas, platos,
            entradas y demás artículos ofrecidos al cliente.
          </p>
        </div>

        <div className="menu-categories-header-actions">
        {administrador && permisos.crear && <button className="menu-categories-refresh" type="button" onClick={() => abrir(null, 'crear')}>Nueva categoría</button>}
        <button
          className="menu-categories-refresh"
          type="button"
          disabled={actualizando}
          onClick={() => void cargarCategorias(true)}
        >
          <RefreshCw
            className={
              actualizando
                ? 'menu-categories-spinner'
                : ''
            }
            aria-hidden="true"
          />

          {actualizando
            ? 'Actualizando...'
            : 'Actualizar categorías'}
        </button>
        </div>
      </header>

      <div className="menu-categories-summary">
        <article className="menu-categories-summary-card">
          <span className="menu-categories-summary-card__icon">
            <Layers3 aria-hidden="true" />
          </span>
          <div>
            <span>Total de categorías</span>
            <strong>{datos.resumen.total_categorias}</strong>
          </div>
        </article>

        <article className="menu-categories-summary-card">
          <span className="menu-categories-summary-card__icon menu-categories-summary-card__icon--active">
            <CheckCircle2 aria-hidden="true" />
          </span>
          <div>
            <span>Categorías activas</span>
            <strong>{datos.resumen.categorias_activas}</strong>
          </div>
        </article>

        <article className="menu-categories-summary-card">
          <span className="menu-categories-summary-card__icon menu-categories-summary-card__icon--items">
            <ShoppingBag aria-hidden="true" />
          </span>
          <div>
            <span>Ítems de carta</span>
            <strong>{datos.resumen.total_items}</strong>
          </div>
        </article>

        <article className="menu-categories-summary-card">
          <span className="menu-categories-summary-card__icon menu-categories-summary-card__icon--presentations">
            <Hash aria-hidden="true" />
          </span>
          <div>
            <span>Presentaciones</span>
            <strong>{datos.resumen.total_presentaciones}</strong>
          </div>
        </article>
      </div>

      {error && (
        <div className="menu-categories-warning" role="alert">
          <AlertTriangle aria-hidden="true" />
          {error}
        </div>
      )}

      <section className="menu-categories-content">
        {mensaje && <p role="status">{mensaje}</p>}
        {administrador && <p className="menu-categories-results">Para editar o desactivar una categoría con artículos, primero reasígnalos a otra categoría.</p>}
        <div className="menu-categories-content__heading">
          <div>
            <span>CLASIFICACIÓN DE LA CARTA</span>
            <h2>Listado de categorías</h2>
          </div>
          <p>Códigos e información asociada.</p>
        </div>

        <div className="menu-categories-filters">
          <label className="menu-categories-search">
            <Search aria-hidden="true" />
            <input
              type="search"
              value={busqueda}
              onChange={(evento) =>
                setBusqueda(evento.target.value)
              }
              placeholder="Buscar por nombre o prefijo"
              aria-label="Buscar categorías de carta"
            />
          </label>

          <select
            value={estado}
            onChange={(evento) =>
              setEstado(
                evento.target.value as FiltroEstado,
              )
            }
            aria-label="Filtrar por estado"
          >
            <option value="todas">Todos los estados</option>
            <option value="activas">Activas</option>
            <option value="inactivas">Inactivas</option>
          </select>

          <button
            className="menu-categories-clear"
            type="button"
            disabled={!hayFiltros}
            onClick={limpiarFiltros}
          >
            Limpiar
          </button>
        </div>

        <p className="menu-categories-results">
          Mostrando{' '}
          <strong>{categoriasFiltradas.length}</strong>{' '}
          de <strong>{datos.categorias.length}</strong>{' '}
          categorías
        </p>

        <div className="menu-categories-table-wrap" role="region" aria-label="Listado de categorías de carta" tabIndex={0}>
          <table className="menu-categories-table">
            <thead>
              <tr>
                <th scope="col">Prefijo</th>
                <th scope="col">Categoría</th>
                <th scope="col" className="is-number">Ítems</th>
                <th scope="col" className="is-number">Ítems activos</th>
                <th scope="col" className="is-number">Presentaciones</th>
                <th scope="col">Siguiente código</th>
                <th scope="col">Estado</th>
                {administrador && <th scope="col">Acciones</th>}
              </tr>
            </thead>
            <tbody>
              {categoriasFiltradas.map((categoria) => (
                <tr key={categoria.id_categoria_carta}>
                  <td><span className="menu-category-prefix">{categoria.prefijo}</span></td>
                  <th scope="row">{categoria.nombre}</th>
                  <td className="is-number">{categoria.total_items}</td>
                  <td className="is-number">{categoria.items_activos}</td>
                  <td className="is-number">{categoria.total_presentaciones}</td>
                  <td className="menu-category-code">
                    {generarSiguienteCodigo(categoria.prefijo, categoria.siguiente_numero)}
                  </td>
                  <td>
                    <span className={`menu-category-status ${categoria.activo ? 'is-active' : 'is-inactive'}`}>
                      {categoria.activo ? 'Activa' : 'Inactiva'}
                    </span>
                  </td>
                  {administrador && <td>
                    <div className="catalog-admin-actions">{permisos.eliminar && <DeleteRecordButton token={token} entidad="categorias-carta" id={categoria.id_categoria_carta} nombre={categoria.nombre} eliminado={() => void cargarCategorias(true)} />}
                      {permisos.editar && <>
                        <button type="button" disabled={categoria.total_items > 0}
                          title={categoria.total_items > 0 ? 'Reasigna todos sus artículos antes de editar' : 'Editar categoría'}
                          onClick={() => abrir(categoria, 'editar')}>Editar</button>
                        {categoria.total_items > 0 && <button type="button"
                          onClick={() => abrir(categoria, 'reasignar')}>Reasignar artículos</button>}
                      </>}
                      {categoria.activo && permisos.desactivar && <button type="button" className="danger"
                        disabled={categoria.total_items > 0}
                        title={categoria.total_items > 0 ? 'Reasigna todos sus artículos antes de desactivar' : 'Desactivar categoría'}
                        onClick={() => abrir(categoria, 'desactivar')}>Desactivar</button>}
                      {!categoria.activo && permisos.reactivar && <button type="button"
                        onClick={() => abrir(categoria, 'reactivar')}>Reactivar</button>}
                    </div>
                  </td>}
                </tr>
              ))}
              {categoriasFiltradas.length === 0 && (
                <tr>
                  <td colSpan={administrador ? 8 : 7}>
                    <div className="menu-categories-empty">
                      <CircleOff aria-hidden="true" />
                      <strong>No se encontraron categorías</strong>
                      <span>Modifica o limpia los filtros.</span>
                    </div>
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
      <CatalogDialog abierto={operacion !== null} procesando={guardando}
        titulo={operacion?.accion === 'crear' ? 'Nueva categoría de carta' : operacion?.accion === 'reasignar' ? 'Reasignar artículos' : operacion?.accion === 'editar' ? 'Editar categoría' : operacion?.accion === 'desactivar' ? 'Desactivar categoría' : 'Reactivar categoría'}
        cerrar={() => setOperacion(null)} guardar={guardar}>
        {errorModal && <p role="alert">{errorModal}</p>}
        {(operacion?.accion === 'crear' || operacion?.accion === 'editar') ? <>
          <label>Nombre<input required maxLength={100} value={nombre} onChange={e => setNombre(e.target.value)} /></label>
          <label>Prefijo<input required maxLength={5} pattern="[A-Za-z]{1,5}" value={prefijo} onChange={e => setPrefijo(e.target.value.toUpperCase())} /></label>
        </> : operacion?.accion === 'reasignar' ? <>
          <p>Se trasladarán los {operacion.categoria?.total_items} artículos de <strong>{operacion.categoria?.nombre}</strong>, incluidos los inactivos. Se conservarán sus códigos, recetas y presentaciones.</p>
          <label>Categoría de destino
            <select required value={destino} onChange={e => setDestino(e.target.value)}>
              <option value="">Seleccionar categoría</option>
              {datos.categorias.filter(c => c.activo && c.id_categoria_carta !== (operacion.categoria?.id_categoria_carta ?? 0))
                .map(c => <option key={c.id_categoria_carta} value={c.id_categoria_carta}>{c.nombre}</option>)}
            </select>
          </label>
          {!datos.categorias.some(c => c.activo && c.id_categoria_carta !== (operacion.categoria?.id_categoria_carta ?? 0)) && <p>No hay otra categoría activa disponible.</p>}
        </> : <p>Confirma que deseas {operacion?.accion} la categoría <strong>{operacion?.categoria?.nombre}</strong>.</p>}
      </CatalogDialog>
    </section>
  )
}
