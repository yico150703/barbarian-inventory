import { formatearUnidad } from '../utils/unitHelpers'
import {
  Fragment,
  useEffect,
  useMemo,
  useState,
} from 'react'
import {
  AlertCircle,
  AlertTriangle,
  Boxes,
  CalendarDays,
  ChevronDown,
  ChevronUp,
  CircleCheck,
  CircleX,
  PackageSearch,
  RefreshCw,
  Search,
} from 'lucide-react'

import { useAuth } from '../context/AuthContext'
import { obtenerStockActual } from '../services/inventoryService'
import type {
  EstadoStock,
  ProductoStock,
  RespuestaStock,
} from '../types/stock'

import './StockPage.css'

const etiquetasEstado: Record<EstadoStock, string> = {
  DISPONIBLE: 'Disponible',
  STOCK_BAJO: 'Stock bajo',
  AGOTADO: 'Agotado',
  SIN_CONTEO: 'Sin conteo',
}

function formatearCantidad(
  cantidad: number | null
): string {
  if (cantidad === null) {
    return 'Sin dato'
  }

  return new Intl.NumberFormat('es-PE', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  }).format(cantidad)
}

function formatearFecha(
  fecha: string | null
): string {
  if (!fecha) {
    return 'Sin conteo'
  }

  return new Intl.DateTimeFormat('es-PE', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  }).format(new Date(`${fecha}T00:00:00`))
}

