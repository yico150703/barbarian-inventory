"""Cobro interno, cierre de mesa y consumo del local en una sola transacción."""
import hashlib
import json
import re
import uuid
from collections import defaultdict
from decimal import Decimal, ROUND_HALF_UP

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required
from sqlalchemy import text
from werkzeug.exceptions import BadRequest, Conflict, Forbidden, NotFound

from app.core.extensions import db
from app.modules.auth.salon_orders import contexto, obtener, nombre_presentacion
from app.modules.auditoria.service import registrar_actividad

salon_payments_bp = Blueprint('salon_payments', __name__)


def preparado():
    if not db.session.execute(text("SELECT to_regclass('public.salon_cobro')")).scalar():
        raise Conflict('Falta ejecutar database/migrations/20260926_pagos_salon.sql')


def huella(datos):
    return hashlib.sha256(json.dumps(datos, sort_keys=True, default=str).encode()).hexdigest()


def cuenta(mesa, sesion):
    pedido = obtener(mesa, sesion)  # Propietario o responsable del mismo local.
    filas = db.session.execute(text('''SELECT l.*,p.id_usuario FROM salon_pedido_linea l
        JOIN salon_pedido_actual p USING(id_pedido)
        WHERE p.id_local=:local AND p.mesa=:mesa AND p.estado='ENVIADO'
        AND NOT EXISTS(SELECT 1 FROM salon_linea_anulada a WHERE a.id_linea=l.id_linea)
        ORDER BY l.id_linea'''), {'local': sesion['id_local'], 'mesa': mesa}).mappings().all()
    pedidos = db.session.execute(text('''SELECT id_pedido,version,estado,id_usuario
        FROM salon_pedido_actual WHERE id_local=:local AND mesa=:mesa ORDER BY id_pedido'''),
        {'local': sesion['id_local'], 'mesa': mesa}).mappings().all()
    revision = huella({'pedidos': [dict(p) for p in pedidos], 'lineas': [dict(l) for l in filas]})
    return pedido, filas, pedidos, revision


@salon_payments_bp.get('/mesas/<mesa>/cuenta')
@jwt_required()
def consultar_cuenta(mesa):
    sesion = contexto(mesa)
    preparado()
    pedido, _, _, revision = cuenta(mesa, sesion)
    return jsonify(**pedido, revision=revision, local=sesion['local'], usuario=sesion['usuario'])


def validar(datos):
    if not isinstance(datos, dict):
        raise BadRequest('Datos de pago inválidos')
    try:
        clave = str(uuid.UUID(str(datos.get('clave'))))
    except (ValueError, TypeError, AttributeError):
        raise BadRequest('Falta el identificador del cobro')
    tipo, metodo = datos.get('tipo'), datos.get('metodo')
    if tipo not in ('BOLETA', 'BOLETA_ELECTRONICA', 'FACTURA'):
        raise BadRequest('Selecciona el tipo de comprobante')
    if metodo not in ('EFECTIVO', 'TARJETA'):
        raise BadRequest('Selecciona efectivo o tarjeta')
    documento, cliente = datos.get('documento', ''), datos.get('cliente', '')
    if not isinstance(documento, str) or not isinstance(cliente, str):
        raise BadRequest('Datos del cliente inválidos')
    documento, cliente = documento.strip(), cliente.strip()
    if tipo == 'BOLETA':
        documento = cliente = ''
    else:
        longitud = 11 if tipo == 'FACTURA' else 8
        if not re.fullmatch(r'[0-9]{%d}' % longitud, documento) or not 1 <= len(cliente) <= 200:
            raise BadRequest('Ingresa RUC de 11 dígitos y razón social' if tipo == 'FACTURA'
                             else 'Ingresa DNI de 8 dígitos y nombres y apellidos')
    revision = datos.get('revision')
    if not isinstance(revision, str) or not re.fullmatch('[a-f0-9]{64}', revision):
        raise BadRequest('Abre nuevamente la cuenta antes de pagar')
    return {'clave': clave, 'tipo': tipo, 'metodo': metodo, 'documento': documento,
            'cliente': cliente, 'revision': revision}


