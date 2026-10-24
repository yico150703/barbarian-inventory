import {useEffect,useRef,useState} from 'react'
import {useNavigate} from 'react-router-dom'
import {SalonMap,type DistribucionSalon} from '../components/SalonMap'
import {SalonPinDialog,salonApi} from '../components/SalonPinDialog'
import './SalonPage.css'
interface Sesion {usuario:string;local:string;id_usuario:number;perfil:number}
interface Mesa {mesa:string;id_usuario:number;usuario:string;desde:string}
export function SalonPage(){
 const navigate=useNavigate(),[sesion,setSesion]=useState<Sesion|null>(null),[mapa,setMapa]=useState<DistribucionSalon|null>(null)
 const [mesas,setMesas]=useState<Mesa[]>([]),[seleccion,setSeleccion]=useState<string|null>(null),[error,setError]=useState(''),[mensaje,setMensaje]=useState('')
 const [modo,setModo]=useState<'normal'|'informacion'|'mover'|'reasignar'>('normal'),[origen,setOrigen]=useState<string|null>(null)
 const [pinAccion,setPinAccion]=useState<'mover'|'reasignar'|null>(null),[autorizacion,setAutorizacion]=useState(''),[busy,setBusy]=useState(false)
 const [lista,setLista]=useState(false),[miembros,setMiembros]=useState<{id_usuario:number;nombre:string}[]>([]),[buscar,setBuscar]=useState(''),[selector,setSelector]=useState(false)
 const listaDialog=useRef<HTMLDialogElement>(null),miembrosDialog=useRef<HTMLDialogElement>(null)
 const actual=mesas.find(m=>m.mesa===seleccion)
 useEffect(()=>{if(lista)listaDialog.current?.showModal()},[lista])
 useEffect(()=>{if(selector)miembrosDialog.current?.showModal()},[selector])
 useEffect(()=>{
  if(!sessionStorage.getItem('salon_token')){navigate('/login',{replace:true});return}
  const c=new AbortController()
  Promise.all([salonApi('me',undefined,'GET',c.signal),salonApi('distribucion',undefined,'GET',c.signal),salonApi('estado-mesas',undefined,'GET',c.signal)]).then(([s,d,m])=>{if(!c.signal.aborted){setSesion(s);setMapa(d);setMesas(m.mesas)}}).catch(e=>{if(!c.signal.aborted)setError(e.message)})
  return ()=>c.abort()
 },[navigate])
 async function refrescar(){const d=await salonApi('estado-mesas');setMesas(d.mesas)}
 function terminar(){setModo('normal');setOrigen(null);setAutorizacion('');setSelector(false)}
 async function operar(destino?:string,id_usuario?:number){
  if(busy||!origen)return
  setBusy(true);setError('')
  try{await salonApi(`mesas/${origen}/${modo}`,{autorizacion,destino,id_usuario});terminar();await refrescar();setMensaje('Cambio registrado correctamente.')}
  catch(e){setError(e instanceof Error?e.message:'No se pudo completar');terminar();await refrescar().catch(()=>{})}
  finally{setBusy(false)}
 }
 async function elegir(codigo:string){
  if(busy)return
  setSeleccion(codigo);setError('');setMensaje('')
  const mesa=mesas.find(m=>m.mesa===codigo)
  if(modo==='informacion')return
  if(modo==='mover'){
   if(!origen){if(!mesa){setError('Selecciona una mesa con pedidos para mover.');return}setOrigen(codigo);return}
   if(mesa||codigo===origen){setError('Selecciona una mesa destino libre.');return}
   await operar(codigo);return
  }
  if(modo==='reasignar'){
   if(!mesa){setError('Selecciona una mesa atendida.');return}
   setOrigen(codigo);setBusy(true)
   try{const d=await salonApi('miembros');setMiembros(d.usuarios);setBuscar('');setSelector(true)}catch(e){setError(e instanceof Error?e.message:'No se pudo cargar')}
   finally{setBusy(false)}return
  }
  if(mesa&&mesa.id_usuario!==sesion?.id_usuario&&![2,3].includes(sesion?.perfil??0)){setModo('informacion');return}
  navigate(`/salon/mesa/${codigo}`)
 }
 return <main className="salon-page salon-console"><header><h1>Salón {sesion?.local??''}</h1><span>{sesion?.usuario}</span></header>
 <div className="salon-notices" aria-live="polite">{error&&<p role="alert">{error}</p>}{mensaje&&<p>{mensaje}</p>}{modo!=='normal'&&<p>{modo==='informacion'?'Selecciona una mesa para ver quién la atiende.':modo==='mover'?(origen?`Origen ${origen}. Selecciona una mesa destino libre.`:'Selecciona la mesa que deseas mover.'):'Selecciona la mesa para cambiar su miembro de equipo.'}<button onClick={terminar} disabled={busy}>Cancelar acción</button></p>}</div>
 {modo==='informacion'&&seleccion&&<p className="salon-mobile-info">{seleccion}: {actual?`Atiende ${actual.usuario} ? ${new Date(actual.desde).toLocaleString('es-PE')}`:'Mesa disponible'}</p>}
 <div className="salon-console-body"><section className="salon-map-panel">{mapa?<SalonMap elementos={mapa.elementos} seleccion={seleccion} ocupadas={mesas.map(m=>m.mesa)} onSelect={codigo=>void elegir(codigo)}/>:<p>Cargando mapa...</p>}</section>
 <aside className="salon-console-info"><h2>{seleccion??'Tu salón'}</h2>{actual?<><span className="salon-occupied-label">En atención</span><p>Atiende: <strong>{actual.usuario}</strong></p><p>Desde {new Date(actual.desde).toLocaleString('es-PE')}</p>{actual.id_usuario!==sesion?.id_usuario&&![2,3].includes(sesion?.perfil??0)&&<p>Solo su responsable puede entrar a esta mesa.</p>}</>:<p>{seleccion?'Mesa disponible':'Toca una mesa para abrir su pedido.'}</p>}<div className="salon-console-user">{sesion?.usuario}<small>{sesion?.local}</small></div></aside></div>
 <footer className="salon-actionbar"><button onClick={()=>setLista(true)}>Listar mesas</button><button aria-pressed={modo==='informacion'} onClick={()=>{terminar();setModo('informacion')}}>Información</button>
 {sesion?.perfil===2&&<><button disabled={busy} onClick={()=>setPinAccion('mover')}>Mover mesa</button><button disabled={busy} onClick={()=>setPinAccion('reasignar')}>Cambiar miembro</button></>}
 <button className="salon-exit" disabled={busy} onClick={()=>{sessionStorage.removeItem('salon_token');navigate('/login',{replace:true})}}>Salir</button></footer>
 {pinAccion&&<SalonPinDialog accion={pinAccion} onCancel={()=>setPinAccion(null)} onAuthorized={token=>{setAutorizacion(token);setModo(pinAccion);setOrigen(null);setError('');setMensaje('');setPinAccion(null)}}/>}
 {lista&&<dialog ref={listaDialog} className="salon-action-dialog" onCancel={()=>setLista(false)}><h2>Mis mesas</h2><div className="salon-linear-list">{mesas.filter(m=>m.id_usuario===sesion?.id_usuario).map(m=><button key={m.mesa} onClick={()=>navigate(`/salon/mesa/${m.mesa}`)}>{m.mesa} ? {m.usuario}</button>)}</div>{!mesas.some(m=>m.id_usuario===sesion?.id_usuario)&&<p>No tienes mesas en atención.</p>}<button onClick={()=>setLista(false)}>Cerrar</button></dialog>}
 {selector&&<dialog ref={miembrosDialog} className="salon-action-dialog" onCancel={e=>{if(busy)e.preventDefault();else terminar()}}><h2>Cambiar miembro ? {origen}</h2><input aria-label="Buscar miembro" placeholder="Buscar por nombre" value={buscar} onChange={e=>setBuscar(e.target.value)}/><div className="salon-linear-list">{miembros.filter(m=>m.nombre.toLocaleLowerCase().includes(buscar.toLocaleLowerCase())).map(m=><button disabled={busy} key={m.id_usuario} onClick={()=>void operar(undefined,m.id_usuario)}>{m.nombre}</button>)}</div><button disabled={busy} onClick={terminar}>Cancelar</button></dialog>}
 </main>
}
