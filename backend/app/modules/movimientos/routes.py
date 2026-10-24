from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity

from app.core.permissions import requiere_permiso
from app.modules.movimientos.service import (
    obtener_formulario_movimiento,
    registrar_movimiento,
)


movimientos_bp = Blueprint("movimientos", __name__)


@movimientos_bp.get("/formulario")
@requiere_permiso(
    id_opcion_menu=20,
    accion="consultar",
)
def consultar_formulario_movimiento():
    respuesta, estado = obtener_formulario_movimiento()

    return jsonify(respuesta), estado


@movimientos_bp.post("")
@requiere_permiso(
    id_opcion_menu=20,
    accion="crear",
)
def crear_movimiento():
    id_usuario = int(get_jwt_identity())
    datos = request.get_json(silent=True)

    respuesta, estado = registrar_movimiento(
        id_usuario,
        datos,
    )

    return jsonify(respuesta), estado

@movimientos_bp.get('/seguimiento')
@requiere_permiso(id_opcion_menu=20, accion='consultar')
def seguimiento_movimientos():
    from app.modules.movimientos.tracking import listar
    return jsonify(listar())


@movimientos_bp.post('/<int:identidad>/recibir')
@requiere_permiso(id_opcion_menu=20, accion='crear')
def recibir_movimiento(identidad):
    from app.modules.movimientos.tracking import recibir
    respuesta, estado = recibir(identidad, request.get_json(silent=True), int(get_jwt_identity()))
    return jsonify(respuesta), estado
