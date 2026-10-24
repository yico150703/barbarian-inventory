-- Ejecutar UNA VEZ como propietario en barbarito, después de 20260926_pagos_salon.sql.
-- Conserva el stock vigente como saldo de apertura. Los conteos nuevos NO ajustan stock.
BEGIN;
SET LOCAL search_path=public,pg_catalog;
SET LOCAL lock_timeout='10s';
DO $$ BEGIN
 IF current_database()<>'barbarito' THEN RAISE EXCEPTION 'Seleccione barbarito'; END IF;
 IF to_regclass('salon_cobro') IS NULL THEN RAISE EXCEPTION 'Ejecute primero 20260926_pagos_salon.sql'; END IF;
 IF EXISTS(SELECT 1 FROM movimiento_inventario WHERE fecha_movimiento>CURRENT_DATE) OR
    EXISTS(SELECT 1 FROM factura_recepcion WHERE fecha_recepcion>CURRENT_DATE) THEN
   RAISE EXCEPTION 'Revise operaciones fechadas en el futuro antes de convertir el stock'; END IF;
END $$;
LOCK TABLE producto,local,inventario_cierre,inventario_cierre_detalle,movimiento_inventario,movimiento_inventario_detalle,
 factura_recepcion,factura_recepcion_detalle,orden_compra,salon_cobro,opcion_menu,perfil_opcion_menu IN SHARE ROW EXCLUSIVE MODE;
CREATE TABLE inventario_saldo_inicial (
 id_local integer REFERENCES local(id_local), id_producto integer REFERENCES producto(id_producto),
 cantidad numeric(18,3) NOT NULL, creado_en timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(id_local,id_producto)
);
INSERT INTO inventario_saldo_inicial(id_local,id_producto,cantidad)
 SELECT l.id_local,p.id_producto,coalesce(c.stock_contado,0)+coalesce(r.cantidad,0)+coalesce(m.cantidad,0)
 FROM local l CROSS JOIN producto p
 LEFT JOIN LATERAL (SELECT i.fecha_inventario,i.fecha_registro,d.stock_contado FROM inventario_cierre i
   JOIN inventario_cierre_detalle d USING(id_inventario_cierre)
   WHERE i.id_local=l.id_local AND d.id_producto=p.id_producto AND i.estado_inventario='CERRADO'
   AND i.fecha_inventario<=CURRENT_DATE ORDER BY i.fecha_inventario DESC,i.id_inventario_cierre DESC LIMIT 1) c ON true
 LEFT JOIN LATERAL (SELECT sum(d.cantidad_recibida) cantidad FROM factura_recepcion_detalle d
   JOIN factura_recepcion f USING(id_factura_recepcion) JOIN orden_compra o USING(id_orden_compra)
   WHERE o.id_local=l.id_local AND d.id_producto=p.id_producto AND (c.fecha_inventario IS NULL OR f.fecha_recepcion>c.fecha_inventario)
   AND f.fecha_recepcion<=CURRENT_DATE) r ON true
 LEFT JOIN LATERAL (SELECT sum(CASE WHEN m.tipo_movimiento='ENTRADA' THEN d.cantidad ELSE -d.cantidad END) cantidad
   FROM movimiento_inventario m JOIN movimiento_inventario_detalle d USING(id_movimiento_inventario)
   WHERE m.id_local=l.id_local AND d.id_producto=p.id_producto AND m.fecha_movimiento<=CURRENT_DATE
   AND (c.fecha_inventario IS NULL OR m.fecha_movimiento>c.fecha_inventario OR
     (m.fecha_movimiento=c.fecha_inventario AND m.registrado_en>c.fecha_registro))) m ON true;
