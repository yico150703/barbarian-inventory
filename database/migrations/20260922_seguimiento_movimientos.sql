-- Ejecutar completo en barbarito como propietario. No modifica movimientos anteriores.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL search_path = public, pg_catalog;
DO $$ BEGIN
 IF current_database() <> 'barbarito' THEN RAISE EXCEPTION 'Seleccione barbarito'; END IF;
END $$;
ALTER TABLE movimiento_inventario ADD COLUMN registrado_en timestamp;
ALTER TABLE movimiento_inventario ALTER COLUMN registrado_en SET DEFAULT (clock_timestamp() AT TIME ZONE 'America/Lima');
CREATE TABLE movimiento_seguimiento (
 id_movimiento integer PRIMARY KEY REFERENCES movimiento_inventario(id_movimiento_inventario),
 id_local_destino integer REFERENCES local(id_local),
 estado varchar(30) NOT NULL CHECK (estado IN ('PENDIENTE_RECEPCION','ACEPTADO','DEVUELTO','REINTEGRO_PARCIAL','REINTEGRADO')),
 CHECK ((id_local_destino IS NOT NULL AND estado IN ('PENDIENTE_RECEPCION','ACEPTADO'))
     OR (id_local_destino IS NULL AND estado IN ('DEVUELTO','REINTEGRO_PARCIAL','REINTEGRADO')))
);
CREATE TABLE movimiento_reintegro (
 id_movimiento integer PRIMARY KEY REFERENCES movimiento_inventario(id_movimiento_inventario),
 id_salida integer NOT NULL REFERENCES movimiento_seguimiento(id_movimiento),
 guia_proveedor varchar(100),
 registrado_en timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX uq_guia_reintegro ON movimiento_reintegro(id_salida, guia_proveedor)
 WHERE guia_proveedor IS NOT NULL;
CREATE INDEX ix_seguimiento_destino ON movimiento_seguimiento(id_local_destino, estado);
CREATE INDEX ix_reintegro_salida ON movimiento_reintegro(id_salida);
-- Cuenta utilizada por el backend. La base temporal de pruebas no tiene este rol.
DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='multi') THEN
   GRANT SELECT, INSERT, UPDATE ON movimiento_seguimiento, movimiento_reintegro TO multi;
 END IF;
END $$;
COMMIT;
