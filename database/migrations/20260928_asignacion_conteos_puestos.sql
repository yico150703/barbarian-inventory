-- Ejecutar una sola vez DESPUÉS de 20260926_jornadas_conteos.sql.
-- No transforma las asignaciones personales antiguas ni altera conteos existentes.
BEGIN;
SET LOCAL search_path=public,pg_catalog;
SET LOCAL lock_timeout='10s';
DO $$ BEGIN
 IF current_database()<>'barbarito' THEN RAISE EXCEPTION 'Seleccione barbarito'; END IF;
END $$;
CREATE TABLE inventario_asignacion_puesto (
 id_local integer NOT NULL REFERENCES local(id_local),
 id_producto integer NOT NULL REFERENCES producto(id_producto),
 id_puesto_laboral integer NOT NULL REFERENCES puesto_laboral(id_puesto_laboral),
 actualizado_por integer NOT NULL REFERENCES usuario(id_usuario),
 actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(id_local,id_producto)
);
ALTER TABLE inventario_ronda ADD COLUMN por_puesto boolean NOT NULL DEFAULT false;
ALTER TABLE inventario_conteo
 ADD COLUMN puesto_asignado integer REFERENCES puesto_laboral(id_puesto_laboral),
 ADD COLUMN puesto_nombre text,
 ADD COLUMN contado_perfil integer REFERENCES perfiles(id_perfil),
 ADD COLUMN contado_puesto integer REFERENCES puesto_laboral(id_puesto_laboral),
 ADD COLUMN contado_perfil_nombre text,
 ADD COLUMN contado_puesto_nombre text;
CREATE INDEX ix_conteo_puesto ON inventario_conteo(puesto_asignado,id_ronda);
UPDATE perfil_opcion_menu SET puede_crear=true WHERE id_perfil=4 AND id_opcion_menu=38;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='multi') THEN
  GRANT SELECT,INSERT,UPDATE,DELETE ON inventario_asignacion_puesto TO multi;
 END IF;
END $$;
COMMIT;
