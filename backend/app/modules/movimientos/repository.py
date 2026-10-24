from sqlalchemy import text

from app.core.local_scope import ejecutar_local, exigir_registro_local


def listar_productos_activos_movimiento():
    consulta = text("""
        SELECT
            p.id_producto,
            p.codigo,
            p.nombre,
            p.unidad,
            p.id_categoria,
            cp.nombre AS categoria
        FROM producto p
        JOIN categoria_producto cp
            ON cp.id_categoria = p.id_categoria
        WHERE p.activo = TRUE
          AND cp.activo = TRUE
        ORDER BY cp.nombre, p.nombre
    """)

    return ejecutar_local(
        consulta
    ).mappings().all()


def listar_proveedores_activos_movimiento():
    consulta = text("""
        SELECT id_proveedor, nombre
        FROM proveedor
        WHERE activo = TRUE
        ORDER BY nombre
    """)

    return ejecutar_local(
        consulta
    ).mappings().all()


def buscar_producto_activo_movimiento(id_producto):
    consulta = text("""
        SELECT id_producto, codigo, nombre, unidad
        FROM producto
        WHERE id_producto = :id_producto
          AND activo = TRUE
    """)

    return ejecutar_local(
        consulta,
        {"id_producto": id_producto},
    ).mappings().first()


def proveedor_activo_movimiento_existe(id_proveedor):
    consulta = text("""
        SELECT EXISTS (
            SELECT 1
            FROM proveedor
            WHERE id_proveedor = :id_proveedor
              AND activo = TRUE
        )
    """)

    return bool(
        ejecutar_local(
            consulta,
            {"id_proveedor": id_proveedor},
        ).scalar()
    )


def generar_codigo_movimiento():
    ejecutar_local(
        text("""
            SELECT pg_advisory_xact_lock(
                hashtext('movimiento_inventario_codigo')
            )
        """)
    )

    consulta = text("""
        SELECT COALESCE(
            MAX(
                CASE
                    WHEN codigo ~ '^MI-[0-9]+$'
                    THEN SUBSTRING(
                        codigo FROM 4
                    )::INTEGER
                    ELSE 0
                END
            ),
            0
        ) + 1
        FROM movimiento_inventario
    """)

    siguiente_numero = int(
        ejecutar_local(consulta).scalar() or 1
    )

    return f"MI-{siguiente_numero:03d}"


def crear_cabecera_movimiento(
    codigo,
    tipo_movimiento,
    motivo_movimiento,
    fecha_movimiento,
    id_usuario,
    local_relacionado,
    id_proveedor,
    observacion,
):
    consulta = text("""
        INSERT INTO movimiento_inventario (
            id_local,
            codigo,
            tipo_movimiento,
            motivo_movimiento,
            fecha_movimiento,
            usuario_registro,
            local_relacionado,
            id_proveedor,
            observacion
        )
        VALUES (
            :id_local_actual,
            :codigo,
            :tipo_movimiento,
            :motivo_movimiento,
            :fecha_movimiento,
            :id_usuario,
            :local_relacionado,
            :id_proveedor,
            :observacion
        )
        RETURNING id_movimiento_inventario
    """)

    return ejecutar_local(
        consulta,
        {
            "codigo": codigo,
            "tipo_movimiento": tipo_movimiento,
            "motivo_movimiento": motivo_movimiento,
            "fecha_movimiento": fecha_movimiento,
            "id_usuario": id_usuario,
            "local_relacionado": local_relacionado,
            "id_proveedor": id_proveedor,
            "observacion": observacion,
        },
    ).scalar_one()


def crear_detalle_movimiento(
    id_movimiento,
    id_producto,
    cantidad,
):
    exigir_registro_local("movimiento", id_movimiento)
    consulta = text("""
        INSERT INTO movimiento_inventario_detalle (
            id_movimiento_inventario,
            id_producto,
            cantidad
        )
        VALUES (
            :id_movimiento,
            :id_producto,
            :cantidad
        )
    """)

    ejecutar_local(
        consulta,
        {
            "id_movimiento": id_movimiento,
            "id_producto": id_producto,
            "cantidad": cantidad,
        },
    )


def buscar_movimiento_creado(id_movimiento):
    exigir_registro_local("movimiento", id_movimiento)
    consulta = text("""
        SELECT
            mi.id_movimiento_inventario,
            mi.codigo,
            mi.tipo_movimiento,
            mi.motivo_movimiento,
            mi.fecha_movimiento,
            mi.local_relacionado,
            mi.id_proveedor,
            pr.nombre AS proveedor,
            mi.observacion,
            CONCAT_WS(
                ' ',
                u.nombres,
                u.apellido_paterno,
                u.apellido_materno
            ) AS registrado_por
        FROM (SELECT * FROM movimiento_inventario WHERE id_local=:id_local_actual) mi
        JOIN usuario u
            ON u.id_usuario = mi.usuario_registro
        LEFT JOIN proveedor pr
            ON pr.id_proveedor = mi.id_proveedor
        WHERE mi.id_movimiento_inventario = :id_movimiento
    """)

    return ejecutar_local(
        consulta,
        {"id_movimiento": id_movimiento},
    ).mappings().first()


def listar_detalles_movimiento_creado(id_movimiento):
    exigir_registro_local("movimiento", id_movimiento)
    consulta = text("""
        SELECT
            p.id_producto,
            p.codigo,
            p.nombre,
            p.unidad,
            mid.cantidad
        FROM movimiento_inventario_detalle mid
        JOIN producto p
            ON p.id_producto = mid.id_producto
        WHERE mid.id_movimiento_inventario = :id_movimiento
        ORDER BY p.nombre
    """)

    return ejecutar_local(
        consulta,
        {"id_movimiento": id_movimiento},
    ).mappings().all()
