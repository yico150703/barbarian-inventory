import { formatearUnidad } from '../utils/unitHelpers'
import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type ChangeEvent,
} from 'react'
import {
  AlertCircle,
  CalendarDays,
  CheckCircle2,
  ClipboardList,
  LoaderCircle,
  LockKeyhole,
  Play,
  Save,
  Search,
  X,
} from 'lucide-react'

import { useAuth } from '../context/AuthContext'
import {
  cerrarInventarioActual,
  guardarInventarioActual,
  iniciarInventarioActual,
  obtenerInventarioActual,
} from '../services/inventoryService'

import type {
  ProductoInventarioActual,
  RespuestaInventarioActual,
  SolicitudGuardarInventario,
} from '../types/inventory'

import './InventoryPage.css'

type ConteosFormulario = Record<number, string>

function formatearFecha(fecha?: string): string {
  if (!fecha) {
    return 'Fecha no seleccionada'
  }

  return new Intl.DateTimeFormat('es-PE', {
    weekday: 'long',
    day: '2-digit',
    month: 'long',
    year: 'numeric',
  }).format(new Date(`${fecha}T00:00:00`))
}

function crearConteosIniciales(
  productos: ProductoInventarioActual[],
): ConteosFormulario {
  return productos.reduce<ConteosFormulario>(
    (resultado, producto) => {
      resultado[producto.id_producto] =
        producto.stock_contado === null
          ? ''
          : String(producto.stock_contado)

      return resultado
    },
    {},
  )
}

function obtenerMensajeError(error: unknown): string {
  return error instanceof Error
    ? error.message
    : 'No se pudo completar la operación.'
}

