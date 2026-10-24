import re

from flask_jwt_extended import create_access_token

from app.core.extensions import db
from app.modules.auditoria.service import registrar_actividad
from app.modules.auth.repository import (
    buscar_usuario,
    buscar_usuario_por_id,
    listar_locales_usuario,
    listar_perfiles_usuario,
    listar_puestos_usuario,
    obtener_local_usuario,
    obtener_menu,
    obtener_perfil_usuario,
    obtener_puesto_usuario,
)


ID_PERFIL_MIEMBRO_EQUIPO = 4
DOMINIO_CORPORATIVO = "barbarian.pe"


def _normalizar_correo_login(valor):
    correo = str(valor or "").strip().lower()

    if not correo:
        return None

    if "@" not in correo:
        correo = f"{correo}@{DOMINIO_CORPORATIVO}"

    partes = correo.split("@")

    if len(partes) != 2:
        return None

    nombre_usuario, dominio = partes

    if dominio != DOMINIO_CORPORATIVO:
        return None

    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]*", nombre_usuario):
        return None

    return correo


def _serializar_perfiles(perfiles):
    return [
        {
            "id_perfil": perfil["id_perfil"],
            "nombre": perfil["nombre"],
            "descripcion": perfil["descripcion"],
        }
        for perfil in perfiles
    ]


def _serializar_puestos(puestos):
    return [
        {
            "id_puesto_laboral": puesto["id_puesto_laboral"],
            "nombre": puesto["nombre"],
            "descripcion": puesto["descripcion"],
        }
        for puesto in puestos
    ]


def _serializar_locales(locales):
    return [
        {
            "id_local": local["id_local"],
            "codigo": local["codigo"],
            "nombre": local["nombre"],
            "direccion": local["direccion"],
        }
        for local in locales
    ]


def _serializar_menu(opciones_menu):
    return [
        {
            "id_opcion_menu": opcion["id_opcion_menu"],
            "codigo": opcion["codigo"],
            "nombre": opcion["nombre"],
            "url_menu": opcion["url_menu"],
            "descripcion": opcion["descripcion"],
            "id_padre": opcion["id_padre"],
            "icono": opcion["icono"],
            "tipo_opcion": opcion["tipo_opcion"],
            "es_configurable": opcion["es_configurable"],
            "orden": opcion["orden"],
            "permisos": {
                "consultar": opcion["puede_consultar"],
                "crear": opcion["puede_crear"],
                "editar": opcion["puede_editar"],
                "revisar": opcion["puede_revisar"],
                "cerrar": opcion["puede_cerrar"],
                "desactivar": opcion["puede_desactivar"],
                "reactivar": opcion["puede_reactivar"],
                "eliminar": opcion["puede_eliminar"],
                "configurar": opcion["puede_configurar"],
            },
        }
        for opcion in opciones_menu
    ]


def _serializar_usuario(usuario, perfil=None, puesto=None):
    respuesta = {
        "id_usuario": usuario["id_usuario"],
        "dni": usuario["dni"],
        "nombres": usuario["nombres"],
        "apellido_paterno": usuario["apellido_paterno"],
        "apellido_materno": usuario["apellido_materno"],
        "correo": usuario["correo_electronico"],
        "id_puesto_laboral": (
            puesto["id_puesto_laboral"] if puesto else None
        ),
        "puesto_laboral": puesto["nombre"] if puesto else None,
    }

    if perfil is not None:
        respuesta["id_perfil"] = perfil["id_perfil"]
        respuesta["perfil"] = perfil["nombre"]

    return respuesta


def _serializar_puesto_activo(puesto):
    if puesto is None:
        return None

    return {
        "id_puesto_laboral": puesto["id_puesto_laboral"],
        "nombre": puesto["nombre"],
        "descripcion": puesto["descripcion"],
    }


def _crear_token_operativo(usuario, perfil, puesto, local):
    return create_access_token(
        identity=str(usuario["id_usuario"]),
        additional_claims={
            "tipo_token": "operativo",
            "id_perfil": perfil["id_perfil"],
            "perfil": perfil["nombre"],
            "id_puesto_laboral": (
                puesto["id_puesto_laboral"] if puesto else None
            ),
            "puesto_laboral": puesto["nombre"] if puesto else None,
            "id_local": local["id_local"],
            "local": local["nombre"],
        },
    )


