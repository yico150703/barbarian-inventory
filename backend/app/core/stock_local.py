from flask import abort, g
from flask_jwt_extended import get_jwt
from sqlalchemy import text

from app.core.extensions import db


def minimo_del_local():
    """Expresión SQL para el alias p y parámetros del local autenticado.

    Conserva las consultas existentes mientras la migración está pendiente.
    Tras aplicarla, los locales sin configuración comienzan con mínimo cero.
    """
    id_local = get_jwt().get("id_local")
    if not isinstance(id_local, int) or isinstance(id_local, bool) or id_local <= 0:
        abort(403, description="La sesión no contiene un local válido")
    if not hasattr(g, "hay_stock_local"):
        g.hay_stock_local = db.session.execute(text(
            "SELECT to_regclass('public.producto_stock_local') IS NOT NULL"
        )).scalar()
    if not g.hay_stock_local:
        return "p.stock_minimo", {}
    return """COALESCE((
        SELECT sl.stock_minimo FROM producto_stock_local sl
        WHERE sl.id_producto = p.id_producto AND sl.id_local = :id_local_stock
    ), 0)""", {"id_local_stock": id_local}
