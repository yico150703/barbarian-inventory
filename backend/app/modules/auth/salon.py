"""PIN independiente: emite tokens que no habilitan las API de gestión."""
import hashlib
import re
from datetime import timedelta
from flask import Blueprint, jsonify, request
from flask_jwt_extended import create_access_token, get_jwt, get_jwt_identity, jwt_required
from sqlalchemy import text
from werkzeug.exceptions import BadRequest, Conflict, Forbidden
from werkzeug.security import generate_password_hash, check_password_hash
from app.core.extensions import db

salon_bp=Blueprint('salon',__name__)

MIEMBRO = '''EXISTS(SELECT 1 FROM usuario_perfiles up JOIN perfiles pf USING(id_perfil)
    WHERE up.id_usuario=u.id_usuario AND up.id_perfil=4 AND up.estado_registro=1 AND pf.estado_registro=1)
 AND EXISTS(SELECT 1 FROM usuario_puestos_laborales up JOIN puesto_laboral p USING(id_puesto_laboral)
    WHERE up.id_usuario=u.id_usuario AND up.estado_registro=1 AND p.estado_registro=1
      AND lower(trim(p.nombre)) IN ('mesero','bartender'))'''
RESPONSABLE = """EXISTS(SELECT 1 FROM usuario_perfiles up JOIN perfiles pf USING(id_perfil)
 WHERE up.id_usuario=u.id_usuario AND up.id_perfil IN (2,3) AND up.estado_registro=1 AND pf.estado_registro=1)"""
ELEGIBLE = f'(({MIEMBRO}) OR ({RESPONSABLE}))'

def perfil_salon(usuario):
    return db.session.execute(text('SELECT min(up.id_perfil) FROM usuario_perfiles up JOIN perfiles p USING(id_perfil) WHERE up.id_usuario=:id AND up.id_perfil IN (2,3,4) AND up.estado_registro=1 AND p.estado_registro=1'),{'id':usuario}).scalar()



def disponible():
    return bool(db.session.execute(text("SELECT to_regclass('public.usuario_pin_salon') IS NOT NULL")).scalar())


def exigir():
    if not disponible():
        raise Conflict('Falta ejecutar database/migrations/20260923_acceso_salon.sql')


def guardar_pin(usuario, datos):
    pin=datos.get('pin_salon','')
    revocar=datos.get('revocar_pin_salon',False)
    if not isinstance(pin,str) or (pin and not re.fullmatch(r'[0-9]{4}',pin)) or type(revocar) is not bool:
        raise BadRequest('El PIN de Salón debe contener exactamente 4 dígitos')
    if not disponible():
        if pin or revocar: exigir()
        return
    elegible=db.session.execute(text(f'SELECT 1 FROM usuario u WHERE u.id_usuario=:id AND {ELEGIBLE}'),{'id':usuario}).scalar()
    if pin and not elegible:
        raise BadRequest('El PIN requiere gerente, supervisor o miembro mesero/bartender')
    if pin and revocar:
        raise BadRequest('Elige asignar o revocar el PIN')
    if revocar or not elegible:
        db.session.execute(text('DELETE FROM usuario_pin_salon WHERE id_usuario=:id'),{'id':usuario})
    elif pin:
        db.session.execute(text('''INSERT INTO usuario_pin_salon(id_usuario,pin_hash) VALUES(:id,:hash)
          ON CONFLICT(id_usuario) DO UPDATE SET pin_hash=EXCLUDED.pin_hash,
          version=usuario_pin_salon.version+1,fallos=0,bloqueado_hasta=NULL,actualizado_en=clock_timestamp()'''),
          {'id':usuario,'hash':generate_password_hash(pin)})


@salon_bp.get('/opciones')
def opciones():
    exigir()
    locales=db.session.execute(text('SELECT id_local,nombre FROM local WHERE estado_registro=1 ORDER BY nombre')).mappings().all()
    try: local=int(request.args.get('local','0'))
    except ValueError: raise BadRequest('Local inválido')
    usuarios=db.session.execute(text(f'''SELECT u.id_usuario,concat_ws(' ',u.nombres,u.apellido_paterno) AS nombre
        FROM usuario u JOIN usuario_pin_salon pin USING(id_usuario)
        JOIN usuario_local ul USING(id_usuario) JOIN local l USING(id_local)
        WHERE u.estado_registro=1 AND ul.estado_registro=1 AND l.estado_registro=1
          AND ul.id_local=:local AND {ELEGIBLE} ORDER BY nombre'''),{'local':local}).mappings().all()
    return jsonify(locales=[dict(l) for l in locales],usuarios=[dict(u) for u in usuarios])


