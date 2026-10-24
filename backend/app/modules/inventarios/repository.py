from sqlalchemy import text

from app.core.local_scope import ejecutar_local, exigir_registro_local
from app.core.stock_local import minimo_del_local


def contar_productos_activos():
    consulta = text("""
        SELECT COUNT(*) AS total
        FROM producto
        WHERE activo = TRUE
    """)

    resultado = ejecutar_local(consulta).mappings().first()

    return int(resultado["total"] or 0)


def buscar_inventario_de_hoy():
    consulta = text("""
        SELECT
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.usuario_registro,
            ic.fecha_registro,
            ic.observacion,
            COUNT(icd.id_inventario_cierre_detalle) AS productos_contados,
            CONCAT(
                u.nombres,
                ' ',
                u.apellido_paterno
            ) AS usuario
        FROM (SELECT * FROM inventario_cierre WHERE id_local=:id_local_actual) ic
        LEFT JOIN inventario_cierre_detalle icd
            ON icd.id_inventario_cierre =
               ic.id_inventario_cierre
        LEFT JOIN usuario u
            ON u.id_usuario = ic.usuario_registro
        WHERE ic.fecha_inventario = CURRENT_DATE
        GROUP BY
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.usuario_registro,
            ic.fecha_registro,
            ic.observacion,
            u.nombres,
            u.apellido_paterno
        ORDER BY ic.id_inventario_cierre DESC
        LIMIT 1
    """)

    return ejecutar_local(consulta).mappings().first()


def buscar_ultimo_inventario_cerrado():
    consulta = text("""
        SELECT
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.usuario_registro,
            ic.fecha_registro,
            ic.observacion,
            COUNT(icd.id_inventario_cierre_detalle) AS productos_contados,
            CONCAT(
                u.nombres,
                ' ',
                u.apellido_paterno
            ) AS usuario
        FROM (SELECT * FROM inventario_cierre WHERE id_local=:id_local_actual) ic
        LEFT JOIN inventario_cierre_detalle icd
            ON icd.id_inventario_cierre =
               ic.id_inventario_cierre
        LEFT JOIN usuario u
            ON u.id_usuario = ic.usuario_registro
        WHERE ic.estado_inventario = 'CERRADO'
        GROUP BY
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.usuario_registro,
            ic.fecha_registro,
            ic.observacion,
            u.nombres,
            u.apellido_paterno
        ORDER BY
            ic.fecha_inventario DESC,
            ic.id_inventario_cierre DESC
        LIMIT 1
    """)

    return ejecutar_local(consulta).mappings().first()


def buscar_ultimos_inventarios(limite=5):
    consulta = text("""
        SELECT
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.fecha_registro,
            ic.observacion,
            COUNT(
                icd.id_inventario_cierre_detalle
            ) AS productos_contados,
            CONCAT(
                u.nombres,
                ' ',
                u.apellido_paterno
            ) AS usuario
        FROM (SELECT * FROM inventario_cierre WHERE id_local=:id_local_actual) ic
        LEFT JOIN inventario_cierre_detalle icd
            ON icd.id_inventario_cierre =
               ic.id_inventario_cierre
        LEFT JOIN usuario u
            ON u.id_usuario = ic.usuario_registro
        WHERE ic.fecha_inventario <= CURRENT_DATE
        GROUP BY
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.fecha_registro,
            ic.observacion,
            u.nombres,
            u.apellido_paterno
        ORDER BY
            ic.fecha_inventario DESC,
            ic.id_inventario_cierre DESC
        LIMIT :limite
    """)

    return ejecutar_local(
        consulta,
        {"limite": limite}
    ).mappings().all()