def consumos(lineas):
    """Las promociones cobran una vez, pero consumen cada presentación elegida y repuesta."""
    totales = defaultdict(Decimal)

    def producto(identidad, cantidad, unidad):
        registro = db.session.execute(text('SELECT nombre,unidad FROM producto WHERE id_producto=:id'),
                                      {'id': identidad}).mappings().first()
        if not registro or registro['unidad'] != unidad or cantidad <= 0:
            raise Conflict('Revisa las unidades y cantidades de los ingredientes antes de cobrar')
        totales[identidad] += cantidad

    def consumir_presentacion(identidad_presentacion, cantidad_unidades, opciones):
        receta = db.session.execute(text('''SELECT id_receta FROM receta
            WHERE id_presentacion_venta=:id AND activo'''), {'id': identidad_presentacion}).scalar()
        detalles = [] if receta is None else db.session.execute(text(
            'SELECT * FROM receta_detalle WHERE id_receta=:id'), {'id': receta}).mappings().all()
        fila = db.session.execute(text('''SELECT ic.nombre FROM presentacion_venta pv
            JOIN item_carta ic USING(id_item_carta) WHERE pv.id_presentacion_venta=:id'''),
            {'id': identidad_presentacion}).mappings().first()
        if not detalles or not fila:
            raise Conflict('Falta configurar la receta de la presentación. No se registró el cobro.')
        for detalle in detalles:
            cantidad = detalle['cantidad'] * cantidad_unidades
            if detalle['tipo_componente'] == 'PRODUCTO':
                producto(detalle['id_producto'], cantidad, detalle['unidad'])
            else:
                sub = db.session.execute(text('SELECT * FROM subproducto WHERE id_subproducto=:id'),
                                         {'id': detalle['id_subproducto']}).mappings().one()
                ingredientes = db.session.execute(text('SELECT * FROM subproducto_detalle WHERE id_subproducto=:id'),
                                                  {'id': detalle['id_subproducto']}).mappings().all()
                if not ingredientes or sub['rendimiento'] <= 0 or sub['unidad'] != detalle['unidad']:
                    raise Conflict(f"Revisa el rendimiento y los ingredientes de {sub['nombre']}")
                for ingrediente in ingredientes:
                    producto(ingrediente['id_producto'], cantidad * ingrediente['cantidad'] / sub['rendimiento'], ingrediente['unidad'])
        for opcion in opciones:
            # Los pedidos nuevos guardan la identidad; los anteriores conservan el ID de opción.
            identidad = opcion.get('id_producto')
            if identidad is None:
                identidad = db.session.execute(text('''SELECT o.id_producto FROM grupo_salsa_opcion o
                    JOIN grupo_salsa g USING(id_grupo_salsa)
                    WHERE o.id_grupo_salsa_opcion=:id AND g.id_presentacion_venta=:presentacion'''),
                    {'id': opcion['id'], 'presentacion': identidad_presentacion}).scalar()
            if identidad is None:
                raise Conflict('No se puede identificar una opción enviada. Revisa la receta antes de cobrar.')
            producto(identidad, Decimal(str(opcion['cantidad'])) * cantidad_unidades, opcion['unidad'])

    for linea in lineas:
        if linea['id_promocion'] is not None:
            for seleccion in linea['selecciones_promocion']:
                consumir_presentacion(seleccion['id_presentacion'], linea['cantidad'], seleccion['opciones'])
        else:
            consumir_presentacion(linea['id_presentacion'], linea['cantidad'], linea['opciones'])
    redondeados = {identidad: valor.quantize(Decimal('.001'), rounding=ROUND_HALF_UP)
                  for identidad, valor in totales.items()}
    if any(v <= 0 or v >= Decimal('1000000000') for v in redondeados.values()):
        raise Conflict('El consumo calculado excede la precisión admitida por el inventario')
    return redondeados


def respuesta(fila):
    return {**fila['comprobante'], 'id': fila['id_cobro'], 'numero': f"INT-{fila['id_cobro']:08d}",
            'fecha': fila['creado_en'].isoformat()}


@salon_payments_bp.get('/comprobantes/<int:identidad>')
@jwt_required()
def comprobante(identidad):
    sesion = contexto()
    preparado()
    fila = db.session.execute(text('SELECT * FROM salon_cobro WHERE id_cobro=:id AND id_local=:local'),
                              {'id': identidad, 'local': sesion['id_local']}).mappings().first()
    if not fila:
        raise NotFound('Comprobante no encontrado en este local')
    if fila['id_usuario'] != sesion['id_usuario'] and sesion['perfil'] not in (2, 3):
        raise Forbidden('No tienes acceso a este comprobante')
    return jsonify(respuesta(fila))


