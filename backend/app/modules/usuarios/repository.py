from sqlalchemy import text

from app.core.extensions import db


def listar_perfiles_permitidos(id_perfil_gestor: int):
    return db.session.execute(
        text("""
            SELECT
                p.id_perfil,
                p.nombre,
                pgu.puede_crear,
                pgu.puede_editar
            FROM perfil_gestion_usuario pgu
            INNER JOIN perfiles p
                ON p.id_perfil = pgu.id_perfil_objetivo
               AND p.estado_registro = 1
            WHERE pgu.id_perfil_gestor = :id_perfil_gestor
              AND pgu.estado_registro = 1
            ORDER BY p.id_perfil
        """),
        {"id_perfil_gestor": id_perfil_gestor},
    ).mappings().all()


def listar_puestos_laborales():
    return db.session.execute(
        text("""
            SELECT
                id_puesto_laboral,
                nombre,
                descripcion
            FROM puesto_laboral
            WHERE estado_registro = 1
            ORDER BY nombre
        """),
    ).mappings().all()


def listar_usuarios_permitidos(id_perfil_gestor, id_local):
    """
    Un usuario es gestionable solamente cuando todos sus perfiles
    activos pueden ser editados por el perfil gestor.

    Esto evita que un Gerente modifique una cuenta que tenga, por
    ejemplo, Gerente y Supervisor simultáneamente.
    """
    return db.session.execute(
        text("""
            SELECT
                u.id_usuario,
                u.dni,
                u.nombres,
                u.apellido_paterno,
                u.apellido_materno,
                u.celular,
                u.correo_electronico,
                u.estado_registro,
                u.fecha_creacion,
                COALESCE(
                    (
                        SELECT ARRAY_AGG(
                            upl.id_puesto_laboral
                            ORDER BY upl.id_puesto_laboral
                        )
                        FROM usuario_puestos_laborales upl
                        WHERE upl.id_usuario = u.id_usuario
                          AND upl.estado_registro = 1
                    ),
                    ARRAY[]::INTEGER[]
                ) AS ids_puestos_laborales,
                COALESCE(
                    (
                        SELECT JSONB_AGG(
                            JSONB_BUILD_OBJECT(
                                'id_puesto_laboral', pl.id_puesto_laboral,
                                'nombre', pl.nombre
                            )
                            ORDER BY pl.nombre
                        )
                        FROM usuario_puestos_laborales upl
                        INNER JOIN puesto_laboral pl
                            ON pl.id_puesto_laboral = upl.id_puesto_laboral
                           AND pl.estado_registro = 1
                        WHERE upl.id_usuario = u.id_usuario
                          AND upl.estado_registro = 1
                    ),
                    '[]'::JSONB
                ) AS puestos_laborales,
                COALESCE(
                    (
                        SELECT ARRAY_AGG(
                            up.id_perfil
                            ORDER BY up.id_perfil
                        )
                        FROM usuario_perfiles up
                        WHERE up.id_usuario = u.id_usuario
                          AND up.estado_registro = 1
                    ),
                    ARRAY[]::INTEGER[]
                ) AS ids_perfiles,
                COALESCE(
                    (
                        SELECT JSONB_AGG(
                            JSONB_BUILD_OBJECT(
                                'id_perfil', p.id_perfil,
                                'nombre', p.nombre
                            )
                            ORDER BY p.id_perfil
                        )
                        FROM usuario_perfiles up
                        INNER JOIN perfiles p
                            ON p.id_perfil = up.id_perfil
                           AND p.estado_registro = 1
                        WHERE up.id_usuario = u.id_usuario
                          AND up.estado_registro = 1
                    ),
                    '[]'::JSONB
                ) AS perfiles,
                COALESCE(
                    (
                        SELECT ARRAY_AGG(
                            ul2.id_local
                            ORDER BY ul2.id_local
                        )
                        FROM usuario_local ul2
                        WHERE ul2.id_usuario = u.id_usuario
                          AND ul2.estado_registro = 1
                    ),
                    ARRAY[]::INTEGER[]
                ) AS ids_locales,
                COALESCE(
                    (
                        SELECT JSONB_AGG(
                            JSONB_BUILD_OBJECT(
                                'id_local', l2.id_local,
                                'codigo', l2.codigo,
                                'nombre', l2.nombre
                            )
                            ORDER BY l2.nombre
                        )
                        FROM usuario_local ul2
                        INNER JOIN local l2
                            ON l2.id_local = ul2.id_local
                           AND l2.estado_registro = 1
                        WHERE ul2.id_usuario = u.id_usuario
                          AND ul2.estado_registro = 1
                    ),
                    '[]'::JSONB
                ) AS locales
            FROM usuario u
            WHERE (:id_perfil_gestor=1 OR EXISTS (
                SELECT 1 FROM usuario_local ul_filtro
                WHERE ul_filtro.id_usuario=u.id_usuario
                  AND ul_filtro.id_local=:id_local AND ul_filtro.estado_registro=1
            )) AND EXISTS (
                SELECT 1
                FROM usuario_perfiles up
                INNER JOIN perfil_gestion_usuario pgu
                    ON pgu.id_perfil_objetivo = up.id_perfil
                   AND pgu.id_perfil_gestor = :id_perfil_gestor
                   AND pgu.estado_registro = 1
                WHERE up.id_usuario = u.id_usuario
                  AND up.estado_registro = 1
            )
              AND NOT EXISTS (
                SELECT 1
                FROM usuario_perfiles up_no_permitido
                WHERE up_no_permitido.id_usuario = u.id_usuario
                  AND up_no_permitido.estado_registro = 1
                  AND NOT EXISTS (
                      SELECT 1
                      FROM perfil_gestion_usuario pgu_permitido
                      WHERE pgu_permitido.id_perfil_gestor = :id_perfil_gestor
                        AND pgu_permitido.id_perfil_objetivo =
                            up_no_permitido.id_perfil
                        AND pgu_permitido.puede_editar = TRUE
                        AND pgu_permitido.estado_registro = 1
                  )
              )
            ORDER BY
                u.nombres,
                u.apellido_paterno,
                u.id_usuario
        """),
        {
            "id_perfil_gestor": id_perfil_gestor,
            "id_local": id_local,
        },
    ).mappings().all()


