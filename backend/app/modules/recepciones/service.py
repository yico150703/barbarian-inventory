from collections import OrderedDict
from datetime import date
from decimal import Decimal, InvalidOperation

from app.core.extensions import db
from app.modules.auditoria.service import registrar_actividad
from app.modules.recepciones.repository import (
    actualizar_cantidad_recepcion,
    actualizar_estado_orden,
    actualizar_factura_recepcion,
    bloquear_orden,
    calcular_totales_orden,
    crear_detalle_recepcion,
    crear_factura_recepcion,
    crear_historial_detalle,
    crear_historial_factura,
    factura_duplicada,
    factura_duplicada_excepto,
    listar_detalles_factura,
    listar_historial_recepciones,
    listar_pendientes_recepcion,
    obtener_factura_recepcion,
    obtener_producto_pendiente,
)


MOTIVOS_CORRECCION = {
    "ERROR_DIGITACION",
    "MAL_CONTADO",
    "PRODUCTO_DANADO",
    "PRODUCTO_RECHAZADO",
    "ERROR_FACTURA",
    "OTRO",
}


def _numero(valor):
    return float(valor or 0)


def _fecha(valor):
    try:
        return date.fromisoformat(str(valor))
    except (TypeError, ValueError):
        return None


def _leer_fecha_filtro(valor):
    if valor in (None, ""):
        return None

    return _fecha(valor) or False


def recalcular_estado_orden(id_orden):
    totales = calcular_totales_orden(id_orden)

    solicitado = Decimal(
        str(totales["total_solicitado"] or 0)
    )
    recibido = Decimal(
        str(totales["total_recibido"] or 0)
    )

    if recibido <= 0:
        estado = "ENVIADA"
    elif recibido < solicitado:
        estado = "RECEPCION_PARCIAL"
    else:
        estado = "RECEPCIONADA"

    actualizar_estado_orden(
        id_orden,
        estado,
    )

    return estado


def obtener_pendientes():
    filas = listar_pendientes_recepcion()
    grupos = OrderedDict()

    for fila in filas:
        clave = (
            fila["id_orden_compra"],
            fila["id_proveedor"],
        )

        if clave not in grupos:
            grupos[clave] = {
                "id_orden_compra": fila[
                    "id_orden_compra"
                ],
                "codigo_orden": fila["codigo_orden"],
                "estado_orden_compra": fila[
                    "estado_orden_compra"
                ],
                "fecha_registro": (
                    fila["fecha_registro"].isoformat()
                    if fila["fecha_registro"]
                    else None
                ),
                "id_proveedor": fila["id_proveedor"],
                "proveedor": fila["proveedor"],
                "productos": [],
            }

        grupos[clave]["productos"].append({
            "id_producto": fila["id_producto"],
            "codigo": fila["codigo_producto"],
            "nombre": fila["producto"],
            "categoria": fila["categoria"],
            "unidad": fila["unidad"],
            "presentacion": _numero(
                fila["presentacion"]
            ),
            "cantidad_solicitada": _numero(
                fila["cantidad_solicitada"]
            ),
            "cantidad_recibida": _numero(
                fila["cantidad_recibida"]
            ),
            "cantidad_pendiente": _numero(
                fila["cantidad_pendiente"]
            ),
        })

    pendientes = list(grupos.values())

    return {
        "resumen": {
            "ordenes_pendientes": len({
                item["id_orden_compra"]
                for item in pendientes
            }),
            "recepciones_pendientes": len(
                pendientes
            ),
            "productos_pendientes": sum(
                len(item["productos"])
                for item in pendientes
            ),
        },
        "pendientes": pendientes,
    }, 200


