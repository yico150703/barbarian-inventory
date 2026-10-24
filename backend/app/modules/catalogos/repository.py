from sqlalchemy import text

from app.core.extensions import db
from app.core.units import unidad_almacenamiento


class CategoriasProveedorNoDisponibles(RuntimeError):
    pass


def categorias_proveedor_disponibles():
    return db.session.execute(
        text("SELECT to_regclass('public.proveedor_categoria') IS NOT NULL")
    ).scalar_one()


def _origen_categorias_proveedor():
    if categorias_proveedor_disponibles():
        return "proveedor_categoria"
    # Compatibilidad con instalaciones que todavía no aplicaron la migración.
    return "(SELECT DISTINCT id_proveedor, id_categoria FROM producto)"


def listar_productos():
    consulta = text("""
        SELECT
            p.id_producto,
            p.codigo,
            p.nombre,
            p.id_categoria,
            cp.nombre AS categoria,
            p.id_proveedor,
            pr.nombre AS proveedor,
            p.unidad,
            p.stock_minimo,
            p.presentacion,
            p.activo
        FROM producto AS p
        INNER JOIN categoria_producto AS cp
            ON cp.id_categoria = p.id_categoria
        INNER JOIN proveedor AS pr
            ON pr.id_proveedor = p.id_proveedor
        ORDER BY
            p.nombre ASC,
            p.codigo ASC
    """)

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]


def listar_categorias_producto():
    consulta = text("""
        SELECT
            id_categoria,
            nombre,
            prefijo,
            siguiente_numero,
            activo
        FROM categoria_producto
        ORDER BY nombre ASC
    """)

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]


def listar_categorias_producto_detalladas():
    consulta = text("""
        SELECT
            cp.id_categoria,
            cp.nombre,
            cp.prefijo,
            cp.siguiente_numero,
            cp.activo,
            COUNT(p.id_producto) AS total_productos,
            COUNT(p.id_producto)
                FILTER (WHERE p.activo = TRUE)
                AS productos_activos,
            COUNT(p.id_producto)
                FILTER (WHERE p.activo = FALSE)
                AS productos_inactivos
        FROM categoria_producto AS cp
        LEFT JOIN producto AS p
            ON p.id_categoria = cp.id_categoria
        GROUP BY
            cp.id_categoria,
            cp.nombre,
            cp.prefijo,
            cp.siguiente_numero,
            cp.activo
        ORDER BY cp.nombre ASC
    """)

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]


def listar_proveedores():
    origen = _origen_categorias_proveedor()
    consulta = text(f"""
        SELECT
            id_proveedor,
            nombre,
            activo,
            ARRAY(SELECT pc.id_categoria FROM {origen} pc
                  WHERE pc.id_proveedor = proveedor.id_proveedor
                  ORDER BY pc.id_categoria) AS ids_categorias
        FROM proveedor
        ORDER BY nombre ASC
    """)

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]

def listar_proveedores_detallados():
    proveedores = listar_proveedores()
    origen = _origen_categorias_proveedor()
    for proveedor in proveedores:
        productos = productos_proveedor(proveedor["id_proveedor"])
        categorias = db.session.execute(text(f"""
            SELECT cp.nombre FROM {origen} pc
            JOIN categoria_producto cp USING(id_categoria)
            WHERE pc.id_proveedor = :id ORDER BY cp.nombre
        """), {"id": proveedor["id_proveedor"]}).scalars().all()
        proveedor.update(
            total_productos=len(productos),
            productos_activos=sum(1 for p in productos if p["activo"]),
            productos_inactivos=sum(1 for p in productos if not p["activo"]),
            total_categorias=len(categorias), categorias=list(categorias),
        )
    return proveedores


def categorias_proveedor(id_proveedor):
    origen = _origen_categorias_proveedor()
    return list(db.session.execute(text(f"""
        SELECT id_categoria FROM {origen} pc
        WHERE id_proveedor = :id ORDER BY id_categoria
    """), {"id": id_proveedor}).scalars().all())


