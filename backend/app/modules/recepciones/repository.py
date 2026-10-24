from sqlalchemy import text

from app.core.local_scope import ejecutar_local, exigir_registro_local


def listar_pendientes_recepcion():
    consulta = text("""
        WITH recibido AS (
            SELECT
                fr.id_orden_compra,
                fr.id_proveedor,
                frd.id_producto,
                SUM(frd.cantidad_recibida) AS cantidad_recibida
            FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=:id_local_actual) fr
            JOIN factura_recepcion_detalle frd
                ON frd.id_factura_recepcion = fr.id_factura_recepcion
            GROUP BY
                fr.id_orden_compra,
                fr.id_proveedor,
                frd.id_producto
        )
        SELECT
            oc.id_orden_compra,
            oc.codigo AS codigo_orden,
            oc.estado_orden_compra,
            oc.fecha_registro,
            pr.id_proveedor,
            pr.nombre AS proveedor,
            p.id_producto,
            p.codigo AS codigo_producto,
            p.nombre AS producto,
            cp.nombre AS categoria,
            p.unidad,
            p.presentacion,
            ocd.cantidad_solicitada,
            COALESCE(r.cantidad_recibida, 0) AS cantidad_recibida,
            GREATEST(
                ocd.cantidad_solicitada
                - COALESCE(r.cantidad_recibida, 0),
                0
            ) AS cantidad_pendiente
        FROM (SELECT * FROM orden_compra WHERE id_local=:id_local_actual) oc
        JOIN orden_compra_detalle ocd
            ON ocd.id_orden_compra = oc.id_orden_compra
        JOIN producto p
            ON p.id_producto = ocd.id_producto
        JOIN categoria_producto cp
            ON cp.id_categoria = p.id_categoria
        JOIN proveedor pr
            ON pr.id_proveedor = ocd.id_proveedor
        LEFT JOIN recibido r
            ON r.id_orden_compra = oc.id_orden_compra
           AND r.id_proveedor = pr.id_proveedor
           AND r.id_producto = p.id_producto
        WHERE oc.estado_orden_compra IN (
            'ENVIADA',
            'RECEPCION_PARCIAL'
        )
          AND ocd.cantidad_solicitada
              > COALESCE(r.cantidad_recibida, 0)
        ORDER BY
            oc.fecha_registro,
            oc.codigo,
            pr.nombre,
            p.nombre
    """)

    return ejecutar_local(consulta).mappings().all()


def bloquear_orden(id_orden):
    exigir_registro_local("orden", id_orden)
    consulta = text("""
        SELECT
            id_orden_compra,
            codigo,
            estado_orden_compra
        FROM (SELECT * FROM orden_compra WHERE id_local=:id_local_actual) orden_compra
        WHERE id_orden_compra = :id_orden
        FOR UPDATE
    """)
    return ejecutar_local(
        consulta,
        {"id_orden": id_orden},
    ).mappings().first()


def obtener_producto_pendiente(
    id_orden,
    id_proveedor,
    id_producto,
):
    exigir_registro_local("orden", id_orden)
    consulta = text("""
        SELECT
            p.id_producto,
            p.codigo,
            p.nombre,
            p.unidad,
            ocd.cantidad_solicitada,
            COALESCE((
                SELECT SUM(frd.cantidad_recibida)
                FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=:id_local_actual) fr
                JOIN factura_recepcion_detalle frd
                    ON frd.id_factura_recepcion = fr.id_factura_recepcion
                WHERE fr.id_orden_compra = oc.id_orden_compra
                  AND fr.id_proveedor = :id_proveedor
                  AND frd.id_producto = p.id_producto
            ), 0) AS cantidad_recibida
        FROM (SELECT * FROM orden_compra WHERE id_local=:id_local_actual) oc
        JOIN orden_compra_detalle ocd
            ON ocd.id_orden_compra = oc.id_orden_compra
        JOIN producto p
            ON p.id_producto = ocd.id_producto
        WHERE oc.id_orden_compra = :id_orden
          AND p.id_producto = :id_producto
          AND ocd.id_proveedor = :id_proveedor
        FOR UPDATE OF ocd
    """)
    return ejecutar_local(
        consulta,
        {
            "id_orden": id_orden,
            "id_proveedor": id_proveedor,
            "id_producto": id_producto,
        },
    ).mappings().first()


