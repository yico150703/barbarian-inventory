"""Auditoria de solo lectura. Ejecutar desde la raiz con el Python del backend."""
import json
import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[2]
load_dotenv(ROOT / 'backend' / '.env')
engine = create_engine(os.environ['DATABASE_URL'])
result = {}

with engine.connect() as conn:
    with conn.begin():
        conn.execute(text('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY'))
        conn.execute(text("SET LOCAL statement_timeout = '30s'"))
        def read(name, sql):
            result[name] = [dict(r) for r in conn.execute(text(sql)).mappings()]
            return result[name]

        read('conexion', "SELECT current_database() base, current_user usuario, version(), now() fecha, current_setting('transaction_read_only') solo_lectura")
        tables = read('tablas', "SELECT tablename, tableowner, rowsecurity FROM pg_tables WHERE schemaname='public' ORDER BY tablename")
        read('vistas', "SELECT viewname, definition FROM pg_views WHERE schemaname='public'")
        read('vistas_materializadas', "SELECT matviewname, definition FROM pg_matviews WHERE schemaname='public'")
        read('politicas', "SELECT tablename, policyname, roles, cmd, qual, with_check FROM pg_policies WHERE schemaname='public'")
        read('columnas', "SELECT table_name, column_name, data_type, is_nullable, column_default, is_identity FROM information_schema.columns WHERE table_schema='public' ORDER BY table_name, ordinal_position")
        read('restricciones', "SELECT c.conrelid::regclass::text tabla, c.conname nombre, c.contype tipo, c.convalidated validada, pg_get_constraintdef(c.oid) definicion FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname='public' ORDER BY 1,2")
        read('indices', "SELECT tablename, indexname, indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY 1,2")
        read('funciones', "SELECT p.proname nombre, pg_get_functiondef(p.oid) definicion FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f' AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.objid=p.oid AND d.deptype='e')")
        read('triggers', "SELECT tgrelid::regclass::text tabla, tgname nombre, pg_get_triggerdef(oid) definicion FROM pg_trigger WHERE NOT tgisinternal AND tgrelid IN (SELECT oid FROM pg_class WHERE relnamespace='public'::regnamespace)")
        quote = engine.dialect.identifier_preparer.quote
        result['conteos'] = {t['tablename']: conn.execute(text('SELECT count(*) FROM public.' + quote(t['tablename']))).scalar_one() for t in tables}
        result['secuencias'] = []
        for c in result['columnas']:
            if c['is_identity'] != 'YES' and 'nextval' not in (c['column_default'] or ''):
                continue
            seq = conn.execute(text('SELECT pg_get_serial_sequence(:tabla,:columna)'), {'tabla': 'public.' + quote(c['table_name']), 'columna': c['column_name']}).scalar_one()
            if not seq:
                continue
            # Los identificadores provienen del catalogo, no de entradas del usuario.
            last = conn.execute(text('SELECT last_value,is_called FROM ' + seq)).mappings().one()
            step = conn.execute(text('SELECT seqincrement FROM pg_sequence WHERE seqrelid=CAST(:seq AS regclass)'), {'seq': seq}).scalar_one()
            maximum = conn.execute(text('SELECT max(' + quote(c['column_name']) + ') FROM public.' + quote(c['table_name']))).scalar_one()
            next_value = last['last_value'] + step if last['is_called'] else last['last_value']
            result['secuencias'].append({'tabla': c['table_name'], 'columna': c['column_name'], 'secuencia': seq, 'siguiente_estimado': next_value, 'maximo': maximum, 'requiere_revision': maximum is not None and next_value <= maximum})
        fks = conn.execute(text("""SELECT c.conname, c.conrelid::regclass::text child,
            c.confrelid::regclass::text parent,
            array_agg(a.attname ORDER BY k.ord) child_cols,
            array_agg(b.attname ORDER BY k.ord) parent_cols
            FROM pg_constraint c
            CROSS JOIN LATERAL unnest(c.conkey,c.confkey) WITH ORDINALITY k(x,y,ord)
            JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.x
            JOIN pg_attribute b ON b.attrelid=c.confrelid AND b.attnum=k.y
            WHERE c.contype='f' AND c.connamespace='public'::regnamespace GROUP BY c.oid""")).mappings().all()
        result['huerfanos'] = {}
        for fk in fks:
            present = ' AND '.join('c.' + quote(c) + ' IS NOT NULL' for c in fk['child_cols'])
            match = ' AND '.join('p.' + quote(p) + '=c.' + quote(c) for c,p in zip(fk['child_cols'],fk['parent_cols']))
            sql = f"SELECT count(*) FROM public.{quote(fk['child'])} c WHERE {present} AND NOT EXISTS(SELECT 1 FROM public.{quote(fk['parent'])} p WHERE {match})"
            result['huerfanos'][fk['conname']] = conn.execute(text(sql)).scalar_one()
        checks = {
            'puestos_legacy': "SELECT count(*) total, count(*) FILTER(WHERE u.id_puesto_laboral IS NOT NULL) con_puesto_legacy, count(*) FILTER(WHERE u.id_puesto_laboral IS NOT NULL AND NOT EXISTS(SELECT 1 FROM usuario_puestos_laborales x WHERE x.id_usuario=u.id_usuario AND x.id_puesto_laboral=u.id_puesto_laboral AND x.estado_registro=1)) legacy_no_activo_en_relacion FROM usuario u",
            'unidades_receta': "SELECT count(*) diferencias FROM receta_detalle d LEFT JOIN producto p USING(id_producto) LEFT JOIN subproducto s USING(id_subproducto) WHERE d.unidad IS DISTINCT FROM CASE WHEN d.tipo_componente='PRODUCTO' THEN p.unidad ELSE s.unidad END",
            'unidades_subproducto': "SELECT count(*) diferencias FROM subproducto_detalle d JOIN producto p USING(id_producto) WHERE d.unidad IS DISTINCT FROM p.unidad",
            'unidades_salsa': "SELECT count(*) diferencias FROM grupo_salsa_opcion d JOIN producto p USING(id_producto) WHERE d.unidad IS DISTINCT FROM p.unidad",
            'recepcion_fuera_orden': "SELECT count(*) diferencias FROM factura_recepcion_detalle d JOIN factura_recepcion f USING(id_factura_recepcion) WHERE NOT EXISTS(SELECT 1 FROM orden_compra_detalle o WHERE o.id_orden_compra=f.id_orden_compra AND o.id_producto=d.id_producto)",
            'proveedor_historico_distinto': "SELECT count(*) diferencias FROM factura_recepcion_detalle d JOIN factura_recepcion f USING(id_factura_recepcion) JOIN producto p USING(id_producto) WHERE f.id_proveedor<>p.id_proveedor",
            'sobre_recepcion': "SELECT count(*) diferencias FROM orden_compra_detalle o WHERE o.cantidad_solicitada < (SELECT coalesce(sum(d.cantidad_recibida),0) FROM factura_recepcion_detalle d JOIN factura_recepcion f USING(id_factura_recepcion) WHERE f.id_orden_compra=o.id_orden_compra AND d.id_producto=o.id_producto)",
            'lineas_sin_proveedor_historico_unico': "SELECT count(*) diferencias FROM orden_compra_detalle o WHERE (SELECT count(DISTINCT f.id_proveedor) FROM factura_recepcion f JOIN factura_recepcion_detalle d USING(id_factura_recepcion) WHERE f.id_orden_compra=o.id_orden_compra AND d.id_producto=o.id_producto)<>1",
            'salsas_sin_opciones_suficientes': "SELECT count(*) diferencias FROM grupo_salsa g WHERE g.activo AND NOT g.permite_repetir AND g.cantidad_maxima>(SELECT count(*) FROM grupo_salsa_opcion o WHERE o.id_grupo_salsa=g.id_grupo_salsa AND o.activo)",
            'promociones_sin_opciones_suficientes': "SELECT count(*) diferencias FROM promocion_grupo g WHERE NOT g.permite_repetir AND g.cantidad_elegir>(SELECT count(*) FROM promocion_opcion o WHERE o.id_promocion_grupo=g.id_promocion_grupo)",
            'nombres_producto_duplicados': "SELECT count(*) grupos FROM (SELECT lower(btrim(nombre)) FROM producto GROUP BY 1 HAVING count(*)>1) x",
            'locales': "SELECT id_local,codigo,nombre,estado_registro FROM local ORDER BY id_local",
            'historial_inventarios': "SELECT id_inventario_cierre,fecha_inventario,estado_inventario FROM inventario_cierre ORDER BY 1",
            'historial_ordenes': "SELECT id_orden_compra,codigo,estado_orden_compra,fecha_registro FROM orden_compra ORDER BY 1",
            'historial_movimientos': "SELECT id_movimiento_inventario,codigo,fecha_movimiento,tipo_movimiento,motivo_movimiento,local_relacionado FROM movimiento_inventario ORDER BY 1",
        }
        for name, sql in checks.items():
            read(name, sql)

out = Path(__file__).with_name('auditoria_actual.json')
out.write_text(json.dumps(result, ensure_ascii=False, indent=2, default=str), encoding='utf-8')
print(json.dumps({'archivo': str(out), 'tablas': len(tables), 'relaciones': len(fks), 'huerfanos': sum(result['huerfanos'].values()), 'comprobaciones': {k: result[k] for k in checks if not k.startswith('historial')}}, ensure_ascii=False, indent=2))
