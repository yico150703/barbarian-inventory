-- Ejecutar como propietario de las tablas (postgres) sobre la base barbarito.
-- Sustituye identificadores; NO convierte ni modifica cantidades.
BEGIN;
LOCK TABLE producto, subproducto, presentacion_venta, subproducto_detalle,
    receta_detalle, grupo_salsa_opcion IN ACCESS EXCLUSIVE MODE;

CREATE TABLE IF NOT EXISTS unidad_medida (
    codigo VARCHAR(10) PRIMARY KEY,
    nombre VARCHAR(40) NOT NULL,
    simbolo VARCHAR(10) NOT NULL,
    dimension VARCHAR(10) NOT NULL CHECK (dimension IN ('MASA','VOLUMEN','CONTEO')),
    codigo_unece VARCHAR(3) UNIQUE,
    codigo_base VARCHAR(10) NOT NULL REFERENCES unidad_medida(codigo),
    factor_a_base NUMERIC(12,6) NOT NULL CHECK (factor_a_base > 0)
);
INSERT INTO unidad_medida VALUES
    ('KGM','Kilogramo','kg','MASA','KGM','KGM',1),
    ('GRM','Gramo','g','MASA','GRM','KGM',0.001),
    ('LTR','Litro','L','VOLUMEN','LTR','LTR',1),
    ('MLT','Mililitro','mL','VOLUMEN','MLT','LTR',0.001),
    ('C62','Unidad','unidad','CONTEO','C62','C62',1),
    ('PORCION','Porción','porción','CONTEO',NULL,'PORCION',1)
ON CONFLICT (codigo) DO NOTHING;

DO $$
DECLARE tabla TEXT; restriccion RECORD;
BEGIN
    FOREACH tabla IN ARRAY ARRAY['producto','subproducto','presentacion_venta',
        'subproducto_detalle','receta_detalle','grupo_salsa_opcion'] LOOP
        FOR restriccion IN
            SELECT conname FROM pg_constraint
            WHERE conrelid = format('public.%I',tabla)::regclass
              AND contype='c' AND pg_get_constraintdef(oid) ILIKE '%unidad%'
        LOOP
            EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I',tabla,restriccion.conname);
        END LOOP;
        EXECUTE format($sql$
            UPDATE public.%I SET unidad=CASE unidad
                WHEN 'Kg' THEN 'KGM' WHEN 'kg' THEN 'KGM'
                WHEN 'L' THEN 'LTR' WHEN 'UNI' THEN 'C62'
                WHEN 'PORCIÓN' THEN 'PORCION' ELSE unidad END
            WHERE unidad IN ('Kg','kg','L','UNI','PORCIÓN')
        $sql$,tabla);
        IF NOT EXISTS (SELECT 1 FROM pg_constraint
            WHERE conrelid=format('public.%I',tabla)::regclass
              AND conname='fk_'||tabla||'_unidad_medida') THEN
            EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY(unidad) REFERENCES unidad_medida(codigo)',
                tabla,'fk_'||tabla||'_unidad_medida');
        END IF;
    END LOOP;
END $$;

ALTER TABLE producto ADD CONSTRAINT ck_producto_unidad CHECK (unidad IN ('KGM','LTR','C62'));
ALTER TABLE subproducto ADD CONSTRAINT ck_subproducto_unidad CHECK (unidad IN ('KGM','LTR','PORCION'));
ALTER TABLE presentacion_venta ADD CONSTRAINT ck_presentacion_venta_unidad CHECK (unidad IN ('KGM','LTR','C62','PORCION'));
ALTER TABLE subproducto_detalle ADD CONSTRAINT ck_subproducto_detalle_unidad CHECK (unidad IN ('KGM','LTR','C62'));
ALTER TABLE receta_detalle ADD CONSTRAINT ck_receta_detalle_unidad CHECK (unidad IN ('KGM','LTR','C62','PORCION'));
ALTER TABLE grupo_salsa_opcion ADD CONSTRAINT grupo_salsa_opcion_unidad_check CHECK (unidad IN ('KGM','LTR','C62'));
GRANT SELECT ON unidad_medida TO multi;
COMMIT;
