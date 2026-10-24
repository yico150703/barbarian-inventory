-- Se puede ejecutar ahora. Solo consulta; no activa las etapas 03 y 04.
-- Si la misma conexion quedo en transaccion fallida, ejecutar ROLLBACK primero.
BEGIN TRANSACTION READ ONLY;
SET LOCAL search_path = public, pg_catalog;
SET LOCAL statement_timeout = '30s';

SELECT current_database() AS base_actual;

SELECT conrelid::regclass AS tabla, conname, pg_get_constraintdef(oid) AS regla
FROM pg_constraint
WHERE conname IN ('ck_movimiento_motivo', 'ck_presentacion_venta_unidad');

SELECT table_name AS tabla, column_name AS columna, is_nullable AS admite_nulos
FROM information_schema.columns
WHERE table_schema = 'public' AND (
    (table_name IN ('inventario_cierre','orden_compra','movimiento_inventario')
        AND column_name = 'id_local')
    OR (table_name = 'orden_compra_detalle' AND column_name = 'id_proveedor'))
ORDER BY table_name;

SELECT id_local, codigo, nombre FROM local ORDER BY id_local;

-- Identificar la tienda propietaria de CADA fila antes de completar el mapa de 03.
SELECT 'INVENTARIO' AS tipo, id_inventario_cierre AS id,
       fecha_inventario AS fecha, id_local, NULL::text AS contraparte
FROM inventario_cierre
UNION ALL
SELECT 'ORDEN', id_orden_compra, fecha_registro, id_local, NULL::text
FROM orden_compra
UNION ALL
SELECT 'MOVIMIENTO', id_movimiento_inventario, fecha_movimiento,
       id_local, local_relacionado::text
FROM movimiento_inventario
ORDER BY tipo,id;

SELECT count(*) AS lineas_compra,
       count(*) FILTER (WHERE id_proveedor IS NULL) AS sin_proveedor_historico
FROM orden_compra_detalle;
COMMIT;
