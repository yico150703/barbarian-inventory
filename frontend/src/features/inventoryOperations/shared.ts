import {useEffect,useState} from 'react'

export async function opApi<T>(token:string,path:string,body?:unknown,method='POST',signal?:AbortSignal):Promise<T>{
  const r=await fetch(`${import.meta.env.VITE_API_URL??'http://127.0.0.1:5000/api'}/inventario-operativo/${path}`,{
    method:body===undefined?'GET':method,signal,headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)})
  const data=await r.json();if(!r.ok)throw new Error(data.mensaje??'No se pudo completar la operación');return data
}
export function useQuery<T>(token:string|null,path:string,revision=0){
  const [result,setResult]=useState<{path:string;revision:number;data:T|null;error:string}|null>(null)
  useEffect(()=>{
    const c=new AbortController()
    if(token&&path)opApi<T>(token,path,undefined,'GET',c.signal).then(data=>{if(!c.signal.aborted)setResult({path,revision,data,error:''})})
      .catch(e=>{if(!c.signal.aborted)setResult({path,revision,data:null,error:e.message})})
    return()=>c.abort()
  },[token,path,revision])
  return {data:result?.path===path?result.data:null,error:result?.path===path?result.error:'',loading:!!path&&(result?.path!==path||result?.revision!==revision)}
}
export const qty=(n:number|null|undefined)=>n==null?'—':Number(n).toLocaleString('es-PE',{maximumFractionDigits:3})
export const money=(n:number)=>new Intl.NumberFormat('es-PE',{style:'currency',currency:'PEN'}).format(n)
export const when=(s:string|null)=>s?new Date(s).toLocaleString('es-PE',{timeZone:'America/Lima'}):'Abierto'
export const day=(s:string)=>s.split('-').reverse().join('/')
export const today=()=>{const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Lima',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date());return ['year','month','day'].map(t=>parts.find(p=>p.type===t)?.value).join('-')}
export function csv(name:string,headers:string[],rows:(string|number|null)[][]){
  const cell=(v:string|number|null)=>`"${String(typeof v==='string'&&/^[=+@-]/.test(v)?"'"+v:v??'').replace(/"/g,'""')}"`
  const blob=new Blob(['\uFEFF'+[headers,...rows].map(r=>r.map(cell).join(';')).join('\r\n')],{type:'text/csv;charset=utf-8'})
  const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)
}
