import { formatearUnidad } from '../utils/unitHelpers'
import { Link } from 'react-router-dom'
import {
  AlertCircle,
  ArrowDownToLine,
  ArrowUpFromLine,
  CheckCircle2,
  ClipboardPlus,
  LoaderCircle,
  PackagePlus,
  Plus,
  Save,
  Search,
  Trash2,
} from 'lucide-react'
import {
  useCallback,
  useEffect,
  useMemo,
  useState,
} from 'react'

import { useAuth } from '../context/AuthContext'
import {
  obtenerFormularioMovimiento,
  registrarMovimiento,
} from '../services/movementService'
import type {
  MotivoMovimiento,
  ProductoMovimiento,
  RespuestaFormularioMovimiento,
} from '../types/movement'
import './RegisterMovementPage.css'


interface ProductoSeleccionado extends ProductoMovimiento {
  cantidad: string
}

const obtenerFechaLocal = () => {
  const fecha = new Date()
  const anio = fecha.getFullYear()
  const mes = String(fecha.getMonth() + 1).padStart(2, '0')
  const dia = String(fecha.getDate()).padStart(2, '0')

  return `${anio}-${mes}-${dia}`
}

export function RegisterMovementPage() {
  const { token } = useAuth()
  const [datos, setDatos] =
    useState<RespuestaFormularioMovimiento | null>(null)
  const [motivo, setMotivo] = useState('')
  const [fecha, setFecha] = useState(obtenerFechaLocal())
  const [local, setLocal] = useState('')
  const [idProveedor, setIdProveedor] = useState('')
  const [observacion, setObservacion] = useState('')
  const [busqueda, setBusqueda] = useState('')
  const [categoria, setCategoria] = useState('TODAS')
  const [seleccionados, setSeleccionados] =
    useState<ProductoSeleccionado[]>([])
  const [cargando, setCargando] = useState(true)
  const [guardando, setGuardando] = useState(false)
  const [error, setError] = useState('')
  const [mensaje, setMensaje] = useState('')

  const cargarDatos = useCallback(async () => {
    if (!token) {
      setError('No existe una sesión válida.')
      setCargando(false)
      return
    }

    try {
      setCargando(true)
      setError('')
      setDatos(await obtenerFormularioMovimiento(token))
    } catch (errorConsulta) {
      setError(
        errorConsulta instanceof Error
          ? errorConsulta.message
          : 'No se pudo cargar el formulario.',
      )
    } finally {
      setCargando(false)
    }
  }, [token])

  useEffect(() => {
    void cargarDatos()
  }, [cargarDatos])

  const configuracion = useMemo<
    MotivoMovimiento | undefined
  >(
    () => datos?.motivos.find(
      (item) => item.valor === motivo,
    ),
    [datos, motivo],
  )

  const productosFiltrados = useMemo(() => {
    const texto = busqueda.trim().toLowerCase()
    const idsSeleccionados = new Set(
      seleccionados.map((item) => item.id_producto),
    )

    return (datos?.productos ?? []).filter((producto) => {
      const coincideTexto =
        !texto ||
        producto.codigo.toLowerCase().includes(texto) ||
        producto.nombre.toLowerCase().includes(texto)
      const coincideCategoria =
        categoria === 'TODAS' ||
        producto.categoria === categoria

      return coincideTexto &&
        coincideCategoria &&
        !idsSeleccionados.has(producto.id_producto)
    })
  }, [busqueda, categoria, datos, seleccionados])

  const seleccionarMotivo = (nuevoMotivo: string) => {
    setMotivo(nuevoMotivo)
    setLocal('')
    setIdProveedor('')
    setError('')
  }

  const agregarProducto = (producto: ProductoMovimiento) => {
    setSeleccionados((actuales) => [
      ...actuales,
      {...producto, cantidad: ''},
    ])
  }

  const cambiarCantidad = (
    idProducto: number,
    cantidad: string,
  ) => {
    setSeleccionados((actuales) =>
      actuales.map((producto) =>
        producto.id_producto === idProducto
          ? {...producto, cantidad}
          : producto,
      ),
    )
  }

  const quitarProducto = (idProducto: number) => {
    setSeleccionados((actuales) =>
      actuales.filter(
        (producto) => producto.id_producto !== idProducto,
      ),
    )
  }

  const guardar = async () => {
    if (!token) return

    if (!configuracion) {
      setError('Selecciona el motivo del movimiento.')
      return
    }

    if (!fecha) {
      setError('Selecciona la fecha del movimiento.')
      return
    }

    if (configuracion.requiere_local && !local.trim()) {
      setError('Escribe el local relacionado.')
      return
    }

    if (configuracion.requiere_proveedor && !idProveedor) {
      setError('Selecciona el proveedor.')
      return
    }

    if (seleccionados.length === 0) {
      setError('Agrega al menos un producto.')
      return
    }

    const cantidadesInvalidas = seleccionados.some(
      (producto) =>
        !producto.cantidad ||
        !Number.isFinite(Number(producto.cantidad)) ||
        Number(producto.cantidad) <= 0,
    )

    if (cantidadesInvalidas) {
      setError(
        'Todas las cantidades deben ser mayores que cero.',
      )
      return
    }

    try {
      setGuardando(true)
      setError('')
      setMensaje('')

      const respuesta = await registrarMovimiento(token, {
        motivo_movimiento: motivo,
        fecha_movimiento: fecha,
        id_local_destino: configuracion.requiere_local ? Number(local) : undefined,
        local_relacionado: null,
        id_proveedor:
          configuracion.requiere_proveedor
            ? Number(idProveedor)
            : null,
        observacion: observacion.trim() || null,
        detalles: seleccionados.map((producto) => ({
          id_producto: producto.id_producto,
          cantidad: Number(producto.cantidad),
        })),
      })

      setMensaje(
        `${respuesta.mensaje}. Código: ` +
          respuesta.movimiento.codigo,
      )
      setMotivo('')
      setLocal('')
      setIdProveedor('')
      setObservacion('')
      setSeleccionados([])
      setBusqueda('')
      setCategoria('TODAS')
    } catch (errorGuardado) {
      setError(
        errorGuardado instanceof Error
          ? errorGuardado.message
          : 'No se pudo registrar el movimiento.',
      )
    } finally {
      setGuardando(false)
    }
  }

  if (cargando) {
    return (
      <section className="movement-state">
        <LoaderCircle className="movement-spin" />
        Cargando productos...
      </section>
    )
  }

  return (
    <section className="movement-page">
      <header className="movement-header">
        <div>
          <span className="movement-header__label">
            MOVIMIENTOS DE INVENTARIO
          </span>
          <h1>Registrar movimiento</h1>
          <p>
            Registra préstamos, mermas y devoluciones de
            productos.
          </p>
        </div>

        <div className="movement-header__badge">
          <ClipboardPlus />
          <div>
            <small>NUEVO REGISTRO</small>
            <strong>
              {configuracion?.etiqueta ?? 'Selecciona un motivo'}
            </strong>
          </div>
        </div>
      </header>

      <Link to="/home/movimientos/seguimiento">Ver prestamos, devoluciones y recepciones pendientes</Link>

      {mensaje && (
        <div className="movement-alert success">
          <CheckCircle2 /> {mensaje}
        </div>
      )}

      {error && (
        <div className="movement-alert error">
          <AlertCircle /> {error}
        </div>
      )}

      <section className="movement-form-card">
        <div className="movement-section-title">
          <div>
            <span>DATOS GENERALES</span>
            <h2>Información del movimiento</h2>
          </div>
          {configuracion && (
            <div
              className={
                configuracion.tipo_movimiento === 'ENTRADA'
                  ? 'movement-type entry'
                  : 'movement-type exit'
              }
            >
              {configuracion.tipo_movimiento === 'ENTRADA'
                ? <ArrowDownToLine />
                : <ArrowUpFromLine />}
              {configuracion.tipo_movimiento}
            </div>
          )}
        </div>

        <div className="movement-fields">
          <label>
            Motivo
            <select
              value={motivo}
              onChange={(event) =>
                seleccionarMotivo(event.target.value)
              }
            >
              <option value="">Seleccionar motivo</option>
              {datos?.motivos.map((item) => (
                <option key={item.valor} value={item.valor}>
                  {item.etiqueta}
                </option>
              ))}
            </select>
          </label>

          <label>
            Fecha
            <input
              type="date"
              value={fecha}
              onChange={(event) => setFecha(event.target.value)}
            />
          </label>

          {configuracion?.requiere_local && (
            <label>
              Local destino
              <select value={local} onChange={e => setLocal(e.target.value)}>
                <option value="">Seleccionar local</option>
                {datos?.locales.map(l => <option key={l.id_local} value={l.id_local}>{l.nombre}</option>)}
              </select>
            </label>
          )}

          {configuracion?.requiere_proveedor && (
            <label>
              Proveedor
              <select
                value={idProveedor}
                onChange={(event) =>
                  setIdProveedor(event.target.value)
                }
              >
                <option value="">Seleccionar proveedor</option>
                {datos?.proveedores.map((proveedor) => (
                  <option
                    key={proveedor.id_proveedor}
                    value={proveedor.id_proveedor}
                  >
                    {proveedor.nombre}
                  </option>
                ))}
              </select>
            </label>
          )}

          <label className="movement-observation">
            Observación
            <textarea
              value={observacion}
              maxLength={500}
              onChange={(event) =>
                setObservacion(event.target.value)
              }
              placeholder="Detalle opcional del movimiento"
            />
            <small>{observacion.length}/500</small>
          </label>
        </div>
      </section>

      <section className="movement-products-card">
        <div className="movement-section-title">
          <div>
            <span>PRODUCTOS</span>
            <h2>Seleccionar productos</h2>
          </div>
          <p>{seleccionados.length} productos agregados</p>
        </div>

        <div className="movement-filters">
          <label className="movement-search">
            <Search />
            <input
              value={busqueda}
              onChange={(event) => setBusqueda(event.target.value)}
              placeholder="Buscar por código o producto"
            />
          </label>

          <select
            value={categoria}
            onChange={(event) => setCategoria(event.target.value)}
          >
            <option value="TODAS">Todas las categorías</option>
            {datos?.categorias.map((item) => (
              <option key={item} value={item}>{item}</option>
            ))}
          </select>
        </div>

        <div className="movement-catalog">
          {productosFiltrados.slice(0, 12).map((producto) => (
            <button
              type="button"
              key={producto.id_producto}
              onClick={() => agregarProducto(producto)}
            >
              <span className="movement-product-icon">
                <PackagePlus />
              </span>
              <div>
                <b>{producto.codigo}</b>
                <strong>{producto.nombre}</strong>
                <small>
                  {producto.categoria} · {formatearUnidad(producto.unidad)}
                </small>
              </div>
              <Plus />
            </button>
          ))}

          {productosFiltrados.length === 0 && (
            <p className="movement-empty">
              No hay productos disponibles con ese filtro.
            </p>
          )}
        </div>

        <div className="movement-selected">
          <h3>Productos del movimiento</h3>

          {seleccionados.map((producto) => (
            <div
              className="movement-selected-row"
              key={producto.id_producto}
            >
              <b>{producto.codigo}</b>
              <div>
                <strong>{producto.nombre}</strong>
                <small>{producto.categoria}</small>
              </div>
              <label>
                Cantidad
                <span>
                  <input
                    type="number"
                    min="0"
                    step="any"
                    value={producto.cantidad}
                    onChange={(event) =>
                      cambiarCantidad(
                        producto.id_producto,
                        event.target.value,
                      )
                    }
                  />
                  <b>{formatearUnidad(producto.unidad)}</b>
                </span>
              </label>
              <button
                type="button"
                aria-label="Quitar producto"
                onClick={() =>
                  quitarProducto(producto.id_producto)
                }
              >
                <Trash2 />
              </button>
            </div>
          ))}

          {seleccionados.length === 0 && (
            <p className="movement-empty selected-empty">
              Agrega los productos que forman parte del movimiento.
            </p>
          )}
        </div>

        <footer className="movement-actions">
          <div>
            <small>Tipo de operación</small>
            <strong>
              {configuracion?.tipo_movimiento ?? 'Sin seleccionar'}
            </strong>
          </div>
          <button
            type="button"
            disabled={guardando}
            onClick={() => void guardar()}
          >
            {guardando
              ? <LoaderCircle className="movement-spin" />
              : <Save />}
            {guardando
              ? 'Registrando...'
              : 'Registrar movimiento'}
          </button>
        </footer>
      </section>
    </section>
  )
}