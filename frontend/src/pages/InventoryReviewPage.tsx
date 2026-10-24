import { formatearUnidad } from '../utils/unitHelpers'
import {
  AlertCircle,
  CheckCircle2,
  ChevronDown,
  ChevronUp,
  ClipboardCheck,
  Eye,
  LoaderCircle,
  PackageCheck,
  PackageX,
  Save,
  Search,
  XCircle,
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
  corregirInventario,
  guardarRevisionInventario,
  obtenerDetalleRevision,
  obtenerInventariosRevision,
} from '../services/inventoryService'
import type {
  InventarioRevisionItem,
  RespuestaDetalleRevision,
  RespuestaInventariosRevision,
} from '../types/inventoryReview'
import './InventoryReviewPage.css'


function obtenerPerfilToken(token: string | null) {
  if (!token) return null

  try {
    const parte = token.split('.')[1]
    const base64 = parte
      .replace(/-/g, '+')
      .replace(/_/g, '/')
      .padEnd(Math.ceil(parte.length / 4) * 4, '=')
    const bytes = Uint8Array.from(
      atob(base64),
      (caracter) => caracter.charCodeAt(0),
    )
    const contenido = new TextDecoder().decode(bytes)
    const datos = JSON.parse(contenido) as {
      perfil?: string
    }

    return datos.perfil ?? null
  } catch {
    return null
  }
}

const formatearFecha = (fecha: string) =>
  new Intl.DateTimeFormat('es-PE', {
    day: '2-digit',
    month: 'long',
    year: 'numeric',
  }).format(new Date(`${fecha}T00:00:00`))

const formatearFechaHora = (fecha: string | null) => {
  if (!fecha) return 'Sin fecha'

  return new Intl.DateTimeFormat('es-PE', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(fecha.replace(' ', 'T')))
}

const formatearNumero = (valor: number) =>
  new Intl.NumberFormat('es-PE', {
    maximumFractionDigits: 3,
  }).format(valor)

