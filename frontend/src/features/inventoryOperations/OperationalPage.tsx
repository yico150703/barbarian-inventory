import {useAuth} from '../../context/AuthContext'
import {DayPanel} from './DayPanel'
import {MixPanel} from './MixPanel'
import {CountsPanel} from './CountsPanel'
import './operations.css'
export function OperationalPage({section}:{section:'day'|'mix'|'counts'}){
 const {token,localActivo,perfilActivo,menu}=useAuth()
 const option={day:36,mix:37,counts:38}[section]
 const allowed=[2,3,4].includes(perfilActivo?.id_perfil??0)&&menu.some(m=>m.id_opcion_menu===option&&m.permisos.consultar)
 return <main className="inventory-operations" key={`${token}:${section}`}><header><span>INVENTARIO · {localActivo?.nombre}</span><h1>{{day:'Día operativo',mix:'Mix de ventas',counts:'Real vs. teórico'}[section]}</h1><p>{{day:'Cierra tu jornada cuando termine la atención, incluso de madrugada.',mix:'Consulta productos vendidos, cantidades e importes por día operativo y hora.',counts:'Asigna, registra y revisa conteos físicos cuando lo necesites.'}[section]}</p></header>
 <section className="io-card">{!allowed?<p>No tienes acceso a esta opción. Si acabas de activar la migración, vuelve a iniciar sesión para actualizar el menú.</p>:section==='day'?<DayPanel/>:section==='mix'?<MixPanel/>:<CountsPanel/>}</section></main>
}
