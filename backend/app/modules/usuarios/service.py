import re

from app.core.extensions import db
from app.core.local_scope import local_actual
from app.modules.auditoria.service import registrar_actividad
from app.modules.usuarios.repository import (
    actualizar_usuario,
    buscar_usuario_gestionable,
    cambiar_estado_usuario,
    crear_usuario,
    existe_correo,
    existe_dni,
    listar_locales_activos,
    listar_perfiles_permitidos,
    listar_puestos_laborales,
    listar_usuarios_permitidos,
    locales_activos_validos,
    perfil_puede_gestionarse,
    puestos_laborales_existen,
    sincronizar_perfiles,
    sincronizar_locales_usuario,
    sincronizar_puestos_laborales,
)


ID_PERFIL_ADMINISTRADOR = 1
ID_PERFIL_MIEMBRO_EQUIPO = 4
DOMINIO_CORPORATIVO = "barbarian.pe"

def _normalizar_correo_corporativo(valor):
    correo = str(valor or "").strip().lower()

    if not correo:
        return None

    # El frontend puede enviar "crodriguez"
    # o el correo corporativo completo.
    if "@" not in correo:
        correo = f"{correo}@{DOMINIO_CORPORATIVO}"

    partes = correo.split("@")

    if len(partes) != 2:
        return None

    nombre_usuario, dominio = partes

    if dominio != DOMINIO_CORPORATIVO:
        return None

    if not re.fullmatch(
        r"[a-z0-9][a-z0-9._-]*",
        nombre_usuario,
    ):
        return None

    return correo

def _perfil_gestor(jwt: dict):
    try:
        return int(jwt.get("id_perfil"))
    except (TypeError, ValueError):
        return None


def _local_activo(jwt: dict):
    return local_actual()


def _normalizar_ids_perfiles(valor):
    if not isinstance(valor, list) or not valor:
        return None

    ids = []

    for elemento in valor:
        try:
            id_perfil = int(elemento)
        except (TypeError, ValueError):
            return None

        if id_perfil <= 0:
            return None

        if id_perfil not in ids:
            ids.append(id_perfil)

    return ids


def _normalizar_ids_puestos(valor):
    if valor is None:
        return []
    if not isinstance(valor, list):
        return None
    try:
        ids = sorted({int(elemento) for elemento in valor})
    except (TypeError, ValueError):
        return None
    if any(id_puesto <= 0 for id_puesto in ids):
        return None
    return ids


def _normalizar_ids_locales(valor):
    if not isinstance(valor, list) or not valor:
        return None

    try:
        ids = sorted({int(elemento) for elemento in valor})
    except (TypeError, ValueError):
        return None

    if any(id_local <= 0 for id_local in ids):
        return None

    return ids


