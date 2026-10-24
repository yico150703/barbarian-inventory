from sqlalchemy import text

from app.core.local_scope import ejecutar_local, exigir_registro_local
from app.core.stock_local import minimo_del_local


def listar_productos_para_compra():
    from app.modules.inventarios.operativo import instalado
    if instalado():
        return ejecutar_local(text('''SELECT p.id_producto,p.codigo,p.nombre,p.unidad,p.presentacion,
            coalesce(sl.stock_minimo,0) stock_minimo,cp.id_categoria,cp.nombre categoria,
            pr.id_proveedor,pr.nombre proveedor,s.stock_actual,
            coalesce(e.consumo,0) consumo_total
            FROM producto p JOIN categoria_producto cp USING(id_categoria) JOIN proveedor pr USING(id_proveedor)
            JOIN inventario_stock_teorico s ON s.id_producto=p.id_producto AND s.id_local=:id_local_actual
            LEFT JOIN producto_stock_local sl ON sl.id_producto=p.id_producto AND sl.id_local=:id_local_actual
            LEFT JOIN (SELECT id_producto,sum(greatest(-cantidad,0)) consumo FROM inventario_evento
              WHERE id_local=:id_local_actual AND registrado_en>=clock_timestamp()-interval '30 days'
              GROUP BY id_producto) e ON e.id_producto=p.id_producto
            WHERE p.activo AND cp.activo AND pr.activo ORDER BY cp.nombre,p.nombre''')).mappings().all()
    minimo_local, parametros = minimo_del_local()
    consulta = text(f"""
        WITH fecha_referencia AS (
            -- Obtiene la fecha de la última orden enviada/recepcionada o la última recepción
            SELECT COALESCE(
                (
                    SELECT MAX(fecha_registro)
                    FROM (SELECT * FROM orden_compra WHERE id_local=:id_local_actual) orden_compra
                    WHERE estado_orden_compra IN ('ENVIADA', 'RECEPCIONADA', 'RECEPCION_PARCIAL')
                ),
                (
                    SELECT MIN(fecha_recepcion)
                    FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=:id_local_actual) factura_recepcion
                ),
                CURRENT_DATE
            ) AS fecha_inicio
        ),
        ultimo_inventario AS (
            -- Obtiene la fecha del último inventario de cierre registrado
            SELECT MAX(fecha_inventario) AS fecha_fin
            FROM (SELECT * FROM inventario_cierre WHERE id_local=:id_local_actual) inventario_cierre
            WHERE estado_inventario = 'CERRADO'
              AND fecha_inventario <= CURRENT_DATE
        ),
        consumo_calculado AS (
            -- Calcula todo lo movido (consumo) entre el lapso definido
            SELECT
                p.id_producto,
                COALESCE(inv_inicio.stock_contado, 0) AS stock_inicial,
                COALESCE(inv_fin.stock_contado, 0) AS stock_final,
                COALESCE(recepciones.cantidad_recibida, 0) AS entradas_compras,
                COALESCE(mov.entradas, 0) AS entradas_movimientos,
                COALESCE(mov.salidas, 0) AS salidas_movimientos,
                
                -- Consumo total transcurrido = (Stock Inicial + Entradas Compras + Entradas Movs) - (Stock Final + Salidas Movs)
                GREATEST(
                    0,
                    (COALESCE(inv_inicio.stock_contado, 0) + COALESCE(recepciones.cantidad_recibida, 0) + COALESCE(mov.entradas, 0)) 
                    - (COALESCE(inv_fin.stock_contado, 0) + COALESCE(mov.salidas, 0))
                ) AS consumo_total
            FROM producto p
            CROSS JOIN fecha_referencia fr
            CROSS JOIN ultimo_inventario ui
            -- Stock según el primer inventario del período
            LEFT JOIN LATERAL (
                SELECT icd.stock_contado
                FROM inventario_cierre_detalle icd
                JOIN (SELECT * FROM inventario_cierre WHERE id_local=:id_local_actual) ic ON ic.id_inventario_cierre = icd.id_inventario_cierre
                WHERE icd.id_producto = p.id_producto
                  AND ic.estado_inventario = 'CERRADO'
                  AND ic.fecha_inventario <= fr.fecha_inicio
                ORDER BY ic.fecha_inventario DESC
                LIMIT 1
            ) inv_inicio ON TRUE
            -- Stock según el último inventario de cierre registrado
            LEFT JOIN LATERAL (
                SELECT icd.stock_contado
                FROM inventario_cierre_detalle icd
                JOIN (SELECT * FROM inventario_cierre WHERE id_local=:id_local_actual) ic ON ic.id_inventario_cierre = icd.id_inventario_cierre
                WHERE icd.id_producto = p.id_producto
                  AND ic.estado_inventario = 'CERRADO'
                  AND ic.fecha_inventario = ui.fecha_fin
                ORDER BY icd.id_inventario_cierre DESC
                LIMIT 1
            ) inv_fin ON TRUE
            -- Entradas por compras en el período
            LEFT JOIN LATERAL (
                SELECT SUM(frd.cantidad_recibida) AS cantidad_recibida
                FROM factura_recepcion_detalle frd
                JOIN (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=:id_local_actual) f ON f.id_factura_recepcion = frd.id_factura_recepcion
                WHERE frd.id_producto = p.id_producto
                  AND f.fecha_recepcion > fr.fecha_inicio
                  AND f.fecha_recepcion <= ui.fecha_fin
            ) recepciones ON TRUE
            -- Entradas y salidas manuales de inventario en el período
            LEFT JOIN LATERAL (
                SELECT
                    SUM(CASE WHEN mi.tipo_movimiento = 'ENTRADA' THEN mid.cantidad ELSE 0 END) AS entradas,
                    SUM(CASE WHEN mi.tipo_movimiento = 'SALIDA' THEN mid.cantidad ELSE 0 END) AS salidas
                FROM movimiento_inventario_detalle mid
                JOIN (SELECT * FROM movimiento_inventario WHERE id_local=:id_local_actual) mi ON mi.id_movimiento_inventario = mid.id_movimiento_inventario
                WHERE mid.id_producto = p.id_producto
                  AND mi.fecha_movimiento > fr.fecha_inicio
                  AND mi.fecha_movimiento <= ui.fecha_fin
            ) mov ON TRUE
        )
        SELECT
            p.id_producto,
            p.codigo,
            p.nombre,
            p.unidad,
            p.presentacion,
            {minimo_local} AS stock_minimo,
            cp.id_categoria,
            cp.nombre AS categoria,
            pr.id_proveedor,
            pr.nombre AS proveedor,
            cc.stock_final AS stock_actual,
            cc.consumo_total
        FROM producto p
        JOIN categoria_producto cp ON cp.id_categoria = p.id_categoria
        JOIN proveedor pr ON pr.id_proveedor = p.id_proveedor
        LEFT JOIN consumo_calculado cc ON cc.id_producto = p.id_producto
        WHERE p.activo = TRUE
          AND cp.activo = TRUE
          AND pr.activo = TRUE
        ORDER BY cp.nombre, p.nombre
    """)
    return ejecutar_local(consulta, parametros).mappings().all()


