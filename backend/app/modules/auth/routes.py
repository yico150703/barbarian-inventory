from flask import Blueprint, jsonify, request
from flask_jwt_extended import (
    get_jwt,
    get_jwt_identity,
    jwt_required,
)

from app.modules.auth.service import (
    cambiar_local_activo,
    cambiar_perfil_activo,
    iniciar_sesion,
    obtener_sesion_actual,
)


auth_bp = Blueprint("auth", __name__)


@auth_bp.post("/login")
def login():
    datos = request.get_json(silent=True) or {}
    respuesta, estado = iniciar_sesion(datos)

    return jsonify(respuesta), estado


@auth_bp.post("/seleccionar-perfil")
@jwt_required()
def seleccionar_perfil():
    respuesta, estado = seleccionar_perfil_inicial(
        int(get_jwt_identity()),
        get_jwt(),
        request.get_json(silent=True) or {},
    )

    return jsonify(respuesta), estado


@auth_bp.post("/cambiar-perfil")
@jwt_required()
def cambiar_perfil():
    respuesta, estado = cambiar_perfil_activo(
        int(get_jwt_identity()),
        get_jwt(),
        request.get_json(silent=True) or {},
    )

    return jsonify(respuesta), estado


@auth_bp.get("/me")
@jwt_required()
def obtener_usuario_actual():
    respuesta, estado = obtener_sesion_actual(
        int(get_jwt_identity()),
        get_jwt(),
    )

    return jsonify(respuesta), estado


@auth_bp.post("/cambiar-local")
@jwt_required()
def cambiar_local():
    respuesta, estado = cambiar_local_activo(
        int(get_jwt_identity()),
        get_jwt(),
        request.get_json(silent=True) or {},
    )
    return jsonify(respuesta), estado