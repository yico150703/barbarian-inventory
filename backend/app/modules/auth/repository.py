from sqlalchemy import text

from app.core.extensions import db


def buscar_usuario(correo: str, clave: str):
    """
    Busca al usuario únicamente por sus credenciales.

    No selecciona ningún perfil porque el usuario puede tener
    varios perfiles asignados.
    """
    consulta = text("""
        SELECT
            u.id_usuario,
            u.dni,
            u.nombres,
            u.apellido_paterno,
            u.apellido_materno,
            u.celular,
            u.correo_electronico
        FROM usuario u
        WHERE LOWER(u.correo_electronico) = LOWER(:correo)
          AND u.clave = crypt(:clave, u.clave)
          AND u.estado_registro = 1
        LIMIT 1
    """)

    return db.session.execute(
        consulta,
        {
            "correo": correo,
            "clave": clave,
        },
    ).mappings().first()


def buscar_usuario_por_id(id_usuario: int):
    """
    Obtiene los datos personales del usuario sin escoger
    automáticamente uno de sus perfiles.
    """
    consulta = text("""
        SELECT
            u.id_usuario,
            u.dni,
            u.nombres,
            u.apellido_paterno,
            u.apellido_materno,
            u.celular,
            u.correo_electronico
        FROM usuario u
        WHERE u.id_usuario = :id_usuario
          AND u.estado_registro = 1
        LIMIT 1
    """)

    return db.session.execute(
        consulta,
        {"id_usuario": id_usuario},
    ).mappings().first()


def listar_perfiles_usuario(id_usuario: int):
    """
    Devuelve todos los perfiles activos asignados al usuario.
    """
    consulta = text("""
        SELECT
            p.id_perfil,
            p.nombre,
            p.descripcion
        FROM usuario_perfiles up
        INNER JOIN perfiles p
            ON p.id_perfil = up.id_perfil
           AND p.estado_registro = 1
        WHERE up.id_usuario = :id_usuario
          AND up.estado_registro = 1
        ORDER BY p.id_perfil
    """)

    return db.session.execute(
        consulta,
        {"id_usuario": id_usuario},
    ).mappings().all()


def obtener_perfil_usuario(
    id_usuario: int,
    id_perfil: int,
):
    """
    Obtiene un perfil solamente cuando se encuentra asignado
    y activo para el usuario indicado.
    """
    consulta = text("""
        SELECT
            p.id_perfil,
            p.nombre,
            p.descripcion
        FROM usuario_perfiles up
        INNER JOIN perfiles p
            ON p.id_perfil = up.id_perfil
           AND p.estado_registro = 1
        WHERE up.id_usuario = :id_usuario
          AND up.id_perfil = :id_perfil
          AND up.estado_registro = 1
        LIMIT 1
    """)

    return db.session.execute(
        consulta,
        {
            "id_usuario": id_usuario,
            "id_perfil": id_perfil,
        },
    ).mappings().first()


def usuario_tiene_perfil(
    id_usuario: int,
    id_perfil: int,
) -> bool:
    """
    Comprueba que el usuario continúa activo y que el perfil
    del JWT todavía está asignado.
    """
    consulta = text("""
        SELECT EXISTS (
            SELECT 1
            FROM usuario u
            INNER JOIN usuario_perfiles up
                ON up.id_usuario = u.id_usuario
               AND up.estado_registro = 1
            INNER JOIN perfiles p
                ON p.id_perfil = up.id_perfil
               AND p.estado_registro = 1
            WHERE u.id_usuario = :id_usuario
              AND up.id_perfil = :id_perfil
              AND u.estado_registro = 1
        )
    """)

    return bool(
        db.session.execute(
            consulta,
            {
                "id_usuario": id_usuario,
                "id_perfil": id_perfil,
            },
        ).scalar()
    )


