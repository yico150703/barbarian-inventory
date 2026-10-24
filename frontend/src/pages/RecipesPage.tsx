import { formatearUnidad } from '../utils/unitHelpers'
import { DeleteRecordButton } from '../components/catalogs/DeleteRecordButton'
import {
  AlertTriangle,
  BookOpen,
  CheckCircle2,
  ChevronDown,
  CircleOff,
  CookingPot,
  Layers3,
  RefreshCw,
  Search,
  UtensilsCrossed,
} from 'lucide-react'
import { Fragment, useCallback, useEffect, useMemo, useState } from 'react'

import { useAuth } from '../context/AuthContext'
import { obtenerRecetas } from '../services/recipeService'
import type { Receta, RespuestaRecetas } from '../types/recipe'
import { RecipeEditor } from '../components/recipes/RecipeEditor'
import { permisosDe } from '../utils/permissionHelpers'

import './RecipesPage.css'

type EstadoFiltro = 'todos' | 'activos' | 'inactivos'

export function RecipesPage() {
  const { token, menu } = useAuth()
  const permisos = permisosDe(menu, 28)
  const [editor, setEditor] = useState(false)
  const [editando, setEditando] = useState<Receta | null>(null)
  const [mensaje, setMensaje] = useState('')
  const [datos, setDatos] = useState<RespuestaRecetas | null>(null)
  const [busqueda, setBusqueda] = useState('')
  const [categoria, setCategoria] = useState('todas')
  const [estado, setEstado] = useState<EstadoFiltro>('todos')
  const [abierta, setAbierta] = useState<number | null>(null)
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
        if (actualizacion) {
          setActualizando(true)
        } else {
          setCargando(true)
        }
        setDatos(await obtenerRecetas(token))
      } catch (desconocido) {
        setError(
          desconocido instanceof Error
            ? desconocido.message
            : 'No se pudieron cargar las recetas.',
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

  const recetasFiltradas = useMemo(() => {
    const texto = busqueda.trim().toLocaleLowerCase('es')

    return (datos?.recetas ?? []).filter((receta) => {
      const coincideTexto =
        !texto ||
        receta.codigo_item.toLocaleLowerCase('es').includes(texto) ||
        receta.item_carta.toLocaleLowerCase('es').includes(texto) ||
        receta.componentes.some((comp) =>
          comp.nombre_componente.toLocaleLowerCase('es').includes(texto),
        ) ||
        (receta.grupo_salsa?.opciones ?? []).some((opcion) =>
          opcion.nombre.toLocaleLowerCase('es').includes(texto),
        )

      const coincideCategoria =
        categoria === 'todas' || receta.categoria_carta === categoria

      const coincideEstado =
        estado === 'todos' ||
        (estado === 'activos' && receta.activo) ||
        (estado === 'inactivos' && !receta.activo)

      return coincideTexto && coincideCategoria && coincideEstado
    })
  }, [busqueda, categoria, datos, estado])

  if (cargando) {
    return (
      <section className="recipes-state">
        <RefreshCw className="recipes-spin" />
        <div>
          <h1>Cargando recetas</h1>
          <p>Consultando catálogo de platos y bebidas.</p>
        </div>
      </section>
    )
  }

  if (error && !datos) {
    return (
      <section className="recipes-state recipes-state--error">
        <AlertTriangle />
        <div>
          <h1>No se pudieron cargar las recetas</h1>
          <p>{error}</p>
          <button type="button" onClick={() => void cargar()}>
            Intentar nuevamente
          </button>
        </div>
      </section>
    )
  }

  if (!datos) return null

  function limpiar() {
    setBusqueda('')
    setCategoria('todas')
    setEstado('todos')
  }

  return (
    <section className="recipes-page">
      <header className="recipes-header">
        <div>
          <span>RECETARIO Y PRODUCCIÓN</span>
          <h1>Recetas de la carta</h1>
          <p>
            Consulta la composición detallada, componentes e instrucciones de
            preparación de los ítems de la carta.
          </p>
        </div>

        <div className="recipes-header-actions">
        {permisos.crear && <button type="button" onClick={() => { setEditando(null); setEditor(true); setMensaje('') }}>Nueva receta</button>}
        <button
          type="button"
          disabled={actualizando}
          onClick={() => void cargar(true)}
        >
          <RefreshCw className={actualizando ? 'recipes-spin' : ''} />
          {actualizando ? 'Actualizando...' : 'Actualizar'}
        </button>
        </div>
      </header>

      <div className="recipes-summary">
        <article>
          <span><BookOpen /></span>
          <div>
            <small>Total de recetas</small>
            <strong>{datos.resumen.total_recetas}</strong>
          </div>
        </article>

        <article>
          <span className="green"><CheckCircle2 /></span>
          <div>
            <small>Recetas activas</small>
            <strong>{datos.resumen.recetas_activas}</strong>
          </div>
        </article>

        <article>
          <span className="red"><CircleOff /></span>
          <div>
            <small>Recetas inactivas</small>
            <strong>{datos.resumen.recetas_inactivas}</strong>
          </div>
        </article>

        <article>
          <span className="yellow"><Layers3 /></span>
          <div>
            <small>Categorías en carta</small>
            <strong>{datos.resumen.total_categorias}</strong>
          </div>
        </article>
      </div>

      {error && <p className="recipe-editor__error" role="alert">{error}</p>}
      {mensaje && <p className="recipes-success" role="status">{mensaje}</p>}
      <section className="recipes-content">
        <div className="recipes-title">
          <div>
            <span>LISTADO GENERAL</span>
            <h2>Ítems con receta configurada</h2>
          </div>
          <p>Despliega un plato para ver sus ingredientes e instrucciones.</p>
        </div>

        <div className="recipes-filters">
          <label>
            <Search />
            <input
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
              placeholder="Buscar por plato, código o ingrediente"
            />
          </label>

          <select
            value={categoria}
            onChange={(e) => setCategoria(e.target.value)}
          >
            <option value="todas">Todas las categorías</option>
            {datos.categorias.map((cat) => (
              <option key={cat} value={cat}>
                {cat}
              </option>
            ))}
          </select>

          <select
            value={estado}
            onChange={(e) => setEstado(e.target.value as EstadoFiltro)}
          >
            <option value="todos">Todos los estados</option>
            <option value="activos">Activas</option>
            <option value="inactivos">Inactivas</option>
          </select>

          <button type="button" onClick={limpiar}>
            Limpiar
          </button>
        </div>

        <p className="recipes-results">
          Mostrando <strong>{recetasFiltradas.length}</strong> de{' '}
          <strong>{datos.recetas.length}</strong> recetas
        </p>

        <div className="recipes-table-wrap">
          <table className="recipes-table">
            <thead>
              <tr>
                <th>Código</th>
                <th>Ítem de carta</th>
                <th>Categoría</th>
                <th>Presentación</th>
                <th>Tipo</th>
                <th>Ingredientes</th>
                <th>Estado</th>
                <th>Detalle</th>
                <th>Acciones</th>
              </tr>
            </thead>

            <tbody>
              {recetasFiltradas.map((receta) => {
                const estaAbierta = abierta === receta.id_receta

                return (
                  <Fragment key={receta.id_receta}>
                    <tr>
                      <td>
                        <b className="recipe-code">{receta.codigo_item}</b>
                      </td>
                      <td>
                        <strong>{receta.item_carta}</strong>
                      </td>
                      <td>{receta.categoria_carta}</td>
                      <td>
                        {receta.contenido} {formatearUnidad(receta.unidad_presentacion)}
                      </td>
                      <td>
                        {receta.tipo_item}
                      </td>
                      <td>{receta.total_componentes} ingredientes</td>
                      <td>
                        <span
                          className={
                            receta.activo
                              ? 'recipe-status active'
                              : 'recipe-status inactive'
                          }
                        >
                          {receta.activo ? 'Activa' : 'Inactiva'}
                        </span>
                      </td>
                      <td>
                        <button
                          className="recipe-detail-button"
                          type="button"
                          aria-label={`Ver detalle de ${receta.item_carta}`}
                          aria-expanded={estaAbierta}
                          onClick={() =>
                            setAbierta(estaAbierta ? null : receta.id_receta)
                          }
                        >
                          <ChevronDown
                            className={estaAbierta ? 'open' : ''}
                          />
                        </button>
                      </td>
                      <td>{permisos.editar && <button className="recipe-edit-button" type="button" onClick={() => { setEditando(receta); setEditor(true); setMensaje('') }}>Editar</button>}{permisos.eliminar && <DeleteRecordButton token={token} entidad="recetas" id={receta.id_receta} nombre={receta.item_carta} eliminado={() => void cargar(true)} />}</td>
                    </tr>

                    {estaAbierta && (
                      <tr className="recipe-detail-row">
                        <td colSpan={9}>
                          <div className="recipe-detail">
                            <div className="recipe-detail-instructions">
                              <strong>Instrucciones de preparación:</strong>
                              {receta.instrucciones}
                            </div>

                            <div className="recipe-components-grid">
                              {receta.componentes.map((comp) => (
                                <article
                                  className="recipe-component-card"
                                  key={comp.id_receta_detalle}
                                >
                                  <header>
                                    <small>{comp.codigo_componente}</small>
                                    <span
                                      className={`recipe-component-type ${comp.tipo_componente.toLowerCase()}`}
                                    >
                                      {comp.tipo_componente}
                                    </span>
                                  </header>
                                  <strong>{comp.nombre_componente}</strong>
                                  <span>
                                    {comp.cantidad} {formatearUnidad(comp.unidad)}
                                  </span>
                                </article>
                              ))}
                            </div>
                            {receta.grupo_salsa && (
                              <section className="recipe-sauce-section">
                                <header className="recipe-sauce-header">
                                  <div className="recipe-sauce-heading">
                                    <span className="recipe-sauce-icon">
                                      <CookingPot aria-hidden="true" />
                                    </span>

                                    <div>
                                      <strong>Productos elegibles / opciones de salsa</strong>
                                      <small>
                                        El cliente puede elegir hasta{' '}
                                        {receta.grupo_salsa.cantidad_maxima}{' '}
                                        {receta.grupo_salsa.cantidad_maxima === 1
                                          ? 'opción'
                                          : 'opciones'}.
                                      </small>
                                    </div>
                                  </div>

                                  <div className="recipe-sauce-badges">
                                    <span>
                                      Elegir {receta.grupo_salsa.cantidad_maxima}
                                    </span>
                                    <span>
                                      {receta.grupo_salsa.permite_repetir
                                        ? 'Permite repetir'
                                        : 'Sin repetir'}
                                    </span>
                                  </div>
                                </header>

                                {receta.grupo_salsa.opciones.length > 0 ? (
                                  <div className="recipe-sauce-grid">
                                    {receta.grupo_salsa.opciones.map((opcion) => (
                                      <article
                                        className="recipe-sauce-card"
                                        key={opcion.id_grupo_salsa_opcion}
                                      >
                                        <UtensilsCrossed aria-hidden="true" />

                                        <div>
                                          <small>{opcion.codigo}</small>
                                          <strong>{opcion.nombre}</strong>
                                          <span>
                                            {opcion.cantidad} {formatearUnidad(opcion.unidad)}
                                          </span>
                                        </div>
                                      </article>
                                    ))}
                                  </div>
                                ) : (
                                  <p className="recipe-sauce-empty">
                                    El grupo todavía no tiene opciones activas.
                                  </p>
                                )}
                              </section>
                            )}
                          </div>
                        </td>
                      </tr>
                    )}
                  </Fragment>
                )
              })}

              {recetasFiltradas.length === 0 && (
                <tr>
                  <td colSpan={9} style={{ textAlign: 'center', padding: 30 }}>
                    No se encontraron recetas que coincidan con la búsqueda.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
      {editor && token && (editando ? permisos.editar : permisos.crear) && <RecipeEditor
        key={`${token}-${editando?.id_receta ?? 'nueva'}`}
        token={token}
        receta={editando}
        cerrar={() => setEditor(false)}
        guardado={(texto) => { setEditor(false); setMensaje(texto); void cargar(true) }}
      />}
    </section>
  )
}
