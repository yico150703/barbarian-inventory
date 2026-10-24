import { formatearUnidad } from '../../utils/unitHelpers'
import {useState} from 'react'
import {useAuth} from '../../context/AuthContext'
import {csv,day,money,opApi,qty,useQuery,when} from './shared'
import {Message} from './Message'

interface Day {id_jornada:number;fecha:string;abierto_en:string;cerrado_en:string|null}
interface Product {id_producto:number;codigo:string;nombre:string;unidad:string;inicial:number;entradas:number;salidas:number;final:number;motivos:{motivo:string;entradas:number;salidas:number}[]}
export interface Sale {id_presentacion:number;nombre:string;hora:number|null;cantidad:number;total:number}
interface Report extends Day {reporte:{inventario:Product[];ventas:Sale[]}}
const reasons:Record<string,string>={VENTA_SALON:'Venta de salón',MERMA:'Merma',PRESTAMO_ENTREGADO:'Préstamo entregado',PRESTAMO_RECIBIDO:'Préstamo recibido',DEVOLUCION_PROVEEDOR:'Devolución a proveedor',REPOSICION_PROVEEDOR:'Reposición de proveedor',RECEPCION_COMPRA:'Recepción de compra',CORRECCION_RECEPCION:'Corrección de recepción'}
export function DayPanel(){
  const {token,menu}=useAuth(),[revision,setRevision]=useState(0),[selected,setSelected]=useState<number|null>(null)
  const {data,error}=useQuery<{dias:Day[]}>(token,'dias',revision)
  const [busy,setBusy]=useState(false),[failure,setFailure]=useState('')
  const id=selected??data?.dias[0]?.id_jornada
  const active=data?.dias.find(d=>!d.cerrado_en)
  const canClose=menu.find(m=>m.id_opcion_menu===36)?.permisos.cerrar
  async function open(){if(busy||!token)return;setBusy(true);setFailure('');try{const d=await opApi<{id_jornada:number}>(token,'dias/abrir',{});setSelected(d.id_jornada);setRevision(v=>v+1)}catch(e){setFailure((e as Error).message)}finally{setBusy(false)}}
  return <><Message error={error||failure}/><div className="io-toolbar">
    <label>Día operativo<select value={id??''} onChange={e=>setSelected(Number(e.target.value))}><option value="" disabled>Selecciona un día</option>
      {data?.dias.map(d=><option key={d.id_jornada} value={d.id_jornada}>{day(d.fecha)} · {d.cerrado_en?'Cerrado':'Abierto'}</option>)}</select></label>
    <button onClick={()=>setRevision(v=>v+1)}>Actualizar</button>
    {!active&&canClose&&<button className="io-primary" disabled={busy} onClick={()=>void open()}>Abrir siguiente día</button>}
  </div><p>El día no cambia a medianoche. Las operaciones de madrugada pertenecen al día que sigue abierto.</p>
    {id&&<DayReport key={`${id}:${revision}`} id={id} canClose={!!canClose} onClosed={()=>setRevision(v=>v+1)}/>}</>
}
function DayReport({id,canClose,onClosed}:{id:number;canClose:boolean;onClosed:()=>void}){
  const {token}=useAuth(),{data,error}=useQuery<Report>(token,`dias/${id}`)
  const [tab,setTab]=useState('inventario'),[busy,setBusy]=useState(false),[failure,setFailure]=useState('')
  async function close(){if(busy||!token)return;setBusy(true);setFailure('');try{await opApi(token,`dias/${id}/cerrar`,{});onClosed()}catch(e){setFailure((e as Error).message)}finally{setBusy(false)}}
  if(!data)return <Message error={error}/>
  const products=data.reporte.inventario,sales=data.reporte.ventas
  return <><Message error={failure}/><div className="io-summary"><div><small>{data.cerrado_en?'DÍA CERRADO':'DÍA ABIERTO'}</small><h2>{day(data.fecha)}</h2><p>Inicio: {when(data.abierto_en)}<br/>Cierre: {when(data.cerrado_en)}</p></div>
    <div><small>VENTAS COBRADAS</small><h2>{money(sales.reduce((s,v)=>s+v.total,0))}</h2><p>{qty(sales.reduce((s,v)=>s+v.cantidad,0))} presentaciones vendidas</p></div>
    {!data.cerrado_en&&canClose&&<button className="io-primary" disabled={busy} onClick={()=>void close()}>{busy?'Cerrando…':`Cerrar día ${day(data.fecha)}`}</button>}</div>
    <nav className="io-tabs"><button aria-pressed={tab==='inventario'} onClick={()=>setTab('inventario')}>Inventario y motivos</button><button aria-pressed={tab==='ventas'} onClick={()=>setTab('ventas')}>Productos vendidos</button></nav>
    <div className="io-toolbar"><button onClick={()=>tab==='inventario'?csv(`inventario-${data.fecha}.csv`,['Código','Producto','Unidad','Inicial','Entradas','Salidas','Final','Motivos'],products.map(p=>[p.codigo,p.nombre,formatearUnidad(p.unidad),p.inicial,p.entradas,p.salidas,p.final,p.motivos.map(m=>`${reasons[m.motivo]??m.motivo}: +${m.entradas} / -${m.salidas}`).join(' | ')])):csv(`ventas-${data.fecha}.csv`,['Producto','Cantidad','Total S/'],sales.map(p=>[p.nombre,p.cantidad,p.total]))}>Descargar hoja CSV</button></div>
    <div className="io-table">{tab==='inventario'?<table><thead><tr><th>Producto</th><th>Unidad</th><th>Inicial</th><th>Entradas</th><th>Salidas</th><th>Final</th><th>Motivos</th></tr></thead><tbody>{products.map(p=><tr key={p.id_producto}><td>{p.nombre}<small>{p.codigo}</small></td><td>{formatearUnidad(p.unidad)}</td><td>{qty(p.inicial)}</td><td>{qty(p.entradas)}</td><td>{qty(p.salidas)}</td><td><strong>{qty(p.final)}</strong></td><td>{p.motivos.map(m=><small key={m.motivo}>{reasons[m.motivo]??m.motivo}: +{qty(m.entradas)} / −{qty(m.salidas)}</small>)}</td></tr>)}</tbody></table>:<SalesTable rows={sales}/>}</div></>
}
export function SalesTable({rows}:{rows:Sale[]}){return <table><thead><tr><th>Producto / presentación</th><th>Hora de cobro</th><th>Cantidad</th><th>Total vendido</th></tr></thead><tbody>{rows.map((p,i)=><tr key={i}><td>{p.nombre}</td><td>{p.hora==null?'Total':`${String(p.hora).padStart(2,'0')}:00 – ${String((p.hora+1)%24).padStart(2,'0')}:00`}</td><td>{qty(p.cantidad)}</td><td>{money(p.total)}</td></tr>)}{!rows.length&&<tr><td colSpan={4}>No hay ventas cobradas para estos filtros.</td></tr>}</tbody></table>}
