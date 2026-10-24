import { useEffect, useState } from 'react'
import { CatalogDialog } from './CatalogDialog'
import { formularioPresentacion, guardarPresentacion, type FormularioPresentacion } from '../../services/cartaService'
import type { PresentacionVenta } from '../../types/carta'
import { etiquetaUnidad, convertirCantidadVisible } from '../../utils/unitHelpers'

export function PresentationEditor({ token, presentacion: p, cerrar, guardado }: {
  token: string; presentacion: PresentacionVenta | null; cerrar: () => void; guardado: (mensaje: string) => void
}) {
  const [catalogo, setCatalogo] = useState<FormularioPresentacion | null>(null)
  const [error, setError] = useState('')
  const [ocupado, setOcupado] = useState(false)
  const [nuevo, setNuevo] = useState(false)
  const [busqueda, setBusqueda] = useState('')
  const [form, setForm] = useState({ id_item_carta: p?.id_item_carta ?? 0, nombre_item: p?.item ?? '',
    id_categoria_carta: p?.id_categoria_carta ?? 0, tipo_item: p?.tipo ?? 'PREPARADO',
    contenido: String(p?.contenido ?? 1), unidad: p?.unidad ?? '', id_menaje: p?.id_menaje ?? 0,
    precio: String(p?.precio ?? 0), activo: p?.activo ?? false })
  useEffect(() => {
    let vigente = true
    formularioPresentacion(token).then(c => { if (vigente) setCatalogo(c) })
      .catch(e => { if (vigente) setError(e instanceof Error ? e.message : 'No se pudo cargar el formulario') })
    return () => { vigente = false }
  }, [token])
  async function guardar() {
    if (!catalogo || ocupado) return
    setOcupado(true); setError('')
    try {
      const resultado = await guardarPresentacion(token, { ...form, id_item_carta: nuevo ? null : form.id_item_carta }, p?.id_presentacion_venta)
      guardado(resultado.mensaje)
    } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo guardar') }
    finally { setOcupado(false) }
  }
  return <CatalogDialog abierto titulo={p ? 'Editar presentación de carta' : 'Nueva presentación de carta'} procesando={ocupado || !catalogo} cerrar={cerrar} guardar={guardar}>
    {error && <p role="alert">{error}</p>}
    {!catalogo ? <p>Cargando catálogo… <button type="button" onClick={cerrar}>Cerrar</button></p> : <fieldset disabled={ocupado} style={{ border: 0, padding: 0, display: 'grid', gap: 14 }}>
      {!p && <>
        <label>Artículo<select value={nuevo ? 'nuevo' : 'existente'} onChange={e => { setNuevo(e.target.value === 'nuevo'); setForm({ ...form, id_item_carta: 0, nombre_item: '', id_categoria_carta: 0 }) }}><option value="existente">Seleccionar artículo existente</option><option value="nuevo">Crear nuevo artículo</option></select></label>
        {!nuevo && <>
          <label>Buscar por nombre o código<input type="search" value={busqueda} onChange={e => setBusqueda(e.target.value)} /></label>
          <label>Artículo existente<select required value={form.id_item_carta || ''} onChange={e => {
            const item = catalogo.items.find(i => i.id_item_carta === Number(e.target.value))
            setForm({ ...form, id_item_carta: item?.id_item_carta ?? 0, nombre_item: item?.nombre ?? '', tipo_item: item?.tipo ?? 'PREPARADO', id_categoria_carta: item?.id_categoria_carta ?? 0 })
          }}><option value="">Seleccionar</option>{catalogo.items.filter(i => i.activo && (i.id_item_carta === form.id_item_carta || `${i.codigo} ${i.nombre}`.toLowerCase().includes(busqueda.toLowerCase()))).map(i => <option key={i.id_item_carta} value={i.id_item_carta}>{i.codigo} · {i.nombre}</option>)}</select></label>
        </>}
      </>}
      <label>Nombre del artículo<input required maxLength={200} readOnly={!p && !nuevo} value={form.nombre_item} onChange={e => setForm({ ...form, nombre_item: e.target.value })} /></label>
      <label>Categoría<select required disabled={!p && !nuevo} value={form.id_categoria_carta || ''} onChange={e => setForm({ ...form, id_categoria_carta: Number(e.target.value) })}><option value="">Seleccionar</option>{catalogo.categorias.filter(c => c.activo || c.id_categoria_carta === form.id_categoria_carta).map(c => <option key={c.id_categoria_carta} value={c.id_categoria_carta}>{c.nombre}</option>)}</select></label>
      <label>Tipo<select disabled={!p && !nuevo} value={form.tipo_item} onChange={e => setForm({ ...form, tipo_item: e.target.value })}>{catalogo.tipos.map(t => <option key={t}>{t}</option>)}</select></label>
      {p && <p>El nombre, la categoría y el tipo se comparten entre todas las presentaciones de este artículo. Cambiar la categoría conserva su código.</p>}
      <label>Contenido<input required type="number" min="0.001" max="999999999.999" step="0.001" value={form.contenido} onChange={e => setForm({ ...form, contenido: e.target.value })} /></label>
      <label>Unidad<select required value={form.unidad} onChange={e => setForm({ ...form, unidad: e.target.value,
        contenido: convertirCantidadVisible(form.contenido, form.unidad, e.target.value, catalogo.unidades_medida),
      })}><option value="">Seleccionar</option>{catalogo.unidades.map(u => <option key={u} value={u}>{etiquetaUnidad(catalogo.unidades_medida, u)}</option>)}</select></label>
      <p>Los gramos y mililitros se convierten a kg y L al guardar. El tamaño de una porción lo define esta presentación.</p>
      <label>Menaje<select required value={form.id_menaje || ''} onChange={e => setForm({ ...form, id_menaje: Number(e.target.value) })}><option value="">Seleccionar</option>{catalogo.menajes.filter(m => m.activo || m.id_menaje === p?.id_menaje).map(m => <option key={m.id_menaje} value={m.id_menaje}>{m.nombre}</option>)}</select></label>
      <label>Precio (S/)<input required type="number" min="0" max="99999999.99" step="0.01" value={form.precio} onChange={e => setForm({ ...form, precio: e.target.value })} /></label>
      <label>Estado de venta<select value={form.activo ? 'activo' : 'inactivo'} onChange={e => setForm({ ...form, activo: e.target.value === 'activo' })}><option value="inactivo">Inactiva</option><option value="activo">Activa</option></select></label>
      <p>Después, configura los ingredientes en Recetas. Cambiar el estado de venta no cambia el estado de la receta.</p>
      {p && <p>Si cambias el contenido o la unidad, revisa las cantidades de su receta: no se recalculan automáticamente.</p>}
    </fieldset>}
  </CatalogDialog>
}
