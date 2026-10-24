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