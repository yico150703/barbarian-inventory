from sqlalchemy import text

from app.core.extensions import db


def listar_promociones():
    consulta = text("""
        SELECT
            id_promocion,
            codigo,
            nombre,
            precio,
            hora_inicio,
            hora_fin,
            activo
        FROM promocion
        ORDER BY
            activo DESC,
            codigo ASC
    """)

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]


def listar_grupos_promocion():
    consulta = text("""
        SELECT
            id_promocion_grupo,
            id_promocion,
            cantidad_elegir,
            permite_repetir
        FROM promocion_grupo
        ORDER BY
            id_promocion,
            id_promocion_grupo
    """)

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]


def listar_opciones_promocion():
    consulta = text("""
        SELECT
            po.id_promocion_opcion,
            po.id_promocion_grupo,
            po.id_presentacion_venta,

            pv.id_item_carta,
            ic.codigo AS codigo_item,
            ic.nombre AS item_carta,
            ic.tipo,

            cc.id_categoria_carta,
            cc.nombre AS categoria_carta,

            pv.contenido,
            pv.unidad,
            pv.precio AS precio_individual,
            pv.activo AS presentacion_activa

        FROM promocion_opcion AS po

        INNER JOIN presentacion_venta AS pv
            ON pv.id_presentacion_venta =
                po.id_presentacion_venta

        INNER JOIN item_carta AS ic
            ON ic.id_item_carta =
                pv.id_item_carta

        INNER JOIN categoria_carta AS cc
            ON cc.id_categoria_carta =
                ic.id_categoria_carta

        ORDER BY
            po.id_promocion_grupo,
            ic.nombre ASC
    """)

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]


def listar_reposiciones_promocion():
    resultado = db.session.execute(text("""
        SELECT id_promocion,id_presentacion_venta
        FROM promocion_reposicion
        ORDER BY id_promocion,id_presentacion_venta
    """))
    return [dict(fila) for fila in resultado.mappings().all()]