function StockPage() {
  const { token } = useAuth()

  const [datos, setDatos] =
    useState<RespuestaStock | null>(null)

  const [busqueda, setBusqueda] = useState('')
  const [categoria, setCategoria] = useState('')
  const [estado, setEstado] = useState<EstadoStock | ''>('')

  const [productoExpandido, setProductoExpandido] =
    useState<number | null>(null)

  const [cargando, setCargando] = useState(true)
  const [error, setError] = useState('')

  const cargarStock = async () => {
    if (!token) {
      return
    }

    try {
      setCargando(true)
      setError('')

      const resultado = await obtenerStockActual(token)

      setDatos(resultado)
    } catch (errorDesconocido) {
      setError(
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se pudo consultar el stock actual.'
      )
    } finally {
      setCargando(false)
    }
  }

  useEffect(() => {
    void cargarStock()
  }, [token])

  const productosFiltrados = useMemo(() => {
    if (!datos) {
      return []
    }

    const texto = busqueda
      .trim()
      .toLocaleLowerCase('es-PE')

    return datos.productos.filter((producto) => {
      const coincideBusqueda =
        !texto ||
        producto.codigo
          .toLocaleLowerCase('es-PE')
          .includes(texto) ||
        producto.nombre
          .toLocaleLowerCase('es-PE')
          .includes(texto)

      const coincideCategoria =
        !categoria ||
        producto.categoria === categoria

      const coincideEstado =
        !estado ||
        producto.estado_stock === estado

      return (
        coincideBusqueda &&
        coincideCategoria &&
        coincideEstado
      )
    })
  }, [datos, busqueda, categoria, estado])

  const fechaActual = new Intl.DateTimeFormat('es-PE', {
    weekday: 'long',
    day: '2-digit',
    month: 'long',
    year: 'numeric',
  }).format(new Date())

  const limpiarFiltros = () => {
    setBusqueda('')
    setCategoria('')
    setEstado('')
  }

  if (cargando) {
    return (
      <div className="stock-loading">
        <RefreshCw aria-hidden="true" />
        <span>Calculando stock actual...</span>
      </div>
    )
  }

  if (error || !datos) {
    return (
      <div className="stock-error">
        <AlertCircle aria-hidden="true" />

        <div>
          <h2>No se pudo cargar el stock</h2>
          <p>{error}</p>

          <button type="button" onClick={cargarStock}>
            Intentar nuevamente
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="stock-page">
      <header className="stock-header">
        <div className="stock-header__content">
          <span className="stock-header__label">
            CONTROL DE EXISTENCIAS
          </span>

          <h1>Stock actual</h1>

          <p>
            Consulta el stock teórico: saldo inicial más recepciones y entradas,
            menos ventas, mermas y otras salidas del local.
          </p>
        </div>

        <div className="stock-header__date">
          <CalendarDays aria-hidden="true" />

          <div>
            <span>FECHA ACTUAL</span>
            <strong>{fechaActual}</strong>
          </div>
        </div>
      </header>

      <section className="stock-summary">
        <article className="stock-summary-card">
          <div className="stock-summary-card__icon">
            <Boxes aria-hidden="true" />
          </div>

          <div>
            <span>Total de productos</span>
            <strong>{datos.resumen.total}</strong>
          </div>
        </article>

        <article className="stock-summary-card">
          <div className="stock-summary-card__icon stock-summary-card__icon--available">
            <CircleCheck aria-hidden="true" />
          </div>

          <div>
            <span>Disponibles</span>
            <strong>{datos.resumen.disponibles}</strong>
          </div>
        </article>

        <article className="stock-summary-card">
          <div className="stock-summary-card__icon stock-summary-card__icon--warning">
            <AlertTriangle aria-hidden="true" />
          </div>

          <div>
            <span>Stock bajo</span>
            <strong>{datos.resumen.stock_bajo}</strong>
          </div>
        </article>

        <article className="stock-summary-card">
          <div className="stock-summary-card__icon stock-summary-card__icon--danger">
            <CircleX aria-hidden="true" />
          </div>

          <div>
            <span>Agotados</span>
            <strong>{datos.resumen.agotados}</strong>
          </div>
        </article>

        <article className="stock-summary-card">
          <div className="stock-summary-card__icon stock-summary-card__icon--neutral">
            <PackageSearch aria-hidden="true" />
          </div>

          <div>
            <span>Sin conteo</span>
            <strong>{datos.resumen.sin_conteo}</strong>
          </div>
        </article>
      </section>

      <section className="stock-content">
        <div className="stock-filters">
          <div className="stock-search">
            <Search aria-hidden="true" />

            <input
              type="search"
              value={busqueda}
              onChange={(evento) =>
                setBusqueda(evento.target.value)
              }
              placeholder="Buscar por código o producto"
              aria-label="Buscar producto"
            />
          </div>

          <select
            value={categoria}
            onChange={(evento) =>
              setCategoria(evento.target.value)
            }
            aria-label="Filtrar por categoría"
          >
            <option value="">Todas las categorías</option>

            {datos.categorias.map((nombreCategoria) => (
              <option
                value={nombreCategoria}
                key={nombreCategoria}
              >
                {nombreCategoria}
              </option>
            ))}
          </select>

          <select
            value={estado}
            onChange={(evento) =>
              setEstado(
                evento.target.value as EstadoStock | ''
              )
            }
            aria-label="Filtrar por estado"
          >
            <option value="">Todos los estados</option>
            <option value="DISPONIBLE">Disponible</option>
            <option value="STOCK_BAJO">Stock bajo</option>
            <option value="AGOTADO">Agotado</option>
            <option value="SIN_CONTEO">Sin conteo</option>
          </select>

          <button
            className="stock-clear-filters"
            type="button"
            onClick={limpiarFiltros}
          >
            Limpiar
          </button>
        </div>

        <div className="stock-results">
          <span>
            Mostrando{' '}
            <strong>{productosFiltrados.length}</strong>{' '}
            productos
          </span>
        </div>

        <div className="stock-table-container">
          <table className="stock-table">
            <thead>
              <tr>
                <th>Código</th>
                <th>Producto</th>
                <th>Categoría</th>
                <th>Saldo desde</th>
                <th>Stock actual</th>
                <th>Stock mínimo</th>
                <th>Stock máximo</th>
                <th>Estado</th>
                <th aria-label="Detalle" />
              </tr>
            </thead>

            <tbody>
              {productosFiltrados.map(
                (producto: ProductoStock) => {
                  const expandido =
                    productoExpandido ===
                    producto.id_producto

                  return (
                    <Fragment key={producto.id_producto}>
                      <tr>
                        <td>
                          <span className="stock-code">
                            {producto.codigo}
                          </span>
                        </td>

                        <td>
                          <div className="stock-product">
                            <strong>{producto.nombre}</strong>
                            <span>{formatearUnidad(producto.unidad)}</span>
                          </div>
                        </td>

                        <td>{producto.categoria}</td>

                        <td>
                          {formatearFecha(
                            producto.fecha_ultimo_conteo
                          )}
                        </td>

                        <td>
                          <strong className="stock-quantity">
                            {formatearCantidad(
                              producto.stock_actual
                            )}
                          </strong>{' '}
                          {producto.stock_actual !== null &&
                            formatearUnidad(producto.unidad)}
                        </td>

                        <td>
                          {formatearCantidad(
                            producto.stock_minimo
                          )}{' '}
                          {formatearUnidad(producto.unidad)}
                        </td>

                        <td>{producto.stock_maximo == null ? 'Sin definir' : formatearCantidad(producto.stock_maximo)}</td>
                        <td>
                          <span
                            className={`stock-status stock-status--${producto.estado_stock.toLowerCase()}`}
                          >
                            {
                              etiquetasEstado[
                                producto.estado_stock
                              ]
                            }
                          </span>
                        </td>

                        <td>
                          <button
                            className="stock-detail-button"
                            type="button"
                            onClick={() =>
                              setProductoExpandido(
                                expandido
                                  ? null
                                  : producto.id_producto
                              )
                            }
                            aria-label={
                              expandido
                                ? 'Ocultar cálculo'
                                : 'Ver cálculo'
                            }
                          >
                            {expandido ? (
                              <ChevronUp aria-hidden="true" />
                            ) : (
                              <ChevronDown aria-hidden="true" />
                            )}
                          </button>
                        </td>
                      </tr>

                      {expandido && (
                        <tr className="stock-detail-row">
                          <td colSpan={9}>
                            <div className="stock-calculation">
                              <div>
                                <span>Saldo inicial</span>
                                <strong>
                                  {formatearCantidad(
                                    producto.stock_ultimo_conteo
                                  )}
                                </strong>
                              </div>

                              <span className="stock-operation">
                                +
                              </span>

                              <div>
                                <span>Recepciones</span>
                                <strong>
                                  {formatearCantidad(
                                    producto.entradas_recepcion
                                  )}
                                </strong>
                              </div>

                              <span className="stock-operation">
                                +
                              </span>

                              <div>
                                <span>Otras entradas</span>
                                <strong>
                                  {formatearCantidad(
                                    producto.entradas_movimiento
                                  )}
                                </strong>
                              </div>

                              <span className="stock-operation">
                                −
                              </span>

                              <div>
                                <span>Salidas</span>
                                <strong>
                                  {formatearCantidad(
                                    producto.salidas_movimiento
                                  )}
                                </strong>
                              </div>

                              <span className="stock-operation">
                                =
                              </span>

                              <div className="stock-calculation__result">
                                <span>Stock actual</span>
                                <strong>
                                  {formatearCantidad(
                                    producto.stock_actual
                                  )}{' '}
                                  {producto.stock_actual !==
                                    null && formatearUnidad(producto.unidad)}
                                </strong>
                              </div>
                            </div>
                          </td>
                        </tr>
                      )}
                    </Fragment>
                  )
                }
              )}
            </tbody>
          </table>

          {productosFiltrados.length === 0 && (
            <div className="stock-empty">
              No se encontraron productos con los filtros
              seleccionados.
            </div>
          )}
        </div>
      </section>
    </div>
  )
}

export { StockPage }
