from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal, InvalidOperation

from app.core.extensions import db
from app.modules.auditoria.service import registrar_actividad
from app.modules.inventarios.repository import (
    actualizar_revision_inventario,
    actualizar_estado_inventario,
    buscar_cabecera_inventario_actual,
    buscar_inventario_de_hoy,
    buscar_inventario_cerrado_por_id,
    buscar_inventario_por_fecha,
    buscar_ultimo_inventario_cerrado,
    buscar_ultimos_inventarios,
    cerrar_inventario_en_base_datos,
    consultar_productos_para_inventario,
    consultar_stock_actual,
    contar_detalles_inventario,
    contar_productos_activos,
    crear_inventario_actual,
    eliminar_detalle_inventario,
    eliminar_inventario_provisional,
    guardar_detalle_inventario,
    listar_inventarios_para_revision,
    listar_productos_revision,
    producto_activo_existe,
    aplicar_stock_corregido,
    bloquear_inventario_cerrado,
    buscar_producto_para_correccion,
    crear_cabecera_correccion,
    crear_detalle_correccion,
    listar_historial_correcciones,
)

ZONA_HORARIA_LIMA = timezone(
    timedelta(hours=-5)
)

HORA_LIMITE_BORRADOR = time(
    hour=9,
    minute=0,
)


def obtener_fecha_hora_lima():
    return datetime.now(ZONA_HORARIA_LIMA)


def obtener_fechas_disponibles():
    ahora = obtener_fecha_hora_lima()
    hoy = ahora.date()
    ayer = hoy - timedelta(days=1)

    fechas = [hoy]

    limite_ayer = datetime.combine(
        hoy,
        HORA_LIMITE_BORRADOR,
        tzinfo=ZONA_HORARIA_LIMA,
    )

    if ahora < limite_ayer:
        fechas.insert(0, ayer)

    return fechas


def convertir_fecha_seleccionada(valor):
    if not isinstance(valor, str):
        return None

    try:
        return date.fromisoformat(valor)
    except ValueError:
        return None


def limpiar_borrador_vencido():
    inventario = buscar_cabecera_inventario_actual()

    if inventario is None:
        return False

    fecha_inventario = inventario[
        "fecha_inventario"
    ]

    fecha_limite = datetime.combine(
        fecha_inventario + timedelta(days=1),
        HORA_LIMITE_BORRADOR,
        tzinfo=ZONA_HORARIA_LIMA,
    )

    if obtener_fecha_hora_lima() < fecha_limite:
        return False

    try:
        eliminado = eliminar_inventario_provisional(
            inventario["id_inventario_cierre"]
        )

        db.session.commit()

        return eliminado
    except Exception:
        db.session.rollback()
        raise


def convertir_inventario(inventario):
    if inventario is None:
        return None

    return {
        "id_inventario_cierre":
            inventario["id_inventario_cierre"],
        "fecha_inventario":
            inventario["fecha_inventario"].isoformat(),
        "estado_inventario":
            inventario["estado_inventario"],
        "fecha_registro":
            inventario["fecha_registro"].isoformat()
            if inventario["fecha_registro"]
            else None,
        "usuario": inventario["usuario"],
        "productos_contados":
            int(inventario["productos_contados"] or 0),
        "observacion": inventario["observacion"],
    }


def obtener_resumen_inventario():
    total_productos = contar_productos_activos()
    inventario_hoy = buscar_inventario_de_hoy()
    ultimo_cerrado = buscar_ultimo_inventario_cerrado()
    ultimos_inventarios = buscar_ultimos_inventarios(5)

    cantidad_contada = (
        int(inventario_hoy["productos_contados"] or 0)
        if inventario_hoy
        else 0
    )

    porcentaje_avance = (
        round((cantidad_contada / total_productos) * 100, 2)
        if total_productos > 0
        else 0
    )

    return {
        "total_productos": total_productos,
        "productos_contados_hoy": cantidad_contada,
        "porcentaje_avance": porcentaje_avance,
        "inventario_hoy":
            convertir_inventario(inventario_hoy),
        "ultimo_inventario_cerrado":
            convertir_inventario(ultimo_cerrado),
        "ultimos_inventarios": [
            convertir_inventario(inventario)
            for inventario in ultimos_inventarios
        ],
    }, 200