def consultar_stock_actual():
    from app.modules.inventarios.operativo import instalado
    if instalado():
        return ejecutar_local(text('''SELECT p.id_producto,p.codigo,p.nombre,p.unidad,p.id_categoria,cp.nombre categoria,
            coalesce(sl.stock_minimo,0) stock_minimo,sl.stock_maximo,
            (b.creado_en AT TIME ZONE 'America/Lima')::date fecha_ultimo_conteo,
            s.inicial stock_ultimo_conteo,s.stock_actual,
            coalesce(e.recepciones,0) entradas_recepcion,coalesce(e.entradas,0) entradas_movimiento,
            coalesce(e.salidas,0) salidas_movimiento,
            CASE WHEN s.stock_actual<=0 THEN 'AGOTADO' WHEN s.stock_actual<=coalesce(sl.stock_minimo,0)
              THEN 'STOCK_BAJO' ELSE 'DISPONIBLE' END estado_stock
            FROM inventario_stock_teorico s JOIN producto p USING(id_producto) JOIN categoria_producto cp USING(id_categoria)
            LEFT JOIN producto_stock_local sl ON sl.id_producto=p.id_producto AND sl.id_local=s.id_local
            LEFT JOIN inventario_saldo_inicial b ON b.id_producto=p.id_producto AND b.id_local=s.id_local
            LEFT JOIN (SELECT id_producto,sum(CASE WHEN origen='RECEPCION' THEN cantidad ELSE 0 END) recepciones,
              sum(CASE WHEN origen='MOVIMIENTO' THEN greatest(cantidad,0) ELSE 0 END) entradas,
              sum(CASE WHEN origen='MOVIMIENTO' THEN greatest(-cantidad,0) ELSE 0 END) salidas
              FROM inventario_evento WHERE id_local=:id_local_actual GROUP BY id_producto) e ON e.id_producto=p.id_producto
            WHERE s.id_local=:id_local_actual AND p.activo AND cp.activo ORDER BY cp.nombre,p.nombre''')).mappings().all()
    minimo_local, parametros = minimo_del_local()
    consulta = text(f"""
        WITH stock_calculado AS (
            SELECT
                p.id_producto,
                p.codigo,
                p.nombre,
                p.unidad,
                {minimo_local} AS stock_minimo,
                p.id_categoria,
                cp.nombre AS categoria,

                ultimo_conteo.fecha_inventario
                    AS fecha_ultimo_conteo,

                ultimo_conteo.stock_contado
                    AS stock_ultimo_conteo,

                COALESCE(
                    recepciones.cantidad,
                    0
                ) AS entradas_recepcion,

                COALESCE(
                    movimientos.entradas,
                    0
                ) AS entradas_movimiento,

                COALESCE(
                    movimientos.salidas,
                    0
                ) AS salidas_movimiento,

                CASE
                    WHEN ultimo_conteo.stock_contado IS NULL
                        THEN COALESCE(recepciones.cantidad,0) + COALESCE(movimientos.entradas,0) - COALESCE(movimientos.salidas,0)
                    ELSE
                        ultimo_conteo.stock_contado
                        + COALESCE(
                            recepciones.cantidad,
                            0
                        )
                        + COALESCE(
                            movimientos.entradas,
                            0
                        )
                        - COALESCE(
                            movimientos.salidas,
                            0
                        )
                END AS stock_actual

            FROM producto p

            INNER JOIN categoria_producto cp
                ON cp.id_categoria = p.id_categoria

            LEFT JOIN LATERAL (
                SELECT
                    ic.fecha_inventario, ic.fecha_registro,
                    icd.stock_contado
                FROM inventario_cierre_detalle icd
                INNER JOIN (SELECT * FROM inventario_cierre WHERE id_local=:id_local_actual) ic
                    ON ic.id_inventario_cierre =
                       icd.id_inventario_cierre
                WHERE icd.id_producto = p.id_producto
                  AND ic.estado_inventario = 'CERRADO'
                  AND ic.fecha_inventario <= CURRENT_DATE
                ORDER BY
                    ic.fecha_inventario DESC,
                    ic.id_inventario_cierre DESC
                LIMIT 1
            ) AS ultimo_conteo ON TRUE

            LEFT JOIN LATERAL (
                SELECT
                    SUM(frd.cantidad_recibida) AS cantidad
                FROM factura_recepcion_detalle frd
                INNER JOIN (SELECT f_local.* FROM factura_recepcion f_local JOIN orden_compra o_local USING(id_orden_compra) WHERE o_local.id_local=:id_local_actual) fr
                    ON fr.id_factura_recepcion =
                       frd.id_factura_recepcion
                WHERE frd.id_producto = p.id_producto
                  AND (ultimo_conteo.fecha_inventario IS NULL OR fr.fecha_recepcion > ultimo_conteo.fecha_inventario)
                  AND fr.fecha_recepcion <= CURRENT_DATE
            ) AS recepciones ON TRUE

            LEFT JOIN LATERAL (
                SELECT
                    SUM(
                        CASE
                            WHEN mi.tipo_movimiento = 'ENTRADA'
                                THEN mid.cantidad
                            ELSE 0
                        END
                    ) AS entradas,

                    SUM(
                        CASE
                            WHEN mi.tipo_movimiento = 'SALIDA'
                                THEN mid.cantidad
                            ELSE 0
                        END
                    ) AS salidas

                FROM movimiento_inventario_detalle mid
                INNER JOIN (SELECT * FROM movimiento_inventario WHERE id_local=:id_local_actual) mi
                    ON mi.id_movimiento_inventario =
                       mid.id_movimiento_inventario
                WHERE mid.id_producto = p.id_producto
                  AND (ultimo_conteo.fecha_inventario IS NULL OR mi.fecha_movimiento > ultimo_conteo.fecha_inventario OR (mi.fecha_movimiento = ultimo_conteo.fecha_inventario AND (to_jsonb(mi)->>'registrado_en')::timestamp > ultimo_conteo.fecha_registro))
                  AND mi.fecha_movimiento <= CURRENT_DATE
            ) AS movimientos ON TRUE

            WHERE p.activo = TRUE
              AND cp.activo = TRUE
        )

        SELECT
            *,
            CASE
                WHEN stock_actual IS NULL
                    THEN 'SIN_CONTEO'
                WHEN stock_actual <= 0
                    THEN 'AGOTADO'
                WHEN stock_actual <= stock_minimo
                    THEN 'STOCK_BAJO'
                ELSE 'DISPONIBLE'
            END AS estado_stock
        FROM stock_calculado
        ORDER BY
            categoria,
            nombre
    """)

    return ejecutar_local(consulta, parametros).mappings().all()


