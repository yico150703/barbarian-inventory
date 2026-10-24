-- Ejecutar una vez en barbarito como propietario. No altera pedidos existentes.
BEGIN;
SET LOCAL search_path=public,pg_catalog;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
 IF current_database()<>'barbarito' THEN RAISE EXCEPTION 'Seleccione barbarito'; END IF;
END $$;
ALTER TABLE salon_pedido DROP CONSTRAINT salon_pedido_mesa_check;
ALTER TABLE salon_pedido ALTER COLUMN mesa TYPE varchar(4);
ALTER TABLE salon_pedido ADD CONSTRAINT salon_pedido_mesa_check CHECK(mesa ~ '^[MB][0-9]{2,3}$');
CREATE TABLE salon_distribucion (
 id_local integer PRIMARY KEY REFERENCES local(id_local),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 elementos jsonb NOT NULL CHECK(jsonb_typeof(elementos)='array')
);
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='multi') THEN
  GRANT SELECT,INSERT,UPDATE ON salon_distribucion TO multi;
 END IF;
END $$;
COMMIT;
