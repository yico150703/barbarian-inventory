from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity

from app.core.permissions import requiere_permiso
from app.modules.recetas.service import obtener_recetas
from app.modules.recetas.editor_service import obtener_formulario, guardar_receta

recetas_bp = Blueprint("recetas", __name__)


@recetas_bp.get("")
@requiere_permiso(id_opcion_menu=28, accion="consultar")
def consultar_recetas():
    respuesta, estado = obtener_recetas()
    return jsonify(respuesta), estado


@recetas_bp.get("/formulario")
@requiere_permiso(28, "consultar")
def consultar_formulario():
    respuesta, estado = obtener_formulario()
    return jsonify(respuesta), estado


@recetas_bp.post("")
@requiere_permiso(28, "crear")
def crear_receta():
    respuesta, estado = guardar_receta(int(get_jwt_identity()), request.get_json(silent=True))
    return jsonify(respuesta), estado


@recetas_bp.put("/<int:id_receta>")
@requiere_permiso(28, "editar")
def editar_receta(id_receta):
    respuesta, estado = guardar_receta(int(get_jwt_identity()), request.get_json(silent=True), id_receta)
    return jsonify(respuesta), estado