def asignar_categorias_proveedor(id_proveedor, ids):
    if not categorias_proveedor_disponibles():
        raise CategoriasProveedorNoDisponibles(
            "La asignación de categorías requiere ejecutar la migración "
            "20261010_proveedor_categorias.sql con el propietario de las tablas "
            "o un administrador de PostgreSQL. No se guardó ningún cambio."
        )
    db.session.execute(text("DELETE FROM proveedor_categoria WHERE id_proveedor = :id"),
                       {"id": id_proveedor})
    for categoria in ids:
        db.session.execute(text("""
            INSERT INTO proveedor_categoria (id_proveedor, id_categoria)
            VALUES (:id, :categoria)
        """), {"id": id_proveedor, "categoria": categoria})


def obtener_categoria(id_categoria, bloquear=False):
    bloqueo = " FOR UPDATE" if bloquear else ""
    return db.session.execute(
        text("""
            SELECT id_categoria, nombre, prefijo,
                   siguiente_numero, activo
            FROM categoria_producto
            WHERE id_categoria = :id_categoria
        """ + bloqueo),
        {"id_categoria": id_categoria},
    ).mappings().first()


def categoria_repetida(nombre, prefijo, excluir_id=None):
    return db.session.execute(
        text("""
            SELECT EXISTS (
                SELECT 1 FROM categoria_producto
                WHERE (:excluir_id IS NULL OR id_categoria <> :excluir_id)
                  AND (
                    LOWER(BTRIM(nombre)) = LOWER(BTRIM(:nombre))
                    OR UPPER(BTRIM(prefijo)) = UPPER(BTRIM(:prefijo))
                  )
            )
        """),
        {"nombre": nombre, "prefijo": prefijo,
         "excluir_id": excluir_id},
    ).scalar()


def crear_categoria(nombre, prefijo):
    return db.session.execute(
        text("""
            INSERT INTO categoria_producto
                (nombre, prefijo, siguiente_numero, activo)
            VALUES (:nombre, :prefijo, 1, TRUE)
            RETURNING id_categoria
        """),
        {"nombre": nombre, "prefijo": prefijo},
    ).scalar_one()


def actualizar_categoria(id_categoria, nombre, prefijo):
    db.session.execute(
        text("""
            UPDATE categoria_producto
            SET nombre = :nombre, prefijo = :prefijo
            WHERE id_categoria = :id_categoria
        """),
        {"id_categoria": id_categoria, "nombre": nombre,
         "prefijo": prefijo},
    )


def productos_categoria(id_categoria, solo_activos=False):
    condicion = " AND p.activo = TRUE" if solo_activos else ""
    return db.session.execute(
        text("""
            SELECT p.id_producto, p.codigo, p.nombre, p.activo
            FROM producto p
            WHERE p.id_categoria = :id_categoria
        """ + condicion + " ORDER BY p.nombre"),
        {"id_categoria": id_categoria},
    ).mappings().all()


def cambiar_estado_categoria(id_categoria, activo):
    db.session.execute(
        text("""
            UPDATE categoria_producto SET activo = :activo
            WHERE id_categoria = :id_categoria
        """),
        {"id_categoria": id_categoria, "activo": activo},
    )


def reasignar_categoria_productos(
    id_categoria_anterior,
    id_categoria_nueva,
    ids_productos,
    id_usuario,
    motivo,
):
    filas = db.session.execute(
        text("""
            UPDATE producto
            SET id_categoria = :nueva
            WHERE id_categoria = :anterior
              AND id_producto = ANY(:ids)
            RETURNING id_producto
        """),
        {"anterior": id_categoria_anterior,
         "nueva": id_categoria_nueva, "ids": ids_productos},
    ).scalars().all()

    for id_producto in filas:
        db.session.execute(
            text("""
                INSERT INTO producto_categoria_historial (
                    id_producto, id_categoria_anterior,
                    id_categoria_nueva, usuario_cambio, motivo
                ) VALUES (
                    :id_producto, :anterior, :nueva, :usuario, :motivo
                )
            """),
            {"id_producto": id_producto,
             "anterior": id_categoria_anterior,
             "nueva": id_categoria_nueva,
             "usuario": id_usuario, "motivo": motivo},
        )
    return filas