def registrar_recepcion(
    id_orden,
    id_usuario,
    datos,
):
    if not isinstance(datos, dict):
        return {
            "mensaje": (
                "Debes enviar un objeto JSON válido"
            )
        }, 400

    try:
        id_proveedor = int(
            datos.get("id_proveedor")
        )
    except (TypeError, ValueError):
        return {
            "mensaje": (
                "Selecciona un proveedor válido"
            )
        }, 400

    numero_factura = str(
        datos.get("numero_factura", "")
    ).strip()

    fecha_recepcion = _fecha(
        datos.get("fecha_recepcion")
    )

    detalles = datos.get("detalles")

    if (
        not numero_factura
        or len(numero_factura) > 40
    ):
        return {
            "mensaje": (
                "Ingresa un número de factura válido"
            )
        }, 400

    if fecha_recepcion is None:
        return {
            "mensaje": "Ingresa una fecha válida"
        }, 400

    if (
        not isinstance(detalles, list)
        or not detalles
    ):
        return {
            "mensaje": (
                "Registra al menos un producto recibido"
            )
        }, 400

    try:
        orden = bloquear_orden(id_orden)

        if orden is None:
            db.session.rollback()
            return {
                "mensaje": "La orden no existe"
            }, 404

        if orden["estado_orden_compra"] not in (
            "ENVIADA",
            "RECEPCION_PARCIAL",
        ):
            db.session.rollback()
            return {
                "mensaje": (
                    "La orden ya no está disponible "
                    "para recepción"
                )
            }, 409

        if factura_duplicada(
            id_proveedor,
            numero_factura,
        ):
            db.session.rollback()
            return {
                "mensaje": (
                    "La factura ya fue registrada "
                    "para este proveedor"
                )
            }, 409

        validados = []
        ids = set()

        for item in detalles:
            try:
                id_producto = int(
                    item.get("id_producto")
                )
                cantidad = Decimal(
                    str(item.get("cantidad_recibida"))
                )
            except (
                AttributeError,
                InvalidOperation,
                TypeError,
                ValueError,
            ):
                db.session.rollback()
                return {
                    "mensaje": (
                        "Se recibió un detalle inválido"
                    )
                }, 400

            if id_producto in ids:
                db.session.rollback()
                return {
                    "mensaje": (
                        "Hay productos repetidos"
                    )
                }, 400

            producto = obtener_producto_pendiente(
                id_orden,
                id_proveedor,
                id_producto,
            )

            if producto is None:
                db.session.rollback()
                return {
                    "mensaje": (
                        "El producto no pertenece "
                        "a la orden y proveedor"
                    )
                }, 400

            pendiente = (
                producto["cantidad_solicitada"]
                - producto["cantidad_recibida"]
            )

            if (
                not cantidad.is_finite()
                or cantidad <= 0
            ):
                db.session.rollback()
                return {
                    "mensaje": (
                        f"La cantidad de "
                        f"{producto['nombre']} debe "
                        f"ser mayor que cero"
                    )
                }, 400

            if cantidad > pendiente:
                db.session.rollback()
                return {
                    "mensaje": (
                        f"{producto['nombre']} solo "
                        f"tiene {pendiente} "
                        f"{producto['unidad']} pendientes"
                    )
                }, 400

            ids.add(id_producto)
            validados.append((
                id_producto,
                cantidad,
            ))

        id_factura = crear_factura_recepcion(
            id_orden,
            id_proveedor,
            numero_factura,
            fecha_recepcion,
            id_usuario,
        )

        for id_producto, cantidad in validados:
            crear_detalle_recepcion(
                id_factura,
                id_producto,
                cantidad,
            )

        # Calcula nuevamente el estado utilizando
        # todas las recepciones de la orden.
        estado = recalcular_estado_orden(
            id_orden
        )

        registrar_actividad(
            id_usuario=id_usuario,
            modulo="RECEPCION_PRODUCTOS",
            accion="CREAR",
            id_registro_afectado=id_factura,
            descripcion=(
                f"Registró la factura "
                f"{numero_factura} para la orden "
                f"{orden['codigo']}"
            ),
        )

        db.session.commit()

        return {
            "mensaje": (
                "Recepción registrada correctamente"
            ),
            "id_factura_recepcion": id_factura,
            "estado_orden_compra": estado,
        }, 201

    except Exception:
        db.session.rollback()
        raise


