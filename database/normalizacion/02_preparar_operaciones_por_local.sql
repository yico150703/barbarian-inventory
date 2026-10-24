-- Etapa aditiva. Todavia NO separa las operaciones en la aplicacion.
-- Ejecutar una sola vez, despues de 01. No asigna locales historicos.
BEGIN;
SET LOCAL search_path = public, pg_catalog;
SET LOCAL lock_timeout = '5s';
DO $$ BEGIN
    IF current_database() <> 'barbarito' THEN
        RAISE EXCEPTION 'Seleccione la base barbarito';
    END IF;
END $$;
ALTER TABLE inventario_cierre ADD COLUMN id_local integer
    REFERENCES local(id_local);
ALTER TABLE orden_compra ADD COLUMN id_local integer
    REFERENCES local(id_local);
ALTER TABLE movimiento_inventario ADD COLUMN id_local integer
    REFERENCES local(id_local);
-- Proveedor pactado en la compra: no debe cambiar al editar el catalogo.
ALTER TABLE orden_compra_detalle ADD COLUMN id_proveedor integer
    REFERENCES proveedor(id_proveedor);

CREATE INDEX ix_inventario_local_fecha ON inventario_cierre(id_local, fecha_inventario);
CREATE INDEX ix_orden_local_fecha ON orden_compra(id_local, fecha_registro);
CREATE INDEX ix_movimiento_local_fecha ON movimiento_inventario(id_local, fecha_movimiento);
CREATE INDEX ix_orden_detalle_proveedor ON orden_compra_detalle(id_proveedor);

COMMENT ON COLUMN inventario_cierre.id_local IS 'Local propietario. Obligatorio tras completar la migracion por local.';
COMMENT ON COLUMN orden_compra.id_local IS 'Local propietario; las recepciones heredan el local de esta orden.';
COMMENT ON COLUMN movimiento_inventario.id_local IS 'Local propietario, distinto de la contraparte local_relacionado.';
COMMENT ON COLUMN orden_compra_detalle.id_proveedor IS 'Proveedor pactado en esta linea, independiente del proveedor actual del producto.';
COMMIT;
