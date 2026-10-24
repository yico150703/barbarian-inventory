from flask import Blueprint, jsonify
from sqlalchemy import text

from app.core.extensions import db

health_bp = Blueprint("health", __name__)


@health_bp.get("/health")
def health():
    if db.engine.dialect.name == "sqlite":
        base_datos = db.engine.url.database or ":memory:"
        usuario = "local"
        total_tablas = db.session.execute(text("""
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
        """)).scalar_one()
    else:
        resultado = db.session.execute(text("""
            SELECT
                current_database() AS base_datos,
                current_user AS usuario,
                (
                    SELECT COUNT(*)
                    FROM pg_tables
                    WHERE schemaname = 'public'
                ) AS total_tablas
        """)).mappings().one()
        base_datos = resultado["base_datos"]
        usuario = resultado["usuario"]
        total_tablas = resultado["total_tablas"]

    return jsonify({
        "estado": "ok",
        "base_datos": base_datos,
        "usuario": usuario,
        "total_tablas": total_tablas
    })