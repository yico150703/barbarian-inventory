"""Creacion y edicion transaccional de preparaciones internas compartidas."""
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from app.core.extensions import db
from app.modules.auditoria.service import registrar_actividad, registrar_cambio
from app.core.units import catalogo_unidades, valores_unidades, normalizar_medida, unidad_almacenamiento, obtener_unidad
from app.modules.recetas.editor_service import DatosInvalidos, cantidad, validar_componentes


def ejecutar(sql, params=None):
    return db.session.execute(text(sql), params or {})


def formulario_subproducto():
    productos = ejecutar('SELECT id_producto AS id,codigo,nombre,unidad,activo FROM producto ORDER BY nombre').mappings().all()
    return {'unidades': valores_unidades('subproducto'),
            'unidades_medida': catalogo_unidades(),
            'productos': [dict(p) for p in productos]}, 200


def guardar_subproducto(id_usuario, datos, id_subproducto=None):
    if not isinstance(datos, dict):
        return {'mensaje': 'Envia los datos del subproducto'}, 400
    try:
        # Serializa codigo y nombres para evitar duplicados concurrentes.
        ejecutar("SELECT pg_advisory_xact_lock(hashtext('subproducto_catalogo'))")
        anterior = None
        anteriores = []
        if id_subproducto is not None:
            fila = ejecutar('SELECT * FROM subproducto WHERE id_subproducto=:id FOR UPDATE',
                            {'id': id_subproducto}).mappings().first()
            if fila is None:
                db.session.rollback()
                return {'mensaje': 'El subproducto no existe'}, 404
            anterior = dict(fila)
            anteriores = [dict(d) for d in ejecutar(
                'SELECT id_producto,cantidad,unidad FROM subproducto_detalle WHERE id_subproducto=:id',
                {'id': id_subproducto}).mappings()]
            anterior['ingredientes'] = anteriores
        nombre = datos.get('nombre')
        if not isinstance(nombre, str) or not 1 <= len(nombre.strip()) <= 150:
            raise DatosInvalidos('Escribe un nombre de hasta 150 caracteres')
        nombre = nombre.strip()
        try:
            rendimiento, unidad = normalizar_medida(datos.get('rendimiento'), datos.get('unidad'), 'subproducto')
        except ValueError as error:
            raise DatosInvalidos(str(error)) from None
        rendimiento = cantidad(rendimiento)
        unidad = unidad_almacenamiento(unidad)
        if anterior and obtener_unidad(unidad).codigo != obtener_unidad(anterior['unidad']).codigo:
            raise DatosInvalidos('La unidad base no se puede cambiar: las recetas usan esa unidad. Crea otro subproducto para una unidad diferente')
        instrucciones = datos.get('instruccion', '')
        if not isinstance(instrucciones, str):
            raise DatosInvalidos('Las instrucciones deben ser texto')
        activo = datos.get('activo', anterior['activo'] if anterior else True)
        if type(activo) is not bool:
            raise DatosInvalidos('Selecciona un estado valido')
        if anterior and not activo and ejecutar('''
            SELECT EXISTS(SELECT 1 FROM receta_detalle d JOIN receta r USING(id_receta)
            WHERE d.id_subproducto=:id AND r.activo)
        ''', {'id': id_subproducto}).scalar():
            raise DatosInvalidos('Este subproducto esta usado en recetas activas; retiralo de ellas antes de desactivarlo')
        if ejecutar('''SELECT EXISTS(SELECT 1 FROM subproducto
            WHERE lower(btrim(nombre))=lower(:nombre)
              AND (:id IS NULL OR id_subproducto<>:id))''',
            {'nombre': nombre, 'id': id_subproducto}).scalar():
            raise DatosInvalidos('Ya existe un subproducto con ese nombre')
        ingredientes = validar_componentes(datos.get('ingredientes'),
            {('PRODUCTO', d['id_producto']) for d in anteriores}, solo_productos=True)
        params = {'nombre': nombre, 'unidad': unidad, 'rendimiento': rendimiento,
                  'instruccion': instrucciones.strip(), 'activo': activo, 'id': id_subproducto}
        if anterior:
            codigo = anterior['codigo']
            ejecutar('''UPDATE subproducto SET nombre=:nombre,rendimiento=:rendimiento,
                instruccion=:instruccion,activo=:activo WHERE id_subproducto=:id''', params)
        else:
            numero = ejecutar("""SELECT coalesce(max(substring(codigo FROM 4)::bigint),0)+1
                FROM subproducto WHERE codigo ~ '^SP-[0-9]+$'""").scalar_one()
            codigo = f'SP-{numero:03d}'
            if len(codigo) > 10:
                raise DatosInvalidos('Se alcanzo el limite de codigos de subproductos')
            params['codigo'] = codigo
            id_subproducto = ejecutar('''INSERT INTO subproducto(codigo,nombre,rendimiento,unidad,instruccion,activo)
                VALUES(:codigo,:nombre,:rendimiento,:unidad,:instruccion,:activo)
                RETURNING id_subproducto''', params).scalar_one()
        ejecutar('DELETE FROM subproducto_detalle WHERE id_subproducto=:id', {'id': id_subproducto})
        for ingrediente in ingredientes:
            ejecutar('''INSERT INTO subproducto_detalle(id_subproducto,id_producto,cantidad,unidad)
                VALUES(:subproducto,:producto,:cantidad,:unidad)''',
                {'subproducto': id_subproducto, 'producto': ingrediente['id'],
                 'cantidad': ingrediente['cantidad'], 'unidad': ingrediente['unidad']})
        nuevo = {**params, 'id': id_subproducto, 'codigo': codigo, 'ingredientes': ingredientes}
        accion = 'EDITAR' if anterior else 'CREAR'
        registrar_cambio(id_usuario, 'SUBPRODUCTOS', accion, 'subproducto', id_subproducto, anterior, nuevo)
        registrar_actividad(id_usuario, 'SUBPRODUCTOS', accion, id_subproducto, f'{accion}: {codigo} - {nombre}')
        db.session.commit()
        return {'mensaje': 'Subproducto guardado correctamente', 'id_subproducto': id_subproducto,
                'codigo': codigo}, 200 if anterior else 201
    except DatosInvalidos as error:
        db.session.rollback()
        return {'mensaje': str(error)}, 400
    except IntegrityError:
        db.session.rollback()
        return {'mensaje': 'No se pudo guardar por un conflicto de datos. Actualiza e intenta nuevamente'}, 409
    except Exception:
        db.session.rollback()
        raise
