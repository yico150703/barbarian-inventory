import { formatearUnidad } from '../utils/unitHelpers'
import {
  ChevronDown,
  ChevronUp,
  ClipboardList,
  LoaderCircle,
  Search,
  XCircle,
} from 'lucide-react'
import { Fragment, useCallback, useEffect, useState } from 'react'

import { useAuth } from '../context/AuthContext'
import {
  cambiarEstadoOrden,
  obtenerDetalleOrden,
  obtenerHistorialOrdenes,
} from '../services/purchaseOrderService'
import type {
  EstadoOrdenCompra,
  OrdenCompraHistorial,
  RespuestaDetalleOrden,
} from '../types/purchaseOrder'
import './HistoryPages.css'

function perfilToken(token: string | null) {
  if (!token) return null
  try {
    const parte = token.split('.')[1]
    const base64 = parte.replace(/-/g, '+').replace(/_/g, '/')
      .padEnd(Math.ceil(parte.length / 4) * 4, '=')
    const datos = JSON.parse(atob(base64)) as { perfil?: string }
    return datos.perfil ?? null
  } catch {
    return null
  }
}

const fechaTexto = (valor: string | null) => valor
  ? new Intl.DateTimeFormat('es-PE', {
    day: '2-digit', month: 'long', year: 'numeric',
  }).format(new Date(`${valor}T00:00:00`))
  : 'Borrador'

const numero = (valor: number) => new Intl.NumberFormat('es-PE', {
  maximumFractionDigits: 3,
}).format(valor)

