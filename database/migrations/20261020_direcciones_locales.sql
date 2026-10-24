-- Direcciones confirmadas por el usuario el 20/10/2026.
BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE TEMP TABLE direcciones_confirmadas (codigo text PRIMARY KEY, direccion text NOT NULL) ON COMMIT DROP;
INSERT INTO direcciones_confirmadas VALUES
    ('SHERATON', 'Av. Paseo de la República 170, Lima 01'),
    ('BARRANCO', 'Av. Pedro de Osma 144, Lima 15063'),
    ('SANTA_ANITA', 'Av. Nicolás Ayllón, Santa Anita 15008'),
    ('MIRAFLORES', 'C. Manuel Bonilla 108, Miraflores 15074');
DO $$ BEGIN
    IF EXISTS (
        SELECT 1 FROM direcciones_confirmadas d
        WHERE (SELECT count(*) FROM local l
               WHERE replace(upper(l.codigo), ' ', '_') = d.codigo) <> 1
    ) THEN
        RAISE EXCEPTION 'Verificar códigos de las cuatro sedes antes de cargar sus direcciones';
    END IF;
END $$;
UPDATE local l SET direccion = d.direccion
FROM direcciones_confirmadas d
WHERE replace(upper(l.codigo), ' ', '_') = d.codigo
  AND l.direccion IS DISTINCT FROM d.direccion;
COMMIT;
