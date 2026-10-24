import { formatearUnidad } from '../utils/unitHelpers'
import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { permisosDe } from '../utils/permissionHelpers'
import './MovementTrackingPage.css'

interface Guia {
  id: number; codigo: string; fecha: string; id_local: number; id_local_destino: number | null;
  estado: string; motivo: string; origen: string; destino: string | null; proveedor: string | null;
  observacion: string | null; registrado_por: string;
  detalles: {id_producto: number; codigo: string; nombre: string; unidad: string; cantidad: number; recibido: number}[];
  recepciones: {codigo: string; guia_proveedor: string | null; fecha: string; nombre: string; unidad: string; cantidad: number}[];
}
const estados: Record<string, string> = {
  PENDIENTE_RECEPCION: 'Pendiente de recepción', ACEPTADO: 'Aceptado',
  DEVUELTO: 'Devuelto · pendiente de reintegro', REINTEGRO_PARCIAL: 'Reintegro parcial', REINTEGRADO: 'Reintegrado',
}
const api = import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'

export function MovementTrackingPage() {
  const { token, localActivo, menu } = useAuth()
  const [guias, setGuias] = useState<Guia[]>([])
  const [tab, setTab] = useState('enviados')
  const [error, setError] = useState('')
  const [ocupado, setOcupado] = useState(false)
  const [seleccion, setSeleccion] = useState<Guia | null>(null)
  const [cantidades, setCantidades] = useState<Record<number, string>>({})
  const [documento, setDocumento] = useState('')
  const [mensaje, setMensaje] = useState('')
  const cargar = useCallback(async () => {
    const r = await fetch(`${api}/movimientos/seguimiento`, {headers: {Authorization: `Bearer ${token}`}})
    const d = await r.json()
    if (!r.ok) throw new Error(d.mensaje ?? 'No se pudo cargar el seguimiento')
    setGuias(d.movimientos)
  }, [token])
  useEffect(() => { cargar().catch(e => setError(e.message)) }, [cargar])
  async function recibir() {
    if (!seleccion) return
    setOcupado(true); setError(''); setMensaje('')
    try {
      const r = await fetch(`${api}/movimientos/${seleccion.id}/recibir`, {
        method: 'POST', headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token}`},
        body: JSON.stringify({guia_proveedor: documento, detalles: Object.entries(cantidades)
          .filter(([,c]) => Number(c) > 0).map(([id,c]) => ({id_producto: Number(id), cantidad: Number(c)}))}),
      })
      const d = await r.json()
      if (!r.ok) throw new Error(d.mensaje ?? 'No se pudo recibir')
      setSeleccion(null); setMensaje(d.mensaje); await cargar()
    } catch (e) { setError(e instanceof Error ? e.message : 'Error de recepción') }
    finally { setOcupado(false) }
  }
  return <section className="movement-tracking">
    <header><h1>Préstamos y devoluciones</h1><p>Guías de salida y recepción del local {localActivo?.nombre}.</p>
      <Link to="/home/movimientos/registrar">Registrar salida</Link>
      <button onClick={() => {setError(''); cargar().catch(e => setError(e.message))}}>Actualizar</button>
    </header>
    {error && <p role="alert">{error}</p>}{mensaje && <p role="status">{mensaje}</p>}
    <nav>{[['enviados','Préstamos entregados'],['pendientes','Préstamos por recibir'],['recibidos','Préstamos recibidos'],['proveedor','Devoluciones a proveedor']].map(([id,label]) =>
      <button key={id} aria-pressed={tab===id} onClick={() => setTab(id)}>{label}</button>)}</nav>
    {guias.filter(g => tab==='proveedor' ? !g.id_local_destino : tab==='enviados' ? g.id_local_destino && g.id_local===localActivo?.id_local : g.id_local_destino===localActivo?.id_local && (tab==='pendientes' ? g.estado==='PENDIENTE_RECEPCION' : g.estado==='ACEPTADO')).map(g =>
      <article key={g.id}>
        <h2>Guía de salida {g.codigo}</h2>
        <p>{g.fecha} · {g.origen} → {g.destino ?? g.proveedor} · <strong>{estados[g.estado]}</strong></p>
        <p>Registrado por {g.registrado_por}. {g.observacion}</p>
        <table><thead><tr><th>Código</th><th>Producto</th><th>Unidad</th><th>Enviado</th><th>Recibido</th><th>Pendiente</th></tr></thead>
          <tbody>{g.detalles.map(d => <tr key={d.id_producto}><td>{d.codigo}</td><td>{d.nombre}</td><td>{formatearUnidad(d.unidad)}</td><td>{d.cantidad}</td><td>{d.recibido}</td><td>{Number((d.cantidad-d.recibido).toFixed(3))}</td></tr>)}</tbody></table>
        {g.recepciones.length>0 && <details><summary>Recepciones registradas</summary>{g.recepciones.map((r,i) => <p key={i}>{r.fecha} · {r.codigo} · {r.guia_proveedor ?? 'Aceptación del local'} · {r.nombre}: {r.cantidad} {formatearUnidad(r.unidad)}</p>)}</details>}
        <button onClick={e => {const article=e.currentTarget.closest("article"); article?.classList.add("printing"); document.body.dataset.guiaImprimir=String(g.id); window.print(); delete document.body.dataset.guiaImprimir; article?.classList.remove("printing")}} className="print-guide">Imprimir guía</button>
        <span className="print-id" data-id={g.id} />
        {permisosDe(menu,20).crear && !['ACEPTADO','REINTEGRADO'].includes(g.estado) && (g.id_local_destino ?? g.id_local)===localActivo?.id_local &&
          <button onClick={() => {setSeleccion(g);setCantidades({});setDocumento('');setError('')}}>{g.id_local_destino ? 'Aceptar recepción' : 'Registrar reintegro'}</button>}
      </article>)}
    {seleccion && <div className="tracking-overlay"><section role="dialog" aria-modal="true" aria-labelledby="recepcion-title">
      <h2 id="recepcion-title">Recibir {seleccion.codigo}</h2>
      <p>{seleccion.id_local_destino ? 'Confirma que recibiste todos los productos indicados. Se sumarán al stock de este local.' : 'Registra únicamente lo recibido. El resto quedará pendiente.'}</p>
      {error && <p role="alert">{error}</p>}
      {!seleccion.id_local_destino && <label>Guía del proveedor<input maxLength={100} value={documento} onChange={e => setDocumento(e.target.value)} /></label>}
      {seleccion.detalles.map(d => <label key={d.id_producto}>{d.nombre} · pendiente {Number((d.cantidad-d.recibido).toFixed(3))} {formatearUnidad(d.unidad)}
        {!seleccion.id_local_destino && <input type="number" min="0" step="0.001" max={d.cantidad-d.recibido} value={cantidades[d.id_producto]??''} onChange={e => setCantidades({...cantidades,[d.id_producto]:e.target.value})} />}</label>)}
      <button disabled={ocupado} onClick={() => setSeleccion(null)}>Cancelar</button><button disabled={ocupado} onClick={recibir}>{ocupado ? 'Guardando…' : 'Confirmar recepción'}</button>
    </section></div>}
  </section>
}
