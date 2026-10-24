from decimal import Decimal

from app.modules.produccion.repository import (
    listar_grupos_salsa_detallados,
    listar_subproductos_detallados,
)


def convertir_decimal(valor):
    if isinstance(valor, Decimal):
        return float(valor)

    return valor


def serializar_ingrediente(ingrediente):
    return {
        "id_producto": ingrediente["id_producto"],
        "codigo": ingrediente["codigo"],
        "producto": ingrediente["producto"],
        "cantidad": convertir_decimal(
            ingrediente["cantidad"]
        ),
        "unidad": ingrediente["unidad"],
        "activo": ingrediente["activo"],
    }


def serializar_subproducto(subproducto):
    return {
        "id_subproducto":
            subproducto["id_subproducto"],
        "codigo":
            subproducto["codigo"],
        "nombre":
            subproducto["nombre"],
        "rendimiento": convertir_decimal(
            subproducto["rendimiento"]
        ),
        "unidad":
            subproducto["unidad"],
        "activo":
            subproducto["activo"],
        "instruccion": subproducto["instruccion"] or '',
        "total_ingredientes":
            subproducto["total_ingredientes"],
        "ingredientes": [
            serializar_ingrediente(ingrediente)
            for ingrediente
            in subproducto["ingredientes"]
        ],
    }


def obtener_subproductos():
    subproductos = [
        serializar_subproducto(subproducto)
        for subproducto
        in listar_subproductos_detallados()
    ]

    activos = sum(
        1
        for subproducto in subproductos
        if subproducto["activo"]
    )

    ingredientes = {
        ingrediente["id_producto"]
        for subproducto in subproductos
        for ingrediente in subproducto["ingredientes"]
        if ingrediente["id_producto"] is not None
    }

    respuesta = {
        "subproductos": subproductos,
        "resumen": {
            "total_subproductos": len(subproductos),
            "subproductos_activos": activos,
            "subproductos_inactivos":
                len(subproductos) - activos,
            "ingredientes_diferentes":
                len(ingredientes),
        },
    }

    return respuesta, 200


def serializar_opcion_salsa(opcion):
    return {
        "id_producto": opcion["id_producto"],
        "codigo": opcion["codigo"],
        "producto": opcion["producto"],
        "cantidad": convertir_decimal(
            opcion["cantidad"]
        ),
        "unidad": opcion["unidad"],
        "es_sin_salsa": opcion["es_sin_salsa"],
    }


def serializar_grupo_salsa(grupo):
    return {
        "id_grupo_salsa":
            grupo["id_grupo_salsa"],
        "id_presentacion_venta":
            grupo["id_presentacion_venta"],
        "cantidad_maxima":
            grupo["cantidad_maxima"],
        "activo":
            grupo["activo"],
        "id_item_carta":
            grupo["id_item_carta"],
        "codigo_item":
            grupo["codigo_item"],
        "item_carta":
            grupo["item_carta"],
        "categoria_carta":
            grupo["categoria_carta"],
        "contenido": convertir_decimal(
            grupo["contenido"]
        ),
        "unidad_presentacion":
            grupo["unidad_presentacion"],
        "precio": convertir_decimal(
            grupo["precio"]
        ),
        "total_opciones":
            grupo["total_opciones"],
        "opciones": [
            serializar_opcion_salsa(opcion)
            for opcion in grupo["opciones"]
        ],
    }


def obtener_grupos_salsa():
    grupos = [
        serializar_grupo_salsa(grupo)
        for grupo
        in listar_grupos_salsa_detallados()
    ]

    activos = sum(
        1
        for grupo in grupos
        if grupo["activo"]
    )

    opciones = {
        opcion["id_producto"]
        for grupo in grupos
        for opcion in grupo["opciones"]
        if opcion["id_producto"] is not None
    }

    respuesta = {
        "grupos_salsa": grupos,
        "resumen": {
            "total_grupos": len(grupos),
            "grupos_activos": activos,
            "grupos_inactivos":
                len(grupos) - activos,
            "salsas_diferentes": len(opciones),
        },
    }

    return respuesta, 200
