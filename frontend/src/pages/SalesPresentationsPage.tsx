import { formatearUnidad } from '../utils/unitHelpers'
import { DeleteRecordButton } from '../components/catalogs/DeleteRecordButton'
import {
  AlertTriangle,
  CheckCircle2,
  CircleOff,
  GlassWater,
  Layers3,
  RefreshCw,
  Search,
  Utensils,
} from 'lucide-react'
import {
  useCallback,
  useEffect,
  useMemo,
  useState,
} from 'react'

import { useAuth } from '../context/AuthContext'
import { PresentationEditor } from '../components/catalogs/PresentationEditor'
import { permisosDe } from '../utils/permissionHelpers'
import {
  obtenerPresentacionesVenta,
} from '../services/cartaService'
import type {
  RespuestaPresentacionesVenta,
  PresentacionVenta,
} from '../types/carta'

import './CartaCatalogPages.css'

type EstadoFiltro = 'todos' | 'activos' | 'inactivos'

function formatearNumero(valor: number) {
  return new Intl.NumberFormat('es-PE', {
    maximumFractionDigits: 3,
  }).format(valor)
}

function formatearPrecio(valor: number) {
  return new Intl.NumberFormat('es-PE', {
    style: 'currency',
    currency: 'PEN',
  }).format(valor)
}

