from flask import Blueprint, jsonify, request

from app.core.permissions import requiere_permiso
from app.modules.auditoria.service import listar_actividades

auditoria_bp = Blueprint("auditoria", __name__)


@auditoria_bp.get('/historial')
@requiere_permiso(id_opcion_menu=26, accion='consultar')
def historial_actividades():
    from app.modules.auditoria.history import historial
    return jsonify(historial(request.args))


@auditoria_bp.get("")
@requiere_permiso(id_opcion_menu=26, accion="consultar")
def obtener_actividades():
    limite = request.args.get("limite", default=50, type=int)

    return jsonify({
        "actividades": listar_actividades(limite)
    }), 200
