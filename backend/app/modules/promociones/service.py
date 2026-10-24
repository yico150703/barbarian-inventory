from datetime import time
from decimal import Decimal

from app.modules.promociones.repository import (
    listar_grupos_promocion,
    listar_opciones_promocion,
    listar_promociones,
    listar_reposiciones_promocion,
)


def convertir_decimal(valor):
    if isinstance(valor, Decimal):
        return float(valor)

    return valor


def convertir_hora(valor):
    if valor is None:
        return None

    if isinstance(valor, time):
        return valor.strftime("%H:%M")

    return str(valor)


def serializar_opcion(opcion):
    return {
        "id_promocion_opcion":
            opcion["id_promocion_opcion"],
        "id_presentacion_venta":
            opcion["id_presentacion_venta"],
        "id_item_carta":
            opcion["id_item_carta"],
        "codigo_item":
            opcion["codigo_item"],
        "item_carta":
            opcion["item_carta"],
        "tipo":
            opcion["tipo"],
        "id_categoria_carta":
            opcion["id_categoria_carta"],
        "categoria_carta":
            opcion["categoria_carta"],
        "contenido": convertir_decimal(
            opcion["contenido"]
        ),
        "unidad":
            opcion["unidad"],
        "precio_individual": convertir_decimal(
            opcion["precio_individual"]
        ),
        "presentacion_activa":
            opcion["presentacion_activa"],
    }


def obtener_promociones():
    promociones_bd = listar_promociones()
    grupos_bd = listar_grupos_promocion()
    opciones_bd = listar_opciones_promocion()
    reposiciones_bd = listar_reposiciones_promocion()

    opciones_por_grupo = {}

    for opcion in opciones_bd:
        id_grupo = opcion["id_promocion_grupo"]

        opciones_por_grupo.setdefault(
            id_grupo,
            [],
        ).append(
            serializar_opcion(opcion)
        )

    grupos_por_promocion = {}
    reposiciones_por_promocion = {}

    for reposicion in reposiciones_bd:
        reposiciones_por_promocion.setdefault(reposicion['id_promocion'], []).append(
            reposicion['id_presentacion_venta'])

    for grupo in grupos_bd:
        id_promocion = grupo["id_promocion"]
        id_grupo = grupo["id_promocion_grupo"]

        grupo_serializado = {
            "id_promocion_grupo": id_grupo,
            "cantidad_elegir":
                grupo["cantidad_elegir"],
            "permite_repetir":
                grupo["permite_repetir"],
            "total_opciones": len(
                opciones_por_grupo.get(
                    id_grupo,
                    [],
                )
            ),
            "opciones": opciones_por_grupo.get(
                id_grupo,
                [],
            ),
        }

        grupos_por_promocion.setdefault(
            id_promocion,
            [],
        ).append(grupo_serializado)

    promociones = []

    for promocion in promociones_bd:
        id_promocion = promocion["id_promocion"]
        hora_inicio = convertir_hora(
            promocion["hora_inicio"]
        )
        hora_fin = convertir_hora(
            promocion["hora_fin"]
        )

        grupos = grupos_por_promocion.get(
            id_promocion,
            [],
        )

        promociones.append({
            "id_promocion": id_promocion,
            "codigo": promocion["codigo"],
            "nombre": promocion["nombre"],
            "precio": convertir_decimal(
                promocion["precio"]
            ),
            "hora_inicio": hora_inicio,
            "hora_fin": hora_fin,
            "tiene_horario": (
                hora_inicio is not None
                and hora_fin is not None
            ),
            "activo": promocion["activo"],
            "reposiciones": reposiciones_por_promocion.get(id_promocion, []),
            "total_grupos": len(grupos),
            "total_opciones": sum(
                grupo["total_opciones"]
                for grupo in grupos
            ),
            "grupos": grupos,
        })

    activas = sum(
        1
        for promocion in promociones
        if promocion["activo"]
    )

    con_horario = sum(
        1
        for promocion in promociones
        if promocion["tiene_horario"]
    )

    respuesta = {
        "promociones": promociones,
        "resumen": {
            "total_promociones": len(promociones),
            "promociones_activas": activas,
            "promociones_inactivas":
                len(promociones) - activas,
            "promociones_con_horario":
                con_horario,
            "promociones_sin_horario":
                len(promociones) - con_horario,
        },
    }

    return respuesta, 200