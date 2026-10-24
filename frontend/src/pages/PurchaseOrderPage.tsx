import { formatearUnidad } from '../utils/unitHelpers'
import { LoaderCircle, Plus, Save, Send, Sparkles, Trash2 } from 'lucide-react'
import { useCallback, useEffect, useMemo, useState } from 'react'

import { useAuth } from '../context/AuthContext'
import {
  obtenerFormularioOrden,
  obtenerPedidoSugerido,
  registrarOrdenCompra,
} from '../services/purchaseOrderService'
import type {
  ProductoCompra,
  RespuestaFormularioOrden,
} from '../types/purchaseOrder'
import './PurchaseOrderPage.css'

interface DetalleFormulario extends ProductoCompra {
  cantidad_solicitada: string
  origen: 'MANUAL' | 'SUGERIDO'
}

export function PurchaseOrderPage() {
  const { token } = useAuth()
  const [formulario, setFormulario] = useState<RespuestaFormularioOrden | null>(null)
  const [detalles, setDetalles] = useState<DetalleFormulario[]>([])
  const [idProducto, setIdProducto] = useState('')
  const [busqueda, setBusqueda] = useState('')
  const [cargando, setCargando] = useState(true)
  const [calculando, setCalculando] = useState(false)
  const [guardando, setGuardando] = useState(false)
  const [error, setError] = useState('')
  const [mensaje, setMensaje] = useState('')

  const cargarFormulario = useCallback(async () => {
    if (!token) return
    try {
      setCargando(true)
      setFormulario(await obtenerFormularioOrden(token))
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se cargaron los productos.')
    } finally {
      setCargando(false)
    }
  }, [token])

  useEffect(() => { void cargarFormulario() }, [cargarFormulario])

  const productos = useMemo(() => {
    const texto = busqueda.trim().toLowerCase()
    return (formulario?.productos ?? []).filter((p) =>
      !texto || p.codigo.toLowerCase().includes(texto) ||
      p.nombre.toLowerCase().includes(texto),
    )
  }, [busqueda, formulario])

  const agregar = () => {
    const id = Number(idProducto)
    const producto = formulario?.productos.find((p) => p.id_producto === id)
    if (!producto) return
    if (detalles.some((p) => p.id_producto === id)) {
      setError('El producto ya está en la orden.')
      return
    }
    setDetalles((actuales) => [...actuales, {
      ...producto,
      cantidad_solicitada: '',
      origen: 'MANUAL',
    }])
    setIdProducto('')
    setError('')
  }

  const cargarSugerido = async () => {
    if (!token) return
    if (detalles.length && !window.confirm(
      'El pedido sugerido reemplazará los productos actuales. ¿Continuar?',
    )) return
    try {
      setCalculando(true)
      setError('')
      const respuesta = await obtenerPedidoSugerido(token)
      setDetalles(respuesta.productos.map((p) => ({
        ...p,
        cantidad_solicitada: String(p.cantidad_sugerida),
        origen: 'SUGERIDO',
      })))
      setMensaje(respuesta.productos.length
        ? 'Pedido sugerido cargado. Puedes modificar las cantidades.'
        : 'No hay productos que necesiten reposición.')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se calculó el pedido.')
    } finally {
      setCalculando(false)
    }
  }

  const guardar = async (accion: 'GUARDAR_BORRADOR' | 'ENVIAR') => {
    if (!token || !detalles.length) {
      setError('Agrega al menos un producto.')
      return
    }
    const enviados = detalles.map((p) => ({
      id_producto: p.id_producto,
      cantidad_solicitada: Number(p.cantidad_solicitada),
    }))
    if (enviados.some((p) => !Number.isFinite(p.cantidad_solicitada) || p.cantidad_solicitada <= 0)) {
      setError('Todas las cantidades deben ser mayores que cero.')
      return
    }
    try {
      setGuardando(true)
      setError('')
      const respuesta = await registrarOrdenCompra(token, {
        accion,
        detalles: enviados,
      })
      setMensaje(respuesta.mensaje)
      setDetalles([])
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se guardó la orden.')
    } finally {
      setGuardando(false)
    }
  }

  if (cargando) return <div className="purchase-state"><LoaderCircle /> Cargando...</div>

  return (
    <section className="purchase-page">
      <header className="purchase-header">
        <span>ÓRDENES DE COMPRA</span>
        <h1>Crear orden de compra</h1>
        <p>Agrega productos manualmente o carga una sugerencia automática.</p>
      </header>

      {error && <div className="purchase-alert error">{error}</div>}
      {mensaje && <div className="purchase-alert ok">{mensaje}</div>}

      <section className="purchase-card">
        <div className="purchase-actions">
          <input
            value={busqueda}
            onChange={(e) => setBusqueda(e.target.value)}
            placeholder="Buscar producto"
          />
          <select value={idProducto} onChange={(e) => setIdProducto(e.target.value)}>
            <option value="">Seleccionar producto</option>
            {productos.map((p) => (
              <option key={p.id_producto} value={p.id_producto}>
                {p.codigo} - {p.nombre} ({p.proveedor})
              </option>
            ))}
          </select>
          <button onClick={agregar} disabled={!idProducto}><Plus /> Agregar</button>
          <button className="suggest" onClick={() => void cargarSugerido()} disabled={calculando}>
            <Sparkles /> {calculando ? 'Calculando...' : 'Generar pedido sugerido'}
          </button>
        </div>

        <div className="purchase-table-wrap">
          <table>
            <thead><tr><th>Producto</th><th>Proveedor</th><th>Stock actual</th><th>Presentación</th><th>Cantidad</th><th>Origen</th><th></th></tr></thead>
            <tbody>
              {detalles.map((p) => (
                <tr key={p.id_producto}>
                  <td><b>{p.codigo}</b><br />{p.nombre}</td>
                  <td>{p.proveedor}</td>
                  <td>{p.stock_actual ?? 'Sin conteo'} {formatearUnidad(p.unidad)}</td>
                  <td>{p.presentacion} {formatearUnidad(p.unidad)}</td>
                  <td><input type="number" min="0.001" step="any" value={p.cantidad_solicitada} onChange={(e) => setDetalles((actuales) => actuales.map((item) => item.id_producto === p.id_producto ? { ...item, cantidad_solicitada: e.target.value } : item))} /></td>
                  <td>{p.origen === 'SUGERIDO' ? 'Sugerido' : 'Manual'}</td>
                  <td><button className="remove" onClick={() => setDetalles((actuales) => actuales.filter((item) => item.id_producto !== p.id_producto))}><Trash2 /></button></td>
                </tr>
              ))}
              {!detalles.length && <tr><td colSpan={7} className="empty">La orden está vacía.</td></tr>}
            </tbody>
          </table>
        </div>

        <footer className="purchase-footer">
          <button className="clear" onClick={() => setDetalles([])}>Limpiar</button>
          <button disabled={guardando} onClick={() => void guardar('GUARDAR_BORRADOR')}><Save /> Guardar borrador</button>
          <button className="send" disabled={guardando} onClick={() => void guardar('ENVIAR')}><Send /> Enviar orden</button>
        </footer>
      </section>
    </section>
  )
}