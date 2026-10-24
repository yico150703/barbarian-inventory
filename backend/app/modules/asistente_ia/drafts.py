import json
from uuid import uuid4
from sqlalchemy import text
from flask_jwt_extended import get_jwt, get_jwt_identity
from app.core.extensions import db
from . import tools
from .provider import AssistantError


def ready():
    return bool(db.session.execute(text("SELECT to_regclass('public.asistente_ia_borrador')")).scalar())


def scope():
    claims = get_jwt()
    return {'usuario': int(get_jwt_identity()), 'perfil': int(claims['id_perfil']), 'local': int(claims['id_local'])}


def require_storage():
    if not ready():
        raise AssistantError('Falta ejecutar 20260923_asistente_ia.sql para confirmar cambios. Las consultas y el dictado sí están disponibles.', 503)


def save(plan):
    require_storage()
    identity = str(uuid4())
    db.session.execute(text('''INSERT INTO asistente_ia_borrador(id,id_usuario,id_perfil,id_local,plan)
      VALUES (:id,:usuario,:perfil,:local,CAST(:plan AS jsonb))'''),
      {**scope(), 'id': identity, 'plan': json.dumps(plan, ensure_ascii=False)})
    db.session.commit()
    return identity


def load(identity):
    require_storage()
    row = db.session.execute(text('''SELECT *, vence_en>now() AS vigente FROM asistente_ia_borrador
        WHERE id=:id AND id_usuario=:usuario AND id_perfil=:perfil AND id_local=:local FOR UPDATE'''),
        {**scope(), 'id': identity}).mappings().first()
    if row is None:
        raise AssistantError('El borrador no pertenece a esta sesión o ya no existe.', 404)
    return row


def cancel(identity):
    row = load(identity)
    if row['estado'] == 'PENDIENTE':
        db.session.execute(text("UPDATE asistente_ia_borrador SET estado='CANCELADO' WHERE id=:id"), {'id': identity})
    db.session.commit()


def perform(session, identity):
    row = load(identity)
    tools.authorize(session, row['plan']['recurso'], row['plan']['accion'])
    if row['estado'] == 'REALIZADO':
        db.session.rollback()
        return row['resultado']
    if row['estado'] != 'PENDIENTE':
        raise AssistantError('Este borrador ya fue procesado o cancelado. Actualiza el módulo antes de preparar otro.', 409)
    if not row['vigente']:
        raise AssistantError('El borrador venció. Prepara uno nuevo para revisar datos actuales.', 409)
    plan = row['plan']
    if plan['accion'] == 'editar' and tools.current_record(session, plan['recurso'], plan['id']) != plan['anterior']:
        raise AssistantError('El registro cambió después de preparar el borrador. Vuelve a prepararlo.', 409)
    # Durable claim BEFORE the existing service commits. Crash/unknown outcomes
    # remain EJECUTANDO, never automatically replayed (prevents duplicate creates).
    db.session.execute(text("UPDATE asistente_ia_borrador SET estado='EJECUTANDO' WHERE id=:id"), {'id': identity})
    db.session.commit()
    try:
        result = tools.execute(session, plan)
    except AssistantError as error:
        db.session.rollback()
        if error.status >= 500:
            raise AssistantError('No se pudo confirmar el resultado. Revisa el módulo antes de preparar otro cambio; este envío no se repetirá automáticamente.', 503) from None
        db.session.execute(text("UPDATE asistente_ia_borrador SET estado='FALLIDO',resultado=CAST(:r AS jsonb) WHERE id=:id"),
                           {'id': identity, 'r': json.dumps({'mensaje': str(error)})})
        db.session.commit()
        raise
    db.session.execute(text("UPDATE asistente_ia_borrador SET estado='REALIZADO',resultado=CAST(:r AS jsonb) WHERE id=:id"),
                       {'id': identity, 'r': json.dumps(result)})
    db.session.commit()
    return result