def _validar_datos(datos, editando=False):
    if not isinstance(datos, dict):
        return None, "Debes enviar un objeto JSON válido"

    limpios = {
        "dni": str(datos.get("dni", "")).strip(),
        "nombres": str(datos.get("nombres", "")).strip(),
        "apellido_paterno": str(
            datos.get("apellido_paterno", "")
        ).strip(),
        "apellido_materno": (
            str(datos.get("apellido_materno", "")).strip()
            or None
        ),
        "celular": str(datos.get("celular", "")).strip(),
        "correo": _normalizar_correo_corporativo(
            datos.get("correo_electronico")
        ),
    }

    if not re.fullmatch(r"\d{8}", limpios["dni"]):
        return None, "El DNI debe tener exactamente 8 números"

    if not re.fullmatch(r"\d{9,15}", limpios["celular"]):
        return None, "El celular debe tener entre 9 y 15 números"

    if not limpios["nombres"]:
        return None, "Ingresa los nombres"

    if not limpios["apellido_paterno"]:
        return None, "Ingresa el apellido paterno"

    if limpios["correo"] is None:
        return (
            None,
            (
                "Ingresa un usuario corporativo válido. "
                f"El dominio permitido es @{DOMINIO_CORPORATIVO}"
            ),
        )

    clave = str(datos.get("clave", ""))

    if not editando and len(clave) < 8:
        return None, "La contraseña debe tener al menos 8 caracteres"

    if editando and clave and len(clave) < 8:
        return None, "La nueva contraseña debe tener al menos 8 caracteres"

    ids_perfiles = _normalizar_ids_perfiles(
        datos.get("ids_perfiles")
    )

    if ids_perfiles is None:
        return None, "Selecciona al menos un perfil válido"

    ids_puestos_laborales = _normalizar_ids_puestos(
        datos.get("ids_puestos_laborales")
    )

    if ids_puestos_laborales is None:
        return None, "Los puestos laborales seleccionados no son válidos"

    if (
        ID_PERFIL_MIEMBRO_EQUIPO in ids_perfiles
        and not ids_puestos_laborales
    ):
        return (
            None,
            "Selecciona el puesto laboral del miembro de equipo",
        )

    # El puesto solo aplica cuando se asigna Miembro de equipo.
    if ID_PERFIL_MIEMBRO_EQUIPO not in ids_perfiles:
        ids_puestos_laborales = []

    if (
        ids_puestos_laborales
        and not puestos_laborales_existen(ids_puestos_laborales)
    ):
        return None, "El puesto laboral seleccionado no está disponible"

    ids_locales = _normalizar_ids_locales(
        datos.get("ids_locales")
    )

    if ids_locales is None:
        return None, "Selecciona al menos un local válido"

    if not locales_activos_validos(ids_locales):
        return None, "Uno de los locales seleccionados no existe"

    return {
        "datos": limpios,
        "ids_perfiles": ids_perfiles,
        "ids_puestos_laborales": ids_puestos_laborales,
        "ids_locales": ids_locales,
        "clave": clave or None,
    }, None


def _validar_perfiles_gestionables(
    id_perfil_gestor: int,
    ids_perfiles: list[int],
    accion: str,
):
    for id_perfil in ids_perfiles:
        if not perfil_puede_gestionarse(
            id_perfil_gestor,
            id_perfil,
            accion,
        ):
            return False

    return True


def _validar_locales_asignables(
    jwt: dict,
    ids_locales: list[int],
):
    id_perfil = _perfil_gestor(jwt)
    id_local = _local_activo(jwt)

    if id_perfil == ID_PERFIL_ADMINISTRADOR:
        return True

    return id_local is not None and ids_locales == [id_local]


def obtener_usuarios(jwt: dict):
    id_perfil = _perfil_gestor(jwt)

    if id_perfil is None:
        return {
            "mensaje": "La sesión no contiene un perfil válido"
        }, 401

    id_local = _local_activo(jwt)

    if id_local is None:
        return {
            "mensaje": "La sesión no contiene un local válido"
        }, 401

    usuarios = listar_usuarios_permitidos(id_perfil, id_local)
    perfiles = listar_perfiles_permitidos(id_perfil)
    puestos = listar_puestos_laborales()
    locales = listar_locales_activos()

    usuarios_serializados = []

    for usuario in usuarios:
        elemento = dict(usuario)
        elemento["fecha_creacion"] = (
            usuario["fecha_creacion"].isoformat()
        )
        elemento["ids_perfiles"] = list(
            usuario["ids_perfiles"] or []
        )
        elemento["perfiles"] = list(
            usuario["perfiles"] or []
        )
        elemento["ids_puestos_laborales"] = list(
            usuario["ids_puestos_laborales"] or []
        )
        elemento["puestos_laborales"] = list(
            usuario["puestos_laborales"] or []
        )
        elemento["ids_locales"] = list(
            usuario["ids_locales"] or []
        )
        elemento["locales"] = list(
            usuario["locales"] or []
        )
        usuarios_serializados.append(elemento)

    return {
        "usuarios": usuarios_serializados,
        "perfiles_permitidos": [
            dict(perfil)
            for perfil in perfiles
        ],
        "puestos_laborales": [
            dict(puesto)
            for puesto in puestos
        ],
        "locales": [
            dict(local)
            for local in locales
        ],
        "id_local_activo": id_local,
        "resumen": {
            "total": len(usuarios_serializados),
            "activos": sum(
                usuario["estado_registro"] == 1
                for usuario in usuarios_serializados
            ),
            "inactivos": sum(
                usuario["estado_registro"] == 0
                for usuario in usuarios_serializados
            ),
        },
    }, 200