export default function InventoryPage() {
  const { token } = useAuth()

  const [datos, setDatos] =
    useState<RespuestaInventarioActual | null>(null)

  const [conteos, setConteos] =
    useState<ConteosFormulario>({})

  const [fechaSeleccionada, setFechaSeleccionada] =
    useState('')

  const [busqueda, setBusqueda] = useState('')
  const [categoria, setCategoria] = useState('TODAS')

  const [cargando, setCargando] = useState(true)
  const [procesando, setProcesando] = useState(false)
  const [mostrarCierre, setMostrarCierre] =
    useState(false)

  const [error, setError] = useState('')
  const [mensaje, setMensaje] = useState('')

  const cargarInventario = useCallback(async () => {
    if (!token) {
      return
    }

    try {
      setCargando(true)
      setError('')

      const respuesta =
        await obtenerInventarioActual(token)

      setDatos(respuesta)
      setConteos(
        crearConteosIniciales(respuesta.productos),
      )

      if (respuesta.inventario) {
        setFechaSeleccionada(
          respuesta.inventario.fecha_inventario,
        )

      } else {
        setFechaSeleccionada((fechaAnterior) => {
          if (
            respuesta.fechas_disponibles.includes(
              fechaAnterior,
            )
          ) {
            return fechaAnterior
          }

          const ultimaPosicion =
            respuesta.fechas_disponibles.length - 1

          return respuesta.fechas_disponibles[
            ultimaPosicion
          ] ?? ''
        })
      }

      if (respuesta.mensaje) {
        setMensaje(respuesta.mensaje)
      }
    } catch (errorDesconocido) {
      setError(obtenerMensajeError(errorDesconocido))
    } finally {
      setCargando(false)
    }
  }, [token])

  useEffect(() => {
    void cargarInventario()
  }, [cargarInventario])

  const categorias = useMemo(() => {
    if (!datos) {
      return []
    }

    return Array.from(
      new Set(
        datos.productos.map(
          (producto) => producto.categoria,
        ),
      ),
    ).sort((a, b) =>
      a.localeCompare(b, 'es', {
        sensitivity: 'base',
      }),
    )
  }, [datos])

  const productosFiltrados = useMemo(() => {
    if (!datos) {
      return []
    }

    const termino =
      busqueda.trim().toLocaleLowerCase()

    return datos.productos.filter((producto) => {
      const coincideCategoria =
        categoria === 'TODAS' ||
        producto.categoria === categoria

      const coincideBusqueda =
        termino === '' ||
        producto.codigo
          .toLocaleLowerCase()
          .includes(termino) ||
        producto.nombre
          .toLocaleLowerCase()
          .includes(termino)

      return coincideCategoria && coincideBusqueda
    })
  }, [datos, busqueda, categoria])

  const resumenActual = useMemo(() => {
    const total = datos?.productos.length ?? 0

    const contados = Object.values(conteos).filter(
      (valor) => valor.trim() !== '',
    ).length

    return {
      total,
      contados,
      pendientes: Math.max(total - contados, 0),
      porcentaje:
        total > 0
          ? Number(
              ((contados / total) * 100).toFixed(2),
            )
          : 0,
    }
  }, [datos, conteos])

  const inventarioIniciado = Boolean(
    datos?.inventario,
  )

  const inventarioCerrado =
    datos?.inventario?.estado_inventario === 'CERRADO'

  const cambiarConteo = (
    evento: ChangeEvent<HTMLInputElement>,
    idProducto: number,
  ) => {
    const valor = evento.target.value

    if (
      valor !== '' &&
      !/^\d*([.,]\d*)?$/.test(valor)
    ) {
      return
    }

    setConteos((anteriores) => ({
      ...anteriores,
      [idProducto]: valor,
    }))

    setMensaje('')
    setError('')
  }

  const construirSolicitudGuardado =
    (): SolicitudGuardarInventario | null => {
      if (!datos) {
        return null
      }

      const conteosParaGuardar = datos.productos.map(
        (producto) => {
          const valor =
            conteos[producto.id_producto]?.trim() ?? ''

          return {
            id_producto: producto.id_producto,
            stock_contado:
              valor === ''
                ? null
                : Number(valor.replace(',', '.')),
          }
        },
      )

      const invalido = conteosParaGuardar.some(
        (conteo) =>
          conteo.stock_contado !== null &&
          (!Number.isFinite(conteo.stock_contado) ||
            conteo.stock_contado < 0),
      )

      if (invalido) {
        setError(
          'Solo se permiten conteos iguales o mayores que cero.',
        )

        return null
      }

      return {
        conteos: conteosParaGuardar,
      }
    }

  const iniciarInventario = async () => {
    if (!token || !fechaSeleccionada) {
      setError('Selecciona la fecha del inventario.')
      return
    }

    try {
      setProcesando(true)
      setError('')
      setMensaje('')

      const respuesta =
        await iniciarInventarioActual(token, {
          fecha_inventario: fechaSeleccionada,
        })

      await cargarInventario()
      setMensaje(respuesta.mensaje)
    } catch (errorDesconocido) {
      setError(obtenerMensajeError(errorDesconocido))
    } finally {
      setProcesando(false)
    }
  }

  const guardarProgreso = async () => {
    if (!token || !datos?.inventario) {
      return
    }

    const solicitud = construirSolicitudGuardado()

    if (!solicitud) {
      return
    }

    try {
      setProcesando(true)
      setError('')
      setMensaje('')

      const respuesta =
        await guardarInventarioActual(
          token,
          solicitud,
        )

      setDatos(respuesta)
      setConteos(
        crearConteosIniciales(respuesta.productos),
      )

      setMensaje(
        respuesta.mensaje ??
          'Progreso guardado correctamente.',
      )
    } catch (errorDesconocido) {
      setError(obtenerMensajeError(errorDesconocido))
    } finally {
      setProcesando(false)
    }
  }

  const abrirConfirmacionCierre = () => {
    setError('')
    setMostrarCierre(true)
  }

  const confirmarCierre = async () => {
    if (!token || !datos?.inventario) {
      return
    }

    const solicitud = construirSolicitudGuardado()

    if (!solicitud) {
      return
    }

    try {
      setProcesando(true)
      setError('')
      setMensaje('')

      /*
       * Primero guarda los últimos valores escritos.
       * Después realiza el cierre definitivo.
       */
      const inventarioGuardado =
        await guardarInventarioActual(
          token,
          solicitud,
        )

      const cierre = await cerrarInventarioActual(
        token,
        {},
      )

      setDatos({
        ...inventarioGuardado,
        inventario: inventarioGuardado.inventario
          ? {
              ...inventarioGuardado.inventario,
              estado_inventario: 'CERRADO',
            }
          : null,
      })

      setConteos(
        crearConteosIniciales(
          inventarioGuardado.productos,
        ),
      )

      setMostrarCierre(false)
      setMensaje(cierre.mensaje)
    } catch (errorDesconocido) {
      setError(obtenerMensajeError(errorDesconocido))
      setMostrarCierre(false)
    } finally {
      setProcesando(false)
    }
  }

  if (cargando) {
    return (
      <section className="inventory-state">
        <LoaderCircle
          className="inventory-spinner"
          aria-hidden="true"
        />

        <div>
          <h1>Cargando inventario</h1>
          <p>Obteniendo los productos registrados.</p>
        </div>
      </section>
    )
  }

  if (error && !datos) {
    return (
      <section className="inventory-state inventory-state--error">
        <AlertCircle aria-hidden="true" />

        <div>
          <h1>No se pudo cargar el inventario</h1>
          <p>{error}</p>

          <button
            type="button"
            onClick={() => void cargarInventario()}
          >
            Volver a intentar
          </button>
        </div>
      </section>
    )
  }

  return (
    <section className="inventory-page">
      <header className="inventory-header">
        <div className="inventory-header__information">
          <span className="inventory-header__label">
            INVENTARIO DE CIERRE
          </span>

          <h1>Realizar inventario</h1>

          <p>
            Registra las existencias físicas encontradas
            durante el conteo.
          </p>
        </div>

        <div className="inventory-date">
          <CalendarDays aria-hidden="true" />

          <div>
            <span>FECHA DEL INVENTARIO</span>
            <strong>
              {formatearFecha(
                datos?.inventario?.fecha_inventario ??
                  fechaSeleccionada,
              )}
            </strong>
          </div>
        </div>
      </header>

      <div className="inventory-summary">
        <article className="inventory-summary-card">
          <div className="inventory-summary-card__icon">
            <ClipboardList aria-hidden="true" />
          </div>
          <div>
            <span>Total de productos</span>
            <strong>{resumenActual.total}</strong>
          </div>
        </article>

        <article className="inventory-summary-card">
          <div className="inventory-summary-card__icon inventory-summary-card__icon--success">
            <CheckCircle2 aria-hidden="true" />
          </div>
          <div>
            <span>Productos contados</span>
            <strong>{resumenActual.contados}</strong>
          </div>
        </article>

        <article className="inventory-summary-card">
          <div className="inventory-summary-card__icon inventory-summary-card__icon--pending">
            <ClipboardList aria-hidden="true" />
          </div>
          <div>
            <span>Productos pendientes</span>
            <strong>{resumenActual.pendientes}</strong>
          </div>
        </article>

        <article className="inventory-progress-card">
          <div className="inventory-progress-card__header">
            <span>Progreso del inventario</span>
            <strong>{resumenActual.porcentaje}%</strong>
          </div>

          <div
            className="inventory-progress"
            role="progressbar"
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={resumenActual.porcentaje}
          >
            <span
              style={{
                width: `${resumenActual.porcentaje}%`,
              }}
            />
          </div>
        </article>
      </div>

      {mensaje && (
        <div className="inventory-message inventory-message--success">
          <CheckCircle2 aria-hidden="true" />
          {mensaje}
        </div>
      )}

      {error && (
        <div
          className="inventory-message inventory-message--error"
          role="alert"
        >
          <AlertCircle aria-hidden="true" />
          {error}
        </div>
      )}

      {!inventarioIniciado && (
        <section className="inventory-start">
          <div>
            <span>INVENTARIO DEL TURNO</span>
            <h2>Selecciona la fecha operativa</h2>
            <p>
              Antes de las 9:00 a. m. también podrás
              seleccionar el día anterior.
            </p>

            <label className="inventory-date-selector">
              <span>Fecha del inventario</span>

              <select
                value={fechaSeleccionada}
                onChange={(evento) =>
                  setFechaSeleccionada(
                    evento.target.value,
                  )
                }
              >
                {datos?.fechas_disponibles.map(
                  (fecha) => (
                    <option key={fecha} value={fecha}>
                      {formatearFecha(fecha)}
                    </option>
                  ),
                )}
              </select>
            </label>
          </div>

          <button
            type="button"
            onClick={() => void iniciarInventario()}
            disabled={
              procesando || !fechaSeleccionada
            }
          >
            {procesando ? (
              <LoaderCircle
                className="inventory-spinner"
                aria-hidden="true"
              />
            ) : (
              <Play aria-hidden="true" />
            )}

            {procesando
              ? 'INICIANDO...'
              : 'INICIAR INVENTARIO'}
          </button>
        </section>
      )}

      <section className="inventory-content">
        <div className="inventory-toolbar">
          <div className="inventory-search">
            <Search aria-hidden="true" />

            <input
              type="search"
              value={busqueda}
              onChange={(evento) =>
                setBusqueda(evento.target.value)
              }
              placeholder="Buscar por código o producto"
            />
          </div>

          <select
            value={categoria}
            onChange={(evento) =>
              setCategoria(evento.target.value)
            }
          >
            <option value="TODAS">
              Todas las categorías
            </option>

            {categorias.map((nombreCategoria) => (
              <option
                key={nombreCategoria}
                value={nombreCategoria}
              >
                {nombreCategoria}
              </option>
            ))}
          </select>

          <button
            className="inventory-clear"
            type="button"
            onClick={() => {
              setBusqueda('')
              setCategoria('TODAS')
            }}
          >
            Limpiar
          </button>
        </div>

        <div className="inventory-results">
          Mostrando{' '}
          <strong>{productosFiltrados.length}</strong>{' '}
          productos
        </div>

        <div className="inventory-table-container">
          <table className="inventory-table">
            <thead>
              <tr>
                <th>Código</th>
                <th>Producto</th>
                <th>Categoría</th>
                <th>Unidad</th>
                <th>Stock contado</th>
                <th>Estado</th>
              </tr>
            </thead>

            <tbody>
              {productosFiltrados.map((producto) => {
                const valor =
                  conteos[producto.id_producto] ?? ''

                const contado = valor.trim() !== ''

                return (
                  <tr key={producto.id_producto}>
                    <td>
                      <span className="inventory-code">
                        {producto.codigo}
                      </span>
                    </td>

                    <td>
                      <strong className="inventory-product">
                        {producto.nombre}
                      </strong>
                    </td>

                    <td>{producto.categoria}</td>
                    <td>{formatearUnidad(producto.unidad)}</td>

                    <td>
                      <div className="inventory-count">
                        <input
                          type="text"
                          inputMode="decimal"
                          value={valor}
                          onChange={(evento) =>
                            cambiarConteo(
                              evento,
                              producto.id_producto,
                            )
                          }
                          placeholder="0"
                          disabled={
                            !inventarioIniciado ||
                            inventarioCerrado ||
                            procesando
                          }
                        />

                        <span>{formatearUnidad(producto.unidad)}</span>
                      </div>
                    </td>

                    <td>
                      <span
                        className={
                          contado
                            ? 'inventory-status inventory-status--counted'
                            : 'inventory-status inventory-status--pending'
                        }
                      >
                        {contado ? 'Contado' : 'Pendiente'}
                      </span>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>

        {inventarioIniciado && (
          <footer className="inventory-actions">
            <div>
              <span>Estado actual</span>
              <strong>
                {inventarioCerrado
                  ? 'Inventario cerrado'
                  : 'Inventario en progreso'}
              </strong>
            </div>

            <div className="inventory-actions__buttons">
              <button
                className="inventory-save-button"
                type="button"
                onClick={() => void guardarProgreso()}
                disabled={
                  procesando || inventarioCerrado
                }
              >
                <Save aria-hidden="true" />
                GUARDAR PROGRESO
              </button>

              <button
                className="inventory-close-button"
                type="button"
                onClick={abrirConfirmacionCierre}
                disabled={
                  procesando || inventarioCerrado
                }
              >
                <LockKeyhole aria-hidden="true" />
                CERRAR INVENTARIO
              </button>
            </div>
          </footer>
        )}
      </section>

      {mostrarCierre && (
        <div
          className="inventory-modal-backdrop"
          role="presentation"
        >
          <section
            className="inventory-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="inventory-close-title"
          >
            <button
              className="inventory-modal__close"
              type="button"
              onClick={() => setMostrarCierre(false)}
              aria-label="Cerrar ventana"
            >
              <X aria-hidden="true" />
            </button>

            <div className="inventory-modal__icon">
              <LockKeyhole aria-hidden="true" />
            </div>

            <h2 id="inventory-close-title">
              Cerrar inventario
            </h2>

            <p>
              Después del cierre ya no podrás modificar
              este inventario. Se guardarán únicamente los
              productos que tengan un valor, incluyendo cero.
            </p>

            {resumenActual.pendientes > 0 && (
              <div className="inventory-modal__warning">
                <AlertCircle aria-hidden="true" />

                <span>
                  Hay {resumenActual.pendientes} productos sin
                  contar. Para ellos se conservará el último
                  conteo cerrado disponible.
                </span>
              </div>
            )}

            <div className="inventory-modal__actions">
              <button
                type="button"
                onClick={() => setMostrarCierre(false)}
              >
                Cancelar
              </button>

              <button
                type="button"
                onClick={() => void confirmarCierre()}
                disabled={procesando}
              >
                {procesando
                  ? 'CERRANDO...'
                  : 'CONFIRMAR CIERRE'}
              </button>
            </div>
          </section>
        </div>
      )}
    </section>
  )
}