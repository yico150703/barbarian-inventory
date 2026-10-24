BEGIN;
CREATE TABLE IF NOT EXISTS proveedor_categoria (
    id_proveedor INTEGER NOT NULL REFERENCES proveedor(id_proveedor) ON DELETE CASCADE,
    id_categoria INTEGER NOT NULL REFERENCES categoria_producto(id_categoria),
    PRIMARY KEY (id_proveedor, id_categoria)
);
CREATE INDEX IF NOT EXISTS idx_proveedor_categoria_categoria ON proveedor_categoria(id_categoria);
-- Conserva las asociaciones actuales. Puede ejecutarse nuevamente.
INSERT INTO proveedor_categoria (id_proveedor, id_categoria)
SELECT DISTINCT id_proveedor, id_categoria FROM producto
ON CONFLICT DO NOTHING;
-- Permisos de la cuenta usada por la aplicacion.
GRANT SELECT, INSERT, UPDATE, DELETE ON proveedor_categoria TO multi;
COMMIT;