def buscar_cabecera_inventario_actual():
    consulta = text("""
        SELECT
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.usuario_registro,
            ic.fecha_registro,
            ic.observacion,
            CONCAT(
                u.nombres,
                ' ',
                u.apellido_paterno
            ) AS usuario
        FROM (SELECT * FROM inventario_cierre WHERE id_local=:id_local_actual) ic
        LEFT JOIN usuario u
            ON u.id_usuario = ic.usuario_registro
        WHERE ic.estado_inventario IN (
            'BORRADOR',
            'INCOMPLETO'
        )
        ORDER BY
            ic.fecha_inventario DESC,
            ic.id_inventario_cierre DESC
        LIMIT 1
    """)

    return ejecutar_local(
        consulta
    ).mappings().first()


def consultar_productos_para_inventario(
    id_inventario_cierre=None
):
    if id_inventario_cierre is not None:
        exigir_registro_local("inventario", id_inventario_cierre)
    consulta = text("""
        SELECT
            p.id_producto,
            p.codigo,
            p.nombre,
            p.unidad,
            p.id_categoria,
            cp.nombre AS categoria,
            icd.stock_contado
        FROM producto p
        INNER JOIN categoria_producto cp
            ON cp.id_categoria = p.id_categoria
        LEFT JOIN inventario_cierre_detalle icd
            ON icd.id_producto = p.id_producto
           AND icd.id_inventario_cierre =
               :id_inventario_cierre
        WHERE p.activo = TRUE
          AND cp.activo = TRUE
        ORDER BY
            cp.nombre,
            p.nombre
    """)

    return ejecutar_local(
        consulta,
        {
            "id_inventario_cierre":
                id_inventario_cierre
        }
    ).mappings().all()


