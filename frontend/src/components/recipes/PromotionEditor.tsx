import { formatearUnidad } from '../../utils/unitHelpers'
import { useEffect, useRef, useState, type FormEvent } from 'react'
import { formularioPromocion, guardarPromocion, type PresentacionPromocion } from '../../services/promotionService'
import type { PromocionDetalle } from '../../types/promotion'
import './RecipeEditor.css'
import './SubproductEditor.css'

interface Grupo {
  clave: number; id_promocion_grupo?: number; cantidad: string; repetir: boolean; opciones: number[]; busqueda: string;
}
export function PromotionEditor({ token, promocion: p, cerrar, guardado }: {
  token: string; promocion: PromocionDetalle | null; cerrar: () => void; guardado: (mensaje: string) => void
}) {
  const dialogo = useRef<HTMLDialogElement>(null)
  const siguiente = useRef(p?.grupos.length ?? 1)
  const [catalogo, setCatalogo] = useState<PresentacionPromocion[] | null>(null)
  const [error, setError] = useState('')
  const [guardando, setGuardando] = useState(false)
  const [intento, setIntento] = useState(0)
  const [nombre, setNombre] = useState(p?.nombre ?? '')
  const [precio, setPrecio] = useState(String(p?.precio ?? 0))
  const [activo, setActivo] = useState(p?.activo ?? true)
  const [reposiciones, setReposiciones] = useState<number[]>(p?.reposiciones ?? [])
  const [horario, setHorario] = useState(p?.tiene_horario ?? false)
  const [inicio, setInicio] = useState(p?.hora_inicio ?? '')
  const [fin, setFin] = useState(p?.hora_fin ?? '')
  const [grupos, setGrupos] = useState<Grupo[]>(() => p ? p.grupos.map((g, i) => ({ clave: i,
    id_promocion_grupo: g.id_promocion_grupo, cantidad: String(g.cantidad_elegir), repetir: g.permite_repetir,
    opciones: g.opciones.map(o => o.id_presentacion_venta), busqueda: '' }))
    : [{ clave: 0, cantidad: '1', repetir: false, opciones: [], busqueda: '' }])
  useEffect(() => { dialogo.current?.showModal() }, [])
  useEffect(() => {
    let vigente = true
    setError('')
    formularioPromocion(token).then(d => { if (vigente) setCatalogo(d.presentaciones) })
      .catch(e => { if (vigente) setError(e instanceof Error ? e.message : 'No se pudo cargar la carta') })
    return () => { vigente = false }
  }, [token, intento])
  function cambiar(clave: number, cambios: Partial<Grupo>) {
    setGrupos(actuales => actuales.map(g => g.clave === clave ? { ...g, ...cambios } : g))
  }
  async function guardar(e: FormEvent) {
    e.preventDefault()
    if (guardando || !catalogo) return
    if (!grupos.length || grupos.some(g => !g.opciones.length || (!g.repetir && Number(g.cantidad) > g.opciones.length))) {
      setError('Agrega opciones a cada grupo. Sin repetición, no puedes elegir más opciones de las disponibles.'); return
    }
    setGuardando(true); setError('')
    try {
      const r = await guardarPromocion(token, { nombre, precio, activo, hora_inicio: horario ? inicio : null, hora_fin: horario ? fin : null,
        grupos: grupos.map(g => ({ id_promocion_grupo: g.id_promocion_grupo, cantidad_elegir: Number(g.cantidad), permite_repetir: g.repetir, opciones: g.opciones })),
        reposiciones }, p?.id_promocion)
      guardado(r.mensaje)
    } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo guardar') }
    finally { setGuardando(false) }
  }
  return <dialog className="subproduct-dialog" ref={dialogo} aria-labelledby="promotion-editor-title" onCancel={e => { e.preventDefault(); if (!guardando) cerrar() }}>
    <form className="recipe-editor" onSubmit={e => void guardar(e)}>
      <header><div><h2 id="promotion-editor-title">{p ? 'Editar promoción' : 'Nueva promoción'}</h2><p>{p?.codigo ?? 'Código automático al guardar'}</p></div><button type="button" disabled={guardando} onClick={cerrar}>Cerrar</button></header>
      {error && <p className="recipe-editor__error" role="alert">{error}</p>}
      {!catalogo ? <p>Cargando carta… {error && <button type="button" onClick={() => setIntento(i => i + 1)}>Reintentar</button>}</p> : <fieldset disabled={guardando}>
        <div className="recipe-editor__grid">
          <label>Nombre<input required maxLength={150} value={nombre} onChange={e => setNombre(e.target.value)} /></label>
          <label>Precio de la promoción (S/)<input required type="number" min="0" max="99999999.99" step="0.01" value={precio} onChange={e => setPrecio(e.target.value)} /></label>
          <label>Estado<select value={activo ? 'activa' : 'inactiva'} onChange={e => setActivo(e.target.value === 'activa')}><option value="activa">Activa</option><option value="inactiva">Inactiva</option></select></label>
        </div>
        <label className="recipe-editor__check"><input type="checkbox" checked={horario} onChange={e => setHorario(e.target.checked)} />Definir horario</label>
        {horario && <><div className="recipe-editor__grid">
          <label>Desde<input required type="time" value={inicio} onChange={e => setInicio(e.target.value)} /></label>
          <label>Hasta<input required type="time" value={fin} onChange={e => setFin(e.target.value)} /></label>
        </div><p className="recipe-editor__hint">Si la hora final es menor que la inicial, el horario termina al día siguiente.</p></>}
        {grupos.map((g, index) => {
          const texto = g.busqueda.trim().toLocaleLowerCase('es')
          const resultados = texto ? catalogo.filter(o => o.activo && !g.opciones.includes(o.id_presentacion_venta) && `${o.codigo} ${o.nombre}`.toLocaleLowerCase('es').includes(texto)).slice(0, 30) : []
          return <section className="recipe-editor__ingredients" key={g.clave}>
            <h3>Grupo {index + 1}</h3>
            <div className="recipe-editor__grid">
              <label>Cuántas opciones puede escoger<input required type="number" min="1" max="32767" step="1" value={g.cantidad} onChange={e => cambiar(g.clave, { cantidad: e.target.value })} /></label>
              <label className="recipe-editor__check"><input type="checkbox" checked={g.repetir} onChange={e => cambiar(g.clave, { repetir: e.target.checked })} />Permitir repetir</label>
              <button type="button" onClick={() => setGrupos(gs => gs.filter(x => x.clave !== g.clave))}>Quitar grupo</button>
            </div>
            <label>Buscar artículo de carta<input type="search" placeholder="Nombre o código del artículo" value={g.busqueda} onChange={e => cambiar(g.clave, { busqueda: e.target.value })} /></label>
            {texto && <div className="recipe-editor__results">{resultados.map(o => <button type="button" key={o.id_presentacion_venta} onClick={() => cambiar(g.clave, { opciones: [...g.opciones, o.id_presentacion_venta], busqueda: '' })}>
              <span>{o.codigo} · {o.nombre} · {o.contenido} {formatearUnidad(o.unidad)} · {o.menaje}</span><span>Agregar</span>
            </button>)}{!resultados.length && <p>No hay coincidencias activas disponibles.</p>}</div>}
            {g.opciones.map(id => {
              const o = catalogo.find(x => x.id_presentacion_venta === id)
              return <div key={id} className="recipe-editor__ingredient" style={{ gridTemplateColumns: '1fr auto' }}>
                <div><strong>{o ? `${o.codigo} · ${o.nombre}` : `Presentación ${id} no disponible`}</strong><small>{o && `${o.contenido} ${formatearUnidad(o.unidad)} · ${o.menaje}${o.activo ? '' : ' · Inactiva'}`}</small>
                  <label className="recipe-editor__check"><input type="checkbox" checked={reposiciones.includes(id)} onChange={e => setReposiciones(actual => e.target.checked ? [...actual, id] : actual.filter(x => x !== id))} />Permitir reposición sin costo</label>
                </div>
                <button type="button" aria-label={`Quitar ${o?.nombre ?? id}`} onClick={() => { cambiar(g.clave, { opciones: g.opciones.filter(x => x !== id) }); setReposiciones(actual => actual.filter(x => x !== id)) }}>Quitar</button>
              </div>
            })}
            {!g.opciones.length && <p className="recipe-editor__hint">Busca y agrega las presentaciones que se pueden elegir.</p>}
          </section>
        })}
        <button type="button" disabled={grupos.length >= 50} onClick={() => setGrupos(gs => [...gs, { clave: siguiente.current++, cantidad: '1', repetir: false, opciones: [], busqueda: '' }])}>Agregar grupo de opciones</button>
      </fieldset>}
      <footer><button type="button" disabled={guardando} onClick={cerrar}>Cancelar</button><button type="submit" disabled={guardando || !catalogo}>{guardando ? 'Guardando…' : 'Guardar promoción'}</button></footer>
    </form>
  </dialog>
}
