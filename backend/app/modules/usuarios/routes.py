from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity

from app.core.permissions import requiere_permiso
from app.modules.usuarios.service import (
    actualizar_estado,
    editar_usuario,
    obtener_usuarios,
    registrar_usuario,
)


usuarios_bp = Blueprint("usuarios", __name__)


@usuarios_bp.get("")
@requiere_permiso(id_opcion_menu=2, accion="consultar")
def consultar_usuarios():
    respuesta, estado = obtener_usuarios(get_jwt())
    return jsonify(respuesta), estado


@usuarios_bp.post("")
@requiere_permiso(id_opcion_menu=2, accion="crear")
def crear_usuario():
    respuesta, estado = registrar_usuario(
        int(get_jwt_identity()),
        get_jwt(),
        request.get_json(silent=True),
    )
    return jsonify(respuesta), estado


@usuarios_bp.put("/<int:id_usuario>")
@requiere_permiso(id_opcion_menu=2, accion="editar")
def actualizar_usuario(id_usuario):
    respuesta, estado = editar_usuario(
        id_usuario,
        int(get_jwt_identity()),
        get_jwt(),
        request.get_json(silent=True),
    )
    return jsonify(respuesta), estado


@usuarios_bp.patch("/<int:id_usuario>/estado")
@requiere_permiso(id_opcion_menu=2, accion="editar")
def cambiar_estado(id_usuario):
    respuesta, estado = actualizar_estado(
        id_usuario,
        int(get_jwt_identity()),
        get_jwt(),
        request.get_json(silent=True),
    )
    return jsonify(respuesta), estado