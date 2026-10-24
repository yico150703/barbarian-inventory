-- Pendiente de ejecucion. Limites independientes por producto y local.
-- Copia los minimos anteriores como punto de partida; no sobrescribe configuraciones.
BEGIN;
CREATE TABLE IF NOT EXISTS producto_stock_local (
    id_producto integer NOT NULL REFERENCES producto(id_producto),
    id_local integer NOT NULL REFERENCES local(id_local),
    stock_minimo numeric(12,3) NOT NULL DEFAULT 0,
    stock_maximo numeric(12,3),
    PRIMARY KEY (id_producto, id_local),
    CONSTRAINT ck_stock_local_minimo CHECK (stock_minimo >= 0),
    CONSTRAINT ck_stock_local_maximo CHECK (stock_maximo IS NULL OR stock_maximo >= stock_minimo)
);
CREATE INDEX IF NOT EXISTS ix_producto_stock_local_local ON producto_stock_local(id_local);
INSERT INTO producto_stock_local (id_producto, id_local, stock_minimo)
SELECT p.id_producto, l.id_local, p.stock_minimo FROM producto p CROSS JOIN local l
ON CONFLICT (id_producto, id_local) DO NOTHING;
-- La aplicacion usa multi; los permisos web siguen controlados por perfil/local.
GRANT SELECT, INSERT, UPDATE ON producto_stock_local TO multi;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM opcion_menu WHERE id_opcion_menu = 33 AND codigo <> 'LIMITES_STOCK') THEN
        RAISE EXCEPTION 'La opcion 33 ya esta ocupada';
    END IF;
END $$;
INSERT INTO opcion_menu (id_opcion_menu, codigo, nombre, url_menu, descripcion,
                         id_padre, tipo_opcion, es_configurable)
VALUES (33, 'LIMITES_STOCK', 'Límites de stock', '/home/limites-stock',
        'Configura los stocks mínimos y máximos de los productos del local activo.', NULL, 'ENLACE', FALSE)
ON CONFLICT (id_opcion_menu) DO UPDATE SET
    nombre = EXCLUDED.nombre, url_menu = EXCLUDED.url_menu,
    descripcion = EXCLUDED.descripcion, estado_registro = 1, es_configurable = FALSE;
UPDATE perfil_opcion_menu SET estado_registro = 0
WHERE id_opcion_menu = 33 AND id_perfil <> 2;
INSERT INTO perfil_opcion_menu
    (id_perfil, id_opcion_menu, puede_consultar, puede_configurar, orden, estado_registro)
VALUES (2, 33, TRUE, TRUE, 16, 1)
ON CONFLICT (id_perfil, id_opcion_menu) DO UPDATE SET
    puede_consultar = TRUE, puede_configurar = TRUE, estado_registro = 1;
COMMIT;
