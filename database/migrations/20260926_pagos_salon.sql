-- Ejecutar una sola vez como propietario, después de control_salon y seguimiento_movimientos.
-- Registra cobros internos. No constituye integración de emisión fiscal con SUNAT.
BEGIN;
SET LOCAL search_path=public,pg_catalog;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
 IF current_database()<>'barbarito' THEN RAISE EXCEPTION 'Seleccione barbarito'; END IF;
END $$;
ALTER TABLE movimiento_inventario DROP CONSTRAINT ck_movimiento_motivo;
ALTER TABLE movimiento_inventario ADD CONSTRAINT ck_movimiento_motivo CHECK (
 motivo_movimiento IN ('PRESTAMO_RECIBIDO','MERMA','PRESTAMO_ENTREGADO','DEVOLUCION_PROVEEDOR','REPOSICION_PROVEEDOR','VENTA_SALON'));
ALTER TABLE movimiento_inventario DROP CONSTRAINT ck_movimiento_coherencia;
ALTER TABLE movimiento_inventario ADD CONSTRAINT ck_movimiento_coherencia CHECK (
 (tipo_movimiento='ENTRADA' AND motivo_movimiento='PRESTAMO_RECIBIDO' AND local_relacionado IS NOT NULL AND id_proveedor IS NULL) OR
 (tipo_movimiento='ENTRADA' AND motivo_movimiento='REPOSICION_PROVEEDOR' AND local_relacionado IS NULL AND id_proveedor IS NOT NULL) OR
 (tipo_movimiento='SALIDA' AND motivo_movimiento IN ('MERMA','VENTA_SALON') AND local_relacionado IS NULL AND id_proveedor IS NULL) OR
 (tipo_movimiento='SALIDA' AND motivo_movimiento='PRESTAMO_ENTREGADO' AND local_relacionado IS NOT NULL AND id_proveedor IS NULL) OR
 (tipo_movimiento='SALIDA' AND motivo_movimiento='DEVOLUCION_PROVEEDOR' AND local_relacionado IS NULL AND id_proveedor IS NOT NULL));
CREATE TABLE salon_cobro (
 id_cobro bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 id_local integer NOT NULL REFERENCES local(id_local),
 id_usuario integer NOT NULL REFERENCES usuario(id_usuario),
 mesa varchar(4) NOT NULL,
 clave uuid NOT NULL,
 solicitud_hash varchar(64) NOT NULL,
 tipo varchar(20) NOT NULL CHECK(tipo IN ('BOLETA','BOLETA_ELECTRONICA','FACTURA')),
 metodo varchar(10) NOT NULL CHECK(metodo IN ('EFECTIVO','TARJETA')),
 documento varchar(11) NOT NULL DEFAULT '',
 cliente varchar(200) NOT NULL DEFAULT '',
 total numeric(12,2) NOT NULL CHECK(total>=0),
 comprobante jsonb NOT NULL,
 id_movimiento integer NOT NULL UNIQUE REFERENCES movimiento_inventario(id_movimiento_inventario),
 creado_en timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(id_local,clave),
 CHECK ((tipo='BOLETA' AND documento='' AND cliente='') OR
        (tipo='BOLETA_ELECTRONICA' AND documento ~ '^[0-9]{8}$' AND length(btrim(cliente))>0) OR
        (tipo='FACTURA' AND documento ~ '^[0-9]{11}$' AND length(btrim(cliente))>0))
);
CREATE TABLE salon_cobro_pedido (
 id_pedido bigint PRIMARY KEY REFERENCES salon_pedido(id_pedido),
 id_cobro bigint NOT NULL REFERENCES salon_cobro(id_cobro)
);
CREATE INDEX ix_salon_cobro_local ON salon_cobro(id_local,creado_en);
CREATE INDEX ix_salon_cobro_pedido ON salon_cobro_pedido(id_cobro);
CREATE OR REPLACE VIEW salon_pedido_actual AS
 SELECT p.id_pedido,p.id_local,coalesce(a.mesa,p.mesa) AS mesa,
 coalesce(a.id_usuario,p.id_usuario) AS id_usuario,p.estado,p.version,p.creado_en,
 p.enviado_en,p.envio_clave,p.envio_hash
 FROM salon_pedido p LEFT JOIN salon_pedido_asignacion a USING(id_pedido)
 WHERE NOT EXISTS(SELECT 1 FROM salon_cobro_pedido c WHERE c.id_pedido=p.id_pedido);
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='multi') THEN
  GRANT SELECT,INSERT ON salon_cobro,salon_cobro_pedido TO multi;
  GRANT USAGE,SELECT ON SEQUENCE salon_cobro_id_cobro_seq TO multi;
 END IF;
END $$;
COMMIT;
