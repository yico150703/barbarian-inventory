-- Ejecutar una sola vez DESPUÉS de 20260923_pedidos_salon.sql.
-- Conserva los pedidos enviados y sus bloqueos; admite nuevos envíos por mesa.
BEGIN;
SET LOCAL search_path=public,pg_catalog;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
 IF current_database()<>'barbarito' THEN RAISE EXCEPTION 'Seleccione barbarito'; END IF;
END $$;
ALTER TABLE salon_pedido DROP CONSTRAINT salon_pedido_id_local_mesa_key;
ALTER TABLE salon_pedido ADD COLUMN envio_clave uuid;
ALTER TABLE salon_pedido ADD COLUMN envio_hash varchar(64);
CREATE UNIQUE INDEX uq_salon_borrador ON salon_pedido(id_local,mesa) WHERE estado='BORRADOR';
CREATE UNIQUE INDEX uq_salon_envio ON salon_pedido(id_local,mesa,envio_clave) WHERE envio_clave IS NOT NULL;
CREATE INDEX ix_salon_mesa ON salon_pedido(id_local,mesa,id_pedido);
COMMIT;