def obtener_stock_actual():
    registros = consultar_stock_actual()

    productos = []

    for registro in registros:
        stock_actual = (
            float(registro["stock_actual"])
            if registro["stock_actual"] is not None
            else None
        )

        productos.append({
            "id_producto": registro["id_producto"],
            "codigo": registro["codigo"],
            "nombre": registro["nombre"],
            "id_categoria": registro["id_categoria"],
            "categoria": registro["categoria"],
            "unidad": registro["unidad"],
            "stock_minimo": float(
                registro["stock_minimo"]
            ),
            "stock_maximo": float(registro['stock_maximo']) if registro.get('stock_maximo') is not None else None,
            "fecha_ultimo_conteo": (
                registro["fecha_ultimo_conteo"].isoformat()
                if registro["fecha_ultimo_conteo"]
                else None
            ),
            "stock_ultimo_conteo": (
                float(registro["stock_ultimo_conteo"])
                if registro["stock_ultimo_conteo"]
                is not None
                else None
            ),
            "entradas_recepcion": float(
                registro["entradas_recepcion"]
            ),
            "entradas_movimiento": float(
                registro["entradas_movimiento"]
            ),
            "salidas_movimiento": float(
                registro["salidas_movimiento"]
            ),
            "stock_actual": stock_actual,
            "estado_stock": registro["estado_stock"],
        })

    resumen = {
        "total": len(productos),
        "disponibles": sum(
            1
            for producto in productos
            if producto["estado_stock"] == "DISPONIBLE"
        ),
        "stock_bajo": sum(
            1
            for producto in productos
            if producto["estado_stock"] == "STOCK_BAJO"
        ),
        "agotados": sum(
            1
            for producto in productos
            if producto["estado_stock"] == "AGOTADO"
        ),
        "sin_conteo": sum(
            1
            for producto in productos
            if producto["estado_stock"] == "SIN_CONTEO"
        ),
    }

    categorias = sorted({
        producto["categoria"]
        for producto in productos
    })

    return {
        "resumen": resumen,
        "categorias": categorias,
        "productos": productos,
    }, 200

def obtener_inventario_actual():
    borrador_eliminado = limpiar_borrador_vencido()

    inventario = buscar_cabecera_inventario_actual()

    id_inventario = (
        inventario["id_inventario_cierre"]
        if inventario
        else None
    )

    registros = consultar_productos_para_inventario(
        id_inventario
    )

    productos = []

    for registro in registros:
        stock_contado = (
            float(registro["stock_contado"])
            if registro["stock_contado"] is not None
            else None
        )

        productos.append({
            "id_producto": registro["id_producto"],
            "codigo": registro["codigo"],
            "nombre": registro["nombre"],
            "unidad": registro["unidad"],
            "id_categoria": registro["id_categoria"],
            "categoria": registro["categoria"],
            "stock_contado": stock_contado,
        })

    productos_contados = sum(
        1
        for producto in productos
        if producto["stock_contado"] is not None
    )

    total_productos = len(productos)

    porcentaje_avance = (
        round(
            productos_contados /
            total_productos *
            100,
            2,
        )
        if total_productos > 0
        else 0
    )

    cabecera = None

    if inventario:
        cabecera = {
            "id_inventario_cierre":
                inventario["id_inventario_cierre"],
            "fecha_inventario":
                inventario["fecha_inventario"].isoformat(),
            "estado_inventario":
                inventario["estado_inventario"],
            "usuario_registro":
                inventario["usuario_registro"],
            "usuario": inventario["usuario"],
            "fecha_registro": (
                inventario["fecha_registro"].isoformat()
                if inventario["fecha_registro"]
                else None
            ),
            "observacion":
                inventario["observacion"],
        }

    respuesta = {
        "inventario": cabecera,
        "fechas_disponibles": [
            fecha_disponible.isoformat()
            for fecha_disponible
            in obtener_fechas_disponibles()
        ],
        "resumen": {
            "total_productos": total_productos,
            "productos_contados":
                productos_contados,
            "productos_pendientes":
                total_productos -
                productos_contados,
            "porcentaje_avance":
                porcentaje_avance,
        },
        "productos": productos,
    }

    if borrador_eliminado:
        respuesta["mensaje"] = (
            "El borrador anterior venció y "
            "su progreso fue eliminado."
        )

    return respuesta, 200


