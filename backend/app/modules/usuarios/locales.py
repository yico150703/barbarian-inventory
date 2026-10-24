"""Administración de tiendas; no copia datos operativos de otras sedes."""

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from app.core.extensions import db
from app.core.permissions import requiere_permiso
from app.modules.auditoria.service import registrar_actividad

locales_bp = Blueprint('locales', __name__)


def validar(datos):
    if not isinstance(datos, dict) or set(datos) != {'nombre', 'direccion'}:
        raise ValueError('Completa nombre y dirección. El código se asigna automáticamente.')
    if any(not isinstance(v, str) for v in datos.values()):
        raise ValueError('Los datos de la tienda deben ser texto.')
    datos = {k: v.strip() for k, v in datos.items()}
    if not 1 <= len(datos['nombre']) <= 100 or not 1 <= len(datos['direccion']) <= 250:
        raise ValueError('Indica un nombre de hasta 100 caracteres y una dirección de hasta 250.')
    return datos


def siguiente_codigo():
    # El bloqueo se mantiene hasta commit, también frente a eliminaciones concurrentes.
    db.session.execute(text('LOCK TABLE local IN SHARE ROW EXCLUSIVE MODE'))
    numero = db.session.execute(text('''WITH usados AS (
        SELECT substring(codigo from 5)::bigint AS numero FROM local
        WHERE codigo ~ '^TDA-[0-9]+$'
    ), candidatos AS (
        SELECT 1::bigint AS numero UNION SELECT numero+1 FROM usados
    ) SELECT min(c.numero) FROM candidatos c
      WHERE NOT EXISTS(SELECT 1 FROM usados u WHERE u.numero=c.numero)''')).scalar_one()
    return f'TDA-{numero:03d}'


@locales_bp.get('')
@requiere_permiso(id_opcion_menu=2, accion='consultar')
def listar():
    if int(get_jwt()['id_perfil']) != 1:
        return jsonify(mensaje='Solo el Administrador puede gestionar tiendas.'), 403
    rows = db.session.execute(text('''SELECT id_local,codigo,nombre,direccion,estado_registro
                                     FROM local ORDER BY length(codigo),codigo''')).mappings().all()
    return jsonify(locales=[dict(r) for r in rows])


@locales_bp.post('')
@requiere_permiso(id_opcion_menu=2, accion='crear')
def crear():
    if int(get_jwt()['id_perfil']) != 1:
        return jsonify(mensaje='Solo el Administrador puede crear tiendas.'), 403
    try:
        datos = validar(request.get_json(silent=True))
    except ValueError as error:
        return jsonify(mensaje=str(error)), 400
    try:
        datos['codigo'] = siguiente_codigo()
        usuario = int(get_jwt_identity())
        local = db.session.execute(text('''INSERT INTO local(codigo,nombre,direccion,usuario_creacion)
            VALUES(:codigo,:nombre,:direccion,:usuario)
            RETURNING id_local,codigo,nombre,direccion,estado_registro'''),
            {**datos, 'usuario': usuario}).mappings().one()
        registrar_actividad(usuario, 'LOCALES', 'CREAR', local['id_local'],
                            'Creó la tienda ' + local['nombre'])
        db.session.commit()
        return jsonify(mensaje='Tienda creada. Asigna su gerente desde Usuarios.', local=dict(local)), 201
    except IntegrityError:
        db.session.rollback()
        return jsonify(mensaje='No se pudo crear la tienda. Verifica que el código sea único.'), 409
    except Exception:
        db.session.rollback()
        raise


