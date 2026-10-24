"""Distribucion de salon por local, administrada por el gerente."""
import json
import math
import re
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from sqlalchemy import text
from werkzeug.exceptions import Forbidden, BadRequest, Conflict
from app.core.extensions import db
from app.core.local_scope import local_actual
from app.modules.auth.salon import validar_sesion_salon
from app.modules.auditoria.service import registrar_actividad

salon_layout_bp=Blueprint('salon_layout',__name__)

def predeterminado():
    elementos=[dict(codigo='BARRA',tipo='barra',x=15,y=3,ancho=70,alto=12)]
    elementos += [dict(codigo=f'B{i+1:02}',tipo='puesto',x=20+i*13,y=18,ancho=7,alto=8) for i in range(5)]
    elementos += [dict(codigo=f'M{i+1:02}',tipo='mesa',x=8+(i%4)*23,y=33+(i//4)*22,ancho=14,alto=14) for i in range(10)]
    return dict(version=0,elementos=elementos)

def existe():
    return db.session.execute(text("SELECT to_regclass('public.salon_distribucion') IS NOT NULL")).scalar()

def leer(local):
    if existe():
        fila=db.session.execute(text('SELECT version,elementos FROM salon_distribucion WHERE id_local=:local'),{'local':local}).mappings().first()
        if fila:return dict(fila)
    return predeterminado()

def validar(datos):
    if not isinstance(datos,dict) or type(datos.get('version')) is not int:raise BadRequest('Version invalida')
    elementos=datos.get('elementos')
    if not isinstance(elementos,list) or not 1<=len(elementos)<=150:raise BadRequest('Agrega entre 1 y 150 elementos')
    codigos=set()
    for e in elementos:
        if not isinstance(e,dict):raise BadRequest('Elemento invalido')
        tipo=e.get('tipo'); codigo=e.get('codigo')
        patron={'mesa':r'M[0-9]{2,3}','puesto':r'B[0-9]{2,3}','barra':r'BARRA'}
        if tipo not in patron or not isinstance(codigo,str) or not re.fullmatch(patron[tipo],codigo) or codigo in codigos:raise BadRequest('Tipo o codigo de mesa invalido o repetido')
        codigos.add(codigo)
        for k in ('x','y','ancho','alto'):
            v=e.get(k)
            if type(v) not in (int,float) or not math.isfinite(v):raise BadRequest('Posicion o tamano invalido')
        if min(e['x'],e['y'])<0 or min(e['ancho'],e['alto'])<4 or e['x']+e['ancho']>100 or e['y']+e['alto']>100:raise BadRequest('Los elementos deben quedar dentro del mapa')
    if any(e['tipo']=='puesto' for e in elementos) and 'BARRA' not in codigos:raise BadRequest('Los puestos necesitan una barra')
    return [{k:e[k] for k in ('codigo','tipo','x','y','ancho','alto')} for e in elementos]

def gerente():
    if get_jwt().get('id_perfil')!=2:raise Forbidden('Solo el perfil Gerente puede administrar el salon')
    return local_actual()

@salon_layout_bp.get('/distribucion')
@jwt_required()
def consultar():
    local=validar_sesion_salon()['id_local'] if get_jwt().get('tipo_token')=='salon' else gerente()
    return jsonify(leer(local))

@salon_layout_bp.put('/distribucion')
@jwt_required()
def guardar():
    local=gerente()
    if not existe():raise Conflict('Ejecuta 20260923_distribucion_salon.sql')
    datos=request.get_json(silent=True); elementos=validar(datos)
    try:
        db.session.execute(text('SELECT pg_advisory_xact_lock(hashtext(:clave))'),{'clave':f'salon-layout:{local}'})
        anterior=leer(local)
        if anterior['version']!=datos['version']:raise Conflict('La distribucion cambio. Recarga antes de editar.')
        disponibles={e['codigo'] for e in elementos if e['tipo']!='barra'}
        if db.session.execute(text("SELECT to_regclass('public.salon_pedido')")).scalar():
            tabla='salon_pedido_actual' if db.session.execute(text("SELECT to_regclass('public.salon_pedido_actual')")).scalar() else 'salon_pedido'
            usadas=set(db.session.execute(text(f'SELECT DISTINCT mesa FROM {tabla} WHERE id_local=:local'),{'local':local}).scalars())
            if usadas-disponibles:raise Conflict('No puedes quitar mesas con pedidos registrados: '+', '.join(sorted(usadas-disponibles)))
        db.session.execute(text('INSERT INTO salon_distribucion(id_local,version,elementos) VALUES(:local,1,CAST(:elementos AS jsonb)) ON CONFLICT(id_local) DO UPDATE SET version=salon_distribucion.version+1,elementos=excluded.elementos'),{'local':local,'elementos':json.dumps(elementos)})
        registrar_actividad(get_jwt_identity(),'SALON','EDITAR_DISTRIBUCION',local,'Actualizo la distribucion del salon',id_perfil_utilizado=2,id_local=local)
        db.session.commit()
        return jsonify(leer(local))
    except Exception:
        db.session.rollback();raise