def obtener_historial_recepciones(
    fecha_desde=None,
    fecha_hasta=None,
    id_proveedor=None,
):
    desde = _leer_fecha_filtro(
        fecha_desde
    )
    hasta = _leer_fecha_filtro(
        fecha_hasta
    )

    if desde is False or hasta is False:
        return {
            "mensaje": (
                "El rango contiene una fecha inválida"
            )
        }, 400

    if desde and hasta and desde > hasta:
        return {
            "mensaje": (
                "La fecha inicial no puede superar "
                "la fecha final"
            )
        }, 400

    proveedor = None

    if id_proveedor not in (None, ""):
        try:
            proveedor = int(id_proveedor)

            if proveedor <= 0:
                raise ValueError

        except (TypeError, ValueError):
            return {
                "mensaje": (
                    "El proveedor no es válido"
                )
            }, 400

    filas = listar_historial_recepciones(
        desde,
        hasta,
        proveedor,
    )

    return {
        "recepciones": [
            {
                "id_factura_recepcion": fila[
                    "id_factura_recepcion"
                ],
                "id_orden_compra": fila[
                    "id_orden_compra"
                ],
                "codigo_orden": fila[
                    "codigo_orden"
                ],
                "estado_orden_compra": fila[
                    "estado_orden_compra"
                ],
                "numero_factura": fila[
                    "numero_factura"
                ],
                "fecha_recepcion": fila[
                    "fecha_recepcion"
                ].isoformat(),
                "id_proveedor": fila[
                    "id_proveedor"
                ],
                "proveedor": fila["proveedor"],
                "recibido_por": fila[
                    "recibido_por"
                ],
                "productos_recibidos": int(
                    fila["productos_recibidos"]
                    or 0
                ),
                "cantidad_total": float(
                    fila["cantidad_total"]
                    or 0
                ),
            }
            for fila in filas
        ]
    }, 200


def obtener_detalle_recepcion(
    id_factura,
):
    factura = obtener_factura_recepcion(
        id_factura
    )

    if factura is None:
        return {
            "mensaje": "La recepción no existe"
        }, 404

    detalles = listar_detalles_factura(
        id_factura
    )

    return {
        "recepcion": {
            "id_factura_recepcion": factura[
                "id_factura_recepcion"
            ],
            "id_orden_compra": factura[
                "id_orden_compra"
            ],
            "codigo_orden": factura[
                "codigo_orden"
            ],
            "estado_orden_compra": factura[
                "estado_orden_compra"
            ],
            "id_proveedor": factura[
                "id_proveedor"
            ],
            "proveedor": factura[
                "proveedor"
            ],
            "numero_factura": factura[
                "numero_factura"
            ],
            "fecha_recepcion": factura[
                "fecha_recepcion"
            ].isoformat(),
            "recibido_por": factura[
                "recibido_por"
            ],
            "detalles": [
                {
                    "id_factura_recepcion_detalle":
                        fila[
                            "id_factura_recepcion_detalle"
                        ],
                    "id_producto": fila[
                        "id_producto"
                    ],
                    "codigo": fila["codigo"],
                    "nombre": fila["nombre"],
                    "unidad": fila["unidad"],
                    "cantidad_recibida": float(
                        fila["cantidad_recibida"]
                    ),
                    "cantidad_solicitada": float(
                        fila["cantidad_solicitada"]
                    ),
                    "recibido_otras_facturas": float(
                        fila[
                            "recibido_otras_facturas"
                        ] or 0
                    ),
                    "maximo_permitido": float(
                        fila["cantidad_solicitada"]
                        - fila[
                            "recibido_otras_facturas"
                        ]
                    ),
                }
                for fila in detalles
            ],
        }
    }, 200