CREATE TABLE inventario_jornada (
 id_jornada bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 id_local integer NOT NULL REFERENCES local(id_local), fecha date NOT NULL,
 abierto_en timestamptz NOT NULL DEFAULT clock_timestamp(), cerrado_en timestamptz,
 abierto_por integer REFERENCES usuario(id_usuario), cerrado_por integer REFERENCES usuario(id_usuario),
 reporte jsonb, UNIQUE(id_local,fecha),
 CHECK((cerrado_en IS NULL AND reporte IS NULL) OR (cerrado_en IS NOT NULL AND reporte IS NOT NULL))
);
CREATE UNIQUE INDEX uq_jornada_abierta ON inventario_jornada(id_local) WHERE cerrado_en IS NULL;
CREATE TABLE inventario_jornada_inicio (
 id_jornada bigint REFERENCES inventario_jornada(id_jornada), id_producto integer REFERENCES producto(id_producto),
 cantidad numeric(18,3) NOT NULL, PRIMARY KEY(id_jornada,id_producto)
);
CREATE TABLE inventario_evento (
 id_evento bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 id_local integer NOT NULL REFERENCES local(id_local), id_jornada bigint NOT NULL REFERENCES inventario_jornada(id_jornada),
 id_producto integer NOT NULL REFERENCES producto(id_producto), cantidad numeric(18,3) NOT NULL CHECK(cantidad<>0),
 motivo varchar(40) NOT NULL, origen varchar(30) NOT NULL, id_origen bigint NOT NULL,
 registrado_en timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX ix_evento_saldo ON inventario_evento(id_local,id_producto);
CREATE INDEX ix_evento_jornada ON inventario_evento(id_jornada,id_producto);
CREATE VIEW inventario_stock_teorico AS
 SELECT l.id_local,p.id_producto,coalesce(b.cantidad,0) AS inicial,coalesce(e.cantidad,0) AS variacion,
 coalesce(b.cantidad,0)+coalesce(e.cantidad,0) AS stock_actual
 FROM local l CROSS JOIN producto p LEFT JOIN inventario_saldo_inicial b USING(id_local,id_producto)
 LEFT JOIN (SELECT id_local,id_producto,sum(cantidad) cantidad FROM inventario_evento GROUP BY id_local,id_producto) e USING(id_local,id_producto);
CREATE FUNCTION inventario_abrir_jornada(local_id integer, usuario_id integer DEFAULT NULL, fecha_solicitada date DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE identidad bigint; ultima date; siguiente date;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtext('inventario-dia:'||local_id));
 SELECT id_jornada INTO identidad FROM inventario_jornada WHERE id_local=local_id AND cerrado_en IS NULL;
 IF identidad IS NOT NULL THEN RETURN identidad; END IF;
 SELECT max(fecha) INTO ultima FROM inventario_jornada WHERE id_local=local_id;
 siguiente:=greatest((clock_timestamp() AT TIME ZONE 'America/Lima')::date,ultima+1);
 IF fecha_solicitada IS NOT NULL THEN
  IF fecha_solicitada> siguiente OR (ultima IS NOT NULL AND fecha_solicitada<=ultima) THEN RAISE EXCEPTION 'Fecha operativa inválida'; END IF;
  siguiente:=fecha_solicitada;
 END IF;
 INSERT INTO inventario_jornada(id_local,fecha,abierto_por) VALUES(local_id,siguiente,usuario_id) RETURNING id_jornada INTO identidad;
 INSERT INTO inventario_jornada_inicio SELECT identidad,id_producto,stock_actual FROM inventario_stock_teorico WHERE id_local=local_id;
 RETURN identidad;
END $$;
-- Abre el día de activación. No modifica ni reasigna comprobantes históricos.
SELECT inventario_abrir_jornada(id_local) FROM local WHERE estado_registro=1;
ALTER TABLE salon_cobro ADD COLUMN id_jornada bigint REFERENCES inventario_jornada(id_jornada);
CREATE INDEX ix_cobro_jornada ON salon_cobro(id_jornada);
CREATE FUNCTION inventario_cobro_jornada() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 NEW.id_jornada:=inventario_abrir_jornada(NEW.id_local,NEW.id_usuario);
 RETURN NEW;
END $$;
CREATE TRIGGER cobro_jornada BEFORE INSERT ON salon_cobro FOR EACH ROW EXECUTE FUNCTION inventario_cobro_jornada();
CREATE FUNCTION inventario_registrar_evento() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE fila record; cab record; delta numeric; jornada bigint; anterior numeric; actual numeric; motivo_evento text;
BEGIN
 IF TG_OP='DELETE' THEN fila:=OLD; ELSE fila:=NEW; END IF;
 IF TG_OP='UPDATE' AND (NEW.id_producto<>OLD.id_producto) THEN RAISE EXCEPTION 'No cambie el producto de una operación registrada'; END IF;
 IF TG_TABLE_NAME='movimiento_inventario_detalle' THEN
  IF TG_OP='UPDATE' AND NEW.id_movimiento_inventario<>OLD.id_movimiento_inventario THEN RAISE EXCEPTION 'Movimiento inmutable'; END IF;
  SELECT m.id_local,m.usuario_registro,m.tipo_movimiento,m.motivo_movimiento INTO cab FROM movimiento_inventario m WHERE id_movimiento_inventario=fila.id_movimiento_inventario;
  anterior:=CASE WHEN TG_OP='INSERT' THEN 0 ELSE OLD.cantidad END;
  actual:=CASE WHEN TG_OP='DELETE' THEN 0 ELSE NEW.cantidad END;
  delta:=(actual-anterior)*CASE WHEN cab.tipo_movimiento='ENTRADA' THEN 1 ELSE -1 END;
  motivo_evento:=cab.motivo_movimiento;
 ELSE
  IF TG_OP='UPDATE' AND NEW.id_factura_recepcion<>OLD.id_factura_recepcion THEN RAISE EXCEPTION 'Recepción inmutable'; END IF;
  SELECT o.id_local,f.usuario_recepcion AS usuario_registro INTO cab FROM factura_recepcion f JOIN orden_compra o USING(id_orden_compra) WHERE f.id_factura_recepcion=fila.id_factura_recepcion;
  anterior:=CASE WHEN TG_OP='INSERT' THEN 0 ELSE OLD.cantidad_recibida END;
  actual:=CASE WHEN TG_OP='DELETE' THEN 0 ELSE NEW.cantidad_recibida END;
  delta:=actual-anterior;
  motivo_evento:=CASE WHEN TG_OP='INSERT' THEN 'RECEPCION_COMPRA' ELSE 'CORRECCION_RECEPCION' END;
 END IF;
 IF delta<>0 THEN
  jornada:=inventario_abrir_jornada(cab.id_local,cab.usuario_registro);
  INSERT INTO inventario_evento(id_local,id_jornada,id_producto,cantidad,motivo,origen,id_origen)
  VALUES(cab.id_local,jornada,fila.id_producto,delta,motivo_evento,
   CASE WHEN TG_TABLE_NAME='movimiento_inventario_detalle' THEN 'MOVIMIENTO' ELSE 'RECEPCION' END,
   CASE WHEN TG_TABLE_NAME='movimiento_inventario_detalle' THEN (to_jsonb(fila)->>'id_movimiento_inventario')::bigint ELSE (to_jsonb(fila)->>'id_factura_recepcion')::bigint END);
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE TRIGGER movimiento_evento AFTER INSERT OR UPDATE OR DELETE ON movimiento_inventario_detalle FOR EACH ROW EXECUTE FUNCTION inventario_registrar_evento();
CREATE TRIGGER recepcion_evento AFTER INSERT OR UPDATE OR DELETE ON factura_recepcion_detalle FOR EACH ROW EXECUTE FUNCTION inventario_registrar_evento();
CREATE TABLE inventario_ronda (
 id_ronda bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, id_local integer NOT NULL REFERENCES local(id_local),
 nombre varchar(120) NOT NULL, creado_por integer NOT NULL REFERENCES usuario(id_usuario),
 creado_en timestamptz NOT NULL DEFAULT clock_timestamp(), cerrado_en timestamptz
);
CREATE UNIQUE INDEX uq_ronda_abierta ON inventario_ronda(id_local) WHERE cerrado_en IS NULL;
CREATE TABLE inventario_conteo (
 id_ronda bigint REFERENCES inventario_ronda(id_ronda), id_producto integer REFERENCES producto(id_producto),
 asignado_a integer REFERENCES usuario(id_usuario), teorico numeric(18,3) NOT NULL,
 contado numeric(18,3), corregido numeric(18,3), contado_por integer REFERENCES usuario(id_usuario), contado_en timestamptz,
 estado varchar(15) NOT NULL DEFAULT 'PENDIENTE' CHECK(estado IN ('PENDIENTE','EN_PROCESO','HECHO','REVISADO')),
 observacion text NOT NULL DEFAULT '', revisado_por integer REFERENCES usuario(id_usuario), revisado_en timestamptz,
 justificacion text NOT NULL DEFAULT '', justificado_por integer REFERENCES usuario(id_usuario), justificado_en timestamptz,
 version integer NOT NULL DEFAULT 1, PRIMARY KEY(id_ronda,id_producto),
 CHECK(contado IS NULL OR contado>=0), CHECK(corregido IS NULL OR corregido>=0),
 CHECK(estado='PENDIENTE' OR contado IS NOT NULL)
);
CREATE TABLE inventario_conteo_historial (
 id_historial bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, id_ronda bigint NOT NULL, id_producto integer NOT NULL,
 id_usuario integer NOT NULL REFERENCES usuario(id_usuario), accion varchar(20) NOT NULL,
 anterior jsonb NOT NULL, nuevo jsonb NOT NULL, creado_en timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(id_ronda,id_producto) REFERENCES inventario_conteo(id_ronda,id_producto)
);
-- Sustituye los accesos antiguos; no elimina conteos históricos.
UPDATE opcion_menu SET estado_registro=0 WHERE id_opcion_menu IN (17,18);
UPDATE opcion_menu SET nombre='Inventario',url_menu=NULL,tipo_opcion='GRUPO' WHERE id_opcion_menu=16;
UPDATE opcion_menu SET id_padre=16 WHERE id_opcion_menu IN (15,33);
UPDATE opcion_menu SET nombre='Mínimos y máximos' WHERE id_opcion_menu=33;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM opcion_menu WHERE id_opcion_menu IN (36,37,38)) THEN RAISE EXCEPTION 'Las opciones 36-38 ya están ocupadas'; END IF;
END $$;
INSERT INTO opcion_menu(id_opcion_menu,codigo,nombre,url_menu,descripcion,id_padre,tipo_opcion,es_configurable) VALUES
 (36,'INVENTARIO_JORNADA','Cerrar día','/home/inventarios/dia','Día operativo y reportes',16,'ENLACE',false),
 (37,'VENTAS_MIX','Mix de ventas','/home/inventarios/mix','Ventas por fechas y horas',16,'ENLACE',false),
 (38,'CONTEO_FISICO','Real vs. teórico','/home/inventarios/conteos','Conteos asignados y diferencias',16,'ENLACE',false);