def crear_inventario_actual(
    id_usuario,
    fecha_inventario
):
    consulta = text("""
        INSERT INTO inventario_cierre (
            id_local,
            fecha_inventario,
            estado_inventario,
            usuario_registro
        )
        VALUES (
            :id_local_actual,
            :fecha_inventario,
            'BORRADOR',
            :id_usuario
        )
        ON CONFLICT (id_local, fecha_inventario)
        DO NOTHING
        RETURNING id_inventario_cierre
    """)

    return ejecutar_local(
        consulta,
        {
            "id_usuario": id_usuario,
            "fecha_inventario":
                fecha_inventario,
        }
    ).scalar()


def producto_activo_existe(id_producto):
    consulta = text("""
        SELECT EXISTS (
            SELECT 1
            FROM producto
            WHERE id_producto = :id_producto
              AND activo = TRUE
        ) AS existe
    """)

    return bool(
        ejecutar_local(
            consulta,
            {"id_producto": id_producto}
        ).scalar()
    )


def guardar_detalle_inventario(
    id_inventario_cierre,
    id_producto,
    stock_contado
):
    exigir_registro_local("inventario", id_inventario_cierre)
    consulta = text("""
        INSERT INTO inventario_cierre_detalle (
            id_inventario_cierre,
            id_producto,
            stock_contado
        )
        VALUES (
            :id_inventario_cierre,
            :id_producto,
            :stock_contado
        )
        ON CONFLICT (
            id_inventario_cierre,
            id_producto
        )
        DO UPDATE SET
            stock_contado = EXCLUDED.stock_contado
    """)

    ejecutar_local(
        consulta,
        {
            "id_inventario_cierre":
                id_inventario_cierre,
            "id_producto": id_producto,
            "stock_contado": stock_contado,
        }
    )


def eliminar_detalle_inventario(
    id_inventario_cierre,
    id_producto
):
    exigir_registro_local("inventario", id_inventario_cierre)
    consulta = text("""
        DELETE FROM inventario_cierre_detalle
        WHERE id_inventario_cierre =
              :id_inventario_cierre
          AND id_producto = :id_producto
    """)

    ejecutar_local(
        consulta,
        {
            "id_inventario_cierre":
                id_inventario_cierre,
            "id_producto": id_producto,
        }
    )


def contar_detalles_inventario(
    id_inventario_cierre
):
    exigir_registro_local("inventario", id_inventario_cierre)
    consulta = text("""
        SELECT COUNT(*)
        FROM inventario_cierre_detalle
        WHERE id_inventario_cierre =
              :id_inventario_cierre
    """)

    return int(
        ejecutar_local(
            consulta,
            {
                "id_inventario_cierre":
                    id_inventario_cierre
            }
        ).scalar() or 0
    )


def actualizar_estado_inventario(
    id_inventario_cierre,
    estado
):
    exigir_registro_local("inventario", id_inventario_cierre)
    consulta = text("""
        UPDATE inventario_cierre
        SET estado_inventario = :estado
        WHERE id_inventario_cierre =
              :id_inventario_cierre
    """)

    ejecutar_local(
        consulta,
        {
            "id_inventario_cierre":
                id_inventario_cierre,
            "estado": estado,
        }
    )


def buscar_inventario_por_fecha(fecha_inventario):
    consulta = text("""
        SELECT
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.usuario_registro,
            ic.fecha_registro,
            ic.observacion,
            CONCAT(
                u.nombres,
                ' ',
                u.apellido_paterno
            ) AS usuario
        FROM (SELECT * FROM inventario_cierre WHERE id_local=:id_local_actual) ic
        LEFT JOIN usuario u
            ON u.id_usuario = ic.usuario_registro
        WHERE ic.fecha_inventario = :fecha_inventario
        ORDER BY ic.id_inventario_cierre DESC
        LIMIT 1
    """)

    return ejecutar_local(
        consulta,
        {
            "fecha_inventario":
                fecha_inventario
        }
    ).mappings().first()


