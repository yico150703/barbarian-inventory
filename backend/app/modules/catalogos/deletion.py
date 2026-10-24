from flask import Blueprint, jsonify
from flask_jwt_extended import get_jwt_identity
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from app.core.extensions import db
from app.core.permissions import requiere_permiso
from app.modules.auditoria.service import registrar_cambio, registrar_actividad

deletion_bp = Blueprint('catalog_deletion', __name__)
# Solo composiciones y configuraciones propias; nunca registros operativos/historicos.
ENTIDADES = {
    'productos': ('producto', 'id_producto', 4, [('producto_stock_local', 'id_producto')]),
    'categorias-productos': ('categoria_producto', 'id_categoria', 5, []),
    'proveedores': ('proveedor', 'id_proveedor', 6, [('proveedor_categoria', 'id_proveedor')]),
    'categorias-carta': ('categoria_carta', 'id_categoria_carta', 8, []),
    'presentaciones': ('presentacion_venta', 'id_presentacion_venta', 9, []),
    'subproductos': ('subproducto', 'id_subproducto', 12, [('subproducto_detalle', 'id_subproducto')]),
    'recetas': ('receta', 'id_receta', 28, [('receta_detalle', 'id_receta')]),
    'promociones': ('promocion', 'id_promocion', 14, [('promocion_grupo', 'id_promocion'), ('promocion_reposicion', 'id_promocion')]),
}


def eliminar_registro(entidad, identidad, usuario):
    tabla, pk, _, propios = ENTIDADES[entidad]
    try:
        # Evita nuevas referencias durante la verificacion, incluso FK con CASCADE.
        fila = db.session.execute(text(f'SELECT * FROM {tabla} WHERE {pk}=:id FOR UPDATE'), {'id': identidad}).mappings().first()
        if fila is None:
            db.session.rollback()
            return {'mensaje': 'El registro ya no existe'}, 404
        def referencias(nombre, ids, permitidas):
            relaciones = db.session.execute(text('''
                SELECT ns.nspname AS esquema, cl.relname AS tabla, a.attname AS columna,
                       cardinality(c.conkey) AS columnas
                FROM pg_constraint c JOIN pg_class cl ON cl.oid=c.conrelid
                JOIN pg_namespace ns ON ns.oid=cl.relnamespace
                JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=c.conkey[1]
                WHERE c.contype='f' AND c.confrelid=to_regclass(:tabla)
            '''), {'tabla': 'public.' + nombre}).mappings().all()
            for r in relaciones:
                if r['esquema'] == 'public' and (r['tabla'], r['columna']) in permitidas:
                    continue
                if r['columnas'] != 1:
                    raise ValueError('El registro tiene relaciones compuestas que requieren revision antes de eliminar')
                # Identificadores proceden del catalogo de PostgreSQL y se escapan.
                quote = db.engine.dialect.identifier_preparer.quote
                sql = f'SELECT EXISTS(SELECT 1 FROM {quote(r["esquema"])}.{quote(r["tabla"])} WHERE {quote(r["columna"])}=ANY(:ids))'
                if db.session.execute(text(sql), {'ids': ids}).scalar():
                    raise ValueError('No se puede eliminar: tiene registros asociados en ' + r['tabla'] + '. Reasigna o retira sus dependencias; si son historicas, conserva el registro y desactivalo.')
        referencias(tabla, [identidad], propios)
        detalles = {}
        for hija, fk in propios:
            detalles[hija] = [dict(r) for r in db.session.execute(text(f'SELECT * FROM {hija} WHERE {fk}=:id FOR UPDATE'), {'id': identidad}).mappings()]
            if hija == 'promocion_grupo':
                ids = [r['id_promocion_grupo'] for r in detalles[hija]]
                if ids:
                    referencias(hija, ids, [('promocion_opcion', 'id_promocion_grupo')])
                    detalles['promocion_opcion'] = [dict(r) for r in db.session.execute(text('SELECT * FROM promocion_opcion WHERE id_promocion_grupo=ANY(:ids) FOR UPDATE'), {'ids': ids}).mappings()]
                    referencias('promocion_opcion', [r['id_promocion_opcion'] for r in detalles['promocion_opcion']], [])
                    db.session.execute(text('DELETE FROM promocion_opcion WHERE id_promocion_grupo=ANY(:ids)'), {'ids': ids})
            elif hija == 'promocion_reposicion':
                pass
            elif hija not in ('producto_stock_local', 'proveedor_categoria'):
                referencias(hija, [r['id_' + hija] for r in detalles[hija]], [])
            elif hija == 'producto_stock_local':
                # La configuracion por tienda no tiene dependientes en el esquema actual.
                if db.session.execute(text("SELECT EXISTS(SELECT 1 FROM pg_constraint WHERE contype='f' AND confrelid='producto_stock_local'::regclass)")).scalar():
                    raise ValueError('La configuracion de stock tiene dependencias; no se puede eliminar')
            db.session.execute(text(f'DELETE FROM {hija} WHERE {fk}=:id'), {'id': identidad})
        db.session.execute(text(f'DELETE FROM {tabla} WHERE {pk}=:id'), {'id': identidad})
        registrar_cambio(usuario, 'CATALOGOS', 'ELIMINAR', tabla, identidad, {'registro': dict(fila), 'detalles': detalles}, None)
        registrar_actividad(usuario, 'CATALOGOS', 'ELIMINAR', identidad, f'Elimino {entidad}: {fila.get("nombre", identidad)}')
        db.session.commit()
        return {'mensaje': 'Registro eliminado correctamente'}, 200
    except ValueError as error:
        db.session.rollback()
        return {'mensaje': str(error)}, 409
    except IntegrityError:
        db.session.rollback()
        return {'mensaje': 'No se puede eliminar: el registro sigue asociado a otros datos.'}, 409
    except Exception:
        db.session.rollback()
        raise


@deletion_bp.delete('/<entidad>/<int:identidad>')
def eliminar(entidad, identidad):
    if entidad not in ENTIDADES:
        return jsonify({'mensaje': 'Apartado no valido'}), 404
    @requiere_permiso(ENTIDADES[entidad][2], 'eliminar')
    def autorizado():
        respuesta, estado = eliminar_registro(entidad, identidad, int(get_jwt_identity()))
        return jsonify(respuesta), estado
    return autorizado()
