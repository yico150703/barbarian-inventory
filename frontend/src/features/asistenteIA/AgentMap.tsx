import { useEffect, useRef, useState, type PointerEvent, type CSSProperties } from 'react'
import { Bot, Network, X, Plus, Minus, Maximize, Scan, ArrowUpRight, Boxes, ShoppingBag, Tags, Utensils, CookingPot, BookOpen, Package, Layers, ShieldCheck, ChevronRight, BadgePercent, type LucideIcon } from 'lucide-react'
import type { AgenteId, CatalogoAgentes, RespuestaAsistente } from './service'
import { nombresAgentes } from './service'
import { etiqueta } from './labels'
import './AgentMap.css'

// Coordinates are node centers. The main branches form a tree; shared
// prerequisites remain explicit cross-links instead of duplicating agents.
const layout: { id: AgenteId; x: number; y: number; icon: LucideIcon; tone: string; caption: string }[] = [
  { id: 'compras', x: 225, y: 420, icon: ShoppingBag, tone: 'forest', caption: 'Pedidos y eventos cercanos' },
  { id: 'inventario', x: 380, y: 185, icon: Boxes, tone: 'forest', caption: 'Stock y operación diaria' },
  { id: 'carta_recetas', x: 360, y: 650, icon: Package, tone: 'olive', caption: 'Productos, categorías y proveedores' },
  { id: 'subproductos', x: 255, y: 835, icon: CookingPot, tone: 'sage', caption: 'Preparaciones internas' },
  { id: 'presentaciones', x: 830, y: 425, icon: Layers, tone: 'forest', caption: 'Artículo, contenido y precio' },
  { id: 'categorias_carta', x: 1030, y: 235, icon: Tags, tone: 'olive', caption: 'Organización de la carta' },
  { id: 'menajes', x: 1060, y: 560, icon: Utensils, tone: 'sage', caption: 'Platos, vasos y formas de servir' },
  { id: 'recetas', x: 785, y: 745, icon: BookOpen, tone: 'olive', caption: 'Ingredientes de cada presentación' },
  { id: 'promociones', x: 790, y: 130, icon: BadgePercent, tone: 'sage', caption: 'Combos, opciones y horarios' },
]
const center = { x: 570, y: 445 }
const connections: { from: AgenteId; to: AgenteId; path: string; extra?: boolean }[] = [
  { from: 'carta_recetas', to: 'subproductos', path: 'M360 650 Q330 750 255 835' },
  { from: 'categorias_carta', to: 'presentaciones', path: 'M1030 235 Q1020 390 830 425' },
  { from: 'menajes', to: 'presentaciones', path: 'M1060 560 Q970 430 830 425' },
  { from: 'presentaciones', to: 'recetas', path: 'M830 425 Q900 605 785 745' },
  { from: 'presentaciones', to: 'promociones', path: 'M830 425 Q905 260 790 130' },
  { from: 'subproductos', to: 'recetas', path: 'M255 835 Q535 955 785 745', extra: true },
  { from: 'carta_recetas', to: 'recetas', path: 'M360 650 Q540 755 785 745', extra: true },
]
const rootBranches: AgenteId[] = ['compras', 'inventario', 'carta_recetas', 'presentaciones']