def iniciar_inventario_actual(
    id_usuario,
    datos,
):
    limpiar_borrador_vencido()

    if not isinstance(datos, dict):
        return {
            "mensaje":
                "Debes enviar un objeto JSON válido"
        }, 400

    fecha_inventario = convertir_fecha_seleccionada(
        datos.get("fecha_inventario")
    )

    if fecha_inventario is None:
        return {
            "mensaje":
                "Selecciona una fecha válida"
        }, 400

    fechas_disponibles = obtener_fechas_disponibles()

    if fecha_inventario not in fechas_disponibles:
        return {
            "mensaje": (
                "Solo puedes seleccionar el día actual "
                "o el día anterior antes de las 9:00 a. m."
            )
        }, 400

    inventario_abierto = (
        buscar_cabecera_inventario_actual()
    )

    if inventario_abierto:
        misma_fecha = (
            inventario_abierto["fecha_inventario"]
            == fecha_inventario
        )

        if misma_fecha:
            return {
                "mensaje":
                    "El inventario ya estaba iniciado",
                "id_inventario_cierre":
                    inventario_abierto[
                        "id_inventario_cierre"
                    ],
                "fecha_inventario":
                    fecha_inventario.isoformat(),
            }, 200

        return {
            "mensaje": (
                "Existe otro inventario sin cerrar "
                "para la fecha "
                f"{inventario_abierto['fecha_inventario']}"
            )
        }, 409

    inventario_existente = buscar_inventario_por_fecha(
        fecha_inventario
    )

    if inventario_existente:
        if (
            inventario_existente["estado_inventario"]
            == "CERRADO"
        ):
            return {
                "mensaje":
                    "El inventario de esa fecha ya fue cerrado"
            }, 409

        return {
            "mensaje":
                "Ya existe un inventario para esa fecha"
        }, 409

    try:
        id_inventario = crear_inventario_actual(
            id_usuario,
            fecha_inventario,
        )

        if id_inventario is None:
            db.session.rollback()

            inventario_existente = (
                buscar_inventario_por_fecha(
                    fecha_inventario
                )
            )

            return {
                "mensaje":
                    "Ya existe un inventario para esa fecha",
                "id_inventario_cierre": (
                    inventario_existente[
                        "id_inventario_cierre"
                    ]
                    if inventario_existente
                    else None
                ),
            }, 409

        registrar_actividad(
            id_usuario=id_usuario,
            modulo="INVENTARIO",
            accion="INICIAR",
            id_registro_afectado=id_inventario,
            descripcion=(
                "Inició el inventario correspondiente "
                f"a la fecha {fecha_inventario.isoformat()}"
            ),
        )

        db.session.commit()

        return {
            "mensaje":
                "Inventario iniciado correctamente",
            "id_inventario_cierre":
                id_inventario,
            "fecha_inventario":
                fecha_inventario.isoformat(),
        }, 201

    except Exception:
        db.session.rollback()
        raise


