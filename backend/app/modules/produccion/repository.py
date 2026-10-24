from sqlalchemy import text

from app.core.extensions import db


def listar_subproductos_detallados():
    consulta = text("""
        SELECT
            s.id_subproducto,
            s.codigo,
            s.nombre,
            s.rendimiento,
            s.unidad,
            s.activo,
            s.instruccion,

            COUNT(sd.id_producto)
                AS total_ingredientes,

            COALESCE(
                JSONB_AGG(
                    JSONB_BUILD_OBJECT(
                        'id_producto', p.id_producto,
                        'codigo', p.codigo,
                        'producto', p.nombre,
                        'cantidad', sd.cantidad,
                        'unidad', sd.unidad,
                        'activo', p.activo
                    )
                    ORDER BY p.nombre
                ) FILTER (
                    WHERE sd.id_producto IS NOT NULL
                ),
                '[]'::JSONB
            ) AS ingredientes

        FROM subproducto AS s

        LEFT JOIN subproducto_detalle AS sd
            ON sd.id_subproducto = s.id_subproducto

        LEFT JOIN producto AS p
            ON p.id_producto = sd.id_producto

        GROUP BY
            s.id_subproducto,
            s.codigo,
            s.nombre,
            s.rendimiento,
            s.unidad,
            s.activo

        ORDER BY s.nombre ASC
    """)

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]


def listar_grupos_salsa_detallados():
    consulta = text("""
        SELECT
            gs.id_grupo_salsa,
            gs.id_presentacion_venta,
            gs.cantidad_maxima,
            gs.activo,

            ic.id_item_carta,
            ic.codigo AS codigo_item,
            ic.nombre AS item_carta,
            cc.nombre AS categoria_carta,

            pv.contenido,
            pv.unidad AS unidad_presentacion,
            pv.precio,

            COUNT(gso.id_grupo_salsa)
                AS total_opciones,

            COALESCE(
                JSONB_AGG(
                    JSONB_BUILD_OBJECT(
                        'id_producto',
                            gso.id_producto,

                        'codigo',
                            p.codigo,

                        'producto',
                            CASE
                                WHEN gso.id_producto IS NULL
                                    THEN 'Sin salsa'
                                ELSE p.nombre
                            END,

                        'cantidad',
                            gso.cantidad,

                        'unidad',
                            gso.unidad,

                        'es_sin_salsa',
                            CASE
                                WHEN gso.id_producto IS NULL
                                    THEN TRUE
                                ELSE FALSE
                            END
                    )
                    ORDER BY
                        (
                            gso.id_producto IS NULL
                        ),
                        p.nombre
                )
                FILTER (
                    WHERE gso.id_grupo_salsa IS NOT NULL
                ),
                '[]'::JSONB
            ) AS opciones

        FROM grupo_salsa AS gs

        INNER JOIN presentacion_venta AS pv
            ON pv.id_presentacion_venta =
                gs.id_presentacion_venta

        INNER JOIN item_carta AS ic
            ON ic.id_item_carta =
                pv.id_item_carta

        INNER JOIN categoria_carta AS cc
            ON cc.id_categoria_carta =
                ic.id_categoria_carta

        LEFT JOIN grupo_salsa_opcion AS gso
            ON gso.id_grupo_salsa =
                gs.id_grupo_salsa

        LEFT JOIN producto AS p
            ON p.id_producto =
                gso.id_producto

        GROUP BY
            gs.id_grupo_salsa,
            gs.id_presentacion_venta,
            gs.cantidad_maxima,
            gs.activo,
            ic.id_item_carta,
            ic.codigo,
            ic.nombre,
            cc.nombre,
            pv.contenido,
            pv.unidad,
            pv.precio

        ORDER BY ic.nombre ASC
    """)

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]
