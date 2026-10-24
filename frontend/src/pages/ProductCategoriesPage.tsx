import { DeleteRecordButton } from '../components/catalogs/DeleteRecordButton'
import {
  AlertTriangle,
  Boxes,
  CheckCircle2,
  CircleOff,
  RefreshCw,
  Search,
  Tags,
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
  cambiarEstadoCategoria,
  consultarDependenciasCategoria,
  crearCategoria,
  editarCategoria,
  obtenerCategoriasProducto,
  reasignarCategoria,
} from '../services/catalogService'
import type {
  CategoriaProductoDetalle,
  RespuestaCategoriasProducto,
} from '../types/catalog'
import { permisosDe } from '../utils/permissionHelpers'

import './ProductCategoriesPage.css'

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

export function ProductCategoriesPage() {
  const { token, menu } = useAuth()
  const permisos = permisosDe(menu, 5)

  const [modal, setModal] = useState(false)
  const [categoriaEditada, setCategoriaEditada] =
    useState<CategoriaProductoDetalle | null>(null)
  const [nombre, setNombre] = useState('')
  const [prefijo, setPrefijo] = useState('')
  const [procesando, setProcesando] = useState(false)

  const [datos, setDatos] =
    useState<RespuestaCategoriasProducto | null>(null)

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
          await obtenerCategoriasProducto(token)

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

  function abrirCategoria(
    categoria?: CategoriaProductoDetalle,
  ) {
    setError('')
    setCategoriaEditada(categoria ?? null)
    setNombre(categoria?.nombre ?? '')
    setPrefijo(categoria?.prefijo ?? '')
    setModal(true)
  }

  async function guardarCategoria() {
    if (!token) {
      setError('No existe una sesión válida.')
      return
    }

    const nombreLimpio = nombre.trim()
    const prefijoLimpio = prefijo.trim().toUpperCase()

    if (!nombreLimpio) {
      setError('Ingresa el nombre de la categoría.')
      return
    }

    if (!/^[A-Z0-9]{1,3}$/.test(prefijoLimpio)) {
      setError(
        'El prefijo debe tener entre 1 y 3 letras o números.',
      )
      return
    }

    try {
      setError('')
      setProcesando(true)

      if (categoriaEditada) {
        await editarCategoria(
          token,
          categoriaEditada.id_categoria,
          { nombre: nombreLimpio, prefijo: prefijoLimpio },
        )
      } else {
        await crearCategoria(token, {
          nombre: nombreLimpio,
          prefijo: prefijoLimpio,
        })
      }

      setModal(false)
      await cargarCategorias(true)
    } catch (errorDesconocido) {
      setError(
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se pudo guardar la categoría.',
      )
    } finally {
      setProcesando(false)
    }
  }

  async function reasignarProductos(
    categoria: CategoriaProductoDetalle,
  ) {
    if (!token) return

    try {
      setError('')
      const dependencia =
        await consultarDependenciasCategoria(
          token,
          categoria.id_categoria,
        )

      const productosActivos = dependencia.productos.filter(
        (producto) => producto.activo,
      )

      if (productosActivos.length === 0) {
        window.alert(
          'Esta categoría no tiene productos activos para reasignar.',
        )
        return
      }

      const destinos = datos?.categorias.filter(
        (item) =>
          item.activo &&
          item.id_categoria !== categoria.id_categoria,
      ) ?? []

      if (destinos.length === 0) {
        setError(
          'No existe otra categoría activa para realizar la reasignación.',
        )
        return
      }

      const opciones = destinos
        .map((item) => `${item.id_categoria}: ${item.nombre}`)
        .join('\n')

      const idDestino = window.prompt(
        `Escribe el ID de la categoría destino:\n\n${opciones}`,
      )

      if (idDestino === null) return

      const destino = destinos.find(
        (item) => item.id_categoria === Number(idDestino),
      )

      if (!destino) {
        setError('Selecciona un ID de categoría destino válido.')
        return
      }

      const motivo = window.prompt(
        `Motivo para reasignar los productos a ${destino.nombre}:`,
      )

      if (!motivo || motivo.trim().length < 10) {
        setError('El motivo debe tener al menos 10 caracteres.')
        return
      }

      if (!window.confirm(
        `¿Reasignar ${productosActivos.length} producto(s) a ${destino.nombre}?`,
      )) return

      setActualizando(true)
      await reasignarCategoria(token, categoria.id_categoria, {
        id_categoria_nueva: destino.id_categoria,
        ids_productos: productosActivos.map(
          (producto) => producto.id_producto,
        ),
        motivo: motivo.trim(),
      })

      const verificacion =
        await consultarDependenciasCategoria(
          token,
          categoria.id_categoria,
        )

      await cargarCategorias(true)

      if (verificacion.productos_activos === 0) {
        window.alert(
          'Los productos fueron reasignados. Ya puedes desactivar la categoría.',
        )
      }
    } catch (errorDesconocido) {
      setError(
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se pudieron reasignar los productos.',
      )
    } finally {
      setActualizando(false)
    }
  }

  async function cambiarEstado(
    categoria: CategoriaProductoDetalle,
  ) {
    if (!token) return

    try {
      setError('')

      if (categoria.activo) {
        const dependencia =
          await consultarDependenciasCategoria(
            token,
            categoria.id_categoria,
          )

        if (dependencia.productos_activos > 0) {
          setError(
            'La categoría tiene productos activos. Debes reasignarlos o desactivarlos primero.',
          )
          return
        }
      }

      const accion = categoria.activo
        ? 'desactivar'
        : 'reactivar'
      const motivo = window.prompt(
        `Motivo para ${accion} ${categoria.nombre}:`,
      )

      if (!motivo || motivo.trim().length < 10) {
        setError('El motivo debe tener al menos 10 caracteres.')
        return
      }

      if (!window.confirm('¿Confirmas esta operación?')) return

      setActualizando(true)
      await cambiarEstadoCategoria(
        token,
        categoria.id_categoria,
        !categoria.activo,
        motivo.trim(),
      )
      await cargarCategorias(true)
    } catch (errorDesconocido) {
      setError(
        errorDesconocido instanceof Error
          ? errorDesconocido.message
          : 'No se pudo cambiar el estado de la categoría.',
      )
    } finally {
      setActualizando(false)
    }
  }

  if (cargando) {
    return (
      <section className="categories-state">
        <RefreshCw
          className="categories-spinner"
          aria-hidden="true"
        />

        <div>
          <h1>Cargando categorías</h1>
          <p>Consultando el catálogo de productos.</p>
        </div>
      </section>
    )
  }

  if (error && !datos) {
    return (
      <section className="categories-state categories-state--error">
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
    <section className="categories-page">
      <header className="categories-header">
        <div className="categories-header__content">
          <span className="categories-header__eyebrow">
            CATÁLOGO DE INVENTARIO
          </span>

          <h1>Categorías de productos</h1>

          <p>
            Consulta la clasificación utilizada para
            organizar y codificar los productos.
          </p>
        </div>

        <div className="catalog-admin-actions">
          {permisos.crear && (
            <button
              className="catalog-admin-new"
              type="button"
              onClick={() => abrirCategoria()}
            >
              Nueva categoría
            </button>
          )}

          <button
            className="categories-refresh"
            type="button"
            disabled={actualizando}
            onClick={() => void cargarCategorias(true)}
          >
          <RefreshCw
            className={
              actualizando ? 'categories-spinner' : ''
            }
            aria-hidden="true"
          />

          {actualizando
            ? 'Actualizando...'
            : 'Actualizar categorías'}
          </button>
        </div>
      </header>

      <div className="categories-summary">
        <article className="categories-summary-card">
          <span className="categories-summary-card__icon">
            <Tags aria-hidden="true" />
          </span>

          <div>
            <span>Total de categorías</span>
            <strong>
              {datos.resumen.total_categorias}
            </strong>
          </div>
        </article>

        <article className="categories-summary-card">
          <span className="categories-summary-card__icon categories-summary-card__icon--active">
            <CheckCircle2 aria-hidden="true" />
          </span>

          <div>
            <span>Categorías activas</span>
            <strong>
              {datos.resumen.categorias_activas}
            </strong>
          </div>
        </article>

        <article className="categories-summary-card">
          <span className="categories-summary-card__icon categories-summary-card__icon--inactive">
            <CircleOff aria-hidden="true" />
          </span>

          <div>
            <span>Categorías inactivas</span>
            <strong>
              {datos.resumen.categorias_inactivas}
            </strong>
          </div>
        </article>

        <article className="categories-summary-card">
          <span className="categories-summary-card__icon categories-summary-card__icon--products">
            <Boxes aria-hidden="true" />
          </span>

          <div>
            <span>Productos asociados</span>
            <strong>
              {
                datos.resumen
                  .total_productos_asociados
              }
            </strong>
          </div>
        </article>
      </div>

      {error && (
        <div className="categories-warning" role="alert">
          <AlertTriangle aria-hidden="true" />
          {error}
        </div>
      )}

      <section className="categories-content">
        <div className="categories-content__heading">
          <div>
            <span>CLASIFICACIÓN</span>
            <h2>Listado de categorías</h2>
          </div>

          <p>
            Cada prefijo permite generar códigos únicos.
          </p>
        </div>

        <div className="categories-filters">
          <label className="categories-search">
            <Search aria-hidden="true" />

            <input
              type="search"
              value={busqueda}
              onChange={(evento) =>
                setBusqueda(evento.target.value)
              }
              placeholder="Buscar por nombre o prefijo"
              aria-label="Buscar categorías"
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
            <option value="todas">
              Todos los estados
            </option>
            <option value="activas">Activas</option>
            <option value="inactivas">Inactivas</option>
          </select>

          <button
            className="categories-clear"
            type="button"
            disabled={!hayFiltros}
            onClick={limpiarFiltros}
          >
            Limpiar
          </button>
        </div>

        <p className="categories-results">
          Mostrando{' '}
          <strong>{categoriasFiltradas.length}</strong>{' '}
          de <strong>{datos.categorias.length}</strong>{' '}
          categorías
        </p>

        <div className="categories-table-container" role="region" aria-label="Listado de categorías" tabIndex={0}>
          <table className="categories-table">
            <thead>
              <tr>
                <th scope="col">Prefijo</th>
                <th scope="col">Categoría</th>
                <th scope="col" className="categories-table__number">Productos</th>
                <th scope="col" className="categories-table__number">Activos</th>
                <th scope="col" className="categories-table__number">Inactivos</th>
                <th scope="col">Siguiente código</th>
                <th scope="col">Estado</th>
                <th scope="col">Acciones</th>
              </tr>
            </thead>
            <tbody>
              {categoriasFiltradas.map((categoria) => (
                <tr key={categoria.id_categoria}>
                  <td><span className="category-prefix">{categoria.prefijo}</span></td>
                  <th scope="row" className="categories-table__name">{categoria.nombre}</th>
                  <td className="categories-table__number"><strong>{categoria.total_productos}</strong></td>
                  <td className="categories-table__number">{categoria.productos_activos}</td>
                  <td className="categories-table__number">{categoria.productos_inactivos}</td>
                  <td><span className="category-next-code">{generarSiguienteCodigo(categoria.prefijo, categoria.siguiente_numero)}</span></td>
                  <td>
                    <span className={`category-status ${categoria.activo ? 'category-status--active' : 'category-status--inactive'}`}>
                      {categoria.activo ? 'Activa' : 'Inactiva'}
                    </span>
                  </td>
                  <td>
                    <div className="catalog-admin-actions">
                      <button
                        type="button"
                        disabled={!permisos.editar}
                        onClick={() => abrirCategoria(categoria)}
                      >
                        Editar
                      </button>
{permisos.eliminar && <DeleteRecordButton token={token} entidad="categorias-productos" id={categoria.id_categoria} nombre={categoria.nombre} eliminado={() => void cargarCategorias(true)} />}

                      {categoria.activo && (
                        <button
                          type="button"
                          disabled={!permisos.configurar}
                          onClick={() =>
                            void reasignarProductos(categoria)
                          }
                        >
                          Reasignar
                        </button>
                      )}

                      <button
                        className={categoria.activo ? 'danger' : ''}
                        type="button"
                        disabled={
                          categoria.activo
                            ? !permisos.desactivar
                            : !permisos.reactivar
                        }
                        onClick={() => void cambiarEstado(categoria)}
                      >
                        {categoria.activo
                          ? 'Desactivar'
                          : 'Reactivar'}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {categoriasFiltradas.length === 0 && (
                <tr>
                  <td colSpan={8}>
                    <div className="categories-empty">
                      <Tags aria-hidden="true" />
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

      <CatalogDialog
        titulo={
          categoriaEditada
            ? 'Editar categoría'
            : 'Nueva categoría'
        }
        abierto={modal}
        procesando={procesando}
        guardar={guardarCategoria}
        cerrar={() => setModal(false)}
      >
        <label>
          Nombre
          <input
            value={nombre}
            onChange={(evento) => setNombre(evento.target.value)}
          />
        </label>

        <label>
          Prefijo
          <input
            maxLength={3}
            value={prefijo}
            onChange={(evento) =>
              setPrefijo(evento.target.value.toUpperCase())
            }
          />
        </label>
      </CatalogDialog>
    </section>
  )
}