def _construir_sesion(
    usuario,
    perfil,
    perfiles,
    puestos,
    puesto,
    local,
    locales,
    incluir_token=True,
):
    opciones_menu = obtener_menu(perfil["id_perfil"])

    respuesta = {
        "requiere_seleccion_perfil": False,
        "usuario": _serializar_usuario(usuario, perfil, puesto),
        "perfil_activo": {
            "id_perfil": perfil["id_perfil"],
            "nombre": perfil["nombre"],
            "descripcion": perfil["descripcion"],
        },
        "perfiles_disponibles": _serializar_perfiles(perfiles),
        "puesto_activo": _serializar_puesto_activo(puesto),
        "puestos_disponibles": _serializar_puestos(puestos),
        "local_activo": {
            "id_local": local["id_local"],
            "codigo": local["codigo"],
            "nombre": local["nombre"],
            "direccion": local["direccion"],
        },
        "locales_disponibles": _serializar_locales(locales),
        "menu": _serializar_menu(opciones_menu),
    }

    if incluir_token:
        respuesta["token"] = _crear_token_operativo(
            usuario,
            perfil,
            puesto,
            local,
        )

    return respuesta


def _leer_id_perfil(datos):
    if not isinstance(datos, dict):
        return None

    try:
        id_perfil = int(datos.get("id_perfil"))
    except (TypeError, ValueError):
        return None

    return id_perfil if id_perfil > 0 else None


def _leer_id_puesto(datos):
    if not isinstance(datos, dict):
        return None

    try:
        id_puesto = int(datos.get("id_puesto_laboral"))
    except (TypeError, ValueError):
        return None

    return id_puesto if id_puesto > 0 else None


def _resolver_puesto(id_usuario, perfil, puestos, datos=None):
    if perfil["id_perfil"] != ID_PERFIL_MIEMBRO_EQUIPO:
        return None, None

    if not puestos:
        return None, "El miembro de equipo no tiene puestos asignados"

    id_puesto = _leer_id_puesto(datos)

    if id_puesto is None:
        return puestos[0], None

    puesto = obtener_puesto_usuario(id_usuario, id_puesto)

    if puesto is None:
        return None, "Ese puesto no está asignado al usuario"

    return puesto, None


def _obtener_puesto_desde_jwt(id_usuario, perfil, puestos, jwt):
    if perfil["id_perfil"] != ID_PERFIL_MIEMBRO_EQUIPO:
        return None, None

    if not puestos:
        return None, "El miembro de equipo no tiene puestos asignados"

    try:
        id_puesto = int(jwt.get("id_puesto_laboral"))
    except (TypeError, ValueError):
        return puestos[0], None

    puesto = obtener_puesto_usuario(id_usuario, id_puesto)

    if puesto is None:
        return puestos[0], None

    return puesto, None


def iniciar_sesion(datos: dict):
    datos = datos if isinstance(datos, dict) else {}
    correo = _normalizar_correo_login(datos.get("correo"))
    clave = str(datos.get("clave", ""))

    if not correo:
        return {
            "mensaje": (
                "Ingresa un usuario corporativo válido. "
                f"Ejemplo: crodriguez@{DOMINIO_CORPORATIVO}"
            )
        }, 400

    if not clave:
        return {"mensaje": "La contraseña es obligatoria"}, 400

    usuario = buscar_usuario(correo, clave)

    if usuario is None:
        return {"mensaje": "Correo o contraseña incorrectos"}, 401

    id_usuario = usuario["id_usuario"]
    perfiles = listar_perfiles_usuario(id_usuario)

    if not perfiles:
        return {
            "mensaje": "El usuario no tiene perfiles activos asignados"
        }, 403

    id_perfil = perfiles[0]["id_perfil"]
    puestos = listar_puestos_usuario(id_usuario)
    locales = listar_locales_usuario(id_usuario, id_perfil)

    if not locales:
        return {
            "mensaje": "El usuario no tiene locales activos asignados"
        }, 403

    # Los perfiles deben venir ordenados por id_perfil ascendente.
    perfil = perfiles[0]
    local = locales[0]

    puesto, error_puesto = _resolver_puesto(
        id_usuario,
        perfil,
        puestos,
    )

    if error_puesto:
        return {"mensaje": error_puesto}, 403

    respuesta = _construir_sesion(
        usuario=usuario,
        perfil=perfil,
        perfiles=perfiles,
        puestos=puestos,
        puesto=puesto,
        local=local,
        locales=locales,
    )
    respuesta["mensaje"] = (
        f"Inicio de sesión correcto como {perfil['nombre']} "
        f"en {local['nombre']}"
    )

    registrar_actividad(
        id_usuario=id_usuario,
        modulo="AUTENTICACION",
        accion="INICIAR_SESION",
        id_registro_afectado=id_usuario,
        descripcion=(
            f"Inició sesión como {perfil['nombre']} "
            f"en el local {local['nombre']}"
        ),
        id_perfil_utilizado=perfil["id_perfil"],
        id_puesto_laboral=(
            puesto["id_puesto_laboral"] if puesto else None
        ),
        id_local=local["id_local"],
    )

    db.session.commit()
    return respuesta, 200