def factura_duplicada(id_proveedor, numero_factura):
    consulta = text("""
        SELECT EXISTS (
            SELECT 1
            FROM factura_recepcion
            WHERE id_proveedor = :id_proveedor
              AND UPPER(numero_factura) = UPPER(:numero_factura)
        )
    """)
    return bool(ejecutar_local(
        consulta,
        {
            "id_proveedor": id_proveedor,
            "numero_factura": numero_factura,
        },
    ).scalar())


def crear_factura_recepcion(
    id_orden,
    id_proveedor,
    numero_factura,
    fecha_recepcion,
    id_usuario,
):
    exigir_registro_local("orden", id_orden)
    consulta = text("""
        INSERT INTO factura_recepcion (
            id_orden_compra,
            id_proveedor,
            numero_factura,
            fecha_recepcion,
            usuario_recepcion
        ) VALUES (
            :id_orden,
            :id_proveedor,
            :numero_factura,
            :fecha_recepcion,
            :id_usuario
        )
        RETURNING id_factura_recepcion
    """)
    return ejecutar_local(
        consulta,
        {
            "id_orden": id_orden,
            "id_proveedor": id_proveedor,
            "numero_factura": numero_factura,
            "fecha_recepcion": fecha_recepcion,
            "id_usuario": id_usuario,
        },
    ).scalar_one()


def crear_detalle_recepcion(
    id_factura,
    id_producto,
    cantidad,
):
    exigir_registro_local("factura", id_factura)
    ejecutar_local(
        text("""
            INSERT INTO factura_recepcion_detalle (
                id_factura_recepcion,
                id_producto,
                cantidad_recibida
            ) VALUES (
                :id_factura,
                :id_producto,
                :cantidad
            )
        """),
        {
            "id_factura": id_factura,
            "id_producto": id_producto,
            "cantidad": cantidad,
        },
    )


def orden_tiene_cantidades_pendientes(id_orden):
    exigir_registro_local("orden", id_orden)
    consulta = text("""
        SELECT EXISTS (
            SELECT 1
            FROM orden_compra_detalle ocd
            JOIN producto p
                ON p.id_producto = ocd.id_producto
            WHERE ocd.id_orden_compra = :id_orden
              AND ocd.cantidad_solicitada > COALESCE((
                  SELECT SUM(frd.cantidad_recibida)
                  FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=:id_local_actual) fr
                  JOIN factura_recepcion_detalle frd
                      ON frd.id_factura_recepcion = fr.id_factura_recepcion
                  WHERE fr.id_orden_compra = ocd.id_orden_compra
                    AND fr.id_proveedor = ocd.id_proveedor
                    AND frd.id_producto = ocd.id_producto
              ), 0)
        )
    """)
    return bool(ejecutar_local(
        consulta,
        {"id_orden": id_orden},
    ).scalar())


def actualizar_estado_orden(id_orden, estado):
    exigir_registro_local("orden", id_orden)
    ejecutar_local(
        text("""
            UPDATE orden_compra
            SET estado_orden_compra = :estado
            WHERE id_orden_compra = :id_orden
        """),
        {"id_orden": id_orden, "estado": estado},
    )


