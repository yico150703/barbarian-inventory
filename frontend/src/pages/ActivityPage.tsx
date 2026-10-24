import { Fragment, useEffect, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import './ActivityPage.css'

interface Evento {
  id: number; origen: string; usuario: string; usuario_afectado: string | null;
  perfil: string | null; puesto: string | null; local: string | null; id_local: number | null;
  modulo: string; accion: string; descripcion: string; fecha: string;
  tabla: string | null; id_registro_afectado: number | null;
  antes: Record<string, unknown> | null; despues: Record<string, unknown> | null;
}
interface Historial {
  eventos: Evento[]; hay_mas: boolean; marca_completa: boolean;
  locales: {id_local: number; nombre: string}[];
}
const mostrar = (valor: unknown) => valor == null ? '—' : typeof valor === 'object' ? JSON.stringify(valor, null, 2) : String(valor)
const etiqueta = (texto: string) => texto.replaceAll('_', ' ')

export function ActivityPage() {
  const { token } = useAuth()
  const [datos, setDatos] = useState<Historial | null>(null)
  const [filtros, setFiltros] = useState({local:'', buscar:'', desde:'', hasta:''})
  const [consulta, setConsulta] = useState(filtros)
  const [pagina, setPagina] = useState(1)
  const [abierto, setAbierto] = useState('')
  const [error, setError] = useState('')
  const [cargando, setCargando] = useState(true)
  const [version, setVersion] = useState(0)
  useEffect(() => {
    const controller=new AbortController()
    setCargando(true);setError('');setAbierto('')
    const params=new URLSearchParams({...consulta,pagina:String(pagina)})
    fetch(`${import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'}/actividades/historial?${params}`, {
      headers:{Authorization:`Bearer ${token}`},signal:controller.signal,
    }).then(async r => {const d=await r.json();if(!r.ok) throw new Error(d.mensaje ?? 'No se pudo cargar la actividad');return d})
      .then(d => {setDatos(d);setCargando(false)})
      .catch(e => {if(!controller.signal.aborted){setError(e.message);setCargando(false)}})
    return () => controller.abort()
  },[token,consulta,pagina,version])
  return <section className="activity-page">
    <header><span>TRAZABILIDAD</span><h1>Actividades del sistema</h1><p>Consulta quién realizó cada acción, con qué perfil y en qué local.</p></header>
    <form onSubmit={e => {e.preventDefault();setConsulta({...filtros});setPagina(1)}}>
      <label>Ámbito<select value={filtros.local} onChange={e => setFiltros({...filtros,local:e.target.value})}>
        <option value="">{datos?.marca_completa ? 'Toda la marca' : 'Mi local'}</option>
        {datos?.marca_completa && <option value="global">Sin local registrado</option>}
        {datos?.locales.map(l => <option key={l.id_local} value={l.id_local}>{l.nombre}</option>)}
      </select></label>
      <label>Usuario, acción o módulo<input value={filtros.buscar} onChange={e => setFiltros({...filtros,buscar:e.target.value})} placeholder="Buscar actividad" /></label>
      <label>Desde<input type="date" value={filtros.desde} onChange={e => setFiltros({...filtros,desde:e.target.value})} /></label>
      <label>Hasta<input type="date" min={filtros.desde} value={filtros.hasta} onChange={e => setFiltros({...filtros,hasta:e.target.value})} /></label>
      <button>Filtrar</button><button type="button" onClick={() => {const vacios={local:'',buscar:'',desde:'',hasta:''};setFiltros(vacios);setConsulta(vacios);setPagina(1)}}>Limpiar</button>
      <button type="button" onClick={() => setVersion(v => v+1)}>Actualizar</button>
    </form>
    {error && <p role="alert">{error}</p>}
    {cargando ? <p role="status">Cargando actividades…</p> : !error && <>
      <p>Hora de Lima. Las actividades y los cambios detallados se identifican por separado.</p>
      <div className="activity-table"><table><thead><tr><th>Fecha y hora</th><th>Realizado por</th><th>Perfil</th><th>Local</th><th>Acción</th><th>Usuario afectado</th><th>Detalle</th></tr></thead>
        <tbody>{datos?.eventos.map(e => {
          const id=`${e.origen}-${e.id}`
          const campos=Array.from(new Set([...Object.keys(e.antes ?? {}),...Object.keys(e.despues ?? {})]))
            .filter(k => JSON.stringify(e.antes?.[k])!==JSON.stringify(e.despues?.[k]))
          return <Fragment key={id}><tr><td>{e.fecha.replace('T',' ').split('.')[0]}</td><td>{e.usuario}</td><td>{e.perfil ?? 'No registrado'}</td><td>{e.local ?? 'Sin local registrado'}</td><td>{etiqueta(e.modulo)} · {etiqueta(e.accion)}</td><td>{e.usuario_afectado ?? '—'}</td><td><button aria-expanded={abierto===id} onClick={() => setAbierto(abierto===id ? '' : id)}>{abierto===id ? 'Cerrar' : 'Ver detalle'}</button></td></tr>
          {abierto===id && <tr><td colSpan={7}><section className="activity-detail"><strong>{e.origen==='cambio' ? 'Cambio de datos' : 'Actividad'} #{e.id}</strong><p>{e.descripcion}</p>
            <p>Puesto: {e.puesto ?? 'No registrado'} · Registro afectado: {e.id_registro_afectado ?? 'No registrado'}{e.tabla && ` · ${e.tabla}`}</p>
            {campos.length>0 ? <table><thead><tr><th>Campo</th><th>Antes</th><th>Después</th></tr></thead><tbody>{campos.map(k => <tr key={k}><td>{etiqueta(k)}</td><td><pre>{mostrar(e.antes?.[k])}</pre></td><td><pre>{mostrar(e.despues?.[k])}</pre></td></tr>)}</tbody></table> : <p>Este registro no contiene un desglose de valores anteriores y nuevos.</p>}
          </section></td></tr>}</Fragment>
        })}</tbody></table></div>
      {!datos?.eventos.length && <p>No hay actividades para estos filtros.</p>}
      <footer><button disabled={pagina===1} onClick={() => setPagina(p => p-1)}>Anterior</button><span>Página {pagina}</span><button disabled={!datos?.hay_mas} onClick={() => setPagina(p => p+1)}>Siguiente</button></footer>
    </>}
  </section>
}