def registrar_usuario(
    id_gestor: int,
    jwt: dict,
    datos,
):
    validado, error = _validar_datos(datos)

    if error:
        return {"mensaje": error}, 400

    id_perfil_gestor = _perfil_gestor(jwt)

    if id_perfil_gestor is None:
        return {
            "mensaje": "La sesión no contiene un perfil válido"
        }, 401

    id_local = _local_activo(jwt)

    if id_local is None:
        return {
            "mensaje": "La sesión no contiene un local válido"
        }, 401

    if not _validar_locales_asignables(
        jwt,
        validado["ids_locales"],
    ):
        return {
            "mensaje": "Solo puedes asignar usuarios al local activo"
        }, 403

    if not _validar_perfiles_gestionables(
        id_perfil_gestor,
        validado["ids_perfiles"],
        "crear",
    ):
        return {
            "mensaje": "No puedes crear usuarios con uno de esos perfiles"
        }, 403

    if existe_dni(validado["datos"]["dni"]):
        return {"mensaje": "El DNI ya está registrado"}, 409

    if existe_correo(validado["datos"]["correo"]):
        return {"mensaje": "El correo ya está registrado"}, 409

    try:
        id_usuario = crear_usuario(
            datos=validado["datos"],
            clave_hash=validado["clave"],
            id_gestor=id_gestor,
        )

        sincronizar_perfiles(
            id_usuario=id_usuario,
            ids_perfiles=validado["ids_perfiles"],
            id_gestor=id_gestor,
        )
        sincronizar_puestos_laborales(
            id_usuario=id_usuario,
            ids_puestos_laborales=validado["ids_puestos_laborales"],
            id_gestor=id_gestor,
        )
        sincronizar_locales_usuario(
            id_usuario=id_usuario,
            ids_locales=validado["ids_locales"],
            id_gestor=id_gestor,
        )

        from app.modules.auth.salon import guardar_pin
        guardar_pin(id_usuario, datos)

        registrar_actividad(
            id_usuario=id_gestor,
            modulo="USUARIOS",
            accion="CREAR",
            id_registro_afectado=id_usuario,
            descripcion=(
                "Registró un usuario con "
                f"{len(validado['ids_perfiles'])} perfil(es)"
            ),
            id_perfil_utilizado=id_perfil_gestor,
            id_puesto_laboral=jwt.get("id_puesto_laboral"),
            id_local=id_local,
        )

        db.session.commit()

        return {
            "mensaje": "Usuario creado correctamente",
            "id_usuario": id_usuario,
        }, 201

    except Exception:
        db.session.rollback()
        raise