def listar_historial_recepciones(
    fecha_desde=None,
    fecha_hasta=None,
    id_proveedor=None,
):
    consulta = text("""
        SELECT
            fr.id_factura_recepcion,
            fr.id_orden_compra,
            oc.codigo AS codigo_orden,
            oc.estado_orden_compra,
            fr.numero_factura,
            fr.fecha_recepcion,
            fr.id_proveedor,
            pr.nombre AS proveedor,
            CONCAT_WS(
                ' ',
                u.nombres,
                u.apellido_paterno,
                u.apellido_materno
            ) AS recibido_por,
            COUNT(frd.id_factura_recepcion_detalle)
                AS productos_recibidos,
            COALESCE(SUM(frd.cantidad_recibida), 0)
                AS cantidad_total
        FROM factura_recepcion fr
        JOIN orden_compra oc
            ON oc.id_orden_compra = fr.id_orden_compra
        JOIN proveedor pr
            ON pr.id_proveedor = fr.id_proveedor
        JOIN usuario u
            ON u.id_usuario = fr.usuario_recepcion
        JOIN factura_recepcion_detalle frd
            ON frd.id_factura_recepcion = fr.id_factura_recepcion
        WHERE oc.id_local=:id_local_actual AND (
            CAST(:fecha_desde AS DATE) IS NULL
            OR fr.fecha_recepcion >= CAST(:fecha_desde AS DATE)
        )
          AND (
            CAST(:fecha_hasta AS DATE) IS NULL
            OR fr.fecha_recepcion <= CAST(:fecha_hasta AS DATE)
          )
          AND (
            CAST(:id_proveedor AS INTEGER) IS NULL
            OR fr.id_proveedor = CAST(:id_proveedor AS INTEGER)
          )
        GROUP BY
            fr.id_factura_recepcion,
            oc.id_orden_compra,
            pr.id_proveedor,
            u.id_usuario
        ORDER BY
            fr.fecha_recepcion DESC,
            fr.id_factura_recepcion DESC
    """)
    return ejecutar_local(
        consulta,
        {
            "fecha_desde": fecha_desde,
            "fecha_hasta": fecha_hasta,
            "id_proveedor": id_proveedor,
        },
    ).mappings().all()


def obtener_factura_recepcion(id_factura, bloquear=False):
    exigir_registro_local("factura", id_factura)
    if bloquear:
        orden = ejecutar_local(text("SELECT id_orden_compra FROM factura_recepcion WHERE id_factura_recepcion=:id"), {"id": id_factura}).scalar_one()
        bloquear_orden(orden)
    bloqueo = "FOR UPDATE OF fr" if bloquear else ""
    consulta = text(f"""
        SELECT
            fr.id_factura_recepcion,
            fr.id_orden_compra,
            oc.codigo AS codigo_orden,
            oc.estado_orden_compra,
            fr.id_proveedor,
            pr.nombre AS proveedor,
            fr.numero_factura,
            fr.fecha_recepcion,
            CONCAT_WS(
                ' ',
                u.nombres,
                u.apellido_paterno,
                u.apellido_materno
            ) AS recibido_por
        FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=:id_local_actual) fr
        JOIN (SELECT * FROM orden_compra WHERE id_local=:id_local_actual) oc
            ON oc.id_orden_compra = fr.id_orden_compra
        JOIN proveedor pr
            ON pr.id_proveedor = fr.id_proveedor
        JOIN usuario u
            ON u.id_usuario = fr.usuario_recepcion
        WHERE fr.id_factura_recepcion = :id_factura
        {bloqueo}
    """)
    return ejecutar_local(
        consulta,
        {"id_factura": id_factura},
    ).mappings().first()


def listar_detalles_factura(id_factura):
    exigir_registro_local("factura", id_factura)
    consulta = text("""
        SELECT
            frd.id_factura_recepcion_detalle,
            frd.id_producto,
            p.codigo,
            p.nombre,
            p.unidad,
            frd.cantidad_recibida,
            ocd.cantidad_solicitada,
            COALESCE((
                SELECT SUM(otra.cantidad_recibida)
                FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=:id_local_actual) otra_fr
                JOIN factura_recepcion_detalle otra
                    ON otra.id_factura_recepcion =
                       otra_fr.id_factura_recepcion
                WHERE otra_fr.id_orden_compra = fr.id_orden_compra
                  AND otra.id_producto = frd.id_producto
                  AND otra_fr.id_factura_recepcion <>
                      fr.id_factura_recepcion
            ), 0) AS recibido_otras_facturas
        FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=:id_local_actual) fr
        JOIN factura_recepcion_detalle frd
            ON frd.id_factura_recepcion = fr.id_factura_recepcion
        JOIN producto p
            ON p.id_producto = frd.id_producto
        JOIN orden_compra_detalle ocd
            ON ocd.id_orden_compra = fr.id_orden_compra
           AND ocd.id_producto = frd.id_producto
        WHERE fr.id_factura_recepcion = :id_factura
        ORDER BY p.nombre
    """)
    return ejecutar_local(
        consulta,
        {"id_factura": id_factura},
    ).mappings().all()


