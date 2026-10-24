import { formatearUnidad } from '../utils/unitHelpers'
import { DeleteRecordButton } from '../components/catalogs/DeleteRecordButton'
import {
  AlertTriangle,
  Beaker,
  CheckCircle2,
  ChevronDown,
  CircleOff,
  FlaskConical,
  RefreshCw,
  Search,
} from 'lucide-react'
import {
  Fragment,
  useCallback,
  useEffect,
  useMemo,
  useState,
} from 'react'

import { useAuth } from '../context/AuthContext'
import {
  obtenerSubproductos,
} from '../services/productionService'
import type {
  RespuestaSubproductos,
} from '../types/production'

import './ProductionCatalogPages.css'
import { SubproductEditor } from '../components/recipes/SubproductEditor'
import { permisosDe } from '../utils/menuHelpers'
import type { SubproductoDetalle } from '../types/production'

type EstadoFiltro = 'todos' | 'activos' | 'inactivos'

function numero(valor: number) {
  return new Intl.NumberFormat('es-PE', {
    maximumFractionDigits: 3,
  }).format(valor)
}

export function SubproductsPage() {
  const { token, menu } = useAuth()
  const permisos = permisosDe(menu, 12)
  const [editor, setEditor] = useState<SubproductoDetalle | null | undefined>(undefined)
  const [mensaje, setMensaje] = useState('')
  const [datos, setDatos] =
    useState<RespuestaSubproductos | null>(null)
  const [busqueda, setBusqueda] = useState('')
  const [estado, setEstado] =
    useState<EstadoFiltro>('todos')
  const [abierto, setAbierto] =
    useState<number | null>(null)
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
        setDatos(await obtenerSubproductos(token))
      } catch (desconocido) {
        setError(
          desconocido instanceof Error
            ? desconocido.message
            : 'No se pudieron cargar los subproductos.',
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

  const filtrados = useMemo(() => {
    const texto = busqueda.trim().toLocaleLowerCase('es')

    return (datos?.subproductos ?? []).filter((item) => {
      const coincideTexto =
        !texto ||
        item.codigo.toLocaleLowerCase('es').includes(texto) ||
        item.nombre.toLocaleLowerCase('es').includes(texto) ||
        item.ingredientes.some((ingrediente) =>
          ingrediente.producto
            .toLocaleLowerCase('es')
            .includes(texto),
        )

      const coincideEstado =
        estado === 'todos' ||
        (estado === 'activos' && item.activo) ||
        (estado === 'inactivos' && !item.activo)

      return coincideTexto && coincideEstado
    })
  }, [busqueda, datos, estado])

  if (cargando) {
    return (
      <section className="production-state">
        <RefreshCw className="production-spin" />
        <div>
          <h1>Cargando subproductos</h1>
          <p>Consultando preparaciones internas.</p>
        </div>
      </section>
    )
  }

  if (error && !datos) {
    return (
      <section className="production-state production-state--error">
        <AlertTriangle />
        <div>
          <h1>No se pudieron cargar los subproductos</h1>
          <p>{error}</p>
          <button type="button" onClick={() => void cargar()}>
            Intentar nuevamente
          </button>
        </div>
      </section>
    )
  }

  if (!datos) return null

  return (
    <section className="production-page">
      <header className="production-header">
        <div>
          <span>RECETAS Y PRODUCCIÓN</span>
          <h1>Subproductos</h1>
          <p>
            Consulta preparaciones internas, rendimientos
            e ingredientes utilizados.
          </p>
        </div>
        <div className="production-header-actions">
        {permisos.crear && <button type="button" onClick={() => { setMensaje(''); setEditor(null) }}>Nuevo subproducto</button>}
        <button
          type="button"
          disabled={actualizando}
          onClick={() => void cargar(true)}
        >
          <RefreshCw className={actualizando ? 'production-spin' : ''} />
          {actualizando ? 'Actualizando...' : 'Actualizar'}
        </button>
        </div>
      </header>
      {mensaje && <p role="status" className="production-feedback">{mensaje}</p>}
      {error && <p role="alert" className="production-feedback production-feedback--error">{error}</p>}

      <div className="production-summary">
        <article><span><FlaskConical /></span><div><small>Subproductos</small><strong>{datos.resumen.total_subproductos}</strong></div></article>
        <article><span className="green"><CheckCircle2 /></span><div><small>Activos</small><strong>{datos.resumen.subproductos_activos}</strong></div></article>
        <article><span className="red"><CircleOff /></span><div><small>Inactivos</small><strong>{datos.resumen.subproductos_inactivos}</strong></div></article>
        <article><span className="yellow"><Beaker /></span><div><small>Ingredientes distintos</small><strong>{datos.resumen.ingredientes_diferentes}</strong></div></article>
      </div>

      <section className="production-content">
        <div className="production-title">
          <div><span>PREPARACIONES INTERNAS</span><h2>Listado de subproductos</h2></div>
          <p>Despliega una fila para revisar su composición.</p>
        </div>

        <div className="production-filters">
          <label><Search /><input value={busqueda} onChange={(e) => setBusqueda(e.target.value)} placeholder="Buscar código, subproducto o ingrediente" /></label>
          <select value={estado} onChange={(e) => setEstado(e.target.value as EstadoFiltro)}>
            <option value="todos">Todos los estados</option>
            <option value="activos">Activos</option>
            <option value="inactivos">Inactivos</option>
          </select>
          <button type="button" onClick={() => { setBusqueda(''); setEstado('todos') }}>Limpiar</button>
        </div>

        <p className="production-results">Mostrando <strong>{filtrados.length}</strong> de <strong>{datos.subproductos.length}</strong></p>

        <div className="production-table-wrap">
          <table className="production-table">
            <thead><tr><th>Código</th><th>Subproducto</th><th>Rendimiento</th><th>Ingredientes</th><th>Estado</th><th>Detalle</th>{(permisos.editar || permisos.eliminar) && <th>Acciones</th>}</tr></thead>
            <tbody>
              {filtrados.map((item) => {
                const estaAbierto = abierto === item.id_subproducto
                return (
                  <Fragment key={item.id_subproducto}>
                    <tr>
                      <td><b className="production-code">{item.codigo}</b></td>
                      <td><strong>{item.nombre}</strong></td>
                      <td>{numero(item.rendimiento)} {formatearUnidad(item.unidad)}</td>
                      <td>{item.total_ingredientes}</td>
                      <td><span className={item.activo ? 'production-status active' : 'production-status inactive'}>{item.activo ? 'Activo' : 'Inactivo'}</span></td>
                      <td><button className="production-detail-button" type="button" onClick={() => setAbierto(estaAbierto ? null : item.id_subproducto)}><ChevronDown className={estaAbierto ? 'open' : ''} /></button></td>
                      {(permisos.editar || permisos.eliminar) && <td>{permisos.editar && <><button type="button" className="production-edit-button" onClick={() => { setMensaje(''); setEditor(item) }}>Editar</button></>}{permisos.eliminar && <DeleteRecordButton token={token} entidad="subproductos" id={item.id_subproducto} nombre={item.nombre} eliminado={() => void cargar(true)} />}</td>}
                    </tr>
                    {estaAbierto && (
                      <tr className="production-detail-row">
                        <td colSpan={(permisos.editar || permisos.eliminar) ? 7 : 6}>
                          <div className="production-detail">
                            <strong>Ingredientes de {item.nombre}</strong>
                            {item.instruccion && <p style={{ whiteSpace: 'pre-wrap' }}>{item.instruccion}</p>}
                            <div className="production-chips">
                              {item.ingredientes.length ? item.ingredientes.map((ingrediente) => (
                                <span key={ingrediente.id_producto}>
                                  <b>{ingrediente.producto}</b>
                                  {numero(ingrediente.cantidad)} {formatearUnidad(ingrediente.unidad)}
                                </span>
                              )) : <p>No tiene ingredientes asociados.</p>}
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </Fragment>
                )
              })}
            </tbody>
          </table>
        </div>
      </section>
      {editor !== undefined && token && <SubproductEditor token={token} subproducto={editor}
        cerrar={() => setEditor(undefined)} guardado={(texto) => {
          setEditor(undefined); setMensaje(texto); setBusqueda(''); setEstado('todos'); void cargar(true)
        }} />}
    </section>
  )
}