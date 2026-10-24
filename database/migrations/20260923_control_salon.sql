-- Ejecutar una vez despues de distribucion_salon, como propietario en barbarito.
BEGIN;
SET LOCAL search_path=public,pg_catalog;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
 IF current_database()<>'barbarito' THEN RAISE EXCEPTION 'Seleccione barbarito'; END IF;
END $$;
CREATE TABLE salon_pedido_asignacion (
 id_pedido bigint PRIMARY KEY REFERENCES salon_pedido(id_pedido),
 mesa varchar(4) NOT NULL CHECK(mesa ~ '^[MB][0-9]{2,3}$'),
 id_usuario integer NOT NULL REFERENCES usuario(id_usuario)
);
CREATE TABLE salon_linea_anulada (
 id_linea bigint PRIMARY KEY REFERENCES salon_pedido_linea(id_linea),
 id_responsable integer NOT NULL REFERENCES usuario(id_usuario),
 fecha timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE salon_autorizacion_usada (
 clave uuid PRIMARY KEY,
 fecha timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE VIEW salon_pedido_actual AS
 SELECT p.id_pedido,p.id_local,coalesce(a.mesa,p.mesa) AS mesa,
 coalesce(a.id_usuario,p.id_usuario) AS id_usuario,p.estado,p.version,p.creado_en,
 p.enviado_en,p.envio_clave,p.envio_hash
 FROM salon_pedido p LEFT JOIN salon_pedido_asignacion a USING(id_pedido);
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='multi') THEN
  GRANT SELECT,INSERT,UPDATE ON salon_pedido_asignacion TO multi;
  GRANT SELECT,INSERT ON salon_linea_anulada,salon_autorizacion_usada TO multi;
  GRANT SELECT ON salon_pedido_actual TO multi;
 END IF;
END $$;
COMMIT;
