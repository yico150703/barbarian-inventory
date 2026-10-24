from datetime import date, datetime
from decimal import Decimal, InvalidOperation

from app.core.extensions import db
from app.modules.auditoria.service import registrar_actividad
from app.modules.compras.repository import (
    crear_cabecera_orden,
    crear_detalle_orden,
    generar_codigo_orden,
    listar_productos_para_compra,
    producto_activo_existe,
    cambiar_estado_orden_historial,
    guardar_historial_estado_orden,
    listar_historial_ordenes,
    obtener_detalle_orden_historial,
    obtener_orden_historial,
    obtener_total_recibido_orden,
)


def _serializar_producto(producto):
    return {
        "id_producto": producto["id_producto"],
        "codigo": producto["codigo"],
        "nombre": producto["nombre"],
        "unidad": producto["unidad"],
        "presentacion": float(producto["presentacion"]),
        "stock_minimo": float(producto["stock_minimo"]),
        "stock_actual": (
            float(producto["stock_actual"])
            if producto["stock_actual"] is not None
            else None
        ),
        "id_categoria": producto["id_categoria"],
        "categoria": producto["categoria"],
        "id_proveedor": producto["id_proveedor"],
        "proveedor": producto["proveedor"],
    }


def obtener_formulario_orden():
    productos = listar_productos_para_compra()
    return {
        "productos": [
            _serializar_producto(producto)
            for producto in productos
        ],
        "categorias": sorted({
            producto["categoria"] for producto in productos
        }),
        "proveedores": sorted({
            producto["proveedor"] for producto in productos
        }),
    }, 200


def _calcular_sugerencia(producto):
    consumo = producto.get("consumo_total")
    stock_actual = producto.get("stock_actual")

    if consumo is None or consumo <= 0:
        return Decimal("0")

    consumo_dec = Decimal(str(consumo))
    actual_dec = Decimal(str(stock_actual)) if stock_actual is not None else Decimal("0")
    presentacion = Decimal(str(producto["presentacion"]))

    if presentacion <= 0:
        presentacion = Decimal("1")

    # 1. Consumo transcurrido con el 20% adicional
    consumo_con_margen = consumo_dec * Decimal("1.20")

    # 2. Restar el stock disponible actual (último inventario de cierre)
    necesidad_neta = consumo_con_margen - actual_dec

    # Si el stock actual cubre holgadamente la necesidad, no se sugiere compra
    if necesidad_neta <= 0:
        return Decimal("0")

    # 3. Dividir entre la presentación para calcular paquetes
    cociente = necesidad_neta / presentacion
    paquetes_enteros = int(cociente)
    residuo_decimal = cociente - paquetes_enteros

    # 4. Redondeo: >= 0.5 suma 1 paquete, < 0.5 se mantiene en el entero inferior
    if residuo_decimal >= Decimal("0.5"):
        paquetes_finales = paquetes_enteros + 1
    else:
        paquetes_finales = paquetes_enteros

    return Decimal(paquetes_finales) * presentacion

def obtener_pedido_sugerido():
    sugeridos = []
    for producto in listar_productos_para_compra():
        cantidad = _calcular_sugerencia(producto)
        if cantidad <= 0:
            continue

        item = _serializar_producto(producto)
        item["cantidad_sugerida"] = float(cantidad)
        sugeridos.append(item)

    return {
        "productos": sugeridos,
        "total_productos": len(sugeridos),
    }, 200


def _validar_detalles(detalles):
    if not isinstance(detalles, list) or not detalles:
        return None, "Agrega al menos un producto"

    ids = set()
    validados = []
    for detalle in detalles:
        try:
            id_producto = int(detalle.get("id_producto"))
            cantidad = Decimal(str(detalle.get("cantidad_solicitada")))
        except (AttributeError, InvalidOperation, TypeError, ValueError):
            return None, "Se recibió un producto o cantidad inválida"

        if id_producto in ids:
            return None, "No puedes repetir un producto"
        if not cantidad.is_finite() or cantidad <= 0:
            return None, "Las cantidades deben ser mayores que cero"
        if not producto_activo_existe(id_producto):
            return None, f"El producto {id_producto} no existe o está inactivo"

        ids.add(id_producto)
        validados.append({
            "id_producto": id_producto,
            "cantidad_solicitada": cantidad,
        })

    return validados, None


