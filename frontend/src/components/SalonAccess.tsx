import { useEffect, useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'

const api=import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'
export function SalonAccess() {
  const navigate=useNavigate()
  const [local,setLocal]=useState('')
  const [usuario,setUsuario]=useState('')
  const [pin,setPin]=useState('')
  const [opciones,setOpciones]=useState<{locales:{id_local:number;nombre:string}[];usuarios:{id_usuario:number;nombre:string}[]}>({locales:[],usuarios:[]})
  const [error,setError]=useState('')
  const [ocupado,setOcupado]=useState(false)
  useEffect(() => {
    const controller=new AbortController()
    setError('');setOpciones(o => ({...o,usuarios:[]}))
    fetch(`${api}/salon/opciones?local=${local || '0'}`,{signal:controller.signal})
      .then(async r => {const d=await r.json();if(!r.ok) throw new Error(d.mensaje);return d})
      .then(setOpciones).catch(e => {if(!controller.signal.aborted)setError(e.message)})
    return () => controller.abort()
  },[local])
  async function ingresar(e:FormEvent) {
    e.preventDefault();setOcupado(true);setError('')
    try {
      const r=await fetch(`${api}/salon/login`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id_local:Number(local),id_usuario:Number(usuario),pin})})
      const d=await r.json()
      if(!r.ok) throw new Error(d.mensaje ?? 'No se pudo acceder')
      sessionStorage.setItem('salon_token',d.token);setPin('');navigate('/salon',{replace:true})
    } catch(e) {setError(e instanceof Error ? e.message : 'No se pudo acceder');setPin('')}
    finally {setOcupado(false)}
  }
  return <form className="login-form salon-form" onSubmit={ingresar}>
    <label>Local<select required value={local} disabled={ocupado} onChange={e => {setLocal(e.target.value);setUsuario('');setPin('')}}>
      <option value="">Selecciona tu local</option>{opciones.locales.map(l => <option key={l.id_local} value={l.id_local}>{l.nombre}</option>)}
    </select></label>
    <label>Usuario<select required value={usuario} disabled={!local || ocupado} onChange={e => {setUsuario(e.target.value);setPin('')}}>
      <option value="">Selecciona tu nombre</option>{opciones.usuarios.map(u => <option key={u.id_usuario} value={u.id_usuario}>{u.nombre}</option>)}
    </select></label>
    <label>PIN de Salón<input required type="password" inputMode="numeric" pattern="[0-9]{4}" maxLength={4} autoComplete="off" disabled={ocupado}
      value={pin} onChange={e => setPin(e.target.value.replace(/[^0-9]/g,''))} placeholder="4 dígitos" /></label>
    <p>Acceso para gerente, supervisor, meseros y bartender con PIN asignado.</p>
    {error && <p role="alert">{error}</p>}
    <button className="login-submit" disabled={ocupado || !usuario}>{ocupado ? 'INGRESANDO…' : 'ENTRAR A SALÓN'}</button>
  </form>
}