def guardar_inventario_actual(
    id_usuario,
    datos,
):
    borrador_eliminado = limpiar_borrador_vencido()

    if borrador_eliminado:
        return {
            "mensaje": (
                "El borrador venció a las 9:00 a. m. "
                "y su progreso fue eliminado."
            )
        }, 410

    inventario = buscar_cabecera_inventario_actual()

    if inventario is None:
        return {
            "mensaje":
                "Primero debes iniciar el inventario"
        }, 404

    if not isinstance(datos, dict):
        return {
            "mensaje":
                "Debes enviar un objeto JSON válido"
        }, 400

    conteos = datos.get("conteos")

    if not isinstance(conteos, list):
        return {
            "mensaje":
                "Debes enviar una lista de conteos"
        }, 400

    ids_recibidos = set()
    conteos_validados = []

    for conteo in conteos:
        if not isinstance(conteo, dict):
            return {
                "mensaje":
                    "Cada conteo debe ser un objeto"
            }, 400

        try:
            id_producto = int(
                conteo.get("id_producto")
            )
        except (TypeError, ValueError):
            return {
                "mensaje":
                    "Se recibió un producto inválido"
            }, 400

        if id_producto in ids_recibidos:
            return {
                "mensaje": (
                    f"El producto {id_producto} "
                    "está repetido"
                )
            }, 400

        ids_recibidos.add(id_producto)

        if not producto_activo_existe(id_producto):
            return {
                "mensaje": (
                    f"El producto {id_producto} "
                    "no existe o está desactivado"
                )
            }, 400

        valor = conteo.get("stock_contado")

        if valor is None or valor == "":
            conteos_validados.append({
                "id_producto": id_producto,
                "stock_contado": None,
            })
            continue

        try:
            stock_contado = Decimal(str(valor))
        except (
            InvalidOperation,
            ValueError,
            TypeError,
        ):
            return {
                "mensaje": (
                    f"El conteo del producto "
                    f"{id_producto} no es válido"
                )
            }, 400

        if not stock_contado.is_finite():
            return {
                "mensaje": (
                    f"El conteo del producto "
                    f"{id_producto} no es válido"
                )
            }, 400

        if stock_contado < 0:
            return {
                "mensaje":
                    "Los conteos no pueden ser negativos"
            }, 400

        conteos_validados.append({
            "id_producto": id_producto,
            "stock_contado": stock_contado,
        })

    id_inventario = inventario[
        "id_inventario_cierre"
    ]

    try:
        for conteo in conteos_validados:
            if conteo["stock_contado"] is None:
                eliminar_detalle_inventario(
                    id_inventario,
                    conteo["id_producto"],
                )
            else:
                guardar_detalle_inventario(
                    id_inventario,
                    conteo["id_producto"],
                    conteo["stock_contado"],
                )

        cantidad_guardada = contar_detalles_inventario(
            id_inventario
        )

        nuevo_estado = (
            "BORRADOR"
            if cantidad_guardada == 0
            else "INCOMPLETO"
        )

        actualizar_estado_inventario(
            id_inventario,
            nuevo_estado,
        )

        db.session.commit()

        respuesta, _ = obtener_inventario_actual()

        respuesta["mensaje"] = (
            "Progreso guardado correctamente"
        )

        return respuesta, 200

    except Exception:
        db.session.rollback()
        raise


def cerrar_inventario_actual(
    id_usuario,
    datos,
):
    borrador_eliminado = limpiar_borrador_vencido()

    if borrador_eliminado:
        return {
            "mensaje": (
                "El borrador venció a las 9:00 a. m. "
                "y ya no puede cerrarse."
            )
        }, 410

    inventario = buscar_cabecera_inventario_actual()

    if inventario is None:
        return {
            "mensaje":
                "No existe un inventario abierto"
        }, 404

    if not isinstance(datos, dict):
        return {
            "mensaje":
                "Debes enviar un objeto JSON válido"
        }, 400


    id_inventario = inventario[
        "id_inventario_cierre"
    ]

    total_productos = contar_productos_activos()

    productos_contados = contar_detalles_inventario(
        id_inventario
    )

    productos_pendientes = max(
        total_productos - productos_contados,
        0,
    )

    try:
        inventario_cerrado = (
            cerrar_inventario_en_base_datos(
                id_inventario,
            )
        )

        if inventario_cerrado is None:
            db.session.rollback()

            return {
                "mensaje": (
                    "El inventario ya no está disponible "
                    "para cerrarse"
                )
            }, 409

        registrar_actividad(
            id_usuario=id_usuario,
            modulo="INVENTARIO",
            accion="CERRAR",
            id_registro_afectado=id_inventario,
            descripcion=(
                "Cerró el inventario correspondiente "
                f"a la fecha "
                f"{inventario['fecha_inventario'].isoformat()}"
            ),
        )

        db.session.commit()

        return {
        "mensaje":
            "Inventario cerrado correctamente",
        "id_inventario_cierre":
            id_inventario,
        "fecha_inventario":
            inventario[
                "fecha_inventario"
            ].isoformat(),
        "estado_inventario": "CERRADO",
        "total_productos": total_productos,
        "productos_contados": productos_contados,
        "productos_pendientes": productos_pendientes,
    }, 200

    except Exception:
        db.session.rollback()
        raise


def _convertir_numero_revision(valor):
    if valor is None:
        return None

    return float(valor)


def _convertir_fecha_hora_revision(valor):
    if valor is None:
        return None

    return valor.isoformat(sep=" ")


