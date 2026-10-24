-- PENDIENTE: ejecutar como propietario de las tablas. No modifica recetas ni precios.
-- Habilita presentaciones medidas en Kg, ademas de las unidades ya existentes.
BEGIN;
ALTER TABLE presentacion_venta DROP CONSTRAINT ck_presentacion_venta_unidad;
ALTER TABLE presentacion_venta ADD CONSTRAINT ck_presentacion_venta_unidad
    CHECK (unidad IN ('L', 'Kg', 'UNI', 'PORCIÓN'));
COMMIT;
