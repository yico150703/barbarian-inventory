import { useEffect, useRef, useState, type FormEvent } from 'react'
import { X } from 'lucide-react'
import { ListaIngredientes, type Fila } from './RecipeEditor'
import { guardarSubproducto, obtenerFormularioSubproducto } from '../../services/productionService'
import type { FormularioSubproducto, SubproductoDetalle } from '../../types/production'
import './SubproductEditor.css'
import { etiquetaUnidad, convertirCantidadVisible } from '../../utils/unitHelpers'

export function SubproductEditor({ token, subproducto, cerrar, guardado }: {
  token: string
  subproducto: SubproductoDetalle | null
  cerrar: () => void
  guardado: (mensaje: string) => void
}) {
  const dialog = useRef<HTMLDialogElement>(null)
  const [catalogo, setCatalogo] = useState<FormularioSubproducto | null>(null)
  const [error, setError] = useState('')
  const [guardando, setGuardando] = useState(false)
  const [reintento, setReintento] = useState(0)
  const [form, setForm] = useState({
    nombre: subproducto?.nombre ?? '', rendimiento: String(subproducto?.rendimiento ?? 1),
    unidad: subproducto?.unidad ?? '', instruccion: subproducto?.instruccion ?? '',
    activo: subproducto?.activo ?? true,
  })
  const [ingredientes, setIngredientes] = useState<Fila[]>(() => (subproducto?.ingredientes ?? []).map((p) => ({
    tipo_componente: 'PRODUCTO', id: p.id_producto, codigo: p.codigo, nombre: p.producto,
    cantidad: String(p.cantidad), unidad: p.unidad,
  })))

  useEffect(() => {
    const modal = dialog.current
    modal?.showModal()
    return () => modal?.close()
  }, [])

  useEffect(() => {
    let vigente = true
    setError('')
    obtenerFormularioSubproducto(token).then((datos) => { if (vigente) setCatalogo(datos) })
      .catch((e: unknown) => { if (vigente) setError(e instanceof Error ? e.message : 'No se pudo cargar el formulario.') })
    return () => { vigente = false }
  }, [token, reintento])

  async function guardar(evento: FormEvent) {
    evento.preventDefault()
    if (guardando || !catalogo) return
    if (!ingredientes.length) { setError('Agrega al menos un ingrediente.'); return }
    setGuardando(true)
    setError('')
    try {
      const respuesta = await guardarSubproducto(token, {
        ...form, ingredientes: ingredientes.map(({ id, cantidad, unidad_cantidad }) => ({ id, cantidad, unidad_cantidad, tipo_componente: 'PRODUCTO' })),
      }, subproducto?.id_subproducto)
      guardado(respuesta.mensaje)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudo guardar el subproducto.')
    } finally {
      setGuardando(false)
    }
  }

  return <dialog ref={dialog} className="subproduct-dialog" aria-labelledby="subproduct-editor-title"
    onCancel={(e) => { e.preventDefault(); if (!guardando) cerrar() }}>
    <form className="recipe-editor" onSubmit={(e) => void guardar(e)}>
      <header>
        <div><h2 id="subproduct-editor-title">{subproducto ? 'Editar subproducto' : 'Nuevo subproducto'}</h2>
          <p>{subproducto ? `Código: ${subproducto.codigo}` : 'El código se genera al guardar.'} Preparación compartida por todas las tiendas.</p></div>
        <button type="button" aria-label="Cerrar editor" disabled={guardando} onClick={cerrar}><X /></button>
      </header>
      {!catalogo && !error && <p role="status">Cargando productos y unidades…</p>}
      {error && <p role="alert" className="recipe-editor__error">{error}</p>}
      {!catalogo && error && <button type="button" onClick={() => setReintento((n) => n + 1)}>Reintentar</button>}
      <fieldset disabled={!catalogo || guardando}>
        <label>Nombre del subproducto
          <input required maxLength={150} value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} />
        </label>
        <div className="recipe-editor__grid">
          <label>Unidad del rendimiento
            <select required disabled={!!subproducto} value={form.unidad} onChange={(e) => setForm({ ...form, unidad: e.target.value,
              rendimiento: convertirCantidadVisible(form.rendimiento, form.unidad, e.target.value, catalogo?.unidades_medida ?? []),
            })}>
              <option value="">Selecciona una unidad</option>
              {(catalogo?.unidades ?? (subproducto ? [subproducto.unidad] : [])).map((u) => <option key={u} value={u}>{etiquetaUnidad(catalogo?.unidades_medida ?? [], u)}</option>)}
            </select>
          </label>
          <label>Cantidad obtenida
            <input required type="number" min="0.001" max="999999999.999" step="0.001" value={form.rendimiento}
              onChange={(e) => setForm({ ...form, rendimiento: e.target.value })} />
          </label>
          <label>Estado<select value={form.activo ? 'activo' : 'inactivo'} onChange={(e) => setForm({ ...form, activo: e.target.value === 'activo' })}>
            <option value="activo">Activo</option><option value="inactivo">Inactivo</option>
          </select></label>
        </div>
        <p className="recipe-editor__hint">Indica cuánto se obtiene usando todas las cantidades de ingredientes de abajo.
          {subproducto && ' La unidad se conserva para no alterar las recetas que usan este subproducto.'}</p>
        <ListaIngredientes titulo="Ingredientes del subproducto" filas={ingredientes} productos={catalogo?.productos ?? []}
          unidades={catalogo?.unidades_medida}
          cambiar={setIngredientes} disabled={guardando || !catalogo} />
        <label>Instrucciones de preparación
          <textarea rows={4} value={form.instruccion} onChange={(e) => setForm({ ...form, instruccion: e.target.value })} />
        </label>
      </fieldset>
      <footer><button type="button" disabled={guardando} onClick={cerrar}>Cancelar</button>
        <button type="submit" disabled={guardando || !catalogo}>{guardando ? 'Guardando…' : 'Guardar subproducto'}</button></footer>
    </form>
  </dialog>
}
