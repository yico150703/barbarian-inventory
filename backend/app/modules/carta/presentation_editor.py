from decimal import Decimal, InvalidOperation

from sqlalchemy.exc import IntegrityError

from app.core.extensions import db
from app.core.units import catalogo_unidades, valores_unidades, normalizar_medida, unidad_almacenamiento, obtener_unidad
from app.modules.auditoria.service import registrar_actividad, registrar_cambio
from app.modules.recetas import editor_repository as repo
from app.modules.recetas.editor_service import DatosInvalidos, cantidad, identidad


def formulario_presentacion():
    return {"tipos": repo.opciones_check('ck_item_carta_tipo'),
            "unidades": valores_unidades('presentacion'),
            "unidades_medida": catalogo_unidades('presentacion'),
            "categorias": repo.filas('SELECT id_categoria_carta, nombre, activo FROM categoria_carta ORDER BY nombre'),
            "menajes": repo.filas('SELECT id_menaje, nombre, activo FROM menaje ORDER BY nombre'),
            "items": repo.filas('SELECT id_item_carta, codigo, nombre, tipo, id_categoria_carta, activo FROM item_carta ORDER BY nombre')}, 200


def guardar_presentacion(id_usuario, datos, id_presentacion=None):
    if not isinstance(datos, dict):
        return {'mensaje': 'Datos invalidos'}, 400
    try:
        # Mismo orden que la administracion de categorias; serializa altas y duplicados.
        repo.ejecutar('LOCK TABLE categoria_carta IN SHARE ROW EXCLUSIVE MODE')
        repo.ejecutar('LOCK TABLE item_carta IN SHARE ROW EXCLUSIVE MODE')
        anterior = None
        if id_presentacion is not None:
            encontrados = repo.filas('SELECT * FROM presentacion_venta WHERE id_presentacion_venta=:id FOR UPDATE', {'id': id_presentacion})
            if not encontrados:
                db.session.rollback()
                return {'mensaje': 'La presentacion no existe'}, 404
            anterior = encontrados[0]
        id_item = anterior['id_item_carta'] if anterior else datos.get('id_item_carta')
        item = None
        if id_item is not None:
            id_item = identidad(id_item)
            encontrados = repo.filas('SELECT * FROM item_carta WHERE id_item_carta=:id FOR UPDATE', {'id': id_item})
            if not encontrados:
                raise DatosInvalidos('Selecciona un articulo existente')
            item = encontrados[0]
            if not anterior and not item['activo']:
                raise DatosInvalidos('Selecciona un articulo activo')
        nombre = datos.get('nombre_item')
        tipo = datos.get('tipo_item')
        if not isinstance(nombre, str) or not 1 <= len(nombre.strip()) <= 200:
            raise DatosInvalidos('Ingresa el nombre del articulo (hasta 200 caracteres)')
        nombre = nombre.strip()
        if tipo not in repo.opciones_check('ck_item_carta_tipo'):
            raise DatosInvalidos('Selecciona un tipo valido')
        categoria = identidad(datos.get('id_categoria_carta'))
        if not item or categoria != item['id_categoria_carta']:
            if not repo.ejecutar('SELECT EXISTS(SELECT 1 FROM categoria_carta WHERE id_categoria_carta=:id AND activo)', {'id': categoria}).scalar():
                raise DatosInvalidos('Selecciona una categoria activa')
        if item and not anterior and (nombre != item['nombre'] or tipo != item['tipo'] or categoria != item['id_categoria_carta']):
            raise DatosInvalidos('Para cambiar el articulo utiliza Editar una presentacion existente')
        if repo.ejecutar('SELECT EXISTS(SELECT 1 FROM item_carta WHERE lower(trim(nombre))=lower(:nombre) AND id_item_carta<>:id)', {'nombre': nombre, 'id': id_item or 0}).scalar():
            raise DatosInvalidos('Ya existe ese articulo; seleccionalo en Articulo existente')
        try:
            contenido, unidad = normalizar_medida(datos.get('contenido'), datos.get('unidad'), 'presentacion')
        except ValueError as error:
            raise DatosInvalidos(str(error)) from None
        contenido = cantidad(contenido)
        unidad = unidad_almacenamiento(unidad)
        menaje = identidad(datos.get('id_menaje'))
        if not repo.filas('SELECT id_menaje FROM menaje WHERE id_menaje=:id AND activo FOR SHARE', {'id': menaje}):
            if not anterior or anterior['id_menaje'] != menaje:
                raise DatosInvalidos('Selecciona un menaje activo')
        try:
            precio = Decimal(str(datos.get('precio')))
            if not precio.is_finite() or precio < 0 or precio > Decimal('99999999.99') or precio != precio.quantize(Decimal('0.01')):
                raise InvalidOperation
        except (InvalidOperation, ValueError):
            raise DatosInvalidos('Precio invalido; usa hasta dos decimales')
        activo = datos.get('activo')
        if not isinstance(activo, bool):
            raise DatosInvalidos('Selecciona el estado de la presentacion')
        if item and tipo == 'DIRECTO' and repo.ejecutar('''
            SELECT EXISTS(SELECT 1 FROM receta r JOIN presentacion_venta pv USING(id_presentacion_venta)
            WHERE pv.id_item_carta=:id AND (SELECT count(*) FROM receta_detalle d WHERE d.id_receta=r.id_receta)<>1)
        ''', {'id': id_item}).scalar():
            raise DatosInvalidos('Las recetas existentes tienen varios ingredientes; no puedes cambiar a Directo')
        if item is None:
            categoria = identidad(datos.get('id_categoria_carta'))
            secuencia = repo.filas('UPDATE categoria_carta SET siguiente_numero=siguiente_numero+1 WHERE id_categoria_carta=:id AND activo RETURNING prefijo,siguiente_numero-1 AS numero', {'id': categoria})
            if not secuencia:
                raise DatosInvalidos('Selecciona una categoria activa')
            codigo = f"{secuencia[0]['prefijo']}-{secuencia[0]['numero']:03d}"
            if len(codigo) > 10:
                raise DatosInvalidos('El codigo generado excede el limite')
            id_item = repo.ejecutar('INSERT INTO item_carta(codigo,nombre,id_categoria_carta,tipo,activo) VALUES (:codigo,:nombre,:categoria,:tipo,true) RETURNING id_item_carta',
                                  {'codigo': codigo, 'nombre': nombre, 'categoria': categoria, 'tipo': tipo}).scalar_one()
        else:
            repo.ejecutar('UPDATE item_carta SET nombre=:nombre,tipo=:tipo,id_categoria_carta=:categoria WHERE id_item_carta=:id', {'nombre': nombre, 'tipo': tipo, 'categoria': categoria, 'id': id_item})
        valores = {'item': id_item, 'menaje': menaje, 'contenido': contenido, 'unidad': unidad, 'precio': precio, 'activo': activo}
        if anterior:
            repo.ejecutar('UPDATE presentacion_venta SET id_menaje=:menaje,contenido=:contenido,unidad=:unidad,precio=:precio,activo=:activo WHERE id_presentacion_venta=:id', {**valores, 'id': id_presentacion})
        else:
            id_presentacion = repo.ejecutar('INSERT INTO presentacion_venta(id_item_carta,id_menaje,contenido,unidad,precio,activo) VALUES (:item,:menaje,:contenido,:unidad,:precio,:activo) RETURNING id_presentacion_venta', valores).scalar_one()
        nuevo_item = repo.filas('SELECT * FROM item_carta WHERE id_item_carta=:id', {'id': id_item})[0]
        registrar_cambio(id_usuario, 'CARTA', 'EDITAR' if item else 'CREAR', 'item_carta', id_item, item, nuevo_item)
        nuevo = repo.filas('SELECT * FROM presentacion_venta WHERE id_presentacion_venta=:id', {'id': id_presentacion})[0]
        registrar_cambio(id_usuario, 'CARTA', 'EDITAR' if anterior else 'CREAR', 'presentacion_venta', id_presentacion, anterior, nuevo)
        registrar_actividad(id_usuario, 'CARTA', 'EDITAR' if anterior else 'CREAR', id_presentacion, f'Guardo presentacion de {nombre}')
        db.session.commit()
        return {'mensaje': 'Presentacion guardada. Su receta se configura en Recetas.', 'id_presentacion_venta': id_presentacion}, 200 if anterior else 201
    except DatosInvalidos as error:
        db.session.rollback()
        return {'mensaje': str(error)}, 400
    except IntegrityError:
        db.session.rollback()
        return {'mensaje': 'Ya existe esa presentacion o los datos no cumplen las restricciones. Edita el registro existente.'}, 409
    except Exception:
        db.session.rollback()
        raise