def _convertir_resumen_revision(fila):
    total_productos = int(
        fila["total_productos_actuales"] or 0
    )
    productos_contados = int(
        fila["productos_contados"] or 0
    )

    return {
        "id_inventario_cierre":
            fila["id_inventario_cierre"],
        "fecha_inventario":
            fila["fecha_inventario"].isoformat(),
        "estado_inventario":
            fila["estado_inventario"],
        "fecha_registro":
            _convertir_fecha_hora_revision(
                fila["fecha_registro"]
            ),
        "usuario_registro":
            fila["usuario_registro"],
        "registrado_por": fila["registrado_por"],
        "usuario_revision": fila["usuario_revision"],
        "revisado_por": fila["revisado_por"],
        "motivo_revision": fila["motivo_revision"],
        "observacion": fila["observacion"],
        "productos_contados": productos_contados,
        "productos_no_contados": max(
            total_productos - productos_contados,
            0,
        ),
        "productos_en_cero": int(
            fila["productos_en_cero"] or 0
        ),
        "productos_con_existencia": int(
            fila["productos_con_existencia"] or 0
        ),
        "total_productos": total_productos,
        "revisado": fila["usuario_revision"] is not None,
    }


def obtener_inventarios_para_revision():
    filas = listar_inventarios_para_revision()

    inventarios = [
        _convertir_resumen_revision(fila)
        for fila in filas
    ]

    return {
        "resumen": {
            "total_inventarios": len(inventarios),
            "pendientes_revision": sum(
                1
                for inventario in inventarios
                if not inventario["revisado"]
            ),
            "inventarios_revisados": sum(
                1
                for inventario in inventarios
                if inventario["revisado"]
            ),
        },
        "inventarios": inventarios,
    }, 200


def obtener_detalle_revision(id_inventario):
    inventario = buscar_inventario_cerrado_por_id(
        id_inventario
    )

    if inventario is None:
        return {
            "mensaje": "El inventario cerrado no existe"
        }, 404

    filas = listar_productos_revision(id_inventario)
    productos = []

    for fila in filas:
        productos.append({
            "id_producto": fila["id_producto"],
            "codigo": fila["codigo"],
            "nombre": fila["producto"],
            "categoria": fila["categoria"],
            "unidad": fila["unidad"],
            "stock_minimo":
                _convertir_numero_revision(
                    fila["stock_minimo"]
                ),
            "stock_contado":
                _convertir_numero_revision(
                    fila["stock_contado"]
                ),
            "fue_contado": bool(fila["fue_contado"]),
            "producto_activo": bool(fila["activo"]),
        })

    productos_contados = sum(
        1
        for producto in productos
        if producto["fue_contado"]
    )
    productos_en_cero = sum(
        1
        for producto in productos
        if producto["fue_contado"]
        and producto["stock_contado"] == 0
    )

    return {
        "inventario": {
            "id_inventario_cierre":
                inventario["id_inventario_cierre"],
            "fecha_inventario":
                inventario["fecha_inventario"].isoformat(),
            "estado_inventario":
                inventario["estado_inventario"],
            "fecha_registro":
                _convertir_fecha_hora_revision(
                    inventario["fecha_registro"]
                ),
            "registrado_por":
                inventario["registrado_por"],
            "usuario_revision":
                inventario["usuario_revision"],
            "revisado_por": inventario["revisado_por"],
            "motivo_revision":
                inventario["motivo_revision"],
            "observacion": inventario["observacion"],
            "revisado":
                inventario["usuario_revision"] is not None,
        },
        "resumen": {
            "total_productos": len(productos),
            "productos_contados": productos_contados,
            "productos_no_contados": (
                len(productos) - productos_contados
            ),
            "productos_en_cero": productos_en_cero,
        },
        "productos": productos,
    }, 200


