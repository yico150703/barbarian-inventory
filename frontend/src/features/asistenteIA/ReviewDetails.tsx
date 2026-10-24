import { etiqueta } from './labels'
import { revisionVisible } from './reviewDisplay'

export function ReviewDetails({ value }: { value: unknown }) {
  return <Details value={revisionVisible(value)} />
}

function Details({ value }: { value: unknown }) {
  if (value === null || value === undefined) return <span>Sin asignar</span>
  if (typeof value === 'boolean') return <span>{value ? 'Sí' : 'No'}</span>
  if (Array.isArray(value)) return <ul className="assistant-values">{value.map((v, i) => <li key={i}><Details value={v} /></li>)}</ul>
  if (typeof value === 'object') return <dl className="assistant-fields">{Object.entries(value).map(([key, v]) =>
    <div key={key}><dt>{etiqueta(key)}</dt><dd><Details value={v} /></dd></div>)}</dl>
  return <span>{String(value)}</span>
}
