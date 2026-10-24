from decimal import Decimal

from app.modules.recetas.repository import listar_recetas_detalladas


def convertir_decimal(valor):
    if isinstance(valor, Decimal):
        return float(valor)
    return valor


def serializar_componente(componente):
    es_producto = componente["tipo_componente"] == "PRODUCTO"

    return {
        "id_receta_detalle": componente["id_receta_detalle"],
        "tipo_componente": componente["tipo_componente"],
        "id_producto": componente["id_producto"],
        "producto_codigo": componente["producto_codigo"],
        "producto_nombre": componente["producto_nombre"],
        "id_subproducto": componente["id_subproducto"],
        "subproducto_codigo": componente["subproducto_codigo"],
        "subproducto_nombre": componente["subproducto_nombre"],
        "nombre_componente": (
            componente["producto_nombre"]
            if es_producto
            else componente["subproducto_nombre"]
        ),
        "codigo_componente": (
            componente["producto_codigo"]
            if es_producto
            else componente["subproducto_codigo"]
        ),
        "cantidad": convertir_decimal(componente["cantidad"]),
        "unidad": componente["unidad"],
    }


def serializar_opcion_salsa(opcion):
    return {
        "id_grupo_salsa_opcion": opcion["id_grupo_salsa_opcion"],
        "id_producto": opcion["id_producto"],
        "codigo": opcion["codigo"],
        "nombre": opcion["nombre"],
        "cantidad": convertir_decimal(opcion["cantidad"]),
        "unidad": opcion["unidad"],
        "activo": opcion["activo"],
    }


def serializar_grupo_salsa(receta):
    if receta["id_grupo_salsa"] is None:
        return None

    return {
        "id_grupo_salsa": receta["id_grupo_salsa"],
        "cantidad_maxima": receta["cantidad_maxima"],
        "permite_repetir": receta["permite_repetir"],
        "activo": receta["grupo_salsa_activo"],
        "opciones": [
            serializar_opcion_salsa(opcion)
            for opcion in receta["opciones_salsa"]
        ],
    }


def serializar_receta(receta):
    return {
        "id_receta": receta["id_receta"],
        "id_presentacion_venta": receta["id_presentacion_venta"],
        "instrucciones": receta["instrucciones"],
        "activo": receta["activo"],
        "id_item_carta": receta["id_item_carta"],
        "codigo_item": receta["codigo_item"],
        "item_carta": receta["item_carta"],
        "tipo_item": receta["tipo_item"],
        "categoria_carta": receta["categoria_carta"],
        "id_categoria_carta": receta["id_categoria_carta"],
        "id_menaje": receta["id_menaje"],
        "contenido": convertir_decimal(receta["contenido"]),
        "unidad_presentacion": receta["unidad_presentacion"],
        "precio": convertir_decimal(receta["precio"]),
        "total_componentes": receta["total_componentes"],
        "componentes": [
            serializar_componente(componente)
            for componente in receta["componentes"]
        ],
        "grupo_salsa": serializar_grupo_salsa(receta),
    }


def obtener_recetas():
    recetas = [
        serializar_receta(receta)
        for receta in listar_recetas_detalladas()
    ]

    activas = sum(1 for receta in recetas if receta["activo"])
    categorias = sorted({
        receta["categoria_carta"]
        for receta in recetas
    })

    respuesta = {
        "recetas": recetas,
        "categorias": categorias,
        "resumen": {
            "total_recetas": len(recetas),
            "recetas_activas": activas,
            "recetas_inactivas": len(recetas) - activas,
            "total_categorias": len(categorias),
        },
    }

    return respuesta, 200
