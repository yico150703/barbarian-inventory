import {useEffect,useState} from 'react'
import {useAuth} from '../context/AuthContext'
import {SalonMap,type DistribucionSalon,type ElementoSalon} from '../components/SalonMap'
const api=import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'
export function SalonLayoutPage(){
 const {token}=useAuth()
 return <SalonLayoutEditor key={token??''}/>
}
function SalonLayoutEditor(){
 const {token,perfilActivo,localActivo}=useAuth()
 const [datos,setDatos]=useState<DistribucionSalon|null>(null),[seleccion,setSeleccion]=useState<string|null>(null)
 const [error,setError]=useState(''),[mensaje,setMensaje]=useState(''),[ocupado,setOcupado]=useState(false),[cambios,setCambios]=useState(false)
 const permitido=perfilActivo?.id_perfil===2
 useEffect(()=>{
  setDatos(null);setSeleccion(null);setCambios(false);setError('');setMensaje('')
  if(!permitido)return
  const control=new AbortController()
  fetch(`${api}/salon/distribucion`,{headers:{Authorization:`Bearer ${token}`},signal:control.signal}).then(async r=>{const d=await r.json();if(!r.ok)throw Error(d.mensaje??'No se pudo cargar');return d}).then(d=>{if(!control.signal.aborted)setDatos(d)}).catch(e=>{if(!control.signal.aborted)setError(e.message)})
  return ()=>control.abort()
 },[token,permitido,localActivo?.id_local])
 const elegido=datos?.elementos.find(e=>e.codigo===seleccion)
 function modificar(codigo:string,parcial:Partial<ElementoSalon>){if(ocupado)return;setDatos(d=>d?{...d,elementos:d.elementos.map(e=>e.codigo===codigo?{...e,...parcial}:e)}:d);setCambios(true);setMensaje('')}
 function agregar(tipo:ElementoSalon['tipo']){
  if(!datos)return
  if(tipo==='barra' && datos.elementos.some(e=>e.tipo==='barra'))return
  const prefijo=tipo==='mesa'?'M':'B'
  let numero=1
  while(datos.elementos.some(e=>e.codigo===`${prefijo}${String(numero).padStart(2,'0')}`))numero++
  const codigo=tipo==='barra'?'BARRA':`${prefijo}${String(numero).padStart(2,'0')}`
  setDatos({...datos,elementos:[...datos.elementos,{codigo,tipo,x:5,y:5,ancho:tipo==='barra'?60:12,alto:12}]});setSeleccion(codigo);setCambios(true);setMensaje('')
 }
 async function guardar(){
  if(!datos || ocupado)return
  setOcupado(true);setError('');setMensaje('')
  try{const r=await fetch(`${api}/salon/distribucion`,{method:'PUT',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify(datos)});const d=await r.json();if(!r.ok)throw Error(d.mensaje??'No se pudo guardar');setDatos(d);setCambios(false);setMensaje('Distribución guardada para este local.')}
  catch(e){setError(e instanceof Error?e.message:'Error al guardar')}
  finally{setOcupado(false)}
 }
 if(!permitido)return <p>Esta opcion corresponde al perfil Gerente.</p>
 return <main className="salon-layout-page"><header><h1>Opciones de salón</h1><p>Distribución de {localActivo?.nombre}. Agrega mesas y puestos, y ajusta su ubicación y tamaño.</p></header>
 {error&&<p role="alert" className="salon-layout-error">{error}</p>}{mensaje&&<p role="status">{mensaje}</p>}
 {datos?<><div className="salon-layout-workspace"><SalonMap elementos={datos.elementos} seleccion={seleccion} onSelect={setSeleccion} onMove={ocupado?undefined:(codigo,x,y)=>modificar(codigo,{x,y})}/>
 <aside className="salon-layout-tools"><button disabled={ocupado||datos.elementos.length>=150} onClick={()=>agregar('mesa')}>Agregar mesa</button>
 <button disabled={ocupado||datos.elementos.length>=150||!datos.elementos.some(e=>e.tipo==='barra')} onClick={()=>agregar('puesto')}>Agregar puesto de barra</button>
 {!datos.elementos.some(e=>e.tipo==='barra')&&<button disabled={ocupado} onClick={()=>agregar('barra')}>Agregar barra</button>}
 <label>Seleccionar elemento<select value={seleccion??''} onChange={e=>setSeleccion(e.target.value)}><option value="">Selecciona</option>{datos.elementos.map(e=><option key={e.codigo}>{e.codigo}</option>)}</select></label>
 {elegido?<><h3>{elegido.codigo}</h3>{(['x','y','ancho','alto'] as const).map(k=><label key={k}>{({x:'Posición horizontal',y:'Posición vertical',ancho:'Ancho',alto:'Alto'})[k]} (%)<input type="number" min={k==='x'||k==='y'?0:4} max={100} step={1} disabled={ocupado} value={Math.round(elegido[k]*10)/10} onChange={e=>modificar(elegido.codigo,{[k]:Number(e.target.value)})}/></label>)}
 <button disabled={ocupado} onClick={()=>{setDatos({...datos,elementos:datos.elementos.filter(e=>e.codigo!==seleccion)});setSeleccion(null);setCambios(true)}}>Quitar del mapa</button></>:<p>Selecciona un elemento para ajustar sus medidas.</p>}
 <small>Arrastra los elementos para moverlos. También puedes usar los campos de posición. Las mesas con pedidos registrados no se pueden quitar.</small></aside></div>
 <div className="salon-layout-actions"><button disabled={!cambios||ocupado} onClick={()=>void guardar()}>{ocupado?'Guardando...':'Guardar distribución'}</button><button disabled={ocupado} onClick={()=>window.location.reload()}>Descartar cambios y recargar</button></div></>:!error&&<p>Cargando mapa...</p>}</main>
}
