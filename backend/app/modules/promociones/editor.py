import re
from datetime import time
from decimal import Decimal, InvalidOperation

from sqlalchemy.exc import IntegrityError
from app.core.extensions import db
from app.modules.recetas import editor_repository as repo
from app.modules.auditoria.service import registrar_cambio, registrar_actividad


def formulario_promocion():
    opciones = repo.filas('''SELECT pv.id_presentacion_venta, ic.codigo, ic.nombre,
        pv.contenido, pv.unidad, m.nombre AS menaje, (pv.activo AND ic.activo) AS activo
        FROM presentacion_venta pv JOIN item_carta ic USING(id_item_carta)
        JOIN menaje m USING(id_menaje) ORDER BY ic.nombre,pv.contenido''')
    for opcion in opciones:
        opcion['contenido'] = float(opcion['contenido'])
    return {'presentaciones': opciones}, 200


def guardar_promocion(usuario, datos, identidad=None):
    if not isinstance(datos, dict):
        return {'mensaje': 'Datos invalidos'}, 400
    try:
        repo.ejecutar('LOCK TABLE promocion IN SHARE ROW EXCLUSIVE MODE')
        anterior = None
        grupos_previos = []
        opciones_previas = []
        reposiciones_previas = []
        if identidad is not None:
            encontrados = repo.filas('SELECT * FROM promocion WHERE id_promocion=:id FOR UPDATE', {'id': identidad})
            if not encontrados:
                db.session.rollback()
                return {'mensaje': 'La promocion no existe'}, 404
            anterior = encontrados[0]
            grupos_previos = repo.filas('SELECT * FROM promocion_grupo WHERE id_promocion=:id', {'id': identidad})
            opciones_previas = repo.filas('SELECT o.* FROM promocion_opcion o JOIN promocion_grupo g USING(id_promocion_grupo) WHERE g.id_promocion=:id', {'id': identidad})
            reposiciones_previas = repo.filas('SELECT * FROM promocion_reposicion WHERE id_promocion=:id', {'id': identidad})
        nombre = datos.get('nombre')
        if not isinstance(nombre, str) or not 1 <= len(nombre.strip()) <= 150:
            raise ValueError('Ingresa un nombre de hasta 150 caracteres')
        nombre = nombre.strip()
        if repo.ejecutar('SELECT EXISTS(SELECT 1 FROM promocion WHERE lower(trim(nombre))=lower(:nombre) AND id_promocion<>:id)', {'nombre': nombre, 'id': identidad or 0}).scalar():
            raise ValueError('Ya existe una promocion con ese nombre')
        try:
            precio = Decimal(str(datos.get('precio')))
            if not precio.is_finite() or not 0 <= precio <= Decimal('99999999.99') or precio != precio.quantize(Decimal('.01')):
                raise InvalidOperation
        except (InvalidOperation, ValueError):
            raise ValueError('Precio invalido; usa hasta dos decimales')
        activo = datos.get('activo')
        if not isinstance(activo, bool):
            raise ValueError('Estado invalido')
        inicio, fin = datos.get('hora_inicio'), datos.get('hora_fin')
        if inicio is not None or fin is not None:
            if not all(isinstance(h, str) and re.fullmatch(r'\d{2}:\d{2}', h) for h in (inicio, fin)):
                raise ValueError('Completa ambas horas con formato HH:MM')
            inicio, fin = time.fromisoformat(inicio), time.fromisoformat(fin)
            if inicio == fin:
                raise ValueError('La hora inicial y final deben ser diferentes')
        grupos = datos.get('grupos')
        if not isinstance(grupos, list) or not 1 <= len(grupos) <= 50:
            raise ValueError('Agrega entre 1 y 50 grupos')
        ids_previos = {g['id_promocion_grupo'] for g in grupos_previos}
        vistos = set()
        validos = []
        for grupo in grupos:
            if not isinstance(grupo, dict):
                raise ValueError('Grupo invalido')
            gid = grupo.get('id_promocion_grupo')
            if gid is not None and (type(gid) is not int or gid not in ids_previos or gid in vistos):
                raise ValueError('El grupo no pertenece a esta promocion o esta duplicado')
            vistos.add(gid)
            elegir, repetir, opciones = grupo.get('cantidad_elegir'), grupo.get('permite_repetir'), grupo.get('opciones')
            if type(elegir) is not int or not 1 <= elegir <= 32767 or not isinstance(repetir, bool):
                raise ValueError('Configura cuantas opciones elegir y si se pueden repetir')
            if not isinstance(opciones, list) or not 1 <= len(opciones) <= 300 or any(type(i) is not int or i <= 0 for i in opciones):
                raise ValueError('Agrega presentaciones de carta al grupo')
            if len(set(opciones)) != len(opciones):
                raise ValueError('No dupliques opciones; utiliza Permitir repetir')
            if not repetir and elegir > len(opciones):
                raise ValueError('Sin repetir, la cantidad a elegir no puede superar las opciones disponibles')
            anteriores = {o['id_presentacion_venta'] for o in opciones_previas if o['id_promocion_grupo'] == gid}
            for pid in sorted(opciones):
                filas = repo.filas('SELECT pv.activo AND ic.activo AS activo FROM presentacion_venta pv JOIN item_carta ic USING(id_item_carta) WHERE pv.id_presentacion_venta=:id FOR SHARE OF pv,ic', {'id': pid})
                if not filas or (not filas[0]['activo'] and pid not in anteriores):
                    raise ValueError('Selecciona presentaciones activas de la carta')
            validos.append({'id': gid, 'elegir': elegir, 'repetir': repetir, 'opciones': opciones})
        reposiciones = datos.get('reposiciones', [r['id_presentacion_venta'] for r in reposiciones_previas])
        opciones_promocion = {pid for grupo in validos for pid in grupo['opciones']}
        if not isinstance(reposiciones, list) or any(type(pid) is not int or pid <= 0 for pid in reposiciones):
            raise ValueError('Selecciona presentaciones validas para reposicion')
        if len(set(reposiciones)) != len(reposiciones) or not set(reposiciones).issubset(opciones_promocion):
            raise ValueError('Solo puedes habilitar reposicion para opciones incluidas en la promocion')
        valores = {'nombre': nombre, 'precio': precio, 'inicio': inicio, 'fin': fin, 'activo': activo}
        if anterior:
            repo.ejecutar('UPDATE promocion SET nombre=:nombre,precio=:precio,hora_inicio=:inicio,hora_fin=:fin,activo=:activo WHERE id_promocion=:id', {**valores, 'id': identidad})
        else:
            numero = repo.ejecutar("SELECT coalesce(max(substring(codigo from 3)::bigint),0)+1 FROM promocion WHERE codigo ~ '^P-[0-9]+$'").scalar_one()
            codigo = f'P-{numero:03d}'
            if len(codigo) > 10:
                raise ValueError('No hay codigos disponibles')
            identidad = repo.ejecutar('INSERT INTO promocion(codigo,nombre,precio,hora_inicio,hora_fin,activo) VALUES (:codigo,:nombre,:precio,:inicio,:fin,:activo) RETURNING id_promocion', {**valores, 'codigo': codigo}).scalar_one()
        for eliminado in ids_previos - vistos:
            repo.ejecutar('DELETE FROM promocion_opcion WHERE id_promocion_grupo=:id', {'id': eliminado})
            repo.ejecutar('DELETE FROM promocion_grupo WHERE id_promocion_grupo=:id', {'id': eliminado})
        for g in validos:
            if g['id'] is None:
                g['id'] = repo.ejecutar('INSERT INTO promocion_grupo(id_promocion,cantidad_elegir,permite_repetir) VALUES (:promo,:elegir,:repetir) RETURNING id_promocion_grupo', {**g, 'promo': identidad}).scalar_one()
            else:
                repo.ejecutar('UPDATE promocion_grupo SET cantidad_elegir=:elegir,permite_repetir=:repetir WHERE id_promocion_grupo=:id', g)
            repo.ejecutar('DELETE FROM promocion_opcion WHERE id_promocion_grupo=:id AND NOT (id_presentacion_venta=ANY(:opciones))', g)
            for pid in g['opciones']:
                repo.ejecutar('INSERT INTO promocion_opcion(id_promocion_grupo,id_presentacion_venta) VALUES (:grupo,:pid) ON CONFLICT (id_promocion_grupo,id_presentacion_venta) DO NOTHING', {'grupo': g['id'], 'pid': pid})
        repo.ejecutar('DELETE FROM promocion_reposicion WHERE id_promocion=:id', {'id': identidad})
        for pid in reposiciones:
            repo.ejecutar('INSERT INTO promocion_reposicion(id_promocion,id_presentacion_venta) VALUES (:promo,:pid)',
                          {'promo': identidad, 'pid': pid})
        nuevo = repo.filas('SELECT * FROM promocion WHERE id_promocion=:id', {'id': identidad})[0]
        accion = 'EDITAR' if anterior else 'CREAR'
        registrar_cambio(usuario, 'PROMOCIONES', accion, 'promocion', identidad,
                         {'promocion': anterior, 'grupos': grupos_previos, 'opciones': opciones_previas,
                          'reposiciones': reposiciones_previas} if anterior else None,
                         {'promocion': nuevo, 'grupos': validos, 'reposiciones': reposiciones})
        registrar_actividad(usuario, 'PROMOCIONES', accion, identidad, f'{accion}: {nombre}')
        db.session.commit()
        return {'mensaje': 'Promocion guardada correctamente', 'id_promocion': identidad}, 200 if anterior else 201
    except ValueError as error:
        db.session.rollback()
        return {'mensaje': str(error)}, 400
    except IntegrityError:
        db.session.rollback()
        return {'mensaje': 'Datos duplicados o referencias no validas. Actualiza el formulario.'}, 409
    except Exception:
        db.session.rollback()
        raise
