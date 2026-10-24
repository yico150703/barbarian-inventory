"""Salidas y recepciones enlazadas; cada recepción genera una sola entrada de stock."""
from datetime import date
from decimal import Decimal, InvalidOperation

from sqlalchemy import text
from werkzeug.exceptions import BadRequest, Conflict, NotFound

from app.core.extensions import db
from app.core.local_scope import local_actual, exigir_migracion_locales
from app.modules.auditoria.service import registrar_actividad
from app.modules.movimientos.repository import (
    generar_codigo_movimiento, crear_cabecera_movimiento, crear_detalle_movimiento,
)


def ready():
    exigir_migracion_locales()
    if not db.session.execute(text("SELECT to_regclass('public.movimiento_seguimiento')")).scalar():
        raise Conflict('Falta ejecutar database/migrations/20260922_seguimiento_movimientos.sql')


def validar_salida(datos, fecha):
    ready()
    if fecha != date.today():
        raise BadRequest('Los préstamos y devoluciones se registran con fecha de hoy')
    destino = None
    if datos['motivo_movimiento'] == 'PRESTAMO_ENTREGADO':
        valor = datos.get('id_local_destino')
        if type(valor) is not int or valor == local_actual():
            raise BadRequest('Selecciona otro local como destino')
        destino = db.session.execute(text('SELECT id_local,nombre FROM local WHERE id_local=:id AND estado_registro=1 FOR SHARE'), {'id': valor}).mappings().first()
        if not destino:
            raise BadRequest('El local destino no está disponible')
    return destino


def registrar_salida(id_movimiento, destino):
    db.session.execute(text('INSERT INTO movimiento_seguimiento VALUES (:id,:destino,:estado)'), {
        'id': id_movimiento, 'destino': destino['id_local'] if destino else None,
        'estado': 'PENDIENTE_RECEPCION' if destino else 'DEVUELTO',
    })


def listar():
    ready()
    local = local_actual()
    filas = db.session.execute(text('''
        SELECT m.id_movimiento_inventario AS id, m.codigo,m.fecha_movimiento AS fecha,
          m.id_local,s.id_local_destino,s.estado,m.motivo_movimiento AS motivo,
          o.nombre AS origen,d.nombre AS destino,p.nombre AS proveedor,m.observacion,
          concat_ws(' ',u.nombres,u.apellido_paterno) AS registrado_por
        FROM movimiento_seguimiento s JOIN movimiento_inventario m ON m.id_movimiento_inventario=s.id_movimiento
        JOIN local o ON o.id_local=m.id_local LEFT JOIN local d ON d.id_local=s.id_local_destino
        LEFT JOIN proveedor p ON p.id_proveedor=m.id_proveedor JOIN usuario u ON u.id_usuario=m.usuario_registro
        WHERE m.id_local=:local OR s.id_local_destino=:local ORDER BY m.id_movimiento_inventario DESC
    '''), {'local': local}).mappings().all()
    resultado = []
    for f in filas:
        item = dict(f)
        item['fecha'] = f['fecha'].isoformat()
        item['detalles'] = [dict(d) for d in db.session.execute(text('''
            SELECT p.id_producto,p.codigo,p.nombre,p.unidad,d.cantidad,
              COALESCE((SELECT sum(rd.cantidad) FROM movimiento_reintegro r
                JOIN movimiento_inventario_detalle rd ON rd.id_movimiento_inventario=r.id_movimiento
                WHERE r.id_salida=:id AND rd.id_producto=d.id_producto),0) AS recibido
            FROM movimiento_inventario_detalle d JOIN producto p USING(id_producto)
            WHERE d.id_movimiento_inventario=:id ORDER BY p.nombre
        '''), {'id': f['id']}).mappings()]
        for d in item['detalles']:
            d['cantidad'],d['recibido'] = float(d['cantidad']),float(d['recibido'])
        item['recepciones'] = [dict(r) for r in db.session.execute(text('''
            SELECT m.codigo,r.guia_proveedor,m.fecha_movimiento::text AS fecha,
                p.nombre,p.unidad,d.cantidad::float AS cantidad
            FROM movimiento_reintegro r JOIN movimiento_inventario m ON m.id_movimiento_inventario=r.id_movimiento
            JOIN movimiento_inventario_detalle d ON d.id_movimiento_inventario=m.id_movimiento_inventario
            JOIN producto p USING(id_producto) WHERE r.id_salida=:id ORDER BY r.id_movimiento,p.nombre
        '''), {'id': f['id']}).mappings()]
        resultado.append(item)
    return {'movimientos': resultado}


