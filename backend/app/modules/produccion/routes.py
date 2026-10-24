from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity
from app.modules.produccion.subproduct_editor import formulario_subproducto, guardar_subproducto

from app.core.permissions import requiere_permiso
from app.modules.produccion.service import (
    obtener_grupos_salsa,
    obtener_subproductos,
)


produccion_bp = Blueprint(
    "produccion",
    __name__,
)


@produccion_bp.get("/subproductos")
@requiere_permiso(
    id_opcion_menu=12,
    accion="consultar",
)
def consultar_subproductos():
    respuesta, estado = obtener_subproductos()

    return jsonify(respuesta), estado


@produccion_bp.get('/subproductos/formulario')
@requiere_permiso(id_opcion_menu=12, accion='consultar')
def consultar_formulario_subproducto():
    respuesta, estado = formulario_subproducto()
    return jsonify(respuesta), estado


@produccion_bp.post('/subproductos')
@requiere_permiso(id_opcion_menu=12, accion='crear')
def crear_subproducto():
    respuesta, estado = guardar_subproducto(int(get_jwt_identity()), request.get_json(silent=True))
    return jsonify(respuesta), estado


@produccion_bp.put('/subproductos/<int:id_subproducto>')
@requiere_permiso(id_opcion_menu=12, accion='editar')
def editar_subproducto(id_subproducto):
    respuesta, estado = guardar_subproducto(int(get_jwt_identity()), request.get_json(silent=True), id_subproducto)
    return jsonify(respuesta), estado


@produccion_bp.get("/grupos-salsa")
@requiere_permiso(
    id_opcion_menu=13,
    accion="consultar",
)
def consultar_grupos_salsa():
    respuesta, estado = obtener_grupos_salsa()

    return jsonify(respuesta), estado