def eliminar_inventario_provisional(
    id_inventario_cierre
):
    exigir_registro_local("inventario", id_inventario_cierre)
    consulta_detalles = text("""
        DELETE FROM inventario_cierre_detalle
        WHERE id_inventario_cierre =
              :id_inventario_cierre
    """)

    consulta_cabecera = text("""
        DELETE FROM inventario_cierre
        WHERE id_inventario_cierre =
              :id_inventario_cierre
          AND estado_inventario IN (
              'BORRADOR',
              'INCOMPLETO'
          )
    """)

    parametros = {
        "id_inventario_cierre":
            id_inventario_cierre
    }

    ejecutar_local(
        consulta_detalles,
        parametros,
    )

    resultado = ejecutar_local(
        consulta_cabecera,
        parametros,
    )

    return resultado.rowcount > 0


def cerrar_inventario_en_base_datos(
    id_inventario_cierre
):
    exigir_registro_local("inventario", id_inventario_cierre)
    consulta = text("""
        UPDATE inventario_cierre
        SET
            estado_inventario = 'CERRADO',
            fecha_registro = (
                CURRENT_TIMESTAMP
                AT TIME ZONE 'America/Lima'
            )
        WHERE id_inventario_cierre =
              :id_inventario_cierre
          AND estado_inventario IN (
              'BORRADOR',
              'INCOMPLETO'
          )
        RETURNING id_inventario_cierre
    """)

    return ejecutar_local(
        consulta,
        {
            "id_inventario_cierre":
                id_inventario_cierre
        }
    ).scalar()


def listar_inventarios_para_revision():
    consulta = text("""
        SELECT
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.fecha_registro,
            ic.usuario_registro,
            CONCAT_WS(
                ' ',
                ur.nombres,
                ur.apellido_paterno,
                ur.apellido_materno
            ) AS registrado_por,
            ic.usuario_revision,
            CASE
                WHEN ic.usuario_revision IS NULL THEN NULL
                ELSE CONCAT_WS(
                    ' ',
                    uv.nombres,
                    uv.apellido_paterno,
                    uv.apellido_materno
                )
            END AS revisado_por,
            ic.motivo_revision,
            ic.observacion,
            COUNT(icd.id_inventario_cierre_detalle)
                AS productos_contados,
            COUNT(*) FILTER (
                WHERE icd.stock_contado = 0
            ) AS productos_en_cero,
            COUNT(*) FILTER (
                WHERE icd.stock_contado > 0
            ) AS productos_con_existencia,
            (
                SELECT COUNT(*)
                FROM producto p
                WHERE p.activo = TRUE
            ) AS total_productos_actuales
        FROM inventario_cierre ic
        JOIN usuario ur
            ON ur.id_usuario = ic.usuario_registro
        LEFT JOIN usuario uv
            ON uv.id_usuario = ic.usuario_revision
        LEFT JOIN inventario_cierre_detalle icd
            ON icd.id_inventario_cierre =
               ic.id_inventario_cierre
        WHERE ic.id_local=:id_local_actual AND ic.estado_inventario = 'CERRADO'
        GROUP BY
            ic.id_inventario_cierre,
            ur.id_usuario,
            uv.id_usuario
        ORDER BY
            ic.fecha_inventario DESC,
            ic.id_inventario_cierre DESC
    """)

    return ejecutar_local(
        consulta
    ).mappings().all()


