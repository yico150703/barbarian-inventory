from decimal import Decimal

from app.modules.carta.repository import (
    listar_categorias_carta_detalladas,
    listar_menajes_detallados,
    listar_presentaciones_venta_detalladas,
)

def obtener_categorias_carta():
    categorias = listar_categorias_carta_detalladas()

    categorias_activas = sum(
        1
        for categoria in categorias
        if categoria["activo"]
    )

    categorias_inactivas = (
        len(categorias) - categorias_activas
    )

    total_items = sum(
        categoria["total_items"]
        for categoria in categorias
    )

    total_presentaciones = sum(
        categoria["total_presentaciones"]
        for categoria in categorias
    )

    respuesta = {
        "categorias": categorias,
        "resumen": {
            "total_categorias": len(categorias),
            "categorias_activas": categorias_activas,
            "categorias_inactivas": categorias_inactivas,
            "total_items": total_items,
            "total_presentaciones": total_presentaciones,
        },
    }

    return respuesta, 200

def convertir_decimal(valor):
    if isinstance(valor, Decimal):
        return float(valor)

    return valor


def serializar_presentacion_venta(presentacion):
    return {
        "id_presentacion_venta":
            presentacion["id_presentacion_venta"],
        "id_item_carta":
            presentacion["id_item_carta"],
        "codigo_item":
            presentacion["codigo_item"],
        "item":
            presentacion["item"],
        "tipo":
            presentacion["tipo"],
        "id_categoria_carta":
            presentacion["id_categoria_carta"],
        "categoria":
            presentacion["categoria"],
        "id_menaje":
            presentacion["id_menaje"],
        "menaje":
            presentacion["menaje"],
        "contenido": convertir_decimal(
            presentacion["contenido"]
        ),
        "unidad":
            presentacion["unidad"],
        "precio": convertir_decimal(
            presentacion["precio"]
        ),
        "activo":
            presentacion["activo"],
    }


def obtener_presentaciones_venta():
    presentaciones = [
        serializar_presentacion_venta(presentacion)
        for presentacion
        in listar_presentaciones_venta_detalladas()
    ]

    activas = sum(
        1
        for presentacion in presentaciones
        if presentacion["activo"]
    )

    categorias = {
        presentacion["id_categoria_carta"]
        for presentacion in presentaciones
    }

    items = {
        presentacion["id_item_carta"]
        for presentacion in presentaciones
    }

    menajes = {
        presentacion["id_menaje"]
        for presentacion in presentaciones
    }

    respuesta = {
        "presentaciones": presentaciones,
        "resumen": {
            "total_presentaciones": len(presentaciones),
            "presentaciones_activas": activas,
            "presentaciones_inactivas":
                len(presentaciones) - activas,
            "total_items": len(items),
            "total_categorias": len(categorias),
            "total_menajes": len(menajes),
        },
    }

    return respuesta, 200


def obtener_menajes():
    menajes = listar_menajes_detallados()

    activos = sum(
        1
        for menaje in menajes
        if menaje["activo"]
    )

    total_presentaciones = sum(
        menaje["total_presentaciones"]
        for menaje in menajes
    )

    respuesta = {
        "menajes": menajes,
        "resumen": {
            "total_menajes": len(menajes),
            "menajes_activos": activos,
            "menajes_inactivos":
                len(menajes) - activos,
            "total_presentaciones":
                total_presentaciones,
        },
    }

    return respuesta, 200