def cambiar_perfil_activo(id_usuario: int, jwt: dict, datos: dict):
    if jwt.get("tipo_token") != "operativo":
        return {"mensaje": "La sesión no permite cambiar de perfil"}, 403

    id_perfil = _leer_id_perfil(datos)

    if id_perfil is None:
        return {"mensaje": "Selecciona un perfil válido"}, 400

    usuario = buscar_usuario_por_id(id_usuario)

    if usuario is None:
        return {"mensaje": "El usuario no existe o está desactivado"}, 404

    perfil = obtener_perfil_usuario(id_usuario, id_perfil)

    if perfil is None:
        return {"mensaje": "El perfil no está asignado al usuario"}, 403

    try:
        id_local = int(jwt.get("id_local"))
    except (TypeError, ValueError):
        return {"mensaje": "La sesión no contiene un local válido"}, 401

    local = obtener_local_usuario(id_usuario, id_local, id_perfil)

    if local is None:
        asignados = listar_locales_usuario(id_usuario, id_perfil)
        if not asignados:
            return {"mensaje": "No tienes locales asignados para este perfil"}, 403
        local = asignados[0]

    perfiles = listar_perfiles_usuario(id_usuario)
    puestos = listar_puestos_usuario(id_usuario)
    locales = listar_locales_usuario(id_usuario, id_perfil)
    puesto, error_puesto = _resolver_puesto(
        id_usuario,
        perfil,
        puestos,
        datos,
    )

    if error_puesto:
        return {"mensaje": error_puesto}, 400

    respuesta = _construir_sesion(
        usuario=usuario,
        perfil=perfil,
        perfiles=perfiles,
        puestos=puestos,
        puesto=puesto,
        local=local,
        locales=locales,
    )
    respuesta["mensaje"] = (
        f"Ahora estás trabajando como {perfil['nombre']} "
        f"en {local['nombre']}"
    )


    db.session.commit()
    return respuesta, 200


def cambiar_puesto_activo(id_usuario: int, jwt: dict, datos: dict):
    if jwt.get("tipo_token") != "operativo":
        return {"mensaje": "La sesión no permite cambiar de puesto"}, 403

    try:
        id_perfil = int(jwt.get("id_perfil"))
        id_local = int(jwt.get("id_local"))
    except (TypeError, ValueError):
        return {"mensaje": "La sesión no es válida"}, 401

    if id_perfil != ID_PERFIL_MIEMBRO_EQUIPO:
        return {
            "mensaje": "Solo Miembro de equipo utiliza un puesto activo"
        }, 403

    id_puesto = _leer_id_puesto(datos)

    if id_puesto is None:
        return {"mensaje": "Selecciona un puesto válido"}, 400

    usuario = buscar_usuario_por_id(id_usuario)
    perfil = obtener_perfil_usuario(id_usuario, id_perfil)
    puesto = obtener_puesto_usuario(id_usuario, id_puesto)
    local = obtener_local_usuario(id_usuario, id_local, id_perfil)

    if usuario is None:
        return {"mensaje": "El usuario no existe o está desactivado"}, 404
    if perfil is None:
        return {"mensaje": "El perfil ya no está asignado"}, 403
    if puesto is None:
        return {"mensaje": "El puesto no está asignado al usuario"}, 403
    if local is None:
        return {"mensaje": "El local ya no está asignado al usuario"}, 403

    perfiles = listar_perfiles_usuario(id_usuario)
    puestos = listar_puestos_usuario(id_usuario)
    locales = listar_locales_usuario(id_usuario, id_perfil)

    respuesta = _construir_sesion(
        usuario=usuario,
        perfil=perfil,
        perfiles=perfiles,
        puestos=puestos,
        puesto=puesto,
        local=local,
        locales=locales,
    )
    respuesta["mensaje"] = f"Ahora estás trabajando como {puesto['nombre']}"

    registrar_actividad(
        id_usuario=id_usuario,
        modulo="AUTENTICACION",
        accion="CAMBIAR_PUESTO",
        id_registro_afectado=id_usuario,
        descripcion=(
            f"Cambió el puesto activo a {puesto['nombre']} "
            f"en el local {local['nombre']}"
        ),
        id_perfil_utilizado=perfil["id_perfil"],
        id_puesto_laboral=puesto["id_puesto_laboral"],
        id_local=local["id_local"],
    )

    db.session.commit()
    return respuesta, 200


