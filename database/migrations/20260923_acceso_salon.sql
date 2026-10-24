-- Ejecutar una sola vez, completo, en barbarito como propietario.
BEGIN;
SET LOCAL search_path=public,pg_catalog;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
 IF current_database()<>'barbarito' THEN RAISE EXCEPTION 'Seleccione barbarito'; END IF;
END $$;
CREATE TABLE usuario_pin_salon (
 id_usuario integer PRIMARY KEY REFERENCES usuario(id_usuario),
 pin_hash text NOT NULL,
 version integer NOT NULL DEFAULT 1,
 fallos integer NOT NULL DEFAULT 0,
 bloqueado_hasta timestamptz,
 actualizado_en timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE salon_intentos (
 origen varchar(64) PRIMARY KEY,
 inicio timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 intentos integer NOT NULL DEFAULT 0
);
DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='multi') THEN
   GRANT SELECT,INSERT,UPDATE,DELETE ON usuario_pin_salon,salon_intentos TO multi;
 END IF;
END $$;
COMMIT;