INSERT INTO perfil_opcion_menu(id_perfil,id_opcion_menu,puede_consultar,puede_crear,puede_editar,puede_revisar,puede_cerrar,puede_configurar,orden)
 SELECT p.id_perfil,o.id,true,p.id_perfil=2,p.id_perfil IN (2,3,4),p.id_perfil IN (2,3),p.id_perfil IN (2,3),p.id_perfil=2,o.id
 FROM perfiles p CROSS JOIN (VALUES(36),(37),(38)) o(id)
 WHERE p.id_perfil IN (2,3) OR (p.id_perfil=4 AND o.id=38);
SELECT setval(pg_get_serial_sequence('opcion_menu','id_opcion_menu'),(SELECT max(id_opcion_menu) FROM opcion_menu),true);
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='multi') THEN
 GRANT SELECT ON inventario_saldo_inicial,inventario_stock_teorico TO multi;
 GRANT SELECT,INSERT,UPDATE ON inventario_jornada,inventario_jornada_inicio,inventario_ronda,inventario_conteo TO multi;
 GRANT SELECT,INSERT ON inventario_evento,inventario_conteo_historial TO multi;
 GRANT USAGE,SELECT ON SEQUENCE inventario_jornada_id_jornada_seq,inventario_evento_id_evento_seq,inventario_ronda_id_ronda_seq,inventario_conteo_historial_id_historial_seq TO multi;
 END IF;
END $$;
COMMIT;
