-- LISTO PARA APLICAR: backend adaptado y probado en PostgreSQL temporal.
-- Ejecutar despues de 02, con escrituras detenidas; reiniciar el backend actualizado.
-- Abrir este archivo guardado, no una copia antigua de Untitled-1.
-- Completar los NULL del mapa con informacion confirmada. NO deducir del usuario
-- ni de local_relacionado: ese campo identifica la contraparte del movimiento.
BEGIN;
SET LOCAL search_path = public, pg_catalog;
SET LOCAL lock_timeout = '5s';
CREATE TEMP TABLE confirmacion_locales (backend_adaptado boolean) ON COMMIT DROP;
INSERT INTO confirmacion_locales VALUES (true);
DO $$ BEGIN
    IF current_database() <> 'barbarito' THEN
        RAISE EXCEPTION 'Seleccione la base barbarito';
    END IF;
    IF NOT (SELECT backend_adaptado FROM confirmacion_locales) THEN
        RAISE EXCEPTION 'Adaptar y probar backend antes de cambiar confirmacion_locales a true';
    END IF;
END $$;

LOCK TABLE inventario_cierre, orden_compra, movimiento_inventario,
    orden_compra_detalle, factura_recepcion, factura_recepcion_detalle
    IN ACCESS EXCLUSIVE MODE;
CREATE TEMP TABLE mapa_locales (
    entidad text NOT NULL CHECK(entidad IN ('inventario_cierre','orden_compra','movimiento_inventario')),
    id_registro integer NOT NULL, id_local integer,
    PRIMARY KEY(entidad,id_registro)
) ON COMMIT DROP;
-- Locales observados: 1 Miraflores, 2 Santa Anita, 3 Barranco, 4 Sheraton.
-- Confirmar nuevamente SELECT id_local,codigo,nombre FROM local.
-- Confirmado por el usuario: inventarios, orden y movimientos son de Miraflores.
-- Las recepciones heredan el local de la orden. Mapa historico confirmado completo.
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM local WHERE id_local=1 AND codigo='MIRAFLORES') THEN
        RAISE EXCEPTION 'Verificar identificador de Miraflores antes de aplicar el mapa';
    END IF;
END $$;
INSERT INTO mapa_locales VALUES
    ('inventario_cierre',1,1), ('inventario_cierre',2,1),
    ('inventario_cierre',3,1), ('inventario_cierre',4,1),
    ('inventario_cierre',5,1), ('inventario_cierre',6,1),
    ('inventario_cierre',7,1), ('inventario_cierre',8,1),
    ('inventario_cierre',9,1), ('orden_compra',1,1),
    ('movimiento_inventario',1,1), ('movimiento_inventario',2,1),
    ('movimiento_inventario',3,1), ('movimiento_inventario',4,1);
-- Agregar al mapa los registros nuevos que aparezcan antes de la migracion.
DO $$ BEGIN
    IF EXISTS(SELECT 1 FROM mapa_locales WHERE id_local IS NULL) THEN
        RAISE EXCEPTION 'Completar TODOS los locales del mapa antes de ejecutar';
    END IF;
    IF EXISTS(SELECT 1 FROM mapa_locales m WHERE NOT EXISTS (
        SELECT 1 FROM local l WHERE l.id_local=m.id_local)) THEN
        RAISE EXCEPTION 'El mapa contiene una tienda inexistente';
    END IF;
    IF EXISTS(SELECT 1 FROM mapa_locales m WHERE NOT EXISTS (
        SELECT 1 FROM inventario_cierre i WHERE m.entidad='inventario_cierre' AND i.id_inventario_cierre=m.id_registro
        UNION ALL SELECT 1 FROM orden_compra o WHERE m.entidad='orden_compra' AND o.id_orden_compra=m.id_registro
        UNION ALL SELECT 1 FROM movimiento_inventario v WHERE m.entidad='movimiento_inventario' AND v.id_movimiento_inventario=m.id_registro)) THEN
        RAISE EXCEPTION 'El mapa contiene registros inexistentes';
    END IF;
    IF EXISTS(SELECT 1 FROM mapa_locales m JOIN inventario_cierre i ON m.entidad='inventario_cierre' AND i.id_inventario_cierre=m.id_registro WHERE i.id_local IS NOT NULL AND i.id_local<>m.id_local)
    OR EXISTS(SELECT 1 FROM mapa_locales m JOIN orden_compra o ON m.entidad='orden_compra' AND o.id_orden_compra=m.id_registro WHERE o.id_local IS NOT NULL AND o.id_local<>m.id_local)
    OR EXISTS(SELECT 1 FROM mapa_locales m JOIN movimiento_inventario v ON m.entidad='movimiento_inventario' AND v.id_movimiento_inventario=m.id_registro WHERE v.id_local IS NOT NULL AND v.id_local<>m.id_local) THEN
        RAISE EXCEPTION 'El mapa contradice una asignacion existente';
    END IF;