def registrar_revision_inventario(
    id_inventario,
    id_usuario,
    datos,
):
    inventario = buscar_inventario_cerrado_por_id(
        id_inventario
    )

    if inventario is None:
        return {
            "mensaje": "El inventario cerrado no existe"
        }, 404

    if not isinstance(datos, dict):
        return {
            "mensaje": "Debes enviar un objeto JSON válido"
        }, 400

    motivo_revision = str(
        datos.get("motivo_revision", "")
    ).strip().upper()

    observacion = str(
        datos.get("observacion", "")
    ).strip()

    if not motivo_revision:
        return {
            "mensaje": "Selecciona un motivo de revisión"
        }, 400

    if not observacion:
        return {
            "mensaje": "Escribe la observación de la revisión"
        }, 400

    if len(motivo_revision) > 100:
        return {
            "mensaje": "El motivo es demasiado largo"
        }, 400

    if len(observacion) > 500:
        return {
            "mensaje": (
                "La observación no puede superar "
                "los 500 caracteres"
            )
        }, 400

    try:
        id_actualizado = actualizar_revision_inventario(
            id_inventario=id_inventario,
            id_usuario_revision=id_usuario,
            motivo_revision=motivo_revision,
            observacion=observacion,
        )

        if id_actualizado is None:
            db.session.rollback()

            return {
                "mensaje": (
                    "El inventario ya no está disponible "
                    "para revisión"
                )
            }, 409

        registrar_actividad(
            id_usuario=id_usuario,
            modulo="INVENTARIO",
            accion="REVISAR",
            id_registro_afectado=id_inventario,
            descripcion=(
                "Registró la revisión del inventario "
                f"{id_inventario}: {motivo_revision}"
            ),
        )

        db.session.commit()

        respuesta, _ = obtener_detalle_revision(
            id_inventario
        )
        respuesta["mensaje"] = (
            "Revisión guardada correctamente"
        )

        return respuesta, 200

    except Exception:
        db.session.rollback()
        raise

    def _convertir_stock_correccion(valor, nombre_producto):
        if valor is None or valor == "":
            return None, None

        try:
            stock = Decimal(str(valor))
        except (InvalidOperation, TypeError, ValueError):
            return None, (
                f"El nuevo conteo de {nombre_producto} "
                "no es válido"
            )

        if not stock.is_finite() or stock < 0:
            return None, (
                f"El nuevo conteo de {nombre_producto} "
                "debe ser cero o un número positivo"
            )

        return stock, None


def _stocks_son_iguales(stock_anterior, stock_nuevo):
    if stock_anterior is None and stock_nuevo is None:
        return True

    if stock_anterior is None or stock_nuevo is None:
        return False

    return Decimal(str(stock_anterior)) == stock_nuevo


def _convertir_stock_correccion(
    valor,
    nombre_producto,
):
    if valor is None or valor == "":
        return None, None

    try:
        stock = Decimal(str(valor))
    except (
        InvalidOperation,
        TypeError,
        ValueError,
    ):
        return None, (
            f"El nuevo conteo de {nombre_producto} "
            "no es válido"
        )

    if not stock.is_finite() or stock < 0:
        return None, (
            f"El nuevo conteo de {nombre_producto} "
            "debe ser cero o un número positivo"
        )

    return stock, None


def _stocks_son_iguales(
    stock_anterior,
    stock_nuevo,
):
    if (
        stock_anterior is None
        and stock_nuevo is None
    ):
        return True

    if (
        stock_anterior is None
        or stock_nuevo is None
    ):
        return False

    return (
        Decimal(str(stock_anterior))
        == stock_nuevo
    )