export function SalesPresentationsPage() {
  const { token, menu } = useAuth()
  const permisos = permisosDe(menu, 9)
  const [editor, setEditor] = useState(false)
  const [seleccionada, setSeleccionada] = useState<PresentacionVenta | null>(null)
  const [mensaje, setMensaje] = useState('')
  const [datos, setDatos] =
    useState<RespuestaPresentacionesVenta | null>(null)
  const [busqueda, setBusqueda] = useState('')
  const [categoria, setCategoria] = useState('todas')
  const [menaje, setMenaje] = useState('todos')
  const [estado, setEstado] =
    useState<EstadoFiltro>('todos')
  const [cargando, setCargando] = useState(true)
  const [actualizando, setActualizando] = useState(false)
  const [error, setError] = useState('')

  const cargar = useCallback(
    async (actualizacion = false) => {
      if (!token) {
        setError('No existe una sesión válida.')
        setCargando(false)
        return
      }

      try {
        setError('')
        actualizacion
          ? setActualizando(true)
          : setCargando(true)
        setDatos(await obtenerPresentacionesVenta(token))
      } catch (desconocido) {
        setError(
          desconocido instanceof Error
            ? desconocido.message
            : 'No se pudieron cargar las presentaciones.',
        )
      } finally {
        setCargando(false)
        setActualizando(false)
      }
    },
    [token],
  )

  useEffect(() => {
    void cargar()
  }, [cargar])

  const categorias = useMemo(
    () => Array.from(
      new Map(
        (datos?.presentaciones ?? []).map((item) => [
          item.id_categoria_carta,
          item.categoria,
        ]),
      ),
    ).sort((a, b) => a[1].localeCompare(b[1])),
    [datos],
  )

  const menajes = useMemo(
    () => Array.from(
      new Map(
        (datos?.presentaciones ?? []).map((item) => [
          item.id_menaje,
          item.menaje,
        ]),
      ),
    ).sort((a, b) => a[1].localeCompare(b[1])),
    [datos],
  )

  const filtradas = useMemo(() => {
    const texto = busqueda.trim().toLocaleLowerCase('es')

    return (datos?.presentaciones ?? []).filter((item) => {
      const coincideTexto =
        !texto ||
        item.codigo_item.toLocaleLowerCase('es').includes(texto) ||
        item.item.toLocaleLowerCase('es').includes(texto) ||
        item.categoria.toLocaleLowerCase('es').includes(texto) ||
        item.menaje.toLocaleLowerCase('es').includes(texto)

      const coincideCategoria =
        categoria === 'todas' ||
        item.id_categoria_carta === Number(categoria)

      const coincideMenaje =
        menaje === 'todos' ||
        item.id_menaje === Number(menaje)

      const coincideEstado =
        estado === 'todos' ||
        (estado === 'activos' && item.activo) ||
        (estado === 'inactivos' && !item.activo)

      return (
        coincideTexto &&
        coincideCategoria &&
        coincideMenaje &&
        coincideEstado
      )
    })
  }, [busqueda, categoria, datos, estado, menaje])

  if (cargando) {
    return (
      <section className="carta-catalog-state">
        <RefreshCw className="carta-catalog-spin" />
        <div>
          <h1>Cargando presentaciones</h1>
          <p>Consultando la carta registrada.</p>
        </div>
      </section>
    )
  }

  if (error && !datos) {
    return (
      <section className="carta-catalog-state carta-catalog-state--error">
        <AlertTriangle />
        <div>
          <h1>No se pudieron cargar las presentaciones</h1>
          <p>{error}</p>
          <button type="button" onClick={() => void cargar()}>
            Intentar nuevamente
          </button>
        </div>
      </section>
    )
  }

  if (!datos) return null

  const limpiar = () => {
    setBusqueda('')
    setCategoria('todas')
    setMenaje('todos')
    setEstado('todos')
  }

  return (
    <section className="carta-catalog-page">
      <header className="carta-catalog-header">
        <div>
          <span className="carta-catalog-eyebrow">
            CATÁLOGO DE VENTA
          </span>
          <h1>Presentaciones de venta</h1>
          <p>
            Consulta formatos, contenidos, precios y menajes
            asociados a cada artículo de la carta.
          </p>
        </div>
        <div className="catalog-admin-actions">
        {permisos.crear && <button type="button" onClick={() => { setSeleccionada(null); setEditor(true) }}>Nueva presentación</button>}
        <button
          className="carta-catalog-refresh"
          type="button"
          disabled={actualizando}
          onClick={() => void cargar(true)}
        >
          <RefreshCw
            className={actualizando ? 'carta-catalog-spin' : ''}
          />
          {actualizando ? 'Actualizando...' : 'Actualizar'}
        </button>
        </div>
      </header>

      <div className="carta-catalog-summary">
        <article>
          <span><GlassWater /></span>
          <div>
            <small>Presentaciones</small>
            <strong>{datos.resumen.total_presentaciones}</strong>
          </div>
        </article>
        <article>
          <span className="is-green"><CheckCircle2 /></span>
          <div>
            <small>Activas</small>
            <strong>{datos.resumen.presentaciones_activas}</strong>
          </div>
        </article>
        <article>
          <span className="is-red"><CircleOff /></span>
          <div>
            <small>Inactivas</small>
            <strong>{datos.resumen.presentaciones_inactivas}</strong>
          </div>
        </article>
        <article>
          <span className="is-yellow"><Utensils /></span>
          <div>
            <small>Ítems asociados</small>
            <strong>{datos.resumen.total_items}</strong>
          </div>
        </article>
      </div>

      <section className="carta-catalog-content">
        {mensaje && <p role="status">{mensaje}</p>}
        {error && <p role="alert">{error}</p>}
        <div className="carta-catalog-title">
          <div>
            <span>LISTADO GENERAL</span>
            <h2>Presentaciones registradas</h2>
          </div>
          <p>Precios expresados en soles.</p>
        </div>

        <div className="carta-catalog-filters is-wide">
          <label>
            <Search />
            <input
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
              placeholder="Buscar código, artículo o menaje"
            />
          </label>
          <select
            value={categoria}
            onChange={(e) => setCategoria(e.target.value)}
          >
            <option value="todas">Todas las categorías</option>
            {categorias.map(([id, nombre]) => (
              <option key={id} value={id}>{nombre}</option>
            ))}
          </select>
          <select
            value={menaje}
            onChange={(e) => setMenaje(e.target.value)}
          >
            <option value="todos">Todos los menajes</option>
            {menajes.map(([id, nombre]) => (
              <option key={id} value={id}>{nombre}</option>
            ))}
          </select>
          <select
            value={estado}
            onChange={(e) =>
              setEstado(e.target.value as EstadoFiltro)
            }
          >
            <option value="todos">Todos los estados</option>
            <option value="activos">Activos</option>
            <option value="inactivos">Inactivos</option>
          </select>
          <button type="button" onClick={limpiar}>Limpiar</button>
        </div>

        <p className="carta-catalog-results">
          Mostrando <strong>{filtradas.length}</strong> de{' '}
          <strong>{datos.presentaciones.length}</strong>
        </p>

        <div className="carta-catalog-table-wrap">
          <table className="carta-catalog-table">
            <thead>
              <tr>
                <th>Código</th>
                <th>Artículo</th>
                <th>Categoría</th>
                <th>Tipo</th>
                <th>Contenido</th>
                <th>Menaje</th>
                <th>Precio</th>
                <th>Estado</th>
                {(permisos.editar || permisos.eliminar) && <th>Acciones</th>}
              </tr>
            </thead>
            <tbody>
              {filtradas.map((item) => (
                <tr key={item.id_presentacion_venta}>
                  <td><b className="carta-code">{item.codigo_item}</b></td>
                  <td><strong>{item.item}</strong></td>
                  <td><span className="carta-inline"><Layers3 />{item.categoria}</span></td>
                  <td>{item.tipo}</td>
                  <td>{formatearNumero(item.contenido)} {formatearUnidad(item.unidad)}</td>
                  <td><span className="carta-inline"><Utensils />{item.menaje}</span></td>
                  <td><strong>{formatearPrecio(item.precio)}</strong></td>
                  <td>
                    <span className={item.activo ? 'carta-status active' : 'carta-status inactive'}>
                      {item.activo ? 'Activa' : 'Inactiva'}
                    </span>
                  </td>
                  {(permisos.editar || permisos.eliminar) && <td>{permisos.editar && <><div className="catalog-admin-actions"><button type="button" onClick={() => { setSeleccionada(item); setEditor(true) }}>Editar</button></div></>}{permisos.eliminar && <DeleteRecordButton token={token} entidad="presentaciones" id={item.id_presentacion_venta} nombre={item.item} eliminado={() => void cargar(true)} />}</td>}
                </tr>
              ))}
              {filtradas.length === 0 && (
                <tr>
                  <td colSpan={(permisos.editar || permisos.eliminar) ? 9 : 8} className="carta-empty">
                    No se encontraron presentaciones.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
      {editor && token && <PresentationEditor token={token} presentacion={seleccionada} cerrar={() => setEditor(false)} guardado={texto => { setEditor(false); setMensaje(texto); void cargar(true) }} />}
    </section>
  )
}
