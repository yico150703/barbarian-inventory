import { useEffect, useState, type FormEvent } from 'react'
import { Plus, Trash2, X } from 'lucide-react'
import { guardarReceta, obtenerFormularioReceta } from '../../services/recipeService'
import type { FormularioReceta, IngredienteDisponible, IngredienteEntrada, Receta, RecetaEntrada } from '../../types/recipe'
import './RecipeEditor.css'
import type { UnidadMedida } from '../../types/units'
import { unidadesCompatibles, etiquetaUnidad, formatearUnidad, convertirCantidadVisible } from '../../utils/unitHelpers'

export type Fila = IngredienteEntrada & { codigo: string; nombre: string; unidad: string }

export function ListaIngredientes({ titulo, filas, productos, cambiar, unico = false, disabled, tipo = 'PRODUCTO', bloquearAgregar = false, unidades = [] }: {
  titulo: string; filas: Fila[]; productos: IngredienteDisponible[]; cambiar: (filas: Fila[]) => void; unico?: boolean; disabled: boolean; tipo?: IngredienteEntrada['tipo_componente']; bloquearAgregar?: boolean; unidades?: UnidadMedida[]
}) {
  const [busqueda, setBusqueda] = useState('')
  const esSubproducto = tipo === 'SUBPRODUCTO'
  const limiteAlcanzado = bloquearAgregar || (unico && filas.length > 0)
  const texto = busqueda.trim().toLocaleLowerCase('es')
  const coincidencias = texto ? productos.filter((p) => p.activo && `${p.codigo} ${p.nombre}`.toLocaleLowerCase('es').includes(texto)).slice(0, 25) : []
  function agregar(p: IngredienteDisponible) {
    cambiar([...filas, { tipo_componente: tipo, id: p.id, codigo: p.codigo, nombre: p.nombre, unidad: p.unidad, cantidad: '1' }])
    setBusqueda('')
  }
  return <section className="recipe-editor__ingredients">
    <h3>{titulo}</h3>
    <label>{esSubproducto ? 'Buscar subproducto' : 'Buscar producto de inventario'}
      <input type="search" placeholder={esSubproducto ? 'Nombre o código del subproducto' : 'Nombre o código del producto'} value={busqueda} disabled={disabled || limiteAlcanzado} onChange={(e) => setBusqueda(e.target.value)} />
    </label>
    {texto && !limiteAlcanzado && <div className="recipe-editor__results">
      {coincidencias.map((p) => <button key={p.id} type="button" disabled={disabled || filas.some((f) => f.tipo_componente === tipo && f.id === p.id)} onClick={() => agregar(p)}>
        <span><b>{p.codigo}</b> · {p.nombre}</span><span>{formatearUnidad(p.unidad)} <Plus size={16} /></span>
      </button>)}
      {!coincidencias.length && <p>No se encontraron {esSubproducto ? 'subproductos' : 'productos'} activos.</p>}
    </div>}
    {filas.length ? <div className="recipe-editor__rows">
      {filas.map((fila, index) => <div className="recipe-editor__ingredient" key={`${fila.tipo_componente}-${fila.id}`}>
        <div><small>{fila.codigo}{fila.tipo_componente === 'SUBPRODUCTO' ? ' · Subproducto' : ''}</small><strong>{fila.nombre}</strong></div>
        <label>Cantidad<input type="number" min="0.001" max="999999999.999" step="0.001" required disabled={disabled} value={fila.cantidad} onChange={(e) => cambiar(filas.map((f, i) => i === index ? { ...f, cantidad: e.target.value } : f))} /></label>
        <label>Unidad
          <select disabled={disabled} value={fila.unidad_cantidad ?? fila.unidad}
            onChange={(e) => cambiar(filas.map((f, i) => i === index ? {
              ...f, unidad_cantidad: e.target.value,
              cantidad: convertirCantidadVisible(f.cantidad, f.unidad_cantidad ?? f.unidad, e.target.value, unidades),
            } : f))}>
            {unidadesCompatibles(unidades, fila.unidad).map((u) => (
              <option key={u.codigo} value={u.valor}>{etiquetaUnidad(unidades, u.valor)}</option>
            ))}
            {!unidadesCompatibles(unidades, fila.unidad).length && (
              <option value={fila.unidad}>{formatearUnidad(fila.unidad)}</option>
            )}
          </select>
        </label>
        <button className="recipe-editor__remove" type="button" disabled={disabled} aria-label={`Quitar ${fila.nombre}`} onClick={() => cambiar(filas.filter((_, i) => i !== index))}><Trash2 size={18} /></button>
      </div>)}
    </div> : <p className="recipe-editor__hint">Busca y agrega {unico ? 'el ingrediente base' : esSubproducto ? 'los subproductos que necesitas' : 'los productos que necesitas'}.</p>}
  </section>
}

