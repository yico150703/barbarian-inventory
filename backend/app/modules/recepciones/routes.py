
from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity

from app.core.permissions import requiere_permiso
from app.modules.recepciones.service import (
    obtener_pendientes,
    registrar_recepcion,
    corregir_recepcion,
    obtener_detalle_recepcion,
    obtener_historial_recepciones,
)


recepciones_bp = Blueprint("recepciones", __name__)


@recepciones_bp.get("/pendientes")
@requiere_permiso(id_opcion_menu=24, accion="consultar")
def consultar_pendientes():
    respuesta, estado = obtener_pendientes()
    return jsonify(respuesta), estado


@recepciones_bp.post("/ordenes/<int:id_orden>/recepciones")
@requiere_permiso(id_opcion_menu=24, accion="crear")
def crear_recepcion(id_orden):
    respuesta, estado = registrar_recepcion(
        id_orden,
        int(get_jwt_identity()),
        request.get_json(silent=True),
    )
    return jsonify(respuesta), estado

@recepciones_bp.get("/historial")
@requiere_permiso(id_opcion_menu=32, accion="consultar")
def consultar_historial_recepciones():
    respuesta, estado = obtener_historial_recepciones(
        request.args.get("fecha_desde"),
        request.args.get("fecha_hasta"),
        request.args.get("id_proveedor"),
    )
    return jsonify(respuesta), estado


@recepciones_bp.get("/<int:id_factura>")
@requiere_permiso(id_opcion_menu=32, accion="consultar")
def consultar_detalle_recepcion(id_factura):
    respuesta, estado = obtener_detalle_recepcion(id_factura)
    return jsonify(respuesta), estado


@recepciones_bp.patch("/<int:id_factura>")
@requiere_permiso(id_opcion_menu=32, accion="editar")
def modificar_recepcion(id_factura):
    respuesta, estado = corregir_recepcion(
        id_factura,
        int(get_jwt_identity()),
        request.get_json(silent=True),
    )
    return jsonify(respuesta), estado