def buscar_inventario_cerrado_por_id(id_inventario):
    exigir_registro_local("inventario", id_inventario)
    consulta = text("""
        SELECT
            ic.id_inventario_cierre,
            ic.fecha_inventario,
            ic.estado_inventario,
            ic.fecha_registro,
            ic.usuario_registro,
            CONCAT_WS(
                ' ',
                ur.nombres,
                ur.apellido_paterno,
                ur.apellido_materno
            ) AS registrado_por,
            ic.usuario_revision,
            CASE
                WHEN ic.usuario_revision IS NULL THEN NULL
                ELSE CONCAT_WS(
                    ' ',
                    uv.nombres,
                    uv.apellido_paterno,
                    uv.apellido_materno
                )
            END AS revisado_por,
            ic.motivo_revision,
            ic.observacion
        FROM (SELECT * FROM inventario_cierre WHERE id_local=:id_local_actual) ic
        JOIN usuario ur
            ON ur.id_usuario = ic.usuario_registro
        LEFT JOIN usuario uv
            ON uv.id_usuario = ic.usuario_revision
        WHERE ic.id_inventario_cierre = :id_inventario
          AND ic.estado_inventario = 'CERRADO'
    """)

    return ejecutar_local(
        consulta,
        {"id_inventario": id_inventario},
    ).mappings().first()


def listar_productos_revision(id_inventario):
    exigir_registro_local("inventario", id_inventario)
    minimo_local, parametros = minimo_del_local()
    consulta = text(f"""
        SELECT
            p.id_producto,
            p.codigo,
            p.nombre AS producto,
            cp.nombre AS categoria,
            p.unidad,
            {minimo_local} AS stock_minimo,
            p.activo,
            icd.stock_contado,
            CASE
                WHEN icd.id_inventario_cierre_detalle
                     IS NULL
                THEN FALSE
                ELSE TRUE
            END AS fue_contado
        FROM producto p
        JOIN categoria_producto cp
            ON cp.id_categoria = p.id_categoria
        LEFT JOIN inventario_cierre_detalle icd
            ON icd.id_producto = p.id_producto
           AND icd.id_inventario_cierre = :id_inventario
        WHERE p.activo = TRUE
           OR icd.id_inventario_cierre_detalle IS NOT NULL
        ORDER BY
            fue_contado DESC,
            cp.nombre,
            p.nombre
    """)

    return ejecutar_local(
        consulta,
        {"id_inventario": id_inventario, **parametros},
    ).mappings().all()


def actualizar_revision_inventario(
    id_inventario,
    id_usuario_revision,
    motivo_revision,
    observacion,
):
    exigir_registro_local("inventario", id_inventario)
    consulta = text("""
        UPDATE inventario_cierre
        SET
            usuario_revision = :id_usuario_revision,
            motivo_revision = :motivo_revision,
            observacion = :observacion
        WHERE id_inventario_cierre = :id_inventario
          AND estado_inventario = 'CERRADO'
        RETURNING id_inventario_cierre
    """)

    return ejecutar_local(
        consulta,
        {
            "id_inventario": id_inventario,
            "id_usuario_revision": id_usuario_revision,
            "motivo_revision": motivo_revision,
            "observacion": observacion,
        },
    ).scalar_one_or_none()


def bloquear_inventario_cerrado(id_inventario):
    exigir_registro_local("inventario", id_inventario)
    consulta = text("""
        SELECT
            id_inventario_cierre,
            fecha_inventario,
            estado_inventario
        FROM (SELECT * FROM inventario_cierre WHERE id_local=:id_local_actual) inventario_cierre
        WHERE id_inventario_cierre = :id_inventario
          AND estado_inventario = 'CERRADO'
        FOR UPDATE
    """)

    return ejecutar_local(
        consulta,
        {"id_inventario": id_inventario},
    ).mappings().first()


def buscar_producto_para_correccion(
    id_inventario,
    id_producto,
):
    exigir_registro_local("inventario", id_inventario)
    consulta = text("""
        SELECT
            p.id_producto,
            p.codigo,
            p.nombre,
            p.activo,
            icd.id_inventario_cierre_detalle,
            icd.stock_contado
        FROM producto p
        LEFT JOIN inventario_cierre_detalle icd
            ON icd.id_producto = p.id_producto
           AND icd.id_inventario_cierre = :id_inventario
        WHERE p.id_producto = :id_producto
          AND (
              p.activo = TRUE
              OR icd.id_inventario_cierre_detalle IS NOT NULL
          )
    """)

    return ejecutar_local(
        consulta,
        {
            "id_inventario": id_inventario,
            "id_producto": id_producto,
        },
    ).mappings().first()