def cambiar_local_activo(id_usuario: int, jwt: dict, datos: dict):
    if jwt.get("tipo_token") != "operativo":
        return {"mensaje": "La sesión no permite cambiar de local"}, 403

    try:
        id_local = int((datos or {}).get("id_local"))
        id_perfil = int(jwt.get("id_perfil"))
    except (TypeError, ValueError):
        return {"mensaje": "Selecciona un local válido"}, 400

    if id_perfil not in (2, 3, 4):
        return {"mensaje": "Selecciona Gerente, Supervisor o Miembro para cambiar de local"}, 403

    usuario = buscar_usuario_por_id(id_usuario)

    if usuario is None:
        return {"mensaje": "El usuario no existe o está desactivado"}, 404

    local = obtener_local_usuario(id_usuario, id_local, id_perfil)

    if local is None:
        return {"mensaje": "No tienes acceso a ese local"}, 403

    perfil = obtener_perfil_usuario(id_usuario, id_perfil)

    if perfil is None:
        return {"mensaje": "El perfil activo ya no está asignado"}, 403

    perfiles = listar_perfiles_usuario(id_usuario)
    puestos = listar_puestos_usuario(id_usuario)
    locales = listar_locales_usuario(id_usuario, id_perfil)
    puesto, error_puesto = _obtener_puesto_desde_jwt(
        id_usuario,
        perfil,
        puestos,
        jwt,
    )

    if error_puesto:
        return {"mensaje": error_puesto}, 403

    respuesta = _construir_sesion(
        usuario=usuario,
        perfil=perfil,
        perfiles=perfiles,
        puestos=puestos,
        puesto=puesto,
        local=local,
        locales=locales,
    )
    respuesta["mensaje"] = f"Ahora estás trabajando en {local['nombre']}"

    registrar_actividad(
        id_usuario=id_usuario,
        modulo="AUTENTICACION",
        accion="CAMBIAR_LOCAL",
        id_registro_afectado=id_usuario,
        descripcion=f"Cambió el local activo a {local['nombre']}",
        id_perfil_utilizado=perfil["id_perfil"],
        id_puesto_laboral=(
            puesto["id_puesto_laboral"] if puesto else None
        ),
        id_local=local["id_local"],
    )

    db.session.commit()
    return respuesta, 200


def obtener_sesion_actual(id_usuario: int, jwt: dict):
    if jwt.get("tipo_token") != "operativo":
        return {"mensaje": "La sesión no es operativa"}, 403

    try:
        id_perfil = int(jwt.get("id_perfil"))
        id_local = int(jwt.get("id_local"))
    except (TypeError, ValueError):
        return {
            "mensaje": "La sesión no contiene perfil o local válido"
        }, 401

    usuario = buscar_usuario_por_id(id_usuario)

    if usuario is None:
        return {"mensaje": "El usuario no existe o está desactivado"}, 404

    perfil = obtener_perfil_usuario(id_usuario, id_perfil)

    if perfil is None:
        return {"mensaje": "El perfil activo ya no está asignado"}, 403

    local = obtener_local_usuario(id_usuario, id_local, id_perfil)

    if local is None:
        return {"mensaje": "El local activo ya no está asignado"}, 403

    perfiles = listar_perfiles_usuario(id_usuario)
    puestos = listar_puestos_usuario(id_usuario)
    locales = listar_locales_usuario(id_usuario, id_perfil)
    puesto, error_puesto = _obtener_puesto_desde_jwt(
        id_usuario,
        perfil,
        puestos,
        jwt,
    )

    if error_puesto:
        return {"mensaje": error_puesto}, 403

    return _construir_sesion(
        usuario=usuario,
        perfil=perfil,
        perfiles=perfiles,
        puestos=puestos,
        puesto=puesto,
        local=local,
        locales=locales,
        incluir_token=False,
    ), 200
