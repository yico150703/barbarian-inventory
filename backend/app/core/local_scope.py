"""Acceso a operaciones del local activo; los catalogos siguen siendo globales."""
from flask import g
from flask_jwt_extended import get_jwt, get_jwt_identity
from sqlalchemy import text
from werkzeug.exceptions import Conflict, Forbidden, NotFound

from app.core.extensions import db


def local_actual():
    if hasattr(g, 'local_operativo'):
        return g.local_operativo
    token = get_jwt()
    local = token.get('id_local')
    perfil = token.get('id_perfil')
    if (token.get('tipo_token') != 'operativo' or type(local) is not int
            or local <= 0 or type(perfil) is not int):
        raise Forbidden('La sesion no contiene un local valido')
    autorizado = db.session.execute(text('''
        SELECT EXISTS (
            SELECT 1 FROM usuario u
            JOIN usuario_perfiles up ON up.id_usuario=u.id_usuario AND up.estado_registro=1
            JOIN perfiles p ON p.id_perfil=up.id_perfil AND p.estado_registro=1
            JOIN local l ON l.id_local=:local AND l.estado_registro=1
            WHERE u.id_usuario=:usuario AND u.estado_registro=1 AND p.id_perfil=:perfil
              AND (p.id_perfil=1 OR EXISTS (
                  SELECT 1 FROM usuario_local ul WHERE ul.id_usuario=u.id_usuario
                  AND ul.id_local=l.id_local AND ul.estado_registro=1))
        )
    '''), {'local': local, 'perfil': perfil, 'usuario': get_jwt_identity()}).scalar()
    if not autorizado:
        raise Forbidden('Ya no tienes acceso al local o perfil activo')
    g.local_operativo = local
    return local


def exigir_migracion_locales():
    if not getattr(g, 'operaciones_por_local_listas', False):
        lista = db.session.execute(text('''
            SELECT EXISTS (SELECT 1 FROM pg_constraint
            WHERE conrelid='public.inventario_cierre'::regclass
              AND conname='uq_inventario_local_fecha' AND convalidated)
        ''')).scalar()
        if not lista:
            raise Conflict('Falta aplicar el archivo 03 de operaciones por tienda. '
                           'Los catalogos siguen disponibles.')
        g.operaciones_por_local_listas = True


def ejecutar_local(consulta, parametros=None):
    local = local_actual()
    exigir_migracion_locales()
    return db.session.execute(consulta, {**(parametros or {}), 'id_local_actual': local})


_REGISTROS = {
    'inventario': ('inventario_cierre', 'id_inventario_cierre', 'id_local'),
    'orden': ('orden_compra', 'id_orden_compra', 'id_local'),
    'movimiento': ('movimiento_inventario', 'id_movimiento_inventario', 'id_local'),
    'factura': ('factura_recepcion f JOIN orden_compra o USING(id_orden_compra)',
                'f.id_factura_recepcion', 'o.id_local'),
    'detalle_recepcion': ('factura_recepcion_detalle d JOIN factura_recepcion f USING(id_factura_recepcion) '
                         'JOIN orden_compra o USING(id_orden_compra)',
                         'd.id_factura_recepcion_detalle', 'o.id_local'),
    'correccion': ('inventario_cierre_correccion c JOIN inventario_cierre i USING(id_inventario_cierre)',
                  'c.id_inventario_cierre_correccion', 'i.id_local'),
    'historial_factura': ('factura_recepcion_historial h JOIN factura_recepcion f USING(id_factura_recepcion) '
                         'JOIN orden_compra o USING(id_orden_compra)',
                         'h.id_factura_recepcion_historial', 'o.id_local'),
}


def exigir_registro_local(tipo, identidad):
    tabla, clave, local = _REGISTROS[tipo]
    existe = ejecutar_local(text(f'SELECT EXISTS(SELECT 1 FROM {tabla} '
        f'WHERE {clave}=:identidad AND {local}=:id_local_actual)'),
        {'identidad': identidad}).scalar()
    if not existe:
        raise NotFound('El registro no existe en el local activo')