def corregir_inventario_cerrado(
    id_inventario,
    id_usuario,
    datos,
):
    if not isinstance(datos, dict):
        return {
            "mensaje": "Debes enviar un objeto JSON válido"
        }, 400

    motivo = str(
        datos.get("motivo_correccion", "")
    ).strip().upper()
    observacion = str(
        datos.get("observacion", "")
    ).strip()
    cambios = datos.get("cambios")

    if not motivo:
        return {
            "mensaje": "Selecciona el motivo de la corrección"
        }, 400

    if not observacion:
        return {
            "mensaje": "Escribe la observación de la corrección"
        }, 400

    if len(motivo) > 100:
        return {
            "mensaje": "El motivo no puede superar 100 caracteres"
        }, 400

    if len(observacion) > 500:
        return {
            "mensaje": (
                "La observación no puede superar "
                "500 caracteres"
            )
        }, 400

    if not isinstance(cambios, list) or not cambios:
        return {
            "mensaje": "Debes enviar al menos una corrección"
        }, 400

    try:
        inventario = bloquear_inventario_cerrado(
            id_inventario
        )

        if inventario is None:
            db.session.rollback()
            return {
                "mensaje": "El inventario cerrado no existe"
            }, 404

        ids_recibidos = set()
        cambios_validados = []

        for cambio in cambios:
            if not isinstance(cambio, dict):
                db.session.rollback()
                return {
                    "mensaje": "Cada corrección debe ser un objeto"
                }, 400

            try:
                id_producto = int(cambio.get("id_producto"))
            except (TypeError, ValueError):
                db.session.rollback()
                return {
                    "mensaje": "Se recibió un producto inválido"
                }, 400

            if id_producto in ids_recibidos:
                db.session.rollback()
                return {
                    "mensaje": (
                        f"El producto {id_producto} está repetido"
                    )
                }, 400

            producto = buscar_producto_para_correccion(
                id_inventario,
                id_producto,
            )

            if producto is None:
                db.session.rollback()
                return {
                    "mensaje": (
                        f"El producto {id_producto} no está "
                        "disponible para corrección"
                    )
                }, 400

            stock_nuevo, error_stock = (
                _convertir_stock_correccion(
                    cambio.get("stock_nuevo"),
                    producto["nombre"],
                )
            )

            if error_stock:
                db.session.rollback()
                return {"mensaje": error_stock}, 400

            stock_anterior = (
                producto["stock_contado"]
                if producto[
                    "id_inventario_cierre_detalle"
                ] is not None
                else None
            )

            ids_recibidos.add(id_producto)

            if _stocks_son_iguales(
                stock_anterior,
                stock_nuevo,
            ):
                continue

            cambios_validados.append({
                "id_producto": id_producto,
                "stock_anterior": stock_anterior,
                "stock_nuevo": stock_nuevo,
            })

        if not cambios_validados:
            db.session.rollback()
            return {
                "mensaje": "No se detectaron cambios en el conteo"
            }, 400

        id_correccion = crear_cabecera_correccion(
            id_inventario=id_inventario,
            id_usuario=id_usuario,
            motivo=motivo,
            observacion=observacion,
        )

        for cambio in cambios_validados:
            crear_detalle_correccion(
                id_correccion=id_correccion,
                id_producto=cambio["id_producto"],
                stock_anterior=cambio["stock_anterior"],
                stock_nuevo=cambio["stock_nuevo"],
            )

            aplicar_stock_corregido(
                id_inventario=id_inventario,
                id_producto=cambio["id_producto"],
                stock_nuevo=cambio["stock_nuevo"],
            )

        registrar_actividad(
            id_usuario=id_usuario,
            modulo="INVENTARIO",
            accion="CORREGIR",
            id_registro_afectado=id_inventario,
            descripcion=(
                f"Corrigió {len(cambios_validados)} producto(s) "
                f"del inventario {id_inventario}: {motivo}"
            ),
        )

        db.session.commit()

        respuesta, _ = obtener_detalle_revision(
            id_inventario
        )
        respuesta["mensaje"] = (
            "Inventario corregido correctamente"
        )
        respuesta["id_correccion"] = id_correccion

        return respuesta, 200

    except Exception:
        db.session.rollback()
        raise


def obtener_historial_correcciones(id_inventario):
    inventario = buscar_inventario_cerrado_por_id(
        id_inventario
    )

    if inventario is None:
        return {
            "mensaje": "El inventario cerrado no existe"
        }, 404

    filas = listar_historial_correcciones(id_inventario)
    correcciones = {}

    for fila in filas:
        id_correccion = fila[
            "id_inventario_cierre_correccion"
        ]

        if id_correccion not in correcciones:
            correcciones[id_correccion] = {
                "id_correccion": id_correccion,
                "fecha_correccion":
                    fila["fecha_correccion"].isoformat(
                        sep=" "
                    ),
                "motivo_correccion":
                    fila["motivo_correccion"],
                "observacion": fila["observacion"],
                "corregido_por": fila["corregido_por"],
                "cambios": [],
            }

        correcciones[id_correccion]["cambios"].append({
            "id_producto": fila["id_producto"],
            "codigo": fila["codigo"],
            "producto": fila["producto"],
            "unidad": fila["unidad"],
            "stock_anterior": (
                float(fila["stock_anterior"])
                if fila["stock_anterior"] is not None
                else None
            ),
            "stock_nuevo": (
                float(fila["stock_nuevo"])
                if fila["stock_nuevo"] is not None
                else None
            ),
        })

    return {
        "correcciones": list(correcciones.values())
    }, 200
