import { formatearUnidad } from '../utils/unitHelpers'
import { ChevronDown, ChevronUp, LoaderCircle, Pencil, Save, Search } from 'lucide-react'
import { Fragment, useCallback, useEffect, useMemo, useState } from 'react'

import { useAuth } from '../context/AuthContext'
import {
  corregirRecepcion,
  obtenerDetalleRecepcion,
  obtenerHistorialRecepciones,
} from '../services/receptionService'
import type {
  DatosCorregirRecepcion,
  RecepcionHistorial,
  RespuestaDetalleRecepcion,
} from '../types/reception'
import './HistoryPages.css'

function perfilToken(token: string | null) {
  if (!token) return null
  try {
    const parte = token.split('.')[1]
    const base64 = parte.replace(/-/g, '+').replace(/_/g, '/')
      .padEnd(Math.ceil(parte.length / 4) * 4, '=')
    return (JSON.parse(atob(base64)) as { perfil?: string }).perfil ?? null
  } catch { return null }
}

export function ReceptionHistoryPage() {
  const { token } = useAuth()
  const puedeEditar = ['Gerente', 'Administrador del sistema']
    .includes(perfilToken(token) ?? '')
  const [recepciones, setRecepciones] = useState<RecepcionHistorial[]>([])
  const [detalle, setDetalle] = useState<RespuestaDetalleRecepcion | null>(null)
  const [abierto, setAbierto] = useState<number | null>(null)
  const [editando, setEditando] = useState(false)
  const [desde, setDesde] = useState('')
  const [hasta, setHasta] = useState('')
  const [proveedor, setProveedor] = useState('')
  const [numeroFactura, setNumeroFactura] = useState('')
  const [fecha, setFecha] = useState('')
  const [motivo, setMotivo] = useState<DatosCorregirRecepcion['motivo_correccion']>('ERROR_DIGITACION')
  const [observacion, setObservacion] = useState('')
  const [cantidades, setCantidades] = useState<Record<number, string>>({})
  const [cargando, setCargando] = useState(true)
  const [guardando, setGuardando] = useState(false)
  const [error, setError] = useState('')
  const [mensaje, setMensaje] = useState('')

  const proveedores = useMemo(() => Array.from(new Map(
    recepciones.map((r) => [r.id_proveedor, r.proveedor]),
  ).entries()), [recepciones])

  const cargar = useCallback(async () => {
    if (!token) return
    try {
      setCargando(true); setError('')
      const respuesta = await obtenerHistorialRecepciones(token, {
        fecha_desde: desde,
        fecha_hasta: hasta,
        id_proveedor: proveedor ? Number(proveedor) : undefined,
      })
      setRecepciones(respuesta.recepciones)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se cargaron las recepciones.')
    } finally { setCargando(false) }
  }, [token, desde, hasta, proveedor])

  useEffect(() => { void cargar() }, [cargar])

  const desplegar = async (id: number) => {
    if (!token) return
    if (abierto === id) { setAbierto(null); setDetalle(null); setEditando(false); return }
    try {
      const respuesta = await obtenerDetalleRecepcion(token, id)
      setDetalle(respuesta); setAbierto(id); setEditando(false)
      setNumeroFactura(respuesta.recepcion.numero_factura)
      setFecha(respuesta.recepcion.fecha_recepcion)
      setCantidades(Object.fromEntries(respuesta.recepcion.detalles.map((d) => [d.id_factura_recepcion_detalle, String(d.cantidad_recibida)])))
    } catch (e) { setError(e instanceof Error ? e.message : 'No se cargó el detalle.') }
  }

  const guardar = async () => {
    if (!token || !detalle) return
    if (observacion.trim().length < 10) {
      setError('La observación debe tener al menos 10 caracteres.'); return
    }
    const detalles = detalle.recepcion.detalles.map((d) => ({
      id_factura_recepcion_detalle: d.id_factura_recepcion_detalle,
      cantidad_recibida: Number(cantidades[d.id_factura_recepcion_detalle]),
    }))
    if (detalles.some((d) => !Number.isFinite(d.cantidad_recibida) || d.cantidad_recibida <= 0)) {
      setError('Todas las cantidades deben ser mayores que cero.'); return
    }
    try {
      setGuardando(true); setError('')
      const respuesta = await corregirRecepcion(token, detalle.recepcion.id_factura_recepcion, {
        numero_factura: numeroFactura.trim(),
        fecha_recepcion: fecha,
        motivo_correccion: motivo,
        observacion: observacion.trim(),
        detalles,
      })
      setMensaje(respuesta.mensaje); setEditando(false); setObservacion('')
      setAbierto(null); setDetalle(null)
      await cargar()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se corrigió la recepción.')
    } finally { setGuardando(false) }
  }

  return <section className="history-page">
    <header className="history-hero"><span>RECEPCIÓN DE PRODUCTOS</span><h1>Historial de recepciones</h1><p>Consulta facturas, productos recibidos y responsables.</p></header>
    {error && <div className="history-alert error">{error}</div>}
    {mensaje && <div className="history-alert ok">{mensaje}</div>}
    <section className="history-card">
      <div className="history-filters">
        <label>Desde<input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} /></label>
        <label>Hasta<input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} /></label>
        <label>Proveedor<select value={proveedor} onChange={(e) => setProveedor(e.target.value)}><option value="">Todos</option>{proveedores.map(([id, nombre]) => <option key={id} value={id}>{nombre}</option>)}</select></label>
        <button onClick={() => void cargar()}><Search /> Buscar</button>
        <button className="secondary" onClick={() => { setDesde(''); setHasta(''); setProveedor('') }}>Limpiar</button>
      </div>
      {cargando ? <div className="history-loading"><LoaderCircle /> Cargando...</div> : <div className="history-table-wrap"><table className="history-table">
        <thead><tr><th>Orden</th><th>Factura</th><th>Fecha</th><th>Proveedor</th><th>Recibido por</th><th>Productos</th><th>Estado orden</th><th>Detalle</th></tr></thead>
        <tbody>{recepciones.map((r) => <Fragment key={r.id_factura_recepcion}>
          <tr><td><b>{r.codigo_orden}</b></td><td>{r.numero_factura}</td><td>{r.fecha_recepcion}</td><td>{r.proveedor}</td><td>{r.recibido_por}</td><td>{r.productos_recibidos}</td><td><span className={`history-status ${r.estado_orden_compra.toLowerCase()}`}>{r.estado_orden_compra.replaceAll('_', ' ')}</span></td><td><button className="icon" onClick={() => void desplegar(r.id_factura_recepcion)}>{abierto === r.id_factura_recepcion ? <ChevronUp /> : <ChevronDown />}</button></td></tr>
          {abierto === r.id_factura_recepcion && detalle?.recepcion.id_factura_recepcion === r.id_factura_recepcion && <tr><td colSpan={8}><div className="history-detail">
            <div className="history-edit-grid"><label>Número de factura<input disabled={!editando} value={numeroFactura} onChange={(e) => setNumeroFactura(e.target.value)} /></label><label>Fecha de recepción<input disabled={!editando} type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} /></label></div>
            <div className="history-products">{detalle.recepcion.detalles.map((d) => <article key={d.id_factura_recepcion_detalle}><div><b>{d.codigo} · {d.nombre}</b><small>Solicitado: {d.cantidad_solicitada} {formatearUnidad(d.unidad)}</small></div><label>Recibido<input disabled={!editando} type="number" min="0.001" max={d.maximo_permitido} step="any" value={cantidades[d.id_factura_recepcion_detalle] ?? ''} onChange={(e) => setCantidades((a) => ({ ...a, [d.id_factura_recepcion_detalle]: e.target.value }))} /></label><span>Máximo: {d.maximo_permitido} {formatearUnidad(d.unidad)}</span></article>)}</div>
            {editando && <div className="history-correction"><label>Motivo<select value={motivo} onChange={(e) => setMotivo(e.target.value as DatosCorregirRecepcion['motivo_correccion'])}><option value="ERROR_DIGITACION">Error de digitación</option><option value="MAL_CONTADO">Mal contado</option><option value="PRODUCTO_DANADO">Producto dañado</option><option value="PRODUCTO_RECHAZADO">Producto rechazado</option><option value="ERROR_FACTURA">Error en factura</option><option value="OTRO">Otro</option></select></label><label>Observación<textarea maxLength={500} value={observacion} onChange={(e) => setObservacion(e.target.value)} placeholder="Explica la corrección realizada" /></label><p>Al guardar se recalculará automáticamente el estado de la orden.</p></div>}
            {puedeEditar && <div className="history-actions">{!editando ? <button onClick={() => setEditando(true)}><Pencil /> Corregir recepción</button> : <><button className="secondary" onClick={() => setEditando(false)}>Cancelar edición</button><button disabled={guardando} onClick={() => void guardar()}><Save /> {guardando ? 'Guardando...' : 'Guardar corrección'}</button></>}</div>}
          </div></td></tr>}
        </Fragment>)}{!recepciones.length && <tr><td colSpan={8} className="history-empty">No hay recepciones con los filtros seleccionados.</td></tr>}</tbody>
      </table></div>}
    </section>
  </section>
}