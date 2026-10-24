import json

from flask_jwt_extended import get_jwt
from app.core.local_scope import local_actual

from sqlalchemy import text

from app.core.extensions import db


def insertar_actividad(
    id_usuario: int,
    modulo: str,
    accion: str,
    id_registro_afectado: int | None,
    descripcion: str,
    id_perfil_utilizado: int | None = None,
    id_puesto_laboral: int | None = None,
    id_local: int | None = None,
):
    consulta = text("""
        INSERT INTO actividad_usuario (
            id_usuario,
            modulo,
            accion,
            id_registro_afectado,
            descripcion,
            id_perfil_utilizado,
            id_puesto_laboral,
            id_local
        ) VALUES (
            :id_usuario,
            :modulo,
            :accion,
            :id_registro_afectado,
            :descripcion,
            :id_perfil_utilizado,
            :id_puesto_laboral,
            :id_local
        )
        RETURNING id_actividad_usuario
    """)

    return db.session.execute(
        consulta,
        {
            "id_usuario": id_usuario,
            "modulo": modulo,
            "accion": accion,
            "id_registro_afectado": id_registro_afectado,
            "descripcion": descripcion,
            "id_perfil_utilizado": id_perfil_utilizado,
            "id_puesto_laboral": id_puesto_laboral,
            "id_local": id_local,
        },
    ).scalar_one()


def consultar_actividades(limite: int = 50):
    consulta = text("""
        SELECT
            a.id_actividad_usuario,
            a.id_usuario,
            CONCAT(u.nombres, ' ', u.apellido_paterno) AS usuario,
            a.id_perfil_utilizado,
            COALESCE(p.nombre, 'Perfil no registrado') AS perfil_utilizado,
            a.id_puesto_laboral,
            pl.nombre AS puesto_laboral,
            a.id_local,
            l.nombre AS local,
            a.modulo,
            a.accion,
            a.id_registro_afectado,
            a.descripcion,
            a.fecha_actividad
        FROM actividad_usuario a
        INNER JOIN usuario u
            ON u.id_usuario = a.id_usuario
        LEFT JOIN perfiles p
            ON p.id_perfil = a.id_perfil_utilizado
        LEFT JOIN puesto_laboral pl
            ON pl.id_puesto_laboral = a.id_puesto_laboral
        LEFT JOIN local l
            ON l.id_local = a.id_local
        WHERE a.estado_registro = 1
          AND NOT (a.modulo='AUTENTICACION' AND a.accion='CAMBIAR_PERFIL')
          AND (:administrador OR a.id_local=:id_local)
        ORDER BY
            a.fecha_actividad DESC,
            a.id_actividad_usuario DESC
        LIMIT :limite
    """)

    return db.session.execute(
        consulta,
        {"limite": limite, "administrador": get_jwt().get("id_perfil") == 1, "id_local": local_actual()},
    ).mappings().all()


def insertar_auditoria_cambio(
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
    consulta = text("""
        INSERT INTO auditoria_cambio (
            id_usuario,
            id_perfil_utilizado,
            id_puesto_laboral,
            id_local,
            modulo,
            accion,
            tabla_afectada,
            id_registro_afectado,
            datos_anteriores,
            datos_nuevos,
            motivo
        ) VALUES (
            :id_usuario,
            :id_perfil_utilizado,
            :id_puesto_laboral,
            :id_local,
            :modulo,
            :accion,
            :tabla_afectada,
            :id_registro_afectado,
            CAST(:datos_anteriores AS JSONB),
            CAST(:datos_nuevos AS JSONB),
            :motivo
        )
        RETURNING id_auditoria_cambio
    """)

    return db.session.execute(
        consulta,
        {
            "id_usuario": id_usuario,
            "id_perfil_utilizado": id_perfil_utilizado,
            "id_puesto_laboral": id_puesto_laboral,
            "id_local": id_local,
            "modulo": modulo.upper(),
            "accion": accion.upper(),
            "tabla_afectada": tabla_afectada,
            "id_registro_afectado": id_registro_afectado,
            "datos_anteriores": (
                json.dumps(datos_anteriores, ensure_ascii=False, default=str)
                if datos_anteriores is not None
                else None
            ),
            "datos_nuevos": (
                json.dumps(datos_nuevos, ensure_ascii=False, default=str)
                if datos_nuevos is not None
                else None
            ),
            "motivo": motivo,
        },
    ).scalar_one()