def perfil_puede_gestionarse(
    id_perfil_gestor: int,
    id_perfil_objetivo: int,
    accion: str,
) -> bool:
    columna = (
        "puede_crear"
        if accion == "crear"
        else "puede_editar"
    )

    consulta = text(f"""
        SELECT EXISTS (
            SELECT 1
            FROM perfil_gestion_usuario
            WHERE id_perfil_gestor = :id_perfil_gestor
              AND id_perfil_objetivo = :id_perfil_objetivo
              AND {columna} = TRUE
              AND estado_registro = 1
        )
    """)

    return bool(
        db.session.execute(
            consulta,
            {
                "id_perfil_gestor": id_perfil_gestor,
                "id_perfil_objetivo": id_perfil_objetivo,
            },
        ).scalar()
    )


def buscar_usuario_gestionable(
    id_usuario: int,
    id_perfil_gestor: int,
    id_local: int,
):
    """
    Devuelve el usuario únicamente cuando todos sus perfiles
    activos pueden ser editados por el gestor.
    """
    return db.session.execute(
        text("""
            SELECT
                u.id_usuario,
                u.id_usuario AS id,
                COALESCE(
                    ARRAY_AGG(
                        up.id_perfil
                        ORDER BY up.id_perfil
                    ) FILTER (
                        WHERE up.estado_registro = 1
                    ),
                    ARRAY[]::INTEGER[]
                ) AS ids_perfiles
            FROM usuario u
            INNER JOIN usuario_perfiles up
                ON up.id_usuario = u.id_usuario
            WHERE u.id_usuario = :id_usuario
              AND (:id_perfil_gestor=1 OR EXISTS (
                  SELECT 1
                  FROM usuario_local ul
                  WHERE ul.id_usuario = u.id_usuario
                    AND ul.id_local = :id_local
                    AND ul.estado_registro = 1
              ))
              AND EXISTS (
                  SELECT 1
                  FROM usuario_perfiles up_existente
                  WHERE up_existente.id_usuario = u.id_usuario
                    AND up_existente.estado_registro = 1
              )
              AND NOT EXISTS (
                  SELECT 1
                  FROM usuario_perfiles up_no_permitido
                  WHERE up_no_permitido.id_usuario = u.id_usuario
                    AND up_no_permitido.estado_registro = 1
                    AND NOT EXISTS (
                        SELECT 1
                        FROM perfil_gestion_usuario pgu
                        WHERE pgu.id_perfil_gestor = :id_perfil_gestor
                          AND pgu.id_perfil_objetivo =
                              up_no_permitido.id_perfil
                          AND pgu.puede_editar = TRUE
                          AND pgu.estado_registro = 1
                    )
              )
            GROUP BY u.id_usuario
        """),
        {
            "id_usuario": id_usuario,
            "id_perfil_gestor": id_perfil_gestor,
            "id_local": id_local,
        },
    ).mappings().first()


