-- Renumera códigos visibles, conservando los ID y las relaciones existentes.
BEGIN;
SET LOCAL lock_timeout = '5s';
LOCK TABLE local IN SHARE ROW EXCLUSIVE MODE;
CREATE TEMP TABLE codigos_tiendas (anterior text PRIMARY KEY, nuevo text UNIQUE NOT NULL) ON COMMIT DROP;
INSERT INTO codigos_tiendas VALUES
    ('MIRAFLORES','TDA-001'), ('BARRANCO','TDA-002'),
    ('SHERATON','TDA-003'), ('SANTA_ANITA','TDA-004');
DO $$ BEGIN
    IF EXISTS(SELECT 1 FROM codigos_tiendas m
              WHERE NOT EXISTS(SELECT 1 FROM local l WHERE l.codigo IN (m.anterior,m.nuevo))) THEN
        RAISE EXCEPTION 'Falta una sede del mapa de códigos';
    END IF;
    IF EXISTS(SELECT 1 FROM codigos_tiendas m JOIN local a ON a.codigo=m.anterior
              JOIN local n ON n.codigo=m.nuevo WHERE a.id_local<>n.id_local) THEN
        RAISE EXCEPTION 'Uno de los códigos nuevos ya está ocupado';
    END IF;
END $$;
UPDATE local l SET codigo=m.nuevo,fecha_modificacion=CURRENT_TIMESTAMP
FROM codigos_tiendas m WHERE l.codigo=m.anterior;
COMMIT;
