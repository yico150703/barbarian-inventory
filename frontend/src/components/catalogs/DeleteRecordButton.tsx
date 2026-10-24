import { useState } from 'react'
import { CatalogDialog } from './CatalogDialog'

export function DeleteRecordButton({ token, entidad, id, nombre, eliminado }: {
  token: string | null; entidad: string; id: number; nombre: string; eliminado: () => void
}) {
  const [abierto, setAbierto] = useState(false)
  const [ocupado, setOcupado] = useState(false)
  const [error, setError] = useState('')
  async function guardar() {
    if (!token || ocupado) return
    setOcupado(true); setError('')
    try {
      const respuesta = await fetch(`${import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:5000/api'}/eliminaciones/${entidad}/${id}`, {
        method: 'DELETE', headers: { Authorization: `Bearer ${token}` },
      })
      const datos = await respuesta.json()
      if (!respuesta.ok) throw new Error(datos.mensaje ?? 'No se pudo eliminar')
      setAbierto(false); eliminado()
    } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo eliminar') }
    finally { setOcupado(false) }
  }
  return <>
    <button type="button" className="delete-record-button danger" onClick={() => { setError(''); setAbierto(true) }}>Eliminar</button>
    <CatalogDialog abierto={abierto} titulo="Eliminar registro" textoGuardar="Eliminar definitivamente" procesando={ocupado} cerrar={() => setAbierto(false)} guardar={guardar}>
      <p>¿Eliminar <strong>{nombre}</strong> definitivamente?</p>
      <p>Se quitará su configuración propia. Si está asociado a otros registros, el sistema bloqueará la eliminación.</p>
      {error && <p role="alert">{error}</p>}
    </CatalogDialog>
  </>
}