export function InventoryReviewPage() {
  const { token } = useAuth()
  const esGerente = obtenerPerfilToken(token) === 'Gerente'
  const [modoCorreccion, setModoCorreccion] = useState(false)
  const [valoresCorregidos, setValoresCorregidos] =
    useState<Record<number, string>>({})
  const [motivoCorreccion, setMotivoCorreccion] = useState('')
  const [observacionCorreccion, setObservacionCorreccion] =
    useState('')
  const [corrigiendo, setCorrigiendo] = useState(false)
  const [datos, setDatos] =
    useState<RespuestaInventariosRevision | null>(null)
  const [detalle, setDetalle] =
    useState<RespuestaDetalleRevision | null>(null)
  const [idAbierto, setIdAbierto] =
    useState<number | null>(null)
  const [busqueda, setBusqueda] = useState('')
  const [filtro, setFiltro] = useState('TODOS')
  const [motivo, setMotivo] = useState('')
  const [observacion, setObservacion] = useState('')
  const [cargando, setCargando] = useState(true)
  const [cargandoDetalle, setCargandoDetalle] =
    useState(false)
  const [guardando, setGuardando] = useState(false)
  const [error, setError] = useState('')
  const [mensaje, setMensaje] = useState('')

  const cargarListado = useCallback(async () => {
    if (!token) {
      setError('No existe una sesión válida.')
      setCargando(false)
      return
    }

    try {
      setCargando(true)
      setError('')
      setDatos(await obtenerInventariosRevision(token))
    } catch (errorConsulta) {
      setError(
        errorConsulta instanceof Error
          ? errorConsulta.message
          : 'No se pudieron cargar los inventarios.',
      )
    } finally {
      setCargando(false)
    }
  }, [token])

  useEffect(() => {
    void cargarListado()
  }, [cargarListado])

  const inventariosFiltrados = useMemo(() => {
    const texto = busqueda.trim().toLowerCase()

    return (datos?.inventarios ?? []).filter((item) => {
      const coincideTexto =
        !texto ||
        item.fecha_inventario.includes(texto) ||
        item.registrado_por.toLowerCase().includes(texto) ||
        (item.revisado_por ?? '').toLowerCase().includes(texto)

      const coincideEstado =
        filtro === 'TODOS' ||
        (filtro === 'REVISADO' && item.revisado) ||
        (filtro === 'PENDIENTE' && !item.revisado)

      return coincideTexto && coincideEstado
    })
  }, [busqueda, datos, filtro])

  const abrirDetalle = async (
    inventario: InventarioRevisionItem,
  ) => {
    if (!token) return

    if (idAbierto === inventario.id_inventario_cierre) {
      setIdAbierto(null)
      setDetalle(null)
      setModoCorreccion(false)
      setMotivoCorreccion('')
      setObservacionCorreccion('')
      setValoresCorregidos({})
      return
    }

    try {
      setCargandoDetalle(true)
      setError('')
      setMensaje('')

      const respuesta = await obtenerDetalleRevision(
        token,
        inventario.id_inventario_cierre,
      )

      setDetalle(respuesta)
      setIdAbierto(inventario.id_inventario_cierre)
      setMotivo(respuesta.inventario.motivo_revision ?? '')
      setObservacion(respuesta.inventario.observacion ?? '')
      setModoCorreccion(false)
      setMotivoCorreccion('')
      setObservacionCorreccion('')
      setValoresCorregidos(
        Object.fromEntries(
          respuesta.productos.map((producto) => [
            producto.id_producto,
            producto.fue_contado
              ? String(producto.stock_contado ?? 0)
              : '',
          ]),
        ),
      )
    } catch (errorConsulta) {
      setError(
        errorConsulta instanceof Error
          ? errorConsulta.message
          : 'No se pudo cargar el detalle.',
      )
    } finally {
      setCargandoDetalle(false)
    }
  }

  const guardarRevision = async () => {
    if (!token || !detalle) return

    if (!motivo.trim() || !observacion.trim()) {
      setError('Completa el motivo y la observación.')
      return
    }

    try {
      setGuardando(true)
      setError('')
      setMensaje('')

      const respuesta = await guardarRevisionInventario(
        token,
        detalle.inventario.id_inventario_cierre,
        {
          motivo_revision: motivo,
          observacion,
        },
      )

      setDetalle(respuesta)
      setMensaje(
        respuesta.mensaje ??
          'Revisión guardada correctamente.',
      )
      await cargarListado()
    } catch (errorGuardado) {
      setError(
        errorGuardado instanceof Error
          ? errorGuardado.message
          : 'No se pudo guardar la revisión.',
      )
    } finally {
      setGuardando(false)
    }
  }

  const cancelarCorreccion = () => {
    if (!detalle) return

    setModoCorreccion(false)
    setMotivoCorreccion('')
    setObservacionCorreccion('')
    setValoresCorregidos(
      Object.fromEntries(
        detalle.productos.map((producto) => [
          producto.id_producto,
          producto.fue_contado
            ? String(producto.stock_contado ?? 0)
            : '',
        ]),
      ),
    )
  }

  const guardarCorreccion = async () => {
    if (!token || !detalle || !esGerente) return

    if (!motivoCorreccion.trim() || !observacionCorreccion.trim()) {
      setError('Completa el motivo y la observación de la corrección.')
      return
    }

    const cambios = detalle.productos.flatMap((producto) => {
      const texto = (valoresCorregidos[producto.id_producto] ?? '').trim()
      const stockNuevo = texto === '' ? null : Number(texto)
      const stockAnterior = producto.fue_contado
        ? producto.stock_contado ?? 0
        : null

      if (
        (stockNuevo === null && stockAnterior === null) ||
        (stockNuevo !== null && stockAnterior !== null && stockNuevo === stockAnterior)
      ) {
        return []
      }

      return [{
        id_producto: producto.id_producto,
        stock_nuevo: stockNuevo,
      }]
    })

    if (cambios.length === 0) {
      setError('Modifica al menos un valor antes de guardar la corrección.')
      return
    }

    const valorInvalido = cambios.some(
      (cambio) =>
        cambio.stock_nuevo !== null &&
        (!Number.isFinite(cambio.stock_nuevo) || cambio.stock_nuevo < 0),
    )

    if (valorInvalido) {
      setError('Los valores corregidos deben ser números mayores o iguales a cero.')
      return
    }

    try {
      setCorrigiendo(true)
      setError('')
      setMensaje('')

      const respuesta = await corregirInventario(
        token,
        detalle.inventario.id_inventario_cierre,
        {
          motivo_correccion: motivoCorreccion.trim(),
          observacion: observacionCorreccion.trim(),
          cambios,
        },
      )

      setDetalle(respuesta)
      setValoresCorregidos(
        Object.fromEntries(
          respuesta.productos.map((producto) => [
            producto.id_producto,
            producto.fue_contado
              ? String(producto.stock_contado ?? 0)
              : '',
          ]),
        ),
      )
      setModoCorreccion(false)
      setMotivoCorreccion('')
      setObservacionCorreccion('')
      setMensaje(
        respuesta.mensaje ?? 'Inventario corregido correctamente.',
      )
      await cargarListado()
    } catch (errorCorreccion) {
      setError(
        errorCorreccion instanceof Error
          ? errorCorreccion.message
          : 'No se pudo corregir el inventario.',
      )
    } finally {
      setCorrigiendo(false)
    }
  }

  if (cargando) {
    return (
      <section className="review-state">
        <LoaderCircle className="review-spin" />
        Cargando inventarios cerrados...
      </section>
    )
  }

  return (
    <section className="review-page">
      <header className="review-header">
        <div>
          <span className="review-header__label">
            INVENTARIO
          </span>
          <h1>Revisar inventarios</h1>
          <p>
            Consulta los conteos cerrados y registra la
            evaluación del supervisor.
          </p>
        </div>
        <div className="review-header__badge">
          <ClipboardCheck />
          <div>
            <small>CONTROL Y SEGUIMIENTO</small>
            <strong>Inventarios cerrados</strong>
          </div>
        </div>
      </header>

      <div className="review-summary">
        <article>
          <span className="review-icon dark">
            <ClipboardCheck />
          </span>
          <div>
            <small>Total cerrados</small>
            <strong>{datos?.resumen.total_inventarios ?? 0}</strong>
          </div>
        </article>
        <article>
          <span className="review-icon yellow">
            <Eye />
          </span>
          <div>
            <small>Pendientes de revisión</small>
            <strong>{datos?.resumen.pendientes_revision ?? 0}</strong>
          </div>
        </article>
        <article>
          <span className="review-icon green">
            <CheckCircle2 />
          </span>
          <div>
            <small>Revisados</small>
            <strong>{datos?.resumen.inventarios_revisados ?? 0}</strong>
          </div>
        </article>
      </div>

      {mensaje && (
        <div className="review-alert review-alert--success">
          <CheckCircle2 /> {mensaje}
        </div>
      )}

      {error && (
        <div className="review-alert review-alert--error">
          <AlertCircle /> {error}
        </div>
      )}

      <section className="review-content">
        <div className="review-content__title">
          <div>
            <span>HISTORIAL</span>
            <h2>Inventarios registrados</h2>
          </div>
          <p>Selecciona un inventario para revisar su conteo.</p>
        </div>

        <div className="review-filters">
          <label className="review-search">
            <Search />
            <input
              value={busqueda}
              onChange={(event) => setBusqueda(event.target.value)}
              placeholder="Buscar por fecha o responsable"
            />
          </label>

          <select
            value={filtro}
            onChange={(event) => setFiltro(event.target.value)}
          >
            <option value="TODOS">Todos los estados</option>
            <option value="PENDIENTE">Pendientes</option>
            <option value="REVISADO">Revisados</option>
          </select>

          <button
            type="button"
            className="review-clear"
            onClick={() => {
              setBusqueda('')
              setFiltro('TODOS')
            }}
          >
            Limpiar
          </button>
        </div>

        <p className="review-results">
          Mostrando <strong>{inventariosFiltrados.length}</strong>
          {' '}de <strong>{datos?.inventarios.length ?? 0}</strong>
          {' '}inventarios
        </p>

        <div className="review-table-wrap">
          <table className="review-table">
            <thead>
              <tr>
                <th>Fecha</th>
                <th>Registrado por</th>
                <th>Cierre</th>
                <th>Contados</th>
                <th>No contados</th>
                <th>Revisión</th>
                <th>Detalle</th>
              </tr>
            </thead>
            <tbody>
              {inventariosFiltrados.map((item) => (
                <Fragment key={item.id_inventario_cierre}>
                  <tr key={`fila-${item.id_inventario_cierre}`}>
                    <td>
                      <strong className="review-date">
                        {formatearFecha(item.fecha_inventario)}
                      </strong>
                    </td>
                    <td>{item.registrado_por}</td>
                    <td>{formatearFechaHora(item.fecha_registro)}</td>
                    <td>
                      <span className="review-count good">
                        {item.productos_contados}
                      </span>
                    </td>
                    <td>
                      <span className="review-count pending">
                        {item.productos_no_contados}
                      </span>
                    </td>
                    <td>
                      <span
                        className={
                          item.revisado
                            ? 'review-status reviewed'
                            : 'review-status waiting'
                        }
                      >
                        {item.revisado ? 'Revisado' : 'Pendiente'}
                      </span>
                    </td>
                    <td>
                      <button
                        type="button"
                        className="review-open"
                        aria-label="Abrir detalle"
                        disabled={cargandoDetalle}
                        onClick={() => void abrirDetalle(item)}
                      >
                        {idAbierto === item.id_inventario_cierre
                          ? <ChevronUp />
                          : <ChevronDown />}
                      </button>
                    </td>
                  </tr>

                  {idAbierto === item.id_inventario_cierre && (
                    <tr
                      key={`detalle-${item.id_inventario_cierre}`}
                      className="review-detail-row"
                    >
                      <td colSpan={7}>
                        {detalle && (
                          <div className="review-detail">
                            <div className="review-detail-summary">
                              <div>
                                <PackageCheck />
                                <span>Contados</span>
                                <strong>
                                  {detalle.resumen.productos_contados}
                                </strong>
                              </div>
                              <div>
                                <XCircle />
                                <span>En cero</span>
                                <strong>
                                  {detalle.resumen.productos_en_cero}
                                </strong>
                              </div>
                              <div>
                                <PackageX />
                                <span>No contados</span>
                                <strong>
                                  {detalle.resumen.productos_no_contados}
                                </strong>
                              </div>
                            </div>

                            {esGerente && (
                              <div className="review-correction-actions">
                                <div>
                                  <strong>Corrección del inventario</strong>
                                  <span>
                                    Un campo vacío significa «No contado» y el valor 0
                                    significa «Contado en cero».
                                  </span>
                                </div>
                                {!modoCorreccion && (
                                  <button
                                    type="button"
                                    className="review-correct-button"
                                    onClick={() => {
                                      setError('')
                                      setMensaje('')
                                      setModoCorreccion(true)
                                    }}
                                  >
                                    Corregir inventario
                                  </button>
                                )}
                              </div>
                            )}

                            <div className="review-products-wrap">
                              <table className="review-products">
                                <thead>
                                  <tr>
                                    <th>Código</th>
                                    <th>Producto</th>
                                    <th>Categoría</th>
                                    <th>Stock contado</th>
                                    <th>Stock mínimo</th>
                                    <th>Resultado</th>
                                  </tr>
                                </thead>
                                <tbody>
                                  {detalle.productos.map((producto) => (
                                    <tr key={producto.id_producto}>
                                      <td>
                                        <b className="review-code">
                                          {producto.codigo}
                                        </b>
                                      </td>
                                      <td>{producto.nombre}</td>
                                      <td>{producto.categoria}</td>
                                      <td>
                                        {modoCorreccion && esGerente ? (
                                          <label className="review-correction-stock">
                                            <input
                                              type="number"
                                              min="0"
                                              step="any"
                                              inputMode="decimal"
                                              aria-label={`Stock corregido de ${producto.nombre}`}
                                              value={
                                                valoresCorregidos[
                                                  producto.id_producto
                                                ] ?? ''
                                              }
                                              onChange={(event) =>
                                                setValoresCorregidos((actuales) => ({
                                                  ...actuales,
                                                  [producto.id_producto]:
                                                    event.target.value,
                                                }))
                                              }
                                            />
                                            <span>{formatearUnidad(producto.unidad)}</span>
                                          </label>
                                        ) : producto.fue_contado ? (
                                          `${formatearNumero(
                                            producto.stock_contado ?? 0,
                                          )} ${formatearUnidad(producto.unidad)}`
                                        ) : (
                                          'Sin dato'
                                        )}
                                      </td>
                                      <td>
                                        {formatearNumero(
                                          producto.stock_minimo,
                                        )}{' '}
                                        {formatearUnidad(producto.unidad)}
                                      </td>
                                      <td>
                                        <span
                                          className={
                                            producto.fue_contado
                                              ? producto.stock_contado === 0
                                                ? 'review-product-state zero'
                                                : 'review-product-state counted'
                                              : 'review-product-state missing'
                                          }
                                        >
                                          {producto.fue_contado
                                            ? producto.stock_contado === 0
                                              ? 'Contado en cero'
                                              : 'Contado'
                                            : 'No contado'}
                                        </span>
                                      </td>
                                    </tr>
                                  ))}
                                </tbody>
                              </table>
                            </div>

                            {modoCorreccion && esGerente && (
                              <div className="review-correction-form">
                                <div className="review-correction-form__heading">
                                  <span>CORRECCIÓN EXCLUSIVA DEL GERENTE</span>
                                  <h3>Justificación de los cambios</h3>
                                  <p>
                                    Solo se enviarán los productos cuyo valor haya
                                    cambiado. La corrección quedará registrada en la
                                    auditoría.
                                  </p>
                                </div>

                                <label>
                                  Motivo de corrección
                                  <select
                                    value={motivoCorreccion}
                                    onChange={(event) =>
                                      setMotivoCorreccion(event.target.value)
                                    }
                                  >
                                    <option value="">Seleccionar motivo</option>
                                    <option value="ERROR DE CONTEO">
                                      Error de conteo
                                    </option>
                                    <option value="PRODUCTO NO CONTADO">
                                      Producto no contado
                                    </option>
                                    <option value="VALOR INGRESADO INCORRECTAMENTE">
                                      Valor ingresado incorrectamente
                                    </option>
                                    <option value="OTRO">Otro</option>
                                  </select>
                                </label>

                                <label className="review-correction-observation">
                                  Observación
                                  <textarea
                                    value={observacionCorreccion}
                                    maxLength={500}
                                    onChange={(event) =>
                                      setObservacionCorreccion(event.target.value)
                                    }
                                    placeholder="Explica qué valores se corrigieron y por qué..."
                                  />
                                  <small>{observacionCorreccion.length}/500</small>
                                </label>

                                <div className="review-correction-form__buttons">
                                  <button
                                    type="button"
                                    className="review-cancel-correction"
                                    disabled={corrigiendo}
                                    onClick={cancelarCorreccion}
                                  >
                                    Cancelar
                                  </button>
                                  <button
                                    type="button"
                                    className="review-save-correction"
                                    disabled={corrigiendo}
                                    onClick={() => void guardarCorreccion()}
                                  >
                                    {corrigiendo ? (
                                      <LoaderCircle className="review-spin" />
                                    ) : (
                                      <Save />
                                    )}
                                    {corrigiendo
                                      ? 'Guardando...'
                                      : 'Guardar corrección'}
                                  </button>
                                </div>
                              </div>
                            )}

                            <div className="review-form">
                              <div className="review-form__heading">
                                <div>
                                  <span>REVISIÓN DEL SUPERVISOR</span>
                                  <h3>
                                    {detalle.inventario.revisado
                                      ? 'Actualizar revisión'
                                      : 'Registrar revisión'}
                                  </h3>
                                </div>
                                {detalle.inventario.revisado_por && (
                                  <p>
                                    Última revisión: {' '}
                                    <strong>
                                      {detalle.inventario.revisado_por}
                                    </strong>
                                  </p>
                                )}
                              </div>

                              <label>
                                Motivo de revisión
                                <select
                                  value={motivo}
                                  onChange={(event) =>
                                    setMotivo(event.target.value)
                                  }
                                >
                                  <option value="">
                                    Seleccionar motivo
                                  </option>
                                  <option value="CONTEO VERIFICADO">
                                    Conteo verificado
                                  </option>
                                  <option value="CONTEO INCORRECTO">
                                    Conteo incorrecto
                                  </option>
                                  <option value="PRODUCTOS NO CONTADOS">
                                    Productos no contados
                                  </option>
                                  <option value="DIFERENCIA DE STOCK">
                                    Diferencia de stock
                                  </option>
                                  <option value="OTRO">Otro</option>
                                </select>
                              </label>

                              <label className="review-observation">
                                Observación
                                <textarea
                                  value={observacion}
                                  maxLength={500}
                                  onChange={(event) =>
                                    setObservacion(event.target.value)
                                  }
                                  placeholder={
                                    'Describe el resultado de la revisión...'
                                  }
                                />
                                <small>{observacion.length}/500</small>
                              </label>

                              <button
                                type="button"
                                className="review-save"
                                disabled={guardando}
                                onClick={() => void guardarRevision()}
                              >
                                {guardando
                                  ? <LoaderCircle className="review-spin" />
                                  : <Save />}
                                {guardando
                                  ? 'Guardando...'
                                  : 'Guardar revisión'}
                              </button>
                            </div>
                          </div>
                        )}
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}

              {inventariosFiltrados.length === 0 && (
                <tr>
                  <td colSpan={7} className="review-empty">
                    No se encontraron inventarios cerrados.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
    </section>
  )
}