export function RecipeEditor({ token, receta, cerrar, guardado }: {
  token: string; receta: Receta | null; cerrar: () => void; guardado: (mensaje: string) => void
}) {
  const [catalogo, setCatalogo] = useState<FormularioReceta | null>(null)
  const [error, setError] = useState('')
  const [guardando, setGuardando] = useState(false)
  const [busquedaItem, setBusquedaItem] = useState('')
  const [form, setForm] = useState({
    id_item_carta: receta?.id_item_carta ?? 0, id_presentacion_venta: receta?.id_presentacion_venta ?? 0,
    nombre_item: receta?.item_carta ?? '', id_categoria_carta: receta?.id_categoria_carta ?? 0,
    tipo_item: receta?.tipo_item ?? 'PREPARADO', contenido: String(receta?.contenido ?? 1),
    unidad_presentacion: receta?.unidad_presentacion ?? '', id_menaje: receta?.id_menaje ?? 0,
    instrucciones: receta?.instrucciones ?? '',
  })
  const [ingredientes, setIngredientes] = useState<Fila[]>(() => (receta?.componentes ?? []).map((c) => ({
    tipo_componente: c.tipo_componente, id: (c.tipo_componente === 'PRODUCTO' ? c.id_producto : c.id_subproducto)!,
    cantidad: String(c.cantidad), nombre: c.nombre_componente, codigo: c.codigo_componente, unidad: c.unidad,
  })))
  const [usaSubproductos, setUsaSubproductos] = useState(() => !!receta?.componentes.some((c) => c.tipo_componente === 'SUBPRODUCTO'))
  const productosSeleccionados = ingredientes.filter((i) => i.tipo_componente === 'PRODUCTO')
  const subproductosSeleccionados = ingredientes.filter((i) => i.tipo_componente === 'SUBPRODUCTO')
  const componentesActivos = usaSubproductos ? ingredientes : productosSeleccionados
  function cambiarProductos(filas: Fila[]) {
    setIngredientes((actuales) => [...filas, ...actuales.filter((i) => i.tipo_componente === 'SUBPRODUCTO')])
  }
  function cambiarSubproductos(filas: Fila[]) {
    setIngredientes((actuales) => [...actuales.filter((i) => i.tipo_componente === 'PRODUCTO'), ...filas])
  }
  const [usaOpciones, setUsaOpciones] = useState(!!receta?.grupo_salsa)
  const [maximo, setMaximo] = useState(String(receta?.grupo_salsa?.cantidad_maxima ?? 1))
  const [repetir, setRepetir] = useState(receta?.grupo_salsa?.permite_repetir ?? false)
  const [opciones, setOpciones] = useState<Fila[]>(() => (receta?.grupo_salsa?.opciones ?? []).map((o) => ({
    tipo_componente: 'PRODUCTO', id: o.id_producto, cantidad: String(o.cantidad), nombre: o.nombre, codigo: o.codigo, unidad: o.unidad,
  })))

  useEffect(() => {
    let vigente = true
    obtenerFormularioReceta(token).then((datos) => { if (vigente) setCatalogo(datos) })
      .catch((e: unknown) => { if (vigente) setError(e instanceof Error ? e.message : 'No se pudo cargar el formulario.') })
    return () => { vigente = false }
  }, [token])

  useEffect(() => {
    const anterior = document.activeElement as HTMLElement | null
    const campo = document.getElementById('recipe-editor-title')
    campo?.focus()
    function tecla(evento: KeyboardEvent) {
      if (evento.key === 'Escape' && !guardando) { evento.preventDefault(); cerrar() }
      if (evento.key === 'Tab') {
        const controles = campo?.closest('form')?.querySelectorAll<HTMLElement>('button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea:not(:disabled)')
        if (!controles?.length) return
        const primero = controles[0]
        const ultimo = controles[controles.length - 1]
        if (evento.shiftKey && (document.activeElement === primero || document.activeElement === campo)) { evento.preventDefault(); ultimo.focus() }
        else if (!evento.shiftKey && document.activeElement === ultimo) { evento.preventDefault(); primero.focus() }
      }
    }
    document.addEventListener('keydown', tecla)
    return () => { document.removeEventListener('keydown', tecla); anterior?.focus() }
  }, [cerrar, guardando])

  function elegirItem(id: number) {
    const item = catalogo?.items.find((i) => i.id_item_carta === id)
    setForm({ ...form, id_item_carta: id, id_presentacion_venta: 0, tipo_item: item?.tipo ?? 'PREPARADO', id_categoria_carta: item?.id_categoria_carta ?? 0 })
  }

  function elegirPresentacion(id: number) {
    const p = catalogo?.presentaciones.find((p) => p.id_presentacion_venta === id)
    setForm({ ...form, id_presentacion_venta: id, ...(p ? { contenido: String(p.contenido), unidad_presentacion: p.unidad, id_menaje: p.id_menaje } : {}) })
  }

  async function guardar(evento: FormEvent) {
    evento.preventDefault()
    if (guardando) return
    if (!componentesActivos.length) { setError('Agrega al menos un ingrediente.'); return }
    if (form.tipo_item === 'DIRECTO' && componentesActivos.length !== 1) { setError('Para un ítem directo conserva un solo ingrediente base.'); return }
    if (usaOpciones && (!opciones.length || (!repetir && Number(maximo) > opciones.length))) { setError('Agrega las opciones elegibles y revisa la cantidad que se puede escoger.'); return }
    const entrada: RecetaEntrada = {
      id_presentacion_venta: form.id_presentacion_venta,
      instrucciones: form.instrucciones,
      componentes: componentesActivos.map(({ tipo_componente, id, cantidad, unidad_cantidad }) => ({ tipo_componente, id, cantidad, unidad_cantidad })),
      grupo_salsa: usaOpciones ? { cantidad_maxima: Number(maximo), permite_repetir: repetir,
        opciones: opciones.map(({ tipo_componente, id, cantidad, unidad_cantidad }) => ({ tipo_componente, id, cantidad, unidad_cantidad })) } : null,
    }
    setGuardando(true)
    setError('')
    try {
      const respuesta = await guardarReceta(token, entrada, receta?.id_receta)
      guardado(respuesta.mensaje)
    } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo guardar la receta.') }
    finally { setGuardando(false) }
  }

  return <div className="recipe-editor-backdrop">
    <form className="recipe-editor" role="dialog" aria-modal="true" aria-labelledby="recipe-editor-title" onSubmit={(e) => void guardar(e)}>
      <header><div><h2 id="recipe-editor-title" tabIndex={-1}>{receta ? 'Editar receta' : 'Nueva receta'}</h2><p>{receta ? `${receta.codigo_item} · ${receta.item_carta} · ${receta.contenido} ${formatearUnidad(receta.unidad_presentacion)}` : 'Selecciona una presentación de Carta que aún no tenga receta.'}</p></div><button type="button" aria-label="Cerrar editor" disabled={guardando} onClick={cerrar}><X /></button></header>
      {error && <p className="recipe-editor__error" role="alert">{error}</p>}
      {!catalogo ? <p>Cargando opciones de la receta…</p> : <fieldset disabled={guardando}>
        {!receta && <>
          <div className="recipe-editor__grid">
            <label>Buscar artículo<input type="search" value={busquedaItem} placeholder="Nombre o código" onChange={e => setBusquedaItem(e.target.value)} /></label>
            <label>Artículo pendiente<select required value={form.id_item_carta || ''} onChange={e => elegirItem(Number(e.target.value))}>
              <option value="">Seleccionar artículo</option>
              {catalogo.items.filter(i => catalogo.presentaciones.some(p => p.id_item_carta === i.id_item_carta && p.id_receta === null) && (i.id_item_carta === form.id_item_carta || `${i.codigo} ${i.nombre}`.toLocaleLowerCase('es').includes(busquedaItem.toLocaleLowerCase('es')))).map(i => <option key={i.id_item_carta} value={i.id_item_carta}>{i.codigo} · {i.nombre}</option>)}
            </select></label>
            <label>Presentación sin receta<select required value={form.id_presentacion_venta || ''} onChange={e => elegirPresentacion(Number(e.target.value))}>
              <option value="">Seleccionar presentación</option>
              {catalogo.presentaciones.filter(p => p.id_item_carta === form.id_item_carta && p.id_receta === null).map(p => <option key={p.id_presentacion_venta} value={p.id_presentacion_venta}>{p.contenido} {formatearUnidad(p.unidad)} · {catalogo.menajes.find(m => m.id_menaje === p.id_menaje)?.nombre}{p.activo ? '' : ' (fuera de venta)'}</option>)}
            </select></label>
          </div>
          {!catalogo.presentaciones.length && <p role="status">No hay presentaciones pendientes. Crea una en Carta → Presentaciones de venta. Las presentaciones que ya tienen receta se configuran desde Editar.</p>}
        </>}
        <p className="recipe-editor__hint">Los datos del artículo se editan en Carta → Presentaciones de venta.</p>
        <ListaIngredientes titulo="Productos de inventario" filas={productosSeleccionados} productos={catalogo.productos}
          unidades={catalogo.unidades_medida}
          cambiar={cambiarProductos} bloquearAgregar={form.tipo_item === 'DIRECTO' && componentesActivos.length >= 1} disabled={guardando} />
        <section className="recipe-editor__subproducts">
          <label className="recipe-editor__check"><input type="checkbox" checked={usaSubproductos}
            onChange={(e) => setUsaSubproductos(e.target.checked)} />Agregar subproductos</label>
          {usaSubproductos && <>
            <p className="recipe-editor__hint">Agrega preparaciones internas ya registradas, con la cantidad que utiliza esta receta.
              Al desmarcar esta casilla, los subproductos no se incluirán al guardar.</p>
            <ListaIngredientes titulo="Subproductos de la preparación" tipo="SUBPRODUCTO" filas={subproductosSeleccionados}
              unidades={catalogo.unidades_medida}
              productos={catalogo.subproductos} cambiar={cambiarSubproductos}
              bloquearAgregar={form.tipo_item === 'DIRECTO' && componentesActivos.length >= 1} disabled={guardando} />
          </>}
          {!usaSubproductos && subproductosSeleccionados.length > 0 && <p className="recipe-editor__hint">
            Hay {subproductosSeleccionados.length} subproducto(s) excluido(s). Marca la casilla para volver a incluirlos antes de guardar.
          </p>}
        </section>
        {form.tipo_item === 'DIRECTO' && <p className="recipe-editor__hint">Un ítem directo utiliza un solo producto o subproducto. Quita el actual antes de elegir otro.</p>}
        <label>Instrucciones de preparación<textarea required rows={3} value={form.instrucciones} onChange={(e) => setForm({ ...form, instrucciones: e.target.value })} /></label>
        <section className="recipe-editor__sauces">
          <label className="recipe-editor__check"><input type="checkbox" checked={usaOpciones} onChange={(e) => setUsaOpciones(e.target.checked)} />Agregar productos elegibles / opciones de salsa</label>
          {usaOpciones && <>
            <div className="recipe-editor__grid"><label>Cuántas opciones puede escoger<input type="number" required min="1" max="32767" step="1" value={maximo} onChange={(e) => setMaximo(e.target.value)} /></label><label className="recipe-editor__check"><input type="checkbox" checked={repetir} onChange={(e) => setRepetir(e.target.checked)} />Permitir repetir opciones</label></div>
            <ListaIngredientes titulo="Opciones disponibles" filas={opciones} productos={catalogo.productos} cambiar={setOpciones} disabled={guardando} unidades={catalogo.unidades_medida} />
          </>}
        </section>
      </fieldset>}
      <footer><button type="button" disabled={guardando} onClick={cerrar}>Cancelar</button><button type="submit" disabled={guardando || !catalogo || !form.id_presentacion_venta}>{guardando ? 'Guardando…' : 'Guardar receta'}</button></footer>
    </form>
  </div>
}