def factura_duplicada_excepto(
    id_proveedor,
    numero_factura,
    id_factura,
):
    exigir_registro_local("factura", id_factura)
    consulta = text("""
        SELECT EXISTS (
            SELECT 1
            FROM factura_recepcion
            WHERE id_proveedor = :id_proveedor
              AND UPPER(numero_factura) = UPPER(:numero_factura)
              AND id_factura_recepcion <> :id_factura
        )
    """)
    return bool(ejecutar_local(
        consulta,
        {
            "id_proveedor": id_proveedor,
            "numero_factura": numero_factura,
            "id_factura": id_factura,
        },
    ).scalar())


def actualizar_factura_recepcion(
    id_factura,
    numero_factura,
    fecha_recepcion,
):
    exigir_registro_local("factura", id_factura)
    ejecutar_local(
        text("""
            UPDATE factura_recepcion
            SET numero_factura = :numero_factura,
                fecha_recepcion = :fecha_recepcion
            WHERE id_factura_recepcion = :id_factura
        """),
        {
            "id_factura": id_factura,
            "numero_factura": numero_factura,
            "fecha_recepcion": fecha_recepcion,
        },
    )


def actualizar_cantidad_recepcion(id_detalle, cantidad):
    exigir_registro_local("detalle_recepcion", id_detalle)
    ejecutar_local(
        text("""
            UPDATE factura_recepcion_detalle
            SET cantidad_recibida = :cantidad
            WHERE id_factura_recepcion_detalle = :id_detalle
        """),
        {
            "id_detalle": id_detalle,
            "cantidad": cantidad,
        },
    )


def crear_historial_factura(
    id_factura,
    numero_anterior,
    numero_nuevo,
    fecha_anterior,
    fecha_nueva,
    id_usuario,
    motivo,
    observacion,
):
    exigir_registro_local("factura", id_factura)
    consulta = text("""
        INSERT INTO factura_recepcion_historial (
            id_factura_recepcion,
            numero_factura_anterior,
            numero_factura_nuevo,
            fecha_recepcion_anterior,
            fecha_recepcion_nueva,
            usuario_correccion,
            motivo_correccion,
            observacion
        ) VALUES (
            :id_factura,
            :numero_anterior,
            :numero_nuevo,
            :fecha_anterior,
            :fecha_nueva,
            :id_usuario,
            :motivo,
            :observacion
        )
        RETURNING id_factura_recepcion_historial
    """)
    return ejecutar_local(
        consulta,
        {
            "id_factura": id_factura,
            "numero_anterior": numero_anterior,
            "numero_nuevo": numero_nuevo,
            "fecha_anterior": fecha_anterior,
            "fecha_nueva": fecha_nueva,
            "id_usuario": id_usuario,
            "motivo": motivo,
            "observacion": observacion,
        },
    ).scalar_one()


def crear_historial_detalle(
    id_historial,
    id_producto,
    cantidad_anterior,
    cantidad_nueva,
):
    exigir_registro_local("historial_factura", id_historial)
    ejecutar_local(
        text("""
            INSERT INTO factura_recepcion_detalle_historial (
                id_factura_recepcion_historial,
                id_producto,
                cantidad_anterior,
                cantidad_nueva
            ) VALUES (
                :id_historial,
                :id_producto,
                :cantidad_anterior,
                :cantidad_nueva
            )
        """),
        {
            "id_historial": id_historial,
            "id_producto": id_producto,
            "cantidad_anterior": cantidad_anterior,
            "cantidad_nueva": cantidad_nueva,
        },
    )


def calcular_totales_orden(id_orden):
    exigir_registro_local("orden", id_orden)
    consulta = text("""
        SELECT
            COALESCE((
                SELECT SUM(cantidad_solicitada)
                FROM orden_compra_detalle
                WHERE id_orden_compra = :id_orden
            ), 0) AS total_solicitado,
            COALESCE((
                SELECT SUM(frd.cantidad_recibida)
                FROM (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=:id_local_actual) fr
                JOIN factura_recepcion_detalle frd
                    ON frd.id_factura_recepcion =
                       fr.id_factura_recepcion
                WHERE fr.id_orden_compra = :id_orden
            ), 0) AS total_recibido
    """)
    return ejecutar_local(
        consulta,
        {"id_orden": id_orden},
    ).mappings().one()
