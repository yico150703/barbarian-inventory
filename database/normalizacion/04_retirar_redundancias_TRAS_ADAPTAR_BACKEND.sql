-- NO EJECUTAR con el backend actual. Ver README y completar primero etapa 03.
-- Este archivo falla intencionalmente mientras la confirmacion siga en false.
-- Ensayar en copia restaurada. No utiliza CASCADE.
BEGIN;
SET LOCAL search_path = public, pg_catalog;
SET LOCAL lock_timeout = '5s';
CREATE TEMP TABLE confirmacion_limpieza (backend_adaptado boolean) ON COMMIT DROP;
INSERT INTO confirmacion_limpieza VALUES (false);
DO $$ BEGIN
    IF current_database() <> 'barbarito' THEN
        RAISE EXCEPTION 'Seleccione la base barbarito';
    END IF;
    IF NOT (SELECT backend_adaptado FROM confirmacion_limpieza) THEN
        RAISE EXCEPTION 'Pendiente adaptar backend, probarlo y cambiar confirmacion_limpieza a true';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
        WHERE conrelid='inventario_cierre'::regclass AND conname='uq_inventario_local_fecha') THEN
        RAISE EXCEPTION 'Completar etapa 03 antes de retirar redundancias';
    END IF;
    IF EXISTS (SELECT 1 FROM inventario_cierre WHERE id_local IS NULL)
        OR EXISTS (SELECT 1 FROM orden_compra WHERE id_local IS NULL)
        OR EXISTS (SELECT 1 FROM movimiento_inventario WHERE id_local IS NULL) THEN
        RAISE EXCEPTION 'Completar etapa 03 primero';
    END IF;
    IF EXISTS (SELECT 1 FROM usuario u WHERE u.id_puesto_laboral IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM usuario_puestos_laborales p
            WHERE p.id_usuario=u.id_usuario AND p.id_puesto_laboral=u.id_puesto_laboral
            AND p.estado_registro=1)) THEN
        RAISE EXCEPTION 'Hay puestos antiguos sin asignacion activa: resolver manualmente';
    END IF;
    IF EXISTS (SELECT 1 FROM receta_detalle d
        LEFT JOIN producto p USING(id_producto) LEFT JOIN subproducto s USING(id_subproducto)
        WHERE d.unidad IS DISTINCT FROM CASE WHEN d.tipo_componente='PRODUCTO' THEN p.unidad ELSE s.unidad END)
        OR EXISTS (SELECT 1 FROM subproducto_detalle d JOIN producto p USING(id_producto) WHERE d.unidad IS DISTINCT FROM p.unidad)
        OR EXISTS (SELECT 1 FROM grupo_salsa_opcion d JOIN producto p USING(id_producto) WHERE d.unidad IS DISTINCT FROM p.unidad) THEN
        RAISE EXCEPTION 'Resolver discrepancias de unidades antes de quitar las columnas repetidas';
    END IF;
    IF EXISTS (SELECT 1 FROM producto p CROSS JOIN local l WHERE NOT EXISTS (
        SELECT 1 FROM producto_stock_local s WHERE s.id_producto=p.id_producto AND s.id_local=l.id_local)) THEN
        RAISE EXCEPTION 'Faltan configuraciones producto/local: definirlas explicitamente antes de retirar el minimo global';
    END IF;
END $$;

-- El puesto deja de repetirse: usuario_puestos_laborales sera la fuente unica.
ALTER TABLE usuario DROP COLUMN id_puesto_laboral;
-- Limites exclusivamente en producto_stock_local.
ALTER TABLE producto DROP COLUMN stock_minimo;

-- Unidad unica en producto/subproducto; las cantidades se expresan en esa unidad.
-- El backend debe devolver la unidad mediante JOIN, no leerla de estos detalles.
DO $$ DECLARE t record; BEGIN
    FOR t IN SELECT tgname, tgrelid::regclass AS tabla FROM pg_trigger
        WHERE NOT tgisinternal AND tgfoid IN (
            'public.validar_unidad_receta_detalle()'::regprocedure,
            'public.validar_unidad_subproducto_detalle()'::regprocedure,
            'public.validar_unidad_grupo_salsa_opcion()'::regprocedure)
    LOOP
        EXECUTE format('DROP TRIGGER %I ON %s', t.tgname, t.tabla);
    END LOOP;
END $$;
ALTER TABLE receta_detalle DROP COLUMN unidad;
ALTER TABLE subproducto_detalle DROP COLUMN unidad;
ALTER TABLE grupo_salsa_opcion DROP COLUMN unidad;
DROP FUNCTION validar_unidad_receta_detalle();
DROP FUNCTION validar_unidad_subproducto_detalle();
DROP FUNCTION validar_unidad_grupo_salsa_opcion();

-- Las unidades base no se reinterpretan: cambiar Kg a UNI no convierte cantidades.
-- Crear otro producto/subproducto para otra unidad; conversiones requieren un proceso propio.
CREATE FUNCTION impedir_cambio_unidad_base() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.unidad IS DISTINCT FROM OLD.unidad THEN
        RAISE EXCEPTION 'La unidad base es inmutable; registre otro componente o una conversion controlada';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER tr_producto_unidad_base BEFORE UPDATE OF unidad ON producto
    FOR EACH ROW EXECUTE FUNCTION impedir_cambio_unidad_base();
CREATE TRIGGER tr_subproducto_unidad_base BEFORE UPDATE OF unidad ON subproducto
    FOR EACH ROW EXECUTE FUNCTION impedir_cambio_unidad_base();
COMMIT;
