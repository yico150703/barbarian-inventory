import { useEffect, useRef, useState } from 'react'
import { ArrowLeft, ChevronRight, CheckCheck } from 'lucide-react'
import { CatalogForm, type FormValues } from './CatalogForm'
import { ReviewDetails } from './ReviewDetails'
import { solicitar, type FormularioCatalogo, type RecursoFormulario, type RespuestaAsistente } from './service'

type Frame = { form: FormularioCatalogo; values: FormValues; version: number }
type Created = { mensaje: string; id_categoria?: number; id_proveedor?: number; id_categoria_carta?: number; id_menaje?: number }
interface Props {
  token: string
  form: FormularioCatalogo
  disabled: boolean
  onChange: () => void
  onReview: (data: Record<string, unknown>) => void
  onInvalidate: () => Promise<void>
  onNestedChange: (nested: boolean) => void
  onBusy: (busy: boolean) => void
  onSaved: (message: string) => void
}

export function CatalogWorkflow({ token, form, disabled, onChange, onReview, onInvalidate, onNestedChange, onBusy, onSaved }: Props) {
  const [frames, setFrames] = useState<Frame[]>([{ form, values: {}, version: 0 }])
  const [proposal, setProposal] = useState<RespuestaAsistente | null>(null)
  const [checked, setChecked] = useState(false)
  const [dirty, setDirty] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [saved, setSaved] = useState<Created | null>(null)
  const controller = useRef<AbortController | null>(null)
  const alive = useRef(true)
  const current = frames[frames.length - 1]
  const nested = frames.length > 1

  useEffect(() => {
    alive.current = true
    return () => { alive.current = false; controller.current?.abort() }
  }, [])

  async function work(task: (signal: AbortSignal) => Promise<void>) {
    if (controller.current || disabled) return
    const control = new AbortController(); controller.current = control
    setBusy(true); onBusy(true); setError('')
    try { await task(control.signal) }
    catch (e) { if (alive.current) setError(e instanceof Error ? e.message : 'No se pudo completar el paso.') }
    finally { controller.current = null; if (alive.current) { setBusy(false); onBusy(false) } }
  }

  async function load(resource: RecursoFormulario, signal: AbortSignal) {
    const result = await solicitar<{ formulario: FormularioCatalogo }>(token, 'formulario', { recurso: resource }, signal)
    return result.formulario
  }

  async function cancelProposal(signal: AbortSignal) {
    if (proposal?.borrador) await solicitar(token, 'cancelar', { id: proposal.borrador.id_borrador }, signal)
  }

  function open(resource: RecursoFormulario, values: FormValues, seed: FormValues = {}) {
    void work(async signal => {
      if (resource !== current.form.recurso && !current.form.dependencias_creables.includes(resource)) throw Error('Este paso no depende de ese formulario.')
      const options = await load(resource, signal)
      await cancelProposal(signal); await onInvalidate()
      if (!alive.current) return
      const parent = { ...current, values, version: current.version + 1 }
      setFrames(resource === current.form.recurso ? [...frames.slice(0, -1), { ...parent, form: options }] :
        [...frames.slice(0, -1), parent, { form: options, values: seed, version: 0 }])
      setProposal(null); setChecked(false); setSaved(null)
      if (resource !== current.form.recurso) onNestedChange(true)
    })
  }

  function back() {
    void work(async signal => {
      await cancelProposal(signal); await onInvalidate()
      if (!alive.current) return
      setFrames(frames.slice(0, -1)); setProposal(null); setChecked(false); setSaved(null)
      onNestedChange(frames.length > 2)
    })
  }

  function review(data: Record<string, unknown>) {
    if (!nested) { onReview(data); return }
    void work(async signal => {
      const result = await solicitar<RespuestaAsistente>(token, 'formulario/preparar', {
        recurso: current.form.recurso, datos: data, reemplaza: proposal?.borrador?.id_borrador,
      }, signal)
      if (alive.current) { setProposal(result); setDirty(false); setChecked(false) }
    })
  }

  async function resume(result: Created, signal: AbortSignal) {
    const parent = frames[frames.length - 2]
    const options = await load(parent.form.recurso, signal)
    const values = { ...parent.values }
    if (current.form.recurso === 'categorias_productos' && result.id_categoria) {
      if (parent.form.recurso === 'proveedores') values.categorias = [...new Set([...(values.categorias ?? []), result.id_categoria])]
      else { values.categoria = String(result.id_categoria); values.proveedor = '' }
    } else if (current.form.recurso === 'proveedores' && result.id_proveedor) {
      const supplier = options.proveedores.find(p => p.id_proveedor === result.id_proveedor)
      if (supplier?.ids_categorias.includes(Number(values.categoria))) values.proveedor = String(result.id_proveedor)
      else if (supplier?.ids_categorias.length === 1) { values.categoria = String(supplier.ids_categorias[0]); values.proveedor = String(result.id_proveedor) }
      else { values.categoria = ''; values.proveedor = '' }
    } else if (current.form.recurso === 'categorias_carta' && result.id_categoria_carta) values.categoria = String(result.id_categoria_carta)
    else if (current.form.recurso === 'menajes' && result.id_menaje) values.menaje = String(result.id_menaje)
    if (!alive.current) return
    setFrames([...frames.slice(0, -2), { form: options, values, version: parent.version + 1 }])
    setSaved(null); setProposal(null); setChecked(false); setDirty(false)
    onNestedChange(frames.length > 2); onChange(); onSaved(result.mensaje + ' Continúa con ' + parent.form.titulo.toLocaleLowerCase() + '.')
  }

  function execute() {
    if (!proposal?.borrador || !checked || dirty || saved) return
    void work(async signal => {
      const result = await solicitar<Created>(token, 'realizar', { id: proposal.borrador!.id_borrador, confirmar: true }, signal)
      if (!alive.current) return
      // Si actualizar las opciones falla, solo se reintenta retomar, nunca la creación.
      setSaved(result); setProposal(null); setChecked(false)
      await resume(result, signal)
    })
  }

  return <div className="assistant-catalog-workflow">
    <nav className="assistant-workflow-path" aria-label="Pasos del formulario">{frames.map((frame, i) => <span key={i}>{i > 0 && <ChevronRight size={14} />}<b aria-current={i === frames.length - 1 ? 'step' : undefined}>{frame.form.titulo}</b></span>)}</nav>
    {nested && <div className="assistant-workflow-intro"><p>Primero completa este requisito. Conservamos los datos del paso anterior.</p><button className="assistant-secondary" disabled={busy || disabled} onClick={back}><ArrowLeft size={14} />Volver{saved ? '' : ' sin crear'}</button></div>}
    {error && <p className="assistant-error" role="alert">{error}</p>}
    {saved ? <div className="assistant-workflow-saved" role="status"><CheckCheck size={20} /><p>{saved.mensaje} La creación ya se realizó.</p><button disabled={busy || disabled} onClick={() => void work(signal => resume(saved, signal))}>Retomar paso anterior</button></div> : <>
      <CatalogForm key={`${frames.length}-${current.version}`} form={current.form} initialValues={current.values} disabled={busy || disabled}
        onChange={() => { setDirty(true); setChecked(false); onChange() }} onReview={review} onDependency={open} />
      {nested && proposal?.borrador && <section className="assistant-proposal assistant-workflow-review"><header><h3>Revisa este requisito</h3></header><ReviewDetails value={proposal.borrador.vista} />
        <label className="assistant-confirm"><input type="checkbox" checked={checked} disabled={busy || disabled || dirty} onChange={e => setChecked(e.target.checked)} />Revisé los datos que se guardarán.</label>
        {dirty && <p className="assistant-note">Revisa nuevamente la propuesta con los datos corregidos.</p>}
        <button disabled={busy || disabled || !checked || dirty} onClick={execute}>Realizar y continuar</button>
      </section>}
    </>}
  </div>
}
