from decimal import Decimal, InvalidOperation

from sqlalchemy.exc import IntegrityError

from app.core.extensions import db
from app.core.units import convertir_cantidad
from app.modules.auditoria.service import registrar_actividad, registrar_cambio
from app.modules.recetas import editor_repository as repo


class DatosInvalidos(ValueError):
    pass


def identidad(valor):
    if isinstance(valor, bool) or not isinstance(valor, int) or valor <= 0:
        raise DatosInvalidos("Selecciona un registro válido")
    return valor


def cantidad(valor):
    try:
        numero = Decimal(str(valor))
    except (InvalidOperation, TypeError, ValueError):
        raise DatosInvalidos("Ingresa una cantidad válida")
    if not numero.is_finite() or numero <= 0 or numero > Decimal('999999999.999'):
        raise DatosInvalidos("Las cantidades deben ser mayores que cero")
    if numero != numero.quantize(Decimal('0.001')):
        raise DatosInvalidos("Usa como máximo tres decimales en las cantidades")
    return numero


def validar_componentes(componentes, existentes=(), solo_productos=False):
    if not isinstance(componentes, list) or not componentes or len(componentes) > 300:
        raise DatosInvalidos("Agrega entre 1 y 300 ingredientes u opciones")
    vistos = set()
    resultado = []
    for componente in componentes:
        if not isinstance(componente, dict):
            raise DatosInvalidos("Ingrediente inválido")
        tipo = componente.get("tipo_componente", "PRODUCTO")
        if tipo not in ("PRODUCTO", "SUBPRODUCTO") or (solo_productos and tipo != "PRODUCTO"):
            raise DatosInvalidos("Selecciona productos de inventario para las opciones elegibles")
        id_componente = identidad(componente.get("id"))
        clave = (tipo, id_componente)
        if clave in vistos:
            raise DatosInvalidos("No repitas un ingrediente en la lista; modifica su cantidad")
        vistos.add(clave)
        registro = repo.ingrediente(tipo, id_componente)
        if registro is None or (not registro["activo"] and clave not in existentes):
            raise DatosInvalidos("El ingrediente no existe o está inactivo")
        # La unidad viene de inventario, nunca de un valor enviado por el cliente.
        valor = componente.get("cantidad")
        if "unidad_cantidad" in componente:
            try:
                valor = convertir_cantidad(valor, componente["unidad_cantidad"], registro["unidad"])
            except ValueError as error:
                raise DatosInvalidos(str(error)) from None
        resultado.append({"tipo_componente": tipo, "id": id_componente,
                          "cantidad": cantidad(valor), "unidad": registro["unidad"]})
    return resultado


def validar_grupo(datos, existentes=()):
    if datos is None:
        return None
    if not isinstance(datos, dict) or not isinstance(datos.get("permite_repetir"), bool):
        raise DatosInvalidos("Configura correctamente las opciones elegibles")
    maximo = identidad(datos.get("cantidad_maxima"))
    if maximo > 32767:
        raise DatosInvalidos("La cantidad elegible es demasiado grande")
    opciones = validar_componentes(datos.get("opciones"), existentes, solo_productos=True)
    if not datos["permite_repetir"] and maximo > len(opciones):
        raise DatosInvalidos("Sin repetición, la cantidad elegible no puede superar las opciones disponibles")
    return {"cantidad_maxima": maximo, "permite_repetir": datos["permite_repetir"], "opciones": opciones}


def obtener_formulario():
    datos = repo.formulario()
    for presentacion in datos["presentaciones"]:
        presentacion["contenido"] = float(presentacion["contenido"])
    return datos, 200


