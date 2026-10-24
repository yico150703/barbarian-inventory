from app.modules.asistente_ia.routes import asistente_ia_bp
from app.modules.auth.salon_control import salon_control_bp
from app.modules.auth.salon_payments import salon_payments_bp
from app.modules.inventarios.operativo import operativo_bp
from app.modules.auth.salon_layout import salon_layout_bp
from app.modules.auth.salon_orders import salon_orders_bp
from app.modules.auth.salon import salon_bp
from flask import Flask, jsonify
from werkzeug.exceptions import HTTPException
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from app.core.config import Config
from app.core.extensions import db
from app.core.units import registrar_medidas_api
from app.modules.auditoria.routes import auditoria_bp
from app.modules.auth.routes import auth_bp
from app.modules.carta.routes import carta_bp
from app.modules.catalogos.routes import catalogos_bp
from app.modules.catalogos.deletion import deletion_bp
from app.modules.catalogos import stock_limits  # Registra las rutas de límites.
from app.modules.compras.routes import compras_bp
from app.modules.health.routes import health_bp
from app.modules.inventarios.routes import inventarios_bp
from app.modules.movimientos.routes import movimientos_bp
from app.modules.produccion.routes import produccion_bp
from app.modules.promociones.routes import promociones_bp
from app.modules.recepciones.routes import recepciones_bp
# 1. IMPORTAR EL BLUEPRINT DE RECETAS
from app.modules.recetas.routes import recetas_bp
from app.modules.usuarios.routes import usuarios_bp
from app.modules.usuarios.locales import locales_bp


def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)
    registrar_medidas_api(app)

    app.register_blueprint(asistente_ia_bp, url_prefix="/api/asistente-ia")
    app.register_blueprint(locales_bp, url_prefix="/api/locales")
    db.init_app(app)
    JWTManager(app)
    app.register_blueprint(deletion_bp, url_prefix='/api/eliminaciones')

    @app.errorhandler(HTTPException)
    def error_http(error):
        return jsonify({"mensaje": error.description}), error.code

    CORS(
        app,
        resources={
            r"/api/*": {
                "origins": "*",
                "allow_headers": [
                    "Content-Type",
                    "Authorization",
                ],
                "methods": [
                    "GET",
                    "POST",
                    "PUT",
                    "PATCH",
                    "DELETE",
                    "OPTIONS",
                ],
            }
        },
    )

    app.register_blueprint(
        health_bp,
        url_prefix="/api"
    )

    app.register_blueprint(salon_bp, url_prefix="/api/salon")
    app.register_blueprint(salon_orders_bp, url_prefix="/api/salon")
    app.register_blueprint(salon_layout_bp, url_prefix="/api/salon")
    app.register_blueprint(salon_control_bp, url_prefix="/api/salon")
    app.register_blueprint(salon_payments_bp, url_prefix="/api/salon")
    app.register_blueprint(operativo_bp, url_prefix="/api/inventario-operativo")
    app.register_blueprint(
        auth_bp,
        url_prefix="/api/auth"
    )

    app.register_blueprint(
        auditoria_bp,
        url_prefix="/api/actividades"
    )
    app.register_blueprint(
        inventarios_bp,
        url_prefix="/api/inventarios"
    )
    app.register_blueprint(
        catalogos_bp,
        url_prefix="/api/catalogos",
    )

    app.register_blueprint(
        carta_bp,
        url_prefix="/api/carta",
    )
    app.register_blueprint(
        produccion_bp,
        url_prefix="/api/produccion",
    )
    app.register_blueprint(
        promociones_bp,
        url_prefix="/api/promociones",
    )
    app.register_blueprint(
        movimientos_bp,
        url_prefix="/api/movimientos",
    )
    app.register_blueprint(
        recepciones_bp,
        url_prefix="/api/recepciones",
    )
    app.register_blueprint(
        compras_bp,
        url_prefix="/api/ordenes-compra",
    )
    app.register_blueprint(
        usuarios_bp,
        url_prefix="/api/usuarios",
    )
    # 2. REGISTRAR EL BLUEPRINT EN LA API
    app.register_blueprint(
        recetas_bp,
        url_prefix="/api/recetas",
    )

    return app