export function AgentMap({ catalog, onClose, communications = [] }: { catalog: CatalogoAgentes; onClose: () => void; communications?: RespuestaAsistente['comunicaciones'] }) {
  const [selected, setSelected] = useState<AgenteId | 'orquestador'>('orquestador')
  const [panelOpen, setPanelOpen] = useState(false)
  const [zoom, setZoom] = useState(1)
  const [fit, setFit] = useState(1)
  const [pan, setPan] = useState({ x: 0, y: 0 })
  const [dragging, setDragging] = useState(false)
  const root = useRef<HTMLElement>(null)
  const viewport = useRef<HTMLDivElement>(null)
  const drag = useRef<{ x: number; y: number; px: number; py: number } | null>(null)
  const agent = catalog.agentes.find(a => a.id === selected)
  const config = layout.find(a => a.id === selected)
  const Icon = config?.icon ?? Network
  const visibleConnections = connections.filter(c => catalog.agentes.some(a => a.id === c.to &&
    a.recursos_solo_consulta?.some(resource => resource === c.from || (resource === 'productos' && c.from === 'carta_recetas'))) &&
    catalog.agentes.some(a => a.id === c.from))
  const requests = visibleConnections.filter(c => c.to === selected)
  const callers = visibleConnections.filter(c => c.from === selected)
  const latestCommunication = communications.at(-1)
  const related = new Set([selected, ...requests.map(c => c.from), ...callers.map(c => c.to)])

  function selectAgent(id: AgenteId | 'orquestador') {
    setSelected(id); setPanelOpen(true)
  }
  function closePanel() {
    setPanelOpen(false)
    root.current?.querySelector<HTMLButtonElement>('button[aria-pressed="true"]')?.focus({ preventScroll: true })
  }

  useEffect(() => {
    const element = viewport.current
    if (!element) return
    const observer = new ResizeObserver(([entry]) => setFit(Math.max(entry.contentRect.width < 780 ? .62 : .1,
      Math.min(entry.contentRect.width / 1200, entry.contentRect.height / 960, 1.25) * .96)))
    observer.observe(element)
    return () => observer.disconnect()
  }, [])

  function start(e: PointerEvent<HTMLDivElement>) {
    if (e.button !== 0 || (e.target as HTMLElement).closest('button, .agent-atlas-panel, .agent-atlas-live')) return
    drag.current = { x: e.clientX, y: e.clientY, px: pan.x, py: pan.y }
    e.currentTarget.setPointerCapture(e.pointerId); setDragging(true)
  }
  function move(e: PointerEvent<HTMLDivElement>) {
    if (drag.current) setPan({ x: drag.current.px + e.clientX - drag.current.x, y: drag.current.py + e.clientY - drag.current.y })
  }
  function stop() { drag.current = null; setDragging(false) }
  function reset() { setPan({ x: 0, y: 0 }); setZoom(1) }
  async function fullscreen() {
    try { if (document.fullscreenElement) await document.exitFullscreen(); else await root.current?.requestFullscreen() } catch { reset() }
  }

  return <section ref={root} className="agent-atlas agent-atlas-radial" aria-labelledby="agent-atlas-title">
    <header className="agent-atlas-heading"><div className="agent-atlas-title"><span className="agent-atlas-mark"><Network size={23} /></span><div><span className="agent-atlas-eyebrow">BARBARITO · INTELIGENCIA CONECTADA</span><h2 id="agent-atlas-title">Mapa de agentes</h2><p>Una red de especialistas, conectados por sus tareas y requisitos.</p></div></div>
      <button className="agent-atlas-close" onClick={onClose} aria-label="Cerrar mapa de agentes"><X size={18} /><span>Cerrar</span></button></header>
    <div className="agent-atlas-legend"><span><i />{catalog.agentes.length} especialistas · un Coordinador</span><span className="agent-atlas-edge-legend"><b />Rama principal <b className="is-requirement" />Conexión compartida</span></div>

    <div ref={viewport} className={`agent-atlas-viewport ${dragging ? 'is-dragging' : ''}`} onPointerDown={start} onPointerMove={move} onPointerUp={stop} onPointerCancel={stop}>
      <div className="agent-atlas-stage" style={{ '--radial-transform': `translate(-50%, -50%) translate(${pan.x}px, ${pan.y}px) scale(${fit * zoom})`, transform: `translate(-50%, -50%) translate(${pan.x}px, ${pan.y}px) scale(${fit * zoom})` } as CSSProperties}>
        <svg className="agent-atlas-wires" viewBox="0 0 1200 960" aria-hidden="true"><defs><linearGradient id="atlas-wire"><stop stopColor="#94b9a1" /><stop offset=".5" stopColor="#167b54" /><stop offset="1" stopColor="#94b9a1" /></linearGradient>
          <marker id="atlas-arrow" markerWidth="7" markerHeight="7" refX="6" refY="3.5" orient="auto"><polygon points="0 0,7 3.5,0 7" fill="#8b9159" /></marker><marker id="atlas-arrow-selected" markerWidth="7" markerHeight="7" refX="6" refY="3.5" orient="auto-start-reverse"><polygon points="0 0,7 3.5,0 7" fill="#258956" /></marker></defs>
          <g className="agent-atlas-rings"><circle cx="570" cy="445" r="155" /><circle cx="570" cy="445" r="290" /><circle cx="570" cy="445" r="435" /><path d="M80 445 H1110 M570 35 V920" /></g>
          {rootBranches.map(id => {
            const node = layout.find(n => n.id === id)!
            if (!catalog.agentes.some(a => a.id === id)) return null
            return <path key={id} className={`agent-atlas-root-wire ${selected === id || selected === 'orquestador' ? 'is-lit' : ''}`} d={`M${center.x} ${center.y} Q${(center.x + node.x) / 2} ${center.y} ${node.x} ${node.y}`} />
          })}
          {visibleConnections.map(c => {
            const highlighted = selected === c.to || selected === c.from
            const recent = communications.some(m => (m.de === c.from && m.a === c.to) || (m.a === c.from && m.de === c.to))
            return <g key={`${c.from}-${c.to}`} className={`agent-atlas-branch ${c.extra ? 'is-extra' : ''} ${highlighted ? 'is-selected' : ''} ${recent ? 'is-recent' : ''}`}><title>{nombresAgentes[c.to]} puede solicitar {nombresAgentes[c.from]} mediante el Coordinador. El resultado regresa tras confirmar.</title><path d={c.path} /><circle className="agent-atlas-junction" cx={layout.find(n => n.id === c.to)!.x} cy={layout.find(n => n.id === c.to)!.y} r="5" /></g>
          })}
        </svg>
        <button className={`agent-atlas-core ${selected === 'orquestador' ? 'is-selected' : ''}`} onClick={() => selectAgent('orquestador')} aria-pressed={selected === 'orquestador'} aria-controls="agent-atlas-detail" aria-expanded={panelOpen && selected === 'orquestador'}><span className="agent-atlas-core-icon"><Bot size={32} strokeWidth={1.5} /></span><strong>Coordinador</strong><small>Delega · conserva tu tarea · retoma</small><span className="agent-atlas-core-label">PUNTO DE ENTRADA</span></button>
        <span className="agent-atlas-sector is-operation">OPERACIÓN</span><span className="agent-atlas-sector is-catalog">INSUMOS Y PREPARACIÓN</span><span className="agent-atlas-sector is-menu">CARTA Y VENTAS</span>
        {layout.map(node => {
          const item = catalog.agentes.find(a => a.id === node.id)
          if (!item) return null
          const NodeIcon = node.icon
          return <button key={item.id} className={`agent-atlas-node agent-atlas-tone-${node.tone} ${selected === item.id ? 'is-selected' : ''} ${selected !== 'orquestador' && !related.has(item.id) ? 'is-muted' : ''} ${latestCommunication && (latestCommunication.de === item.id || latestCommunication.a === item.id) ? 'has-communication' : ''}`} style={{ left: node.x, top: node.y, "--node-x": `${node.x}px`, "--node-y": `${node.y}px` } as CSSProperties} onClick={() => selectAgent(item.id)} aria-pressed={selected === item.id} aria-controls="agent-atlas-detail" aria-expanded={panelOpen && selected === item.id}>
            <span className="agent-atlas-node-icon"><NodeIcon size={29} strokeWidth={1.5} /></span><span className="agent-atlas-node-body"><strong>{item.nombre}</strong><small>{node.caption}</small><span className="agent-atlas-node-meta"><small>{item.skills.length} {item.skills.length === 1 ? 'habilidad' : 'habilidades'}</small><span>Explorar <ChevronRight size={12} /></span></span></span></button>
        })}
      </div>
      <div className="agent-atlas-map-label"><span className="agent-atlas-map-cross">+</span><span>ECOSISTEMA BARBARIAN<small>Administración del asistente</small></span></div>
      <div className="agent-atlas-controls" onPointerDown={e => e.stopPropagation()}><button onClick={() => setZoom(z => Math.max(.6, z - .15))} disabled={zoom <= .6} aria-label="Alejar mapa"><Minus size={17} /></button><span aria-live="polite">{Math.round(zoom * 100)}%</span><button onClick={() => setZoom(z => Math.min(1.9, z + .15))} disabled={zoom >= 1.9} aria-label="Acercar mapa"><Plus size={17} /></button><span className="agent-atlas-control-separator" /><button onClick={reset} title="Centrar mapa" aria-label="Centrar mapa"><Scan size={17} /></button><button onClick={() => void fullscreen()} title="Pantalla completa" aria-label="Pantalla completa"><Maximize size={16} /></button></div>
      <span className="agent-atlas-pan-hint">{selected === 'orquestador' ? 'Arrastra para explorar · selecciona un agente para ver sus conexiones' : 'Los traspasos pasan por el Coordinador · cada creación requiere confirmación'}</span>
      {latestCommunication && <div className="agent-atlas-live" role="status"><span className="agent-atlas-eyebrow">ÚLTIMO TRASPASO DE ESTA CONVERSACIÓN</span><button onClick={() => selectAgent(latestCommunication.a)}>{nombresAgentes[latestCommunication.de]} <ChevronRight size={14} /> {nombresAgentes[latestCommunication.a]} <ArrowUpRight size={14} /></button><small>{latestCommunication.motivo}</small></div>}
      {panelOpen && <aside className={`agent-atlas-panel ${config && config.x > 540 ? 'is-panel-left' : ''}`} aria-labelledby="agent-atlas-panel-title" onPointerDown={e => e.stopPropagation()} onKeyDown={e => { if (e.key === 'Escape') { e.stopPropagation(); closePanel() } }}>
        <header className="agent-atlas-panel-heading"><div><span className="agent-atlas-eyebrow">EXPLORAR AGENTE</span><h3 id="agent-atlas-panel-title">{agent?.nombre ?? 'Coordinador'}</h3></div><button className="agent-atlas-panel-close" onClick={closePanel} aria-label="Cerrar detalle del agente"><X size={18} /></button></header>
        <div key={selected} className="agent-atlas-panel-scroll" tabIndex={0} role="region" aria-label={`Información e instrucciones de ${agent?.nombre ?? 'Coordinador'}`}>
    <section id="agent-atlas-detail" className="agent-atlas-detail">
      <div className="agent-atlas-detail-intro"><span className="agent-atlas-detail-icon"><Icon size={24} /></span><div><span className="agent-atlas-eyebrow">{agent ? 'ESPECIALISTA SELECCIONADO' : 'EL CENTRO DE TU ASISTENTE'}</span><h3>{agent?.nombre ?? 'Coordinador'}</h3><p>{agent?.descripcion ?? 'Interpreta lo que necesitas y dirige la solicitud al especialista adecuado, conservando el contexto de la conversación.'}</p></div></div>
      {requests.length > 0 && <div className="agent-atlas-flow-parents"><span>Puede solicitar ayuda a</span><div>{requests.map(c => <button key={c.from} onClick={() => selectAgent(c.from)}>{nombresAgentes[c.from]}<ChevronRight size={12} /></button>)}</div><p>Si falta un requisito, delega su creación. Después de tu confirmación recibe el resultado y continúa.</p></div>}
      {callers.length > 0 && <div className="agent-atlas-flow-parents is-return"><span>Devuelve resultados a</span><div>{callers.map(c => <button key={c.to} onClick={() => selectAgent(c.to)}>{nombresAgentes[c.to]}<ChevronRight size={12} /></button>)}</div></div>}
      {agent ? <><div className="agent-atlas-capabilities"><div><span>Puede trabajar con</span><p>{(agent.recursos_modificables ?? agent.recursos).map(etiqueta).join(' · ')}</p></div>{Boolean(agent.recursos_solo_consulta?.length) && <div><span>Consulta como referencia</span><p>{agent.recursos_solo_consulta?.map(etiqueta).join(' · ')}</p></div>}<div><span>Habilidades específicas</span><p>{agent.skills.map(s => s.nombre).join(' · ') || 'Instrucciones del especialista'}</p></div></div>
        <details className="agent-atlas-technical" open key={agent.id}><summary><ChevronRight size={15} />Instrucciones y skills</summary><div><details open><summary>Instrucciones del agente</summary><pre>{agent.instrucciones}</pre></details>{agent.skills.map(s => <details open key={s.archivo}><summary>{s.nombre}</summary><pre>{s.contenido}</pre></details>)}</div></details></> : <div className="agent-atlas-coordinator-flow"><span>Tu solicitud</span><ChevronRight size={16} /><span>Coordinador</span><ChevronRight size={16} /><span>Especialista</span><ChevronRight size={16} /><span>Revisión y confirmación</span></div>}
    </section>
        </div>
      </aside>}
    </div>
    <footer className="agent-atlas-footer"><ShieldCheck size={16} /><span>Los agentes preparan propuestas. Tú revisas y confirmas cada cambio.</span></footer>
  </section>
}
