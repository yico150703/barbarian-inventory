from sqlalchemy import text

from app.core.extensions import db


def listar_recetas_detalladas():
    consulta = text("""
        SELECT
            r.id_receta,
            r.id_presentacion_venta,
            r.instrucciones,
            r.activo,

            ic.id_item_carta,
            ic.codigo AS codigo_item,
            ic.nombre AS item_carta,
            ic.tipo AS tipo_item,
            ic.id_categoria_carta,
            cc.nombre AS categoria_carta,

            pv.contenido,
            pv.unidad AS unidad_presentacion,
            pv.precio,
            pv.id_menaje,

            (
                SELECT COUNT(*)
                FROM receta_detalle rd_conteo
                WHERE rd_conteo.id_receta = r.id_receta
            ) AS total_componentes,

            COALESCE(
                (
                    SELECT JSONB_AGG(
                        JSONB_BUILD_OBJECT(
                            'id_receta_detalle', rd.id_receta_detalle,
                            'tipo_componente', rd.tipo_componente,
                            'id_producto', rd.id_producto,
                            'producto_codigo', p.codigo,
                            'producto_nombre', p.nombre,
                            'id_subproducto', rd.id_subproducto,
                            'subproducto_codigo', sp.codigo,
                            'subproducto_nombre', sp.nombre,
                            'cantidad', rd.cantidad,
                            'unidad', rd.unidad
                        )
                        ORDER BY
                            rd.tipo_componente,
                            COALESCE(p.nombre, sp.nombre)
                    )
                    FROM receta_detalle rd
                    LEFT JOIN producto p
                        ON p.id_producto = rd.id_producto
                    LEFT JOIN subproducto sp
                        ON sp.id_subproducto = rd.id_subproducto
                    WHERE rd.id_receta = r.id_receta
                ),
                '[]'::JSONB
            ) AS componentes,

            gs.id_grupo_salsa,
            gs.cantidad_maxima,
            gs.permite_repetir,
            gs.activo AS grupo_salsa_activo,

            COALESCE(
                (
                    SELECT JSONB_AGG(
                        JSONB_BUILD_OBJECT(
                            'id_grupo_salsa_opcion', gso.id_grupo_salsa_opcion,
                            'id_producto', producto_salsa.id_producto,
                            'codigo', producto_salsa.codigo,
                            'nombre', producto_salsa.nombre,
                            'cantidad', gso.cantidad,
                            'unidad', gso.unidad,
                            'activo', gso.activo
                        )
                        ORDER BY producto_salsa.nombre
                    )
                    FROM grupo_salsa_opcion gso
                    INNER JOIN producto producto_salsa
                        ON producto_salsa.id_producto = gso.id_producto
                    WHERE gso.id_grupo_salsa = gs.id_grupo_salsa
                      AND gso.activo = TRUE
                ),
                '[]'::JSONB
            ) AS opciones_salsa

        FROM receta r

        INNER JOIN presentacion_venta pv
            ON pv.id_presentacion_venta = r.id_presentacion_venta

        INNER JOIN item_carta ic
            ON ic.id_item_carta = pv.id_item_carta

        INNER JOIN categoria_carta cc
            ON cc.id_categoria_carta = ic.id_categoria_carta

        LEFT JOIN grupo_salsa gs
            ON gs.id_presentacion_venta = pv.id_presentacion_venta
           AND gs.activo = TRUE

        ORDER BY ic.nombre, pv.contenido
    """)

    resultado = db.session.execute(consulta)
    return [dict(fila) for fila in resultado.mappings().all()]
