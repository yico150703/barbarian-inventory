SET search_path = public, pg_catalog;

CREATE TABLE IF NOT EXISTS promocion_reposicion (
 id_promocion integer NOT NULL REFERENCES promocion(id_promocion),
 id_presentacion_venta integer NOT NULL REFERENCES presentacion_venta(id_presentacion_venta),
 PRIMARY KEY(id_promocion,id_presentacion_venta)
);

DO $$ BEGIN
  ALTER TABLE salon_pedido_linea ALTER COLUMN id_presentacion DROP NOT NULL;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE salon_pedido_linea ADD COLUMN id_promocion integer REFERENCES promocion(id_promocion);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE salon_pedido_linea ADD COLUMN selecciones_promocion jsonb NOT NULL DEFAULT '[]'::jsonb;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE salon_pedido_linea ADD COLUMN id_barra_libre bigint REFERENCES salon_pedido_linea(id_linea);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

UPDATE local SET direccion = 'Av. Paseo de la Republica 170, Lima 01' WHERE upper(codigo) LIKE '%SHERATON%';
UPDATE local SET direccion = 'Av. Pedro de Osma 144, Lima 15063' WHERE upper(codigo) LIKE '%BARRANCO%';
UPDATE local SET direccion = 'Av. Nicolas Ayllon, Santa Anita 15008' WHERE upper(codigo) LIKE '%SANTA_ANITA%';
UPDATE local SET direccion = 'C. Manuel Bonilla 108, Miraflores 15074' WHERE upper(codigo) LIKE '%MIRAFLORES%';

UPDATE local SET codigo='TDA-001' WHERE codigo='MIRAFLORES';
UPDATE local SET codigo='TDA-002' WHERE codigo='BARRANCO';
UPDATE local SET codigo='TDA-003' WHERE codigo='SHERATON';
UPDATE local SET codigo='TDA-004' WHERE codigo='SANTA_ANITA';