def listar_puestos_usuario(id_usuario: int):
    consulta = text("""
        SELECT
            pl.id_puesto_laboral,
            pl.nombre,
            pl.descripcion
        FROM usuario_puestos_laborales upl
        INNER JOIN puesto_laboral pl
            ON pl.id_puesto_laboral = upl.id_puesto_laboral
           AND pl.estado_registro = 1
        WHERE upl.id_usuario = :id_usuario
          AND upl.estado_registro = 1
        ORDER BY pl.nombre
    """)
    return db.session.execute(
        consulta,
        {"id_usuario": id_usuario},
    ).mappings().all()


def obtener_puesto_usuario(id_usuario: int, id_puesto_laboral: int):
    consulta = text("""
        SELECT
            pl.id_puesto_laboral,
            pl.nombre,
            pl.descripcion
        FROM usuario_puestos_laborales upl
        INNER JOIN puesto_laboral pl
            ON pl.id_puesto_laboral = upl.id_puesto_laboral
           AND pl.estado_registro = 1
        WHERE upl.id_usuario = :id_usuario
          AND upl.id_puesto_laboral = :id_puesto_laboral
          AND upl.estado_registro = 1
        LIMIT 1
    """)
    return db.session.execute(
        consulta,
        {
            "id_usuario": id_usuario,
            "id_puesto_laboral": id_puesto_laboral,
        },
    ).mappings().first()


def obtener_menu(id_perfil: int):
    """
    Obtiene únicamente el menú y los permisos del perfil activo.
    Los permisos de otros perfiles del usuario no se suman.
    """
    consulta = text("""
        SELECT
            om.id_opcion_menu,
            om.codigo,
            om.nombre,
            om.url_menu,
            om.descripcion,
            om.id_padre,
            om.icono,
            om.tipo_opcion,
            om.es_configurable,
            pom.puede_consultar,
            pom.puede_crear,
            pom.puede_editar,
            pom.puede_revisar,
            pom.puede_cerrar,
            pom.puede_desactivar,
            pom.puede_reactivar,
            pom.puede_eliminar,
            pom.puede_configurar,
            pom.orden
        FROM perfil_opcion_menu pom
        INNER JOIN opcion_menu om
            ON om.id_opcion_menu = pom.id_opcion_menu
        WHERE pom.id_perfil = :id_perfil
          AND pom.estado_registro = 1
            AND (:id_perfil IN (2,3,4) OR om.id_opcion_menu NOT IN (15,16,17,18,19,20,21,22,23,24,31,32,36,37,38))
          AND om.estado_registro = 1
          -- Las opciones de salsa ya se configuran desde Recetas.
          AND COALESCE(RTRIM(om.url_menu, '/'), '') <> '/home/grupos-salsa'
        ORDER BY
            COALESCE(
                om.id_padre,
                om.id_opcion_menu
            ),
            om.id_padre NULLS FIRST,
            pom.orden
    """)

    return db.session.execute(
        consulta,
        {"id_perfil": id_perfil},
    ).mappings().all()


def listar_locales_usuario(id_usuario: int, id_perfil: int):
    consulta = text("""
        SELECT l.id_local, l.codigo, l.nombre, l.direccion
        FROM local l
        WHERE l.estado_registro=1 AND (
            (:id_perfil=1 AND EXISTS (
                SELECT 1 FROM usuario_perfiles up JOIN perfiles p USING(id_perfil)
                JOIN usuario u USING(id_usuario)
                WHERE up.id_usuario=:id_usuario AND up.id_perfil=1
                  AND up.estado_registro=1 AND p.estado_registro=1 AND u.estado_registro=1))
            OR EXISTS (SELECT 1 FROM usuario_local ul
                WHERE ul.id_usuario=:id_usuario AND ul.id_local=l.id_local AND ul.estado_registro=1))
        ORDER BY l.nombre
    """)
    return db.session.execute(consulta, {
        "id_usuario": id_usuario, "id_perfil": id_perfil,
    }).mappings().all()


def obtener_local_usuario(id_usuario: int, id_local: int, id_perfil: int):
    return next((local for local in listar_locales_usuario(id_usuario, id_perfil)
                 if local["id_local"] == id_local), None)
