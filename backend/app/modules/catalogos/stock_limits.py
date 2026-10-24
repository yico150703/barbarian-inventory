from decimal import Decimal, InvalidOperation
from functools import wraps

from flask import g, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity
from sqlalchemy import text

from app.core.extensions import db
from app.core.permissions import requiere_permiso
from app.modules.auditoria.service import registrar_actividad, registrar_cambio
from app.modules.catalogos.routes import catalogos_bp


def solo_gerente(accion):
    def decorar(funcion):
        @requiere_permiso(33, accion)
        @wraps(funcion)
        def protegida(*args, **kwargs):
            if get_jwt().get("id_perfil") != 2:
                return jsonify(mensaje="Solo el perfil Gerente puede configurar los límites de stock"), 403
            id_local = get_jwt().get("id_local")
            if not isinstance(id_local, int) or isinstance(id_local, bool) or id_local <= 0:
                return jsonify(mensaje="La sesión no contiene un local válido"), 403
            asignado = db.session.execute(text("""
                SELECT EXISTS (
                    SELECT 1 FROM usuario_local ul
                    JOIN local l ON l.id_local = ul.id_local
                    WHERE ul.id_usuario = :usuario AND ul.id_local = :local
                      AND ul.estado_registro = 1 AND l.estado_registro = 1
                )
            """), {"usuario": int(get_jwt_identity()), "local": id_local}).scalar()
            if not asignado:
                return jsonify(mensaje="El local activo ya no está asignado a tu cuenta"), 403
            g.id_local_limites = id_local
            return funcion(*args, **kwargs)
        return protegida
    return decorar


def validar_limites(datos):
    if not isinstance(datos, dict):
        return None
    try:
        minimo = Decimal(str(datos.get("stock_minimo")))
        maximo = Decimal(str(datos.get("stock_maximo")))
    except (InvalidOperation, ValueError, TypeError):
        return None
    for valor in (minimo, maximo):
        if not valor.is_finite() or valor < 0 or valor > Decimal("999999999.999"):
            return None
        if valor != valor.quantize(Decimal("0.001")):
            return None
    if maximo <= minimo:
        return None
    return minimo, maximo


@catalogos_bp.get("/limites-stock")
@solo_gerente("consultar")
def consultar_limites_stock():
    filas = db.session.execute(text("""
        SELECT p.id_producto, p.codigo, p.nombre, c.nombre AS categoria,
               p.unidad, COALESCE(sl.stock_minimo, 0) AS stock_minimo,
               sl.stock_maximo, p.activo
        FROM producto p
        JOIN categoria_producto c ON c.id_categoria = p.id_categoria
        LEFT JOIN producto_stock_local sl
          ON sl.id_producto = p.id_producto AND sl.id_local = :local
        ORDER BY p.nombre
    """), {"local": g.id_local_limites}).mappings().all()
    return jsonify(id_local=g.id_local_limites, productos=[{
        **dict(fila),
        "stock_minimo": float(fila["stock_minimo"]),
        "stock_maximo": float(fila["stock_maximo"]) if fila["stock_maximo"] is not None else None,
    } for fila in filas])


@catalogos_bp.put("/limites-stock/<int:id_producto>")
@solo_gerente("configurar")
def guardar_limites_stock(id_producto):
    datos = request.get_json(silent=True)
    if isinstance(datos, dict) and "id_local" in datos:
        return jsonify(mensaje="El local se determina por la sesión; cambia de local antes de configurar sus límites"), 400
    limites = validar_limites(datos)
    if limites is None:
        return jsonify(mensaje="Ingresa límites no negativos con hasta 3 decimales; el máximo debe ser mayor al mínimo. No pueden ser iguales"), 400
    minimo, maximo = limites
    id_local = g.id_local_limites
    try:
        actual = db.session.execute(text("""
            SELECT p.id_producto, p.codigo, COALESCE(sl.stock_minimo, 0) AS stock_minimo,
                   sl.stock_maximo
            FROM producto p
            LEFT JOIN producto_stock_local sl
              ON sl.id_producto = p.id_producto AND sl.id_local = :local
            WHERE p.id_producto = :id FOR UPDATE OF p
        """), {"id": id_producto, "local": id_local}).mappings().first()
        if actual is None:
            db.session.rollback()
            return jsonify(mensaje="El producto no existe"), 404
        db.session.execute(text("""
            INSERT INTO producto_stock_local (id_producto, id_local, stock_minimo, stock_maximo)
            VALUES (:id, :local, :minimo, :maximo)
            ON CONFLICT (id_producto, id_local) DO UPDATE
            SET stock_minimo = EXCLUDED.stock_minimo, stock_maximo = EXCLUDED.stock_maximo
        """), {"id": id_producto, "local": id_local, "minimo": minimo, "maximo": maximo})
        usuario = int(get_jwt_identity())
        anterior = {"id_local": id_local, "stock_minimo": str(actual["stock_minimo"]),
                    "stock_maximo": str(actual["stock_maximo"]) if actual["stock_maximo"] is not None else None}
        nuevo = {"id_local": id_local, "stock_minimo": str(minimo), "stock_maximo": str(maximo)}
        registrar_cambio(usuario, "LIMITES_STOCK", "CONFIGURAR", "producto_stock_local",
                         id_producto, anterior, nuevo, id_local=id_local)
        registrar_actividad(usuario, "LIMITES_STOCK", "CONFIGURAR", id_producto,
                            f"Configuró los límites de stock de {actual['codigo']} en el local {id_local}",
                            id_local=id_local)
        db.session.commit()
        return jsonify(mensaje="Límites de stock guardados para el local activo", id_local=id_local)
    except Exception:
        db.session.rollback()
        raise