def puestos_laborales_existen(ids_puestos_laborales: list[int]) -> bool:
    if not ids_puestos_laborales:
        return True
    return bool(
        db.session.execute(
            text("""
                SELECT COUNT(*) = :cantidad
                FROM puesto_laboral
                WHERE id_puesto_laboral = ANY(:ids_puestos_laborales)
                  AND estado_registro = 1
            """),
            {
                "ids_puestos_laborales": ids_puestos_laborales,
                "cantidad": len(ids_puestos_laborales),
            },
        ).scalar()
    )


def existe_dni(dni: str, excluir_id: int | None = None) -> bool:
    return bool(
        db.session.execute(
            text("""
                SELECT EXISTS (
                    SELECT 1
                    FROM usuario
                    WHERE dni = :dni
                      AND (
                          :excluir_id IS NULL
                          OR id_usuario <> :excluir_id
                      )
                )
            """),
            {
                "dni": dni,
                "excluir_id": excluir_id,
            },
        ).scalar()
    )


def existe_correo(
    correo: str,
    excluir_id: int | None = None,
) -> bool:
    return bool(
        db.session.execute(
            text("""
                SELECT EXISTS (
                    SELECT 1
                    FROM usuario
                    WHERE LOWER(correo_electronico) = LOWER(:correo)
                      AND (
                          :excluir_id IS NULL
                          OR id_usuario <> :excluir_id
                      )
                )
            """),
            {
                "correo": correo,
                "excluir_id": excluir_id,
            },
        ).scalar()
    )


def crear_usuario(
    datos: dict,
    clave_hash: str,
    id_gestor: int,
):
    return db.session.execute(
        text("""
            INSERT INTO usuario (
                dni,
                nombres,
                apellido_paterno,
                apellido_materno,
                celular,
                correo_electronico,
                clave,
                usuario_creacion,
                estado_registro
            ) VALUES (
                :dni,
                :nombres,
                :apellido_paterno,
                :apellido_materno,
                :celular,
                :correo,
                crypt(:clave, gen_salt('bf')),
                :id_gestor,
                1
            )
            RETURNING id_usuario
        """),
        {
            **datos,
            "clave": clave_hash,
            "id_gestor": id_gestor,
        },
    ).scalar_one()


def asignar_perfil(
    id_usuario: int,
    id_perfil: int,
    id_gestor: int,
):
    db.session.execute(
        text("""
            INSERT INTO usuario_perfiles (
                id_usuario,
                id_perfil,
                usuario_asignacion,
                estado_registro
            ) VALUES (
                :id_usuario,
                :id_perfil,
                :id_gestor,
                1
            )
            ON CONFLICT (id_usuario, id_perfil)
            DO UPDATE SET
                estado_registro = 1,
                usuario_modificacion = :id_gestor,
                fecha_modificacion = CURRENT_DATE
        """),
        {
            "id_usuario": id_usuario,
            "id_perfil": id_perfil,
            "id_gestor": id_gestor,
        },
    )


def sincronizar_perfiles(
    id_usuario: int,
    ids_perfiles: list[int],
    id_gestor: int,
):
    """
    Desactiva las asignaciones anteriores y reactiva o crea las
    seleccionadas. No elimina registros históricos.
    """
    db.session.execute(
        text("""
            UPDATE usuario_perfiles
            SET
                estado_registro = 0,
                usuario_modificacion = :id_gestor,
                fecha_modificacion = CURRENT_DATE
            WHERE id_usuario = :id_usuario
              AND estado_registro = 1
        """),
        {
            "id_usuario": id_usuario,
            "id_gestor": id_gestor,
        },
    )

    for id_perfil in ids_perfiles:
        asignar_perfil(
            id_usuario=id_usuario,
            id_perfil=id_perfil,
            id_gestor=id_gestor,
        )