def modificar(identidad, accion):
    if int(get_jwt()['id_perfil']) != 1:
        return jsonify(mensaje='Solo el Administrador puede gestionar tiendas.'), 403
    try:
        datos = validar(request.get_json(silent=True)) if accion == 'EDITAR' else {}
        if accion == 'ESTADO':
            payload = request.get_json(silent=True)
            if not isinstance(payload, dict) or set(payload) != {'estado_registro'} or type(payload['estado_registro']) is not int or payload['estado_registro'] not in (0, 1):
                raise ValueError('Indica un estado válido para la tienda.')
            datos = payload
    except ValueError as error:
        return jsonify(mensaje=str(error)), 400
    try:
        db.session.execute(text('LOCK TABLE local IN SHARE ROW EXCLUSIVE MODE'))
        anterior = db.session.execute(text('SELECT * FROM local WHERE id_local=:id FOR UPDATE'), {'id': identidad}).mappings().first()
        if anterior is None:
            db.session.rollback()
            return jsonify(mensaje='La tienda ya no existe.'), 404
        if accion == 'ELIMINAR' or (accion == 'ESTADO' and datos['estado_registro'] == 0):
            if anterior['estado_registro'] == 1 and db.session.execute(text('SELECT count(*) FROM local WHERE estado_registro=1')).scalar() <= 1:
                db.session.rollback()
                return jsonify(mensaje='Debes conservar al menos una tienda activa.'), 409
            if get_jwt().get('id_local') == identidad:
                db.session.rollback()
                return jsonify(mensaje='Cambia el local activo antes de desactivar o eliminar esta tienda.'), 409
        if accion == 'ELIMINAR':
            # Revisa incluso relaciones CASCADE: nunca elimina datos asociados.
            relaciones = db.session.execute(text('''SELECT ns.nspname AS esquema, cl.relname AS tabla,
                a.attname AS columna, cardinality(c.conkey) AS columnas
                FROM pg_constraint c JOIN pg_class cl ON cl.oid=c.conrelid
                JOIN pg_namespace ns ON ns.oid=cl.relnamespace
                JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=c.conkey[1]
                WHERE c.contype='f' AND c.confrelid='public.local'::regclass''')).mappings().all()
            quote = db.engine.dialect.identifier_preparer.quote
            for r in relaciones:
                if r['columnas'] != 1 or db.session.execute(text(
                    f'SELECT EXISTS(SELECT 1 FROM {quote(r["esquema"])}.{quote(r["tabla"])} WHERE {quote(r["columna"])}=:id)'), {'id': identidad}).scalar():
                    db.session.rollback()
                    return jsonify(mensaje='Esta tienda tiene usuarios, configuraciones o historial asociado. Puedes desactivarla para conservar sus datos.'), 409
            db.session.execute(text('DELETE FROM local WHERE id_local=:id'), {'id': identidad})
            resultado = None
        else:
            campos = 'nombre=:nombre,direccion=:direccion' if accion == 'EDITAR' else 'estado_registro=:estado_registro'
            resultado = dict(db.session.execute(text(f'''UPDATE local SET {campos},
                usuario_modificacion=:usuario,fecha_modificacion=CURRENT_TIMESTAMP WHERE id_local=:id
                RETURNING id_local,codigo,nombre,direccion,estado_registro'''),
                {**datos, 'usuario': int(get_jwt_identity()), 'id': identidad}).mappings().one())
        from app.modules.auditoria.service import registrar_cambio
        usuario = int(get_jwt_identity())
        registrar_cambio(usuario, 'LOCALES', accion, 'local', identidad, dict(anterior), resultado)
        registrar_actividad(usuario, 'LOCALES', accion, identidad, f'{accion}: tienda {anterior["nombre"]}')
        db.session.commit()
        return jsonify(mensaje={'EDITAR': 'Tienda actualizada.', 'ESTADO': 'Estado de la tienda actualizado.', 'ELIMINAR': 'Tienda eliminada.'}[accion], local=resultado)
    except IntegrityError:
        db.session.rollback()
        return jsonify(mensaje='No se pudo guardar: código duplicado o tienda con datos asociados.'), 409
    except Exception:
        db.session.rollback()
        raise


@locales_bp.put('/<int:identidad>')
@requiere_permiso(id_opcion_menu=2, accion='editar')
def editar(identidad):
    return modificar(identidad, 'EDITAR')


@locales_bp.patch('/<int:identidad>/estado')
@requiere_permiso(id_opcion_menu=2, accion='editar')
def estado(identidad):
    return modificar(identidad, 'ESTADO')


@locales_bp.delete('/<int:identidad>')
@requiere_permiso(id_opcion_menu=2, accion='eliminar')
def eliminar(identidad):
    return modificar(identidad, 'ELIMINAR')