def obtener_proveedor(id_proveedor, bloquear=False):
    bloqueo = " FOR UPDATE" if bloquear else ""
    return db.session.execute(
        text("""
            SELECT id_proveedor, nombre, activo
            FROM proveedor
            WHERE id_proveedor = :id_proveedor
        """ + bloqueo),
        {"id_proveedor": id_proveedor},
    ).mappings().first()


def proveedor_repetido(nombre, excluir_id=None):
    return db.session.execute(
        text("""
            SELECT EXISTS (
                SELECT 1 FROM proveedor
                WHERE LOWER(BTRIM(nombre)) = LOWER(BTRIM(:nombre))
                  AND (:excluir_id IS NULL OR id_proveedor <> :excluir_id)
            )
        """),
        {"nombre": nombre, "excluir_id": excluir_id},
    ).scalar()


def crear_proveedor(nombre):
    return db.session.execute(
        text("""
            INSERT INTO proveedor (nombre, activo)
            VALUES (:nombre, TRUE)
            RETURNING id_proveedor
        """),
        {"nombre": nombre},
    ).scalar_one()


def actualizar_proveedor(id_proveedor, nombre):
    db.session.execute(
        text("""
            UPDATE proveedor SET nombre = :nombre
            WHERE id_proveedor = :id_proveedor
        """),
        {"id_proveedor": id_proveedor, "nombre": nombre},
    )


def productos_proveedor(id_proveedor, solo_activos=False):
    condicion = " AND p.activo = TRUE" if solo_activos else ""
    return db.session.execute(
        text("""
            SELECT p.id_producto, p.codigo, p.nombre, p.activo,
                   p.id_categoria
            FROM producto p
            WHERE p.id_proveedor = :id_proveedor
        """ + condicion + " ORDER BY p.nombre"),
        {"id_proveedor": id_proveedor},
    ).mappings().all()


def cambiar_estado_proveedor(id_proveedor, activo):
    db.session.execute(
        text("""
            UPDATE proveedor SET activo = :activo
            WHERE id_proveedor = :id_proveedor
        """),
        {"id_proveedor": id_proveedor, "activo": activo},
    )


def reasignar_proveedor_productos(
    id_proveedor_anterior,
    id_proveedor_nuevo,
    ids_productos,
    id_usuario,
    motivo,
):
    filas = db.session.execute(
        text("""
            UPDATE producto
            SET id_proveedor = :nuevo
            WHERE id_proveedor = :anterior
              AND id_producto = ANY(:ids)
            RETURNING id_producto
        """),
        {"anterior": id_proveedor_anterior,
         "nuevo": id_proveedor_nuevo, "ids": ids_productos},
    ).scalars().all()

    for id_producto in filas:
        db.session.execute(
            text("""
                INSERT INTO producto_proveedor_historial (
                    id_producto, id_proveedor_anterior,
                    id_proveedor_nuevo, usuario_cambio, motivo
                ) VALUES (
                    :id_producto, :anterior, :nuevo, :usuario, :motivo
                )
            """),
            {"id_producto": id_producto,
             "anterior": id_proveedor_anterior,
             "nuevo": id_proveedor_nuevo,
             "usuario": id_usuario, "motivo": motivo},
        )
    return filas


def obtener_producto(id_producto, bloquear=False):
    bloqueo = " FOR UPDATE" if bloquear else ""
    return db.session.execute(
        text("""
            SELECT id_producto, codigo, nombre, id_categoria,
                   id_proveedor, unidad, stock_minimo,
                   presentacion, activo
            FROM producto
            WHERE id_producto = :id_producto
        """ + bloqueo),
        {"id_producto": id_producto},
    ).mappings().first()


def generar_codigo_producto(id_categoria):
    fila = db.session.execute(
        text("""
            UPDATE categoria_producto
            SET siguiente_numero = siguiente_numero + 1
            WHERE id_categoria = :id_categoria AND activo = TRUE
            RETURNING prefijo, siguiente_numero - 1 AS numero
        """),
        {"id_categoria": id_categoria},
    ).mappings().first()
    if fila is None:
        return None
    return f"{fila['prefijo']}-{int(fila['numero']):03d}"