export function PurchaseOrderHistoryPage() {
  const { token } = useAuth()
  const puedeModificar = ['Gerente', 'Administrador del sistema']
    .includes(perfilToken(token) ?? '')
  const [ordenes, setOrdenes] = useState<OrdenCompraHistorial[]>([])
  const [detalle, setDetalle] = useState<RespuestaDetalleOrden | null>(null)
  const [abierto, setAbierto] = useState<number | null>(null)
  const [desde, setDesde] = useState('')
  const [hasta, setHasta] = useState('')
  const [estado, setEstado] = useState<EstadoOrdenCompra | ''>('')
  const [cargando, setCargando] = useState(true)
  const [error, setError] = useState('')
  const [mensaje, setMensaje] = useState('')

  const cargar = useCallback(async () => {
    if (!token) return
    try {
      setCargando(true)
      setError('')
      const respuesta = await obtenerHistorialOrdenes(token, {
        fecha_desde: desde,
        fecha_hasta: hasta,
        estado,
      })
      setOrdenes(respuesta.ordenes)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se cargaron las órdenes.')
    } finally {
      setCargando(false)
    }
  }, [token, desde, hasta, estado])

  useEffect(() => { void cargar() }, [cargar])

  const desplegar = async (id: number) => {
    if (!token) return
    if (abierto === id) {
      setAbierto(null)
      setDetalle(null)
      return
    }
    try {
      setError('')
      setDetalle(await obtenerDetalleOrden(token, id))
      setAbierto(id)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se cargó el detalle.')
    }
  }

  const cambiar = async (
    orden: OrdenCompraHistorial,
    accion: 'CANCELAR' | 'CERRAR_INCOMPLETA',
  ) => {
    if (!token) return
    const motivo = window.prompt(
      accion === 'CANCELAR'
        ? 'Indica el motivo de cancelación (mínimo 10 caracteres):'
        : 'Indica por qué se cerrará con lo recibido (mínimo 10 caracteres):',
    )
    if (!motivo) return
    try {
      setError('')
      const respuesta = await cambiarEstadoOrden(
        token, orden.id_orden_compra, accion, motivo,
      )
      setMensaje(respuesta.mensaje)
      setAbierto(null)
      setDetalle(null)
      await cargar()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se actualizó la orden.')
    }
  }

  return (
    <section className="history-page">
      <header className="history-hero">
        <span>ÓRDENES DE COMPRA</span>
        <h1>Historial de órdenes</h1>
        <p>Consulta los pedidos, su avance y el estado de recepción.</p>
      </header>

      {error && <div className="history-alert error">{error}</div>}
      {mensaje && <div className="history-alert ok">{mensaje}</div>}

      <section className="history-card">
        <div className="history-filters">
          <label>Desde<input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} /></label>
          <label>Hasta<input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} /></label>
          <label>Estado<select value={estado} onChange={(e) => setEstado(e.target.value as EstadoOrdenCompra | '')}>
            <option value="">Todos los estados</option>
            <option value="BORRADOR">Borrador</option>
            <option value="ENVIADA">Enviada</option>
            <option value="RECEPCION_PARCIAL">Recepción parcial</option>
            <option value="RECEPCIONADA">Recepcionada</option>
            <option value="CERRADA_INCOMPLETA">Cerrada incompleta</option>
            <option value="CANCELADA">Cancelada</option>
          </select></label>
          <button onClick={() => void cargar()}><Search /> Buscar</button>
          <button className="secondary" onClick={() => { setDesde(''); setHasta(''); setEstado('') }}>Limpiar</button>
        </div>

        {cargando ? <div className="history-loading"><LoaderCircle /> Cargando...</div> : (
          <div className="history-table-wrap"><table className="history-table">
            <thead>
              <tr>
                <th>Orden</th>
                <th>Fecha</th>
                <th>Registrada por</th>
                <th>Productos</th>
                <th>Completados</th>
                <th>Pendientes</th>
                <th>Estado</th>
                <th>Detalle</th>
              </tr>
            </thead>
            <tbody>
              {ordenes.map((orden) => (
                <Fragment key={orden.id_orden_compra}>
                  <tr>
                    <td><b>{orden.codigo}</b></td>
                    <td>{fechaTexto(orden.fecha_registro)}</td>
                    <td>{orden.registrado_por}</td>
                    <td>{orden.total_productos ?? 0}</td>
                    <td>{orden.productos_completos ?? 0}</td>
                    <td>{orden.productos_pendientes ?? 0}</td>
                    <td><span className={`history-status ${orden.estado_orden_compra.toLowerCase()}`}>{orden.estado_orden_compra.replaceAll('_', ' ')}</span></td>
                    <td><button className="icon" onClick={() => void desplegar(orden.id_orden_compra)}>{abierto === orden.id_orden_compra ? <ChevronUp /> : <ChevronDown />}</button></td>
                  </tr>
                  {abierto === orden.id_orden_compra && detalle?.orden.id_orden_compra === orden.id_orden_compra && (
                    <tr><td colSpan={8}><div className="history-detail">
                      <div className="history-products">
                        {detalle.orden.detalles.map((item) => <article key={item.id_orden_compra_detalle}>
                          <div><b>{item.codigo} · {item.nombre}</b><small>{item.proveedor}</small></div>
                          <span>Pedido: {numero(item.cantidad_solicitada)} {formatearUnidad(item.unidad)}</span>
                          <span>Recibido: {numero(item.cantidad_recibida)} {formatearUnidad(item.unidad)}</span>
                          <span>Pendiente: {numero(item.cantidad_pendiente)} {formatearUnidad(item.unidad)}</span>
                        </article>)}
                      </div>
                      {orden.motivo_cierre && <p className="history-reason"><b>Motivo:</b> {orden.motivo_cierre}</p>}
                      {puedeModificar && <div className="history-actions">
                        {['BORRADOR', 'ENVIADA'].includes(orden.estado_orden_compra) && orden.productos_con_recepcion === 0 && <button className="danger" onClick={() => void cambiar(orden, 'CANCELAR')}><XCircle /> Cancelar orden</button>}
                        {orden.estado_orden_compra === 'RECEPCION_PARCIAL' && <button onClick={() => void cambiar(orden, 'CERRAR_INCOMPLETA')}><ClipboardList /> Cerrar con lo recibido</button>}
                      </div>}
                    </div></td></tr>
                  )}
                </Fragment>
              ))}
              {!ordenes.length && <tr><td colSpan={8} className="history-empty">No hay órdenes con los filtros seleccionados.</td></tr>}
            </tbody>
          </table></div>
        )}
      </section>
    </section>
  )
}