def producto_activo_existe(id_producto):
    return bool(ejecutar_local(
        text("""
            SELECT EXISTS (
                SELECT 1
                FROM producto
                WHERE id_producto = :id_producto
                  AND activo = TRUE
            )
        """),
        {"id_producto": id_producto},
    ).scalar())


def generar_codigo_orden():
    ejecutar_local(text("""
        SELECT pg_advisory_xact_lock(
            hashtext('orden_compra_codigo')
        )
    """))
    numero = int(ejecutar_local(text("""
        SELECT COALESCE(MAX(
            CASE
                WHEN codigo ~ '^OC-[0-9]+$'
                THEN SUBSTRING(codigo FROM 4)::INTEGER
                ELSE 0
            END
        ), 0) + 1
        FROM orden_compra
    """)).scalar() or 1)
    return f"OC-{numero:03d}"


def crear_cabecera_orden(codigo, estado, id_usuario, fecha_registro):
    return ejecutar_local(
        text("""
            INSERT INTO orden_compra (
                id_local,
                codigo,
                estado_orden_compra,
                usuario_registro,
                fecha_registro
            ) VALUES (
                :id_local_actual,
                :codigo,
                :estado,
                :id_usuario,
                :fecha_registro
            )
            RETURNING id_orden_compra
        """),
        {
            "codigo": codigo,
            "estado": estado,
            "id_usuario": id_usuario,
            "fecha_registro": fecha_registro,
        },
    ).scalar_one()


