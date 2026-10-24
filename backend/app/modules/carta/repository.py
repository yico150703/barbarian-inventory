from sqlalchemy import text

from app.core.extensions import db


def listar_categorias_carta_detalladas():
    consulta = text("""
        SELECT
            cc.id_categoria_carta,
            cc.nombre,
            cc.prefijo,
            cc.siguiente_numero,
            cc.activo,

            COUNT(DISTINCT ic.id_item_carta)
                AS total_items,

            COUNT(DISTINCT ic.id_item_carta)
                FILTER (WHERE ic.activo = TRUE)
                AS items_activos,

            COUNT(DISTINCT ic.id_item_carta)
                FILTER (WHERE ic.activo = FALSE)
                AS items_inactivos,

            COUNT(DISTINCT pv.id_presentacion_venta)
                AS total_presentaciones,

            COUNT(DISTINCT pv.id_presentacion_venta)
                FILTER (WHERE pv.activo = TRUE)
                AS presentaciones_activas,

            COUNT(DISTINCT pv.id_presentacion_venta)
                FILTER (WHERE pv.activo = FALSE)
                AS presentaciones_inactivas

        FROM categoria_carta AS cc

        LEFT JOIN item_carta AS ic
            ON ic.id_categoria_carta = cc.id_categoria_carta

        LEFT JOIN presentacion_venta AS pv
            ON pv.id_item_carta = ic.id_item_carta

        GROUP BY
            cc.id_categoria_carta,
            cc.nombre,
            cc.prefijo,
            cc.siguiente_numero,
            cc.activo

        ORDER BY cc.nombre ASC
    """)

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]

def listar_presentaciones_venta_detalladas():
    consulta = text("""
        SELECT
            pv.id_presentacion_venta,
            pv.id_item_carta,
            ic.codigo AS codigo_item,
            ic.nombre AS item,
            ic.tipo,
            ic.id_categoria_carta,
            cc.nombre AS categoria,
            pv.id_menaje,
            m.nombre AS menaje,
            pv.contenido,
            pv.unidad,
            pv.precio,
            pv.activo
        FROM presentacion_venta AS pv
        INNER JOIN item_carta AS ic
            ON ic.id_item_carta = pv.id_item_carta
        INNER JOIN categoria_carta AS cc
            ON cc.id_categoria_carta =
                ic.id_categoria_carta
        INNER JOIN menaje AS m
            ON m.id_menaje = pv.id_menaje
        ORDER BY
            cc.nombre ASC,
            ic.nombre ASC,
            pv.contenido ASC,
            pv.precio ASC
    """)

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]


def listar_menajes_detallados():
    consulta = text("""
        SELECT
            m.id_menaje,
            m.nombre,
            m.activo,

            COUNT(pv.id_presentacion_venta)
                AS total_presentaciones,

            COUNT(pv.id_presentacion_venta)
                FILTER (WHERE pv.activo = TRUE)
                AS presentaciones_activas,

            COUNT(pv.id_presentacion_venta)
                FILTER (WHERE pv.activo = FALSE)
                AS presentaciones_inactivas,

            COUNT(DISTINCT pv.id_item_carta)
                AS total_items,

            COALESCE(
                JSONB_AGG(DISTINCT ic.nombre)
                    FILTER (
                        WHERE ic.id_item_carta IS NOT NULL
                    ),
                '[]'::JSONB
            ) AS items

        FROM menaje AS m

        LEFT JOIN presentacion_venta AS pv
            ON pv.id_menaje = m.id_menaje

        LEFT JOIN item_carta AS ic
            ON ic.id_item_carta = pv.id_item_carta

        GROUP BY
            m.id_menaje,
            m.nombre,
            m.activo

        ORDER BY m.nombre ASC
    """)

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]