def crear_cabecera_correccion(
    id_inventario,
    id_usuario,
    motivo,
    observacion,
):
    exigir_registro_local("inventario", id_inventario)
    consulta = text("""
        INSERT INTO inventario_cierre_correccion (
            id_inventario_cierre,
            usuario_correccion,
            motivo_correccion,
            observacion
        )
        VALUES (
            :id_inventario,
            :id_usuario,
            :motivo,
            :observacion
        )
        RETURNING id_inventario_cierre_correccion
    """)

    return ejecutar_local(
        consulta,
        {
            "id_inventario": id_inventario,
            "id_usuario": id_usuario,
            "motivo": motivo,
            "observacion": observacion,
        },
    ).scalar_one()


def crear_detalle_correccion(
    id_correccion,
    id_producto,
    stock_anterior,
    stock_nuevo,
):
    exigir_registro_local("correccion", id_correccion)
    consulta = text("""
        INSERT INTO inventario_cierre_correccion_detalle (
            id_inventario_cierre_correccion,
            id_producto,
            stock_anterior,
            stock_nuevo
        )
        VALUES (
            :id_correccion,
            :id_producto,
            :stock_anterior,
            :stock_nuevo
        )
    """)

    ejecutar_local(
        consulta,
        {
            "id_correccion": id_correccion,
            "id_producto": id_producto,
            "stock_anterior": stock_anterior,
            "stock_nuevo": stock_nuevo,
        },
    )


def aplicar_stock_corregido(
    id_inventario,
    id_producto,
    stock_nuevo,
):
    exigir_registro_local("inventario", id_inventario)
    parametros = {
        "id_inventario": id_inventario,
        "id_producto": id_producto,
        "stock_nuevo": stock_nuevo,
    }

    if stock_nuevo is None:
        consulta = text("""
            DELETE FROM inventario_cierre_detalle
            WHERE id_inventario_cierre = :id_inventario
              AND id_producto = :id_producto
        """)
    else:
        consulta = text("""
            INSERT INTO inventario_cierre_detalle (
                id_inventario_cierre,
                id_producto,
                stock_contado
            )
            VALUES (
                :id_inventario,
                :id_producto,
                :stock_nuevo
            )
            ON CONFLICT (
                id_inventario_cierre,
                id_producto
            )
            DO UPDATE SET
                stock_contado = EXCLUDED.stock_contado
        """)

    ejecutar_local(consulta, parametros)


def listar_historial_correcciones(id_inventario):
    exigir_registro_local("inventario", id_inventario)
    consulta = text("""
        SELECT
            icc.id_inventario_cierre_correccion,
            icc.fecha_correccion,
            icc.motivo_correccion,
            icc.observacion,
            CONCAT_WS(
                ' ',
                u.nombres,
                u.apellido_paterno,
                u.apellido_materno
            ) AS corregido_por,
            iccd.id_producto,
            p.codigo,
            p.nombre AS producto,
            p.unidad,
            iccd.stock_anterior,
            iccd.stock_nuevo
        FROM inventario_cierre_correccion icc
        JOIN usuario u
            ON u.id_usuario = icc.usuario_correccion
        JOIN inventario_cierre_correccion_detalle iccd
            ON iccd.id_inventario_cierre_correccion =
               icc.id_inventario_cierre_correccion
        JOIN producto p
            ON p.id_producto = iccd.id_producto
        WHERE icc.id_inventario_cierre = :id_inventario
        ORDER BY
            icc.fecha_correccion DESC,
            icc.id_inventario_cierre_correccion DESC,
            p.nombre
    """)

    return ejecutar_local(
        consulta,
        {"id_inventario": id_inventario},
    ).mappings().all()

