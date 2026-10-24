import { useState } from 'react'

import type {
  PerfilDisponible,
  PuestoDisponible,
} from '../../types/auth'
import './ProfileSelectionDialog.css'

interface Props {
  abierto: boolean
  perfiles: PerfilDisponible[]
  puestos: PuestoDisponible[]
  procesando: boolean
  error: string
  seleccionar: (idPerfil: number, idPuesto?: number) => void
  cancelar: () => void
}

const ID_MIEMBRO = 4

export function ProfileSelectionDialog({
  abierto,
  perfiles,
  puestos,
  procesando,
  error,
  seleccionar,
  cancelar,
}: Props) {
  const [idPerfil, setIdPerfil] = useState<number | null>(null)
  const [idPuesto, setIdPuesto] = useState<number | null>(null)

  if (!abierto) return null

  const requierePuesto = idPerfil === ID_MIEMBRO
  const puedeContinuar =
    idPerfil !== null && (!requierePuesto || idPuesto !== null)

  return (
    <div className="profile-dialog-backdrop">
      <section className="profile-dialog" role="dialog" aria-modal="true">
        <h2>¿Con qué perfil trabajarás?</h2>
        <p>El menú y los permisos cambiarán según tu selección.</p>

        <div className="profile-dialog__options">
          {perfiles.map((perfil) => (
            <button
              key={perfil.id_perfil}
              type="button"
              className={idPerfil === perfil.id_perfil ? 'is-active' : ''}
              onClick={() => {
                setIdPerfil(perfil.id_perfil)
                if (perfil.id_perfil !== ID_MIEMBRO) setIdPuesto(null)
              }}
            >
              <strong>{perfil.nombre}</strong>
              <span>{perfil.descripcion}</span>
            </button>
          ))}
        </div>

        {requierePuesto && (
          <label className="profile-dialog__puesto">
            Puesto laboral
            <select
              value={idPuesto ?? ''}
              onChange={(e) => setIdPuesto(Number(e.target.value) || null)}
            >
              <option value="">Selecciona un puesto</option>
              {puestos.map((puesto) => (
                <option
                  key={puesto.id_puesto_laboral}
                  value={puesto.id_puesto_laboral}
                >
                  {puesto.nombre}
                </option>
              ))}
            </select>
          </label>
        )}

        {error && <p className="profile-dialog__error">{error}</p>}

        <div className="profile-dialog__actions">
          <button type="button" onClick={cancelar} disabled={procesando}>
            Cancelar
          </button>
          <button
            type="button"
            disabled={!puedeContinuar || procesando}
            onClick={() => seleccionar(idPerfil!, idPuesto ?? undefined)}
          >
            {procesando ? 'Ingresando…' : 'Continuar'}
          </button>
        </div>
      </section>
    </div>
  )
}
