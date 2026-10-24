import { formatearUnidad } from '../utils/unitHelpers'
import { DeleteRecordButton } from '../components/catalogs/DeleteRecordButton'
import {
  AlertTriangle,
  CheckCircle2,
  ChevronDown,
  CircleOff,
  Clock3,
  RefreshCw,
  Repeat2,
  Search,
  Tags,
  TicketPercent,
} from 'lucide-react'
import {
  Fragment,
  useCallback,
  useEffect,
  useMemo,
  useState,
} from 'react'

import { useAuth } from '../context/AuthContext'
import { PromotionEditor } from '../components/recipes/PromotionEditor'
import { permisosDe } from '../utils/permissionHelpers'
import {
  obtenerPromociones,
} from '../services/promotionService'
import type {
  RespuestaPromociones,
  PromocionDetalle,
} from '../types/promotion'

import './PromotionsPage.css'

type EstadoFiltro = 'todos' | 'activos' | 'inactivos'
type HorarioFiltro = 'todos' | 'horario' | 'permanentes'

function formatearPrecio(valor: number) {
  return new Intl.NumberFormat('es-PE', {
    style: 'currency',
    currency: 'PEN',
  }).format(valor)
}

export function PromotionsPage() {
  const { token, menu } = useAuth()
  const permisos = permisosDe(menu, 14)
  const [editor, setEditor] = useState(false)
  const [seleccionada, setSeleccionada] = useState<PromocionDetalle | null>(null)
  const [mensaje, setMensaje] = useState('')
  const [datos, setDatos] =
    useState<RespuestaPromociones | null>(null)
  const [busqueda, setBusqueda] = useState('')
  const [estado, setEstado] =
    useState<EstadoFiltro>('todos')
  const [horario, setHorario] =
    useState<HorarioFiltro>('todos')
  const [abierta, setAbierta] =
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

        if (actualizacion) {
          setActualizando(true)
        } else {
          setCargando(true)
        }

        setDatos(await obtenerPromociones(token))
      } catch (desconocido) {
        setError(
          desconocido instanceof Error
            ? desconocido.message
            : 'No se pudieron cargar las promociones.',
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

  const promocionesFiltradas = useMemo(() => {
    const texto = busqueda
      .trim()
      .toLocaleLowerCase('es')

    return (datos?.promociones ?? []).filter(
      (promocion) => {
        const coincideTexto =
          !texto ||
          promocion.codigo
            .toLocaleLowerCase('es')
            .includes(texto) ||
          promocion.nombre
            .toLocaleLowerCase('es')
            .includes(texto) ||
          promocion.grupos.some((grupo) =>
            grupo.opciones.some((opcion) =>
              opcion.item_carta
                .toLocaleLowerCase('es')
                .includes(texto),
            ),
          )

        const coincideEstado =
          estado === 'todos' ||
          (estado === 'activos' && promocion.activo) ||
          (
            estado === 'inactivos' &&
            !promocion.activo
          )

        const coincideHorario =
          horario === 'todos' ||
          (
            horario === 'horario' &&
            promocion.tiene_horario
          ) ||
          (
            horario === 'permanentes' &&
            !promocion.tiene_horario
          )

        return (
          coincideTexto &&
          coincideEstado &&
          coincideHorario
        )
      },
    )
  }, [busqueda, datos, estado, horario])

  if (cargando) {
    return (
      <section className="promotions-state">
        <RefreshCw className="promotions-spin" />
        <div>
          <h1>Cargando promociones</h1>
          <p>Consultando ofertas registradas.</p>
        </div>
      </section>
    )
  }

  if (error && !datos) {
    return (
      <section className="promotions-state promotions-state--error">
        <AlertTriangle />
        <div>
          <h1>No se pudieron cargar las promociones</h1>
          <p>{error}</p>
          <button
            type="button"
            onClick={() => void cargar()}
          >
            Intentar nuevamente
          </button>
        </div>
      </section>
    )
  }

  if (!datos) return null

  function limpiar() {
    setBusqueda('')
    setEstado('todos')
    setHorario('todos')
  }

  return (
    <section className="promotions-page">
      <header className="promotions-header">
        <div>
          <span>PROMOCIONES COMERCIALES</span>
          <h1>Promociones</h1>
          <p>
            Consulta precios, horarios y artículos
            disponibles dentro de cada promoción.
          </p>
        </div>

        <div className="production-header-actions">
        {permisos.crear && <button type="button" onClick={() => { setSeleccionada(null); setEditor(true) }}>Nueva promoción</button>}
        <button
          type="button"
          disabled={actualizando}
          onClick={() => void cargar(true)}
        >
          <RefreshCw
            className={
              actualizando ? 'promotions-spin' : ''
            }
          />
          {actualizando ? 'Actualizando...' : 'Actualizar'}
        </button>
        </div>
      </header>

      <div className="promotions-summary">
        <article>
          <span><TicketPercent /></span>
          <div>
            <small>Total de promociones</small>
            <strong>
              {datos.resumen.total_promociones}
            </strong>
          </div>
        </article>

        <article>
          <span className="green"><CheckCircle2 /></span>
          <div>
            <small>Promociones activas</small>
            <strong>
              {datos.resumen.promociones_activas}
            </strong>
          </div>
        </article>

        <article>
          <span className="red"><CircleOff /></span>
          <div>
            <small>Promociones inactivas</small>
            <strong>
              {datos.resumen.promociones_inactivas}
            </strong>
          </div>
        </article>

        <article>
          <span className="yellow"><Clock3 /></span>
          <div>
            <small>Con horario definido</small>
            <strong>
              {datos.resumen.promociones_con_horario}
            </strong>
          </div>
        </article>
      </div>

      <section className="promotions-content">
        {mensaje && <p role="status" className="production-feedback">{mensaje}</p>}
        {error && <p role="alert" className="production-feedback production-feedback--error">{error}</p>}
        <div className="promotions-title">
          <div>
            <span>LISTADO GENERAL</span>
            <h2>Promociones registradas</h2>
          </div>
          <p>
            Despliega una promoción para revisar sus opciones.
          </p>
        </div>

        <div className="promotions-filters">
          <label>
            <Search />
            <input
              value={busqueda}
              onChange={(evento) =>
                setBusqueda(evento.target.value)
              }
              placeholder="Buscar promoción o artículo"
            />
          </label>

          <select
            value={horario}
            onChange={(evento) =>
              setHorario(
                evento.target.value as HorarioFiltro,
              )
            }
          >
            <option value="todos">Todos los horarios</option>
            <option value="horario">Con horario</option>
            <option value="permanentes">Sin horario</option>
          </select>

          <select
            value={estado}
            onChange={(evento) =>
              setEstado(
                evento.target.value as EstadoFiltro,
              )
            }
          >
            <option value="todos">Todos los estados</option>
            <option value="activos">Activas</option>
            <option value="inactivos">Inactivas</option>
          </select>

          <button type="button" onClick={limpiar}>
            Limpiar
          </button>
        </div>

        <p className="promotions-results">
          Mostrando{' '}
          <strong>{promocionesFiltradas.length}</strong>{' '}
          de <strong>{datos.promociones.length}</strong>
        </p>

        <div className="promotions-table-wrap">
          <table className="promotions-table">
            <thead>
              <tr>
                <th>Código</th>
                <th>Promoción</th>
                <th>Precio</th>
                <th>Horario</th>
                <th>Grupos</th>
                <th>Opciones</th>
                <th>Estado</th>
                <th>Detalle</th>
                {(permisos.editar || permisos.eliminar) && <th>Acciones</th>}
              </tr>
            </thead>

            <tbody>
              {promocionesFiltradas.map((promocion) => {
                const estaAbierta =
                  abierta === promocion.id_promocion

                return (
                  <Fragment key={promocion.id_promocion}>
                    <tr>
                      <td>
                        <b className="promotion-code">
                          {promocion.codigo}
                        </b>
                      </td>
                      <td>
                        <strong>{promocion.nombre}</strong>
                      </td>
                      <td>
                        <strong>
                          {formatearPrecio(promocion.precio)}
                        </strong>
                      </td>
                      <td>
                        {promocion.tiene_horario ? (
                          <span className="promotion-time">
                            <Clock3 />
                            {promocion.hora_inicio} –{' '}
                            {promocion.hora_fin}
                          </span>
                        ) : (
                          <span className="promotion-permanent">
                            Sin horario
                          </span>
                        )}
                      </td>
                      <td>{promocion.total_grupos}</td>
                      <td>{promocion.total_opciones}</td>
                      <td>
                        <span
                          className={
                            promocion.activo
                              ? 'promotion-status active'
                              : 'promotion-status inactive'
                          }
                        >
                          {promocion.activo
                            ? 'Activa'
                            : 'Inactiva'}
                        </span>
                      </td>
                      <td>
                        <button
                          className="promotion-detail-button"
                          type="button"
                          aria-expanded={estaAbierta}
                          onClick={() =>
                            setAbierta(
                              estaAbierta
                                ? null
                                : promocion.id_promocion,
                            )
                          }
                        >
                          <ChevronDown
                            className={
                              estaAbierta ? 'open' : ''
                            }
                          />
                        </button>
                      </td>
                      {(permisos.editar || permisos.eliminar) && <td>{permisos.editar && <><button className="production-edit-button" type="button" onClick={() => { setSeleccionada(promocion); setEditor(true) }}>Editar</button></>}{permisos.eliminar && <DeleteRecordButton token={token} entidad="promociones" id={promocion.id_promocion} nombre={promocion.nombre} eliminado={() => void cargar(true)} />}</td>}
                    </tr>

                    {estaAbierta && (
                      <tr className="promotion-detail-row">
                        <td colSpan={(permisos.editar || permisos.eliminar) ? 9 : 8}>
                          <div className="promotion-detail">
                            {promocion.grupos.map(
                              (grupo, indiceGrupo) => (
                                <section
                                  className="promotion-group"
                                  key={
                                    grupo.id_promocion_grupo
                                  }
                                >
                                  <header>
                                    <div>
                                      <Tags />
                                      <strong>
                                        Grupo {indiceGrupo + 1}
                                      </strong>
                                    </div>

                                    <div className="promotion-rules">
                                      <span>
                                        Elegir{' '}
                                        {grupo.cantidad_elegir}
                                      </span>

                                      <span>
                                        <Repeat2 />
                                        {grupo.permite_repetir
                                          ? 'Permite repetir'
                                          : 'Sin repetir'}
                                      </span>
                                    </div>
                                  </header>

                                  <div className="promotion-options">
                                    {grupo.opciones.map(
                                      (opcion) => (
                                        <article
                                          key={
                                            opcion
                                              .id_promocion_opcion
                                          }
                                        >
                                          <b>
                                            {
                                              opcion.codigo_item
                                            }
                                          </b>
                                          <strong>
                                            {
                                              opcion.item_carta
                                            }
                                          </strong>
                                          <span>
                                            {
                                              opcion
                                                .categoria_carta
                                            }
                                          </span>
                                          <small>
                                            {opcion.contenido}{' '}
                                            {formatearUnidad(opcion.unidad)}
                                            {' · '}
                                            {formatearPrecio(
                                              opcion
                                                .precio_individual,
                                            )}
                                          </small>
                                        </article>
                                      ),
                                    )}
                                  </div>
                                </section>
                              ),
                            )}

                            {promocion.grupos.length === 0 && (
                              <p>
                                Esta promoción no tiene grupos
                                configurados.
                              </p>
                            )}
                          </div>
                        </td>
                      </tr>
                    )}
                  </Fragment>
                )
              })}

              {promocionesFiltradas.length === 0 && (
                <tr>
                  <td colSpan={(permisos.editar || permisos.eliminar) ? 9 : 8} className="promotions-empty">
                    No se encontraron promociones.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
      {editor && token && <PromotionEditor token={token} promocion={seleccionada} cerrar={() => setEditor(false)} guardado={texto => { setEditor(false); setMensaje(texto); void cargar(true) }} />}
    </section>
  )
}
