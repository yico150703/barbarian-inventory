import { formatearUnidad } from '../../utils/unitHelpers'
import {useState} from 'react'
import {useAuth} from '../../context/AuthContext'
import {csv,opApi,qty,today,useQuery,when} from './shared'
import {Message} from './Message'
import {AssignmentsPanel,type Position} from './AssignmentsPanel'
interface Round {id_ronda:number;nombre:string;creado_en:string;cerrado_en:string|null;por_puesto?:boolean}
interface Person {id_usuario:number;nombre:string}
interface Count {
 id_ronda:number;id_producto:number;nombre:string;codigo:string;unidad:string;categoria:string;asignado_a:number|null;asignado_nombre:string
 teorico?:number;contado:number|null;corregido?:number|null;diferencia?:number|null;estado:string;observacion:string;version:number;justificacion?:string
 ronda?:string;creado_en?:string
 puesto_asignado?:number|null;puesto_nombre?:string;contado_nombre?:string;contado_perfil_nombre?:string;contado_puesto_nombre?:string;contado_en?:string
}
type Save=(product:Count,changes:Record<string,unknown>)=>Promise<void>
type ReviewDraft={cantidad:string;observacion:string}
export function CountsPanel(){
 const {token,perfilActivo}=useAuth(),[tab,setTab]=useState('conteos'),[revision,setRevision]=useState(0),[id,setId]=useState<number|null>(null)
 const {data,error}=useQuery<{rondas:Round[];por_puesto:boolean}>(token,'conteos',revision),[name,setName]=useState(''),[busy,setBusy]=useState(false),[failure,setFailure]=useState('')
 const manager=perfilActivo?.id_perfil===2,reviewer=[2,3].includes(perfilActivo?.id_perfil??0)
 const selected=id??data?.rondas[0]?.id_ronda
 async function create(){if(!token||busy)return;setBusy(true);setFailure('');try{const d=await opApi<{id_ronda:number}>(token,'conteos',{nombre:name});setId(d.id_ronda);setRevision(v=>v+1);setName('')}catch(e){setFailure((e as Error).message)}finally{setBusy(false)}}
 return <><nav className="io-tabs">{manager&&<button aria-pressed={tab==='asignaciones'} onClick={()=>setTab('asignaciones')}>Asignación por puesto</button>}<button aria-pressed={tab==='conteos'} onClick={()=>setTab('conteos')}>{reviewer?'Revisar conteos':'Mis conteos'}</button>{reviewer&&<button aria-pressed={tab==='diferencias'} onClick={()=>setTab('diferencias')}>Diferencias y justificación</button>}</nav>
 <Message error={error||failure}/>{tab==='asignaciones'?<AssignmentsPanel/>:tab==='diferencias'?<Differences/>:<>
 {reviewer&&<p>Edita las cantidades contadas y añade una observación si la necesitas. Guarda todos los cambios al cerrar la revisión; la cantidad del sistema y la diferencia no se editan.</p>}
 {manager&&data&&!data.rondas.some(r=>!r.cerrado_en)&&<form className="io-toolbar" onSubmit={e=>{e.preventDefault();void create()}}><label>Nuevo conteo<input required maxLength={120} value={name} onChange={e=>setName(e.target.value)} placeholder="Ej. Conteo de barra y cocina"/></label><button className="io-primary" disabled={busy}>Abrir conteo para el equipo</button></form>}
 {!reviewer&&data&&!data.rondas.some(r=>!r.cerrado_en)&&<p>Espera a que el gerente abra un conteo. Cuando esté habilitado, pulsa Actualizar para ver los productos de tu puesto.</p>}
 <div className="io-toolbar"><label>Ronda<select value={selected??''} onChange={e=>setId(Number(e.target.value))}><option value="" disabled>Selecciona una ronda</option>{data?.rondas.map(r=><option value={r.id_ronda} key={r.id_ronda}>{r.nombre} · {r.cerrado_en?'Finalizada':'Abierta'} · {when(r.creado_en)}</option>)}</select></label><button onClick={()=>setRevision(v=>v+1)}>Actualizar</button></div>
 {!data?.rondas.length&&<p>No hay conteos {reviewer?'entregados por el equipo':'asignados a tu puesto'}.</p>}
 {selected&&<RoundDetail key={`${selected}:${revision}`} id={selected} manager={manager} reviewer={reviewer} onFinish={()=>setRevision(v=>v+1)}/>}</>}</>
}
function RoundDetail({id,manager,reviewer,onFinish}:{id:number;manager:boolean;reviewer:boolean;onFinish:()=>void}){
 const {token}=useAuth(),[revision,setRevision]=useState(0),[busy,setBusy]=useState(false),[failure,setFailure]=useState(''),[success,setSuccess]=useState('')
 const {data,error}=useQuery<{ronda:Round;productos:Count[];equipo:Person[];puestos:Position[]}>(token,`conteos/${id}`,revision)
 const [search,setSearch]=useState(''),[status,setStatus]=useState(''),[history,setHistory]=useState(false)
 const [assignee,setAssignee]=useState(''),[category,setCategory]=useState('')
 const [drafts,setDrafts]=useState<Record<number,ReviewDraft>>({})
 const stage=(p:Count,draft:ReviewDraft)=>setDrafts(previous=>{const next={...previous};if(draft.cantidad===String(p.corregido??p.contado??'')&&draft.observacion===p.observacion)delete next[p.id_producto];else next[p.id_producto]=draft;return next})
 const invalidDraft=Object.values(drafts).some(d=>!d.cantidad.trim()||!Number.isFinite(Number(d.cantidad))||Number(d.cantidad)<0||Number(d.cantidad)>999999999.999)
 const save:Save=async(p,changes)=>{if(!token||busy)return;setBusy(true);setFailure('');setSuccess('');try{await opApi(token,`conteos/${id}/productos/${p.id_producto}`,{version:p.version,...changes},'PUT');setRevision(v=>v+1);setSuccess('Guardado. El stock teórico no se modifica.')}catch(e){setFailure((e as Error).message)}finally{setBusy(false)}}
 async function finish(){if(!token||busy||!data||invalidDraft)return;setBusy(true);setFailure('');try{await opApi(token,`conteos/${id}/finalizar`,{aceptar_entregados:true,correcciones:drafts,versiones:Object.fromEntries(data.productos.map(p=>[String(p.id_producto),p.version]))});onFinish()}catch(e){setFailure((e as Error).message)}finally{setBusy(false)}}
 if(!data)return <Message error={error}/>
 const byPosition=!!data.ronda.por_puesto
 const assigned=(p:Count)=>byPosition?p.puesto_asignado??null:p.asignado_a
 const assignedName=(p:Count)=>byPosition?p.puesto_nombre:p.asignado_nombre
 const people=new Map(byPosition?data.puestos.map(p=>[p.id_puesto_laboral,p.nombre]):data.equipo.map(u=>[u.id_usuario,u.nombre]))
 const assignedCounts=new Map<number,number>()
 for(const p of data.productos){const key=assigned(p);if(key!==null){people.set(key,assignedName(p)||people.get(key)||String(key));assignedCounts.set(key,(assignedCounts.get(key)??0)+1)}}
 const members=[...people].sort((a,b)=>a[1].localeCompare(b[1],'es'))
 const unassigned=data.productos.filter(p=>assigned(p)===null).length
 const categories=[...new Set(data.productos.map(p=>p.categoria).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'es'))
 const rows=data.productos.filter(p=>(!status||p.estado===status)&&(!category||p.categoria===category)&&(!assignee||(assignee==='unassigned'?assigned(p)===null:String(assigned(p))===assignee))&&`${p.nombre} ${p.codigo} ${p.categoria} ${assignedName(p)} ${p.contado_nombre??''}`.toLocaleLowerCase().includes(search.trim().toLocaleLowerCase()))
 const closed=!!data.ronda.cerrado_en
 return <><Message error={error||failure}/>{success&&<p role="status" className="io-success">{success}</p>}
 <div className="io-summary"><div><small>REFERENCIA DEL CONTEO</small><h2>{data.ronda.nombre}</h2><p>{when(data.ronda.creado_en)}</p><p>Las cantidades teóricas corresponden a ese momento. Contar, revisar y justificar no ajusta el inventario.</p></div><div><small>REVISADOS</small><h2>{data.productos.filter(p=>p.estado==='REVISADO').length} / {data.productos.length}</h2>
 {reviewer&&!closed&&<button disabled={busy||invalidDraft||data.productos.some(p=>!['HECHO','REVISADO'].includes(p.estado))} className="io-primary" onClick={()=>void finish()}>{busy?'Guardando…':'Guardar y cerrar revisión'}</button>}{closed&&<strong>Revisión cerrada</strong>}</div></div>
 {reviewer&&<section aria-label="Asignación de productos"><h3>Asignación y revisión por {byPosition?'puesto':'miembro (ronda anterior)'}</h3>{manager&&!closed&&<p>{byPosition?'La distribución se copió de la configuración permanente. Puedes corregir el puesto de un producto pendiente solo para esta ronda.':'Esta ronda anterior conserva sus asignaciones personales.'}</p>}<p>{data.productos.length-unassigned} productos asignados · {unassigned} sin asignar</p></section>}
 <div className="io-toolbar"><label>Buscar producto<input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Nombre, código o categoría"/></label>
 {reviewer&&<label>{byPosition?'Puesto responsable':'Miembro de equipo'}<select value={assignee} onChange={e=>setAssignee(e.target.value)}><option value="">Todos</option><option value="unassigned">Sin asignar ({unassigned})</option>{members.map(([userId,userName])=><option key={userId} value={userId}>{userName} ({assignedCounts.get(userId)??0})</option>)}</select></label>}
 <label>Categoría<select value={category} onChange={e=>setCategory(e.target.value)}><option value="">Todas las categorías</option>{categories.map(c=><option key={c} value={c}>{c}</option>)}</select></label>
 <label>Estado<select value={status} onChange={e=>setStatus(e.target.value)}><option value="">Todos</option>{['PENDIENTE','EN_PROCESO','HECHO','REVISADO'].map(s=><option key={s} value={s}>{s.replace('_',' ')}</option>)}</select></label>
 <button disabled={!search&&!status&&!assignee&&!category} onClick={()=>{setSearch('');setStatus('');setAssignee('');setCategory('')}}>Limpiar filtros</button>
 {reviewer&&<><button onClick={()=>setHistory(v=>!v)}>{history?'Ocultar':'Ver'} historial</button><button onClick={()=>csv(`conteo-${id}.csv`,['Producto','Unidad','Asignado','Contado por','Perfil','Puesto utilizado','Fecha','Teórico','Contado original','Real revisado','Diferencia','Estado','Observación'],rows.map(p=>[p.nombre,formatearUnidad(p.unidad),assignedName(p)||'Sin asignar',p.contado_nombre??'',p.contado_perfil_nombre??'',p.contado_puesto_nombre??'',p.contado_en??'',p.teorico??null,p.contado,p.corregido??null,p.diferencia??null,p.estado,p.observacion]))}>Descargar vista filtrada CSV</button></>}</div>
 <p role="status">Mostrando {rows.length} de {data.productos.length} productos.</p>
 {reviewer&&!closed&&<p role="status">{Object.keys(drafts).length} productos con cambios pendientes. Todo se guarda con «Guardar y cerrar revisión».{invalidDraft&&' Revisa las cantidades inválidas.'}</p>}
 {history&&<CountHistory id={id} revision={revision}/>}
 <div className="io-table"><table><thead><tr><th>Producto</th><th>Responsable</th>{reviewer&&<th>Cantidad del sistema</th>}<th>{reviewer?'Cantidad contada':'Mi conteo'}</th><th>Estado</th>{reviewer&&<th>Diferencia</th>}<th>Acciones</th></tr></thead><tbody>
 {data.productos.map(p=><CountRow hidden={!rows.some(row=>row.id_producto===p.id_producto)} key={`${p.id_producto}:${p.version}`} p={p} team={data.equipo} positions={data.puestos} byPosition={byPosition} manager={manager} reviewer={reviewer} closed={closed} busy={busy} save={save} stage={stage} draft={drafts[p.id_producto]}/>)}{!rows.length&&<tr><td colSpan={reviewer?7:5}>No hay productos que coincidan con estos filtros.</td></tr>}</tbody></table></div></>
}
function CountRow({hidden,p,team,positions,byPosition,manager,reviewer,closed,busy,save,stage,draft}:{hidden:boolean;p:Count;team:Person[];positions:Position[];byPosition:boolean;manager:boolean;reviewer:boolean;closed:boolean;busy:boolean;save:Save;stage:(p:Count,draft:ReviewDraft)=>void;draft?:ReviewDraft}){
 const [memberValue,setMemberValue]=useState(String(p.contado??'')),[showNote,setShowNote]=useState(false)
 const value=reviewer?draft?.cantidad??String(p.corregido??p.contado??''):memberValue
 const note=draft?.observacion??p.observacion
 const invalid=value.trim()===''||!Number.isFinite(Number(value))||Number(value)<0
 const done=byPosition&&p.estado==='HECHO'
 const editable=reviewer?['HECHO','REVISADO'].includes(p.estado):!['HECHO','REVISADO'].includes(p.estado)
 const difference=invalid?null:Number(value)-Number(p.teorico??0)
 return <tr hidden={hidden}><td><strong>{p.nombre}</strong><small>{p.codigo} · {formatearUnidad(p.unidad)}</small></td><td>{manager&&!closed&&p.estado==='PENDIENTE'?<select aria-label={`Asignar ${p.nombre}`} disabled={busy} value={(byPosition?p.puesto_asignado:p.asignado_a)??''} onChange={e=>void save(p,{accion:'asignar',[byPosition?'id_puesto_laboral':'id_usuario']:e.target.value?Number(e.target.value):null})}><option value="" disabled={byPosition}>Sin asignar</option>{byPosition?positions.map(u=><option key={u.id_puesto_laboral} value={u.id_puesto_laboral}>{u.nombre}</option>):team.map(u=><option key={u.id_usuario} value={u.id_usuario}>{u.nombre}</option>)}</select>:(byPosition?p.puesto_nombre:p.asignado_nombre)||'Sin asignar'}{p.contado_nombre&&<small>Contó: {p.contado_nombre}<br/>{p.contado_perfil_nombre} {p.contado_puesto_nombre&&`· ${p.contado_puesto_nombre}`}<br/>{p.contado_en&&when(p.contado_en)}</small>}</td>
 {reviewer&&<td>{qty(p.teorico)}</td>}
 <td><input aria-label={`Cantidad ${p.nombre}`} type="number" min="0" step="0.001" max="999999999.999" value={value} disabled={closed||busy||!editable} onChange={e=>{if(reviewer)stage(p,{cantidad:e.target.value,observacion:note});else setMemberValue(e.target.value)}}/>
 {reviewer&&p.corregido!=null&&p.corregido!==p.contado&&<small>Original del equipo: {qty(p.contado)}</small>}{reviewer&&showNote&&!closed&&<textarea autoFocus aria-label={`Observación ${p.nombre}`} placeholder="Observación opcional" maxLength={2000} value={note} disabled={busy||!editable} onChange={e=>stage(p,{cantidad:value,observacion:e.target.value})}/>} {reviewer&&note&&(!showNote||closed)&&<small>Observación: {note}</small>}</td>
 <td><span className="io-badge">{p.estado.replace('_',' ')}</span></td>{reviewer&&<td className={(difference??0)<0?'io-negative':''}>{qty(p.contado===null?null:difference)}<small>{(difference??0)<0?'Faltante':(difference??0)>0?'Sobrante':''}</small></td>}
 <td><div className="io-row-actions">{!reviewer&&!closed&&!done&&p.estado!=='REVISADO'&&!(reviewer&&p.estado==='HECHO')&&<><button disabled={busy||invalid} onClick={()=>void save(p,{accion:'contar',cantidad:value,estado:'EN_PROCESO'})}>Guardar avance</button><button disabled={busy||invalid} onClick={()=>void save(p,{accion:'contar',cantidad:value,estado:'HECHO'})}>Hecho</button></>}
 {reviewer&&!closed&&editable&&<button disabled={busy} aria-expanded={showNote} onClick={()=>setShowNote(v=>!v)}>{showNote?'Ocultar observación':note?'Editar observación':'Añadir observación'}</button>}</div></td></tr>
}
function CountHistory({id,revision}:{id:number;revision:number}){
 const {token}=useAuth(),{data,error}=useQuery<{historial:{id_historial:number;producto:string;usuario:string;accion:string;creado_en:string;anterior:Count;nuevo:Count}[]}>(token,`conteos/${id}/historial`,revision)
 return <details open><summary>Historial de cambios</summary><Message error={error}/><div className="io-table"><table><thead><tr><th>Hora / responsable</th><th>Producto</th><th>Acción</th><th>Detalle</th></tr></thead><tbody>{data?.historial.map(h=><tr key={h.id_historial}><td>{when(h.creado_en)}<small>{h.usuario}</small>{h.accion==='contar'&&<small>{h.nuevo.contado_perfil_nombre} {h.nuevo.contado_puesto_nombre&&`· ${h.nuevo.contado_puesto_nombre}`}</small>}</td><td>{h.producto}</td><td>{h.accion}</td><td>{h.accion==='asignar'&&h.nuevo.puesto_nombre&&<small>Puesto: {h.anterior.puesto_nombre||'Sin asignar'} → {h.nuevo.puesto_nombre}</small>}Contado: {qty(h.anterior.contado)} → {qty(h.nuevo.contado)}<small>Revisado: {qty(h.anterior.corregido)} → {qty(h.nuevo.corregido)}</small><small>{h.nuevo.observacion}</small><small>{h.nuevo.justificacion}</small></td></tr>)}</tbody></table></div></details>
}
function Differences(){
 const {token}=useAuth(),[from,setFrom]=useState(today),[to,setTo]=useState(today),[top,setTop]=useState(10),[revision,setRevision]=useState(0)
 const [query,setQuery]=useState(`diferencias?desde=${today()}&hasta=${today()}&top=10`),[busy,setBusy]=useState(false),[failure,setFailure]=useState('')
 const {data,error}=useQuery<{productos:Count[]}>(token,query,revision)
 const save:Save=async(p,d)=>{if(!token||busy)return;setBusy(true);setFailure('');try{await opApi(token,`conteos/${p.id_ronda}/productos/${p.id_producto}`,{...d,version:p.version},'PUT');setRevision(v=>v+1)}catch(e){setFailure((e as Error).message)}finally{setBusy(false)}}
 return <><form className="io-toolbar" onSubmit={e=>{e.preventDefault();setQuery(`diferencias?desde=${from}&hasta=${to}&top=${top}`);setRevision(v=>v+1)}}><label>Desde<input type="date" required value={from} onChange={e=>setFrom(e.target.value)}/></label><label>Hasta<input type="date" required min={from} value={to} onChange={e=>setTo(e.target.value)}/></label><label>Mayores diferencias<select value={top} onChange={e=>setTop(Number(e.target.value))}>{[5,10,15,20].map(n=><option key={n} value={n}>Top {n}</option>)}</select></label><button className="io-primary">Consultar</button></form>
 <p>Ordenado por magnitud de la diferencia en la unidad de cada producto; no por valor monetario. Solo incluye conteos revisados.</p><Message error={error||failure}/>
 <div className="io-table"><table><thead><tr><th>Fecha / ronda</th><th>Producto</th><th>Teórico</th><th>Real revisado</th><th>Diferencia</th><th>Justificación</th></tr></thead><tbody>{data?.productos.map(p=><DifferenceRow key={`${p.id_ronda}:${p.id_producto}:${p.version}`} p={p} busy={busy} save={save}/>)}{!data?.productos.length&&<tr><td colSpan={6}>No hay diferencias revisadas para estas fechas.</td></tr>}</tbody></table></div></>
}
function DifferenceRow({p,busy,save}:{p:Count;busy:boolean;save:Save}){
 const [note,setNote]=useState(p.justificacion??'')
 return <tr><td>{p.creado_en&&when(p.creado_en)}<small>{p.ronda}</small></td><td>{p.nombre}<small>{formatearUnidad(p.unidad)}</small></td><td>{qty(p.teorico)}</td><td>{qty(p.corregido??p.contado)}</td><td className={(p.diferencia??0)<0?'io-negative':''}>{qty(p.diferencia)}</td><td><textarea aria-label={`Justificación ${p.nombre}`} maxLength={2000} value={note} onChange={e=>setNote(e.target.value)} disabled={busy}/><button disabled={busy||!note.trim()} onClick={()=>void save(p,{accion:'justificar',justificacion:note})}>Guardar justificación</button></td></tr>
}
