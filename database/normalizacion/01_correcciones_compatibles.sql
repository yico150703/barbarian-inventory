-- Ejecutar completo en barbarito como propietario, despues de un respaldo.
-- No ejecutar tambien la migracion antigua de recetas: este archivo la incluye.
BEGIN;
SET LOCAL search_path = public, pg_catalog;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $$ BEGIN
    IF current_database() <> 'barbarito' THEN
        RAISE EXCEPTION 'Seleccione la base barbarito';
    END IF;
END $$;

ALTER TABLE movimiento_inventario DROP CONSTRAINT ck_movimiento_motivo;
ALTER TABLE movimiento_inventario ADD CONSTRAINT ck_movimiento_motivo
    CHECK (motivo_movimiento IN ('PRESTAMO_RECIBIDO', 'MERMA',
        'PRESTAMO_ENTREGADO', 'DEVOLUCION_PROVEEDOR', 'REPOSICION_PROVEEDOR'));

ALTER TABLE presentacion_venta DROP CONSTRAINT ck_presentacion_venta_unidad;
ALTER TABLE presentacion_venta ADD CONSTRAINT ck_presentacion_venta_unidad
    CHECK (unidad IN ('L', 'Kg', 'UNI', 'PORCIÓN'));

-- Se inserto manualmente la opcion 33 y la secuencia todavia propone 33.
-- No retroceder una secuencia que ya haya avanzado. RESTART es transaccional.
LOCK TABLE opcion_menu IN ACCESS EXCLUSIVE MODE;
DO $$ DECLARE siguiente bigint; estado record; BEGIN
    SELECT last_value, is_called INTO estado FROM opcion_menu_id_opcion_menu_seq;
    SELECT greatest(coalesce(max(id_opcion_menu),0)+1,
        CASE WHEN estado.is_called THEN estado.last_value+1 ELSE estado.last_value END)
        INTO siguiente FROM opcion_menu;
    EXECUTE format('ALTER SEQUENCE public.opcion_menu_id_opcion_menu_seq RESTART WITH %s', siguiente);
END $$;
COMMIT;

SELECT conrelid::regclass AS tabla, conname, pg_get_constraintdef(oid)
FROM pg_constraint WHERE conname IN ('ck_movimiento_motivo','ck_presentacion_venta_unidad');
