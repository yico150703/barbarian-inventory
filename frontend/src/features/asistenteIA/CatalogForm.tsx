import { useState, type FormEvent } from 'react'
import { ClipboardList, RefreshCw, Plus } from 'lucide-react'
import type { FormularioCatalogo, RecursoFormulario } from './service'
import './CatalogForm.css'

interface Props {
  form: FormularioCatalogo
  disabled: boolean
  onChange: () => void
  onReview: (datos: Record<string, unknown>) => void
  initialValues?: FormValues
  onDependency: (resource: RecursoFormulario, values: FormValues, seed?: FormValues) => void
}
export type FormValues = { nombre?: string; prefijo?: string; categorias?: number[]; proveedor?: string; categoria?: string; unidad?: string; contenido?: string; item?: string; tipo?: string; menaje?: string; precio?: string }

export function CatalogForm({ form, disabled, onChange, onReview, initialValues = {}, onDependency }: Props) {
  const [nombre, setNombre] = useState(initialValues.nombre ?? '')
  const [prefijo, setPrefijo] = useState(initialValues.prefijo ?? '')
  const [categorias, setCategorias] = useState<number[]>(initialValues.categorias ?? [])
  const [proveedor, setProveedor] = useState(initialValues.proveedor ?? '')
  const [categoria, setCategoria] = useState(initialValues.categoria ?? '')
  const [unidad, setUnidad] = useState(initialValues.unidad ?? '')
  const [contenido, setContenido] = useState(initialValues.contenido ?? '')
  const [item, setItem] = useState(initialValues.item ?? '')
  const [tipo, setTipo] = useState(initialValues.tipo ?? '')
  const [menaje, setMenaje] = useState(initialValues.menaje ?? '')
  const [precio, setPrecio] = useState(initialValues.precio ?? '')
  const categoryForm = form.recurso === 'categorias_productos' || form.recurso === 'categorias_carta'
  const supplierForm = form.recurso === 'proveedores'
  const presentationForm = form.recurso === 'presentaciones'
  const productForm = form.recurso === 'productos'
  const tablewareForm = form.recurso === 'menajes'
  const maxPrefix = form.recurso === 'categorias_carta' ? 5 : 3
  const activeCategories = form.categorias.filter(c => c.activo)
  const availableSuppliers = form.proveedores.filter(p => p.activo && p.ids_categorias.includes(Number(categoria)))
  const symbol = form.unidades_medida.find(u => u.codigo === unidad)?.simbolo ?? ''
  const duplicate = categoryForm && form.categorias.some(c => c.nombre.trim().toLocaleLowerCase() === nombre.trim().toLocaleLowerCase() || (prefijo && c.prefijo.toUpperCase() === prefijo.toUpperCase()))
  const values = { nombre, prefijo, categorias, proveedor, categoria, unidad, contenido, item, tipo, menaje, precio }
  function dependency(resource: RecursoFormulario, label: string, seed?: FormValues) {
    return form.dependencias_creables?.includes(resource) ? <button type="button" className="assistant-dependency-link" onClick={() => onDependency(resource, values, seed)}><Plus size={14} />{label}</button> : null
  }

  function submit(e: FormEvent) {
    e.preventDefault()
    if (duplicate || disabled) return
    onReview(categoryForm ? { nombre: nombre.trim(), prefijo } : tablewareForm ? { nombre: nombre.trim() } : presentationForm ? {
      id_item_carta: item ? Number(item) : null, nombre_item: nombre.trim(), tipo_item: tipo,
      id_categoria_carta: Number(categoria), id_menaje: Number(menaje), contenido: Number(contenido), unidad, precio: Number(precio), activo: true,
    } : supplierForm ?
      { nombre: nombre.trim(), ids_categorias: categorias } :
      { nombre: nombre.trim(), id_proveedor: Number(proveedor), id_categoria: Number(categoria), unidad, presentacion: Number(contenido) })
  }

  return <form className="assistant-catalog-form" onSubmit={submit}>
    <header><span className="assistant-catalog-icon"><ClipboardList size={20} /></span><div><h3>{form.titulo}</h3><p>Completa los datos. El siguiente paso es revisar la propuesta.</p></div></header>
    <fieldset disabled={disabled} onChange={onChange}>
      {presentationForm && <label>Artículo de carta<select value={item} onChange={e => { const next = form.items.find(i => i.id_item_carta === Number(e.target.value)); setItem(e.target.value); setNombre(next?.nombre ?? ''); setTipo(next?.tipo ?? ''); setCategoria(next ? String(next.id_categoria_carta) : '') }}><option value="">Crear artículo nuevo</option>{form.items.filter(i => i.activo).map(i => <option key={i.id_item_carta} value={i.id_item_carta}>{i.nombre}</option>)}</select></label>}
      <label>{presentationForm ? 'Nombre del artículo' : 'Nombre'}<input autoFocus required readOnly={presentationForm && Boolean(item)} maxLength={presentationForm ? 200 : 100} value={nombre} onChange={e => setNombre(e.target.value)} placeholder={categoryForm ? 'Nombre de la categoría' : supplierForm ? 'Nombre del proveedor' : 'Nombre'} /></label>
      {categoryForm && <>
        <label>Prefijo<input required maxLength={maxPrefix} pattern={`[A-Za-z]{1,${maxPrefix}}`} value={prefijo} onChange={e => setPrefijo(e.target.value.toUpperCase())} placeholder="Ej. BEB" /><small>De 1 a {maxPrefix} letras. No debe repetirse.</small></label>
        <label>Categorías existentes<select defaultValue="" aria-label="Consultar categorías existentes"><option value="">Ver categorías y prefijos registrados</option>{form.categorias.map(c => <option key={c.id_categoria} value={c.id_categoria}>{c.nombre} · {c.prefijo}{c.activo ? '' : ' (inactiva)'}</option>)}</select></label>
        {duplicate && <p className="assistant-error" role="alert">El nombre o prefijo ya está registrado.</p>}
      </>}
      {supplierForm && <div className="assistant-catalog-categories"><span>¿Qué categorías abastece?</span><small>Selecciona una o varias categorías existentes.</small>
        {dependency('categorias_productos', 'No está mi categoría: crear una')}
        {activeCategories.length ? <div>{activeCategories.map(c => <label key={c.id_categoria}><input type="checkbox" checked={categorias.includes(c.id_categoria)} onChange={e => setCategorias(current => e.target.checked ? [...current, c.id_categoria] : current.filter(id => id !== c.id_categoria))} />{c.nombre}<small>{c.prefijo}</small></label>)}</div> : <p>No hay categorías activas. Crea una categoría y luego vuelve a este formulario.</p>}
      </div>}
      {productForm && <>
        <label>1. Categoría del producto<select required value={categoria} onChange={e => { setCategoria(e.target.value); setProveedor('') }}><option value="">Selecciona una categoría existente</option>{activeCategories.map(c => <option key={c.id_categoria} value={c.id_categoria}>{c.nombre} · {c.prefijo}</option>)}</select></label>
        {dependency('categorias_productos', 'No está mi categoría: crear una')}
        <label>2. Proveedor<select required disabled={!categoria} value={proveedor} onChange={e => setProveedor(e.target.value)}><option value="">Selecciona un proveedor de esta categoría</option>{availableSuppliers.map(p => <option key={p.id_proveedor} value={p.id_proveedor}>{p.nombre}</option>)}</select><small>{categoria && !availableSuppliers.length ? 'No hay proveedores activos para esta categoría. Puedes crear uno a continuación.' : 'Solo se muestran proveedores que abastecen la categoría seleccionada.'}</small></label>
        {dependency('proveedores', 'No está mi proveedor: crear uno', { categorias: categoria ? [Number(categoria)] : [] })}
        <div className="assistant-catalog-columns"><label>Unidad base<select required value={unidad} onChange={e => setUnidad(e.target.value)}><option value="">Selecciona una unidad</option>{form.unidades_medida.filter(u => ['KGM', 'LTR', 'C62'].includes(u.codigo)).map(u => <option key={u.codigo} value={u.codigo}>{u.nombre} ({u.simbolo})</option>)}</select></label>
          <label>Contenido por presentación{symbol ? ` (${symbol})` : ''}<input required type="number" min="0.001" max="999999999.999" step="0.001" value={contenido} onChange={e => setContenido(e.target.value)} placeholder="Ej. 1" /></label></div>
        <p className="assistant-note">Indica el contenido de una presentación de compra en la unidad elegida. El código del producto se genera automáticamente.</p>
      </>}
      {presentationForm && <>
        <label>1. Categoría de carta<select required disabled={Boolean(item)} value={categoria} onChange={e => setCategoria(e.target.value)}><option value="">Selecciona una categoría existente</option>{activeCategories.map(c => <option key={c.id_categoria} value={c.id_categoria}>{c.nombre}</option>)}</select></label>
        {!item && dependency('categorias_carta', 'No está mi categoría de carta: crear una')}
        <label>2. Menaje<select required value={menaje} onChange={e => setMenaje(e.target.value)}><option value="">Selecciona el menaje</option>{form.menajes.filter(m => m.activo).map(m => <option key={m.id_menaje} value={m.id_menaje}>{m.nombre}</option>)}</select></label>
        {dependency('menajes', 'No está mi menaje: crear uno')}
        <label>Tipo de artículo<select required disabled={Boolean(item)} value={tipo} onChange={e => setTipo(e.target.value)}><option value="">Selecciona</option>{form.tipos.map(t => <option key={t} value={t}>{t === 'DIRECTO' ? 'Directo' : 'Preparado'}</option>)}</select></label>
        <div className="assistant-catalog-columns"><label>Unidad<select required value={unidad} onChange={e => setUnidad(e.target.value)}><option value="">Selecciona</option>{form.unidades_medida.filter(u => ['KGM', 'LTR', 'C62', 'PORCION'].includes(u.codigo)).map(u => <option key={u.codigo} value={u.codigo}>{u.nombre} ({u.simbolo})</option>)}</select></label>
        <label>Contenido{symbol ? ` (${symbol})` : ''}<input required type="number" min="0.001" max="999999999.999" step="0.001" value={contenido} onChange={e => setContenido(e.target.value)} /></label></div>
        <label>Precio de venta (S/)<input required type="number" min="0" max="99999999.99" step="0.01" value={precio} onChange={e => setPrecio(e.target.value)} /></label>
        <p className="assistant-note">Se creará una presentación activa. La receta se define después de guardar esta presentación.</p>
      </>}
    </fieldset>
    <footer><button type="button" className="assistant-secondary" onClick={() => onDependency(form.recurso, values)} disabled={disabled}><RefreshCw size={15} />Actualizar opciones</button><button type="submit" disabled={disabled || duplicate || (supplierForm && !categorias.length)}>Revisar propuesta</button></footer>
    <small>Los datos se guardan únicamente después de confirmar con Realizar.</small>
  </form>
}
