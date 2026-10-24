-- Ejecutar completo una sola vez en barbarito, como propietario.
BEGIN;
SET LOCAL search_path=public,pg_catalog;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
 IF current_database()<>'barbarito' THEN RAISE EXCEPTION 'Seleccione barbarito'; END IF;
END $$;
CREATE TABLE salon_pedido (
 id_pedido bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 id_local integer NOT NULL REFERENCES local(id_local),
 mesa varchar(3) NOT NULL CHECK (mesa ~ '^(M0[1-9]|M10|B0[1-5])$'),
 id_usuario integer NOT NULL REFERENCES usuario(id_usuario),
 estado varchar(10) NOT NULL DEFAULT 'BORRADOR' CHECK(estado IN ('BORRADOR','ENVIADO')),
 version integer NOT NULL DEFAULT 1,
 creado_en timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 enviado_en timestamptz,
 UNIQUE(id_local,mesa),
 CHECK((estado='BORRADOR' AND enviado_en IS NULL) OR (estado='ENVIADO' AND enviado_en IS NOT NULL))
);
CREATE TABLE salon_pedido_linea (
 id_linea bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 id_pedido bigint NOT NULL REFERENCES salon_pedido(id_pedido),
 posicion integer NOT NULL,
 id_presentacion integer NOT NULL REFERENCES presentacion_venta(id_presentacion_venta),
 nombre text NOT NULL,
 precio numeric(10,2) NOT NULL CHECK(precio>=0),
 cantidad integer NOT NULL CHECK(cantidad BETWEEN 1 AND 99),
 comentario varchar(500) NOT NULL DEFAULT '',
 opciones jsonb NOT NULL DEFAULT '[]'::jsonb CHECK(jsonb_typeof(opciones)='array'),
 UNIQUE(id_pedido,posicion)
);
CREATE INDEX ix_salon_pedido_usuario ON salon_pedido(id_local,id_usuario);
CREATE FUNCTION proteger_pedido_salon() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.estado='ENVIADO' THEN RAISE EXCEPTION 'Un pedido enviado no puede modificarse'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER proteger_pedido_salon BEFORE UPDATE OR DELETE ON salon_pedido
 FOR EACH ROW EXECUTE FUNCTION proteger_pedido_salon();
CREATE FUNCTION proteger_linea_salon() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE estado_actual text;
BEGIN
 IF TG_OP IN ('UPDATE','DELETE') THEN
   SELECT estado INTO estado_actual FROM salon_pedido WHERE id_pedido=OLD.id_pedido FOR UPDATE;
   IF estado_actual='ENVIADO' THEN RAISE EXCEPTION 'Los productos enviados no pueden modificarse'; END IF;
 END IF;
 IF TG_OP IN ('INSERT','UPDATE') THEN
   SELECT estado INTO estado_actual FROM salon_pedido WHERE id_pedido=NEW.id_pedido FOR UPDATE;
   IF estado_actual='ENVIADO' THEN RAISE EXCEPTION 'No se pueden agregar productos al pedido enviado'; END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER proteger_linea_salon BEFORE INSERT OR UPDATE OR DELETE ON salon_pedido_linea
 FOR EACH ROW EXECUTE FUNCTION proteger_linea_salon();
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='multi') THEN
  GRANT SELECT,INSERT,UPDATE,DELETE ON salon_pedido,salon_pedido_linea TO multi;
  GRANT USAGE,SELECT ON SEQUENCE salon_pedido_id_pedido_seq,salon_pedido_linea_id_linea_seq TO multi;
 END IF;
END $$;
COMMIT;