@salon_bp.post('/login')
def login_salon():
    exigir()
    datos=request.get_json(silent=True)
    if not isinstance(datos,dict): raise BadRequest('Datos inválidos')
    pin=datos.get('pin','')
    if type(datos.get('id_usuario')) is not int or type(datos.get('id_local')) is not int or not isinstance(pin,str) or not re.fullmatch(r'[0-9]{4}',pin):
        raise BadRequest('Selecciona local y usuario e ingresa los 4 dígitos')
    # Se limita por conexión, sin confiar en cabeceras de proxy suministradas por clientes.
    origen=hashlib.sha256((request.remote_addr or 'desconocido').encode()).hexdigest()
    db.session.execute(text("DELETE FROM salon_intentos WHERE inicio<clock_timestamp()-interval '1 day'"))
    intentos=db.session.execute(text('''INSERT INTO salon_intentos(origen,intentos) VALUES(:origen,1)
      ON CONFLICT(origen) DO UPDATE SET
        intentos=CASE WHEN salon_intentos.inicio<clock_timestamp()-interval '5 minutes' THEN 1 ELSE salon_intentos.intentos+1 END,
        inicio=CASE WHEN salon_intentos.inicio<clock_timestamp()-interval '5 minutes' THEN clock_timestamp() ELSE salon_intentos.inicio END
      RETURNING intentos'''),{'origen':origen}).scalar_one()
    if intentos>15:
        db.session.commit()
        return jsonify(mensaje='Demasiados intentos. Espera 5 minutos.'),429
    fila=db.session.execute(text(f'''SELECT pin.*,u.nombres,l.nombre AS local,
        pin.bloqueado_hasta>clock_timestamp() AS bloqueado
        FROM usuario_pin_salon pin JOIN usuario u USING(id_usuario)
        JOIN usuario_local ul USING(id_usuario) JOIN local l USING(id_local)
        WHERE u.id_usuario=:usuario AND ul.id_local=:local AND u.estado_registro=1
          AND ul.estado_registro=1 AND l.estado_registro=1 AND {ELEGIBLE} FOR UPDATE OF pin'''),
        {'usuario':datos['id_usuario'],'local':datos['id_local']}).mappings().first()
    if not fila or fila['bloqueado'] or not check_password_hash(fila['pin_hash'],pin):
        if fila and not fila['bloqueado']:
            db.session.execute(text('''UPDATE usuario_pin_salon SET
                bloqueado_hasta=CASE WHEN fallos>=4 THEN clock_timestamp()+interval '5 minutes' ELSE NULL END,
                fallos=CASE WHEN fallos>=4 THEN 0 ELSE fallos+1 END WHERE id_usuario=:id'''),{'id':datos['id_usuario']})
        db.session.commit()
        return jsonify(mensaje='No se pudo acceder. Revisa los datos o espera si agotaste los intentos.'),401
    db.session.execute(text('UPDATE usuario_pin_salon SET fallos=0,bloqueado_hasta=NULL WHERE id_usuario=:id'),{'id':fila['id_usuario']})
    token=create_access_token(identity=str(fila['id_usuario']),expires_delta=timedelta(hours=2),additional_claims={
        'tipo_token':'salon','id_local':datos['id_local'],'pin_version':fila['version'],
        'pin_actualizado':fila['actualizado_en'].isoformat()})
    db.session.commit()
    return jsonify(token=token)


def validar_sesion_salon():
    jwt=get_jwt()
    if jwt.get('tipo_token')!='salon': raise Forbidden('Esta sesión no pertenece a Salón')
    exigir()
    fila=db.session.execute(text(f'''SELECT u.nombres,l.nombre AS local,pin.version,pin.actualizado_en
        FROM usuario u JOIN usuario_pin_salon pin USING(id_usuario)
        JOIN usuario_local ul USING(id_usuario) JOIN local l USING(id_local)
        WHERE u.id_usuario=:usuario AND ul.id_local=:local AND ul.estado_registro=1
          AND u.estado_registro=1 AND l.estado_registro=1 AND {ELEGIBLE}'''),
        {'usuario':get_jwt_identity(),'local':jwt.get('id_local')}).mappings().first()
    if not fila or fila['version']!=jwt.get('pin_version') or fila['actualizado_en'].isoformat()!=jwt.get('pin_actualizado'):
        raise Forbidden('El acceso de Salón fue revocado. Inicia sesión nuevamente.')
    return {'usuario':fila['nombres'],'local':fila['local'],'id_usuario':int(get_jwt_identity()),'id_local':jwt['id_local'],'perfil':perfil_salon(int(get_jwt_identity()))}


@salon_bp.get('/me')
@jwt_required()
def sesion_salon():
    return jsonify(validar_sesion_salon())