def crear_detalle_orden(id_orden, id_producto, cantidad_solicitada):
    exigir_registro_local("orden", id_orden)
    ejecutar_local(
        text("""
            INSERT INTO orden_compra_detalle (
                id_proveedor,
                id_orden_compra,
                id_producto,
                cantidad_solicitada
            ) VALUES (
                (SELECT id_proveedor FROM producto WHERE id_producto=:id_producto),
                :id_orden,
                :id_producto,
                :cantidad
            )
        """),
        {
            "id_orden": id_orden,
            "id_producto": id_producto,
            "cantidad": cantidad_solicitada,
        },
    )


def listar_historial_ordenes(
    fecha_desde=None,
    fecha_hasta=None,
    estado=None,
):
    consulta = text("""
        WITH recibido_por_producto AS (
            SELECT
                fr.id_orden_compra,
                frd.id_producto,
                SUM(frd.cantidad_recibida) AS cantidad_recibida
            FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=:id_local_actual) fr
            JOIN factura_recepcion_detalle frd
                ON frd.id_factura_recepcion =
                   fr.id_factura_recepcion
            GROUP BY
                fr.id_orden_compra,
                frd.id_producto
        ),
        avance_por_orden AS (
            SELECT
                ocd.id_orden_compra,
                COUNT(*) AS total_productos,
                COUNT(*) FILTER (
                    WHERE COALESCE(rpp.cantidad_recibida, 0) > 0
                ) AS productos_con_recepcion,
                COUNT(*) FILTER (
                    WHERE COALESCE(rpp.cantidad_recibida, 0)
                          >= ocd.cantidad_solicitada
                ) AS productos_completos,
                COUNT(*) FILTER (
                    WHERE COALESCE(rpp.cantidad_recibida, 0)
                          < ocd.cantidad_solicitada
                ) AS productos_pendientes
            FROM orden_compra_detalle ocd
            LEFT JOIN recibido_por_producto rpp
                ON rpp.id_orden_compra = ocd.id_orden_compra
               AND rpp.id_producto = ocd.id_producto
            GROUP BY ocd.id_orden_compra
        )
        SELECT
            oc.id_orden_compra,
            oc.codigo,
            oc.estado_orden_compra,
            oc.fecha_registro,
            CONCAT_WS(
                ' ',
                u.nombres,
                u.apellido_paterno,
                u.apellido_materno
            ) AS registrado_por,
            COALESCE(apo.total_productos, 0)
                AS total_productos,
            COALESCE(apo.productos_con_recepcion, 0)
                AS productos_con_recepcion,
            COALESCE(apo.productos_completos, 0)
                AS productos_completos,
            COALESCE(apo.productos_pendientes, 0)
                AS productos_pendientes,
            oc.motivo_cierre,
            oc.fecha_modificacion,
            NULLIF(BTRIM(CONCAT_WS(
                ' ',
                um.nombres,
                um.apellido_paterno,
                um.apellido_materno
            )), '') AS modificado_por
        FROM (SELECT * FROM orden_compra WHERE id_local=:id_local_actual) oc
        JOIN usuario u
            ON u.id_usuario = oc.usuario_registro
        LEFT JOIN usuario um
            ON um.id_usuario = oc.usuario_modificacion
        LEFT JOIN avance_por_orden apo
            ON apo.id_orden_compra = oc.id_orden_compra
        WHERE (
            CAST(:fecha_desde AS DATE) IS NULL
            OR oc.fecha_registro >= CAST(:fecha_desde AS DATE)
        )
          AND (
            CAST(:fecha_hasta AS DATE) IS NULL
            OR oc.fecha_registro <= CAST(:fecha_hasta AS DATE)
          )
          AND (
            CAST(:estado AS VARCHAR) IS NULL
            OR oc.estado_orden_compra = CAST(:estado AS VARCHAR)
          )
        ORDER BY
            oc.fecha_registro DESC NULLS LAST,
            oc.id_orden_compra DESC
    """)

    return ejecutar_local(
        consulta,
        {
            "fecha_desde": fecha_desde,
            "fecha_hasta": fecha_hasta,
            "estado": estado,
        },
    ).mappings().all()


