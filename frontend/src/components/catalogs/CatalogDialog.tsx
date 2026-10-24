import type { FormEvent, ReactNode } from 'react'
import './CatalogDialog.css'

interface Props {
  titulo: string
  abierto: boolean
  procesando?: boolean
  children: ReactNode
  guardar: () => void | Promise<void>
  cerrar: () => void
  textoGuardar?: string
}

export function CatalogDialog({
  titulo, abierto, procesando = false, children, guardar, cerrar, textoGuardar = 'Guardar',
}: Props) {
  if (!abierto) return null

  function enviar(evento: FormEvent) {
    evento.preventDefault()
    void guardar()
  }

  return (
    <div className="catalog-dialog-backdrop" role="presentation">
      <form className="catalog-dialog" onSubmit={enviar}>
        <h2>{titulo}</h2>
        <div className="catalog-dialog__body">{children}</div>
        <footer>
          <button type="button" onClick={cerrar} disabled={procesando}>Cancelar</button>
          <button className="primary" type="submit" disabled={procesando}>
            {procesando ? 'Procesando...' : textoGuardar}
          </button>
        </footer>
      </form>
    </div>
  )
}
