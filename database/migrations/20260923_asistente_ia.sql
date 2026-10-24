-- Ejecutar en barbarito. No modifica inventarios ni catálogos.
BEGIN;
SET LOCAL search_path=public,pg_catalog;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
 IF current_database()<>'barbarito' THEN RAISE EXCEPTION 'Seleccione barbarito'; END IF;
END $$;
CREATE TABLE IF NOT EXISTS asistente_ia_borrador (
 id uuid PRIMARY KEY,
 id_usuario integer NOT NULL REFERENCES usuario(id_usuario),
 id_perfil integer NOT NULL,
 id_local integer NOT NULL,
 plan jsonb NOT NULL,
 estado varchar(16) NOT NULL DEFAULT 'PENDIENTE'
   CHECK (estado IN ('PENDIENTE','EJECUTANDO','REALIZADO','FALLIDO','CANCELADO')),
 resultado jsonb,
 creado_en timestamptz NOT NULL DEFAULT now(),
 vence_en timestamptz NOT NULL DEFAULT now() + interval '20 minutes'
);
CREATE INDEX IF NOT EXISTS ix_asistente_usuario ON asistente_ia_borrador(id_usuario, creado_en);
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='multi') THEN
   GRANT SELECT, INSERT, UPDATE, DELETE ON asistente_ia_borrador TO multi;
 END IF;
END $$;
COMMIT;