def obtener_detalle_orden_historial(id_orden):
    exigir_registro_local("orden", id_orden)
    consulta = text("""
        SELECT
            ocd.id_orden_compra_detalle,
            p.id_producto,
            p.codigo,
            p.nombre,
            p.unidad,
            pr.id_proveedor,
            pr.nombre AS proveedor,
            ocd.cantidad_solicitada,
            COALESCE((
                SELECT SUM(frd.cantidad_recibida)
                FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=:id_local_actual) fr
                JOIN factura_recepcion_detalle frd
                    ON frd.id_factura_recepcion =
                       fr.id_factura_recepcion
                WHERE fr.id_orden_compra = ocd.id_orden_compra
                  AND frd.id_producto = ocd.id_producto
            ), 0) AS cantidad_recibida,
            GREATEST(
                ocd.cantidad_solicitada - COALESCE((
                    SELECT SUM(frd.cantidad_recibida)
                    FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=:id_local_actual) fr
                    JOIN factura_recepcion_detalle frd
                        ON frd.id_factura_recepcion =
                           fr.id_factura_recepcion
                    WHERE fr.id_orden_compra = ocd.id_orden_compra
                      AND frd.id_producto = ocd.id_producto
                ), 0),
                0
            ) AS cantidad_pendiente
        FROM orden_compra_detalle ocd
        JOIN producto p
            ON p.id_producto = ocd.id_producto
        JOIN proveedor pr
            ON pr.id_proveedor = ocd.id_proveedor
        WHERE ocd.id_orden_compra = :id_orden
        ORDER BY pr.nombre, p.nombre
    """)
    return ejecutar_local(
        consulta,
        {"id_orden": id_orden},
    ).mappings().all()


def obtener_orden_historial(id_orden, bloquear=False):
    exigir_registro_local("orden", id_orden)
    bloqueo = "FOR UPDATE" if bloquear else ""
    consulta = text(f"""
        SELECT
            id_orden_compra,
            codigo,
            estado_orden_compra,
            fecha_registro,
            motivo_cierre
        FROM (SELECT * FROM orden_compra WHERE id_local=:id_local_actual) orden_compra
        WHERE id_orden_compra = :id_orden
        {bloqueo}
    """)
    return ejecutar_local(
        consulta,
        {"id_orden": id_orden},
    ).mappings().first()


def obtener_total_recibido_orden(id_orden):
    exigir_registro_local("orden", id_orden)
    consulta = text("""
        SELECT COALESCE(SUM(frd.cantidad_recibida), 0)
        FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=:id_local_actual) fr
        JOIN factura_recepcion_detalle frd
            ON frd.id_factura_recepcion = fr.id_factura_recepcion
        WHERE fr.id_orden_compra = :id_orden
    """)
    return ejecutar_local(
        consulta,
        {"id_orden": id_orden},
    ).scalar()


def guardar_historial_estado_orden(
    id_orden,
    estado_anterior,
    estado_nuevo,
    motivo,
    id_usuario,
):
    exigir_registro_local("orden", id_orden)
    ejecutar_local(
        text("""
            INSERT INTO orden_compra_estado_historial (
                id_orden_compra,
                estado_anterior,
                estado_nuevo,
                motivo,
                usuario_modificacion
            ) VALUES (
                :id_orden,
                :estado_anterior,
                :estado_nuevo,
                :motivo,
                :id_usuario
            )
        """),
        {
            "id_orden": id_orden,
            "estado_anterior": estado_anterior,
            "estado_nuevo": estado_nuevo,
            "motivo": motivo,
            "id_usuario": id_usuario,
        },
    )


def cambiar_estado_orden_historial(
    id_orden,
    estado,
    motivo,
    id_usuario,
):
    exigir_registro_local("orden", id_orden)
    ejecutar_local(
        text("""
            UPDATE orden_compra
            SET estado_orden_compra = :estado,
                motivo_cierre = :motivo,
                usuario_modificacion = :id_usuario,
                fecha_modificacion = (
                    CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima'
                )
            WHERE id_orden_compra = :id_orden
        """),
        {
            "id_orden": id_orden,
            "estado": estado,
            "motivo": motivo,
            "id_usuario": id_usuario,
        },
    )