def corregir_recepcion(
    id_factura,
    id_usuario,
    datos,
):
    if not isinstance(datos, dict):
        return {
            "mensaje": (
                "Debes enviar un objeto JSON válido"
            )
        }, 400

    numero = str(
        datos.get("numero_factura", "")
    ).strip()

    fecha_nueva = _fecha(
        datos.get("fecha_recepcion")
    )

    motivo = str(
        datos.get("motivo_correccion", "")
    ).strip().upper()

    observacion = str(
        datos.get("observacion", "")
    ).strip()

    detalles_enviados = datos.get(
        "detalles"
    )

    if not numero or len(numero) > 40:
        return {
            "mensaje": (
                "Ingresa un número de factura válido"
            )
        }, 400

    if fecha_nueva is None:
        return {
            "mensaje": "Ingresa una fecha válida"
        }, 400

    if motivo not in MOTIVOS_CORRECCION:
        return {
            "mensaje": (
                "Selecciona un motivo de corrección"
            )
        }, 400

    if (
        len(observacion) < 10
        or len(observacion) > 500
    ):
        return {
            "mensaje": (
                "La observación debe tener entre "
                "10 y 500 caracteres"
            )
        }, 400

    if (
        not isinstance(detalles_enviados, list)
        or not detalles_enviados
    ):
        return {
            "mensaje": (
                "La recepción no contiene detalles"
            )
        }, 400

    try:
        factura = obtener_factura_recepcion(
            id_factura,
            bloquear=True,
        )

        if factura is None:
            db.session.rollback()
            return {
                "mensaje": (
                    "La recepción no existe"
                )
            }, 404

        if factura[
            "estado_orden_compra"
        ] in {
            "CANCELADA",
            "CERRADA_INCOMPLETA",
        }:
            db.session.rollback()
            return {
                "mensaje": (
                    "No se puede corregir una orden "
                    "cerrada o cancelada"
                )
            }, 409

        if factura_duplicada_excepto(
            factura["id_proveedor"],
            numero,
            id_factura,
        ):
            db.session.rollback()
            return {
                "mensaje": (
                    "La factura ya existe para "
                    "este proveedor"
                )
            }, 409

        actuales = listar_detalles_factura(
            id_factura
        )

        por_id = {
            fila[
                "id_factura_recepcion_detalle"
            ]: fila
            for fila in actuales
        }

        cambios = []
        ids_recibidos = set()

        for item in detalles_enviados:
            try:
                id_detalle = int(
                    item.get(
                        "id_factura_recepcion_detalle"
                    )
                )
                cantidad = Decimal(
                    str(
                        item.get(
                            "cantidad_recibida"
                        )
                    )
                )
            except (
                AttributeError,
                InvalidOperation,
                TypeError,
                ValueError,
            ):
                db.session.rollback()
                return {
                    "mensaje": (
                        "Se recibió un detalle inválido"
                    )
                }, 400

            if (
                id_detalle in ids_recibidos
                or id_detalle not in por_id
            ):
                db.session.rollback()
                return {
                    "mensaje": (
                        "Hay detalles repetidos o "
                        "ajenos a la factura"
                    )
                }, 400

            if (
                not cantidad.is_finite()
                or cantidad <= 0
            ):
                db.session.rollback()
                return {
                    "mensaje": (
                        "Las cantidades deben ser "
                        "mayores que cero"
                    )
                }, 400

            fila = por_id[id_detalle]

            cantidad_solicitada = Decimal(
                str(fila["cantidad_solicitada"])
            )
            recibido_otras = Decimal(
                str(
                    fila[
                        "recibido_otras_facturas"
                    ] or 0
                )
            )

            maximo = (
                cantidad_solicitada
                - recibido_otras
            )

            if cantidad > maximo:
                db.session.rollback()
                return {
                    "mensaje": (
                        f"{fila['nombre']} permite "
                        f"como máximo {maximo} "
                        f"{fila['unidad']} en esta "
                        f"factura"
                    )
                }, 409

            anterior = Decimal(
                str(fila["cantidad_recibida"])
            )

            if cantidad != anterior:
                cambios.append((
                    fila,
                    anterior,
                    cantidad,
                ))

            ids_recibidos.add(id_detalle)

        if ids_recibidos != set(por_id):
            db.session.rollback()
            return {
                "mensaje": (
                    "Debes enviar todos los detalles "
                    "de la recepción"
                )
            }, 400

        cambio_cabecera = (
            numero.upper()
            != factura[
                "numero_factura"
            ].upper()
            or fecha_nueva
            != factura["fecha_recepcion"]
        )

        if (
            not cambio_cabecera
            and not cambios
        ):
            db.session.rollback()
            return {
                "mensaje": (
                    "No se detectaron cambios"
                )
            }, 400

        id_historial = crear_historial_factura(
            id_factura,
            factura["numero_factura"],
            numero,
            factura["fecha_recepcion"],
            fecha_nueva,
            id_usuario,
            motivo,
            observacion,
        )

        for (
            fila,
            anterior,
            cantidad,
        ) in cambios:
            crear_historial_detalle(
                id_historial,
                fila["id_producto"],
                anterior,
                cantidad,
            )

            actualizar_cantidad_recepcion(
                fila[
                    "id_factura_recepcion_detalle"
                ],
                cantidad,
            )

        actualizar_factura_recepcion(
            id_factura,
            numero,
            fecha_nueva,
        )

        estado = recalcular_estado_orden(
            factura["id_orden_compra"]
        )

        registrar_actividad(
            id_usuario=id_usuario,
            modulo="RECEPCION_PRODUCTOS",
            accion="CORREGIR",
            id_registro_afectado=id_factura,
            descripcion=(
                f"Corrigió la factura "
                f"{factura['numero_factura']} "
                f"de la orden "
                f"{factura['codigo_orden']}. "
                f"Motivo: {motivo}. "
                f"Observación: {observacion}"
            ),
        )

        db.session.commit()

        return {
            "mensaje": (
                "Recepción corregida correctamente"
            ),
            "estado_orden_compra": estado,
        }, 200

    except Exception:
        db.session.rollback()
        raise