def registrar_orden(id_usuario, datos):
    if not isinstance(datos, dict):
        return {"mensaje": "Debes enviar un objeto JSON válido"}, 400

    accion = str(datos.get("accion", "")).strip().upper()
    estados = {
        "GUARDAR_BORRADOR": "BORRADOR",
        "ENVIAR": "ENVIADA",
    }
    if accion not in estados:
        return {"mensaje": "Selecciona una acción válida"}, 400

    detalles, error = _validar_detalles(datos.get("detalles"))
    if error:
        return {"mensaje": error}, 400

    estado = estados[accion]
    fecha_registro = None if estado == "BORRADOR" else date.today()

    try:
        codigo = generar_codigo_orden()
        id_orden = crear_cabecera_orden(
            codigo,
            estado,
            id_usuario,
            fecha_registro,
        )
        for detalle in detalles:
            crear_detalle_orden(
                id_orden,
                detalle["id_producto"],
                detalle["cantidad_solicitada"],
            )

        registrar_actividad(
            id_usuario=id_usuario,
            modulo="ORDEN_COMPRA",
            accion="CREAR",
            id_registro_afectado=id_orden,
            descripcion=f"Registró la orden {codigo} en estado {estado}",
        )
        db.session.commit()
        return {
            "mensaje": (
                "Orden enviada correctamente"
                if estado == "ENVIADA"
                else "Borrador guardado correctamente"
            ),
            "orden": {
                "id_orden_compra": id_orden,
                "codigo": codigo,
                "estado_orden_compra": estado,
            },
        }, 201
    except Exception:
        db.session.rollback()
        raise

ESTADOS_ORDEN = {
    "BORRADOR",
    "ENVIADA",
    "RECEPCION_PARCIAL",
    "RECEPCIONADA",
    "CERRADA_INCOMPLETA",
    "CANCELADA",
}


def _leer_fecha_filtro(valor):
    if valor in (None, ""):
        return None
    try:
        return date.fromisoformat(str(valor))
    except ValueError:
        return False


def _serializar_fecha_hora(valor):
    return valor.isoformat() if valor else None


def obtener_historial_ordenes(
    fecha_desde=None,
    fecha_hasta=None,
    estado=None,
):
    desde = _leer_fecha_filtro(fecha_desde)
    hasta = _leer_fecha_filtro(fecha_hasta)

    if desde is False or hasta is False:
        return {"mensaje": "El rango contiene una fecha inválida"}, 400
    if desde and hasta and desde > hasta:
        return {
            "mensaje": "La fecha inicial no puede superar la fecha final"
        }, 400

    estado_limpio = str(estado or "").strip().upper() or None
    if estado_limpio and estado_limpio not in ESTADOS_ORDEN:
        return {"mensaje": "El estado de orden no es válido"}, 400

    filas = listar_historial_ordenes(
        desde,
        hasta,
        estado_limpio,
    )

    return {
        "ordenes": [
            {
                "id_orden_compra": fila["id_orden_compra"],
                "codigo": fila["codigo"],
                "estado_orden_compra": fila["estado_orden_compra"],
                "fecha_registro": (
                    fila["fecha_registro"].isoformat()
                    if fila["fecha_registro"] else None
                ),
                "registrado_por": fila["registrado_por"],
                "total_productos": int(
                    fila["total_productos"] or 0
                ),
                "productos_con_recepcion": int(
                    fila["productos_con_recepcion"] or 0
                ),
                "productos_completos": int(
                    fila["productos_completos"] or 0
                ),
                "productos_pendientes": int(
                    fila["productos_pendientes"] or 0
                ),
                "motivo_cierre": fila["motivo_cierre"],
                "fecha_modificacion": _serializar_fecha_hora(
                    fila["fecha_modificacion"]
                ),
                "modificado_por": fila["modificado_por"],
            }
            for fila in filas
        ]
    }, 200


