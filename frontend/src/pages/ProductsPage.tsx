import { DeleteRecordButton } from '../components/catalogs/DeleteRecordButton'
import {
  AlertTriangle,
  Boxes,
  CheckCircle2,
  CircleOff,
  Layers3,
  PackageSearch,
  RefreshCw,
  Search,
  Truck,
} from 'lucide-react'
import {
  useCallback,
  useEffect,
  useMemo,
  useState,
} from 'react'

import { CatalogDialog } from '../components/catalogs/CatalogDialog'
import { useAuth } from '../context/AuthContext'
import {
  cambiarEstadoProducto,
  crearProducto,
  editarProducto,
  obtenerProductosCatalogo,
} from '../services/catalogService'
import type {
  ProductoCatalogo,
  RespuestaCatalogoProductos,
  UnidadProducto,
} from '../types/catalog'
import { permisosDe } from '../utils/permissionHelpers'
import { formatearUnidad } from '../utils/unitHelpers'

import './ProductsPage.css'

type FiltroEstado = 'todos' | 'activos' | 'inactivos'

function formatearNumero(valor: number): string {
  return new Intl.NumberFormat('es-PE', {
    maximumFractionDigits: 3,
  }).format(valor)
}

export function ProductsPage() {
  const { token, menu, perfilActivo } = useAuth()
  const permisos = permisosDe(menu, 4)
  const administrador = perfilActivo?.id_perfil === 1
  const mostrarAcciones = administrador || (
    permisos.editar || permisos.desactivar || permisos.reactivar || permisos.eliminar
  )

  const [modal, setModal] = useState(false)
  const [editando, setEditando] =
    useState<ProductoCatalogo | null>(null)
  const [procesando, setProcesando] = useState(false)
  const [formulario, setFormulario] = useState({
    nombre: '',
    id_categoria: '',
    id_proveedor: '',
    unidad: 'KGM' as UnidadProducto,
    presentacion: '1',
  })

  const [datos, setDatos] =
    useState<RespuestaCatalogoProductos | null>(null)

  const [busqueda, setBusqueda] = useState('')
  const [categoria, setCategoria] = useState('todas')
  const [proveedor, setProveedor] = useState('todos')

  const [estado, setEstado] =
    useState<FiltroEstado>('todos')

  const [cargando, setCargando] = useState(true)
  const [actualizando, setActualizando] = useState(false)
  const [error, setError] = useState('')

  const cargarProductos = useCallback(
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
          await obtenerProductosCatalogo(token)

        setDatos(respuesta)
      } catch (errorDesconocido) {
        const mensaje =
          errorDesconocido instanceof Error
            ? errorDesconocido.message
            : 'No fue posible cargar los productos.'

        setError(mensaje)
      } finally {
        setCargando(false)
        setActualizando(false)
      }
    },
    [token],
  )

  useEffect(() => {
    void cargarProductos()
  }, [cargarProductos])

  const productosFiltrados = useMemo(() => {
    if (!datos) {
      return []
    }

    const texto = busqueda.trim().toLocaleLowerCase('es')

    return datos.productos.filter((producto) => {
      const coincideBusqueda =
        texto === '' ||
        producto.codigo
          .toLocaleLowerCase('es')
          .includes(texto) ||
        producto.nombre
          .toLocaleLowerCase('es')
          .includes(texto) ||
        producto.categoria
          .toLocaleLowerCase('es')
          .includes(texto) ||
        producto.proveedor
          .toLocaleLowerCase('es')
          .includes(texto)

      const coincideCategoria =
        categoria === 'todas' ||
        producto.id_categoria === Number(categoria)

      const coincideProveedor =
        proveedor === 'todos' ||
        producto.id_proveedor === Number(proveedor)

      const coincideEstado =
        estado === 'todos' ||
        (estado === 'activos' && producto.activo) ||
        (estado === 'inactivos' && !producto.activo)

      return (
        coincideBusqueda &&
        coincideCategoria &&
        coincideProveedor &&
        coincideEstado
      )
    })
  }, [
    busqueda,
    categoria,
    datos,
    estado,
    proveedor,
  ])

  const hayFiltros =
    busqueda.trim() !== '' ||
    categoria !== 'todas' ||
    proveedor !== 'todos' ||
    estado !== 'todos'

  function limpiarFiltros() {
    setBusqueda('')
    setCategoria('todas')
    setProveedor('todos')
    setEstado('todos')
  }

  function abrirProducto(producto?: ProductoCatalogo) {
    setError('')
    setEditando(producto ?? null)

    setFormulario(
      producto
        ? {
            nombre: producto.nombre,
            id_categoria: String(producto.id_categoria),
            id_proveedor: String(producto.id_proveedor),
            unidad: producto.unidad,
            presentacion: String(producto.presentacion),
          }
        : {
            nombre: '',
            id_categoria: '',
            id_proveedor: '',
            unidad: 'KGM',
            presentacion: '1',
          },
    )

    setModal(true)
  }

  async function guardarProducto() {
    if (!token) {
      setError('No existe una sesión válida.')
      return
    }

    const entrada = {
      nombre: formulario.nombre.trim(),
      id_categoria: Number(formulario.id_categoria),
      id_proveedor: Number(formulario.id_proveedor),
      unidad: formulario.unidad,
      presentacion: Number(formulario.presentacion),
      motivo: 'Actualización administrativa del catálogo',
    }

    if (
      !entrada.nombre ||
      !entrada.id_categoria ||
      !entrada.id_proveedor ||
      !Number.isFinite(entrada.presentacion) ||
      entrada.presentacion <= 0
    ) {
      setError('Completa correctamente todos los campos.')
      return
    }

    try {
      setError('')
      setProcesando(true)

      if (editando) {
        await editarProducto(
          token,
          editando.id_producto,
          entrada,
        )
      } else {
        await crearProducto(token, entrada)
      }

      setModal(false)
      await cargarProductos(true)
    } catch (errorDesconocido) {
      const mensaje =
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se pudo guardar el producto.'

      setError(mensaje)
    } finally {
      setProcesando(false)
    }
  }

  async function alternarProducto(
    producto: ProductoCatalogo,
  ) {
    if (!token) {
      setError('No existe una sesión válida.')
      return
    }

    const accion = producto.activo
      ? 'desactivar'
      : 'reactivar'

    const motivo = window.prompt(
      `Motivo para ${accion} ${producto.nombre}:`,
    )

    if (!motivo || motivo.trim().length < 10) {
      setError('El motivo debe tener al menos 10 caracteres.')
      return
    }

    if (!window.confirm('¿Confirmas esta operación?')) {
      return
    }

    try {
      setError('')
      setActualizando(true)

      await cambiarEstadoProducto(
        token,
        producto.id_producto,
        !producto.activo,
        motivo.trim(),
      )

      await cargarProductos(true)
    } catch (errorDesconocido) {
      const mensaje =
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se pudo cambiar el estado.'

      setError(mensaje)
    } finally {
      setActualizando(false)
    }
  }

  if (cargando) {
    return (
      <section className="products-state">
        <RefreshCw
          className="products-state__spinner"
          aria-hidden="true"
        />

        <div>
          <h1>Cargando productos</h1>
          <p>Estamos consultando el catálogo.</p>
        </div>
      </section>
    )
  }

  if (error && !datos) {
    return (
      <section className="products-state products-state--error">
        <AlertTriangle aria-hidden="true" />

        <div>
          <h1>No se pudo cargar el catálogo</h1>
          <p>{error}</p>

          <button
            type="button"
            onClick={() => void cargarProductos()}
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

  return (
    <section className="products-page">
      <header className="products-header">
        <div className="products-header__content">
          <span className="products-header__eyebrow">
            CATÁLOGO DE INVENTARIO
          </span>

          <h1>Productos</h1>

          <p>
            Consulta los insumos, sus categorías,
            proveedores y parámetros de inventario.
          </p>
        </div>

        <div className="catalog-admin-actions">
          {(administrador || permisos.crear) && (
            <button
              className="catalog-admin-new"
              type="button"
              onClick={() => abrirProducto()}
            >
              Nuevo producto
            </button>
          )}

          <button
            className="products-refresh"
            type="button"
            disabled={actualizando}
            onClick={() => void cargarProductos(true)}
          >
            <RefreshCw
              className={
                actualizando
                  ? 'products-refresh__spinning'
                  : ''
              }
              aria-hidden="true"
            />

            {actualizando
              ? 'Actualizando...'
              : 'Actualizar catálogo'}
          </button>
        </div>
      </header>

      <div className="products-summary">
        <article className="products-summary-card">
          <span className="products-summary-card__icon">
            <Boxes aria-hidden="true" />
          </span>

          <div>
            <span>Total de productos</span>
            <strong>
              {datos.resumen.total_productos}
            </strong>
          </div>
        </article>

        <article className="products-summary-card">
          <span className="products-summary-card__icon products-summary-card__icon--active">
            <CheckCircle2 aria-hidden="true" />
          </span>

          <div>
            <span>Productos activos</span>
            <strong>
              {datos.resumen.productos_activos}
            </strong>
          </div>
        </article>

        <article className="products-summary-card">
          <span className="products-summary-card__icon products-summary-card__icon--inactive">
            <CircleOff aria-hidden="true" />
          </span>

          <div>
            <span>Productos inactivos</span>
            <strong>
              {datos.resumen.productos_inactivos}
            </strong>
          </div>
        </article>

        <article className="products-summary-card">
          <span className="products-summary-card__icon products-summary-card__icon--category">
            <Layers3 aria-hidden="true" />
          </span>

          <div>
            <span>Categorías</span>
            <strong>
              {datos.resumen.total_categorias}
            </strong>
          </div>
        </article>

        <article className="products-summary-card">
          <span className="products-summary-card__icon products-summary-card__icon--supplier">
            <Truck aria-hidden="true" />
          </span>

          <div>
            <span>Proveedores</span>
            <strong>
              {datos.resumen.total_proveedores}
            </strong>
          </div>
        </article>
      </div>

      {!datos.categorias_proveedor_configurables && (
        <div className="products-warning" role="status">
          El catálogo está disponible. Las categorías se muestran según los productos
          existentes hasta completar la actualización de proveedores en la base de datos.
        </div>
      )}

      {error && (
        <div className="products-warning" role="alert">
          <AlertTriangle aria-hidden="true" />
          {error}
        </div>
      )}

      <section className="products-content">
        <div className="products-content__heading">
          <div>
            <span>LISTADO GENERAL</span>
            <h2>Catálogo de productos</h2>
          </div>

          <p>Información registrada en la base de datos.</p>
        </div>

        <div className="products-filters">
          <label className="products-search">
            <Search aria-hidden="true" />

            <input
              type="search"
              value={busqueda}
              onChange={(evento) =>
                setBusqueda(evento.target.value)
              }
              placeholder="Buscar por código, producto, categoría o proveedor"
              aria-label="Buscar productos"
            />
          </label>

          <select
            value={categoria}
            onChange={(evento) =>
              setCategoria(evento.target.value)
            }
            aria-label="Filtrar por categoría"
          >
            <option value="todas">
              Todas las categorías
            </option>

            {datos.categorias.map((item) => (
              <option
                key={item.id_categoria}
                value={item.id_categoria}
              >
                {item.nombre}
              </option>
            ))}
          </select>

          <select
            value={proveedor}
            onChange={(evento) =>
              setProveedor(evento.target.value)
            }
            aria-label="Filtrar por proveedor"
          >
            <option value="todos">
              Todos los proveedores
            </option>

            {datos.proveedores.map((item) => (
              <option
                key={item.id_proveedor}
                value={item.id_proveedor}
              >
                {item.nombre}
              </option>
            ))}
          </select>

          <select
            value={estado}
            onChange={(evento) =>
              setEstado(
                evento.target.value as FiltroEstado,
              )
            }
            aria-label="Filtrar por estado"
          >
            <option value="todos">
              Todos los estados
            </option>
            <option value="activos">Activos</option>
            <option value="inactivos">Inactivos</option>
          </select>

          <button
            className="products-clear"
            type="button"
            onClick={limpiarFiltros}
            disabled={!hayFiltros}
          >
            Limpiar
          </button>
        </div>

        <p className="products-results">
          Mostrando{' '}
          <strong>{productosFiltrados.length}</strong>{' '}
          de <strong>{datos.productos.length}</strong>{' '}
          productos
        </p>

        <div className="products-table-container">
          <table className="products-table">
            <thead>
              <tr>
                <th>Código</th>
                <th>Producto</th>
                <th>Categoría</th>
                <th>Proveedor</th>
                <th>Unidad</th>
                <th>Presentación</th>
                <th>Estado</th>
                {mostrarAcciones && <th>Acciones</th>}
              </tr>
            </thead>

            <tbody>
              {productosFiltrados.map((producto) => (
                <tr key={producto.id_producto}>
                  <td>
                    <span className="products-code">
                      {producto.codigo}
                    </span>
                  </td>

                  <td>
                    <strong className="products-name">
                      {producto.nombre}
                    </strong>
                  </td>

                  <td>{producto.categoria}</td>

                  <td>
                    <span className="products-supplier">
                      <Truck aria-hidden="true" />
                      {producto.proveedor}
                    </span>
                  </td>

                  <td>{formatearUnidad(producto.unidad)}</td>

                  <td>
                    {formatearNumero(
                      producto.presentacion,
                    )}{' '}
                    {formatearUnidad(producto.unidad)}
                  </td>

                  <td>
                    <span
                      className={
                        producto.activo
                          ? 'products-status products-status--active'
                          : 'products-status products-status--inactive'
                      }
                    >
                      {producto.activo
                        ? 'Activo'
                        : 'Inactivo'}
                    </span>
                  </td>

                  {mostrarAcciones && <td>
                    <div className="catalog-admin-actions">
                      {(administrador || permisos.editar) && <button
                        type="button"
                        onClick={() => abrirProducto(producto)}
                      >Editar</button>}
                      {(administrador || permisos.eliminar) && <DeleteRecordButton token={token} entidad="productos" id={producto.id_producto} nombre={producto.nombre} eliminado={() => void cargarProductos(true)} />}
                      {(producto.activo ? (administrador || permisos.desactivar) : (administrador || permisos.reactivar)) && <button
                        className={producto.activo ? 'danger' : ''}
                        type="button"
                        onClick={() => void alternarProducto(producto)}
                      >{producto.activo ? 'Desactivar' : 'Reactivar'}</button>}
                    </div>
                  </td>}
                </tr>
              ))}

              {productosFiltrados.length === 0 && (
                <tr>
                  <td colSpan={mostrarAcciones ? 8 : 7}>
                    <div className="products-empty">
                      <PackageSearch aria-hidden="true" />

                      <strong>
                        No se encontraron productos
                      </strong>

                      <span>
                        Prueba modificando o limpiando
                        los filtros.
                      </span>
                    </div>
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

      <CatalogDialog
        titulo={editando ? 'Editar producto' : 'Nuevo producto'}
        abierto={modal}
        procesando={procesando}
        guardar={guardarProducto}
        cerrar={() => setModal(false)}
      >
        <label>
          Nombre
          <input
            value={formulario.nombre}
            onChange={(evento) =>
              setFormulario({
                ...formulario,
                nombre: evento.target.value,
              })
            }
          />
        </label>

        <div className="products-form-note">
          <strong>Asignación del producto</strong>
          <span>
            Selecciona primero el proveedor y luego una de sus categorías.
            Si tiene una sola categoría activa, se selecciona automáticamente.
            La categoría define el prefijo y el código.
          </span>
        </div>

        <label>
          Proveedor
          <select
            value={formulario.id_proveedor}
            onChange={(evento) => {
              const id = evento.target.value
              const proveedorSeleccionado = datos.proveedores.find((p) => p.id_proveedor === Number(id))
              const categoriasDisponibles = datos.categorias.filter((c) =>
                c.activo && proveedorSeleccionado?.ids_categorias.includes(c.id_categoria),
              )
              setFormulario({
                ...formulario,
                id_proveedor: id,
                id_categoria: categoriasDisponibles.length === 1
                  ? String(categoriasDisponibles[0].id_categoria) : '',
              })
            }}
          >
            <option value="">Selecciona</option>

            {datos.proveedores
              .filter((item) => item.activo)
              .map((item) => (
                <option
                  key={item.id_proveedor}
                  value={item.id_proveedor}
                >
                  {item.nombre}
                </option>
              ))}
          </select>
        </label>

        <label>
          Categoría
          <select
            disabled={!formulario.id_proveedor}
            value={formulario.id_categoria}
            onChange={(evento) =>
              setFormulario({
                ...formulario,
                id_categoria: evento.target.value,
              })
            }
          >
            <option value="">Selecciona</option>

            {datos.categorias
              .filter((item) => item.activo &&
                datos.proveedores.find((p) => p.id_proveedor === Number(formulario.id_proveedor))
                  ?.ids_categorias.includes(item.id_categoria))
              .map((item) => (
                <option
                  key={item.id_categoria}
                  value={item.id_categoria}
                >
                  {item.nombre}
                </option>
              ))}
          </select>
        </label>

        {formulario.id_proveedor && !datos.categorias.some((c) => c.activo &&
          datos.proveedores.find((p) => p.id_proveedor === Number(formulario.id_proveedor))?.ids_categorias.includes(c.id_categoria)) && (
          <p>Asigna categorías activas a este proveedor desde Proveedores.</p>
        )}

        <label>
          Unidad de medida
          <select
            disabled={!!editando}
            value={formulario.unidad}
            onChange={(evento) =>
              setFormulario({
                ...formulario,
                unidad: evento.target.value as UnidadProducto,
              })
            }
          >
            {datos.unidades_medida.filter((u) => u.codigo === u.codigo_base).map((u) => (
              <option key={u.codigo} value={u.valor}>
                {u.nombre.toLocaleLowerCase('es') === u.simbolo ? u.nombre : `${u.nombre} (${u.simbolo})`}
              </option>
            ))}
          </select>
        </label>

        <label>
          Contenido por envase o paquete ({formatearUnidad(formulario.unidad)})
          <input
            type="number"
            min="0.001"
            step="any"
            value={formulario.presentacion}
            onChange={(evento) =>
              setFormulario({
                ...formulario,
                presentacion: evento.target.value,
              })
            }
          />
        </label>
        <p className="products-form-note">
          El contenido de compra se expresa en {formatearUnidad(formulario.unidad)}.
          Por ejemplo, un barril de 30 L contiene 30; una botella de 750 mL contiene
          0,750 si la unidad del producto es L.
          {editando && ' La unidad se conserva para mantener correctas las cantidades registradas.'}
        </p>
      </CatalogDialog>
    </section>
  )
}
