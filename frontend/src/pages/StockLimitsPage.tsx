import { formatearUnidad } from '../utils/unitHelpers'
import { useEffect, useState, type FormEvent } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { obtenerLimitesStock, guardarLimitesStock, type ProductoLimitesStock } from '../services/catalogService'
import './StockLimitsPage.css'

export function StockLimitsPage() {
  const { token } = useAuth()
  return <StockLimitsContent key={token} />
}

function StockLimitsContent() {
  const { token, perfilActivo, menu, localActivo } = useAuth()
  const permiso = menu.find((opcion) => opcion.codigo === 'LIMITES_STOCK')?.permisos
  const autorizado = perfilActivo?.id_perfil === 2 && permiso?.consultar
  const [productos, setProductos] = useState<ProductoLimitesStock[]>([])
  const [busqueda, setBusqueda] = useState('')
  const [cargando, setCargando] = useState(true)
  const [error, setError] = useState('')
  const [mensaje, setMensaje] = useState('')
  const [editando, setEditando] = useState<ProductoLimitesStock | null>(null)
  const [minimo, setMinimo] = useState('')
  const [maximo, setMaximo] = useState('')
  const [guardando, setGuardando] = useState(false)
  const [revision, setRevision] = useState(0)

  useEffect(() => {
    if (!token || !autorizado) return
    let vigente = true
    setCargando(true)
    setError('')
    setEditando(null)
    obtenerLimitesStock(token).then((datos) => {
      if (vigente) setProductos(datos.productos)
    }).catch((e: unknown) => {
      if (vigente) setError(e instanceof Error ? e.message : 'No se pudieron cargar los límites.')
    }).finally(() => { if (vigente) setCargando(false) })
    return () => { vigente = false }
  }, [token, autorizado, revision])

  if (!autorizado) return <Navigate to="/home" replace />

  function abrir(producto: ProductoLimitesStock) {
    setEditando(producto)
    setMinimo(String(producto.stock_minimo))
    setMaximo(producto.stock_maximo === null ? '' : String(producto.stock_maximo))
    setError('')
    setMensaje('')
  }

  async function guardar(evento: FormEvent) {
    evento.preventDefault()
    if (!token || !editando || guardando) return
    const min = Number(minimo)
    const max = Number(maximo)
    if (!minimo.trim() || !maximo.trim() || !Number.isFinite(min) ||
        !Number.isFinite(max) || min < 0 || max <= min) {
      setError('Ingresa un mínimo no negativo y un máximo mayor al mínimo. No pueden ser iguales.')
      return
    }
    setGuardando(true)
    setError('')
    try {
      const respuesta = await guardarLimitesStock(token, editando.id_producto, min, max)
      setProductos((actuales) => actuales.map((p) => p.id_producto === editando.id_producto
        ? { ...p, stock_minimo: min, stock_maximo: max } : p))
      setMensaje(respuesta.mensaje)
      setEditando(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudieron guardar los límites.')
    } finally { setGuardando(false) }
  }

  const texto = busqueda.trim().toLocaleLowerCase('es')
  const filtrados = productos.filter((p) => `${p.codigo} ${p.nombre} ${p.categoria}`.toLocaleLowerCase('es').includes(texto))
  return <section className="stock-limits">
    <header className="stock-limits__header">
      <span>CONFIGURACIÓN DE INVENTARIO</span>
      <h1>Límites de stock</h1>
      <p>Local: <strong>{localActivo?.nombre}</strong>. Define el mínimo y máximo de cada producto para esta tienda.</p>
    </header>
    {error && <p className="stock-limits__error" role="alert">{error}</p>}
    {mensaje && <p className="stock-limits__success" role="status">{mensaje}</p>}
    <div className="stock-limits__card">
      <div className="stock-limits__tools">
        <label>Buscar producto<input value={busqueda} onChange={(e) => setBusqueda(e.target.value)} placeholder="Código, producto o categoría" /></label>
        <button type="button" disabled={cargando} onClick={() => setRevision((r) => r + 1)}>Actualizar</button>
      </div>
      {cargando ? <p role="status">Cargando límites…</p> : <div className="stock-limits__table">
        <table><thead><tr><th>Código</th><th>Producto</th><th>Categoría</th><th>Unidad</th><th>Mínimo</th><th>Máximo</th><th>Estado</th><th>Acciones</th></tr></thead>
          <tbody>{filtrados.map((p) => <tr key={p.id_producto}>
            <td>{p.codigo}</td><td><strong>{p.nombre}</strong></td><td>{p.categoria}</td><td>{formatearUnidad(p.unidad)}</td>
            <td>{p.stock_minimo}</td><td>{p.stock_maximo ?? 'Sin definir'}</td><td>{p.activo ? 'Activo' : 'Inactivo'}</td>
            <td>{permiso?.configurar && <button type="button" onClick={() => abrir(p)}>Configurar</button>}</td>
          </tr>)}{!filtrados.length && <tr><td colSpan={8}>No se encontraron productos.</td></tr>}</tbody>
        </table>
      </div>}
    </div>
    {editando && <div className="stock-limits__backdrop">
      <form className="stock-limits__dialog" role="dialog" aria-modal="true" aria-labelledby="limits-title" onSubmit={(e) => void guardar(e)}>
        <h2 id="limits-title">Configurar límites</h2>
        <p>{editando.codigo} · {editando.nombre} ({formatearUnidad(editando.unidad)})</p>
        {error && <p className="stock-limits__error" role="alert">{error}</p>}
        <fieldset disabled={guardando}>
          <label>Stock mínimo<input autoFocus type="number" min="0" max="999999999.999" step="0.001" required value={minimo} onChange={(e) => setMinimo(e.target.value)} /></label>
          <label>Stock máximo<input type="number" min={Number.isFinite(Number(minimo)) ? (Number(minimo) + 0.001).toFixed(3) : '0.001'} max="999999999.999" step="0.001" required value={maximo} onChange={(e) => setMaximo(e.target.value)} /></label>
        </fieldset>
        <div className="stock-limits__tools">
          <button type="button" disabled={guardando} onClick={() => setEditando(null)}>Cancelar</button>
          <button disabled={guardando}>{guardando ? 'Guardando…' : 'Guardar límites'}</button>
        </div>
      </form>
    </div>}
  </section>
}
