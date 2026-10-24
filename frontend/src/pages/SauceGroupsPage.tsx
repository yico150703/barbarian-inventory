import { formatearUnidad } from '../utils/unitHelpers'
import {
  AlertTriangle,
  CheckCircle2,
  ChevronDown,
  CircleOff,
  RefreshCw,
  Search,
  Soup,
  Utensils,
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
  obtenerGruposSalsa,
} from '../services/productionService'
import type {
  RespuestaGruposSalsa,
} from '../types/production'

import './ProductionCatalogPages.css'

type EstadoFiltro = 'todos' | 'activos' | 'inactivos'

function numero(valor: number) {
  return new Intl.NumberFormat('es-PE', {
    maximumFractionDigits: 3,
  }).format(valor)
}

export function SauceGroupsPage() {
  const { token } = useAuth()
  const [datos, setDatos] =
    useState<RespuestaGruposSalsa | null>(null)
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
        setDatos(await obtenerGruposSalsa(token))
      } catch (desconocido) {
        setError(
          desconocido instanceof Error
            ? desconocido.message
            : 'No se pudieron cargar los grupos.',
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

    return (datos?.grupos_salsa ?? []).filter((item) => {
      const coincideTexto =
        !texto ||
        item.codigo_item.toLocaleLowerCase('es').includes(texto) ||
        item.item_carta.toLocaleLowerCase('es').includes(texto) ||
        item.opciones.some((opcion) =>
          opcion.producto.toLocaleLowerCase('es').includes(texto),
        )

      const coincideEstado =
        estado === 'todos' ||
        (estado === 'activos' && item.activo) ||
        (estado === 'inactivos' && !item.activo)

      return coincideTexto && coincideEstado
    })
  }, [busqueda, datos, estado])

  if (cargando) {
    return <section className="production-state"><RefreshCw className="production-spin" /><div><h1>Cargando grupos de salsa</h1><p>Consultando opciones permitidas.</p></div></section>
  }

  if (error && !datos) {
    return <section className="production-state production-state--error"><AlertTriangle /><div><h1>No se pudieron cargar los grupos</h1><p>{error}</p><button type="button" onClick={() => void cargar()}>Intentar nuevamente</button></div></section>
  }

  if (!datos) return null

  return (
    <section className="production-page">
      <header className="production-header">
        <div><span>RECETAS Y PRODUCCIÓN</span><h1>Grupos de salsa</h1><p>Consulta qué presentaciones permiten elegir salsas y la cantidad máxima autorizada.</p></div>
        <button type="button" disabled={actualizando} onClick={() => void cargar(true)}><RefreshCw className={actualizando ? 'production-spin' : ''} />{actualizando ? 'Actualizando...' : 'Actualizar'}</button>
      </header>

      <div className="production-summary">
        <article><span><Soup /></span><div><small>Grupos</small><strong>{datos.resumen.total_grupos}</strong></div></article>
        <article><span className="green"><CheckCircle2 /></span><div><small>Activos</small><strong>{datos.resumen.grupos_activos}</strong></div></article>
        <article><span className="red"><CircleOff /></span><div><small>Inactivos</small><strong>{datos.resumen.grupos_inactivos}</strong></div></article>
        <article><span className="yellow"><Utensils /></span><div><small>Salsas diferentes</small><strong>{datos.resumen.salsas_diferentes}</strong></div></article>
      </div>

      <section className="production-content">
        <div className="production-title"><div><span>PERSONALIZACIÓN DE CARTA</span><h2>Presentaciones con salsa</h2></div><p>Despliega una fila para ver sus opciones.</p></div>

        <div className="production-filters">
          <label><Search /><input value={busqueda} onChange={(e) => setBusqueda(e.target.value)} placeholder="Buscar artículo, código o salsa" /></label>
          <select value={estado} onChange={(e) => setEstado(e.target.value as EstadoFiltro)}><option value="todos">Todos los estados</option><option value="activos">Activos</option><option value="inactivos">Inactivos</option></select>
          <button type="button" onClick={() => { setBusqueda(''); setEstado('todos') }}>Limpiar</button>
        </div>

        <p className="production-results">Mostrando <strong>{filtrados.length}</strong> de <strong>{datos.grupos_salsa.length}</strong></p>

        <div className="production-table-wrap">
          <table className="production-table">
            <thead><tr><th>Código</th><th>Artículo</th><th>Presentación</th><th>Máximo</th><th>Opciones</th><th>Estado</th><th>Detalle</th></tr></thead>
            <tbody>
              {filtrados.map((item) => {
                const estaAbierto = abierto === item.id_grupo_salsa
                return (
                  <Fragment key={item.id_grupo_salsa}>
                    <tr>
                      <td><b className="production-code">{item.codigo_item}</b></td>
                      <td><strong>{item.item_carta}</strong><small className="production-subtext">{item.categoria_carta}</small></td>
                      <td>{numero(item.contenido)} {formatearUnidad(item.unidad_presentacion)}</td>
                      <td>{item.cantidad_maxima} {item.cantidad_maxima === 1 ? 'salsa' : 'salsas'}</td>
                      <td>{item.total_opciones}</td>
                      <td><span className={item.activo ? 'production-status active' : 'production-status inactive'}>{item.activo ? 'Activo' : 'Inactivo'}</span></td>
                      <td><button className="production-detail-button" type="button" onClick={() => setAbierto(estaAbierto ? null : item.id_grupo_salsa)}><ChevronDown className={estaAbierto ? 'open' : ''} /></button></td>
                    </tr>
                    {estaAbierto && (
                      <tr className="production-detail-row">
                        <td colSpan={7}>
                          <div className="production-detail">
                            <strong>Opciones permitidas para {item.item_carta}</strong>
                            <div className="production-chips">
                              {item.opciones.map((opcion, indice) => (
                                <span className={opcion.es_sin_salsa ? 'special' : ''} key={opcion.id_producto ?? `sin-salsa-${indice}`}>
                                  <b>{opcion.producto}</b>
                                  {!opcion.es_sin_salsa && opcion.cantidad !== null
                                    ? `${numero(opcion.cantidad)} ${formatearUnidad(opcion.unidad)}`
                                    : 'Sin consumo de producto'}
                                </span>
                              ))}
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
    </section>
  )
}