@salon_payments_bp.post('/mesas/<mesa>/emitir')
@jwt_required()
def emitir(mesa):
    sesion = contexto(mesa)
    preparado()
    datos = validar(request.get_json(silent=True))
    solicitud_hash = huella({**datos, 'mesa': mesa})
    try:
        # Reintentos y operaciones sobre la mesa se serializan antes de consultar el estado.
        for clave in (f"salon-cobro:{sesion['id_local']}:{datos['clave']}", f"salon:{sesion['id_local']}:{mesa}"):
            db.session.execute(text('SELECT pg_advisory_xact_lock(hashtext(:clave))'), {'clave': clave})
        previo = db.session.execute(text('SELECT * FROM salon_cobro WHERE id_local=:local AND clave=CAST(:clave AS uuid)'),
                                    {'local': sesion['id_local'], 'clave': datos['clave']}).mappings().first()
        if previo:
            if previo['id_usuario'] != sesion['id_usuario'] or previo['solicitud_hash'] != solicitud_hash:
                raise Conflict('El identificador de cobro ya se utilizó con otros datos')
            return jsonify(respuesta(previo))
        pedido, lineas, pedidos, revision = cuenta(mesa, sesion)
        if datos['revision'] != revision:
            raise Conflict('La cuenta cambió o ya fue pagada. Regresa a la mesa y revisa los productos.')
        if not lineas or any(p['estado'] != 'ENVIADO' for p in pedidos):
            raise Conflict('Envía o cancela los productos pendientes antes de pagar una cuenta con productos enviados')
        # Evita que una edición de receta deje un consumo calculado a medias.
        db.session.execute(text('LOCK TABLE receta,receta_detalle,subproducto,subproducto_detalle,producto,grupo_salsa,grupo_salsa_opcion IN SHARE MODE'))
        consumo = consumos(lineas)
        total = sum(l['precio'] * l['cantidad'] for l in lineas)
        snapshot = {'tipo': datos['tipo'], 'metodo': datos['metodo'], 'documento': datos['documento'],
                    'cliente': datos['cliente'], 'local': sesion['local'], 'mesa': mesa,
                    'usuario': sesion['usuario'], 'total': float(total), 'fiscal': False,
                    'lineas': pedido['lineas']}
        # Comparte el mismo bloqueo de numeración que los movimientos manuales.
        db.session.execute(text("SELECT pg_advisory_xact_lock(hashtext('movimiento_inventario_codigo'))"))
        numero = db.session.execute(text("""SELECT coalesce(max(CASE WHEN codigo ~ '^MI-[0-9]+$'
            THEN substring(codigo FROM 4)::integer END),0)+1 FROM movimiento_inventario""")).scalar_one()
        movimiento = db.session.execute(text('''INSERT INTO movimiento_inventario
            (codigo,tipo_movimiento,motivo_movimiento,fecha_movimiento,usuario_registro,id_local,observacion)
            VALUES(:codigo,'SALIDA','VENTA_SALON',(clock_timestamp() AT TIME ZONE 'America/Lima')::date,:usuario,:local,:observacion)
            RETURNING id_movimiento_inventario'''),
            {'codigo': f'MI-{numero:03d}', 'usuario': sesion['id_usuario'], 'local': sesion['id_local'],
             'observacion': f'Cobro de Salón, mesa {mesa}'}).scalar_one()
        for identidad, cantidad in sorted(consumo.items()):
            db.session.execute(text('''INSERT INTO movimiento_inventario_detalle
                (id_movimiento_inventario,id_producto,cantidad) VALUES(:movimiento,:producto,:cantidad)'''),
                {'movimiento': movimiento, 'producto': identidad, 'cantidad': cantidad})
        cobro = db.session.execute(text('''INSERT INTO salon_cobro
            (id_local,id_usuario,mesa,clave,solicitud_hash,tipo,metodo,documento,cliente,total,comprobante,id_movimiento)
            VALUES(:local,:usuario,:mesa,CAST(:clave AS uuid),:hash,:tipo,:metodo,:documento,:cliente,:total,CAST(:snapshot AS jsonb),:movimiento)
            RETURNING *'''), {**datos, 'local': sesion['id_local'], 'usuario': sesion['id_usuario'], 'mesa': mesa,
                'hash': solicitud_hash, 'total': total, 'snapshot': json.dumps(snapshot, ensure_ascii=False),
                'movimiento': movimiento}).mappings().one()
        for p in pedidos:
            db.session.execute(text('INSERT INTO salon_cobro_pedido(id_cobro,id_pedido) VALUES(:cobro,:pedido)'),
                               {'cobro': cobro['id_cobro'], 'pedido': p['id_pedido']})
        registrar_actividad(sesion['id_usuario'], 'SALON', 'COBRAR_MESA', cobro['id_cobro'],
            f"Cobró {mesa}: S/ {total:.2f}, {datos['metodo']}, comprobante interno INT-{cobro['id_cobro']:08d}",
            id_perfil_utilizado=sesion['perfil'], id_local=sesion['id_local'])
        resultado = respuesta(cobro)
        db.session.commit()
        return jsonify(resultado), 201
    except Exception:
        db.session.rollback()
        raise