def guardar_receta(id_usuario, datos, id_receta=None):
    if not isinstance(datos, dict):
        return {"mensaje": "Envía los datos de la receta"}, 400
    try:
        anterior = repo.buscar_receta(id_receta) if id_receta is not None else None
        if id_receta is not None and anterior is None:
            db.session.rollback()
            return {"mensaje": "La receta no existe"}, 404
        if anterior:
            presentacion = anterior
        else:
            id_presentacion = identidad(datos.get("id_presentacion_venta"))
            encontrados = repo.filas("""
                SELECT pv.*, ic.tipo FROM presentacion_venta pv
                JOIN item_carta ic USING(id_item_carta)
                WHERE pv.id_presentacion_venta=:id FOR UPDATE OF ic, pv
            """, {"id": id_presentacion})
            if not encontrados:
                raise DatosInvalidos("Crea primero la presentacion en Carta")
            presentacion = encontrados[0]
            if repo.ejecutar("SELECT EXISTS(SELECT 1 FROM receta WHERE id_presentacion_venta=:id)", {"id": id_presentacion}).scalar():
                raise DatosInvalidos("Esta presentacion ya tiene receta, incluso si esta inactiva; utiliza Editar")
        id_presentacion = presentacion["id_presentacion_venta"]
        id_item = presentacion["id_item_carta"]
        tipo = presentacion["tipo"]
        unidad = presentacion["unidad"]
        contenido = presentacion["contenido"]
        menaje = presentacion["id_menaje"]
        # Los datos comerciales solo se editan desde Carta.
        for campo in ("nombre_item", "id_categoria_carta", "tipo_item", "contenido", "unidad_presentacion", "id_menaje", "id_item_carta"):
            if campo in datos:
                raise DatosInvalidos("Edita los datos del articulo y la presentacion desde Carta")
        if anterior and datos.get("id_presentacion_venta", id_presentacion) != id_presentacion:
            raise DatosInvalidos("No se puede cambiar la presentacion de una receta existente")
        activo = datos.get("activo", anterior["activo"] if anterior else True)
        if not isinstance(activo, bool):
            raise DatosInvalidos("Estado de receta inválido")
        instrucciones = str(datos.get("instrucciones") or "").strip()
        if not instrucciones:
            raise DatosInvalidos("Escribe las instrucciones de preparación")
        prev_detalles = repo.detalles(id_receta) if anterior else []
        prev_grupo = repo.grupo(anterior["id_presentacion_venta"]) if anterior else None
        existentes = {(d['tipo_componente'], d['id_producto'] if d['tipo_componente'] == 'PRODUCTO' else d['id_subproducto']) for d in prev_detalles}
        componentes = validar_componentes(datos.get("componentes"), existentes)
        if tipo == "DIRECTO" and len(componentes) != 1:
            raise DatosInvalidos("Un ítem directo debe tener un solo ingrediente base")
        opciones_existentes = {('PRODUCTO', o['id_producto']) for o in (prev_grupo or {}).get('opciones', [])}
        grupo = validar_grupo(datos.get("grupo_salsa"), opciones_existentes)
        if anterior:
            repo.ejecutar("UPDATE receta SET instrucciones=:instrucciones,activo=:activo WHERE id_receta=:id",
                          {"id": id_receta, "instrucciones": instrucciones, "activo": activo})
        else:
            id_receta = repo.ejecutar("""
                INSERT INTO receta(id_presentacion_venta,instrucciones,activo)
                VALUES (:presentacion,:instrucciones,:activo) RETURNING id_receta
            """, {"presentacion": id_presentacion, "instrucciones": instrucciones, "activo": activo}).scalar_one()
        repo.reemplazar_detalles(id_receta, componentes)
        repo.guardar_grupo(id_presentacion, grupo)
        previo = {"receta": anterior, "componentes": prev_detalles, "grupo_salsa": prev_grupo} if anterior else None
        nuevo = {"id_item_carta": id_item, "id_presentacion_venta": id_presentacion,
                 "tipo_item": tipo, "contenido": contenido, "unidad": unidad, "id_menaje": menaje,
                 "instrucciones": instrucciones, "activo": activo, "componentes": componentes, "grupo_salsa": grupo}
        accion = "EDITAR" if anterior else "CREAR"
        registrar_cambio(id_usuario, "RECETAS", accion, "receta", id_receta, previo, nuevo)
        registrar_actividad(id_usuario, "RECETAS", accion, id_receta, f"{accion.title()} receta y opciones de la presentación {id_presentacion}")
        db.session.commit()
        mensaje = "Receta guardada correctamente"
        return {"mensaje": mensaje, "id_receta": id_receta}, 200 if anterior else 201
    except DatosInvalidos as error:
        db.session.rollback()
        return {"mensaje": str(error)}, 400
    except IntegrityError:
        db.session.rollback()
        return {"mensaje": "El código o la presentación ya existe, o los datos no cumplen las restricciones. Actualiza el formulario y revisa los valores."}, 409
    except Exception:
        db.session.rollback()
        raise
