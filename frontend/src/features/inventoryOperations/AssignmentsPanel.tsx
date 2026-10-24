import {useEffect,useRef,useState} from 'react'
import {useAuth} from '../../context/AuthContext'
import {opApi,useQuery} from './shared'
import {Message} from './Message'
import './assignments.css'

export interface Position {id_puesto_laboral:number;nombre:string}
interface Product {id_producto:number;codigo:string;nombre:string;categoria:string;id_puesto_laboral:number|null;puesto:string|null}
interface AssignmentData {puestos:Position[];productos:Product[]}

function filter(products:Product[],search:string,category:string,position:string){
 const term=search.trim().toLocaleLowerCase()
 return products.filter(p=>(!category||p.categoria===category)&&(!position||(position==='none'?p.id_puesto_laboral===null:String(p.id_puesto_laboral)===position))&&`${p.nombre} ${p.codigo}`.toLocaleLowerCase().includes(term))
}
function Filters({data,search,setSearch,category,setCategory,position,setPosition}:{data:AssignmentData;search:string;setSearch:(s:string)=>void;category:string;setCategory:(s:string)=>void;position:string;setPosition:(s:string)=>void}){
 return <div className="io-toolbar"><label>Buscar producto<input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Nombre o código"/></label><label>Categoría<select value={category} onChange={e=>setCategory(e.target.value)}><option value="">Todas las categorías</option>{[...new Set(data.productos.map(p=>p.categoria))].sort().map(c=><option key={c}>{c}</option>)}</select></label><label>Asignación actual<select value={position} onChange={e=>setPosition(e.target.value)}><option value="">Todos los puestos</option><option value="none">Sin asignar</option>{data.puestos.map(p=><option key={p.id_puesto_laboral} value={p.id_puesto_laboral}>{p.nombre}</option>)}</select></label></div>
}
export function AssignmentsPanel(){
 const {token}=useAuth(),[revision,setRevision]=useState(0),[editing,setEditing]=useState(false),[success,setSuccess]=useState('')
 const {data,error}=useQuery<AssignmentData>(token,'asignaciones',revision)
 const [search,setSearch]=useState(''),[category,setCategory]=useState(''),[position,setPosition]=useState('')
 if(!data)return <Message error={error}/>
 const rows=filter(data.productos,search,category,position)
 return <section><h2>Asignación permanente por puesto</h2><p>Define qué cuenta Cocina, Bartender y Mesero en este local. Cualquier miembro con ese puesto activo puede contar sus productos. Los nuevos conteos copiarán esta configuración.</p><p>Un producto pertenece a un solo puesto. Cambiar su asignación aquí no modifica las rondas ya iniciadas.</p>
 <Message error={error}/>{success&&<p className="io-success" role="status">{success}</p>}
 <div className="io-summary"><div><strong>{data.productos.filter(p=>p.id_puesto_laboral===null).length} productos sin asignar</strong><p>{data.productos.length} productos activos en total</p></div><button className="io-primary" onClick={()=>setEditing(true)}>Asignar varios productos</button></div>
 <Filters {...{data,search,setSearch,category,setCategory,position,setPosition}}/>
 <p>Mostrando {rows.length} productos</p><div className="io-table"><table><thead><tr><th>Producto</th><th>Categoría</th><th>Puesto responsable</th></tr></thead><tbody>{rows.map(p=><tr key={p.id_producto}><td>{p.nombre}<small>{p.codigo}</small></td><td>{p.categoria}</td><td>{p.puesto||'Sin asignar'}</td></tr>)}{!rows.length&&<tr><td colSpan={3}>No hay productos para estos filtros.</td></tr>}</tbody></table></div>
 {editing&&<AssignmentDialog data={data} close={()=>setEditing(false)} saved={()=>{setEditing(false);setRevision(v=>v+1);setSuccess('Asignación guardada. Se utilizará en los próximos conteos.')}}/>}</section>
}
function AssignmentDialog({data,close,saved}:{data:AssignmentData;close:()=>void;saved:()=>void}){
 const {token}=useAuth(),dialog=useRef<HTMLDialogElement>(null)
 const [search,setSearch]=useState(''),[category,setCategory]=useState(''),[position,setPosition]=useState(''),[target,setTarget]=useState('')
 const [selected,setSelected]=useState<Set<number>>(new Set()),[busy,setBusy]=useState(false),[error,setError]=useState('')
 useEffect(()=>{dialog.current?.showModal()},[])
 const rows=filter(data.productos,search,category,position)
 const all=rows.length>0&&rows.every(p=>selected.has(p.id_producto))
 function toggle(ids:number[],checked:boolean){setSelected(previous=>{const next=new Set(previous);for(const id of ids){if(checked)next.add(id);else next.delete(id)}return next})}
 async function save(){if(!token||busy||!selected.size||!target)return;setBusy(true);setError('');try{await opApi(token,'asignaciones',{productos:[...selected],id_puesto_laboral:target==='none'?null:Number(target)},'PUT');saved()}catch(e){setError((e as Error).message)}finally{setBusy(false)}}
 return <dialog ref={dialog} className="io-assignment-dialog" aria-labelledby="assignment-title" onCancel={e=>{e.preventDefault();if(!busy)close()}}><form onSubmit={e=>{e.preventDefault();void save()}}><h2 id="assignment-title">Asignar varios productos</h2><p>Filtra, marca los productos y elige el puesto. Se reemplazará su asignación anterior. La selección se conserva al cambiar de filtro.</p><Message error={error}/>
 <fieldset disabled={busy}><Filters {...{data,search,setSearch,category,setCategory,position,setPosition}}/><div className="io-toolbar"><label>Puesto de destino<select required value={target} onChange={e=>setTarget(e.target.value)}><option value="" disabled>Selecciona un puesto</option>{data.puestos.map(p=><option key={p.id_puesto_laboral} value={p.id_puesto_laboral}>{p.nombre}</option>)}<option value="none">Quitar asignación</option></select></label><button type="button" onClick={()=>setSelected(new Set())}>Limpiar selección</button></div>
 <label className="io-bulk-check"><input type="checkbox" checked={all} disabled={!rows.length} onChange={e=>toggle(rows.map(p=>p.id_producto),e.target.checked)}/>Seleccionar los {rows.length} productos filtrados</label>
 <div className="io-assignment-products">{rows.map(p=><label key={p.id_producto} className="io-bulk-check"><input type="checkbox" checked={selected.has(p.id_producto)} onChange={e=>toggle([p.id_producto],e.target.checked)}/><span><strong>{p.nombre}</strong><small>{p.codigo} · {p.categoria} · {p.puesto||'Sin asignar'}</small></span></label>)}{!rows.length&&<p>No hay productos para estos filtros.</p>}</div></fieldset>
 <footer><span aria-live="polite">{selected.size} seleccionados</span><button type="button" disabled={busy} onClick={close}>Cancelar</button><button className="io-primary" disabled={busy||!target||!selected.size}>{busy?'Guardando…':'Guardar asignación'}</button></footer></form></dialog>
}