def editar_usuario(
    id_usuario: int,
    id_gestor: int,
    jwt: dict,
    datos,
):
    id_perfil_gestor = _perfil_gestor(jwt)

    if id_perfil_gestor is None:
        return {
            "mensaje": "La sesión no contiene un perfil válido"
        }, 401

    id_local = _local_activo(jwt)

    if id_local is None:
        return {
            "mensaje": "La sesión no contiene un local válido"
        }, 401

    objetivo = buscar_usuario_gestionable(
        id_usuario,
        id_perfil_gestor,
        id_local,
    )

    if objetivo is None:
        return {
            "mensaje": "No puedes modificar este usuario"
        }, 403

    validado, error = _validar_datos(
        datos,
        editando=True,
    )

    if error:
        return {"mensaje": error}, 400

    if not _validar_locales_asignables(
        jwt,
        validado["ids_locales"],
    ):
        return {
            "mensaje": "Solo puedes asignar usuarios al local activo"
        }, 403

    if (
        id_usuario == id_gestor
        and id_perfil_gestor != 1
        and id_local not in validado["ids_locales"]
    ):
        return {
            "mensaje": "No puedes retirar de tu cuenta el local activo"
        }, 400

    if not _validar_perfiles_gestionables(
        id_perfil_gestor,
        validado["ids_perfiles"],
        "editar",
    ):
        return {
            "mensaje": "No puedes asignar uno de esos perfiles"
        }, 403

    # Una persona no puede retirar de sí misma el perfil con el
    # que está trabajando actualmente.
    if (
        id_usuario == id_gestor
        and id_perfil_gestor not in validado["ids_perfiles"]
    ):
        return {
            "mensaje": (
                "No puedes retirar de tu cuenta el perfil "
                "que estás utilizando actualmente"
            )
        }, 400

    if existe_dni(
        validado["datos"]["dni"],
        id_usuario,
    ):
        return {"mensaje": "El DNI ya está registrado"}, 409

    if existe_correo(
        validado["datos"]["correo"],
        id_usuario,
    ):
        return {"mensaje": "El correo ya está registrado"}, 409

    try:
        clave_hash = validado["clave"]

        actualizar_usuario(
            id_usuario=id_usuario,
            datos=validado["datos"],
            id_gestor=id_gestor,
            clave_hash=clave_hash,
        )

        sincronizar_perfiles(
            id_usuario=id_usuario,
            ids_perfiles=validado["ids_perfiles"],
            id_gestor=id_gestor,
        )
        sincronizar_puestos_laborales(
            id_usuario=id_usuario,
            ids_puestos_laborales=validado["ids_puestos_laborales"],
            id_gestor=id_gestor,
        )
        sincronizar_locales_usuario(
            id_usuario=id_usuario,
            ids_locales=validado["ids_locales"],
            id_gestor=id_gestor,
        )

        from app.modules.auth.salon import guardar_pin
        guardar_pin(id_usuario, datos)

        registrar_actividad(
            id_usuario=id_gestor,
            modulo="USUARIOS",
            accion="EDITAR",
            id_registro_afectado=id_usuario,
            descripcion=(
                "Actualizó un usuario y sus perfiles asignados"
            ),
            id_perfil_utilizado=id_perfil_gestor,
            id_puesto_laboral=jwt.get("id_puesto_laboral"),
            id_local=id_local,
        )

        db.session.commit()

        return {
            "mensaje": "Usuario actualizado correctamente"
        }, 200

    except Exception:
        db.session.rollback()
        raise


def actualizar_estado(
    id_usuario: int,
    id_gestor: int,
    jwt: dict,
    datos,
):
    if id_usuario == id_gestor:
        return {
            "mensaje": "No puedes desactivar tu propia cuenta"
        }, 400

    id_perfil_gestor = _perfil_gestor(jwt)

    if id_perfil_gestor is None:
        return {
            "mensaje": "La sesión no contiene un perfil válido"
        }, 401

    id_local = _local_activo(jwt)

    if id_local is None:
        return {
            "mensaje": "La sesión no contiene un local válido"
        }, 401

    if buscar_usuario_gestionable(
        id_usuario,
        id_perfil_gestor,
        id_local,
    ) is None:
        return {
            "mensaje": "No puedes modificar este usuario"
        }, 403

    try:
        estado = int(datos.get("estado_registro"))
    except (AttributeError, TypeError, ValueError):
        return {"mensaje": "El estado no es válido"}, 400

    if estado not in (0, 1):
        return {
            "mensaje": "El estado debe ser 0 o 1"
        }, 400

    try:
        cambiar_estado_usuario(
            id_usuario,
            estado,
            id_gestor,
        )

        registrar_actividad(
            id_usuario=id_gestor,
            modulo="USUARIOS",
            accion="CAMBIAR_ESTADO",
            id_registro_afectado=id_usuario,
            descripcion=(
                "Activó un usuario"
                if estado == 1
                else "Desactivó un usuario"
            ),
            id_perfil_utilizado=id_perfil_gestor,
            id_puesto_laboral=jwt.get("id_puesto_laboral"),
            id_local=id_local,
        )

        db.session.commit()

        return {
            "mensaje": "Estado actualizado correctamente"
        }, 200

    except Exception:
        db.session.rollback()
        raise
