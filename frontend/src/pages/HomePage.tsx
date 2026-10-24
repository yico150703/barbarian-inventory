import {Link} from 'react-router-dom'
import {useAuth} from '../context/AuthContext'
import './HomePage.css'
export function HomePage(){
 const {usuario,perfilActivo,localActivo,menu}=useAuth()
 const operational=[2,3,4].includes(perfilActivo?.id_perfil??0)
 const links=menu.filter(m=>[15,33,36,37,38].includes(m.id_opcion_menu)&&m.permisos.consultar&&m.url_menu)
 return <div className="home-page"><section className="home-welcome"><div><span className="home-welcome__label">PANEL PRINCIPAL</span><h1>Buen día, {usuario?.nombres}</h1>
 <p>{operational?`Local: ${localActivo?.nombre??''}. Consulta el stock, tu día operativo y los conteos asignados.`:'Administra los usuarios y los catálogos compartidos del sistema.'}</p></div></section>
 {operational&&<section className="home-welcome"><div><h2>Inventario y operación</h2><p>Los conteos físicos se realizan por indicación del gerente. El día operativo termina cuando un responsable lo cierra.</p><div style={{display:'flex',gap:14,flexWrap:'wrap'}}>{links.map(m=><Link key={m.id_opcion_menu} to={m.url_menu!}>{m.nombre}</Link>)}</div></div></section>}</div>
}