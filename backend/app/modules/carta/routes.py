from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity
from app.modules.carta.category_admin import modificar_categoria
from app.modules.carta.presentation_editor import formulario_presentacion, guardar_presentacion
from app.modules.carta.tableware_admin import guardar_menaje

from app.core.permissions import requiere_permiso
from app.modules.carta.service import (
    obtener_categorias_carta,
    obtener_menajes,
    obtener_presentaciones_venta,
)

carta_bp = Blueprint(
    "carta",
    __name__,
)


@carta_bp.post('/menajes')
@requiere_permiso(10, 'crear')
def crear_menaje():
    if int(get_jwt()['id_perfil']) != 1:
        return jsonify({'mensaje': 'Solo el administrador puede gestionar menajes'}), 403
    respuesta, estado = guardar_menaje(int(get_jwt_identity()), 'crear', request.get_json(silent=True))
    return jsonify(respuesta), estado


@carta_bp.post('/menajes/<int:id_menaje>/<accion>')
def administrar_menaje(id_menaje, accion):
    if accion not in ('editar', 'desactivar', 'reactivar', 'eliminar'):
        return jsonify({'mensaje': 'Accion invalida'}), 404

    @requiere_permiso(10, accion)
    def autorizado():
        if int(get_jwt()['id_perfil']) != 1:
            return jsonify({'mensaje': 'Solo el administrador puede gestionar menajes'}), 403
        respuesta, estado = guardar_menaje(int(get_jwt_identity()), accion, request.get_json(silent=True), id_menaje)
        return jsonify(respuesta), estado
    return autorizado()


@carta_bp.get('/presentaciones/formulario')
@requiere_permiso(9, 'consultar')
def formulario_carta():
    respuesta, estado = formulario_presentacion()
    return jsonify(respuesta), estado


@carta_bp.post('/presentaciones')
@requiere_permiso(9, 'crear')
def crear_presentacion():
    respuesta, estado = guardar_presentacion(int(get_jwt_identity()), request.get_json(silent=True))
    return jsonify(respuesta), estado


@carta_bp.put('/presentaciones/<int:id_presentacion>')
@requiere_permiso(9, 'editar')
def editar_presentacion(id_presentacion):
    respuesta, estado = guardar_presentacion(int(get_jwt_identity()), request.get_json(silent=True), id_presentacion)
    return jsonify(respuesta), estado


@carta_bp.post('/categorias/<int:id_categoria>/<accion>')
def administrar_categoria(id_categoria, accion):
    if accion not in ('editar', 'reasignar', 'desactivar', 'reactivar'):
        return jsonify({'mensaje': 'Accion invalida'}), 404

    @requiere_permiso(8, 'editar' if accion == 'reasignar' else accion)
    def autorizado():
        if int(get_jwt()['id_perfil']) != 1:
            return jsonify({'mensaje': 'Solo el administrador puede gestionar categorias de carta'}), 403
        respuesta, estado = modificar_categoria(id_categoria, int(get_jwt_identity()), accion,
                                                request.get_json(silent=True))
        return jsonify(respuesta), estado
    return autorizado()


@carta_bp.post('/categorias')
@requiere_permiso(8, 'crear')
def crear_categoria_carta():
    if int(get_jwt()['id_perfil']) != 1:
        return jsonify({'mensaje': 'Solo el administrador puede gestionar categorias de carta'}), 403
    respuesta, estado = modificar_categoria(0, int(get_jwt_identity()), 'crear', request.get_json(silent=True))
    return jsonify(respuesta), estado


@carta_bp.get("/categorias")
@requiere_permiso(
    id_opcion_menu=8,
    accion="consultar",
)
def consultar_categorias_carta():
    respuesta, estado = obtener_categorias_carta()

    return jsonify(respuesta), estado

@carta_bp.get("/presentaciones")
@requiere_permiso(
    id_opcion_menu=9,
    accion="consultar",
)
def consultar_presentaciones_venta():
    respuesta, estado = obtener_presentaciones_venta()

    return jsonify(respuesta), estado


@carta_bp.get("/menajes")
@requiere_permiso(
    id_opcion_menu=10,
    accion="consultar",
)
def consultar_menajes():
    respuesta, estado = obtener_menajes()

    return jsonify(respuesta), estado