def sincronizar_puestos_laborales(
    id_usuario: int,
    ids_puestos_laborales: list[int],
    id_gestor: int,
):
    db.session.execute(
        text("""
            UPDATE usuario_puestos_laborales
            SET estado_registro = 0,
                usuario_modificacion = :id_gestor,
                fecha_modificacion = CURRENT_DATE
            WHERE id_usuario = :id_usuario
              AND estado_registro = 1
        """),
        {"id_usuario": id_usuario, "id_gestor": id_gestor},
    )

    for id_puesto in ids_puestos_laborales:
        db.session.execute(
            text("""
                INSERT INTO usuario_puestos_laborales (
                    id_usuario,
                    id_puesto_laboral,
                    usuario_asignacion,
                    estado_registro
                ) VALUES (
                    :id_usuario,
                    :id_puesto_laboral,
                    :id_gestor,
                    1
                )
                ON CONFLICT (id_usuario, id_puesto_laboral)
                DO UPDATE SET
                    estado_registro = 1,
                    usuario_modificacion = :id_gestor,
                    fecha_modificacion = CURRENT_DATE
            """),
            {
                "id_usuario": id_usuario,
                "id_puesto_laboral": id_puesto,
                "id_gestor": id_gestor,
            },
        )


def actualizar_usuario(
    id_usuario: int,
    datos: dict,
    id_gestor: int,
    clave_hash: str | None = None,
):
    db.session.execute(
        text("""
            UPDATE usuario
            SET
                dni = :dni,
                nombres = :nombres,
                apellido_paterno = :apellido_paterno,
                apellido_materno = :apellido_materno,
                celular = :celular,
                correo_electronico = :correo,
                clave = CASE
                    WHEN :clave IS NULL THEN clave
                    ELSE crypt(:clave, gen_salt('bf'))
                END,
                usuario_modificacion = :id_gestor,
                fecha_modificacion = CURRENT_DATE
            WHERE id_usuario = :id_usuario
        """),
        {
            **datos,
            "id_usuario": id_usuario,
            "id_gestor": id_gestor,
            "clave": clave_hash,
        },
    )


def cambiar_estado_usuario(
    id_usuario: int,
    estado: int,
    id_gestor: int,
):
    db.session.execute(
        text("""
            UPDATE usuario
            SET
                estado_registro = :estado,
                usuario_modificacion = :id_gestor,
                fecha_modificacion = CURRENT_DATE
            WHERE id_usuario = :id_usuario
        """),
        {
            "id_usuario": id_usuario,
            "estado": estado,
            "id_gestor": id_gestor,
        },
    )

def listar_locales_activos():
    return db.session.execute(
        text("""
            SELECT id_local, codigo, nombre, direccion
            FROM local
            WHERE estado_registro = 1
            ORDER BY nombre
        """)
    ).mappings().all()


def locales_activos_validos(ids_locales: list[int]) -> bool:
    if not ids_locales:
        return False

    cantidad = db.session.execute(
        text("""
            SELECT COUNT(*)
            FROM local
            WHERE id_local = ANY(:ids_locales)
              AND estado_registro = 1
        """),
        {"ids_locales": ids_locales},
    ).scalar_one()

    return cantidad == len(set(ids_locales))


def sincronizar_locales_usuario(
    id_usuario: int,
    ids_locales: list[int],
    id_gestor: int,
):
    """Desactiva locales anteriores y activa los seleccionados."""
    db.session.execute(
        text("""
            UPDATE usuario_local
            SET
                estado_registro = 0,
                usuario_modificacion = :id_gestor,
                fecha_modificacion = CURRENT_TIMESTAMP
            WHERE id_usuario = :id_usuario
              AND estado_registro = 1
        """),
        {
            "id_usuario": id_usuario,
            "id_gestor": id_gestor,
        },
    )

    for id_local in ids_locales:
        db.session.execute(
            text("""
                INSERT INTO usuario_local (
                    id_usuario,
                    id_local,
                    usuario_asignacion,
                    estado_registro
                ) VALUES (
                    :id_usuario,
                    :id_local,
                    :id_gestor,
                    1
                )
                ON CONFLICT (id_usuario, id_local)
                DO UPDATE SET
                    estado_registro = 1,
                    usuario_modificacion = :id_gestor,
                    fecha_modificacion = CURRENT_TIMESTAMP
            """),
            {
                "id_usuario": id_usuario,
                "id_local": id_local,
                "id_gestor": id_gestor,
            },
        )
