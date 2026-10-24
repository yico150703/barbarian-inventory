from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity
from sqlalchemy import text
from app.core.extensions import db
from app.modules.promociones.editor import formulario_promocion, guardar_promocion

from app.core.permissions import requiere_permiso
from app.modules.promociones.service import (
    obtener_promociones,
)


promociones_bp = Blueprint(
    "promociones",
    __name__,
)


def migracion_reposiciones_pendiente():
    if not db.session.execute(text("SELECT to_regclass('public.promocion_reposicion') IS NOT NULL")).scalar():
        return jsonify(mensaje='Falta ejecutar database/migrations/20261016_promociones_reposicion_salon.sql'), 503
    return None


@promociones_bp.get('/formulario')
@requiere_permiso(14, 'consultar')
def formulario():
    pendiente = migracion_reposiciones_pendiente()
    if pendiente: return pendiente
    datos, estado = formulario_promocion()
    return jsonify(datos), estado


@promociones_bp.post('')
@requiere_permiso(14, 'crear')
def crear():
    pendiente = migracion_reposiciones_pendiente()
    if pendiente: return pendiente
    datos, estado = guardar_promocion(int(get_jwt_identity()), request.get_json(silent=True))
    return jsonify(datos), estado


@promociones_bp.put('/<int:id_promocion>')
@requiere_permiso(14, 'editar')
def editar(id_promocion):
    pendiente = migracion_reposiciones_pendiente()
    if pendiente: return pendiente
    datos, estado = guardar_promocion(int(get_jwt_identity()), request.get_json(silent=True), id_promocion)
    return jsonify(datos), estado


@promociones_bp.get("")
@requiere_permiso(
    id_opcion_menu=14,
    accion="consultar",
)
def consultar_promociones():
    pendiente = migracion_reposiciones_pendiente()
    if pendiente: return pendiente
    respuesta, estado = obtener_promociones()

    return jsonify(respuesta), estado