def obtener_detalle_orden(id_orden):
    orden = obtener_orden_historial(id_orden)
    if orden is None:
        return {"mensaje": "La orden no existe"}, 404

    filas = obtener_detalle_orden_historial(id_orden)
    return {
        "orden": {
            "id_orden_compra": orden["id_orden_compra"],
            "codigo": orden["codigo"],
            "estado_orden_compra": orden["estado_orden_compra"],
            "fecha_registro": (
                orden["fecha_registro"].isoformat()
                if orden["fecha_registro"] else None
            ),
            "motivo_cierre": orden["motivo_cierre"],
            "detalles": [
                {
                    "id_orden_compra_detalle":
                        fila["id_orden_compra_detalle"],
                    "id_producto": fila["id_producto"],
                    "codigo": fila["codigo"],
                    "nombre": fila["nombre"],
                    "unidad": fila["unidad"],
                    "id_proveedor": fila["id_proveedor"],
                    "proveedor": fila["proveedor"],
                    "cantidad_solicitada": float(
                        fila["cantidad_solicitada"] or 0
                    ),
                    "cantidad_recibida": float(
                        fila["cantidad_recibida"] or 0
                    ),
                    "cantidad_pendiente": float(
                        fila["cantidad_pendiente"] or 0
                    ),
                }
                for fila in filas
            ],
        }
    }, 200


def cambiar_estado_orden(id_orden, id_usuario, datos):
    if not isinstance(datos, dict):
        return {"mensaje": "Debes enviar un objeto JSON válido"}, 400

    accion = str(datos.get("accion", "")).strip().upper()
    motivo = str(datos.get("motivo", "")).strip()

    if accion not in {"CANCELAR", "CERRAR_INCOMPLETA"}:
        return {"mensaje": "Selecciona una acción válida"}, 400
    if len(motivo) < 10 or len(motivo) > 500:
        return {
            "mensaje": "El motivo debe tener entre 10 y 500 caracteres"
        }, 400

    try:
        orden = obtener_orden_historial(id_orden, bloquear=True)
        if orden is None:
            db.session.rollback()
            return {"mensaje": "La orden no existe"}, 404

        estado_anterior = orden["estado_orden_compra"]
        recibido = Decimal(str(obtener_total_recibido_orden(id_orden) or 0))

        if accion == "CANCELAR":
            if estado_anterior not in {"BORRADOR", "ENVIADA"}:
                db.session.rollback()
                return {
                    "mensaje": "Solo se puede cancelar una orden sin recepción"
                }, 409
            if recibido > 0:
                db.session.rollback()
                return {
                    "mensaje": (
                        "La orden ya tiene productos recibidos; "
                        "debes cerrarla como incompleta"
                    )
                }, 409
            estado_nuevo = "CANCELADA"
        else:
            if estado_anterior != "RECEPCION_PARCIAL" or recibido <= 0:
                db.session.rollback()
                return {
                    "mensaje": (
                        "Solo una orden parcialmente recibida puede "
                        "cerrarse como incompleta"
                    )
                }, 409
            estado_nuevo = "CERRADA_INCOMPLETA"

        guardar_historial_estado_orden(
            id_orden,
            estado_anterior,
            estado_nuevo,
            motivo,
            id_usuario,
        )
        cambiar_estado_orden_historial(
            id_orden,
            estado_nuevo,
            motivo,
            id_usuario,
        )
        registrar_actividad(
            id_usuario=id_usuario,
            modulo="ORDEN_COMPRA",
            accion=accion,
            id_registro_afectado=id_orden,
            descripcion=(
                f"Cambió la orden {orden['codigo']} de "
                f"{estado_anterior} a {estado_nuevo}. Motivo: {motivo}"
            ),
        )
        db.session.commit()
        return {
            "mensaje": "Estado de la orden actualizado correctamente",
            "estado_orden_compra": estado_nuevo,
        }, 200
    except Exception:
        db.session.rollback()
        raise