import {useState} from 'react'
import {useAuth} from '../../context/AuthContext'
import {SalesTable,type Sale} from './DayPanel'
import {csv,money,qty,today,useQuery} from './shared'
import {Message} from './Message'
export function MixPanel(){
  const {token}=useAuth(),[from,setFrom]=useState(today),[to,setTo]=useState(today),[hours,setHours]=useState<number[]>([]),[separate,setSeparate]=useState(false),[top,setTop]=useState(0)
  const [query,setQuery]=useState(`mix?desde=${today()}&hasta=${today()}`),[revision,setRevision]=useState(0)
  const {data,error}=useQuery<{productos:Sale[];total:number;cantidad:number}>(token,query,revision)
  const ranking=new Map<number,number>()
  data?.productos.forEach(p=>ranking.set(p.id_presentacion,(ranking.get(p.id_presentacion)??0)+p.cantidad))
  const leaders=new Set([...ranking].sort((a,b)=>b[1]-a[1]).slice(0,top).map(([id])=>id))
  const rows=top?data?.productos.filter(p=>leaders.has(p.id_presentacion)):data?.productos
  return <><form onSubmit={e=>{e.preventDefault();const p=new URLSearchParams({desde:from,hasta:to,separar:separate?'1':'0'});hours.forEach(h=>p.append('hora',String(h)));setQuery(`mix?${p}`);setRevision(v=>v+1)}}>
    <div className="io-toolbar"><label>Desde<input required type="date" value={from} onChange={e=>setFrom(e.target.value)}/></label><label>Hasta<input required type="date" min={from} value={to} onChange={e=>setTo(e.target.value)}/></label>
      <label>Ranking por cantidad<select value={top} onChange={e=>setTop(Number(e.target.value))}><option value={0}>Todos</option>{[5,10,15,20].map(n=><option key={n} value={n}>Top {n}</option>)}</select></label></div>
    <details><summary>Filtrar horas de cobro (hora de Lima)</summary><p>Sin selección se incluyen todas. Puedes elegir horas a ambos lados de medianoche.</p><div className="io-hours">{Array.from({length:24},(_,h)=><button type="button" key={h} aria-pressed={hours.includes(h)} onClick={()=>setHours(a=>a.includes(h)?a.filter(v=>v!==h):[...a,h])}>{String(h).padStart(2,'0')}:00</button>)}</div>
      <button type="button" onClick={()=>setHours([])}>Todas las horas</button></details>
    <div className="io-toolbar"><label className="io-check"><input type="checkbox" checked={separate} onChange={e=>setSeparate(e.target.checked)}/>Separar por hora</label><button className="io-primary">Consultar</button></div>
  </form><p>Fechas por día operativo; horas por el momento del cobro en Lima. Los cobros anteriores a esta migración usan su fecha calendario.</p>
    <Message error={error}/>{data&&<><div className="io-summary"><div><small>TOTAL DEL FILTRO</small><h2>{money(data.total)}</h2></div><div><small>CANTIDAD VENDIDA</small><h2>{qty(data.cantidad)}</h2></div></div>
      <button onClick={()=>csv('mix-ventas.csv',['Producto','Hora','Cantidad','Total S/'],(rows??[]).map(p=>[p.nombre,p.hora,p.cantidad,p.total]))}>Descargar hoja CSV</button>
      <div className="io-table"><SalesTable rows={rows??[]}/></div></>}</>
}
