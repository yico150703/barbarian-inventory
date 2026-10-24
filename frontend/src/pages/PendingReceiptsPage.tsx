import { formatearUnidad } from '../utils/unitHelpers'
import { ChevronDown, ChevronUp, LoaderCircle, PackageCheck } from 'lucide-react'
import { Fragment, useCallback, useEffect, useState } from 'react'

import { useAuth } from '../context/AuthContext'
import {
  obtenerPendientesRecepcion,
  registrarRecepcion,
} from '../services/receptionService'
import type {
  PendienteRecepcion,
  RespuestaPendientesRecepcion,
} from '../types/reception'
import './PendingReceiptsPage.css'

const hoy = () => new Date().toISOString().slice(0, 10)

export function PendingReceiptsPage() {
  const { token } = useAuth()
  const [datos, setDatos] = useState<RespuestaPendientesRecepcion | null>(null)
  const [abierto, setAbierto] = useState<string | null>(null)
  const [factura, setFactura] = useState('')
  const [fecha, setFecha] = useState(hoy())
  const [cantidades, setCantidades] = useState<Record<number, string>>({})
  const [cargando, setCargando] = useState(true)
  const [guardando, setGuardando] = useState(false)
  const [error, setError] = useState('')
  const [mensaje, setMensaje] = useState('')

  const cargar = useCallback(async () => {
    if (!token) return
    try {
      setCargando(true)
      setError('')
      setDatos(await obtenerPendientesRecepcion(token))
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudieron cargar los pendientes.')
    } finally {
      setCargando(false)
    }
  }, [token])

  useEffect(() => { void cargar() }, [cargar])

  const seleccionar = (item: PendienteRecepcion) => {
    const clave = `${item.id_orden_compra}-${item.id_proveedor}`
    if (abierto === clave) {
      setAbierto(null)
      return
    }
    setAbierto(clave)
    setFactura('')
    setFecha(hoy())
    setCantidades(Object.fromEntries(
      item.productos.map((p) => [p.id_producto, String(p.cantidad_pendiente)]),
    ))
    setError('')
    setMensaje('')
  }

  const guardar = async (item: PendienteRecepcion) => {
    if (!token || !factura.trim() || !fecha) {
      setError('Completa el número de factura y la fecha.')
      return
    }
    const detalles = item.productos.flatMap((producto) => {
      const cantidad = Number(cantidades[producto.id_producto] ?? '')
      return Number.isFinite(cantidad) && cantidad > 0
        ? [{ id_producto: producto.id_producto, cantidad_recibida: cantidad }]
        : []
    })
    if (!detalles.length) {
      setError('Registra al menos una cantidad recibida mayor que cero.')
      return
    }
    try {
      setGuardando(true)
      setError('')
      const respuesta = await registrarRecepcion(
        token,
        item.id_orden_compra,
        {
          id_proveedor: item.id_proveedor,
          numero_factura: factura.trim(),
          fecha_recepcion: fecha,
          detalles,
        },
      )
      setMensaje(respuesta.mensaje)
      setAbierto(null)
      await cargar()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudo registrar la recepción.')
    } finally {
      setGuardando(false)
    }
  }

  if (cargando) return <div className="receipt-state"><LoaderCircle /> Cargando...</div>

  return (
    <section className="receipt-page">
      <header className="receipt-header">
        <span>RECEPCIÓN DE PRODUCTOS</span>
        <h1>Pendientes de recepción</h1>
        <p>Registra entregas completas o parciales por proveedor.</p>
      </header>

      {mensaje && <div className="receipt-message ok">{mensaje}</div>}
      {error && <div className="receipt-message error">{error}</div>}

      <div className="receipt-summary">
        <article><strong>{datos?.resumen.ordenes_pendientes ?? 0}</strong><span>Órdenes pendientes</span></article>
        <article><strong>{datos?.resumen.recepciones_pendientes ?? 0}</strong><span>Proveedores pendientes</span></article>
        <article><strong>{datos?.resumen.productos_pendientes ?? 0}</strong><span>Productos pendientes</span></article>
      </div>

      <div className="receipt-list">
        {(datos?.pendientes ?? []).map((item) => {
          const clave = `${item.id_orden_compra}-${item.id_proveedor}`
          return (
            <Fragment key={clave}>
              <button className="receipt-row" onClick={() => seleccionar(item)}>
                <PackageCheck />
                <b>{item.codigo_orden}</b>
                <span>{item.proveedor}</span>
                <span>{item.productos.length} productos</span>
                {abierto === clave ? <ChevronUp /> : <ChevronDown />}
              </button>
              {abierto === clave && (
                <div className="receipt-detail">
                  <div className="receipt-fields">
                    <label>Número de factura<input value={factura} maxLength={40} onChange={(e) => setFactura(e.target.value)} /></label>
                    <label>Fecha de recepción<input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} /></label>
                  </div>
                  <div className="receipt-products">
                    {item.productos.map((producto) => (
                      <div key={producto.id_producto}>
                        <span><b>{producto.codigo}</b> {producto.nombre}</span>
                        <small>Solicitado: {producto.cantidad_solicitada} · Recibido: {producto.cantidad_recibida} · Pendiente: {producto.cantidad_pendiente} {formatearUnidad(producto.unidad)}</small>
                        <input
                          type="number"
                          min="0"
                          max={producto.cantidad_pendiente}
                          step="any"
                          value={cantidades[producto.id_producto] ?? ''}
                          onChange={(e) => setCantidades((actual) => ({ ...actual, [producto.id_producto]: e.target.value }))}
                        />
                      </div>
                    ))}
                  </div>
                  <button className="receipt-save" disabled={guardando} onClick={() => void guardar(item)}>
                    {guardando ? 'Guardando...' : 'Registrar recepción'}
                  </button>
                </div>
              )}
            </Fragment>
          )
        })}
        {!datos?.pendientes.length && (
          <div className="receipt-empty">No existen órdenes enviadas pendientes de recepción.</div>
        )}
      </div>
    </section>
  )
}