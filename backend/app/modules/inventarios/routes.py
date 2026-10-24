from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity

from app.core.permissions import requiere_permiso
from app.modules.inventarios.service import (
    cerrar_inventario_actual,
    guardar_inventario_actual,
    iniciar_inventario_actual,
    obtener_detalle_revision,
    obtener_inventario_actual,
    obtener_inventarios_para_revision,
    obtener_resumen_inventario,
    obtener_stock_actual,
    registrar_revision_inventario,
    corregir_inventario_cerrado,
    obtener_historial_correcciones,
)



inventarios_bp = Blueprint("inventarios", __name__)


@inventarios_bp.before_request
def proteger_conteos_anteriores():
    # Los registros históricos dejan de ser una fuente mutable del stock.
    from app.modules.inventarios.operativo import instalado
    from werkzeug.exceptions import Conflict
    if request.method in ('POST','PUT','DELETE','PATCH') and instalado():
        raise Conflict('Usa Real vs. teórico. Los inventarios de cierre anteriores son históricos.')


@inventarios_bp.get("/resumen")
@requiere_permiso(
    id_opcion_menu=16,
    accion="consultar",
)
def consultar_resumen_inventario():
    respuesta, estado = obtener_resumen_inventario()

    return jsonify(respuesta), estado


@inventarios_bp.get("/stock")
@requiere_permiso(
    id_opcion_menu=15,
    accion="consultar",
)
def consultar_stock():
    respuesta, estado = obtener_stock_actual()

    return jsonify(respuesta), estado


@inventarios_bp.get("/actual")
@requiere_permiso(
    id_opcion_menu=17,
    accion="consultar",
)
def consultar_inventario_actual():
    respuesta, estado = obtener_inventario_actual()

    return jsonify(respuesta), estado


@inventarios_bp.post("/actual/iniciar")
@requiere_permiso(
    id_opcion_menu=17,
    accion="crear",
)
def iniciar_inventario():
    id_usuario = int(get_jwt_identity())
    datos = request.get_json(silent=True)

    respuesta, estado = iniciar_inventario_actual(
        id_usuario,
        datos,
    )

    return jsonify(respuesta), estado


@inventarios_bp.put("/actual/guardar")
@requiere_permiso(
    id_opcion_menu=17,
    accion="editar",
)
def guardar_inventario():
    id_usuario = int(get_jwt_identity())
    datos = request.get_json(silent=True)

    respuesta, estado = guardar_inventario_actual(
        id_usuario,
        datos,
    )

    return jsonify(respuesta), estado


@inventarios_bp.post("/actual/cerrar")
@requiere_permiso(
    id_opcion_menu=17,
    accion="editar",
)
def cerrar_inventario():
    id_usuario = int(get_jwt_identity())
    datos = request.get_json(silent=True)

    respuesta, estado = cerrar_inventario_actual(
        id_usuario,
        datos,
    )

    return jsonify(respuesta), estado


@inventarios_bp.get("/revisiones")
@requiere_permiso(
    id_opcion_menu=18,
    accion="consultar",
)
def consultar_inventarios_para_revision():
    respuesta, estado = (
        obtener_inventarios_para_revision()
    )

    return jsonify(respuesta), estado


@inventarios_bp.get(
    "/revisiones/<int:id_inventario>"
)
@requiere_permiso(
    id_opcion_menu=18,
    accion="consultar",
)
def consultar_detalle_revision(id_inventario):
    respuesta, estado = obtener_detalle_revision(
        id_inventario
    )

    return jsonify(respuesta), estado


@inventarios_bp.put(
    "/revisiones/<int:id_inventario>"
)
@requiere_permiso(
    id_opcion_menu=18,
    accion="revisar",
)
def revisar_inventario_cerrado(id_inventario):
    id_usuario = int(get_jwt_identity())
    datos = request.get_json(silent=True)

    respuesta, estado = registrar_revision_inventario(
        id_inventario=id_inventario,
        id_usuario=id_usuario,
        datos=datos,
    )

    return jsonify(respuesta), estado


@inventarios_bp.put(
    "/revisiones/<int:id_inventario>/corregir"
)
@requiere_permiso(
    id_opcion_menu=18,
    accion="editar",
)
def corregir_inventario(id_inventario):
    id_usuario = int(get_jwt_identity())
    datos = request.get_json(silent=True)

    respuesta, estado = corregir_inventario_cerrado(
        id_inventario=id_inventario,
        id_usuario=id_usuario,
        datos=datos,
    )

    return jsonify(respuesta), estado


@inventarios_bp.get(
    "/revisiones/<int:id_inventario>/correcciones"
)
@requiere_permiso(
    id_opcion_menu=18,
    accion="consultar",
)
def consultar_correcciones_inventario(id_inventario):
    respuesta, estado = obtener_historial_correcciones(
        id_inventario
    )

    return jsonify(respuesta), estado