END $$;
UPDATE inventario_cierre i SET id_local=m.id_local FROM mapa_locales m
WHERE m.entidad='inventario_cierre' AND i.id_inventario_cierre=m.id_registro AND i.id_local IS NULL;
UPDATE orden_compra o SET id_local=m.id_local FROM mapa_locales m
WHERE m.entidad='orden_compra' AND o.id_orden_compra=m.id_registro AND o.id_local IS NULL;
UPDATE movimiento_inventario v SET id_local=m.id_local FROM mapa_locales m
WHERE m.entidad='movimiento_inventario' AND v.id_movimiento_inventario=m.id_registro AND v.id_local IS NULL;

-- Recuperar el proveedor historico SOLO donde las facturas dan una respuesta unica.
-- En esta auditoria los 140 detalles tienen una respuesta unica. Si aparecen otros,
-- completar su id_proveedor con evidencia antes de esta etapa; no usar a ciegas
-- el proveedor actual del catalogo. Mas de uno requiere decidir si dividir la linea.
UPDATE orden_compra_detalle o SET id_proveedor=x.id_proveedor
FROM (SELECT f.id_orden_compra, d.id_producto, min(f.id_proveedor) id_proveedor
      FROM factura_recepcion f JOIN factura_recepcion_detalle d USING(id_factura_recepcion)
      GROUP BY f.id_orden_compra,d.id_producto HAVING count(DISTINCT f.id_proveedor)=1) x
WHERE o.id_orden_compra=x.id_orden_compra AND o.id_producto=x.id_producto AND o.id_proveedor IS NULL;

DO $$ BEGIN
    IF EXISTS(SELECT 1 FROM inventario_cierre WHERE id_local IS NULL)
        OR EXISTS(SELECT 1 FROM orden_compra WHERE id_local IS NULL)
        OR EXISTS(SELECT 1 FROM movimiento_inventario WHERE id_local IS NULL) THEN
        RAISE EXCEPTION 'Hay registros sin local; agregar los faltantes al mapa';
    END IF;
    IF EXISTS(SELECT 1 FROM orden_compra_detalle WHERE id_proveedor IS NULL) THEN
        RAISE EXCEPTION 'Hay lineas sin proveedor historico confirmado';
    END IF;
    IF EXISTS(SELECT 1 FROM factura_recepcion f JOIN factura_recepcion_detalle d USING(id_factura_recepcion)
        LEFT JOIN orden_compra_detalle o ON o.id_orden_compra=f.id_orden_compra AND o.id_producto=d.id_producto
        WHERE o.id_proveedor IS DISTINCT FROM f.id_proveedor) THEN
        RAISE EXCEPTION 'Facturas incompatibles con las lineas de compra: revisar proveedores/productos';
    END IF;
END $$;
ALTER TABLE inventario_cierre ALTER COLUMN id_local SET NOT NULL;
ALTER TABLE orden_compra ALTER COLUMN id_local SET NOT NULL;
ALTER TABLE movimiento_inventario ALTER COLUMN id_local SET NOT NULL;
ALTER TABLE orden_compra_detalle ALTER COLUMN id_proveedor SET NOT NULL;

-- Requiere INSERT ... ON CONFLICT (id_local,fecha_inventario) en el backend.
ALTER TABLE inventario_cierre ADD CONSTRAINT uq_inventario_local_fecha UNIQUE(id_local,fecha_inventario);
ALTER TABLE inventario_cierre DROP CONSTRAINT inventario_cierre_fecha_inventario_key;
-- Indice antiguo redundante: tambien impedia cierres de dos tiendas el mismo dia.
DROP INDEX IF EXISTS ux_inventario_cierre_fecha;
DROP INDEX ix_inventario_local_fecha;
COMMIT;

SELECT id_local,count(*) FROM inventario_cierre GROUP BY id_local;
SELECT id_local,count(*) FROM orden_compra GROUP BY id_local;
SELECT id_local,count(*) FROM movimiento_inventario GROUP BY id_local;
