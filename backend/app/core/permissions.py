from functools import wraps

from flask import jsonify
from flask_jwt_extended import (
    get_jwt,
    get_jwt_identity,
    verify_jwt_in_request,
)
from sqlalchemy import text

from app.core.extensions import db


CAMPOS_PERMISO = {
    "consultar": "puede_consultar",
    "crear": "puede_crear",
    "editar": "puede_editar",
    "revisar": "puede_revisar",
    "cerrar": "puede_cerrar",
    "desactivar": "puede_desactivar",
    "reactivar": "puede_reactivar",
    "eliminar": "puede_eliminar",
    "configurar": "puede_configurar",
}


def requiere_permiso(id_opcion_menu: int, accion: str):
    if accion not in CAMPOS_PERMISO:
        raise ValueError(f"Permiso no reconocido: {accion}")

    campo = CAMPOS_PERMISO[accion]

    def decorador(funcion):
        @wraps(funcion)
        def envoltura(*args, **kwargs):
            verify_jwt_in_request()

            token = get_jwt()

            if token.get("tipo_token") != "operativo":
                return jsonify({
                    "mensaje": "Debes seleccionar un perfil para continuar"
                }), 403

            try:
                id_usuario = int(get_jwt_identity())
                id_perfil = int(token.get("id_perfil"))
            except (TypeError, ValueError):
                return jsonify({
                    "mensaje": "La sesión no contiene un perfil válido"
                }), 401

            if id_opcion_menu in (15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 31, 32, 36, 37, 38) and id_perfil not in (2, 3, 4):
                return jsonify({"mensaje": "Esta operación requiere un perfil operativo de tienda"}), 403

            consulta = text(f"""
                SELECT EXISTS (
                    SELECT 1
                    FROM usuario u
                    INNER JOIN usuario_perfiles up
                        ON up.id_usuario = u.id_usuario
                       AND up.estado_registro = 1
                    INNER JOIN perfiles p
                        ON p.id_perfil = up.id_perfil
                       AND p.estado_registro = 1
                    INNER JOIN perfil_opcion_menu pom
                        ON pom.id_perfil = p.id_perfil
                       AND pom.estado_registro = 1
                    INNER JOIN opcion_menu om
                        ON om.id_opcion_menu = pom.id_opcion_menu
                       AND om.estado_registro = 1
                    WHERE u.id_usuario = :id_usuario
                      AND u.estado_registro = 1
                      AND p.id_perfil = :id_perfil
                      AND pom.id_opcion_menu = :id_opcion_menu
                      AND {campo} = TRUE
                )
            """)

            autorizado = db.session.execute(
                consulta,
                {
                    "id_usuario": id_usuario,
                    "id_perfil": id_perfil,
                    "id_opcion_menu": id_opcion_menu,
                },
            ).scalar()

            if not autorizado:
                return jsonify({
                    "mensaje": (
                        "No tienes permiso para realizar esta acción "
                        "con el perfil activo"
                    )
                }), 403

            return funcion(*args, **kwargs)

        return envoltura

    return decorador
