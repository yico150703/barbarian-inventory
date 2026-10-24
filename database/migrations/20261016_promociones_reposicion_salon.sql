-- Ejecutar una sola vez despues de 20260926_pagos_salon.sql, como propietario.
BEGIN;
SET LOCAL search_path=public,pg_catalog;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
 IF current_database()<>'barbarito' THEN RAISE EXCEPTION 'Seleccione barbarito'; END IF;
END $$;

CREATE TABLE promocion_reposicion (
 id_promocion integer NOT NULL REFERENCES promocion(id_promocion),
 id_presentacion_venta integer NOT NULL REFERENCES presentacion_venta(id_presentacion_venta),
 PRIMARY KEY(id_promocion,id_presentacion_venta)
);

ALTER TABLE salon_pedido_linea ALTER COLUMN id_presentacion DROP NOT NULL;
ALTER TABLE salon_pedido_linea ADD COLUMN id_promocion integer REFERENCES promocion(id_promocion);
ALTER TABLE salon_pedido_linea ADD COLUMN selecciones_promocion jsonb NOT NULL DEFAULT '[]'::jsonb
 CHECK(jsonb_typeof(selecciones_promocion)='array');
ALTER TABLE salon_pedido_linea ADD COLUMN id_barra_libre bigint REFERENCES salon_pedido_linea(id_linea);
ALTER TABLE salon_pedido_linea ADD CONSTRAINT ck_salon_linea_tipo CHECK (
 (id_presentacion IS NOT NULL AND id_promocion IS NULL) OR
 (id_presentacion IS NULL AND id_promocion IS NOT NULL AND cantidad=1 AND id_barra_libre IS NULL)
);
ALTER TABLE salon_pedido_linea ADD CONSTRAINT ck_salon_reposicion_gratis CHECK (
 id_barra_libre IS NULL OR (id_presentacion IS NOT NULL AND id_promocion IS NULL AND precio=0)
);
CREATE INDEX ix_salon_reposicion_barra ON salon_pedido_linea(id_barra_libre) WHERE id_barra_libre IS NOT NULL;
CREATE INDEX ix_salon_linea_promocion ON salon_pedido_linea(id_promocion) WHERE id_promocion IS NOT NULL;

DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='multi') THEN
  GRANT SELECT,INSERT,UPDATE,DELETE ON promocion_reposicion TO multi;
 END IF;
END $$;
COMMIT;