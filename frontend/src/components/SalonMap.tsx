import type { PointerEvent } from 'react'
import './SalonMap.css'
export interface ElementoSalon {codigo:string;tipo:'mesa'|'puesto'|'barra';x:number;y:number;ancho:number;alto:number}
export interface DistribucionSalon {version:number;elementos:ElementoSalon[]}
export function SalonMap({elementos,seleccion,onSelect,onMove,ocupadas=[]}:{elementos:ElementoSalon[];ocupadas?:string[];seleccion?:string|null;onSelect:(codigo:string)=>void;onMove?:(codigo:string,x:number,y:number)=>void}) {
  function arrastrar(event:PointerEvent<HTMLButtonElement>,e:ElementoSalon) {
    if(!onMove)return
    const boton=event.currentTarget, plano=boton.parentElement!.getBoundingClientRect()
    const x=event.clientX,y=event.clientY
    boton.setPointerCapture(event.pointerId);onSelect(e.codigo)
    boton.onpointermove=mov => onMove(e.codigo,Math.max(0,Math.min(100-e.ancho,e.x+(mov.clientX-x)/plano.width*100)),Math.max(0,Math.min(100-e.alto,e.y+(mov.clientY-y)/plano.height*100)))
    const terminar=()=>{boton.onpointermove=null;boton.onpointerup=null;boton.onpointercancel=null}
    boton.onpointerup=terminar;boton.onpointercancel=terminar
  }
  return <div className={`salon-map ${onMove ? 'salon-map--editing':''}`} aria-label="Distribución del salon">
    {elementos.map(e=><button type="button" key={e.codigo} className={`salon-map-item salon-map-${e.tipo} ${ocupadas.includes(e.codigo)?'salon-map-occupied':''}`} aria-pressed={seleccion===e.codigo}
      disabled={!onMove && e.tipo==='barra'} style={{left:`${e.x}%`,top:`${e.y}%`,width:`${e.ancho}%`,height:`${e.alto}%`}}
      onPointerDown={event=>arrastrar(event,e)} onClick={()=>onSelect(e.codigo)}>{e.codigo}</button>)}
  </div>
}