def recibir(id_salida, datos, usuario):
    ready()
    local = local_actual()
    if not isinstance(datos, dict):
        raise BadRequest('Envía los datos de recepción')
    try:
        salida = db.session.execute(text('''
            SELECT m.*,s.id_local_destino,s.estado FROM movimiento_seguimiento s
            JOIN movimiento_inventario m ON m.id_movimiento_inventario=s.id_movimiento
            WHERE s.id_movimiento=:id AND (m.id_local=:local OR s.id_local_destino=:local)
            FOR UPDATE OF s
        '''), {'id': id_salida,'local': local}).mappings().first()
        if not salida:
            raise NotFound('La guía no existe en este local')
        prestamo = salida['id_local_destino'] is not None
        if local != (salida['id_local_destino'] if prestamo else salida['id_local']):
            raise NotFound('Solo el local destinatario puede aceptar el préstamo')
        if salida['estado'] in ('ACEPTADO','REINTEGRADO'):
            raise Conflict('Esta guía ya fue recibida completamente')
        guia = str(datos.get('guia_proveedor') or '').strip()
        if not prestamo and (not guia or len(guia)>100):
            raise BadRequest('Registra la guía del proveedor (máximo 100 caracteres)')
        if guia and db.session.execute(text('SELECT 1 FROM movimiento_reintegro WHERE id_salida=:id AND guia_proveedor=:guia'), {'id':id_salida,'guia':guia}).scalar():
            raise Conflict('Esta guía del proveedor ya fue registrada para esta devolución')
        cantidades = dict(db.session.execute(text('SELECT id_producto,cantidad FROM movimiento_inventario_detalle WHERE id_movimiento_inventario=:id'), {'id':id_salida}).all())
        recibidos = dict(db.session.execute(text('''SELECT d.id_producto,sum(d.cantidad) FROM movimiento_reintegro r
            JOIN movimiento_inventario_detalle d ON d.id_movimiento_inventario=r.id_movimiento
            WHERE r.id_salida=:id GROUP BY d.id_producto'''), {'id':id_salida}).all())
        entrada = cantidades.copy() if prestamo else {}
        if not prestamo:
            detalles = datos.get('detalles')
            if not isinstance(detalles,list) or not detalles:
                raise BadRequest('Agrega las cantidades recibidas')
            for d in detalles:
                if not isinstance(d,dict) or type(d.get('id_producto')) is not int:
                    raise BadRequest('Producto inválido')
                p = d['id_producto']
                try:
                    c = Decimal(str(d.get('cantidad')))
                except InvalidOperation:
                    raise BadRequest('Cantidad inválida')
                if p not in cantidades or p in entrada or not c.is_finite() or c<=0 or c.as_tuple().exponent < -3 or c>cantidades[p]-recibidos.get(p,0):
                    raise BadRequest('La cantidad debe ser positiva, tener hasta 3 decimales y no superar lo pendiente')
                entrada[p] = c
        codigo = generar_codigo_movimiento()
        mid = crear_cabecera_movimiento(codigo,'ENTRADA','PRESTAMO_RECIBIDO' if prestamo else 'REPOSICION_PROVEEDOR',
            date.today(),usuario,str(salida['id_local']) if prestamo else None,salida['id_proveedor'],f"Recepción de {salida['codigo']}")
        for p,c in entrada.items():
            crear_detalle_movimiento(mid,p,c)
        db.session.execute(text('INSERT INTO movimiento_reintegro(id_movimiento,id_salida,guia_proveedor) VALUES (:id,:salida,:guia)'), {'id':mid,'salida':id_salida,'guia':None if prestamo else guia})
        completo = all(recibidos.get(p,0)+entrada.get(p,0)==c for p,c in cantidades.items())
        estado = 'ACEPTADO' if prestamo else ('REINTEGRADO' if completo else 'REINTEGRO_PARCIAL')
        db.session.execute(text('UPDATE movimiento_seguimiento SET estado=:estado WHERE id_movimiento=:id'), {'estado':estado,'id':id_salida})
        registrar_actividad(id_usuario=usuario,modulo='MOVIMIENTO_INVENTARIO',accion='CREAR',id_registro_afectado=mid,descripcion=f'Recepción {codigo} de {salida["codigo"]}: {estado}')
        db.session.commit()
        return {'mensaje':f'Recepción registrada: {codigo}', 'estado':estado},201
    except Exception:
        db.session.rollback()
        raise
