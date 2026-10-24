from flask import has_request_context
from flask_jwt_extended import get_jwt

from app.modules.auditoria.repository import (
    consultar_actividades,
    insertar_actividad,
    insertar_auditoria_cambio,
)


def _obtener_contexto_del_token():
    if not has_request_context():
        return None, None, None

    try:
        jwt = get_jwt()
    except RuntimeError:
        return None, None, None

    try:
        id_perfil = int(jwt.get("id_perfil"))
    except (TypeError, ValueError):
        id_perfil = None

    try:
        id_puesto = int(jwt.get("id_puesto_laboral"))
    except (TypeError, ValueError):
        id_puesto = None

    try:
        id_local = int(jwt.get("id_local"))
    except (TypeError, ValueError):
        id_local = None

    return id_perfil, id_puesto, id_local


def registrar_actividad(
    id_usuario: int,
    modulo: str,
    accion: str,
    id_registro_afectado: int | None,
    descripcion: str,
    id_perfil_utilizado: int | None = None,
    id_puesto_laboral: int | None = None,
    id_local: int | None = None,
):
    perfil_token, puesto_token, local_token = _obtener_contexto_del_token()

    if id_perfil_utilizado is None:
        id_perfil_utilizado = perfil_token
    if id_puesto_laboral is None:
        id_puesto_laboral = puesto_token
    if id_local is None:
        id_local = local_token if perfil_token != 1 else None

    return insertar_actividad(
        id_usuario=id_usuario,
        modulo=modulo.upper(),
        accion=accion.upper(),
        id_registro_afectado=id_registro_afectado,
        descripcion=descripcion,
        id_perfil_utilizado=id_perfil_utilizado,
        id_puesto_laboral=id_puesto_laboral,
        id_local=id_local,
    )


def listar_actividades(limite: int = 50):
    limite = max(1, min(limite, 100))
    actividades = consultar_actividades(limite)

    return [
        {
            "id_actividad_usuario": actividad["id_actividad_usuario"],
            "id_usuario": actividad["id_usuario"],
            "usuario": actividad["usuario"],
            "id_perfil_utilizado": actividad["id_perfil_utilizado"],
            "perfil_utilizado": actividad["perfil_utilizado"],
            "id_puesto_laboral": actividad["id_puesto_laboral"],
            "puesto_laboral": actividad["puesto_laboral"],
            "id_local": actividad["id_local"],
            "local": actividad["local"],
            "modulo": actividad["modulo"],
            "accion": actividad["accion"],
            "id_registro_afectado": actividad["id_registro_afectado"],
            "descripcion": actividad["descripcion"],
            "fecha_actividad": actividad["fecha_actividad"].isoformat(),
        }
        for actividad in actividades
    ]


def registrar_cambio(
    id_usuario: int,
    modulo: str,
    accion: str,
    tabla_afectada: str,
    id_registro_afectado: int | None,
    datos_anteriores,
    datos_nuevos,
    motivo: str | None = None,
    id_perfil_utilizado: int | None = None,
    id_puesto_laboral: int | None = None,
    id_local: int | None = None,
):
    perfil_token, puesto_token, local_token = _obtener_contexto_del_token()

    if id_perfil_utilizado is None:
        id_perfil_utilizado = perfil_token
    if id_puesto_laboral is None:
        id_puesto_laboral = puesto_token
    if id_local is None:
        id_local = local_token if perfil_token != 1 else None

    return insertar_auditoria_cambio(
        id_usuario=id_usuario,
        id_perfil_utilizado=id_perfil_utilizado,
        id_puesto_laboral=id_puesto_laboral,
        id_local=id_local,
        modulo=modulo,
        accion=accion,
        tabla_afectada=tabla_afectada,
        id_registro_afectado=id_registro_afectado,
        datos_anteriores=datos_anteriores,
        datos_nuevos=datos_nuevos,
        motivo=motivo,
    )