def producto_repetido(nombre, excluir_id=None):
    return db.session.execute(
        text("""
            SELECT EXISTS (
                SELECT 1 FROM producto
                WHERE LOWER(BTRIM(nombre)) = LOWER(BTRIM(:nombre))
                  AND (:excluir_id IS NULL OR id_producto <> :excluir_id)
            )
        """),
        {"nombre": nombre, "excluir_id": excluir_id},
    ).scalar()


def crear_producto_registro(
    codigo, nombre, id_categoria, id_proveedor,
    unidad, presentacion,
):
    return db.session.execute(
        text("""
            INSERT INTO producto (
                codigo, nombre, id_categoria, id_proveedor,
                unidad, presentacion, activo
            ) VALUES (
                :codigo, :nombre, :categoria, :proveedor,
                :unidad, :presentacion, TRUE
            ) RETURNING id_producto
        """),
        {"codigo": codigo, "nombre": nombre,
         "categoria": id_categoria, "proveedor": id_proveedor,
         "unidad": unidad_almacenamiento(unidad),
         "presentacion": presentacion},
    ).scalar_one()


def actualizar_producto_registro(
    id_producto, nombre, id_categoria, id_proveedor,
    unidad, presentacion,
):
    db.session.execute(
        text("""
            UPDATE producto
            SET nombre = :nombre,
                id_categoria = :categoria,
                id_proveedor = :proveedor,
                unidad = :unidad,
                presentacion = :presentacion
            WHERE id_producto = :id_producto
        """),
        {"id_producto": id_producto, "nombre": nombre,
         "categoria": id_categoria, "proveedor": id_proveedor,
         "unidad": unidad_almacenamiento(unidad),
         "presentacion": presentacion},
    )


def cambiar_estado_producto(id_producto, activo):
    db.session.execute(
        text("""
            UPDATE producto SET activo = :activo
            WHERE id_producto = :id_producto
        """),
        {"id_producto": id_producto, "activo": activo},
    )


def dependencias_producto(id_producto):
    consulta = text("""
        SELECT
          (SELECT COUNT(*) FROM receta_detalle
           WHERE id_producto = :id) AS recetas,
          (SELECT COUNT(*) FROM subproducto_detalle
           WHERE id_producto = :id) AS subproductos,
          (SELECT COUNT(*) FROM grupo_salsa_opcion
           WHERE id_producto = :id AND activo = TRUE) AS salsas_activas,
          (SELECT COUNT(*) FROM orden_compra_detalle
           WHERE id_producto = :id) AS ordenes,
          (SELECT COUNT(*) FROM factura_recepcion_detalle
           WHERE id_producto = :id) AS recepciones,
          (SELECT COUNT(*) FROM inventario_cierre_detalle
           WHERE id_producto = :id) AS inventarios,
          (SELECT COUNT(*) FROM movimiento_inventario_detalle
           WHERE id_producto = :id) AS movimientos
    """)
    return db.session.execute(
        consulta, {"id": id_producto}
    ).mappings().one()


def guardar_historial_categoria_producto(
    id_producto, anterior, nueva, id_usuario, motivo,
):
    db.session.execute(text("""
        INSERT INTO producto_categoria_historial (
            id_producto, id_categoria_anterior, id_categoria_nueva,
            usuario_cambio, motivo
        ) VALUES (:producto, :anterior, :nueva, :usuario, :motivo)
    """), {"producto": id_producto, "anterior": anterior,
            "nueva": nueva, "usuario": id_usuario, "motivo": motivo})


def guardar_historial_proveedor_producto(
    id_producto, anterior, nuevo, id_usuario, motivo,
):
    db.session.execute(text("""
        INSERT INTO producto_proveedor_historial (
            id_producto, id_proveedor_anterior, id_proveedor_nuevo,
            usuario_cambio, motivo
        ) VALUES (:producto, :anterior, :nuevo, :usuario, :motivo)
    """), {"producto": id_producto, "anterior": anterior,
            "nuevo": nuevo, "usuario": id_usuario, "motivo": motivo})
