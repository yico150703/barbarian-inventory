from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity

from app.core.permissions import requiere_permiso
from app.modules.compras.service import (
    obtener_formulario_orden,
    obtener_pedido_sugerido,
    registrar_orden,
    cambiar_estado_orden,
    obtener_detalle_orden,
    obtener_historial_ordenes,
)


compras_bp = Blueprint("compras", __name__)


@compras_bp.get("/formulario")
@requiere_permiso(id_opcion_menu=22, accion="consultar")
def consultar_formulario():
    respuesta, estado = obtener_formulario_orden()
    return jsonify(respuesta), estado


@compras_bp.get("/pedido-sugerido")
@requiere_permiso(id_opcion_menu=22, accion="consultar")
def consultar_pedido_sugerido():
    respuesta, estado = obtener_pedido_sugerido()
    return jsonify(respuesta), estado


@compras_bp.post("")
@requiere_permiso(id_opcion_menu=22, accion="crear")
def crear_orden():
    respuesta, estado = registrar_orden(
        int(get_jwt_identity()),
        request.get_json(silent=True),
    )
    return jsonify(respuesta), estado

@compras_bp.get("/historial")
@requiere_permiso(id_opcion_menu=31, accion="consultar")
def consultar_historial_ordenes():
    respuesta, estado = obtener_historial_ordenes(
        request.args.get("fecha_desde"),
        request.args.get("fecha_hasta"),
        request.args.get("estado"),
    )
    return jsonify(respuesta), estado


@compras_bp.get("/<int:id_orden>")
@requiere_permiso(id_opcion_menu=31, accion="consultar")
def consultar_detalle_orden(id_orden):
    respuesta, estado = obtener_detalle_orden(id_orden)
    return jsonify(respuesta), estado


@compras_bp.patch("/<int:id_orden>/estado")
@requiere_permiso(id_opcion_menu=31, accion="cerrar")
def modificar_estado_orden(id_orden):
    respuesta, estado = cambiar_estado_orden(
        id_orden,
        int(get_jwt_identity()),
        request.get_json(silent=True),
    )
    return jsonify(respuesta), estado