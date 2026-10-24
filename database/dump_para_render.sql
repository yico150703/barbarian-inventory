--
-- PostgreSQL database dump
--

\restrict aJ0nFskcdHEa3sPL2kZUtz3CFiRDMameF2EFeGztEvXtaTMac289xzmO7xGbk2K

-- Dumped from database version 18.4
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: inventario_abrir_jornada(integer, integer, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inventario_abrir_jornada(local_id integer, usuario_id integer DEFAULT NULL::integer, fecha_solicitada date DEFAULT NULL::date) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE identidad bigint; ultima date; siguiente date;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtext('inventario-dia:'||local_id));
 SELECT id_jornada INTO identidad FROM inventario_jornada WHERE id_local=local_id AND cerrado_en IS NULL;
 IF identidad IS NOT NULL THEN RETURN identidad; END IF;
 SELECT max(fecha) INTO ultima FROM inventario_jornada WHERE id_local=local_id;
 siguiente:=greatest((clock_timestamp() AT TIME ZONE 'America/Lima')::date,ultima+1);
 IF fecha_solicitada IS NOT NULL THEN
  IF fecha_solicitada> siguiente OR (ultima IS NOT NULL AND fecha_solicitada<=ultima) THEN RAISE EXCEPTION 'Fecha operativa inválida'; END IF;
  siguiente:=fecha_solicitada;
 END IF;
 INSERT INTO inventario_jornada(id_local,fecha,abierto_por) VALUES(local_id,siguiente,usuario_id) RETURNING id_jornada INTO identidad;
 INSERT INTO inventario_jornada_inicio SELECT identidad,id_producto,stock_actual FROM inventario_stock_teorico WHERE id_local=local_id;
 RETURN identidad;
END $$;


--
-- Name: inventario_cobro_jornada(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inventario_cobro_jornada() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN
 NEW.id_jornada:=inventario_abrir_jornada(NEW.id_local,NEW.id_usuario);
 RETURN NEW;
END $$;


--
-- Name: inventario_registrar_evento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inventario_registrar_evento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE fila record; cab record; delta numeric; jornada bigint; anterior numeric; actual numeric; motivo_evento text;
BEGIN
 IF TG_OP='DELETE' THEN fila:=OLD; ELSE fila:=NEW; END IF;
 IF TG_OP='UPDATE' AND (NEW.id_producto<>OLD.id_producto) THEN RAISE EXCEPTION 'No cambie el producto de una operación registrada'; END IF;
 IF TG_TABLE_NAME='movimiento_inventario_detalle' THEN
  IF TG_OP='UPDATE' AND NEW.id_movimiento_inventario<>OLD.id_movimiento_inventario THEN RAISE EXCEPTION 'Movimiento inmutable'; END IF;
  SELECT m.id_local,m.usuario_registro,m.tipo_movimiento,m.motivo_movimiento INTO cab FROM movimiento_inventario m WHERE id_movimiento_inventario=fila.id_movimiento_inventario;
  anterior:=CASE WHEN TG_OP='INSERT' THEN 0 ELSE OLD.cantidad END;
  actual:=CASE WHEN TG_OP='DELETE' THEN 0 ELSE NEW.cantidad END;
  delta:=(actual-anterior)*CASE WHEN cab.tipo_movimiento='ENTRADA' THEN 1 ELSE -1 END;
  motivo_evento:=cab.motivo_movimiento;
 ELSE
  IF TG_OP='UPDATE' AND NEW.id_factura_recepcion<>OLD.id_factura_recepcion THEN RAISE EXCEPTION 'Recepción inmutable'; END IF;
  SELECT o.id_local,f.usuario_recepcion AS usuario_registro INTO cab FROM factura_recepcion f JOIN orden_compra o USING(id_orden_compra) WHERE f.id_factura_recepcion=fila.id_factura_recepcion;
  anterior:=CASE WHEN TG_OP='INSERT' THEN 0 ELSE OLD.cantidad_recibida END;
  actual:=CASE WHEN TG_OP='DELETE' THEN 0 ELSE NEW.cantidad_recibida END;
  delta:=actual-anterior;
  motivo_evento:=CASE WHEN TG_OP='INSERT' THEN 'RECEPCION_COMPRA' ELSE 'CORRECCION_RECEPCION' END;
 END IF;
 IF delta<>0 THEN
  jornada:=inventario_abrir_jornada(cab.id_local,cab.usuario_registro);
  INSERT INTO inventario_evento(id_local,id_jornada,id_producto,cantidad,motivo,origen,id_origen)
  VALUES(cab.id_local,jornada,fila.id_producto,delta,motivo_evento,
   CASE WHEN TG_TABLE_NAME='movimiento_inventario_detalle' THEN 'MOVIMIENTO' ELSE 'RECEPCION' END,
   CASE WHEN TG_TABLE_NAME='movimiento_inventario_detalle' THEN (to_jsonb(fila)->>'id_movimiento_inventario')::bigint ELSE (to_jsonb(fila)->>'id_factura_recepcion')::bigint END);
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;


--
-- Name: proteger_linea_salon(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.proteger_linea_salon() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE estado_actual text;
BEGIN
 IF TG_OP IN ('UPDATE','DELETE') THEN
   SELECT estado INTO estado_actual FROM salon_pedido WHERE id_pedido=OLD.id_pedido FOR UPDATE;
   IF estado_actual='ENVIADO' THEN RAISE EXCEPTION 'Los productos enviados no pueden modificarse'; END IF;
 END IF;
 IF TG_OP IN ('INSERT','UPDATE') THEN
   SELECT estado INTO estado_actual FROM salon_pedido WHERE id_pedido=NEW.id_pedido FOR UPDATE;
   IF estado_actual='ENVIADO' THEN RAISE EXCEPTION 'No se pueden agregar productos al pedido enviado'; END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;


--
-- Name: proteger_pedido_salon(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.proteger_pedido_salon() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
 IF OLD.estado='ENVIADO' THEN RAISE EXCEPTION 'Un pedido enviado no puede modificarse'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;


--
-- Name: validar_unidad_grupo_salsa_opcion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_unidad_grupo_salsa_opcion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE unidad_producto VARCHAR(10);
BEGIN
    SELECT unidad INTO unidad_producto
    FROM producto
    WHERE id_producto=NEW.id_producto;

    IF unidad_producto IS NULL THEN
        RAISE EXCEPTION 'No existe el producto con ID %',NEW.id_producto;
    END IF;

    IF NEW.unidad<>unidad_producto THEN
        RAISE EXCEPTION 'La unidad % no coincide con la unidad % del producto ID %',
            NEW.unidad,unidad_producto,NEW.id_producto;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: validar_unidad_receta_detalle(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_unidad_receta_detalle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    unidad_esperada VARCHAR(10);
BEGIN
    IF NEW.tipo_componente = 'PRODUCTO' THEN
        SELECT unidad INTO unidad_esperada
        FROM producto
        WHERE id_producto = NEW.id_producto;
    ELSE
        SELECT unidad INTO unidad_esperada
        FROM subproducto
        WHERE id_subproducto = NEW.id_subproducto;
    END IF;

    IF unidad_esperada IS NULL THEN
        RAISE EXCEPTION 'No se encontró el componente indicado';
    END IF;

    IF NEW.unidad <> unidad_esperada THEN
        RAISE EXCEPTION
            'La unidad % no coincide con la unidad esperada %',
            NEW.unidad, unidad_esperada;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: validar_unidad_subproducto_detalle(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_unidad_subproducto_detalle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    unidad_producto VARCHAR(10);
BEGIN
    SELECT unidad
    INTO unidad_producto
    FROM producto
    WHERE id_producto = NEW.id_producto;

    IF unidad_producto IS NULL THEN
        RAISE EXCEPTION
            'No existe el producto con ID %',
            NEW.id_producto;
    END IF;

    IF NEW.unidad <> unidad_producto THEN
        RAISE EXCEPTION
            'La unidad % no coincide con la unidad % del producto ID %',
            NEW.unidad,
            unidad_producto,
            NEW.id_producto;
    END IF;

    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: actividad_usuario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.actividad_usuario (
    id_actividad_usuario bigint NOT NULL,
    id_usuario integer NOT NULL,
    modulo character varying(60) NOT NULL,
    accion character varying(40) NOT NULL,
    id_registro_afectado integer,
    descripcion character varying(500) NOT NULL,
    fecha_actividad timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    estado_registro smallint DEFAULT 1 NOT NULL,
    id_perfil_utilizado integer,
    id_puesto_laboral integer,
    id_local integer,
    CONSTRAINT ck_actividad_estado CHECK ((estado_registro = ANY (ARRAY[0, 1])))
);


--
-- Name: actividad_usuario_id_actividad_usuario_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.actividad_usuario ALTER COLUMN id_actividad_usuario ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.actividad_usuario_id_actividad_usuario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: asistente_ia_borrador; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asistente_ia_borrador (
    id uuid NOT NULL,
    id_usuario integer NOT NULL,
    id_perfil integer NOT NULL,
    id_local integer NOT NULL,
    plan jsonb NOT NULL,
    estado character varying(16) DEFAULT 'PENDIENTE'::character varying NOT NULL,
    resultado jsonb,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    vence_en timestamp with time zone DEFAULT (now() + '00:20:00'::interval) NOT NULL,
    CONSTRAINT asistente_ia_borrador_estado_check CHECK (((estado)::text = ANY ((ARRAY['PENDIENTE'::character varying, 'EJECUTANDO'::character varying, 'REALIZADO'::character varying, 'FALLIDO'::character varying, 'CANCELADO'::character varying])::text[])))
);


--
-- Name: auditoria_cambio; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditoria_cambio (
    id_auditoria_cambio bigint NOT NULL,
    id_usuario integer NOT NULL,
    modulo character varying(60) NOT NULL,
    accion character varying(40) NOT NULL,
    tabla_afectada character varying(80) NOT NULL,
    id_registro_afectado integer,
    datos_anteriores jsonb,
    datos_nuevos jsonb,
    motivo character varying(500),
    fecha_cambio timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    id_perfil_utilizado integer,
    id_puesto_laboral integer,
    id_local integer,
    CONSTRAINT ck_auditoria_cambio_accion CHECK ((length(btrim((accion)::text)) > 0)),
    CONSTRAINT ck_auditoria_cambio_modulo CHECK ((length(btrim((modulo)::text)) > 0)),
    CONSTRAINT ck_auditoria_cambio_tabla CHECK ((length(btrim((tabla_afectada)::text)) > 0))
);


--
-- Name: auditoria_cambio_id_auditoria_cambio_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.auditoria_cambio ALTER COLUMN id_auditoria_cambio ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auditoria_cambio_id_auditoria_cambio_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: categoria_carta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categoria_carta (
    id_categoria_carta integer NOT NULL,
    nombre character varying(100) NOT NULL,
    prefijo character varying(5) NOT NULL,
    siguiente_numero integer DEFAULT 1 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_categoria_carta_prefijo CHECK (((prefijo)::text ~ '^[A-Z]{1,3}$'::text)),
    CONSTRAINT ck_categoria_carta_siguiente_numero CHECK ((siguiente_numero >= 1))
);


--
-- Name: categoria_carta_id_categoria_carta_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.categoria_carta ALTER COLUMN id_categoria_carta ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.categoria_carta_id_categoria_carta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: categoria_producto; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categoria_producto (
    id_categoria integer NOT NULL,
    nombre character varying(100) NOT NULL,
    prefijo character varying(5) NOT NULL,
    siguiente_numero integer DEFAULT 1 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_categoria_producto_prefijo CHECK (((prefijo)::text ~ '^[A-Z]{1,3}$'::text)),
    CONSTRAINT ck_categoria_producto_siguiente_numero CHECK ((siguiente_numero >= 1))
);


--
-- Name: categoria_producto_id_categoria_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.categoria_producto ALTER COLUMN id_categoria ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.categoria_producto_id_categoria_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: factura_recepcion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.factura_recepcion (
    id_factura_recepcion integer NOT NULL,
    id_orden_compra integer NOT NULL,
    id_proveedor integer NOT NULL,
    numero_factura character varying(40) NOT NULL,
    fecha_recepcion date NOT NULL,
    usuario_recepcion integer NOT NULL
);


--
-- Name: factura_recepcion_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.factura_recepcion_detalle (
    id_factura_recepcion_detalle integer NOT NULL,
    id_factura_recepcion integer NOT NULL,
    id_producto integer NOT NULL,
    cantidad_recibida numeric(12,3) NOT NULL,
    CONSTRAINT ck_factura_cantidad CHECK ((cantidad_recibida > (0)::numeric))
);


--
-- Name: factura_recepcion_detalle_historial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.factura_recepcion_detalle_historial (
    id_factura_recepcion_detalle_historial bigint CONSTRAINT factura_recepcion_detalle_h_id_factura_recepcion_detal_not_null NOT NULL,
    id_factura_recepcion_historial bigint CONSTRAINT factura_recepcion_detalle_h_id_factura_recepcion_histo_not_null NOT NULL,
    id_producto integer NOT NULL,
    cantidad_anterior numeric(14,3),
    cantidad_nueva numeric(14,3),
    CONSTRAINT ck_frdh_cantidad_anterior CHECK (((cantidad_anterior IS NULL) OR (cantidad_anterior >= (0)::numeric))),
    CONSTRAINT ck_frdh_cantidad_nueva CHECK (((cantidad_nueva IS NULL) OR (cantidad_nueva >= (0)::numeric))),
    CONSTRAINT ck_frdh_valores_diferentes CHECK ((cantidad_anterior IS DISTINCT FROM cantidad_nueva))
);


--
-- Name: factura_recepcion_detalle_his_id_factura_recepcion_detalle__seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.factura_recepcion_detalle_historial ALTER COLUMN id_factura_recepcion_detalle_historial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.factura_recepcion_detalle_his_id_factura_recepcion_detalle__seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: factura_recepcion_detalle_id_factura_recepcion_detalle_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.factura_recepcion_detalle ALTER COLUMN id_factura_recepcion_detalle ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.factura_recepcion_detalle_id_factura_recepcion_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: factura_recepcion_historial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.factura_recepcion_historial (
    id_factura_recepcion_historial bigint CONSTRAINT factura_recepcion_historial_id_factura_recepcion_histo_not_null NOT NULL,
    id_factura_recepcion integer NOT NULL,
    numero_factura_anterior character varying(40) NOT NULL,
    numero_factura_nuevo character varying(40) NOT NULL,
    fecha_recepcion_anterior date NOT NULL,
    fecha_recepcion_nueva date NOT NULL,
    usuario_correccion integer NOT NULL,
    motivo_correccion character varying(100) NOT NULL,
    observacion character varying(500) NOT NULL,
    fecha_correccion timestamp without time zone DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima'::text) NOT NULL,
    CONSTRAINT ck_frh_motivo CHECK ((btrim((motivo_correccion)::text) <> ''::text)),
    CONSTRAINT ck_frh_observacion CHECK ((btrim((observacion)::text) <> ''::text))
);


--
-- Name: factura_recepcion_historial_id_factura_recepcion_historial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.factura_recepcion_historial ALTER COLUMN id_factura_recepcion_historial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.factura_recepcion_historial_id_factura_recepcion_historial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: factura_recepcion_id_factura_recepcion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.factura_recepcion ALTER COLUMN id_factura_recepcion ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.factura_recepcion_id_factura_recepcion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: grupo_salsa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grupo_salsa (
    id_grupo_salsa integer NOT NULL,
    id_presentacion_venta integer NOT NULL,
    cantidad_maxima smallint NOT NULL,
    permite_repetir boolean DEFAULT false NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT grupo_salsa_cantidad_maxima_check CHECK ((cantidad_maxima > 0))
);


--
-- Name: grupo_salsa_id_grupo_salsa_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.grupo_salsa ALTER COLUMN id_grupo_salsa ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.grupo_salsa_id_grupo_salsa_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: grupo_salsa_opcion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grupo_salsa_opcion (
    id_grupo_salsa_opcion integer NOT NULL,
    id_grupo_salsa integer NOT NULL,
    id_producto integer NOT NULL,
    cantidad numeric(12,3) NOT NULL,
    unidad character varying(10) NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT grupo_salsa_opcion_cantidad_check CHECK ((cantidad > (0)::numeric)),
    CONSTRAINT grupo_salsa_opcion_unidad_check CHECK (((unidad)::text = ANY ((ARRAY['KGM'::character varying, 'LTR'::character varying, 'C62'::character varying])::text[])))
);


--
-- Name: grupo_salsa_opcion_id_grupo_salsa_opcion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.grupo_salsa_opcion ALTER COLUMN id_grupo_salsa_opcion ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.grupo_salsa_opcion_id_grupo_salsa_opcion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_asignacion_puesto; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_asignacion_puesto (
    id_local integer NOT NULL,
    id_producto integer NOT NULL,
    id_puesto_laboral integer NOT NULL,
    actualizado_por integer NOT NULL,
    actualizado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: inventario_cierre; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_cierre (
    id_inventario_cierre integer NOT NULL,
    fecha_inventario date NOT NULL,
    estado_inventario character varying(20) DEFAULT 'BORRADOR'::character varying NOT NULL,
    usuario_registro integer NOT NULL,
    fecha_registro timestamp without time zone,
    usuario_revision integer,
    motivo_revision character varying(150),
    observacion character varying(500),
    id_local integer NOT NULL,
    CONSTRAINT ck_inventario_estado CHECK (((estado_inventario)::text = ANY ((ARRAY['BORRADOR'::character varying, 'CERRADO'::character varying, 'INCOMPLETO'::character varying])::text[]))),
    CONSTRAINT ck_inventario_fecha_registro CHECK (((((estado_inventario)::text = 'CERRADO'::text) AND (fecha_registro IS NOT NULL)) OR (((estado_inventario)::text = ANY (ARRAY[('BORRADOR'::character varying)::text, ('INCOMPLETO'::character varying)::text])) AND (fecha_registro IS NULL)))),
    CONSTRAINT ck_inventario_revision CHECK ((((usuario_revision IS NULL) AND (motivo_revision IS NULL) AND (observacion IS NULL)) OR ((usuario_revision IS NOT NULL) AND (motivo_revision IS NOT NULL) AND (observacion IS NOT NULL))))
);


--
-- Name: COLUMN inventario_cierre.id_local; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inventario_cierre.id_local IS 'Local propietario. Obligatorio tras completar la migracion por local.';


--
-- Name: inventario_cierre_correccion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_cierre_correccion (
    id_inventario_cierre_correccion bigint CONSTRAINT inventario_cierre_correccio_id_inventario_cierre_corre_not_null NOT NULL,
    id_inventario_cierre integer NOT NULL,
    usuario_correccion integer NOT NULL,
    motivo_correccion character varying(100) NOT NULL,
    observacion character varying(500) NOT NULL,
    fecha_correccion timestamp without time zone DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima'::text) NOT NULL,
    CONSTRAINT ck_correccion_motivo CHECK ((btrim((motivo_correccion)::text) <> ''::text)),
    CONSTRAINT ck_correccion_observacion CHECK ((btrim((observacion)::text) <> ''::text))
);


--
-- Name: inventario_cierre_correccion_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_cierre_correccion_detalle (
    id_inventario_cierre_correccion_detalle bigint CONSTRAINT inventario_cierre_correcci_id_inventario_cierre_corre_not_null1 NOT NULL,
    id_inventario_cierre_correccion bigint CONSTRAINT inventario_cierre_correcci_id_inventario_cierre_corre_not_null2 NOT NULL,
    id_producto integer NOT NULL,
    stock_anterior numeric,
    stock_nuevo numeric,
    CONSTRAINT ck_correccion_stock_anterior CHECK (((stock_anterior IS NULL) OR (stock_anterior >= (0)::numeric))),
    CONSTRAINT ck_correccion_stock_nuevo CHECK (((stock_nuevo IS NULL) OR (stock_nuevo >= (0)::numeric))),
    CONSTRAINT ck_correccion_valores_diferentes CHECK ((stock_anterior IS DISTINCT FROM stock_nuevo))
);


--
-- Name: inventario_cierre_correccion__id_inventario_cierre_correcci_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_cierre_correccion_detalle ALTER COLUMN id_inventario_cierre_correccion_detalle ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.inventario_cierre_correccion__id_inventario_cierre_correcci_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_cierre_correccion_id_inventario_cierre_correccio_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_cierre_correccion ALTER COLUMN id_inventario_cierre_correccion ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.inventario_cierre_correccion_id_inventario_cierre_correccio_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_cierre_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_cierre_detalle (
    id_inventario_cierre_detalle integer NOT NULL,
    id_inventario_cierre integer NOT NULL,
    id_producto integer NOT NULL,
    stock_contado numeric(12,3) NOT NULL,
    CONSTRAINT ck_inventario_stock CHECK ((stock_contado >= (0)::numeric))
);


--
-- Name: inventario_cierre_detalle_id_inventario_cierre_detalle_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_cierre_detalle ALTER COLUMN id_inventario_cierre_detalle ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.inventario_cierre_detalle_id_inventario_cierre_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_cierre_id_inventario_cierre_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_cierre ALTER COLUMN id_inventario_cierre ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.inventario_cierre_id_inventario_cierre_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_conteo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_conteo (
    id_ronda bigint NOT NULL,
    id_producto integer NOT NULL,
    asignado_a integer,
    teorico numeric(18,3) NOT NULL,
    contado numeric(18,3),
    corregido numeric(18,3),
    contado_por integer,
    contado_en timestamp with time zone,
    estado character varying(15) DEFAULT 'PENDIENTE'::character varying NOT NULL,
    observacion text DEFAULT ''::text NOT NULL,
    revisado_por integer,
    revisado_en timestamp with time zone,
    justificacion text DEFAULT ''::text NOT NULL,
    justificado_por integer,
    justificado_en timestamp with time zone,
    version integer DEFAULT 1 NOT NULL,
    puesto_asignado integer,
    puesto_nombre text,
    contado_perfil integer,
    contado_puesto integer,
    contado_perfil_nombre text,
    contado_puesto_nombre text,
    CONSTRAINT inventario_conteo_check CHECK ((((estado)::text = 'PENDIENTE'::text) OR (contado IS NOT NULL))),
    CONSTRAINT inventario_conteo_contado_check CHECK (((contado IS NULL) OR (contado >= (0)::numeric))),
    CONSTRAINT inventario_conteo_corregido_check CHECK (((corregido IS NULL) OR (corregido >= (0)::numeric))),
    CONSTRAINT inventario_conteo_estado_check CHECK (((estado)::text = ANY ((ARRAY['PENDIENTE'::character varying, 'EN_PROCESO'::character varying, 'HECHO'::character varying, 'REVISADO'::character varying])::text[])))
);


--
-- Name: inventario_conteo_historial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_conteo_historial (
    id_historial bigint NOT NULL,
    id_ronda bigint NOT NULL,
    id_producto integer NOT NULL,
    id_usuario integer NOT NULL,
    accion character varying(20) NOT NULL,
    anterior jsonb NOT NULL,
    nuevo jsonb NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: inventario_conteo_historial_id_historial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_conteo_historial ALTER COLUMN id_historial ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.inventario_conteo_historial_id_historial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_evento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_evento (
    id_evento bigint NOT NULL,
    id_local integer NOT NULL,
    id_jornada bigint NOT NULL,
    id_producto integer NOT NULL,
    cantidad numeric(18,3) NOT NULL,
    motivo character varying(40) NOT NULL,
    origen character varying(30) NOT NULL,
    id_origen bigint NOT NULL,
    registrado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT inventario_evento_cantidad_check CHECK ((cantidad <> (0)::numeric))
);


--
-- Name: inventario_evento_id_evento_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_evento ALTER COLUMN id_evento ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.inventario_evento_id_evento_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_jornada; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_jornada (
    id_jornada bigint NOT NULL,
    id_local integer NOT NULL,
    fecha date NOT NULL,
    abierto_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    cerrado_en timestamp with time zone,
    abierto_por integer,
    cerrado_por integer,
    reporte jsonb,
    CONSTRAINT inventario_jornada_check CHECK ((((cerrado_en IS NULL) AND (reporte IS NULL)) OR ((cerrado_en IS NOT NULL) AND (reporte IS NOT NULL))))
);


--
-- Name: inventario_jornada_id_jornada_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_jornada ALTER COLUMN id_jornada ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.inventario_jornada_id_jornada_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_jornada_inicio; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_jornada_inicio (
    id_jornada bigint NOT NULL,
    id_producto integer NOT NULL,
    cantidad numeric(18,3) NOT NULL
);


--
-- Name: inventario_ronda; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_ronda (
    id_ronda bigint NOT NULL,
    id_local integer NOT NULL,
    nombre character varying(120) NOT NULL,
    creado_por integer NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    cerrado_en timestamp with time zone,
    por_puesto boolean DEFAULT false NOT NULL
);


--
-- Name: inventario_ronda_id_ronda_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventario_ronda ALTER COLUMN id_ronda ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.inventario_ronda_id_ronda_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventario_saldo_inicial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_saldo_inicial (
    id_local integer NOT NULL,
    id_producto integer NOT NULL,
    cantidad numeric(18,3) NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: local; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.local (
    id_local integer NOT NULL,
    codigo character varying(30) NOT NULL,
    nombre character varying(100) NOT NULL,
    direccion character varying(250),
    estado_registro smallint DEFAULT 1 NOT NULL,
    fecha_creacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    usuario_creacion integer,
    fecha_modificacion timestamp without time zone,
    usuario_modificacion integer,
    CONSTRAINT chk_local_estado CHECK ((estado_registro = ANY (ARRAY[0, 1])))
);


--
-- Name: producto; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producto (
    id_producto integer NOT NULL,
    codigo character varying(10) NOT NULL,
    nombre character varying(200) NOT NULL,
    id_categoria integer NOT NULL,
    id_proveedor integer NOT NULL,
    unidad character varying(10) NOT NULL,
    stock_minimo numeric(12,3) DEFAULT 0 NOT NULL,
    presentacion numeric(12,3) DEFAULT 1 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_producto_codigo CHECK (((codigo)::text = upper((codigo)::text))),
    CONSTRAINT ck_producto_presentacion CHECK ((presentacion > (0)::numeric)),
    CONSTRAINT ck_producto_stock_minimo CHECK ((stock_minimo >= (0)::numeric)),
    CONSTRAINT ck_producto_unidad CHECK (((unidad)::text = ANY ((ARRAY['KGM'::character varying, 'LTR'::character varying, 'C62'::character varying])::text[])))
);


--
-- Name: inventario_stock_teorico; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.inventario_stock_teorico AS
 SELECT l.id_local,
    p.id_producto,
    COALESCE(b.cantidad, (0)::numeric) AS inicial,
    COALESCE(e.cantidad, (0)::numeric) AS variacion,
    (COALESCE(b.cantidad, (0)::numeric) + COALESCE(e.cantidad, (0)::numeric)) AS stock_actual
   FROM (((public.local l
     CROSS JOIN public.producto p)
     LEFT JOIN public.inventario_saldo_inicial b USING (id_local, id_producto))
     LEFT JOIN ( SELECT inventario_evento.id_local,
            inventario_evento.id_producto,
            sum(inventario_evento.cantidad) AS cantidad
           FROM public.inventario_evento
          GROUP BY inventario_evento.id_local, inventario_evento.id_producto) e USING (id_local, id_producto));


--
-- Name: item_carta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.item_carta (
    id_item_carta integer NOT NULL,
    codigo character varying(10) NOT NULL,
    nombre character varying(200) NOT NULL,
    id_categoria_carta integer NOT NULL,
    tipo character varying(15) NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_item_carta_codigo CHECK (((codigo)::text = upper((codigo)::text))),
    CONSTRAINT ck_item_carta_tipo CHECK (((tipo)::text = ANY ((ARRAY['DIRECTO'::character varying, 'PORCIONADO'::character varying, 'PREPARADO'::character varying])::text[])))
);


--
-- Name: item_carta_id_item_carta_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.item_carta ALTER COLUMN id_item_carta ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.item_carta_id_item_carta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: local_id_local_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.local_id_local_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: local_id_local_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.local_id_local_seq OWNED BY public.local.id_local;


--
-- Name: menaje; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menaje (
    id_menaje integer NOT NULL,
    nombre character varying(100) NOT NULL,
    activo boolean DEFAULT true NOT NULL
);


--
-- Name: menaje_id_menaje_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.menaje ALTER COLUMN id_menaje ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.menaje_id_menaje_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: movimiento_inventario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movimiento_inventario (
    id_movimiento_inventario integer NOT NULL,
    codigo character varying(20) NOT NULL,
    tipo_movimiento character varying(10) NOT NULL,
    motivo_movimiento character varying(30) NOT NULL,
    fecha_movimiento date NOT NULL,
    usuario_registro integer NOT NULL,
    local_relacionado character varying(150),
    id_proveedor integer,
    observacion character varying(500),
    id_local integer NOT NULL,
    registrado_en timestamp without time zone DEFAULT (clock_timestamp() AT TIME ZONE 'America/Lima'::text),
    CONSTRAINT ck_movimiento_coherencia CHECK (((((tipo_movimiento)::text = 'ENTRADA'::text) AND ((motivo_movimiento)::text = 'PRESTAMO_RECIBIDO'::text) AND (local_relacionado IS NOT NULL) AND (id_proveedor IS NULL)) OR (((tipo_movimiento)::text = 'ENTRADA'::text) AND ((motivo_movimiento)::text = 'REPOSICION_PROVEEDOR'::text) AND (local_relacionado IS NULL) AND (id_proveedor IS NOT NULL)) OR (((tipo_movimiento)::text = 'SALIDA'::text) AND ((motivo_movimiento)::text = ANY ((ARRAY['MERMA'::character varying, 'VENTA_SALON'::character varying])::text[])) AND (local_relacionado IS NULL) AND (id_proveedor IS NULL)) OR (((tipo_movimiento)::text = 'SALIDA'::text) AND ((motivo_movimiento)::text = 'PRESTAMO_ENTREGADO'::text) AND (local_relacionado IS NOT NULL) AND (id_proveedor IS NULL)) OR (((tipo_movimiento)::text = 'SALIDA'::text) AND ((motivo_movimiento)::text = 'DEVOLUCION_PROVEEDOR'::text) AND (local_relacionado IS NULL) AND (id_proveedor IS NOT NULL)))),
    CONSTRAINT ck_movimiento_local CHECK (((local_relacionado IS NULL) OR (btrim((local_relacionado)::text) <> ''::text))),
    CONSTRAINT ck_movimiento_motivo CHECK (((motivo_movimiento)::text = ANY ((ARRAY['PRESTAMO_RECIBIDO'::character varying, 'MERMA'::character varying, 'PRESTAMO_ENTREGADO'::character varying, 'DEVOLUCION_PROVEEDOR'::character varying, 'REPOSICION_PROVEEDOR'::character varying, 'VENTA_SALON'::character varying])::text[]))),
    CONSTRAINT ck_movimiento_tipo CHECK (((tipo_movimiento)::text = ANY ((ARRAY['ENTRADA'::character varying, 'SALIDA'::character varying])::text[])))
);


--
-- Name: COLUMN movimiento_inventario.id_local; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.movimiento_inventario.id_local IS 'Local propietario, distinto de la contraparte local_relacionado.';


--
-- Name: movimiento_inventario_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movimiento_inventario_detalle (
    id_movimiento_inventario_detalle integer CONSTRAINT movimiento_inventario_detal_id_movimiento_inventario_d_not_null NOT NULL,
    id_movimiento_inventario integer NOT NULL,
    id_producto integer NOT NULL,
    cantidad numeric(12,3) NOT NULL,
    CONSTRAINT ck_movimiento_cantidad CHECK ((cantidad > (0)::numeric))
);


--
-- Name: movimiento_inventario_detalle_id_movimiento_inventario_deta_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.movimiento_inventario_detalle ALTER COLUMN id_movimiento_inventario_detalle ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.movimiento_inventario_detalle_id_movimiento_inventario_deta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: movimiento_inventario_id_movimiento_inventario_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.movimiento_inventario ALTER COLUMN id_movimiento_inventario ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.movimiento_inventario_id_movimiento_inventario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: movimiento_reintegro; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movimiento_reintegro (
    id_movimiento integer NOT NULL,
    id_salida integer NOT NULL,
    guia_proveedor character varying(100),
    registrado_en timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: movimiento_seguimiento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movimiento_seguimiento (
    id_movimiento integer NOT NULL,
    id_local_destino integer,
    estado character varying(30) NOT NULL,
    CONSTRAINT movimiento_seguimiento_check CHECK ((((id_local_destino IS NOT NULL) AND ((estado)::text = ANY ((ARRAY['PENDIENTE_RECEPCION'::character varying, 'ACEPTADO'::character varying])::text[]))) OR ((id_local_destino IS NULL) AND ((estado)::text = ANY ((ARRAY['DEVUELTO'::character varying, 'REINTEGRO_PARCIAL'::character varying, 'REINTEGRADO'::character varying])::text[]))))),
    CONSTRAINT movimiento_seguimiento_estado_check CHECK (((estado)::text = ANY ((ARRAY['PENDIENTE_RECEPCION'::character varying, 'ACEPTADO'::character varying, 'DEVUELTO'::character varying, 'REINTEGRO_PARCIAL'::character varying, 'REINTEGRADO'::character varying])::text[])))
);


--
-- Name: opcion_menu; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.opcion_menu (
    id_opcion_menu integer NOT NULL,
    nombre character varying(100) NOT NULL,
    url_menu character varying(180),
    descripcion character varying(500) NOT NULL,
    id_padre integer,
    estado_registro smallint DEFAULT 1 NOT NULL,
    codigo character varying(60) NOT NULL,
    icono character varying(80),
    tipo_opcion character varying(15) DEFAULT 'ENLACE'::character varying NOT NULL,
    es_configurable boolean DEFAULT true NOT NULL,
    usuario_creacion integer,
    fecha_creacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    usuario_modificacion integer,
    fecha_modificacion timestamp without time zone,
    CONSTRAINT ck_opcion_menu_estado CHECK ((estado_registro = ANY (ARRAY[0, 1]))),
    CONSTRAINT ck_opcion_menu_tipo CHECK (((tipo_opcion)::text = ANY ((ARRAY['GRUPO'::character varying, 'ENLACE'::character varying])::text[])))
);


--
-- Name: opcion_menu_id_opcion_menu_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.opcion_menu ALTER COLUMN id_opcion_menu ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.opcion_menu_id_opcion_menu_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: orden_compra; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orden_compra (
    id_orden_compra integer NOT NULL,
    codigo character varying(20) NOT NULL,
    estado_orden_compra character varying(25) DEFAULT 'BORRADOR'::character varying NOT NULL,
    usuario_registro integer NOT NULL,
    fecha_registro date,
    motivo_cierre character varying(500),
    usuario_modificacion integer,
    fecha_modificacion timestamp without time zone,
    id_local integer NOT NULL,
    CONSTRAINT ck_orden_estado CHECK (((estado_orden_compra)::text = ANY ((ARRAY['BORRADOR'::character varying, 'ENVIADA'::character varying, 'RECEPCION_PARCIAL'::character varying, 'RECEPCIONADA'::character varying, 'CERRADA_INCOMPLETA'::character varying, 'CANCELADA'::character varying])::text[]))),
    CONSTRAINT ck_orden_fecha CHECK (((((estado_orden_compra)::text = 'BORRADOR'::text) AND (fecha_registro IS NULL)) OR (((estado_orden_compra)::text <> 'BORRADOR'::text) AND (fecha_registro IS NOT NULL))))
);


--
-- Name: COLUMN orden_compra.id_local; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orden_compra.id_local IS 'Local propietario; las recepciones heredan el local de esta orden.';


--
-- Name: orden_compra_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orden_compra_detalle (
    id_orden_compra_detalle integer NOT NULL,
    id_orden_compra integer NOT NULL,
    id_producto integer NOT NULL,
    cantidad_solicitada numeric(12,3) NOT NULL,
    id_proveedor integer NOT NULL,
    CONSTRAINT ck_orden_cantidad CHECK ((cantidad_solicitada > (0)::numeric))
);


--
-- Name: COLUMN orden_compra_detalle.id_proveedor; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orden_compra_detalle.id_proveedor IS 'Proveedor pactado en esta linea, independiente del proveedor actual del producto.';


--
-- Name: orden_compra_detalle_id_orden_compra_detalle_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.orden_compra_detalle ALTER COLUMN id_orden_compra_detalle ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.orden_compra_detalle_id_orden_compra_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: orden_compra_estado_historial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orden_compra_estado_historial (
    id_orden_compra_estado_historial bigint CONSTRAINT orden_compra_estado_histori_id_orden_compra_estado_his_not_null NOT NULL,
    id_orden_compra integer NOT NULL,
    estado_anterior character varying(30) NOT NULL,
    estado_nuevo character varying(30) NOT NULL,
    motivo character varying(500) NOT NULL,
    usuario_modificacion integer NOT NULL,
    fecha_modificacion timestamp without time zone DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'America/Lima'::text) NOT NULL,
    CONSTRAINT ck_oceh_estados_diferentes CHECK (((estado_anterior)::text <> (estado_nuevo)::text)),
    CONSTRAINT ck_oceh_motivo CHECK ((btrim((motivo)::text) <> ''::text))
);


--
-- Name: orden_compra_estado_historial_id_orden_compra_estado_histor_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.orden_compra_estado_historial ALTER COLUMN id_orden_compra_estado_historial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.orden_compra_estado_historial_id_orden_compra_estado_histor_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: orden_compra_id_orden_compra_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.orden_compra ALTER COLUMN id_orden_compra ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.orden_compra_id_orden_compra_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: perfil_gestion_usuario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.perfil_gestion_usuario (
    id_perfil_gestor integer NOT NULL,
    id_perfil_objetivo integer NOT NULL,
    puede_crear boolean DEFAULT false NOT NULL,
    puede_editar boolean DEFAULT false NOT NULL,
    estado_registro smallint DEFAULT 1 NOT NULL,
    CONSTRAINT ck_perfil_gestion_estado CHECK ((estado_registro = ANY (ARRAY[0, 1])))
);


--
-- Name: perfil_opcion_menu; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.perfil_opcion_menu (
    id_perfil integer NOT NULL,
    id_opcion_menu integer NOT NULL,
    puede_consultar boolean DEFAULT false NOT NULL,
    puede_crear boolean DEFAULT false NOT NULL,
    puede_editar boolean DEFAULT false NOT NULL,
    puede_revisar boolean DEFAULT false NOT NULL,
    puede_cerrar boolean DEFAULT false NOT NULL,
    orden smallint NOT NULL,
    estado_registro smallint DEFAULT 1 NOT NULL,
    puede_desactivar boolean DEFAULT false NOT NULL,
    puede_reactivar boolean DEFAULT false NOT NULL,
    puede_eliminar boolean DEFAULT false NOT NULL,
    puede_configurar boolean DEFAULT false NOT NULL,
    CONSTRAINT ck_perfil_opcion_estado CHECK ((estado_registro = ANY (ARRAY[0, 1]))),
    CONSTRAINT ck_perfil_opcion_orden CHECK ((orden > 0))
);


--
-- Name: perfiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.perfiles (
    id_perfil integer NOT NULL,
    nombre character varying(60) NOT NULL,
    descripcion character varying(500) NOT NULL,
    estado_registro smallint DEFAULT 1 NOT NULL,
    CONSTRAINT ck_perfiles_estado CHECK ((estado_registro = ANY (ARRAY[0, 1])))
);


--
-- Name: perfiles_id_perfil_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.perfiles ALTER COLUMN id_perfil ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.perfiles_id_perfil_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: presentacion_venta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.presentacion_venta (
    id_presentacion_venta integer NOT NULL,
    id_item_carta integer NOT NULL,
    id_menaje integer NOT NULL,
    contenido numeric(12,3) NOT NULL,
    unidad character varying(10) NOT NULL,
    precio numeric(10,2) NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_presentacion_venta_contenido CHECK ((contenido > (0)::numeric)),
    CONSTRAINT ck_presentacion_venta_precio CHECK ((precio >= (0)::numeric)),
    CONSTRAINT ck_presentacion_venta_unidad CHECK (((unidad)::text = ANY ((ARRAY['KGM'::character varying, 'LTR'::character varying, 'C62'::character varying, 'PORCION'::character varying])::text[])))
);


--
-- Name: presentacion_venta_id_presentacion_venta_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.presentacion_venta ALTER COLUMN id_presentacion_venta ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.presentacion_venta_id_presentacion_venta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: producto_categoria_historial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producto_categoria_historial (
    id_producto_categoria_historial bigint CONSTRAINT producto_categoria_historia_id_producto_categoria_hist_not_null NOT NULL,
    id_producto integer NOT NULL,
    id_categoria_anterior integer NOT NULL,
    id_categoria_nueva integer NOT NULL,
    usuario_cambio integer NOT NULL,
    fecha_cambio timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    motivo character varying(500) NOT NULL,
    CONSTRAINT ck_producto_categoria_historial_diferentes CHECK ((id_categoria_anterior <> id_categoria_nueva)),
    CONSTRAINT ck_producto_categoria_historial_motivo CHECK (((length(btrim((motivo)::text)) >= 10) AND (length(btrim((motivo)::text)) <= 500)))
);


--
-- Name: producto_categoria_historial_id_producto_categoria_historia_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.producto_categoria_historial ALTER COLUMN id_producto_categoria_historial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.producto_categoria_historial_id_producto_categoria_historia_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: producto_id_producto_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.producto ALTER COLUMN id_producto ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.producto_id_producto_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: producto_proveedor_historial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producto_proveedor_historial (
    id_producto_proveedor_historial bigint CONSTRAINT producto_proveedor_historia_id_producto_proveedor_hist_not_null NOT NULL,
    id_producto integer NOT NULL,
    id_proveedor_anterior integer NOT NULL,
    id_proveedor_nuevo integer NOT NULL,
    usuario_cambio integer NOT NULL,
    fecha_cambio timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    motivo character varying(500) NOT NULL,
    CONSTRAINT ck_producto_proveedor_historial_diferentes CHECK ((id_proveedor_anterior <> id_proveedor_nuevo)),
    CONSTRAINT ck_producto_proveedor_historial_motivo CHECK (((length(btrim((motivo)::text)) >= 10) AND (length(btrim((motivo)::text)) <= 500)))
);


--
-- Name: producto_proveedor_historial_id_producto_proveedor_historia_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.producto_proveedor_historial ALTER COLUMN id_producto_proveedor_historial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.producto_proveedor_historial_id_producto_proveedor_historia_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: producto_stock_local; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producto_stock_local (
    id_producto integer NOT NULL,
    id_local integer NOT NULL,
    stock_minimo numeric(12,3) DEFAULT 0 NOT NULL,
    stock_maximo numeric(12,3),
    CONSTRAINT ck_stock_local_maximo CHECK (((stock_maximo IS NULL) OR (stock_maximo >= stock_minimo))),
    CONSTRAINT ck_stock_local_minimo CHECK ((stock_minimo >= (0)::numeric))
);


--
-- Name: promocion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promocion (
    id_promocion integer NOT NULL,
    codigo character varying(10) NOT NULL,
    nombre character varying(150) NOT NULL,
    precio numeric(10,2) NOT NULL,
    hora_inicio time without time zone,
    hora_fin time without time zone,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_promocion_horario CHECK ((((hora_inicio IS NULL) AND (hora_fin IS NULL)) OR ((hora_inicio IS NOT NULL) AND (hora_fin IS NOT NULL)))),
    CONSTRAINT promocion_codigo_check CHECK (((codigo)::text = upper((codigo)::text))),
    CONSTRAINT promocion_precio_check CHECK ((precio >= (0)::numeric))
);


--
-- Name: promocion_grupo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promocion_grupo (
    id_promocion_grupo integer NOT NULL,
    id_promocion integer NOT NULL,
    cantidad_elegir smallint NOT NULL,
    permite_repetir boolean DEFAULT false NOT NULL,
    CONSTRAINT promocion_grupo_cantidad_elegir_check CHECK ((cantidad_elegir > 0))
);


--
-- Name: promocion_grupo_id_promocion_grupo_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.promocion_grupo ALTER COLUMN id_promocion_grupo ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.promocion_grupo_id_promocion_grupo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: promocion_id_promocion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.promocion ALTER COLUMN id_promocion ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.promocion_id_promocion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: promocion_opcion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promocion_opcion (
    id_promocion_opcion integer NOT NULL,
    id_promocion_grupo integer NOT NULL,
    id_presentacion_venta integer NOT NULL
);


--
-- Name: promocion_opcion_id_promocion_opcion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.promocion_opcion ALTER COLUMN id_promocion_opcion ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.promocion_opcion_id_promocion_opcion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: proveedor; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proveedor (
    id_proveedor integer NOT NULL,
    nombre character varying(200) NOT NULL,
    activo boolean DEFAULT true NOT NULL
);


--
-- Name: proveedor_categoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proveedor_categoria (
    id_proveedor integer NOT NULL,
    id_categoria integer NOT NULL
);


--
-- Name: proveedor_id_proveedor_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.proveedor ALTER COLUMN id_proveedor ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.proveedor_id_proveedor_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: puesto_laboral; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.puesto_laboral (
    id_puesto_laboral integer NOT NULL,
    nombre character varying(80) NOT NULL,
    descripcion character varying(250),
    estado_registro smallint DEFAULT 1 NOT NULL,
    usuario_creacion integer,
    fecha_creacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    usuario_modificacion integer,
    fecha_modificacion timestamp without time zone,
    CONSTRAINT ck_puesto_laboral_estado CHECK ((estado_registro = ANY (ARRAY[0, 1])))
);


--
-- Name: puesto_laboral_id_puesto_laboral_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.puesto_laboral ALTER COLUMN id_puesto_laboral ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.puesto_laboral_id_puesto_laboral_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: receta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receta (
    id_receta integer NOT NULL,
    id_presentacion_venta integer NOT NULL,
    instrucciones text DEFAULT 'Pendiente de registrar.'::text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_receta_instrucciones CHECK ((length(btrim(instrucciones)) > 0))
);


--
-- Name: receta_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receta_detalle (
    id_receta_detalle integer NOT NULL,
    id_receta integer NOT NULL,
    tipo_componente character varying(15) NOT NULL,
    id_producto integer,
    id_subproducto integer,
    cantidad numeric(12,3) NOT NULL,
    unidad character varying(10) NOT NULL,
    CONSTRAINT ck_receta_detalle_cantidad CHECK ((cantidad > (0)::numeric)),
    CONSTRAINT ck_receta_detalle_componente CHECK (((((tipo_componente)::text = 'PRODUCTO'::text) AND (id_producto IS NOT NULL) AND (id_subproducto IS NULL)) OR (((tipo_componente)::text = 'SUBPRODUCTO'::text) AND (id_producto IS NULL) AND (id_subproducto IS NOT NULL)))),
    CONSTRAINT ck_receta_detalle_tipo CHECK (((tipo_componente)::text = ANY ((ARRAY['PRODUCTO'::character varying, 'SUBPRODUCTO'::character varying])::text[]))),
    CONSTRAINT ck_receta_detalle_unidad CHECK (((unidad)::text = ANY ((ARRAY['KGM'::character varying, 'LTR'::character varying, 'C62'::character varying, 'PORCION'::character varying])::text[])))
);


--
-- Name: receta_detalle_id_receta_detalle_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.receta_detalle ALTER COLUMN id_receta_detalle ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.receta_detalle_id_receta_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: receta_id_receta_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.receta ALTER COLUMN id_receta ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.receta_id_receta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: salon_autorizacion_usada; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_autorizacion_usada (
    clave uuid NOT NULL,
    fecha timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: salon_cobro; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_cobro (
    id_cobro bigint NOT NULL,
    id_local integer NOT NULL,
    id_usuario integer NOT NULL,
    mesa character varying(4) NOT NULL,
    clave uuid NOT NULL,
    solicitud_hash character varying(64) NOT NULL,
    tipo character varying(20) NOT NULL,
    metodo character varying(10) NOT NULL,
    documento character varying(11) DEFAULT ''::character varying NOT NULL,
    cliente character varying(200) DEFAULT ''::character varying NOT NULL,
    total numeric(12,2) NOT NULL,
    comprobante jsonb NOT NULL,
    id_movimiento integer NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    id_jornada bigint,
    CONSTRAINT salon_cobro_check CHECK (((((tipo)::text = 'BOLETA'::text) AND ((documento)::text = ''::text) AND ((cliente)::text = ''::text)) OR (((tipo)::text = 'BOLETA_ELECTRONICA'::text) AND ((documento)::text ~ '^[0-9]{8}$'::text) AND (length(btrim((cliente)::text)) > 0)) OR (((tipo)::text = 'FACTURA'::text) AND ((documento)::text ~ '^[0-9]{11}$'::text) AND (length(btrim((cliente)::text)) > 0)))),
    CONSTRAINT salon_cobro_metodo_check CHECK (((metodo)::text = ANY ((ARRAY['EFECTIVO'::character varying, 'TARJETA'::character varying])::text[]))),
    CONSTRAINT salon_cobro_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['BOLETA'::character varying, 'BOLETA_ELECTRONICA'::character varying, 'FACTURA'::character varying])::text[]))),
    CONSTRAINT salon_cobro_total_check CHECK ((total >= (0)::numeric))
);


--
-- Name: salon_cobro_id_cobro_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.salon_cobro ALTER COLUMN id_cobro ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.salon_cobro_id_cobro_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: salon_cobro_pedido; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_cobro_pedido (
    id_pedido bigint NOT NULL,
    id_cobro bigint NOT NULL
);


--
-- Name: salon_distribucion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_distribucion (
    id_local integer NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    elementos jsonb NOT NULL,
    CONSTRAINT salon_distribucion_elementos_check CHECK ((jsonb_typeof(elementos) = 'array'::text)),
    CONSTRAINT salon_distribucion_version_check CHECK ((version > 0))
);


--
-- Name: salon_intentos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_intentos (
    origen character varying(64) NOT NULL,
    inicio timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    intentos integer DEFAULT 0 NOT NULL
);


--
-- Name: salon_linea_anulada; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_linea_anulada (
    id_linea bigint NOT NULL,
    id_responsable integer NOT NULL,
    fecha timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: salon_pedido; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_pedido (
    id_pedido bigint NOT NULL,
    id_local integer NOT NULL,
    mesa character varying(4) NOT NULL,
    id_usuario integer NOT NULL,
    estado character varying(10) DEFAULT 'BORRADOR'::character varying NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    creado_en timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    enviado_en timestamp with time zone,
    envio_clave uuid,
    envio_hash character varying(64),
    CONSTRAINT salon_pedido_check CHECK (((((estado)::text = 'BORRADOR'::text) AND (enviado_en IS NULL)) OR (((estado)::text = 'ENVIADO'::text) AND (enviado_en IS NOT NULL)))),
    CONSTRAINT salon_pedido_estado_check CHECK (((estado)::text = ANY ((ARRAY['BORRADOR'::character varying, 'ENVIADO'::character varying])::text[]))),
    CONSTRAINT salon_pedido_mesa_check CHECK (((mesa)::text ~ '^[MB][0-9]{2,3}$'::text))
);


--
-- Name: salon_pedido_asignacion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_pedido_asignacion (
    id_pedido bigint NOT NULL,
    mesa character varying(4) NOT NULL,
    id_usuario integer NOT NULL,
    CONSTRAINT salon_pedido_asignacion_mesa_check CHECK (((mesa)::text ~ '^[MB][0-9]{2,3}$'::text))
);


--
-- Name: salon_pedido_actual; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.salon_pedido_actual AS
 SELECT p.id_pedido,
    p.id_local,
    COALESCE(a.mesa, p.mesa) AS mesa,
    COALESCE(a.id_usuario, p.id_usuario) AS id_usuario,
    p.estado,
    p.version,
    p.creado_en,
    p.enviado_en,
    p.envio_clave,
    p.envio_hash
   FROM (public.salon_pedido p
     LEFT JOIN public.salon_pedido_asignacion a USING (id_pedido))
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.salon_cobro_pedido c
          WHERE (c.id_pedido = p.id_pedido))));


--
-- Name: salon_pedido_id_pedido_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.salon_pedido ALTER COLUMN id_pedido ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.salon_pedido_id_pedido_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: salon_pedido_linea; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salon_pedido_linea (
    id_linea bigint NOT NULL,
    id_pedido bigint NOT NULL,
    posicion integer NOT NULL,
    id_presentacion integer NOT NULL,
    nombre text NOT NULL,
    precio numeric(10,2) NOT NULL,
    cantidad integer NOT NULL,
    comentario character varying(500) DEFAULT ''::character varying NOT NULL,
    opciones jsonb DEFAULT '[]'::jsonb NOT NULL,
    CONSTRAINT salon_pedido_linea_cantidad_check CHECK (((cantidad >= 1) AND (cantidad <= 99))),
    CONSTRAINT salon_pedido_linea_opciones_check CHECK ((jsonb_typeof(opciones) = 'array'::text)),
    CONSTRAINT salon_pedido_linea_precio_check CHECK ((precio >= (0)::numeric))
);


--
-- Name: salon_pedido_linea_id_linea_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.salon_pedido_linea ALTER COLUMN id_linea ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.salon_pedido_linea_id_linea_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: subproducto; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subproducto (
    id_subproducto integer NOT NULL,
    codigo character varying(10) NOT NULL,
    nombre character varying(150) NOT NULL,
    rendimiento numeric(12,3) DEFAULT 1 NOT NULL,
    unidad character varying(10) NOT NULL,
    instruccion text,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_subproducto_codigo CHECK (((codigo)::text = upper((codigo)::text))),
    CONSTRAINT ck_subproducto_rendimiento CHECK ((rendimiento > (0)::numeric)),
    CONSTRAINT ck_subproducto_unidad CHECK (((unidad)::text = ANY ((ARRAY['KGM'::character varying, 'LTR'::character varying, 'PORCION'::character varying])::text[])))
);


--
-- Name: subproducto_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subproducto_detalle (
    id_subproducto_detalle integer NOT NULL,
    id_subproducto integer NOT NULL,
    id_producto integer NOT NULL,
    cantidad numeric(12,3) NOT NULL,
    unidad character varying(10) NOT NULL,
    CONSTRAINT ck_subproducto_detalle_cantidad CHECK ((cantidad > (0)::numeric)),
    CONSTRAINT ck_subproducto_detalle_unidad CHECK (((unidad)::text = ANY ((ARRAY['KGM'::character varying, 'LTR'::character varying, 'C62'::character varying])::text[])))
);


--
-- Name: subproducto_detalle_id_subproducto_detalle_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.subproducto_detalle ALTER COLUMN id_subproducto_detalle ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.subproducto_detalle_id_subproducto_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: subproducto_id_subproducto_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.subproducto ALTER COLUMN id_subproducto ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.subproducto_id_subproducto_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: unidad_medida; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.unidad_medida (
    codigo character varying(10) NOT NULL,
    nombre character varying(40) NOT NULL,
    simbolo character varying(10) NOT NULL,
    dimension character varying(10) NOT NULL,
    codigo_unece character varying(3),
    codigo_base character varying(10) NOT NULL,
    factor_a_base numeric(12,6) NOT NULL,
    CONSTRAINT unidad_medida_dimension_check CHECK (((dimension)::text = ANY ((ARRAY['MASA'::character varying, 'VOLUMEN'::character varying, 'CONTEO'::character varying])::text[]))),
    CONSTRAINT unidad_medida_factor_a_base_check CHECK ((factor_a_base > (0)::numeric))
);


--
-- Name: usuario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario (
    id_usuario integer NOT NULL,
    dni character varying(8) NOT NULL,
    nombres character varying(100) NOT NULL,
    apellido_paterno character varying(80) NOT NULL,
    apellido_materno character varying(80),
    celular character varying(15) NOT NULL,
    correo_electronico character varying(150) NOT NULL,
    clave character varying(255) NOT NULL,
    usuario_creacion integer,
    fecha_creacion date DEFAULT CURRENT_DATE NOT NULL,
    usuario_modificacion integer,
    fecha_modificacion date,
    estado_registro smallint DEFAULT 1 NOT NULL,
    id_puesto_laboral integer,
    CONSTRAINT ck_usuario_celular CHECK (((celular)::text ~ '^[0-9]{9,15}$'::text)),
    CONSTRAINT ck_usuario_correo_corporativo CHECK ((lower(TRIM(BOTH FROM correo_electronico)) ~ '^[a-z0-9][a-z0-9._-]*@barbarian\.pe$'::text)),
    CONSTRAINT ck_usuario_dni CHECK (((dni)::text ~ '^[0-9]{8}$'::text)),
    CONSTRAINT ck_usuario_estado CHECK ((estado_registro = ANY (ARRAY[0, 1]))),
    CONSTRAINT ck_usuario_modificacion CHECK ((((usuario_modificacion IS NULL) AND (fecha_modificacion IS NULL)) OR ((usuario_modificacion IS NOT NULL) AND (fecha_modificacion IS NOT NULL))))
);


--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.usuario ALTER COLUMN id_usuario ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.usuario_id_usuario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: usuario_local; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario_local (
    id_usuario_local integer NOT NULL,
    id_usuario integer NOT NULL,
    id_local integer NOT NULL,
    estado_registro smallint DEFAULT 1 NOT NULL,
    fecha_asignacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    usuario_asignacion integer,
    fecha_modificacion timestamp without time zone,
    usuario_modificacion integer,
    CONSTRAINT chk_usuario_local_estado CHECK ((estado_registro = ANY (ARRAY[0, 1])))
);


--
-- Name: usuario_local_id_usuario_local_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.usuario_local_id_usuario_local_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: usuario_local_id_usuario_local_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.usuario_local_id_usuario_local_seq OWNED BY public.usuario_local.id_usuario_local;


--
-- Name: usuario_perfiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario_perfiles (
    id_usuario integer NOT NULL,
    id_perfil integer NOT NULL,
    usuario_asignacion integer NOT NULL,
    fecha_asignacion date DEFAULT CURRENT_DATE NOT NULL,
    usuario_modificacion integer,
    fecha_modificacion date,
    estado_registro smallint DEFAULT 1 NOT NULL,
    CONSTRAINT ck_usuario_perfiles_estado CHECK ((estado_registro = ANY (ARRAY[0, 1]))),
    CONSTRAINT ck_usuario_perfiles_modificacion CHECK ((((usuario_modificacion IS NULL) AND (fecha_modificacion IS NULL)) OR ((usuario_modificacion IS NOT NULL) AND (fecha_modificacion IS NOT NULL))))
);


--
-- Name: usuario_pin_salon; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario_pin_salon (
    id_usuario integer NOT NULL,
    pin_hash text NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    fallos integer DEFAULT 0 NOT NULL,
    bloqueado_hasta timestamp with time zone,
    actualizado_en timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: usuario_puestos_laborales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario_puestos_laborales (
    id_usuario integer NOT NULL,
    id_puesto_laboral integer NOT NULL,
    usuario_asignacion integer NOT NULL,
    fecha_asignacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    usuario_modificacion integer,
    fecha_modificacion timestamp without time zone,
    estado_registro smallint DEFAULT 1 NOT NULL,
    CONSTRAINT ck_upl_estado CHECK ((estado_registro = ANY (ARRAY[0, 1])))
);


--
-- Name: local id_local; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.local ALTER COLUMN id_local SET DEFAULT nextval('public.local_id_local_seq'::regclass);


--
-- Name: usuario_local id_usuario_local; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_local ALTER COLUMN id_usuario_local SET DEFAULT nextval('public.usuario_local_id_usuario_local_seq'::regclass);


--
-- Data for Name: actividad_usuario; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.actividad_usuario (id_actividad_usuario, id_usuario, modulo, accion, id_registro_afectado, descripcion, fecha_actividad, estado_registro, id_perfil_utilizado, id_puesto_laboral, id_local) FROM stdin;
1	1	USUARIO	CREAR	2	Creó al usuario José Ríos con perfil de gerente	2026-08-28 09:10:00	1	\N	\N	\N
2	2	USUARIO	CREAR	3	Creó al usuario Roberto Díaz con perfil de supervisor	2026-08-28 09:20:00	1	\N	\N	\N
3	2	USUARIO	CREAR	4	Creó a María López con perfil de miembro de equipo	2026-08-28 09:30:00	1	\N	\N	\N
4	4	INVENTARIO	INICIAR	1	Inició el inventario correspondiente al 01/09/2026	2026-09-01 20:00:00	1	\N	\N	\N
5	4	INVENTARIO	CERRAR	1	Cerró el inventario correspondiente al 01/09/2026	2026-09-01 22:45:00	1	\N	\N	\N
6	3	INVENTARIO	REVISAR	1	Revisó el inventario y registró una observación	2026-09-02 09:00:00	1	\N	\N	\N
7	3	ORDEN_COMPRA	CREAR	3	Creó el borrador de la orden de compra OC-003	2026-09-13 10:00:00	1	\N	\N	\N
8	2	ORDEN_COMPRA	CONFIRMAR	1	Confirmó la orden de compra OC-001	2026-09-05 09:00:00	1	\N	\N	\N
9	3	RECEPCION	REGISTRAR	1	Registró la factura F001-4587	2026-09-07 08:30:00	1	\N	\N	\N
10	2	RECEPCION	REGISTRAR	2	Registró la factura F001-4620	2026-09-09 09:15:00	1	\N	\N	\N
11	3	MOVIMIENTO	REGISTRAR	1	Registró un préstamo recibido de otra tienda	2026-09-10 10:00:00	1	\N	\N	\N
12	3	MOVIMIENTO	REGISTRAR	2	Registró una salida de productos por merma	2026-09-10 18:00:00	1	\N	\N	\N
13	2	MOVIMIENTO	REGISTRAR	3	Registró un préstamo entregado a otra tienda	2026-09-11 11:00:00	1	\N	\N	\N
14	3	MOVIMIENTO	REGISTRAR	4	Registró una devolución de productos al proveedor	2026-09-12 10:30:00	1	\N	\N	\N
15	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-01 19:20:31.454847	1	\N	\N	\N
16	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-01 19:21:59.778893	1	\N	\N	\N
17	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-01 19:23:12.825452	1	\N	\N	\N
18	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-01 21:02:42.008075	1	\N	\N	\N
19	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-01 21:36:18.856997	1	\N	\N	\N
20	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-01 21:36:52.786195	1	\N	\N	\N
21	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-01 21:39:11.770556	1	\N	\N	\N
22	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-01 21:40:26.056906	1	\N	\N	\N
23	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-01 21:41:06.507181	1	\N	\N	\N
24	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-01 21:41:27.743618	1	\N	\N	\N
25	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-02 00:02:02.442241	1	\N	\N	\N
26	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-02 01:38:17.469486	1	\N	\N	\N
27	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-02 15:45:30.108913	1	\N	\N	\N
28	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-02 16:31:32.180998	1	\N	\N	\N
29	4	INVENTARIO	CERRAR	2	Cerró el inventario correspondiente a la fecha 2026-09-02	2026-09-02 16:55:42.250999	1	\N	\N	\N
30	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-02 17:09:25.929722	1	\N	\N	\N
31	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-02 17:09:56.082113	1	\N	\N	\N
32	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-02 19:59:01.410894	1	\N	\N	\N
33	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-02 21:27:35.084882	1	\N	\N	\N
34	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-03 01:11:41.485535	1	\N	\N	\N
35	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-03 11:18:36.30482	1	\N	\N	\N
36	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-08 17:13:27.153858	1	\N	\N	\N
37	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-08 17:23:35.857617	1	\N	\N	\N
38	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 00:05:08.536085	1	\N	\N	\N
39	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 09:50:01.783669	1	\N	\N	\N
40	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-09 12:30:05.180487	1	\N	\N	\N
41	2	INVENTARIO	REVISAR	2	Registró la revisión del inventario 2: PRODUCTOS NO CONTADOS	2026-09-09 12:32:12.274658	1	\N	\N	\N
42	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 13:52:50.395701	1	\N	\N	\N
43	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-09 13:53:04.589535	1	\N	\N	\N
44	2	INVENTARIO	CORREGIR	2	Corrigió 140 producto(s) del inventario 2: ERROR DE CONTEO	2026-09-09 14:02:24.609226	1	\N	\N	\N
45	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-09 15:43:21.81226	1	\N	\N	\N
46	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-09 15:43:45.676948	1	\N	\N	\N
47	2	ORDEN_COMPRA	CREAR	4	Registró la orden OC-004 en estado ENVIADA	2026-09-09 16:42:18.935655	1	\N	\N	\N
48	2	RECEPCION_PRODUCTOS	CREAR	3	Registró la factura 00001 para la orden OC-004	2026-09-09 16:45:17.927355	1	\N	\N	\N
49	2	RECEPCION_PRODUCTOS	CREAR	4	Registró la factura 000002 para la orden OC-004	2026-09-09 16:46:02.066497	1	\N	\N	\N
50	2	RECEPCION_PRODUCTOS	CREAR	5	Registró la factura 000003 para la orden OC-004	2026-09-09 16:46:12.142582	1	\N	\N	\N
51	2	RECEPCION_PRODUCTOS	CREAR	6	Registró la factura 00005 para la orden OC-004	2026-09-09 16:46:20.209521	1	\N	\N	\N
52	2	RECEPCION_PRODUCTOS	CREAR	7	Registró la factura 000006 para la orden OC-004	2026-09-09 16:46:29.36707	1	\N	\N	\N
53	2	RECEPCION_PRODUCTOS	CREAR	8	Registró la factura 00004 para la orden OC-004	2026-09-09 16:46:34.454402	1	\N	\N	\N
54	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 16:49:11.619798	1	\N	\N	\N
55	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-09 16:49:29.870663	1	\N	\N	\N
56	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-09 17:38:25.398843	1	\N	\N	\N
57	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-09 17:41:05.935722	1	\N	\N	\N
58	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-09 18:54:28.349749	1	\N	\N	\N
59	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 18:55:04.302909	1	\N	\N	\N
60	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-09 19:04:23.738492	1	\N	\N	\N
61	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-09 19:04:33.245462	1	\N	\N	\N
62	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-09 19:04:38.440552	1	\N	\N	\N
63	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 19:04:44.977061	1	\N	\N	\N
64	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 19:22:14.946973	1	\N	\N	\N
65	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-09 19:49:40.149516	1	\N	\N	\N
66	4	INVENTARIO	INICIAR	10	Inició el inventario correspondiente a la fecha 2026-09-09	2026-09-09 19:49:45.740144	1	\N	\N	\N
67	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-09 19:49:55.859914	1	\N	\N	\N
68	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-09 19:50:04.411345	1	\N	\N	\N
69	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 19:50:09.64224	1	\N	\N	\N
70	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-09 19:59:01.527033	1	\N	\N	\N
71	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-09 19:59:09.438473	1	\N	\N	\N
72	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-09 20:00:06.317675	1	\N	\N	\N
73	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-09 20:01:41.689629	1	\N	\N	\N
74	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-09 20:01:54.918181	1	\N	\N	\N
75	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-09 20:01:58.351514	1	\N	\N	\N
76	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-09 20:02:03.757823	1	\N	\N	\N
77	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-09 20:02:13.946474	1	\N	\N	\N
78	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-09 20:02:20.794432	1	\N	\N	\N
79	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-09 20:02:23.809487	1	\N	\N	\N
80	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 20:02:29.342321	1	\N	\N	\N
81	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 20:02:56.566853	1	\N	\N	\N
82	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-09 20:03:08.254447	1	\N	\N	\N
83	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-09 20:03:18.862673	1	\N	\N	\N
84	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-09 20:04:54.926127	1	\N	\N	\N
85	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-09 20:21:20.006675	1	\N	\N	\N
86	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-09 20:21:33.790434	1	\N	\N	\N
87	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-09 22:05:38.003194	1	\N	\N	\N
88	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 22:05:43.710912	1	\N	\N	\N
89	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 22:22:52.326526	1	\N	\N	\N
90	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 23:23:35.434008	1	\N	\N	\N
91	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-09 23:24:46.586727	1	\N	\N	\N
92	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 23:25:17.297906	1	\N	\N	\N
93	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 23:49:53.114357	1	\N	\N	\N
94	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-09 23:54:00.078822	1	\N	\N	\N
95	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-10 05:56:14.864675	1	\N	\N	\N
96	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-10 05:56:22.334819	1	\N	\N	\N
97	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-10 12:59:28.83824	1	\N	\N	\N
98	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-10 13:29:24.397661	1	\N	\N	\N
99	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-10 13:42:59.88513	1	\N	\N	\N
100	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-10 13:43:18.811835	1	\N	\N	\N
101	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-10 13:47:10.782907	1	\N	\N	\N
102	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-10 13:49:55.04507	1	\N	\N	\N
103	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-10 13:50:16.565667	1	\N	\N	\N
104	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-10 17:40:08.013663	1	\N	\N	\N
105	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-10 17:40:22.846185	1	\N	\N	\N
106	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-10 17:40:28.793728	1	\N	\N	\N
107	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-10 17:41:42.076182	1	\N	\N	\N
108	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-10 17:53:15.657544	1	\N	\N	\N
109	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-10 17:53:41.686505	1	\N	\N	\N
110	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-10 18:49:28.058801	1	\N	\N	\N
111	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-10 18:49:34.917095	1	\N	\N	\N
112	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-10 23:10:37.022381	1	\N	\N	\N
113	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-10 23:10:50.103911	1	\N	\N	\N
114	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-10 23:11:24.945071	1	\N	\N	\N
115	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-10 23:14:07.140199	1	\N	\N	\N
116	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-10 23:14:56.559143	1	\N	\N	\N
117	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-11 16:26:43.225628	1	\N	\N	\N
118	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-11 16:26:58.857852	1	\N	\N	\N
119	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-12 13:58:57.313162	1	\N	\N	\N
120	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-12 14:05:04.696196	1	\N	\N	\N
121	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión el usuario María López	2026-09-12 14:05:53.553941	1	\N	\N	\N
122	4	INVENTARIO	INICIAR	11	Inició el inventario correspondiente a la fecha 2026-09-12	2026-09-12 14:08:36.933282	1	\N	\N	\N
123	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-12 14:09:08.024622	1	\N	\N	\N
124	3	AUTENTICACION	INICIAR_SESION	3	Inició sesión el usuario Roberto Díaz	2026-09-12 14:20:56.701972	1	\N	\N	\N
125	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión el usuario José Ríos	2026-09-12 14:21:03.762332	1	\N	\N	\N
126	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-12 14:24:24.285561	1	\N	\N	\N
127	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-19 09:56:29.949464	1	\N	\N	\N
128	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-19 18:49:55.649657	1	\N	\N	\N
129	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión el usuario Carlos Rodríguez	2026-09-19 19:30:29.339298	1	\N	\N	\N
130	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión con el perfil Administrador del sistema	2026-09-20 20:13:52.246568	1	1	\N	\N
131	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión con el perfil Administrador del sistema	2026-09-20 20:15:30.238116	1	1	\N	\N
132	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión con el perfil Administrador del sistema	2026-09-20 20:44:53.675703	1	1	\N	\N
133	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión con el perfil Administrador del sistema	2026-09-20 20:45:17.29664	1	1	\N	\N
134	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión con el perfil Administrador del sistema	2026-09-20 20:50:38.233595	1	1	\N	\N
135	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión con el perfil Administrador del sistema	2026-09-20 21:50:27.907568	1	1	\N	\N
136	1	USUARIOS	EDITAR	4	Actualizó un usuario y sus perfiles asignados	2026-09-20 21:52:02.195251	1	1	\N	\N
137	1	USUARIOS	EDITAR	1	Actualizó un usuario y sus perfiles asignados	2026-09-20 21:53:00.149494	1	1	\N	\N
138	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión con el perfil Administrador del sistema	2026-09-20 21:53:39.356472	1	1	1	\N
139	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión con el perfil Miembro de equipo	2026-09-20 21:53:58.772033	1	4	1	\N
140	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión con el perfil Administrador del sistema	2026-09-20 21:54:49.867737	1	1	1	\N
141	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión con el perfil Administrador del sistema	2026-09-21 11:22:49.138311	1	1	\N	\N
142	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Gerente	2026-09-21 11:22:52.07135	1	2	\N	\N
143	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Supervisor	2026-09-21 11:22:52.544219	1	3	\N	\N
144	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Miembro de equipo	2026-09-21 11:22:57.077133	1	4	1	\N
145	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Administrador del sistema	2026-09-21 11:23:11.804474	1	1	1	\N
146	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Miembro de equipo	2026-09-21 13:18:40.226315	1	4	1	\N
147	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Gerente	2026-09-21 13:18:42.914394	1	2	1	\N
148	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Administrador del sistema	2026-09-21 13:18:43.266602	1	1	\N	\N
149	1	USUARIOS	EDITAR	1	Actualizó un usuario y sus perfiles asignados	2026-09-21 13:18:51.395538	1	1	\N	\N
150	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Miembro de equipo	2026-09-21 13:19:00.641055	1	4	1	\N
151	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Miembro de equipo	2026-09-21 13:19:03.522098	1	4	3	\N
152	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Administrador del sistema	2026-09-21 13:19:04.621475	1	1	3	\N
153	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión automáticamente con el perfil Administrador del sistema	2026-09-21 13:25:27.602786	1	1	\N	\N
154	1	USUARIOS	EDITAR	2	Actualizó un usuario y sus perfiles asignados	2026-09-21 13:26:14.155984	1	1	\N	\N
155	1	USUARIOS	EDITAR	3	Actualizó un usuario y sus perfiles asignados	2026-09-21 13:26:38.537874	1	1	\N	\N
156	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión automáticamente con el perfil Administrador del sistema	2026-09-22 07:55:21.977307	1	1	\N	\N
157	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Gerente	2026-09-22 07:55:28.423797	1	2	\N	\N
158	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Supervisor	2026-09-22 07:55:29.060105	1	3	\N	\N
159	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Miembro de equipo	2026-09-22 07:55:32.876284	1	4	2	\N
160	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Miembro de equipo	2026-09-22 07:55:33.742633	1	4	3	\N
161	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Miembro de equipo	2026-09-22 07:55:35.514962	1	4	1	\N
162	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Administrador del sistema	2026-09-22 07:55:49.401528	1	1	1	\N
163	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión automáticamente con el perfil Administrador del sistema	2026-09-22 08:06:54.255178	1	1	\N	\N
164	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión automáticamente con el perfil Administrador del sistema	2026-09-22 08:07:16.173888	1	1	\N	\N
165	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Gerente	2026-09-22 10:55:28.035232	1	2	\N	\N
166	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Miembro de equipo	2026-09-22 10:55:35.608876	1	4	2	\N
167	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Supervisor	2026-09-22 10:55:43.461758	1	3	2	\N
168	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Gerente	2026-09-22 10:55:47.77504	1	2	\N	\N
169	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Administrador del sistema	2026-09-22 10:56:03.180362	1	1	\N	\N
170	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-22 12:42:56.007005	1	1	\N	3
171	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-22 12:43:01.111467	1	1	\N	1
172	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Santa Anita	2026-09-22 12:43:02.663329	1	1	\N	2
173	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Sheraton	2026-09-22 12:43:03.771463	1	1	\N	4
174	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Santa Anita	2026-09-22 12:43:06.079853	1	1	\N	2
175	4	AUTENTICACION	INICIAR_SESION	4	Inició sesión como Miembro de equipo en el local Miraflores	2026-09-22 12:43:33.250837	1	4	1	1
176	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión como Gerente en el local Miraflores	2026-09-22 12:44:45.241058	1	2	\N	1
177	2	AUTENTICACION	CAMBIAR_PERFIL	2	Cambió el perfil activo a Supervisor en el local Miraflores	2026-09-22 12:44:51.081656	1	3	\N	1
178	2	AUTENTICACION	CAMBIAR_PERFIL	2	Cambió el perfil activo a Miembro de equipo en el local Miraflores	2026-09-22 12:44:53.60326	1	4	1	1
179	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-22 12:45:38.732293	1	1	\N	3
180	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-22 12:45:46.14895	1	1	\N	1
181	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Barranco	2026-09-22 12:45:51.561893	1	1	\N	3
182	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-22 12:45:56.846135	1	1	\N	3
183	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-22 12:46:04.301679	1	1	\N	1
184	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Santa Anita	2026-09-22 12:46:08.132199	1	1	\N	2
185	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Sheraton	2026-09-22 12:46:11.222907	1	1	\N	4
186	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-22 13:47:26.240714	1	1	\N	3
187	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-22 13:47:51.885243	1	1	\N	3
188	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-22 13:50:10.068642	1	1	\N	1
189	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Santa Anita	2026-09-22 13:50:14.372283	1	1	\N	2
190	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-22 13:50:52.61751	1	1	\N	3
191	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-22 13:50:58.158769	1	1	\N	1
192	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Santa Anita	2026-09-22 13:51:03.734349	1	1	\N	2
193	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Sheraton	2026-09-22 13:51:06.879895	1	1	\N	4
194	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Barranco	2026-09-22 13:51:10.418877	1	1	\N	3
195	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-22 14:14:24.037663	1	1	\N	3
196	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-22 14:14:33.598804	1	1	\N	1
197	1	USUARIOS	EDITAR	2	Actualizó un usuario y sus perfiles asignados	2026-09-22 14:14:56.001113	1	1	\N	1
198	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-22 14:15:31.850269	1	1	\N	3
199	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-22 14:15:56.741155	1	1	\N	1
200	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión como Gerente en el local Miraflores	2026-09-22 14:16:30.984609	1	2	\N	1
201	2	AUTENTICACION	INICIAR_SESION	2	Inició sesión como Gerente en el local Miraflores	2026-09-22 14:17:24.726672	1	2	\N	1
202	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-22 14:22:28.144182	1	1	\N	3
203	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-22 15:08:01.38972	1	1	\N	3
204	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-22 15:54:52.319276	1	1	\N	3
205	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-22 16:29:09.760282	1	1	\N	1
206	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-22 17:02:20.398403	1	1	\N	3
207	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-22 18:32:31.935386	1	1	\N	3
208	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-22 21:33:42.671538	1	1	\N	3
209	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Gerente en el local Barranco	2026-09-22 21:36:58.645713	1	2	\N	3
210	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Supervisor en el local Barranco	2026-09-22 21:36:59.225313	1	3	\N	3
211	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Miembro de equipo en el local Barranco	2026-09-22 21:37:02.065899	1	4	2	3
212	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Miembro de equipo en el local Barranco	2026-09-22 21:37:03.855375	1	4	3	3
213	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Administrador del sistema en el local Barranco	2026-09-22 21:37:07.936052	1	1	3	3
214	1	PROMOCIONES	CREAR	4	CREAR: BARRA DE ALITAS	2026-09-22 21:40:56.99245	1	1	\N	3
215	1	CATALOGOS	ELIMINAR	4	Elimino promociones: BARRA DE ALITAS	2026-09-22 21:47:38.145305	1	1	\N	3
216	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-22 21:47:55.664802	1	1	\N	1
217	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Gerente en el local Miraflores	2026-09-22 21:48:27.115308	1	2	\N	1
218	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Administrador del sistema en el local Miraflores	2026-09-22 21:48:31.190718	1	1	\N	1
219	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Gerente en el local Miraflores	2026-09-22 22:06:12.253391	1	2	\N	1
220	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Supervisor en el local Miraflores	2026-09-22 22:06:13.286277	1	3	\N	1
221	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Administrador del sistema en el local Miraflores	2026-09-22 22:06:14.199571	1	1	\N	1
222	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Gerente en el local Miraflores	2026-09-22 22:06:16.382987	1	2	\N	1
275	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-23 14:09:03.79346	1	2	\N	1
223	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Supervisor en el local Miraflores	2026-09-22 22:06:18.553075	1	3	\N	1
224	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-23 07:21:33.253995	1	1	\N	3
225	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Miembro de equipo en el local Barranco	2026-09-23 07:21:46.356881	1	4	2	3
226	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Administrador del sistema en el local Barranco	2026-09-23 07:21:47.827995	1	1	2	3
227	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Gerente en el local Barranco	2026-09-23 07:21:48.844037	1	2	\N	3
228	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Administrador del sistema en el local Barranco	2026-09-23 07:21:50.68376	1	1	\N	3
229	1	USUARIOS	EDITAR	1	Actualizó un usuario y sus perfiles asignados	2026-09-23 07:22:14.892583	1	1	\N	3
230	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Miembro de equipo en el local Barranco	2026-09-23 07:25:08.997623	1	4	2	3
231	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Gerente en el local Barranco	2026-09-23 07:25:12.418335	1	2	2	3
232	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Administrador del sistema en el local Barranco	2026-09-23 07:27:58.481261	1	1	\N	3
233	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Supervisor en el local Barranco	2026-09-23 07:38:02.905169	1	3	\N	3
234	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Gerente en el local Barranco	2026-09-23 07:38:04.005215	1	2	\N	3
235	1	AUTENTICACION	CAMBIAR_PERFIL	1	Cambió el perfil activo a Administrador del sistema en el local Barranco	2026-09-23 07:38:06.789772	1	1	\N	3
236	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-23 07:42:24.797091	1	2	\N	1
237	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Barranco	2026-09-23 07:42:31.442413	1	2	\N	3
238	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Santa Anita	2026-09-23 07:42:32.998271	1	2	\N	2
239	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Sheraton	2026-09-23 07:42:34.356682	1	2	\N	4
240	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Santa Anita	2026-09-23 07:42:37.699353	1	2	\N	2
241	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Barranco	2026-09-23 07:42:40.789779	1	2	\N	3
242	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-23 07:42:43.921668	1	2	\N	1
243	1	SUBPRODUCTOS	EDITAR	8	EDITAR: SP-008 - Aros de cebolla (pequeño)	2026-09-23 08:04:06.120415	1	1	\N	\N
244	1	SUBPRODUCTOS	EDITAR	8	EDITAR: SP-008 - Aros de cebolla (pequeño)	2026-09-23 08:04:13.586172	1	1	\N	\N
245	1	LIMITES_STOCK	CONFIGURAR	107	Configuró los límites de stock de CV-007 en el local 1	2026-09-23 08:07:38.860395	1	2	\N	1
246	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-23 08:10:43.435474	1	1	\N	3
247	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-23 08:14:34.417833	1	1	\N	3
248	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-23 08:22:27.122149	1	1	\N	3
249	1	USUARIOS	EDITAR	1	Actualizó un usuario y sus perfiles asignados	2026-09-23 08:23:05.312809	1	1	\N	3
250	1	USUARIOS	EDITAR	2	Actualizó un usuario y sus perfiles asignados	2026-09-23 08:23:15.605701	1	1	\N	3
251	1	USUARIOS	EDITAR	4	Actualizó un usuario y sus perfiles asignados	2026-09-23 08:23:24.974784	1	1	\N	3
252	1	SALON	ENVIAR_PEDIDO	1	Envió pedido de B01: 3 productos	2026-09-23 11:14:16.230489	1	4	\N	1
253	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-23 11:16:51.51218	1	1	\N	3
254	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Sheraton	2026-09-23 11:16:56.150175	1	2	\N	4
255	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Santa Anita	2026-09-23 11:16:57.496564	1	2	\N	2
256	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-23 11:16:58.475785	1	2	\N	1
257	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-23 11:44:13.191561	1	1	\N	3
258	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-23 11:44:30.325275	1	2	\N	1
259	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-23 11:45:18.573547	1	1	\N	3
260	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-23 11:45:25.329512	1	2	\N	1
261	1	SALON	EDITAR_DISTRIBUCION	1	Actualizo la distribucion del salon	2026-09-23 11:48:29.168966	1	2	\N	1
262	1	SALON	ENVIAR_PEDIDO	2	Envió pedido de B01: 1 productos	2026-09-23 12:31:23.89411	1	2	\N	1
263	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-23 12:31:32.786085	1	1	\N	3
264	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-23 12:31:51.979419	1	2	\N	1
265	1	LIMITES_STOCK	CONFIGURAR	107	Configuró los límites de stock de CV-007 en el local 1	2026-09-23 12:32:07.930971	1	2	\N	1
266	1	LIMITES_STOCK	CONFIGURAR	109	Configuró los límites de stock de CV-009 en el local 1	2026-09-23 12:32:12.975256	1	2	\N	1
267	1	SALON	ENVIAR_PEDIDO	3	Envió pedido de B01: 1 productos	2026-09-23 13:54:12.910396	1	2	\N	1
268	1	SALON	MOVER	1	Traslado B01 a M01; responsable 1	2026-09-23 13:54:37.090323	1	2	\N	1
269	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-23 13:55:30.229076	1	1	\N	3
270	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-23 14:08:47.375268	1	2	\N	1
271	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Santa Anita	2026-09-23 14:08:48.263266	1	2	\N	2
272	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Sheraton	2026-09-23 14:08:49.734067	1	2	\N	4
273	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-23 14:08:53.36673	1	3	\N	1
274	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Santa Anita	2026-09-23 14:08:54.273145	1	3	\N	2
276	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Santa Anita	2026-09-23 14:09:09.893655	1	3	\N	2
277	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-23 14:22:45.129775	1	2	\N	1
278	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-23 19:20:56.974277	1	1	\N	3
279	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-23 19:54:57.235835	1	1	\N	3
280	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-23 22:59:59.352232	1	1	\N	3
281	1	SALON	ENVIAR_PEDIDO	4	Envió pedido de M01: 2 productos	2026-09-23 23:03:36.895855	1	2	\N	1
282	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-23 23:19:13.836468	1	1	\N	3
283	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-25 13:26:24.755526	1	1	\N	3
284	1	SALON	ENVIAR_PEDIDO	5	Envió pedido de M01: 2 productos	2026-09-25 13:29:00.70023	1	2	\N	1
285	1	SALON	ELIMINAR	1	Elimino de M01: 2 x Agua con Gas · 1.000 UNI	2026-09-25 13:29:19.157252	1	2	\N	1
286	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-25 13:29:39.910824	1	1	\N	3
287	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-25 13:30:12.727401	1	2	\N	1
288	1	USUARIOS	EDITAR	1	Actualizó un usuario y sus perfiles asignados	2026-09-25 13:32:08.45004	1	1	\N	1
289	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-26 04:15:04.48817	1	1	\N	3
290	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-26 04:15:51.211516	1	1	\N	3
291	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-26 05:17:40.450045	1	1	\N	3
292	1	SALON	COBRAR_MESA	1	Cobró M01: S/ 275.00, TARJETA, comprobante interno INT-00000001	2026-09-26 05:19:00.212438	1	2	\N	1
293	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-26 11:55:39.206392	1	1	\N	3
294	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-26 13:53:58.402978	1	1	\N	3
295	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-26 13:54:11.842531	1	2	\N	1
296	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-27 13:20:42.595949	1	1	\N	3
297	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Santa Anita	2026-09-27 13:20:55.797139	1	2	\N	2
298	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-27 13:20:57.272184	1	2	\N	1
299	1	INVENTARIO_OPERATIVO	CERRAR_DIA	1	Cerró el día operativo 2026-09-26	2026-09-27 13:21:18.994564	1	2	\N	1
300	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-28 11:42:57.736024	1	1	\N	3
301	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-28 11:43:12.328108	1	4	2	1
302	1	INVENTARIO_OPERATIVO	ABRIR_DIA	5	Abrió o consultó la jornada operativa	2026-09-28 11:44:35.822296	1	2	\N	1
303	1	INVENTARIO_OPERATIVO	CERRAR_DIA	5	Cerró el día operativo 2026-09-28	2026-09-28 18:49:24.201062	1	2	\N	1
304	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-28 18:49:43.513958	1	1	\N	3
305	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-28 18:49:48.614858	1	2	\N	1
306	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-28 18:50:28.136412	1	1	\N	3
307	1	INVENTARIO_OPERATIVO	ASIGNAR_PUESTOS	3	Actualizó la asignación por puesto de 11 productos	2026-09-28 18:51:48.754401	1	2	\N	3
308	1	INVENTARIO_OPERATIVO	CERRAR_DIA	3	Cerró el día operativo 2026-09-26	2026-09-28 20:45:55.952331	1	2	\N	3
309	1	INVENTARIO_OPERATIVO	ABRIR_DIA	6	Abrió o consultó la jornada operativa	2026-09-28 20:45:59.603353	1	2	\N	3
310	1	INVENTARIO_OPERATIVO	CERRAR_DIA	6	Cerró el día operativo 2026-09-28	2026-09-28 20:46:02.350016	1	2	\N	3
311	1	INVENTARIO_OPERATIVO	ABRIR_DIA	7	Abrió o consultó la jornada operativa	2026-09-28 20:46:04.451244	1	2	\N	3
312	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-28 20:46:29.582588	1	2	\N	1
313	1	SALON	COBRO_PRUEBA	2	DEMO-MIRAFLORES-20260928 · fecha simulada 2026-09-29	2026-09-28 20:51:28.655069	1	2	\N	1
314	1	SALON	COBRO_PRUEBA	3	DEMO-MIRAFLORES-20260928 · fecha simulada 2026-09-29	2026-09-28 20:51:28.655069	1	2	\N	1
315	1	INVENTARIO_OPERATIVO	CIERRE_PRUEBA	8	DEMO-MIRAFLORES-20260928 · fecha simulada 2026-09-29	2026-09-28 20:51:28.655069	1	2	\N	1
316	1	SALON	COBRO_PRUEBA	4	DEMO-MIRAFLORES-20260928 · fecha simulada 2026-09-30	2026-09-28 20:51:28.655069	1	2	\N	1
317	1	SALON	COBRO_PRUEBA	5	DEMO-MIRAFLORES-20260928 · fecha simulada 2026-09-30	2026-09-28 20:51:28.655069	1	2	\N	1
318	1	INVENTARIO_OPERATIVO	CIERRE_PRUEBA	9	DEMO-MIRAFLORES-20260928 · fecha simulada 2026-09-30	2026-09-28 20:51:28.655069	1	2	\N	1
319	1	SALON	COBRO_PRUEBA	6	DEMO-MIRAFLORES-20260928 · fecha simulada 2026-10-01	2026-09-28 20:51:28.655069	1	2	\N	1
320	1	SALON	COBRO_PRUEBA	7	DEMO-MIRAFLORES-20260928 · fecha simulada 2026-10-01	2026-09-28 20:51:28.655069	1	2	\N	1
321	1	INVENTARIO_OPERATIVO	CIERRE_PRUEBA	10	DEMO-MIRAFLORES-20260928 · fecha simulada 2026-10-01	2026-09-28 20:51:28.655069	1	2	\N	1
322	1	SALON	COBRO_PRUEBA	8	DEMO-MIRAFLORES-20260928 · fecha simulada 2026-10-02	2026-09-28 20:51:28.655069	1	2	\N	1
323	1	SALON	COBRO_PRUEBA	9	DEMO-MIRAFLORES-20260928 · fecha simulada 2026-10-02	2026-09-28 20:51:28.655069	1	2	\N	1
324	1	INVENTARIO_OPERATIVO	CIERRE_PRUEBA	11	DEMO-MIRAFLORES-20260928 · fecha simulada 2026-10-02	2026-09-28 20:51:28.655069	1	2	\N	1
325	1	SALON	COBRO_PRUEBA	10	DEMO-MIRAFLORES-20260928 · fecha simulada 2026-10-03	2026-09-28 20:51:28.655069	1	2	\N	1
326	1	SALON	COBRO_PRUEBA	11	DEMO-MIRAFLORES-20260928 · fecha simulada 2026-10-03	2026-09-28 20:51:28.655069	1	2	\N	1
327	1	INVENTARIO_OPERATIVO	CIERRE_PRUEBA	12	DEMO-MIRAFLORES-20260928 · fecha simulada 2026-10-03	2026-09-28 20:51:28.655069	1	2	\N	1
328	1	INVENTARIO_OPERATIVO	CARGAR_DEMO	1	DEMO-MIRAFLORES-20260928	2026-09-28 20:51:28.655069	1	2	\N	1
329	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-28 20:52:52.830137	1	1	\N	3
330	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-28 20:53:50.545145	1	2	\N	1
331	4	INVENTARIO_OPERATIVO	CONTEO_PRUEBA	1	PRUEBA - Conteo entregado por el equipo de Miraflores - entrega simulada, no es un conteo físico real	2026-09-28 21:00:09.649426	1	4	1	1
332	3	INVENTARIO_OPERATIVO	CONTEO_PRUEBA	1	PRUEBA - Conteo entregado por el equipo de Miraflores - entrega simulada, no es un conteo físico real	2026-09-28 21:00:09.649426	1	4	2	1
333	2	INVENTARIO_OPERATIVO	CONTEO_PRUEBA	1	PRUEBA - Conteo entregado por el equipo de Miraflores - entrega simulada, no es un conteo físico real	2026-09-28 21:00:09.649426	1	4	3	1
334	1	INVENTARIO_OPERATIVO	FINALIZAR_CONTEO	1	Finalizó la revisión del conteo físico sin ajustar stock	2026-09-28 21:10:21.838428	1	2	\N	1
335	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-28 22:44:58.604963	1	1	\N	3
336	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-28 23:24:30.429973	1	1	\N	3
337	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-28 23:24:53.825191	1	2	\N	1
338	1	CATALOGOS	CREAR	10	Creó el proveedor Florcita S.A.C.	2026-09-28 23:32:25.358555	1	1	\N	\N
339	1	CATALOGOS	ELIMINAR	10	Elimino proveedores: Florcita S.A.C.	2026-09-28 23:34:17.7294	1	1	\N	\N
340	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-28 23:37:37.23027	1	1	\N	3
341	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-09-28 23:37:53.598148	1	2	\N	1
342	1	SALON	ENVIAR_PEDIDO	16	Envió pedido de M01: 5 productos	2026-09-29 00:02:22.590407	1	2	\N	1
343	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-29 00:02:31.188246	1	1	\N	3
344	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-09-30 17:43:06.780575	1	1	\N	3
345	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-10-03 16:51:10.264599	1	1	\N	3
346	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-10-03 17:00:32.252439	1	2	\N	1
347	1	INVENTARIO_OPERATIVO	ABRIR_DIA	13	Abrió o consultó la jornada operativa	2026-10-03 17:06:20.663424	1	2	\N	1
348	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-10-03 17:08:54.414044	1	1	\N	3
349	1	CATALOGOS	CREAR	10	Creó la categoría ABARROTES	2026-10-03 17:10:11.300518	1	1	\N	\N
350	1	CATALOGOS	CREAR	11	Creó el proveedor PEPITO	2026-10-03 17:10:35.502937	1	1	\N	\N
351	1	CATALOGOS	CREAR	141	Creó el producto AB-001 - ATUN	2026-10-03 17:20:29.035524	1	1	\N	\N
352	1	CATALOGOS	ELIMINAR	141	Elimino productos: ATUN	2026-10-03 17:20:35.159676	1	1	\N	\N
353	1	CATALOGOS	ELIMINAR	10	Elimino categorias-productos: ABARROTES	2026-10-03 17:20:43.226065	1	1	\N	\N
354	1	CATALOGOS	ELIMINAR	11	Elimino proveedores: PEPITO	2026-10-03 17:20:47.86933	1	1	\N	\N
355	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-10-03 17:25:12.772081	1	2	\N	1
356	1	RECEPCION_PRODUCTOS	CORREGIR	7	Corrigió la factura FAC-20260830-007 de la orden OC-001. Motivo: PRODUCTO_DANADO. Observación: PRODUCTO GOLPEADO	2026-10-03 17:31:13.519013	1	2	\N	1
357	1	RECEPCION_PRODUCTOS	CREAR	10	Registró la factura FAC-20260830-010 para la orden OC-001	2026-10-03 17:31:43.73928	1	2	\N	1
358	1	ORDEN_COMPRA	CREAR	2	Registró la orden OC-002 en estado ENVIADA	2026-10-03 17:32:28.727503	1	2	\N	1
359	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-10-03 19:02:30.827098	1	1	\N	3
360	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-10-03 19:15:20.257339	1	1	\N	3
361	1	LIMITES_STOCK	CONFIGURAR	107	Configuró los límites de stock de CV-007 en el local 3	2026-10-03 19:16:40.782831	1	2	\N	3
362	1	CATALOGOS	CREAR	12	Creó el proveedor pepito	2026-10-03 19:20:04.249206	1	1	\N	\N
363	1	CATALOGOS	EDITAR	12	Editó el proveedor pepito	2026-10-03 19:20:14.154742	1	1	\N	\N
364	1	CATALOGOS	CREAR	11	Creó la categoría ABARROTE	2026-10-03 19:21:11.901667	1	1	\N	\N
365	1	CATALOGOS	CREAR	142	Creó el producto AB-001 - ATUN	2026-10-03 19:21:37.805264	1	1	\N	\N
366	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-10-03 19:23:24.453846	1	2	\N	1
367	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Santa Anita	2026-10-03 19:23:28.650463	1	2	\N	2
368	1	AUTENTICACION	CAMBIAR_LOCAL	1	Cambió el local activo a Miraflores	2026-10-03 19:24:20.431651	1	2	\N	1
369	1	SALON	ENVIAR_PEDIDO	17	Envió pedido de M01: 3 productos	2026-10-03 19:25:14.760129	1	2	\N	1
370	1	SALON	COBRAR_MESA	12	Cobró M01: S/ 236.00, EFECTIVO, comprobante interno INT-00000012	2026-10-03 19:25:24.264139	1	2	\N	1
371	1	SALON	ENVIAR_PEDIDO	18	Envió pedido de M04: 5 productos	2026-10-03 19:25:58.796537	1	2	\N	3
372	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-10-10 06:31:39.189984	1	1	\N	3
373	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-10-10 07:49:54.092766	1	1	\N	3
374	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-10-10 07:53:34.369668	1	1	\N	3
375	1	CATALOGOS	EDITAR	12	Editó el proveedor pepito	2026-10-10 15:52:43.740912	1	1	\N	\N
376	1	CATALOGOS	ELIMINAR	142	Elimino productos: ATUN	2026-10-10 15:53:21.215285	1	1	\N	\N
377	1	AUTENTICACION	INICIAR_SESION	1	Inició sesión como Administrador del sistema en el local Barranco	2026-10-10 15:53:56.422597	1	1	\N	3
378	1	CATALOGOS	CREAR	143	Creó el producto AB-002 - atún	2026-10-10 15:54:39.432716	1	1	\N	\N
\.


--
-- Data for Name: asistente_ia_borrador; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.asistente_ia_borrador (id, id_usuario, id_perfil, id_local, plan, estado, resultado, creado_en, vence_en) FROM stdin;
e2baf60f-dc85-4d8d-93d0-a29dcc1ca4cb	1	1	1	{"id": null, "datos": {"nombre": "Florcita S.A.C."}, "accion": "crear", "recurso": "proveedores", "anterior": null}	REALIZADO	{"mensaje": "Proveedor creado correctamente", "id_proveedor": 10}	2026-09-28 23:32:12.212018-05	2026-09-28 23:52:12.212018-05
\.


--
-- Data for Name: auditoria_cambio; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditoria_cambio (id_auditoria_cambio, id_usuario, modulo, accion, tabla_afectada, id_registro_afectado, datos_anteriores, datos_nuevos, motivo, fecha_cambio, id_perfil_utilizado, id_puesto_laboral, id_local) FROM stdin;
1	1	PROMOCIONES	CREAR	promocion	4	\N	{"grupos": [{"id": 4, "elegir": 1, "repetir": true, "opciones": [80]}], "promocion": {"activo": true, "codigo": "P-004", "nombre": "BARRA DE ALITAS", "precio": "39.90", "hora_fin": null, "hora_inicio": null, "id_promocion": 4}}	\N	2026-09-22 21:40:56.99245	1	\N	3
2	1	CATALOGOS	ELIMINAR	promocion	4	{"detalles": {"promocion_grupo": [{"id_promocion": 4, "cantidad_elegir": 1, "permite_repetir": true, "id_promocion_grupo": 4}], "promocion_opcion": [{"id_promocion_grupo": 4, "id_promocion_opcion": 9, "id_presentacion_venta": 80}]}, "registro": {"activo": true, "codigo": "P-004", "nombre": "BARRA DE ALITAS", "precio": "39.90", "hora_fin": null, "hora_inicio": null, "id_promocion": 4}}	\N	\N	2026-09-22 21:47:38.145305	1	\N	3
3	1	SUBPRODUCTOS	EDITAR	subproducto	8	{"activo": true, "codigo": "SP-008", "nombre": "Aros de cebolla (pequeño)", "unidad": "PORCIÓN", "instruccion": null, "rendimiento": "1.000", "ingredientes": [{"unidad": "UNI", "cantidad": "5.000", "id_producto": 61}], "id_subproducto": 8}	{"id": 8, "activo": true, "codigo": "SP-008", "nombre": "Aros de cebolla (pequeño)", "unidad": "PORCIÓN", "instruccion": "sdsss", "rendimiento": "1", "ingredientes": [{"id": 61, "unidad": "UNI", "cantidad": "5", "tipo_componente": "PRODUCTO"}]}	\N	2026-09-23 08:04:06.120415	1	\N	\N
4	1	SUBPRODUCTOS	EDITAR	subproducto	8	{"activo": true, "codigo": "SP-008", "nombre": "Aros de cebolla (pequeño)", "unidad": "PORCIÓN", "instruccion": "sdsss", "rendimiento": "1.000", "ingredientes": [{"unidad": "UNI", "cantidad": "5.000", "id_producto": 61}], "id_subproducto": 8}	{"id": 8, "activo": true, "codigo": "SP-008", "nombre": "Aros de cebolla (pequeño)", "unidad": "PORCIÓN", "instruccion": "", "rendimiento": "1", "ingredientes": [{"id": 61, "unidad": "UNI", "cantidad": "5", "tipo_componente": "PRODUCTO"}]}	\N	2026-09-23 08:04:13.586172	1	\N	\N
5	1	LIMITES_STOCK	CONFIGURAR	producto_stock_local	107	{"id_local": 1, "stock_maximo": null, "stock_minimo": "5.000"}	{"id_local": 1, "stock_maximo": "30", "stock_minimo": "5"}	\N	2026-09-23 08:07:38.860395	2	\N	1
6	1	LIMITES_STOCK	CONFIGURAR	producto_stock_local	107	{"id_local": 1, "stock_maximo": "30.000", "stock_minimo": "5.000"}	{"id_local": 1, "stock_maximo": "100", "stock_minimo": "5"}	\N	2026-09-23 12:32:07.930971	2	\N	1
7	1	LIMITES_STOCK	CONFIGURAR	producto_stock_local	109	{"id_local": 1, "stock_maximo": null, "stock_minimo": "5.000"}	{"id_local": 1, "stock_maximo": "100", "stock_minimo": "5"}	\N	2026-09-23 12:32:12.975256	2	\N	1
8	1	INVENTARIO_OPERATIVO	ASIGNAR_PUESTOS	inventario_asignacion_puesto	3	[]	{"productos": [64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74], "id_puesto_laboral": 3}	\N	2026-09-28 18:51:48.754401	2	\N	3
9	1	CATALOGOS	CREAR	proveedor	10	\N	{"activo": true, "nombre": "Florcita S.A.C.", "id_proveedor": 10}	\N	2026-09-28 23:32:25.358555	1	\N	\N
10	1	CATALOGOS	ELIMINAR	proveedor	10	{"detalles": {}, "registro": {"activo": true, "nombre": "Florcita S.A.C.", "id_proveedor": 10}}	\N	\N	2026-09-28 23:34:17.7294	1	\N	\N
11	1	CATALOGOS	CREAR	categoria_producto	10	\N	{"activo": true, "nombre": "ABARROTES", "prefijo": "AB", "id_categoria": 10, "siguiente_numero": 1}	\N	2026-10-03 17:10:11.300518	1	\N	\N
12	1	CATALOGOS	CREAR	proveedor	11	\N	{"activo": true, "nombre": "PEPITO", "id_proveedor": 11}	\N	2026-10-03 17:10:35.502937	1	\N	\N
13	1	CATALOGOS	CREAR	producto	141	\N	{"activo": true, "codigo": "AB-001", "nombre": "ATUN", "unidad": "UNI", "id_producto": 141, "id_categoria": 10, "id_proveedor": 11, "presentacion": "6.000", "stock_minimo": "0.000"}	\N	2026-10-03 17:20:29.035524	1	\N	\N
14	1	CATALOGOS	ELIMINAR	producto	141	{"detalles": {"producto_stock_local": []}, "registro": {"activo": true, "codigo": "AB-001", "nombre": "ATUN", "unidad": "UNI", "id_producto": 141, "id_categoria": 10, "id_proveedor": 11, "presentacion": "6.000", "stock_minimo": "0.000"}}	\N	\N	2026-10-03 17:20:35.159676	1	\N	\N
15	1	CATALOGOS	ELIMINAR	categoria_producto	10	{"detalles": {}, "registro": {"activo": true, "nombre": "ABARROTES", "prefijo": "AB", "id_categoria": 10, "siguiente_numero": 2}}	\N	\N	2026-10-03 17:20:43.226065	1	\N	\N
16	1	CATALOGOS	ELIMINAR	proveedor	11	{"detalles": {}, "registro": {"activo": true, "nombre": "PEPITO", "id_proveedor": 11}}	\N	\N	2026-10-03 17:20:47.86933	1	\N	\N
17	1	LIMITES_STOCK	CONFIGURAR	producto_stock_local	107	{"id_local": 3, "stock_maximo": null, "stock_minimo": "5.000"}	{"id_local": 3, "stock_maximo": "10", "stock_minimo": "10"}	\N	2026-10-03 19:16:40.782831	2	\N	3
18	1	CATALOGOS	CREAR	proveedor	12	\N	{"activo": true, "nombre": "pepito", "id_proveedor": 12}	\N	2026-10-03 19:20:04.249206	1	\N	\N
19	1	CATALOGOS	EDITAR	proveedor	12	{"activo": true, "nombre": "pepito", "id_proveedor": 12}	{"activo": true, "nombre": "pepito", "id_proveedor": 12}	\N	2026-10-03 19:20:14.154742	1	\N	\N
20	1	CATALOGOS	CREAR	categoria_producto	11	\N	{"activo": true, "nombre": "ABARROTE", "prefijo": "AB", "id_categoria": 11, "siguiente_numero": 1}	\N	2026-10-03 19:21:11.901667	1	\N	\N
21	1	CATALOGOS	CREAR	producto	142	\N	{"activo": true, "codigo": "AB-001", "nombre": "ATUN", "unidad": "UNI", "id_producto": 142, "id_categoria": 11, "id_proveedor": 12, "presentacion": "6.000", "stock_minimo": "0.000"}	\N	2026-10-03 19:21:37.805264	1	\N	\N
22	1	CATALOGOS	EDITAR	proveedor	12	{"activo": true, "nombre": "pepito", "id_proveedor": 12, "ids_categorias": [11]}	{"activo": true, "nombre": "pepito", "id_proveedor": 12, "ids_categorias": [11]}	\N	2026-10-10 15:52:43.740912	1	\N	\N
23	1	CATALOGOS	ELIMINAR	producto	142	{"detalles": {"producto_stock_local": []}, "registro": {"activo": true, "codigo": "AB-001", "nombre": "ATUN", "unidad": "C62", "id_producto": 142, "id_categoria": 11, "id_proveedor": 12, "presentacion": "6.000", "stock_minimo": "0.000"}}	\N	\N	2026-10-10 15:53:21.215285	1	\N	\N
24	1	CATALOGOS	CREAR	producto	143	\N	{"activo": true, "codigo": "AB-002", "nombre": "atún", "unidad": "C62", "id_producto": 143, "id_categoria": 11, "id_proveedor": 12, "presentacion": "6.000", "stock_minimo": "0.000"}	\N	2026-10-10 15:54:39.432716	1	\N	\N
\.


--
-- Data for Name: categoria_carta; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.categoria_carta (id_categoria_carta, nombre, prefijo, siguiente_numero, activo) FROM stdin;
1	Cócteles	CT	34	t
2	Botellas locales	BL	6	t
3	Botellas importadas	BI	9	t
4	Sin alcohol	SA	15	t
5	Entradas	ET	22	t
6	Platos	PL	19	t
7	Cerveza de barril	CB	35	t
8	Extras	EX	1	t
\.


--
-- Data for Name: categoria_producto; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.categoria_producto (id_categoria, nombre, prefijo, siguiente_numero, activo) FROM stdin;
1	Vegetales	V	11	t
2	Secos	S	28	t
3	Salsas	SS	15	t
4	Lácteos	L	8	t
5	Producción	PR	7	t
6	Carnes	C	12	t
7	Botellas	B	16	t
8	Tragos	T	12	t
9	Cervecera	CV	40	t
11	ABARROTE	AB	3	t
\.


--
-- Data for Name: factura_recepcion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.factura_recepcion (id_factura_recepcion, id_orden_compra, id_proveedor, numero_factura, fecha_recepcion, usuario_recepcion) FROM stdin;
1	1	1	FAC-20260830-001	2026-08-30	2
2	1	2	FAC-20260830-002	2026-08-30	2
3	1	3	FAC-20260830-003	2026-08-30	2
4	1	4	FAC-20260830-004	2026-08-30	2
5	1	5	FAC-20260830-005	2026-08-30	2
6	1	6	FAC-20260830-006	2026-08-30	2
8	1	8	FAC-20260830-008	2026-08-30	2
9	1	9	FAC-20260830-009	2026-08-30	2
7	1	7	FAC-20260830-007	2026-08-30	2
10	1	7	FAC-20260830-010	2026-10-03	1
\.


--
-- Data for Name: factura_recepcion_detalle; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.factura_recepcion_detalle (id_factura_recepcion_detalle, id_factura_recepcion, id_producto, cantidad_recibida) FROM stdin;
1	1	1	20.000
2	1	2	20.000
3	1	3	20.000
4	1	4	20.000
5	1	5	20.000
6	1	6	20.000
7	1	7	20.000
8	1	8	20.000
9	1	9	20.000
10	1	10	20.000
11	2	11	20.000
12	2	12	20.000
13	2	13	20.000
14	2	14	24.000
15	2	15	20.000
16	2	16	20.000
17	2	17	20.000
18	2	18	24.000
19	2	19	20.000
20	2	20	20.000
21	2	21	20.000
22	2	22	24.000
23	2	23	20.000
24	2	24	20.000
25	2	25	20.000
26	2	26	20.000
27	2	27	20.000
28	2	28	20.000
29	2	29	24.000
30	2	30	24.000
31	2	31	24.000
32	2	32	24.000
33	2	33	24.000
34	2	34	24.000
35	2	35	24.000
36	2	36	24.000
37	3	37	20.000
38	3	38	20.000
39	3	39	20.000
40	3	40	20.000
41	3	41	20.000
42	3	42	20.000
43	3	43	20.000
44	3	44	20.000
45	3	45	20.000
46	3	46	20.000
47	3	47	20.000
48	3	48	20.000
49	3	49	20.000
50	3	50	20.000
51	4	51	20.000
52	4	52	20.000
53	4	53	20.000
54	4	54	20.000
55	4	55	20.000
56	4	56	20.000
57	4	57	20.000
58	5	58	24.000
59	5	59	24.000
60	5	60	24.000
61	5	61	24.000
62	5	62	20.000
63	5	63	20.000
64	6	64	20.000
65	6	65	20.000
66	6	66	20.000
67	6	67	20.000
68	6	68	20.000
69	6	69	20.000
70	6	70	20.000
71	6	71	20.000
72	6	72	24.000
73	6	73	20.000
74	6	74	20.000
75	7	75	24.000
76	7	76	24.000
77	7	77	30.000
78	7	78	30.000
79	7	79	30.000
80	7	80	30.000
81	7	81	30.000
82	7	82	30.000
83	7	83	24.000
85	7	85	24.000
86	7	86	24.000
87	7	87	24.000
88	7	88	24.000
89	7	89	24.000
90	8	90	20.300
91	8	91	20.300
92	8	92	20.300
93	8	93	20.300
94	8	94	20.000
95	8	95	20.300
96	8	96	20.300
97	8	97	20.300
98	8	98	20.300
99	8	99	20.300
100	8	100	20.400
101	9	101	30.000
102	9	102	30.000
103	9	103	30.000
104	9	104	30.000
105	9	105	30.000
106	9	106	30.000
107	9	107	30.000
108	9	108	30.000
109	9	109	30.000
110	9	110	30.000
111	9	111	30.000
112	9	112	30.000
113	9	113	30.000
114	9	114	30.000
115	9	115	30.000
116	9	116	30.000
117	9	117	30.000
118	9	118	30.000
119	9	119	30.000
120	9	120	30.000
121	9	121	30.000
122	9	122	30.000
123	9	123	30.000
124	9	124	30.000
125	9	125	30.000
126	9	126	30.000
127	9	127	30.000
128	9	128	30.000
129	9	129	30.000
130	9	130	30.000
131	9	131	30.000
132	9	132	30.000
133	9	133	30.000
134	9	134	30.000
135	9	135	24.000
136	9	136	24.000
137	9	137	24.000
138	9	138	24.000
139	9	139	24.000
140	2	140	24.000
84	7	84	12.000
141	10	84	12.000
\.


--
-- Data for Name: factura_recepcion_detalle_historial; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.factura_recepcion_detalle_historial (id_factura_recepcion_detalle_historial, id_factura_recepcion_historial, id_producto, cantidad_anterior, cantidad_nueva) FROM stdin;
1	1	84	24.000	12.000
\.


--
-- Data for Name: factura_recepcion_historial; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.factura_recepcion_historial (id_factura_recepcion_historial, id_factura_recepcion, numero_factura_anterior, numero_factura_nuevo, fecha_recepcion_anterior, fecha_recepcion_nueva, usuario_correccion, motivo_correccion, observacion, fecha_correccion) FROM stdin;
1	7	FAC-20260830-007	FAC-20260830-007	2026-08-30	2026-08-30	1	PRODUCTO_DANADO	PRODUCTO GOLPEADO	2026-10-03 17:31:13.519013
\.


--
-- Data for Name: grupo_salsa; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.grupo_salsa (id_grupo_salsa, id_presentacion_venta, cantidad_maxima, permite_repetir, activo) FROM stdin;
1	74	1	f	t
2	76	2	t	t
3	77	2	t	t
4	78	2	t	t
5	79	1	f	t
6	80	1	f	t
7	81	1	f	t
\.


--
-- Data for Name: grupo_salsa_opcion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.grupo_salsa_opcion (id_grupo_salsa_opcion, id_grupo_salsa, id_producto, cantidad, unidad, activo) FROM stdin;
1	1	38	0.060	KGM	t
2	1	39	0.060	KGM	t
3	1	40	0.060	KGM	t
4	1	41	0.060	KGM	t
5	1	42	0.060	KGM	t
6	2	38	0.060	KGM	t
7	2	39	0.060	KGM	t
8	2	40	0.060	KGM	t
9	2	41	0.060	KGM	t
10	2	42	0.060	KGM	t
11	3	38	0.060	KGM	t
12	3	39	0.060	KGM	t
13	3	40	0.060	KGM	t
14	3	41	0.060	KGM	t
15	3	42	0.060	KGM	t
16	4	38	0.060	KGM	t
17	4	39	0.060	KGM	t
18	4	40	0.060	KGM	t
19	4	41	0.060	KGM	t
20	4	42	0.060	KGM	t
21	5	38	0.060	KGM	t
22	5	39	0.060	KGM	t
23	5	40	0.060	KGM	t
24	5	41	0.060	KGM	t
25	5	42	0.060	KGM	t
26	6	38	0.060	KGM	t
27	6	39	0.060	KGM	t
28	6	40	0.060	KGM	t
29	6	41	0.060	KGM	t
30	6	42	0.060	KGM	t
31	7	38	0.060	KGM	t
32	7	39	0.060	KGM	t
33	7	40	0.060	KGM	t
34	7	41	0.060	KGM	t
35	7	42	0.060	KGM	t
\.


--
-- Data for Name: inventario_asignacion_puesto; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventario_asignacion_puesto (id_local, id_producto, id_puesto_laboral, actualizado_por, actualizado_en) FROM stdin;
3	64	3	1	2026-09-28 18:51:48.785728-05
3	65	3	1	2026-09-28 18:51:48.78644-05
3	66	3	1	2026-09-28 18:51:48.786467-05
3	67	3	1	2026-09-28 18:51:48.786485-05
3	68	3	1	2026-09-28 18:51:48.78649-05
3	69	3	1	2026-09-28 18:51:48.786498-05
3	70	3	1	2026-09-28 18:51:48.786512-05
3	71	3	1	2026-09-28 18:51:48.78652-05
3	72	3	1	2026-09-28 18:51:48.786528-05
3	73	3	1	2026-09-28 18:51:48.786536-05
3	74	3	1	2026-09-28 18:51:48.786544-05
1	1	3	1	2026-09-28 20:51:28.686917-05
1	2	3	1	2026-09-28 20:51:28.688778-05
1	3	3	1	2026-09-28 20:51:28.689732-05
1	4	3	1	2026-09-28 20:51:28.690812-05
1	5	3	1	2026-09-28 20:51:28.691869-05
1	6	3	1	2026-09-28 20:51:28.692494-05
1	7	3	1	2026-09-28 20:51:28.693295-05
1	8	3	1	2026-09-28 20:51:28.694184-05
1	9	3	1	2026-09-28 20:51:28.694718-05
1	10	3	1	2026-09-28 20:51:28.695215-05
1	11	3	1	2026-09-28 20:51:28.695759-05
1	12	3	1	2026-09-28 20:51:28.696262-05
1	13	3	1	2026-09-28 20:51:28.697032-05
1	14	3	1	2026-09-28 20:51:28.697809-05
1	15	3	1	2026-09-28 20:51:28.698241-05
1	16	3	1	2026-09-28 20:51:28.698537-05
1	17	3	1	2026-09-28 20:51:28.698781-05
1	18	3	1	2026-09-28 20:51:28.699163-05
1	19	3	1	2026-09-28 20:51:28.699614-05
1	20	3	1	2026-09-28 20:51:28.700026-05
1	21	3	1	2026-09-28 20:51:28.700449-05
1	22	3	1	2026-09-28 20:51:28.700693-05
1	23	3	1	2026-09-28 20:51:28.700914-05
1	24	3	1	2026-09-28 20:51:28.701138-05
1	25	3	1	2026-09-28 20:51:28.701373-05
1	26	3	1	2026-09-28 20:51:28.701594-05
1	27	3	1	2026-09-28 20:51:28.701812-05
1	28	3	1	2026-09-28 20:51:28.702053-05
1	29	3	1	2026-09-28 20:51:28.702428-05
1	30	3	1	2026-09-28 20:51:28.702762-05
1	31	3	1	2026-09-28 20:51:28.703088-05
1	32	3	1	2026-09-28 20:51:28.703517-05
1	33	3	1	2026-09-28 20:51:28.704212-05
1	34	3	1	2026-09-28 20:51:28.705164-05
1	35	3	1	2026-09-28 20:51:28.705527-05
1	36	3	1	2026-09-28 20:51:28.705913-05
1	37	3	1	2026-09-28 20:51:28.706448-05
1	38	3	1	2026-09-28 20:51:28.707275-05
1	39	3	1	2026-09-28 20:51:28.707912-05
1	40	3	1	2026-09-28 20:51:28.70841-05
1	41	3	1	2026-09-28 20:51:28.709022-05
1	42	3	1	2026-09-28 20:51:28.709556-05
1	43	3	1	2026-09-28 20:51:28.709874-05
1	44	3	1	2026-09-28 20:51:28.71015-05
1	45	3	1	2026-09-28 20:51:28.710752-05
1	46	3	1	2026-09-28 20:51:28.711285-05
1	47	3	1	2026-09-28 20:51:28.71186-05
1	48	3	1	2026-09-28 20:51:28.712148-05
1	49	3	1	2026-09-28 20:51:28.712397-05
1	50	3	1	2026-09-28 20:51:28.712634-05
1	51	3	1	2026-09-28 20:51:28.712859-05
1	52	3	1	2026-09-28 20:51:28.713087-05
1	53	3	1	2026-09-28 20:51:28.713346-05
1	54	3	1	2026-09-28 20:51:28.713571-05
1	55	3	1	2026-09-28 20:51:28.7138-05
1	56	3	1	2026-09-28 20:51:28.714033-05
1	57	3	1	2026-09-28 20:51:28.714417-05
1	58	3	1	2026-09-28 20:51:28.714678-05
1	59	3	1	2026-09-28 20:51:28.71491-05
1	60	3	1	2026-09-28 20:51:28.715132-05
1	61	3	1	2026-09-28 20:51:28.715413-05
1	62	3	1	2026-09-28 20:51:28.715692-05
1	63	3	1	2026-09-28 20:51:28.715929-05
1	64	3	1	2026-09-28 20:51:28.716151-05
1	65	3	1	2026-09-28 20:51:28.716386-05
1	66	3	1	2026-09-28 20:51:28.716606-05
1	67	3	1	2026-09-28 20:51:28.716987-05
1	68	3	1	2026-09-28 20:51:28.717369-05
1	69	3	1	2026-09-28 20:51:28.718075-05
1	70	3	1	2026-09-28 20:51:28.718629-05
1	71	3	1	2026-09-28 20:51:28.718969-05
1	72	3	1	2026-09-28 20:51:28.719248-05
1	73	3	1	2026-09-28 20:51:28.719485-05
1	74	3	1	2026-09-28 20:51:28.719716-05
1	75	1	1	2026-09-28 20:51:28.719948-05
1	76	1	1	2026-09-28 20:51:28.720193-05
1	77	1	1	2026-09-28 20:51:28.720434-05
1	78	1	1	2026-09-28 20:51:28.720825-05
1	79	1	1	2026-09-28 20:51:28.721193-05
1	80	1	1	2026-09-28 20:51:28.721571-05
1	81	1	1	2026-09-28 20:51:28.721826-05
1	82	1	1	2026-09-28 20:51:28.722064-05
1	83	1	1	2026-09-28 20:51:28.722289-05
1	84	1	1	2026-09-28 20:51:28.722506-05
1	85	1	1	2026-09-28 20:51:28.722732-05
1	86	1	1	2026-09-28 20:51:28.72298-05
1	87	1	1	2026-09-28 20:51:28.723197-05
1	88	1	1	2026-09-28 20:51:28.723416-05
1	89	1	1	2026-09-28 20:51:28.723791-05
1	90	2	1	2026-09-28 20:51:28.724033-05
1	91	2	1	2026-09-28 20:51:28.724734-05
1	92	2	1	2026-09-28 20:51:28.725322-05
1	93	2	1	2026-09-28 20:51:28.726065-05
1	94	2	1	2026-09-28 20:51:28.726372-05
1	95	2	1	2026-09-28 20:51:28.72664-05
1	96	2	1	2026-09-28 20:51:28.726909-05
1	97	2	1	2026-09-28 20:51:28.727276-05
1	98	2	1	2026-09-28 20:51:28.727828-05
1	99	2	1	2026-09-28 20:51:28.72852-05
1	100	2	1	2026-09-28 20:51:28.729058-05
1	101	2	1	2026-09-28 20:51:28.729498-05
1	102	2	1	2026-09-28 20:51:28.729915-05
1	103	2	1	2026-09-28 20:51:28.730288-05
1	104	2	1	2026-09-28 20:51:28.730652-05
1	105	2	1	2026-09-28 20:51:28.730993-05
1	106	2	1	2026-09-28 20:51:28.73153-05
1	107	2	1	2026-09-28 20:51:28.73218-05
1	108	2	1	2026-09-28 20:51:28.732724-05
1	109	2	1	2026-09-28 20:51:28.733005-05
1	110	2	1	2026-09-28 20:51:28.733237-05
1	111	2	1	2026-09-28 20:51:28.733466-05
1	112	2	1	2026-09-28 20:51:28.733704-05
1	113	2	1	2026-09-28 20:51:28.733948-05
1	114	2	1	2026-09-28 20:51:28.734254-05
1	115	2	1	2026-09-28 20:51:28.734641-05
1	116	2	1	2026-09-28 20:51:28.734945-05
1	117	2	1	2026-09-28 20:51:28.735286-05
1	118	2	1	2026-09-28 20:51:28.735525-05
1	119	2	1	2026-09-28 20:51:28.735764-05
1	120	2	1	2026-09-28 20:51:28.73599-05
1	121	2	1	2026-09-28 20:51:28.736214-05
1	122	2	1	2026-09-28 20:51:28.736576-05
1	123	2	1	2026-09-28 20:51:28.736925-05
1	124	2	1	2026-09-28 20:51:28.737189-05
1	125	2	1	2026-09-28 20:51:28.737424-05
1	126	2	1	2026-09-28 20:51:28.737642-05
1	127	2	1	2026-09-28 20:51:28.737903-05
1	128	2	1	2026-09-28 20:51:28.738499-05
1	129	2	1	2026-09-28 20:51:28.738982-05
1	130	2	1	2026-09-28 20:51:28.739415-05
1	131	2	1	2026-09-28 20:51:28.740038-05
1	132	2	1	2026-09-28 20:51:28.740477-05
1	133	2	1	2026-09-28 20:51:28.740858-05
1	134	2	1	2026-09-28 20:51:28.741414-05
1	135	2	1	2026-09-28 20:51:28.742268-05
1	136	2	1	2026-09-28 20:51:28.742876-05
1	137	2	1	2026-09-28 20:51:28.743564-05
1	138	2	1	2026-09-28 20:51:28.744152-05
1	139	2	1	2026-09-28 20:51:28.744621-05
1	140	3	1	2026-09-28 20:51:28.744983-05
\.


--
-- Data for Name: inventario_cierre; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventario_cierre (id_inventario_cierre, fecha_inventario, estado_inventario, usuario_registro, fecha_registro, usuario_revision, motivo_revision, observacion, id_local) FROM stdin;
1	2026-08-31	CERRADO	2	2026-08-31 23:00:00	\N	\N	\N	1
2	2026-09-01	CERRADO	2	2026-09-01 23:00:00	\N	\N	\N	1
3	2026-09-02	CERRADO	2	2026-09-02 23:00:00	\N	\N	\N	1
4	2026-09-03	CERRADO	2	2026-09-03 23:00:00	\N	\N	\N	1
5	2026-09-04	CERRADO	2	2026-09-04 23:00:00	\N	\N	\N	1
6	2026-09-05	CERRADO	2	2026-09-05 23:00:00	\N	\N	\N	1
7	2026-09-06	CERRADO	2	2026-09-06 23:00:00	\N	\N	\N	1
8	2026-09-07	CERRADO	2	2026-09-07 23:00:00	\N	\N	\N	1
9	2026-09-08	CERRADO	2	2026-09-08 23:00:00	\N	\N	\N	1
\.


--
-- Data for Name: inventario_cierre_correccion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventario_cierre_correccion (id_inventario_cierre_correccion, id_inventario_cierre, usuario_correccion, motivo_correccion, observacion, fecha_correccion) FROM stdin;
\.


--
-- Data for Name: inventario_cierre_correccion_detalle; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventario_cierre_correccion_detalle (id_inventario_cierre_correccion_detalle, id_inventario_cierre_correccion, id_producto, stock_anterior, stock_nuevo) FROM stdin;
\.


--
-- Data for Name: inventario_cierre_detalle; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventario_cierre_detalle (id_inventario_cierre_detalle, id_inventario_cierre, id_producto, stock_contado) FROM stdin;
1	1	1	20.000
2	1	2	20.000
3	1	3	20.000
4	1	4	20.000
5	1	5	20.000
6	1	6	20.000
7	1	7	20.000
8	1	8	20.000
9	1	9	20.000
10	1	10	20.000
11	1	11	20.000
12	1	12	20.000
13	1	13	20.000
14	1	14	24.000
15	1	15	20.000
16	1	16	20.000
17	1	17	20.000
18	1	18	24.000
19	1	19	20.000
20	1	20	20.000
21	1	21	20.000
22	1	22	24.000
23	1	23	20.000
24	1	24	20.000
25	1	25	20.000
26	1	26	20.000
27	1	27	20.000
28	1	28	20.000
29	1	29	24.000
30	1	30	24.000
31	1	31	24.000
32	1	32	24.000
33	1	33	24.000
34	1	34	24.000
35	1	35	24.000
36	1	36	24.000
37	1	37	20.000
38	1	38	20.000
39	1	39	20.000
40	1	40	20.000
41	1	41	20.000
42	1	42	20.000
43	1	43	20.000
44	1	44	20.000
45	1	45	20.000
46	1	46	20.000
47	1	47	20.000
48	1	48	20.000
49	1	49	20.000
50	1	50	20.000
51	1	51	20.000
52	1	52	20.000
53	1	53	20.000
54	1	54	20.000
55	1	55	20.000
56	1	56	20.000
57	1	57	20.000
58	1	58	24.000
59	1	59	24.000
60	1	60	24.000
61	1	61	24.000
62	1	62	20.000
63	1	63	20.000
64	1	64	20.000
65	1	65	20.000
66	1	66	20.000
67	1	67	20.000
68	1	68	20.000
69	1	69	20.000
70	1	70	20.000
71	1	71	20.000
72	1	72	24.000
73	1	73	20.000
74	1	74	20.000
75	1	75	24.000
76	1	76	24.000
77	1	77	30.000
78	1	78	30.000
79	1	79	30.000
80	1	80	30.000
81	1	81	30.000
82	1	82	30.000
83	1	83	24.000
84	1	84	24.000
85	1	85	24.000
86	1	86	24.000
87	1	87	24.000
88	1	88	24.000
89	1	89	24.000
90	1	90	20.300
91	1	91	20.300
92	1	92	20.300
93	1	93	20.300
94	1	94	20.000
95	1	95	20.300
96	1	96	20.300
97	1	97	20.300
98	1	98	20.300
99	1	99	20.300
100	1	100	20.400
101	1	101	30.000
102	1	102	30.000
103	1	103	30.000
104	1	104	30.000
105	1	105	30.000
106	1	106	30.000
107	1	107	30.000
108	1	108	30.000
109	1	109	30.000
110	1	110	30.000
111	1	111	30.000
112	1	112	30.000
113	1	113	30.000
114	1	114	30.000
115	1	115	30.000
116	1	116	30.000
117	1	117	30.000
118	1	118	30.000
119	1	119	30.000
120	1	120	30.000
121	1	121	30.000
122	1	122	30.000
123	1	123	30.000
124	1	124	30.000
125	1	125	30.000
126	1	126	30.000
127	1	127	30.000
128	1	128	30.000
129	1	129	30.000
130	1	130	30.000
131	1	131	30.000
132	1	132	30.000
133	1	133	30.000
134	1	134	30.000
135	1	135	24.000
136	1	136	24.000
137	1	137	24.000
138	1	138	24.000
139	1	139	24.000
140	1	140	24.000
141	2	1	18.000
142	2	2	18.000
143	2	3	18.000
144	2	4	18.000
145	2	5	18.000
146	2	6	18.000
147	2	7	18.000
148	2	8	18.000
149	2	9	18.000
150	2	10	18.000
151	2	11	18.000
152	2	12	18.000
153	2	13	18.000
154	2	14	22.000
155	2	15	18.000
156	2	16	18.000
157	2	17	18.000
158	2	18	22.000
159	2	19	18.000
160	2	20	18.000
161	2	21	18.000
162	2	22	22.000
163	2	23	18.000
164	2	24	18.000
165	2	25	18.000
166	2	26	18.000
167	2	27	18.000
168	2	28	18.000
169	2	29	22.000
170	2	30	22.000
171	2	31	22.000
172	2	32	22.000
173	2	33	22.000
174	2	34	22.000
175	2	35	22.000
176	2	36	22.000
177	2	37	18.000
178	2	38	18.000
179	2	39	18.000
180	2	40	18.000
181	2	41	18.000
182	2	42	18.000
183	2	43	18.000
184	2	44	18.000
185	2	45	18.000
186	2	46	18.000
187	2	47	18.000
188	2	48	18.000
189	2	49	18.000
190	2	50	18.000
191	2	51	18.000
192	2	52	18.000
193	2	53	18.000
194	2	54	18.000
195	2	55	18.000
196	2	56	18.000
197	2	57	18.000
198	2	58	22.000
199	2	59	22.000
200	2	60	22.000
201	2	61	22.000
202	2	62	18.000
203	2	63	18.000
204	2	64	18.000
205	2	65	18.000
206	2	66	18.000
207	2	67	18.000
208	2	68	18.000
209	2	69	18.000
210	2	70	18.000
211	2	71	18.000
212	2	72	22.000
213	2	73	18.000
214	2	74	18.000
215	2	75	22.000
216	2	76	22.000
217	2	77	28.000
218	2	78	28.000
219	2	79	28.000
220	2	80	28.000
221	2	81	28.000
222	2	82	28.000
223	2	83	22.000
224	2	84	22.000
225	2	85	22.000
226	2	86	22.000
227	2	87	22.000
228	2	88	22.000
229	2	89	22.000
230	2	90	18.300
231	2	91	18.300
232	2	92	18.300
233	2	93	18.300
234	2	94	18.000
235	2	95	18.300
236	2	96	18.300
237	2	97	18.300
238	2	98	18.300
239	2	99	18.300
240	2	100	18.400
241	2	101	28.000
242	2	102	28.000
243	2	103	28.000
244	2	104	28.000
245	2	105	28.000
246	2	106	28.000
247	2	107	28.000
248	2	108	28.000
249	2	109	28.000
250	2	110	28.000
251	2	111	28.000
252	2	112	28.000
253	2	113	28.000
254	2	114	28.000
255	2	115	28.000
256	2	116	28.000
257	2	117	28.000
258	2	118	28.000
259	2	119	28.000
260	2	120	28.000
261	2	121	28.000
262	2	122	28.000
263	2	123	28.000
264	2	124	28.000
265	2	125	28.000
266	2	126	28.000
267	2	127	28.000
268	2	128	28.000
269	2	129	28.000
270	2	130	28.000
271	2	131	28.000
272	2	132	28.000
273	2	133	28.000
274	2	134	28.000
275	2	135	22.000
276	2	136	22.000
277	2	137	22.000
278	2	138	22.000
279	2	139	22.000
280	2	140	22.000
281	3	1	16.000
282	3	2	16.000
283	3	3	16.000
284	3	4	16.000
285	3	5	16.000
286	3	6	16.000
287	3	7	16.000
288	3	8	16.000
289	3	9	16.000
290	3	10	16.000
291	3	11	16.000
292	3	12	16.000
293	3	13	16.000
294	3	14	20.000
295	3	15	16.000
296	3	16	16.000
297	3	17	16.000
298	3	18	20.000
299	3	19	16.000
300	3	20	16.000
301	3	21	16.000
302	3	22	20.000
303	3	23	16.000
304	3	24	16.000
305	3	25	16.000
306	3	26	16.000
307	3	27	16.000
308	3	28	16.000
309	3	29	20.000
310	3	30	20.000
311	3	31	20.000
312	3	32	20.000
313	3	33	20.000
314	3	34	20.000
315	3	35	20.000
316	3	36	20.000
317	3	37	16.000
318	3	38	16.000
319	3	39	16.000
320	3	40	16.000
321	3	41	16.000
322	3	42	16.000
323	3	43	16.000
324	3	44	16.000
325	3	45	16.000
326	3	46	16.000
327	3	47	16.000
328	3	48	16.000
329	3	49	16.000
330	3	50	16.000
331	3	51	16.000
332	3	52	16.000
333	3	53	16.000
334	3	54	16.000
335	3	55	16.000
336	3	56	16.000
337	3	57	16.000
338	3	58	20.000
339	3	59	20.000
340	3	60	20.000
341	3	61	20.000
342	3	62	16.000
343	3	63	16.000
344	3	64	16.000
345	3	65	16.000
346	3	66	16.000
347	3	67	16.000
348	3	68	16.000
349	3	69	16.000
350	3	70	16.000
351	3	71	16.000
352	3	72	20.000
353	3	73	16.000
354	3	74	16.000
355	3	75	20.000
356	3	76	20.000
357	3	77	26.000
358	3	78	26.000
359	3	79	26.000
360	3	80	26.000
361	3	81	26.000
362	3	82	26.000
363	3	83	20.000
364	3	84	20.000
365	3	85	20.000
366	3	86	20.000
367	3	87	20.000
368	3	88	20.000
369	3	89	20.000
370	3	90	16.300
371	3	91	16.300
372	3	92	16.300
373	3	93	16.300
374	3	94	16.000
375	3	95	16.300
376	3	96	16.300
377	3	97	16.300
378	3	98	16.300
379	3	99	16.300
380	3	100	16.400
381	3	101	26.000
382	3	102	26.000
383	3	103	26.000
384	3	104	26.000
385	3	105	26.000
386	3	106	26.000
387	3	107	26.000
388	3	108	26.000
389	3	109	26.000
390	3	110	26.000
391	3	111	26.000
392	3	112	26.000
393	3	113	26.000
394	3	114	26.000
395	3	115	26.000
396	3	116	26.000
397	3	117	26.000
398	3	118	26.000
399	3	119	26.000
400	3	120	26.000
401	3	121	26.000
402	3	122	26.000
403	3	123	26.000
404	3	124	26.000
405	3	125	26.000
406	3	126	26.000
407	3	127	26.000
408	3	128	26.000
409	3	129	26.000
410	3	130	26.000
411	3	131	26.000
412	3	132	26.000
413	3	133	26.000
414	3	134	26.000
415	3	135	20.000
416	3	136	20.000
417	3	137	20.000
418	3	138	20.000
419	3	139	20.000
420	3	140	20.000
421	4	1	14.000
422	4	2	14.000
423	4	3	14.000
424	4	4	14.000
425	4	5	14.000
426	4	6	14.000
427	4	7	14.000
428	4	8	14.000
429	4	9	14.000
430	4	10	14.000
431	4	11	14.000
432	4	12	14.000
433	4	13	14.000
434	4	14	18.000
435	4	15	14.000
436	4	16	14.000
437	4	17	14.000
438	4	18	18.000
439	4	19	14.000
440	4	20	14.000
441	4	21	14.000
442	4	22	18.000
443	4	23	14.000
444	4	24	14.000
445	4	25	14.000
446	4	26	14.000
447	4	27	14.000
448	4	28	14.000
449	4	29	18.000
450	4	30	18.000
451	4	31	18.000
452	4	32	18.000
453	4	33	18.000
454	4	34	18.000
455	4	35	18.000
456	4	36	18.000
457	4	37	14.000
458	4	38	14.000
459	4	39	14.000
460	4	40	14.000
461	4	41	14.000
462	4	42	14.000
463	4	43	14.000
464	4	44	14.000
465	4	45	14.000
466	4	46	14.000
467	4	47	14.000
468	4	48	14.000
469	4	49	14.000
470	4	50	14.000
471	4	51	14.000
472	4	52	14.000
473	4	53	14.000
474	4	54	14.000
475	4	55	14.000
476	4	56	14.000
477	4	57	14.000
478	4	58	18.000
479	4	59	18.000
480	4	60	18.000
481	4	61	18.000
482	4	62	14.000
483	4	63	14.000
484	4	64	14.000
485	4	65	14.000
486	4	66	14.000
487	4	67	14.000
488	4	68	14.000
489	4	69	14.000
490	4	70	14.000
491	4	71	14.000
492	4	72	18.000
493	4	73	14.000
494	4	74	14.000
495	4	75	18.000
496	4	76	18.000
497	4	77	24.000
498	4	78	24.000
499	4	79	24.000
500	4	80	24.000
501	4	81	24.000
502	4	82	24.000
503	4	83	18.000
504	4	84	18.000
505	4	85	18.000
506	4	86	18.000
507	4	87	18.000
508	4	88	18.000
509	4	89	18.000
510	4	90	14.300
511	4	91	14.300
512	4	92	14.300
513	4	93	14.300
514	4	94	14.000
515	4	95	14.300
516	4	96	14.300
517	4	97	14.300
518	4	98	14.300
519	4	99	14.300
520	4	100	14.400
521	4	101	24.000
522	4	102	24.000
523	4	103	24.000
524	4	104	24.000
525	4	105	24.000
526	4	106	24.000
527	4	107	24.000
528	4	108	24.000
529	4	109	24.000
530	4	110	24.000
531	4	111	24.000
532	4	112	24.000
533	4	113	24.000
534	4	114	24.000
535	4	115	24.000
536	4	116	24.000
537	4	117	24.000
538	4	118	24.000
539	4	119	24.000
540	4	120	24.000
541	4	121	24.000
542	4	122	24.000
543	4	123	24.000
544	4	124	24.000
545	4	125	24.000
546	4	126	24.000
547	4	127	24.000
548	4	128	24.000
549	4	129	24.000
550	4	130	24.000
551	4	131	24.000
552	4	132	24.000
553	4	133	24.000
554	4	134	24.000
555	4	135	18.000
556	4	136	18.000
557	4	137	18.000
558	4	138	18.000
559	4	139	18.000
560	4	140	18.000
561	5	1	12.000
562	5	2	12.000
563	5	3	12.000
564	5	4	12.000
565	5	5	12.000
566	5	6	12.000
567	5	7	12.000
568	5	8	12.000
569	5	9	12.000
570	5	10	12.000
571	5	11	12.000
572	5	12	12.000
573	5	13	12.000
574	5	14	16.000
575	5	15	12.000
576	5	16	12.000
577	5	17	12.000
578	5	18	16.000
579	5	19	12.000
580	5	20	12.000
581	5	21	12.000
582	5	22	16.000
583	5	23	12.000
584	5	24	12.000
585	5	25	12.000
586	5	26	12.000
587	5	27	12.000
588	5	28	12.000
589	5	29	16.000
590	5	30	16.000
591	5	31	16.000
592	5	32	16.000
593	5	33	16.000
594	5	34	16.000
595	5	35	16.000
596	5	36	16.000
597	5	37	12.000
598	5	38	12.000
599	5	39	12.000
600	5	40	12.000
601	5	41	12.000
602	5	42	12.000
603	5	43	12.000
604	5	44	12.000
605	5	45	12.000
606	5	46	12.000
607	5	47	12.000
608	5	48	12.000
609	5	49	12.000
610	5	50	12.000
611	5	51	12.000
612	5	52	12.000
613	5	53	12.000
614	5	54	12.000
615	5	55	12.000
616	5	56	12.000
617	5	57	12.000
618	5	58	16.000
619	5	59	16.000
620	5	60	16.000
621	5	61	16.000
622	5	62	12.000
623	5	63	12.000
624	5	64	12.000
625	5	65	12.000
626	5	66	12.000
627	5	67	12.000
628	5	68	12.000
629	5	69	12.000
630	5	70	12.000
631	5	71	12.000
632	5	72	16.000
633	5	73	12.000
634	5	74	12.000
635	5	75	16.000
636	5	76	16.000
637	5	77	22.000
638	5	78	22.000
639	5	79	22.000
640	5	80	22.000
641	5	81	22.000
642	5	82	22.000
643	5	83	16.000
644	5	84	16.000
645	5	85	16.000
646	5	86	16.000
647	5	87	16.000
648	5	88	16.000
649	5	89	16.000
650	5	90	12.300
651	5	91	12.300
652	5	92	12.300
653	5	93	12.300
654	5	94	12.000
655	5	95	12.300
656	5	96	12.300
657	5	97	12.300
658	5	98	12.300
659	5	99	12.300
660	5	100	12.400
661	5	101	22.000
662	5	102	22.000
663	5	103	22.000
664	5	104	22.000
665	5	105	22.000
666	5	106	22.000
667	5	107	22.000
668	5	108	22.000
669	5	109	22.000
670	5	110	22.000
671	5	111	22.000
672	5	112	22.000
673	5	113	22.000
674	5	114	22.000
675	5	115	22.000
676	5	116	22.000
677	5	117	22.000
678	5	118	22.000
679	5	119	22.000
680	5	120	22.000
681	5	121	22.000
682	5	122	22.000
683	5	123	22.000
684	5	124	22.000
685	5	125	22.000
686	5	126	22.000
687	5	127	22.000
688	5	128	22.000
689	5	129	22.000
690	5	130	22.000
691	5	131	22.000
692	5	132	22.000
693	5	133	22.000
694	5	134	22.000
695	5	135	16.000
696	5	136	16.000
697	5	137	16.000
698	5	138	16.000
699	5	139	16.000
700	5	140	16.000
701	6	1	10.000
702	6	2	10.000
703	6	3	10.000
704	6	4	10.000
705	6	5	10.000
706	6	6	10.000
707	6	7	10.000
708	6	8	10.000
709	6	9	10.000
710	6	10	10.000
711	6	11	10.000
712	6	12	10.000
713	6	13	10.000
714	6	14	14.000
715	6	15	10.000
716	6	16	10.000
717	6	17	10.000
718	6	18	14.000
719	6	19	10.000
720	6	20	10.000
721	6	21	10.000
722	6	22	14.000
723	6	23	10.000
724	6	24	10.000
725	6	25	10.000
726	6	26	10.000
727	6	27	10.000
728	6	28	10.000
729	6	29	14.000
730	6	30	14.000
731	6	31	14.000
732	6	32	14.000
733	6	33	14.000
734	6	34	14.000
735	6	35	14.000
736	6	36	14.000
737	6	37	10.000
738	6	38	10.000
739	6	39	10.000
740	6	40	10.000
741	6	41	10.000
742	6	42	10.000
743	6	43	10.000
744	6	44	10.000
745	6	45	10.000
746	6	46	10.000
747	6	47	10.000
748	6	48	10.000
749	6	49	10.000
750	6	50	10.000
751	6	51	10.000
752	6	52	10.000
753	6	53	10.000
754	6	54	10.000
755	6	55	10.000
756	6	56	10.000
757	6	57	10.000
758	6	58	14.000
759	6	59	14.000
760	6	60	14.000
761	6	61	14.000
762	6	62	10.000
763	6	63	10.000
764	6	64	10.000
765	6	65	10.000
766	6	66	10.000
767	6	67	10.000
768	6	68	10.000
769	6	69	10.000
770	6	70	10.000
771	6	71	10.000
772	6	72	14.000
773	6	73	10.000
774	6	74	10.000
775	6	75	14.000
776	6	76	14.000
777	6	77	20.000
778	6	78	20.000
779	6	79	20.000
780	6	80	20.000
781	6	81	20.000
782	6	82	20.000
783	6	83	14.000
784	6	84	14.000
785	6	85	14.000
786	6	86	14.000
787	6	87	14.000
788	6	88	14.000
789	6	89	14.000
790	6	90	10.300
791	6	91	10.300
792	6	92	10.300
793	6	93	10.300
794	6	94	10.000
795	6	95	10.300
796	6	96	10.300
797	6	97	10.300
798	6	98	10.300
799	6	99	10.300
800	6	100	10.400
801	6	101	20.000
802	6	102	20.000
803	6	103	20.000
804	6	104	20.000
805	6	105	20.000
806	6	106	20.000
807	6	107	20.000
808	6	108	20.000
809	6	109	20.000
810	6	110	20.000
811	6	111	20.000
812	6	112	20.000
813	6	113	20.000
814	6	114	20.000
815	6	115	20.000
816	6	116	20.000
817	6	117	20.000
818	6	118	20.000
819	6	119	20.000
820	6	120	20.000
821	6	121	20.000
822	6	122	20.000
823	6	123	20.000
824	6	124	20.000
825	6	125	20.000
826	6	126	20.000
827	6	127	20.000
828	6	128	20.000
829	6	129	20.000
830	6	130	20.000
831	6	131	20.000
832	6	132	20.000
833	6	133	20.000
834	6	134	20.000
835	6	135	14.000
836	6	136	14.000
837	6	137	14.000
838	6	138	14.000
839	6	139	14.000
840	6	140	14.000
841	7	1	8.000
842	7	2	8.000
843	7	3	8.000
844	7	4	8.000
845	7	5	8.000
846	7	6	8.000
847	7	7	8.000
848	7	8	8.000
849	7	9	8.000
850	7	10	8.000
851	7	11	8.000
852	7	12	8.000
853	7	13	8.000
854	7	14	12.000
855	7	15	8.000
856	7	16	8.000
857	7	17	8.000
858	7	18	12.000
859	7	19	8.000
860	7	20	8.000
861	7	21	8.000
862	7	22	12.000
863	7	23	8.000
864	7	24	8.000
865	7	25	8.000
866	7	26	8.000
867	7	27	8.000
868	7	28	8.000
869	7	29	12.000
870	7	30	12.000
871	7	31	12.000
872	7	32	12.000
873	7	33	12.000
874	7	34	12.000
875	7	35	12.000
876	7	36	12.000
877	7	37	8.000
878	7	38	8.000
879	7	39	8.000
880	7	40	8.000
881	7	41	8.000
882	7	42	8.000
883	7	43	8.000
884	7	44	8.000
885	7	45	8.000
886	7	46	8.000
887	7	47	8.000
888	7	48	8.000
889	7	49	8.000
890	7	50	8.000
891	7	51	8.000
892	7	52	8.000
893	7	53	8.000
894	7	54	8.000
895	7	55	8.000
896	7	56	8.000
897	7	57	8.000
898	7	58	12.000
899	7	59	12.000
900	7	60	12.000
901	7	61	12.000
902	7	62	8.000
903	7	63	8.000
904	7	64	8.000
905	7	65	8.000
906	7	66	8.000
907	7	67	8.000
908	7	68	8.000
909	7	69	8.000
910	7	70	8.000
911	7	71	8.000
912	7	72	12.000
913	7	73	8.000
914	7	74	8.000
915	7	75	12.000
916	7	76	12.000
917	7	77	18.000
918	7	78	18.000
919	7	79	18.000
920	7	80	18.000
921	7	81	18.000
922	7	82	18.000
923	7	83	12.000
924	7	84	12.000
925	7	85	12.000
926	7	86	12.000
927	7	87	12.000
928	7	88	12.000
929	7	89	12.000
930	7	90	8.300
931	7	91	8.300
932	7	92	8.300
933	7	93	8.300
934	7	94	8.000
935	7	95	8.300
936	7	96	8.300
937	7	97	8.300
938	7	98	8.300
939	7	99	8.300
940	7	100	8.400
941	7	101	18.000
942	7	102	18.000
943	7	103	18.000
944	7	104	18.000
945	7	105	18.000
946	7	106	18.000
947	7	107	18.000
948	7	108	18.000
949	7	109	18.000
950	7	110	18.000
951	7	111	18.000
952	7	112	18.000
953	7	113	18.000
954	7	114	18.000
955	7	115	18.000
956	7	116	18.000
957	7	117	18.000
958	7	118	18.000
959	7	119	18.000
960	7	120	18.000
961	7	121	18.000
962	7	122	18.000
963	7	123	18.000
964	7	124	18.000
965	7	125	18.000
966	7	126	18.000
967	7	127	18.000
968	7	128	18.000
969	7	129	18.000
970	7	130	18.000
971	7	131	18.000
972	7	132	18.000
973	7	133	18.000
974	7	134	18.000
975	7	135	12.000
976	7	136	12.000
977	7	137	12.000
978	7	138	12.000
979	7	139	12.000
980	7	140	12.000
981	8	1	6.000
982	8	2	6.000
983	8	3	6.000
984	8	4	6.000
985	8	5	6.000
986	8	6	6.000
987	8	7	6.000
988	8	8	6.000
989	8	9	6.000
990	8	10	6.000
991	8	11	6.000
992	8	12	6.000
993	8	13	6.000
994	8	14	10.000
995	8	15	6.000
996	8	16	6.000
997	8	17	6.000
998	8	18	10.000
999	8	19	6.000
1000	8	20	6.000
1001	8	21	6.000
1002	8	22	10.000
1003	8	23	6.000
1004	8	24	6.000
1005	8	25	6.000
1006	8	26	6.000
1007	8	27	6.000
1008	8	28	6.000
1009	8	29	10.000
1010	8	30	10.000
1011	8	31	10.000
1012	8	32	10.000
1013	8	33	10.000
1014	8	34	10.000
1015	8	35	10.000
1016	8	36	10.000
1017	8	37	6.000
1018	8	38	6.000
1019	8	39	6.000
1020	8	40	6.000
1021	8	41	6.000
1022	8	42	6.000
1023	8	43	6.000
1024	8	44	6.000
1025	8	45	6.000
1026	8	46	6.000
1027	8	47	6.000
1028	8	48	6.000
1029	8	49	6.000
1030	8	50	6.000
1031	8	51	6.000
1032	8	52	6.000
1033	8	53	6.000
1034	8	54	6.000
1035	8	55	6.000
1036	8	56	6.000
1037	8	57	6.000
1038	8	58	10.000
1039	8	59	10.000
1040	8	60	10.000
1041	8	61	10.000
1042	8	62	6.000
1043	8	63	6.000
1044	8	64	6.000
1045	8	65	6.000
1046	8	66	6.000
1047	8	67	6.000
1048	8	68	6.000
1049	8	69	6.000
1050	8	70	6.000
1051	8	71	6.000
1052	8	72	10.000
1053	8	73	6.000
1054	8	74	6.000
1055	8	75	10.000
1056	8	76	10.000
1057	8	77	16.000
1058	8	78	16.000
1059	8	79	16.000
1060	8	80	16.000
1061	8	81	16.000
1062	8	82	16.000
1063	8	83	10.000
1064	8	84	10.000
1065	8	85	10.000
1066	8	86	10.000
1067	8	87	10.000
1068	8	88	10.000
1069	8	89	10.000
1070	8	90	6.300
1071	8	91	6.300
1072	8	92	6.300
1073	8	93	6.300
1074	8	94	6.000
1075	8	95	6.300
1076	8	96	6.300
1077	8	97	6.300
1078	8	98	6.300
1079	8	99	6.300
1080	8	100	6.400
1081	8	101	16.000
1082	8	102	16.000
1083	8	103	16.000
1084	8	104	16.000
1085	8	105	16.000
1086	8	106	16.000
1087	8	107	16.000
1088	8	108	16.000
1089	8	109	16.000
1090	8	110	16.000
1091	8	111	16.000
1092	8	112	16.000
1093	8	113	16.000
1094	8	114	16.000
1095	8	115	16.000
1096	8	116	16.000
1097	8	117	16.000
1098	8	118	16.000
1099	8	119	16.000
1100	8	120	16.000
1101	8	121	16.000
1102	8	122	16.000
1103	8	123	16.000
1104	8	124	16.000
1105	8	125	16.000
1106	8	126	16.000
1107	8	127	16.000
1108	8	128	16.000
1109	8	129	16.000
1110	8	130	16.000
1111	8	131	16.000
1112	8	132	16.000
1113	8	133	16.000
1114	8	134	16.000
1115	8	135	10.000
1116	8	136	10.000
1117	8	137	10.000
1118	8	138	10.000
1119	8	139	10.000
1120	8	140	10.000
1121	9	1	4.000
1122	9	2	4.000
1123	9	3	4.000
1124	9	4	4.000
1125	9	5	4.000
1126	9	6	4.000
1127	9	7	4.000
1128	9	8	4.000
1129	9	9	4.000
1130	9	10	4.000
1131	9	11	4.000
1132	9	12	4.000
1133	9	13	4.000
1134	9	14	8.000
1135	9	15	4.000
1136	9	16	4.000
1137	9	17	4.000
1138	9	18	8.000
1139	9	19	4.000
1140	9	20	4.000
1141	9	21	4.000
1142	9	22	8.000
1143	9	23	4.000
1144	9	24	4.000
1145	9	25	4.000
1146	9	26	4.000
1147	9	27	4.000
1148	9	28	4.000
1149	9	29	8.000
1150	9	30	8.000
1151	9	31	8.000
1152	9	32	8.000
1153	9	33	8.000
1154	9	34	8.000
1155	9	35	8.000
1156	9	36	8.000
1157	9	37	4.000
1158	9	38	4.000
1159	9	39	4.000
1160	9	40	4.000
1161	9	41	4.000
1162	9	42	4.000
1163	9	43	4.000
1164	9	44	4.000
1165	9	45	4.000
1166	9	46	4.000
1167	9	47	4.000
1168	9	48	4.000
1169	9	49	4.000
1170	9	50	4.000
1171	9	51	4.000
1172	9	52	4.000
1173	9	53	4.000
1174	9	54	4.000
1175	9	55	4.000
1176	9	56	4.000
1177	9	57	4.000
1178	9	58	8.000
1179	9	59	8.000
1180	9	60	8.000
1181	9	61	8.000
1182	9	62	4.000
1183	9	63	4.000
1184	9	64	4.000
1185	9	65	4.000
1186	9	66	4.000
1187	9	67	4.000
1188	9	68	4.000
1189	9	69	4.000
1190	9	70	4.000
1191	9	71	4.000
1192	9	72	8.000
1193	9	73	4.000
1194	9	74	4.000
1195	9	75	8.000
1196	9	76	8.000
1197	9	77	14.000
1198	9	78	14.000
1199	9	79	14.000
1200	9	80	14.000
1201	9	81	14.000
1202	9	82	14.000
1203	9	83	8.000
1204	9	84	8.000
1205	9	85	8.000
1206	9	86	8.000
1207	9	87	8.000
1208	9	88	8.000
1209	9	89	8.000
1210	9	90	4.300
1211	9	91	4.300
1212	9	92	4.300
1213	9	93	4.300
1214	9	94	4.000
1215	9	95	4.300
1216	9	96	4.300
1217	9	97	4.300
1218	9	98	4.300
1219	9	99	4.300
1220	9	100	4.400
1221	9	101	14.000
1222	9	102	14.000
1223	9	103	14.000
1224	9	104	14.000
1225	9	105	14.000
1226	9	106	14.000
1227	9	107	14.000
1228	9	108	14.000
1229	9	109	14.000
1230	9	110	14.000
1231	9	111	14.000
1232	9	112	14.000
1233	9	113	14.000
1234	9	114	14.000
1235	9	115	14.000
1236	9	116	14.000
1237	9	117	14.000
1238	9	118	14.000
1239	9	119	14.000
1240	9	120	14.000
1241	9	121	14.000
1242	9	122	14.000
1243	9	123	14.000
1244	9	124	14.000
1245	9	125	14.000
1246	9	126	14.000
1247	9	127	14.000
1248	9	128	14.000
1249	9	129	14.000
1250	9	130	14.000
1251	9	131	14.000
1252	9	132	14.000
1253	9	133	14.000
1254	9	134	14.000
1255	9	135	8.000
1256	9	136	8.000
1257	9	137	8.000
1258	9	138	8.000
1259	9	139	8.000
1260	9	140	8.000
\.


--
-- Data for Name: inventario_conteo; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventario_conteo (id_ronda, id_producto, asignado_a, teorico, contado, corregido, contado_por, contado_en, estado, observacion, revisado_por, revisado_en, justificacion, justificado_por, justificado_en, version, puesto_asignado, puesto_nombre, contado_perfil, contado_puesto, contado_perfil_nombre, contado_puesto_nombre) FROM stdin;
1	26	\N	4.000	3.900	3.900	2	2026-09-28 21:00:09.740303-05	REVISADO		1	2026-09-28 21:10:21.905773-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	27	\N	4.000	4.100	4.100	2	2026-09-28 21:00:09.742107-05	REVISADO		1	2026-09-28 21:10:21.91372-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	28	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.743074-05	REVISADO		1	2026-09-28 21:10:21.915441-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	29	\N	7.000	7.000	7.000	2	2026-09-28 21:00:09.744067-05	REVISADO		1	2026-09-28 21:10:21.916666-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	30	\N	8.000	8.000	8.000	2	2026-09-28 21:00:09.74497-05	REVISADO		1	2026-09-28 21:10:21.918069-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	31	\N	8.000	7.000	7.000	2	2026-09-28 21:00:09.745907-05	REVISADO		1	2026-09-28 21:10:21.918912-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	32	\N	8.000	9.000	9.000	2	2026-09-28 21:00:09.747573-05	REVISADO		1	2026-09-28 21:10:21.920315-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	33	\N	7.000	7.000	7.000	2	2026-09-28 21:00:09.749038-05	REVISADO		1	2026-09-28 21:10:21.921635-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	34	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.749941-05	REVISADO		1	2026-09-28 21:10:21.922848-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	35	\N	8.000	8.000	8.000	2	2026-09-28 21:00:09.750781-05	REVISADO		1	2026-09-28 21:10:21.923685-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	36	\N	2.000	1.000	1.000	2	2026-09-28 21:00:09.7518-05	REVISADO		1	2026-09-28 21:10:21.925186-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	37	\N	4.000	4.100	4.100	2	2026-09-28 21:00:09.752616-05	REVISADO		1	2026-09-28 21:10:21.926629-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	38	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.753342-05	REVISADO		1	2026-09-28 21:10:21.927917-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	39	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.754085-05	REVISADO		1	2026-09-28 21:10:21.929906-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	40	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.756102-05	REVISADO		1	2026-09-28 21:10:21.930941-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	41	\N	4.000	3.900	3.900	2	2026-09-28 21:00:09.757338-05	REVISADO		1	2026-09-28 21:10:21.931929-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	42	\N	4.000	4.100	4.100	2	2026-09-28 21:00:09.759481-05	REVISADO		1	2026-09-28 21:10:21.9337-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	43	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.760818-05	REVISADO		1	2026-09-28 21:10:21.93601-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	44	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.76262-05	REVISADO		1	2026-09-28 21:10:21.939455-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	45	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.763889-05	REVISADO		1	2026-09-28 21:10:21.941673-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	46	\N	4.000	3.000	3.000	2	2026-09-28 21:00:09.764979-05	REVISADO		1	2026-09-28 21:10:21.943888-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	47	\N	4.000	4.100	4.100	2	2026-09-28 21:00:09.765885-05	REVISADO		1	2026-09-28 21:10:21.946178-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	48	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.766729-05	REVISADO		1	2026-09-28 21:10:21.948141-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	49	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.767505-05	REVISADO		1	2026-09-28 21:10:21.950061-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	50	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.768726-05	REVISADO		1	2026-09-28 21:10:21.956225-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	51	\N	4.000	3.000	3.000	2	2026-09-28 21:00:09.770455-05	REVISADO		1	2026-09-28 21:10:21.95762-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	52	\N	4.000	5.000	5.000	2	2026-09-28 21:00:09.772509-05	REVISADO		1	2026-09-28 21:10:21.958625-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	53	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.773847-05	REVISADO		1	2026-09-28 21:10:21.959545-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	54	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.774898-05	REVISADO		1	2026-09-28 21:10:21.960787-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	55	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.776621-05	REVISADO		1	2026-09-28 21:10:21.962082-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	56	\N	4.000	3.000	3.000	2	2026-09-28 21:00:09.777703-05	REVISADO		1	2026-09-28 21:10:21.963617-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	57	\N	4.000	4.100	4.100	2	2026-09-28 21:00:09.778566-05	REVISADO		1	2026-09-28 21:10:21.964614-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	58	\N	8.000	8.000	8.000	2	2026-09-28 21:00:09.77962-05	REVISADO		1	2026-09-28 21:10:21.965688-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	59	\N	8.000	8.000	8.000	2	2026-09-28 21:00:09.780466-05	REVISADO		1	2026-09-28 21:10:21.967012-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	60	\N	8.000	8.000	8.000	2	2026-09-28 21:00:09.781381-05	REVISADO		1	2026-09-28 21:10:21.967983-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	61	\N	8.000	7.000	7.000	2	2026-09-28 21:00:09.782881-05	REVISADO		1	2026-09-28 21:10:21.969005-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	62	\N	4.000	5.000	5.000	2	2026-09-28 21:00:09.784588-05	REVISADO		1	2026-09-28 21:10:21.970176-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	63	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.78678-05	REVISADO		1	2026-09-28 21:10:21.971656-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	64	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.788523-05	REVISADO		1	2026-09-28 21:10:21.973299-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	65	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.790731-05	REVISADO		1	2026-09-28 21:10:21.974617-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	66	\N	4.000	3.000	3.000	2	2026-09-28 21:00:09.791977-05	REVISADO		1	2026-09-28 21:10:21.975646-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	67	\N	4.000	5.000	5.000	2	2026-09-28 21:00:09.793047-05	REVISADO		1	2026-09-28 21:10:21.976907-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	68	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.793879-05	REVISADO		1	2026-09-28 21:10:21.978321-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	69	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.794688-05	REVISADO		1	2026-09-28 21:10:21.979642-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	70	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.795501-05	REVISADO		1	2026-09-28 21:10:21.981129-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	71	\N	4.000	3.000	3.000	2	2026-09-28 21:00:09.797188-05	REVISADO		1	2026-09-28 21:10:21.982506-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	72	\N	14.000	15.000	15.000	2	2026-09-28 21:00:09.79844-05	REVISADO		1	2026-09-28 21:10:21.984111-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	73	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.79934-05	REVISADO		1	2026-09-28 21:10:21.985772-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	74	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.800433-05	REVISADO		1	2026-09-28 21:10:21.986666-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	75	\N	8.000	8.000	8.000	4	2026-09-28 21:00:09.801453-05	REVISADO		1	2026-09-28 21:10:21.98784-05		\N	\N	3	1	Mesero	4	1	Miembro de equipo	Mesero
1	76	\N	8.000	7.000	7.000	4	2026-09-28 21:00:09.802305-05	REVISADO		1	2026-09-28 21:10:21.989262-05		\N	\N	3	1	Mesero	4	1	Miembro de equipo	Mesero
1	77	\N	14.000	15.000	15.000	4	2026-09-28 21:00:09.803669-05	REVISADO		1	2026-09-28 21:10:21.990695-05		\N	\N	3	1	Mesero	4	1	Miembro de equipo	Mesero
1	1	\N	3.500	3.400	3.400	2	2026-09-28 21:00:09.69845-05	REVISADO		1	2026-09-28 21:10:21.854798-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	2	\N	4.000	4.100	4.100	2	2026-09-28 21:00:09.704515-05	REVISADO		1	2026-09-28 21:10:21.865252-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	3	\N	9.000	9.000	9.000	2	2026-09-28 21:00:09.707647-05	REVISADO		1	2026-09-28 21:10:21.86764-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	4	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.711024-05	REVISADO		1	2026-09-28 21:10:21.869279-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	5	\N	0.800	0.800	0.800	2	2026-09-28 21:00:09.713875-05	REVISADO		1	2026-09-28 21:10:21.871127-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	6	\N	4.000	3.900	3.900	2	2026-09-28 21:00:09.715921-05	REVISADO		1	2026-09-28 21:10:21.873351-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	7	\N	4.000	4.100	4.100	2	2026-09-28 21:00:09.717274-05	REVISADO		1	2026-09-28 21:10:21.874833-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	8	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.718134-05	REVISADO		1	2026-09-28 21:10:21.875849-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	9	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.720458-05	REVISADO		1	2026-09-28 21:10:21.876971-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	10	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.7216-05	REVISADO		1	2026-09-28 21:10:21.878278-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	11	\N	4.000	3.900	3.900	2	2026-09-28 21:00:09.722624-05	REVISADO		1	2026-09-28 21:10:21.879466-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	12	\N	4.000	5.000	5.000	2	2026-09-28 21:00:09.723615-05	REVISADO		1	2026-09-28 21:10:21.881221-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	13	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.724549-05	REVISADO		1	2026-09-28 21:10:21.883562-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	14	\N	8.000	8.000	8.000	2	2026-09-28 21:00:09.725293-05	REVISADO		1	2026-09-28 21:10:21.885076-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	15	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.726049-05	REVISADO		1	2026-09-28 21:10:21.886244-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	16	\N	4.000	3.000	3.000	2	2026-09-28 21:00:09.72756-05	REVISADO		1	2026-09-28 21:10:21.887867-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	17	\N	4.000	4.100	4.100	2	2026-09-28 21:00:09.728795-05	REVISADO		1	2026-09-28 21:10:21.889864-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	18	\N	8.000	8.000	8.000	2	2026-09-28 21:00:09.729755-05	REVISADO		1	2026-09-28 21:10:21.892839-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	19	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.730543-05	REVISADO		1	2026-09-28 21:10:21.89525-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	20	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.731688-05	REVISADO		1	2026-09-28 21:10:21.897172-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	21	\N	4.000	3.000	3.000	2	2026-09-28 21:00:09.732698-05	REVISADO		1	2026-09-28 21:10:21.898781-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	22	\N	8.000	9.000	9.000	2	2026-09-28 21:00:09.733984-05	REVISADO		1	2026-09-28 21:10:21.900177-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	23	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.735944-05	REVISADO		1	2026-09-28 21:10:21.901661-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	24	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.738219-05	REVISADO		1	2026-09-28 21:10:21.903181-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	25	\N	4.000	4.000	4.000	2	2026-09-28 21:00:09.739381-05	REVISADO		1	2026-09-28 21:10:21.904424-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
1	78	\N	14.000	14.000	14.000	4	2026-09-28 21:00:09.806142-05	REVISADO		1	2026-09-28 21:10:21.991922-05		\N	\N	3	1	Mesero	4	1	Miembro de equipo	Mesero
1	79	\N	14.000	14.000	14.000	4	2026-09-28 21:00:09.807883-05	REVISADO		1	2026-09-28 21:10:21.992909-05		\N	\N	3	1	Mesero	4	1	Miembro de equipo	Mesero
1	80	\N	14.000	14.000	14.000	4	2026-09-28 21:00:09.808966-05	REVISADO		1	2026-09-28 21:10:21.993722-05		\N	\N	3	1	Mesero	4	1	Miembro de equipo	Mesero
1	81	\N	12.000	11.000	11.000	4	2026-09-28 21:00:09.810182-05	REVISADO		1	2026-09-28 21:10:21.994699-05		\N	\N	3	1	Mesero	4	1	Miembro de equipo	Mesero
1	82	\N	8.000	9.000	9.000	4	2026-09-28 21:00:09.811762-05	REVISADO		1	2026-09-28 21:10:21.995691-05		\N	\N	3	1	Mesero	4	1	Miembro de equipo	Mesero
1	83	\N	8.000	8.000	8.000	4	2026-09-28 21:00:09.812693-05	REVISADO		1	2026-09-28 21:10:21.997152-05		\N	\N	3	1	Mesero	4	1	Miembro de equipo	Mesero
1	84	\N	8.000	8.000	8.000	4	2026-09-28 21:00:09.813895-05	REVISADO		1	2026-09-28 21:10:21.998633-05		\N	\N	3	1	Mesero	4	1	Miembro de equipo	Mesero
1	85	\N	8.000	8.000	8.000	4	2026-09-28 21:00:09.81486-05	REVISADO		1	2026-09-28 21:10:21.9999-05		\N	\N	3	1	Mesero	4	1	Miembro de equipo	Mesero
1	86	\N	8.000	7.000	7.000	4	2026-09-28 21:00:09.815893-05	REVISADO		1	2026-09-28 21:10:22.001311-05		\N	\N	3	1	Mesero	4	1	Miembro de equipo	Mesero
1	87	\N	8.000	9.000	9.000	4	2026-09-28 21:00:09.817418-05	REVISADO		1	2026-09-28 21:10:22.002553-05		\N	\N	3	1	Mesero	4	1	Miembro de equipo	Mesero
1	88	\N	8.000	8.000	8.000	4	2026-09-28 21:00:09.819146-05	REVISADO		1	2026-09-28 21:10:22.003709-05		\N	\N	3	1	Mesero	4	1	Miembro de equipo	Mesero
1	89	\N	8.000	8.000	8.000	4	2026-09-28 21:00:09.82146-05	REVISADO		1	2026-09-28 21:10:22.004478-05		\N	\N	3	1	Mesero	4	1	Miembro de equipo	Mesero
1	90	\N	4.300	4.300	4.300	3	2026-09-28 21:00:09.822771-05	REVISADO		1	2026-09-28 21:10:22.005404-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	91	\N	4.300	4.200	4.200	3	2026-09-28 21:00:09.824197-05	REVISADO		1	2026-09-28 21:10:22.006422-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	92	\N	4.300	4.400	4.400	3	2026-09-28 21:00:09.826132-05	REVISADO		1	2026-09-28 21:10:22.00785-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	93	\N	4.300	4.300	4.300	3	2026-09-28 21:00:09.827601-05	REVISADO		1	2026-09-28 21:10:22.009329-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	94	\N	4.000	4.000	4.000	3	2026-09-28 21:00:09.828859-05	REVISADO		1	2026-09-28 21:10:22.010593-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	95	\N	4.300	4.300	4.300	3	2026-09-28 21:00:09.830044-05	REVISADO		1	2026-09-28 21:10:22.011933-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	96	\N	4.300	4.200	4.200	3	2026-09-28 21:00:09.831643-05	REVISADO		1	2026-09-28 21:10:22.013397-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	97	\N	4.300	4.400	4.400	3	2026-09-28 21:00:09.833267-05	REVISADO		1	2026-09-28 21:10:22.01462-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	98	\N	4.300	4.300	4.300	3	2026-09-28 21:00:09.834829-05	REVISADO		1	2026-09-28 21:10:22.015705-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	99	\N	4.300	4.300	4.300	3	2026-09-28 21:00:09.836662-05	REVISADO		1	2026-09-28 21:10:22.016743-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	100	\N	4.400	4.400	4.400	3	2026-09-28 21:00:09.838415-05	REVISADO		1	2026-09-28 21:10:22.018171-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	101	\N	14.000	13.900	13.900	3	2026-09-28 21:00:09.840458-05	REVISADO		1	2026-09-28 21:10:22.019304-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	102	\N	14.000	14.100	14.100	3	2026-09-28 21:00:09.842556-05	REVISADO		1	2026-09-28 21:10:22.02041-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	103	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.843697-05	REVISADO		1	2026-09-28 21:10:22.021766-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	104	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.845576-05	REVISADO		1	2026-09-28 21:10:22.022899-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	105	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.84738-05	REVISADO		1	2026-09-28 21:10:22.024207-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	106	\N	14.000	13.900	13.900	3	2026-09-28 21:00:09.848767-05	REVISADO		1	2026-09-28 21:10:22.025184-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	107	\N	4.000	4.100	4.100	3	2026-09-28 21:00:09.850618-05	REVISADO		1	2026-09-28 21:10:22.026031-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	108	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.85259-05	REVISADO		1	2026-09-28 21:10:22.027681-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	109	\N	12.000	12.000	12.000	3	2026-09-28 21:00:09.854621-05	REVISADO		1	2026-09-28 21:10:22.029272-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	110	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.856931-05	REVISADO		1	2026-09-28 21:10:22.030901-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	111	\N	14.000	13.900	13.900	3	2026-09-28 21:00:09.858334-05	REVISADO		1	2026-09-28 21:10:22.032403-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	112	\N	14.000	14.100	14.100	3	2026-09-28 21:00:09.860156-05	REVISADO		1	2026-09-28 21:10:22.033801-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	113	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.861778-05	REVISADO		1	2026-09-28 21:10:22.035097-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	114	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.863469-05	REVISADO		1	2026-09-28 21:10:22.036387-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	115	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.865068-05	REVISADO		1	2026-09-28 21:10:22.037339-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	116	\N	14.000	13.900	13.900	3	2026-09-28 21:00:09.867637-05	REVISADO		1	2026-09-28 21:10:22.03821-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	117	\N	14.000	14.100	14.100	3	2026-09-28 21:00:09.869899-05	REVISADO		1	2026-09-28 21:10:22.039533-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	118	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.871358-05	REVISADO		1	2026-09-28 21:10:22.040882-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	119	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.872604-05	REVISADO		1	2026-09-28 21:10:22.042056-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	120	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.874533-05	REVISADO		1	2026-09-28 21:10:22.043407-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	121	\N	14.000	13.900	13.900	3	2026-09-28 21:00:09.875905-05	REVISADO		1	2026-09-28 21:10:22.044601-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	122	\N	14.000	14.100	14.100	3	2026-09-28 21:00:09.877962-05	REVISADO		1	2026-09-28 21:10:22.045546-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	123	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.880067-05	REVISADO		1	2026-09-28 21:10:22.046483-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	124	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.881898-05	REVISADO		1	2026-09-28 21:10:22.047802-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	125	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.883114-05	REVISADO		1	2026-09-28 21:10:22.049193-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	126	\N	14.000	13.900	13.900	3	2026-09-28 21:00:09.884419-05	REVISADO		1	2026-09-28 21:10:22.050124-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	127	\N	14.000	14.100	14.100	3	2026-09-28 21:00:09.885559-05	REVISADO		1	2026-09-28 21:10:22.051041-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	128	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.887302-05	REVISADO		1	2026-09-28 21:10:22.052099-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	129	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.889565-05	REVISADO		1	2026-09-28 21:10:22.053-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	130	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.891996-05	REVISADO		1	2026-09-28 21:10:22.054054-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	131	\N	14.000	13.900	13.900	3	2026-09-28 21:00:09.893452-05	REVISADO		1	2026-09-28 21:10:22.055123-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	132	\N	14.000	14.100	14.100	3	2026-09-28 21:00:09.895426-05	REVISADO		1	2026-09-28 21:10:22.056759-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	133	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.89656-05	REVISADO		1	2026-09-28 21:10:22.058367-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	134	\N	14.000	14.000	14.000	3	2026-09-28 21:00:09.897818-05	REVISADO		1	2026-09-28 21:10:22.059533-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	135	\N	3.000	3.000	3.000	3	2026-09-28 21:00:09.898719-05	REVISADO		1	2026-09-28 21:10:22.060424-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	136	\N	8.000	7.000	7.000	3	2026-09-28 21:00:09.900038-05	REVISADO		1	2026-09-28 21:10:22.061362-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	137	\N	6.000	7.000	7.000	3	2026-09-28 21:00:09.902214-05	REVISADO		1	2026-09-28 21:10:22.062662-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	138	\N	8.000	8.000	8.000	3	2026-09-28 21:00:09.9049-05	REVISADO		1	2026-09-28 21:10:22.063899-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	139	\N	8.000	8.000	8.000	3	2026-09-28 21:00:09.906711-05	REVISADO		1	2026-09-28 21:10:22.065301-05		\N	\N	3	2	Bartender	4	2	Miembro de equipo	Bartender
1	140	\N	8.000	8.000	8.000	2	2026-09-28 21:00:09.908677-05	REVISADO		1	2026-09-28 21:10:22.066741-05		\N	\N	3	3	Cocina	4	3	Miembro de equipo	Cocina
\.


--
-- Data for Name: inventario_conteo_historial; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventario_conteo_historial (id_historial, id_ronda, id_producto, id_usuario, accion, anterior, nuevo, creado_en) FROM stdin;
1	1	1	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 3.5, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 1, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 3.4, "teorico": 3.5, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.698450-05:00", "contado_por": 2, "id_producto": 1, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.700669-05
2	1	2	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 2, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.704515-05:00", "contado_por": 2, "id_producto": 2, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.70593-05
3	1	3	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 9.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 3, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 9.0, "teorico": 9.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.707647-05:00", "contado_por": 2, "id_producto": 3, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.709688-05
4	1	4	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 4, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.711024-05:00", "contado_por": 2, "id_producto": 4, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.712383-05
5	1	5	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 0.8, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 5, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 0.8, "teorico": 0.8, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.713875-05:00", "contado_por": 2, "id_producto": 5, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.715175-05
6	1	6	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 6, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 3.9, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.715921-05:00", "contado_por": 2, "id_producto": 6, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.716804-05
7	1	7	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 7, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.717274-05:00", "contado_por": 2, "id_producto": 7, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.717781-05
8	1	8	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 8, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.718134-05:00", "contado_por": 2, "id_producto": 8, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.718592-05
9	1	9	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 9, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.720458-05:00", "contado_por": 2, "id_producto": 9, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.721198-05
10	1	10	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 10, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.721600-05:00", "contado_por": 2, "id_producto": 10, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.722165-05
11	1	11	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 11, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 3.9, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.722624-05:00", "contado_por": 2, "id_producto": 11, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.72318-05
12	1	12	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 12, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 5.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.723615-05:00", "contado_por": 2, "id_producto": 12, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.724216-05
13	1	13	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 13, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.724549-05:00", "contado_por": 2, "id_producto": 13, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.725001-05
14	1	14	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 14, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.725293-05:00", "contado_por": 2, "id_producto": 14, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.725741-05
15	1	15	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 15, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.726049-05:00", "contado_por": 2, "id_producto": 15, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.726716-05
16	1	16	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 16, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 3.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.727560-05:00", "contado_por": 2, "id_producto": 16, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.728275-05
17	1	17	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 17, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.728795-05:00", "contado_por": 2, "id_producto": 17, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.729367-05
18	1	18	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 18, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.729755-05:00", "contado_por": 2, "id_producto": 18, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.730229-05
19	1	19	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 19, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.730543-05:00", "contado_por": 2, "id_producto": 19, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.731117-05
20	1	20	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 20, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.731688-05:00", "contado_por": 2, "id_producto": 20, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.732343-05
21	1	21	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 21, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 3.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.732698-05:00", "contado_por": 2, "id_producto": 21, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.733295-05
22	1	22	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 22, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 9.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.733984-05:00", "contado_por": 2, "id_producto": 22, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.735246-05
23	1	23	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 23, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.735944-05:00", "contado_por": 2, "id_producto": 23, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.737599-05
24	1	24	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 24, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.738219-05:00", "contado_por": 2, "id_producto": 24, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.738948-05
25	1	25	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 25, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.739381-05:00", "contado_por": 2, "id_producto": 25, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.739959-05
26	1	26	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 26, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 3.9, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.740303-05:00", "contado_por": 2, "id_producto": 26, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.741544-05
27	1	27	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 27, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.742107-05:00", "contado_por": 2, "id_producto": 27, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.742726-05
28	1	28	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 28, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.743074-05:00", "contado_por": 2, "id_producto": 28, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.743589-05
29	1	29	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 7.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 29, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 7.0, "teorico": 7.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.744067-05:00", "contado_por": 2, "id_producto": 29, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.744588-05
30	1	30	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 30, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.744970-05:00", "contado_por": 2, "id_producto": 30, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.745499-05
31	1	31	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 31, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 7.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.745907-05:00", "contado_por": 2, "id_producto": 31, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.746508-05
32	1	32	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 32, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 9.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.747573-05:00", "contado_por": 2, "id_producto": 32, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.748562-05
33	1	33	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 7.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 33, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 7.0, "teorico": 7.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.749038-05:00", "contado_por": 2, "id_producto": 33, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.749604-05
34	1	34	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 34, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.749941-05:00", "contado_por": 2, "id_producto": 34, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.750419-05
35	1	35	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 35, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.750781-05:00", "contado_por": 2, "id_producto": 35, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.751403-05
36	1	36	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 2.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 36, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 1.0, "teorico": 2.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.751800-05:00", "contado_por": 2, "id_producto": 36, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.75224-05
37	1	37	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 37, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.752616-05:00", "contado_por": 2, "id_producto": 37, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.753053-05
38	1	38	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 38, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.753342-05:00", "contado_por": 2, "id_producto": 38, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.753767-05
39	1	39	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 39, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.754085-05:00", "contado_por": 2, "id_producto": 39, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.755148-05
40	1	40	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 40, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.756102-05:00", "contado_por": 2, "id_producto": 40, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.756833-05
41	1	41	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 41, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 3.9, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.757338-05:00", "contado_por": 2, "id_producto": 41, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.758687-05
42	1	42	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 42, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.759481-05:00", "contado_por": 2, "id_producto": 42, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.760453-05
43	1	43	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 43, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.760818-05:00", "contado_por": 2, "id_producto": 43, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.761675-05
44	1	44	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 44, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.762620-05:00", "contado_por": 2, "id_producto": 44, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.763444-05
45	1	45	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 45, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.763889-05:00", "contado_por": 2, "id_producto": 45, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.764532-05
46	1	46	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 46, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 3.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.764979-05:00", "contado_por": 2, "id_producto": 46, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.765533-05
47	1	47	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 47, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.765885-05:00", "contado_por": 2, "id_producto": 47, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.766402-05
48	1	48	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 48, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.766729-05:00", "contado_por": 2, "id_producto": 48, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.767181-05
49	1	49	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 49, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.767505-05:00", "contado_por": 2, "id_producto": 49, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.767944-05
50	1	50	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 50, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.768726-05:00", "contado_por": 2, "id_producto": 50, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.769908-05
51	1	51	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 51, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 3.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.770455-05:00", "contado_por": 2, "id_producto": 51, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.771481-05
52	1	52	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 52, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 5.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.772509-05:00", "contado_por": 2, "id_producto": 52, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.773427-05
53	1	53	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 53, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.773847-05:00", "contado_por": 2, "id_producto": 53, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.774482-05
54	1	54	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 54, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.774898-05:00", "contado_por": 2, "id_producto": 54, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.776082-05
55	1	55	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 55, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.776621-05:00", "contado_por": 2, "id_producto": 55, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.777213-05
56	1	56	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 56, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 3.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.777703-05:00", "contado_por": 2, "id_producto": 56, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.778242-05
57	1	57	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 57, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.778566-05:00", "contado_por": 2, "id_producto": 57, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.779077-05
58	1	58	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 58, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.779620-05:00", "contado_por": 2, "id_producto": 58, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.780134-05
59	1	59	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 59, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.780466-05:00", "contado_por": 2, "id_producto": 59, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.780945-05
60	1	60	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 60, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.781381-05:00", "contado_por": 2, "id_producto": 60, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.781946-05
61	1	61	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 61, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 7.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.782881-05:00", "contado_por": 2, "id_producto": 61, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.784022-05
62	1	62	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 62, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 5.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.784588-05:00", "contado_por": 2, "id_producto": 62, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.785968-05
63	1	63	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 63, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.786780-05:00", "contado_por": 2, "id_producto": 63, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.787954-05
64	1	64	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 64, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.788523-05:00", "contado_por": 2, "id_producto": 64, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.78996-05
65	1	65	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 65, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.790731-05:00", "contado_por": 2, "id_producto": 65, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.791409-05
66	1	66	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 66, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 3.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.791977-05:00", "contado_por": 2, "id_producto": 66, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.792691-05
67	1	67	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 67, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 5.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.793047-05:00", "contado_por": 2, "id_producto": 67, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.79354-05
68	1	68	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 68, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.793879-05:00", "contado_por": 2, "id_producto": 68, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.794358-05
69	1	69	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 69, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.794688-05:00", "contado_por": 2, "id_producto": 69, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.79515-05
70	1	70	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 70, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.795501-05:00", "contado_por": 2, "id_producto": 70, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.796138-05
71	1	71	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 71, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 3.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.797188-05:00", "contado_por": 2, "id_producto": 71, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.79801-05
72	1	72	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 72, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 15.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.798440-05:00", "contado_por": 2, "id_producto": 72, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.798969-05
73	1	73	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 73, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.799340-05:00", "contado_por": 2, "id_producto": 73, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.800032-05
74	1	74	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 74, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.800433-05:00", "contado_por": 2, "id_producto": 74, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.801041-05
75	1	75	4	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 75, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.801453-05:00", "contado_por": 4, "id_producto": 75, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:00:09.801952-05
76	1	76	4	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 76, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 7.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.802305-05:00", "contado_por": 4, "id_producto": 76, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:00:09.802786-05
77	1	77	4	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 77, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 15.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.803669-05:00", "contado_por": 4, "id_producto": 77, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:00:09.805226-05
78	1	78	4	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 78, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.806142-05:00", "contado_por": 4, "id_producto": 78, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:00:09.807359-05
79	1	79	4	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 79, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.807883-05:00", "contado_por": 4, "id_producto": 79, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:00:09.808532-05
80	1	80	4	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 80, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.808966-05:00", "contado_por": 4, "id_producto": 80, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:00:09.809503-05
81	1	81	4	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 12.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 81, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 11.0, "teorico": 12.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.810182-05:00", "contado_por": 4, "id_producto": 81, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:00:09.811293-05
82	1	82	4	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 82, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 9.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.811762-05:00", "contado_por": 4, "id_producto": 82, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:00:09.812342-05
83	1	83	4	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 83, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.812693-05:00", "contado_por": 4, "id_producto": 83, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:00:09.813496-05
84	1	84	4	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 84, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.813895-05:00", "contado_por": 4, "id_producto": 84, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:00:09.81446-05
85	1	85	4	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 85, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.814860-05:00", "contado_por": 4, "id_producto": 85, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:00:09.815401-05
86	1	86	4	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 86, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 7.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.815893-05:00", "contado_por": 4, "id_producto": 86, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:00:09.816617-05
87	1	87	4	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 87, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 9.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.817418-05:00", "contado_por": 4, "id_producto": 87, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:00:09.818654-05
88	1	88	4	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 88, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.819146-05:00", "contado_por": 4, "id_producto": 88, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:00:09.820624-05
89	1	89	4	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 89, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.821460-05:00", "contado_por": 4, "id_producto": 89, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:00:09.822319-05
90	1	90	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.3, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 90, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.3, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.822771-05:00", "contado_por": 3, "id_producto": 90, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.823437-05
91	1	91	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.3, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 91, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.2, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.824197-05:00", "contado_por": 3, "id_producto": 91, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.825366-05
92	1	92	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.3, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 92, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.4, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.826132-05:00", "contado_por": 3, "id_producto": 92, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.82711-05
93	1	93	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.3, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 93, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.3, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.827601-05:00", "contado_por": 3, "id_producto": 93, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.828299-05
94	1	94	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 94, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.828859-05:00", "contado_por": 3, "id_producto": 94, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.829589-05
95	1	95	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.3, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 95, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.3, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.830044-05:00", "contado_por": 3, "id_producto": 95, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.830755-05
96	1	96	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.3, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 96, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.2, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.831643-05:00", "contado_por": 3, "id_producto": 96, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.832775-05
97	1	97	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.3, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 97, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.4, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.833267-05:00", "contado_por": 3, "id_producto": 97, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.833973-05
98	1	98	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.3, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 98, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.3, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.834829-05:00", "contado_por": 3, "id_producto": 98, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.835954-05
99	1	99	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.3, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 99, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.3, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.836662-05:00", "contado_por": 3, "id_producto": 99, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.837571-05
100	1	100	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.4, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 100, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.4, "teorico": 4.4, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.838415-05:00", "contado_por": 3, "id_producto": 100, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.839742-05
101	1	101	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 101, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 13.9, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.840458-05:00", "contado_por": 3, "id_producto": 101, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.841975-05
102	1	102	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 102, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.1, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.842556-05:00", "contado_por": 3, "id_producto": 102, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.843271-05
103	1	103	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 103, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.843697-05:00", "contado_por": 3, "id_producto": 103, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.844282-05
104	1	104	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 104, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.845576-05:00", "contado_por": 3, "id_producto": 104, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.84669-05
105	1	105	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 105, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.847380-05:00", "contado_por": 3, "id_producto": 105, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.848273-05
106	1	106	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 106, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 13.9, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.848767-05:00", "contado_por": 3, "id_producto": 106, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.850041-05
107	1	107	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 4.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 107, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.850618-05:00", "contado_por": 3, "id_producto": 107, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.851604-05
108	1	108	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 108, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.852590-05:00", "contado_por": 3, "id_producto": 108, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.853895-05
109	1	109	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 12.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 109, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 12.0, "teorico": 12.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.854621-05:00", "contado_por": 3, "id_producto": 109, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.856182-05
110	1	110	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 110, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.856931-05:00", "contado_por": 3, "id_producto": 110, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.85785-05
111	1	111	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 111, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 13.9, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.858334-05:00", "contado_por": 3, "id_producto": 111, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.859474-05
112	1	112	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 112, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.1, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.860156-05:00", "contado_por": 3, "id_producto": 112, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.861007-05
113	1	113	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 113, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.861778-05:00", "contado_por": 3, "id_producto": 113, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.862768-05
114	1	114	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 114, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.863469-05:00", "contado_por": 3, "id_producto": 114, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.864481-05
115	1	115	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 115, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.865068-05:00", "contado_por": 3, "id_producto": 115, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.866637-05
116	1	116	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 116, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 13.9, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.867637-05:00", "contado_por": 3, "id_producto": 116, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.868807-05
117	1	117	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 117, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.1, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.869899-05:00", "contado_por": 3, "id_producto": 117, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.870746-05
118	1	118	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 118, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.871358-05:00", "contado_por": 3, "id_producto": 118, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.872059-05
119	1	119	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 119, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.872604-05:00", "contado_por": 3, "id_producto": 119, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.873748-05
120	1	120	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 120, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.874533-05:00", "contado_por": 3, "id_producto": 120, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.875336-05
121	1	121	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 121, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 13.9, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.875905-05:00", "contado_por": 3, "id_producto": 121, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.877196-05
122	1	122	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 122, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.1, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.877962-05:00", "contado_por": 3, "id_producto": 122, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.878778-05
123	1	123	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 123, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.880067-05:00", "contado_por": 3, "id_producto": 123, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.881337-05
124	1	124	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 124, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.881898-05:00", "contado_por": 3, "id_producto": 124, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.882625-05
125	1	125	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 125, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.883114-05:00", "contado_por": 3, "id_producto": 125, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.883799-05
126	1	126	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 126, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 13.9, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.884419-05:00", "contado_por": 3, "id_producto": 126, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.885174-05
127	1	127	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 127, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.1, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.885559-05:00", "contado_por": 3, "id_producto": 127, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.886192-05
128	1	128	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 128, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.887302-05:00", "contado_por": 3, "id_producto": 128, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.888774-05
129	1	129	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 129, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.889565-05:00", "contado_por": 3, "id_producto": 129, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.891309-05
130	1	130	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 130, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.891996-05:00", "contado_por": 3, "id_producto": 130, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.892827-05
131	1	131	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 131, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 13.9, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.893452-05:00", "contado_por": 3, "id_producto": 131, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.894896-05
132	1	132	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 132, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.1, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.895426-05:00", "contado_por": 3, "id_producto": 132, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.896113-05
133	1	133	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 133, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.896560-05:00", "contado_por": 3, "id_producto": 133, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.897402-05
134	1	134	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 14.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 134, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.897818-05:00", "contado_por": 3, "id_producto": 134, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.89836-05
135	1	135	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 3.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 135, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 3.0, "teorico": 3.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.898719-05:00", "contado_por": 3, "id_producto": 135, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.899578-05
136	1	136	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 136, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 7.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.900038-05:00", "contado_por": 3, "id_producto": 136, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.901101-05
137	1	137	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 6.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 137, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 7.0, "teorico": 6.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.902214-05:00", "contado_por": 3, "id_producto": 137, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.903538-05
138	1	138	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 138, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.904900-05:00", "contado_por": 3, "id_producto": 138, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.906093-05
139	1	139	3	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 139, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.906711-05:00", "contado_por": 3, "id_producto": 139, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:00:09.907904-05
140	1	140	2	contar	{"estado": "PENDIENTE", "contado": null, "teorico": 8.0, "version": 1, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": null, "contado_por": null, "id_producto": 140, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": null, "contado_puesto": null, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": null, "contado_puesto_nombre": null}	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.908677-05:00", "contado_por": 2, "id_producto": 140, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:00:09.909386-05
141	1	1	1	revisar	{"estado": "HECHO", "contado": 3.4, "teorico": 3.5, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.698450-05:00", "contado_por": 2, "id_producto": 1, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 3.4, "teorico": 3.5, "version": 3, "id_ronda": 1, "corregido": 3.4, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.698450-05:00", "contado_por": 2, "id_producto": 1, "observacion": "", "revisado_en": "2026-09-28T21:10:21.854798-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.85659-05
142	1	2	1	revisar	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.704515-05:00", "contado_por": 2, "id_producto": 2, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.1, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.1, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.704515-05:00", "contado_por": 2, "id_producto": 2, "observacion": "", "revisado_en": "2026-09-28T21:10:21.865252-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.86686-05
143	1	3	1	revisar	{"estado": "HECHO", "contado": 9.0, "teorico": 9.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.707647-05:00", "contado_por": 2, "id_producto": 3, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 9.0, "teorico": 9.0, "version": 3, "id_ronda": 1, "corregido": 9.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.707647-05:00", "contado_por": 2, "id_producto": 3, "observacion": "", "revisado_en": "2026-09-28T21:10:21.867640-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.868643-05
144	1	4	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.711024-05:00", "contado_por": 2, "id_producto": 4, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.711024-05:00", "contado_por": 2, "id_producto": 4, "observacion": "", "revisado_en": "2026-09-28T21:10:21.869279-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.87031-05
145	1	5	1	revisar	{"estado": "HECHO", "contado": 0.8, "teorico": 0.8, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.713875-05:00", "contado_por": 2, "id_producto": 5, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 0.8, "teorico": 0.8, "version": 3, "id_ronda": 1, "corregido": 0.8, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.713875-05:00", "contado_por": 2, "id_producto": 5, "observacion": "", "revisado_en": "2026-09-28T21:10:21.871127-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.872212-05
146	1	6	1	revisar	{"estado": "HECHO", "contado": 3.9, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.715921-05:00", "contado_por": 2, "id_producto": 6, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 3.9, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 3.9, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.715921-05:00", "contado_por": 2, "id_producto": 6, "observacion": "", "revisado_en": "2026-09-28T21:10:21.873351-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.874316-05
147	1	7	1	revisar	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.717274-05:00", "contado_por": 2, "id_producto": 7, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.1, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.1, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.717274-05:00", "contado_por": 2, "id_producto": 7, "observacion": "", "revisado_en": "2026-09-28T21:10:21.874833-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.875304-05
148	1	8	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.718134-05:00", "contado_por": 2, "id_producto": 8, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.718134-05:00", "contado_por": 2, "id_producto": 8, "observacion": "", "revisado_en": "2026-09-28T21:10:21.875849-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.876492-05
149	1	9	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.720458-05:00", "contado_por": 2, "id_producto": 9, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.720458-05:00", "contado_por": 2, "id_producto": 9, "observacion": "", "revisado_en": "2026-09-28T21:10:21.876971-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.877847-05
150	1	10	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.721600-05:00", "contado_por": 2, "id_producto": 10, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.721600-05:00", "contado_por": 2, "id_producto": 10, "observacion": "", "revisado_en": "2026-09-28T21:10:21.878278-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.878911-05
151	1	11	1	revisar	{"estado": "HECHO", "contado": 3.9, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.722624-05:00", "contado_por": 2, "id_producto": 11, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 3.9, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 3.9, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.722624-05:00", "contado_por": 2, "id_producto": 11, "observacion": "", "revisado_en": "2026-09-28T21:10:21.879466-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.880494-05
152	1	12	1	revisar	{"estado": "HECHO", "contado": 5.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.723615-05:00", "contado_por": 2, "id_producto": 12, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 5.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 5.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.723615-05:00", "contado_por": 2, "id_producto": 12, "observacion": "", "revisado_en": "2026-09-28T21:10:21.881221-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.882207-05
153	1	13	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.724549-05:00", "contado_por": 2, "id_producto": 13, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.724549-05:00", "contado_por": 2, "id_producto": 13, "observacion": "", "revisado_en": "2026-09-28T21:10:21.883562-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.884561-05
154	1	14	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.725293-05:00", "contado_por": 2, "id_producto": 14, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.725293-05:00", "contado_por": 2, "id_producto": 14, "observacion": "", "revisado_en": "2026-09-28T21:10:21.885076-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.885671-05
155	1	15	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.726049-05:00", "contado_por": 2, "id_producto": 15, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.726049-05:00", "contado_por": 2, "id_producto": 15, "observacion": "", "revisado_en": "2026-09-28T21:10:21.886244-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.887047-05
156	1	16	1	revisar	{"estado": "HECHO", "contado": 3.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.727560-05:00", "contado_por": 2, "id_producto": 16, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 3.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 3.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.727560-05:00", "contado_por": 2, "id_producto": 16, "observacion": "", "revisado_en": "2026-09-28T21:10:21.887867-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.88923-05
157	1	17	1	revisar	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.728795-05:00", "contado_por": 2, "id_producto": 17, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.1, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.1, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.728795-05:00", "contado_por": 2, "id_producto": 17, "observacion": "", "revisado_en": "2026-09-28T21:10:21.889864-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.891473-05
158	1	18	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.729755-05:00", "contado_por": 2, "id_producto": 18, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.729755-05:00", "contado_por": 2, "id_producto": 18, "observacion": "", "revisado_en": "2026-09-28T21:10:21.892839-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.894226-05
159	1	19	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.730543-05:00", "contado_por": 2, "id_producto": 19, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.730543-05:00", "contado_por": 2, "id_producto": 19, "observacion": "", "revisado_en": "2026-09-28T21:10:21.895250-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.896428-05
160	1	20	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.731688-05:00", "contado_por": 2, "id_producto": 20, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.731688-05:00", "contado_por": 2, "id_producto": 20, "observacion": "", "revisado_en": "2026-09-28T21:10:21.897172-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.898224-05
161	1	21	1	revisar	{"estado": "HECHO", "contado": 3.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.732698-05:00", "contado_por": 2, "id_producto": 21, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 3.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 3.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.732698-05:00", "contado_por": 2, "id_producto": 21, "observacion": "", "revisado_en": "2026-09-28T21:10:21.898781-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.8997-05
162	1	22	1	revisar	{"estado": "HECHO", "contado": 9.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.733984-05:00", "contado_por": 2, "id_producto": 22, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 9.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 9.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.733984-05:00", "contado_por": 2, "id_producto": 22, "observacion": "", "revisado_en": "2026-09-28T21:10:21.900177-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.900817-05
163	1	23	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.735944-05:00", "contado_por": 2, "id_producto": 23, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.735944-05:00", "contado_por": 2, "id_producto": 23, "observacion": "", "revisado_en": "2026-09-28T21:10:21.901661-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.90263-05
164	1	24	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.738219-05:00", "contado_por": 2, "id_producto": 24, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.738219-05:00", "contado_por": 2, "id_producto": 24, "observacion": "", "revisado_en": "2026-09-28T21:10:21.903181-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.903768-05
165	1	25	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.739381-05:00", "contado_por": 2, "id_producto": 25, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.739381-05:00", "contado_por": 2, "id_producto": 25, "observacion": "", "revisado_en": "2026-09-28T21:10:21.904424-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.905395-05
166	1	26	1	revisar	{"estado": "HECHO", "contado": 3.9, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.740303-05:00", "contado_por": 2, "id_producto": 26, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 3.9, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 3.9, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.740303-05:00", "contado_por": 2, "id_producto": 26, "observacion": "", "revisado_en": "2026-09-28T21:10:21.905773-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.91297-05
167	1	27	1	revisar	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.742107-05:00", "contado_por": 2, "id_producto": 27, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.1, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.1, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.742107-05:00", "contado_por": 2, "id_producto": 27, "observacion": "", "revisado_en": "2026-09-28T21:10:21.913720-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.914689-05
168	1	28	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.743074-05:00", "contado_por": 2, "id_producto": 28, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.743074-05:00", "contado_por": 2, "id_producto": 28, "observacion": "", "revisado_en": "2026-09-28T21:10:21.915441-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.916171-05
169	1	29	1	revisar	{"estado": "HECHO", "contado": 7.0, "teorico": 7.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.744067-05:00", "contado_por": 2, "id_producto": 29, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 7.0, "teorico": 7.0, "version": 3, "id_ronda": 1, "corregido": 7.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.744067-05:00", "contado_por": 2, "id_producto": 29, "observacion": "", "revisado_en": "2026-09-28T21:10:21.916666-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.917657-05
170	1	30	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.744970-05:00", "contado_por": 2, "id_producto": 30, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.744970-05:00", "contado_por": 2, "id_producto": 30, "observacion": "", "revisado_en": "2026-09-28T21:10:21.918069-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.918578-05
171	1	31	1	revisar	{"estado": "HECHO", "contado": 7.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.745907-05:00", "contado_por": 2, "id_producto": 31, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 7.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 7.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.745907-05:00", "contado_por": 2, "id_producto": 31, "observacion": "", "revisado_en": "2026-09-28T21:10:21.918912-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.91981-05
172	1	32	1	revisar	{"estado": "HECHO", "contado": 9.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.747573-05:00", "contado_por": 2, "id_producto": 32, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 9.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 9.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.747573-05:00", "contado_por": 2, "id_producto": 32, "observacion": "", "revisado_en": "2026-09-28T21:10:21.920315-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.920991-05
173	1	33	1	revisar	{"estado": "HECHO", "contado": 7.0, "teorico": 7.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.749038-05:00", "contado_por": 2, "id_producto": 33, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 7.0, "teorico": 7.0, "version": 3, "id_ronda": 1, "corregido": 7.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.749038-05:00", "contado_por": 2, "id_producto": 33, "observacion": "", "revisado_en": "2026-09-28T21:10:21.921635-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.922445-05
174	1	34	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.749941-05:00", "contado_por": 2, "id_producto": 34, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.749941-05:00", "contado_por": 2, "id_producto": 34, "observacion": "", "revisado_en": "2026-09-28T21:10:21.922848-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.923366-05
175	1	35	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.750781-05:00", "contado_por": 2, "id_producto": 35, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.750781-05:00", "contado_por": 2, "id_producto": 35, "observacion": "", "revisado_en": "2026-09-28T21:10:21.923685-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.924537-05
176	1	36	1	revisar	{"estado": "HECHO", "contado": 1.0, "teorico": 2.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.751800-05:00", "contado_por": 2, "id_producto": 36, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 1.0, "teorico": 2.0, "version": 3, "id_ronda": 1, "corregido": 1.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.751800-05:00", "contado_por": 2, "id_producto": 36, "observacion": "", "revisado_en": "2026-09-28T21:10:21.925186-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.926163-05
177	1	37	1	revisar	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.752616-05:00", "contado_por": 2, "id_producto": 37, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.1, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.1, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.752616-05:00", "contado_por": 2, "id_producto": 37, "observacion": "", "revisado_en": "2026-09-28T21:10:21.926629-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.927195-05
178	1	38	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.753342-05:00", "contado_por": 2, "id_producto": 38, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.753342-05:00", "contado_por": 2, "id_producto": 38, "observacion": "", "revisado_en": "2026-09-28T21:10:21.927917-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.929192-05
179	1	39	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.754085-05:00", "contado_por": 2, "id_producto": 39, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.754085-05:00", "contado_por": 2, "id_producto": 39, "observacion": "", "revisado_en": "2026-09-28T21:10:21.929906-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.93054-05
180	1	40	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.756102-05:00", "contado_por": 2, "id_producto": 40, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.756102-05:00", "contado_por": 2, "id_producto": 40, "observacion": "", "revisado_en": "2026-09-28T21:10:21.930941-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.931531-05
181	1	41	1	revisar	{"estado": "HECHO", "contado": 3.9, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.757338-05:00", "contado_por": 2, "id_producto": 41, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 3.9, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 3.9, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.757338-05:00", "contado_por": 2, "id_producto": 41, "observacion": "", "revisado_en": "2026-09-28T21:10:21.931929-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.932713-05
182	1	42	1	revisar	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.759481-05:00", "contado_por": 2, "id_producto": 42, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.1, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.1, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.759481-05:00", "contado_por": 2, "id_producto": 42, "observacion": "", "revisado_en": "2026-09-28T21:10:21.933700-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.935078-05
183	1	43	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.760818-05:00", "contado_por": 2, "id_producto": 43, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.760818-05:00", "contado_por": 2, "id_producto": 43, "observacion": "", "revisado_en": "2026-09-28T21:10:21.936010-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.938082-05
184	1	44	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.762620-05:00", "contado_por": 2, "id_producto": 44, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.762620-05:00", "contado_por": 2, "id_producto": 44, "observacion": "", "revisado_en": "2026-09-28T21:10:21.939455-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.940816-05
185	1	45	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.763889-05:00", "contado_por": 2, "id_producto": 45, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.763889-05:00", "contado_por": 2, "id_producto": 45, "observacion": "", "revisado_en": "2026-09-28T21:10:21.941673-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.942876-05
186	1	46	1	revisar	{"estado": "HECHO", "contado": 3.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.764979-05:00", "contado_por": 2, "id_producto": 46, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 3.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 3.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.764979-05:00", "contado_por": 2, "id_producto": 46, "observacion": "", "revisado_en": "2026-09-28T21:10:21.943888-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.945177-05
187	1	47	1	revisar	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.765885-05:00", "contado_por": 2, "id_producto": 47, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.1, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.1, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.765885-05:00", "contado_por": 2, "id_producto": 47, "observacion": "", "revisado_en": "2026-09-28T21:10:21.946178-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.947171-05
188	1	48	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.766729-05:00", "contado_por": 2, "id_producto": 48, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.766729-05:00", "contado_por": 2, "id_producto": 48, "observacion": "", "revisado_en": "2026-09-28T21:10:21.948141-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.949258-05
189	1	49	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.767505-05:00", "contado_por": 2, "id_producto": 49, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.767505-05:00", "contado_por": 2, "id_producto": 49, "observacion": "", "revisado_en": "2026-09-28T21:10:21.950061-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.953567-05
190	1	50	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.768726-05:00", "contado_por": 2, "id_producto": 50, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.768726-05:00", "contado_por": 2, "id_producto": 50, "observacion": "", "revisado_en": "2026-09-28T21:10:21.956225-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.957068-05
191	1	51	1	revisar	{"estado": "HECHO", "contado": 3.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.770455-05:00", "contado_por": 2, "id_producto": 51, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 3.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 3.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.770455-05:00", "contado_por": 2, "id_producto": 51, "observacion": "", "revisado_en": "2026-09-28T21:10:21.957620-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.958275-05
192	1	52	1	revisar	{"estado": "HECHO", "contado": 5.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.772509-05:00", "contado_por": 2, "id_producto": 52, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 5.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 5.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.772509-05:00", "contado_por": 2, "id_producto": 52, "observacion": "", "revisado_en": "2026-09-28T21:10:21.958625-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.9592-05
193	1	53	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.773847-05:00", "contado_por": 2, "id_producto": 53, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.773847-05:00", "contado_por": 2, "id_producto": 53, "observacion": "", "revisado_en": "2026-09-28T21:10:21.959545-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.960095-05
194	1	54	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.774898-05:00", "contado_por": 2, "id_producto": 54, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.774898-05:00", "contado_por": 2, "id_producto": 54, "observacion": "", "revisado_en": "2026-09-28T21:10:21.960787-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.961443-05
195	1	55	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.776621-05:00", "contado_por": 2, "id_producto": 55, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.776621-05:00", "contado_por": 2, "id_producto": 55, "observacion": "", "revisado_en": "2026-09-28T21:10:21.962082-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.963022-05
196	1	56	1	revisar	{"estado": "HECHO", "contado": 3.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.777703-05:00", "contado_por": 2, "id_producto": 56, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 3.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 3.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.777703-05:00", "contado_por": 2, "id_producto": 56, "observacion": "", "revisado_en": "2026-09-28T21:10:21.963617-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.964126-05
197	1	57	1	revisar	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.778566-05:00", "contado_por": 2, "id_producto": 57, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.1, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.1, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.778566-05:00", "contado_por": 2, "id_producto": 57, "observacion": "", "revisado_en": "2026-09-28T21:10:21.964614-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.965274-05
198	1	58	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.779620-05:00", "contado_por": 2, "id_producto": 58, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.779620-05:00", "contado_por": 2, "id_producto": 58, "observacion": "", "revisado_en": "2026-09-28T21:10:21.965688-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.966437-05
199	1	59	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.780466-05:00", "contado_por": 2, "id_producto": 59, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.780466-05:00", "contado_por": 2, "id_producto": 59, "observacion": "", "revisado_en": "2026-09-28T21:10:21.967012-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.967571-05
200	1	60	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.781381-05:00", "contado_por": 2, "id_producto": 60, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.781381-05:00", "contado_por": 2, "id_producto": 60, "observacion": "", "revisado_en": "2026-09-28T21:10:21.967983-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.968494-05
201	1	61	1	revisar	{"estado": "HECHO", "contado": 7.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.782881-05:00", "contado_por": 2, "id_producto": 61, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 7.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 7.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.782881-05:00", "contado_por": 2, "id_producto": 61, "observacion": "", "revisado_en": "2026-09-28T21:10:21.969005-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.969646-05
202	1	62	1	revisar	{"estado": "HECHO", "contado": 5.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.784588-05:00", "contado_por": 2, "id_producto": 62, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 5.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 5.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.784588-05:00", "contado_por": 2, "id_producto": 62, "observacion": "", "revisado_en": "2026-09-28T21:10:21.970176-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.970988-05
203	1	63	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.786780-05:00", "contado_por": 2, "id_producto": 63, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.786780-05:00", "contado_por": 2, "id_producto": 63, "observacion": "", "revisado_en": "2026-09-28T21:10:21.971656-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.972635-05
204	1	64	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.788523-05:00", "contado_por": 2, "id_producto": 64, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.788523-05:00", "contado_por": 2, "id_producto": 64, "observacion": "", "revisado_en": "2026-09-28T21:10:21.973299-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.973951-05
205	1	65	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.790731-05:00", "contado_por": 2, "id_producto": 65, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.790731-05:00", "contado_por": 2, "id_producto": 65, "observacion": "", "revisado_en": "2026-09-28T21:10:21.974617-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.975238-05
206	1	66	1	revisar	{"estado": "HECHO", "contado": 3.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.791977-05:00", "contado_por": 2, "id_producto": 66, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 3.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 3.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.791977-05:00", "contado_por": 2, "id_producto": 66, "observacion": "", "revisado_en": "2026-09-28T21:10:21.975646-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.97639-05
207	1	67	1	revisar	{"estado": "HECHO", "contado": 5.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.793047-05:00", "contado_por": 2, "id_producto": 67, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 5.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 5.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.793047-05:00", "contado_por": 2, "id_producto": 67, "observacion": "", "revisado_en": "2026-09-28T21:10:21.976907-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.977847-05
208	1	68	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.793879-05:00", "contado_por": 2, "id_producto": 68, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.793879-05:00", "contado_por": 2, "id_producto": 68, "observacion": "", "revisado_en": "2026-09-28T21:10:21.978321-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.979147-05
209	1	69	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.794688-05:00", "contado_por": 2, "id_producto": 69, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.794688-05:00", "contado_por": 2, "id_producto": 69, "observacion": "", "revisado_en": "2026-09-28T21:10:21.979642-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.980527-05
210	1	70	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.795501-05:00", "contado_por": 2, "id_producto": 70, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.795501-05:00", "contado_por": 2, "id_producto": 70, "observacion": "", "revisado_en": "2026-09-28T21:10:21.981129-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.981945-05
211	1	71	1	revisar	{"estado": "HECHO", "contado": 3.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.797188-05:00", "contado_por": 2, "id_producto": 71, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 3.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 3.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.797188-05:00", "contado_por": 2, "id_producto": 71, "observacion": "", "revisado_en": "2026-09-28T21:10:21.982506-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.983416-05
212	1	72	1	revisar	{"estado": "HECHO", "contado": 15.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.798440-05:00", "contado_por": 2, "id_producto": 72, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 15.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 15.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.798440-05:00", "contado_por": 2, "id_producto": 72, "observacion": "", "revisado_en": "2026-09-28T21:10:21.984111-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.985221-05
213	1	73	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.799340-05:00", "contado_por": 2, "id_producto": 73, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.799340-05:00", "contado_por": 2, "id_producto": 73, "observacion": "", "revisado_en": "2026-09-28T21:10:21.985772-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.986268-05
214	1	74	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.800433-05:00", "contado_por": 2, "id_producto": 74, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.800433-05:00", "contado_por": 2, "id_producto": 74, "observacion": "", "revisado_en": "2026-09-28T21:10:21.986666-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:21.98722-05
215	1	75	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.801453-05:00", "contado_por": 4, "id_producto": 75, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.801453-05:00", "contado_por": 4, "id_producto": 75, "observacion": "", "revisado_en": "2026-09-28T21:10:21.987840-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:10:21.988778-05
216	1	76	1	revisar	{"estado": "HECHO", "contado": 7.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.802305-05:00", "contado_por": 4, "id_producto": 76, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	{"estado": "REVISADO", "contado": 7.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 7.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.802305-05:00", "contado_por": 4, "id_producto": 76, "observacion": "", "revisado_en": "2026-09-28T21:10:21.989262-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:10:21.990168-05
217	1	77	1	revisar	{"estado": "HECHO", "contado": 15.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.803669-05:00", "contado_por": 4, "id_producto": 77, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	{"estado": "REVISADO", "contado": 15.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 15.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.803669-05:00", "contado_por": 4, "id_producto": 77, "observacion": "", "revisado_en": "2026-09-28T21:10:21.990695-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:10:21.991424-05
218	1	78	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.806142-05:00", "contado_por": 4, "id_producto": 78, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.806142-05:00", "contado_por": 4, "id_producto": 78, "observacion": "", "revisado_en": "2026-09-28T21:10:21.991922-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:10:21.992542-05
219	1	79	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.807883-05:00", "contado_por": 4, "id_producto": 79, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.807883-05:00", "contado_por": 4, "id_producto": 79, "observacion": "", "revisado_en": "2026-09-28T21:10:21.992909-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:10:21.993401-05
220	1	80	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.808966-05:00", "contado_por": 4, "id_producto": 80, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.808966-05:00", "contado_por": 4, "id_producto": 80, "observacion": "", "revisado_en": "2026-09-28T21:10:21.993722-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:10:21.994296-05
221	1	81	1	revisar	{"estado": "HECHO", "contado": 11.0, "teorico": 12.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.810182-05:00", "contado_por": 4, "id_producto": 81, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	{"estado": "REVISADO", "contado": 11.0, "teorico": 12.0, "version": 3, "id_ronda": 1, "corregido": 11.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.810182-05:00", "contado_por": 4, "id_producto": 81, "observacion": "", "revisado_en": "2026-09-28T21:10:21.994699-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:10:21.995252-05
222	1	82	1	revisar	{"estado": "HECHO", "contado": 9.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.811762-05:00", "contado_por": 4, "id_producto": 82, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	{"estado": "REVISADO", "contado": 9.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 9.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.811762-05:00", "contado_por": 4, "id_producto": 82, "observacion": "", "revisado_en": "2026-09-28T21:10:21.995691-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:10:21.996714-05
223	1	83	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.812693-05:00", "contado_por": 4, "id_producto": 83, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.812693-05:00", "contado_por": 4, "id_producto": 83, "observacion": "", "revisado_en": "2026-09-28T21:10:21.997152-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:10:21.99807-05
224	1	84	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.813895-05:00", "contado_por": 4, "id_producto": 84, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.813895-05:00", "contado_por": 4, "id_producto": 84, "observacion": "", "revisado_en": "2026-09-28T21:10:21.998633-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:10:21.999478-05
225	1	85	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.814860-05:00", "contado_por": 4, "id_producto": 85, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.814860-05:00", "contado_por": 4, "id_producto": 85, "observacion": "", "revisado_en": "2026-09-28T21:10:21.999900-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:10:22.000829-05
226	1	86	1	revisar	{"estado": "HECHO", "contado": 7.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.815893-05:00", "contado_por": 4, "id_producto": 86, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	{"estado": "REVISADO", "contado": 7.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 7.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.815893-05:00", "contado_por": 4, "id_producto": 86, "observacion": "", "revisado_en": "2026-09-28T21:10:22.001311-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:10:22.002051-05
227	1	87	1	revisar	{"estado": "HECHO", "contado": 9.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.817418-05:00", "contado_por": 4, "id_producto": 87, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	{"estado": "REVISADO", "contado": 9.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 9.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.817418-05:00", "contado_por": 4, "id_producto": 87, "observacion": "", "revisado_en": "2026-09-28T21:10:22.002553-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:10:22.00332-05
228	1	88	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.819146-05:00", "contado_por": 4, "id_producto": 88, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.819146-05:00", "contado_por": 4, "id_producto": 88, "observacion": "", "revisado_en": "2026-09-28T21:10:22.003709-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:10:22.004162-05
229	1	89	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.821460-05:00", "contado_por": 4, "id_producto": 89, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.821460-05:00", "contado_por": 4, "id_producto": 89, "observacion": "", "revisado_en": "2026-09-28T21:10:22.004478-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Mesero", "contado_perfil": 4, "contado_puesto": 1, "justificado_en": null, "justificado_por": null, "puesto_asignado": 1, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Mesero"}	2026-09-28 21:10:22.004888-05
230	1	90	1	revisar	{"estado": "HECHO", "contado": 4.3, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.822771-05:00", "contado_por": 3, "id_producto": 90, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 4.3, "teorico": 4.3, "version": 3, "id_ronda": 1, "corregido": 4.3, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.822771-05:00", "contado_por": 3, "id_producto": 90, "observacion": "", "revisado_en": "2026-09-28T21:10:22.005404-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.005975-05
231	1	91	1	revisar	{"estado": "HECHO", "contado": 4.2, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.824197-05:00", "contado_por": 3, "id_producto": 91, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 4.2, "teorico": 4.3, "version": 3, "id_ronda": 1, "corregido": 4.2, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.824197-05:00", "contado_por": 3, "id_producto": 91, "observacion": "", "revisado_en": "2026-09-28T21:10:22.006422-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.00717-05
232	1	92	1	revisar	{"estado": "HECHO", "contado": 4.4, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.826132-05:00", "contado_por": 3, "id_producto": 92, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 4.4, "teorico": 4.3, "version": 3, "id_ronda": 1, "corregido": 4.4, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.826132-05:00", "contado_por": 3, "id_producto": 92, "observacion": "", "revisado_en": "2026-09-28T21:10:22.007850-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.00873-05
233	1	93	1	revisar	{"estado": "HECHO", "contado": 4.3, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.827601-05:00", "contado_por": 3, "id_producto": 93, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 4.3, "teorico": 4.3, "version": 3, "id_ronda": 1, "corregido": 4.3, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.827601-05:00", "contado_por": 3, "id_producto": 93, "observacion": "", "revisado_en": "2026-09-28T21:10:22.009329-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.01012-05
234	1	94	1	revisar	{"estado": "HECHO", "contado": 4.0, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.828859-05:00", "contado_por": 3, "id_producto": 94, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 4.0, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.828859-05:00", "contado_por": 3, "id_producto": 94, "observacion": "", "revisado_en": "2026-09-28T21:10:22.010593-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.011383-05
235	1	95	1	revisar	{"estado": "HECHO", "contado": 4.3, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.830044-05:00", "contado_por": 3, "id_producto": 95, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 4.3, "teorico": 4.3, "version": 3, "id_ronda": 1, "corregido": 4.3, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.830044-05:00", "contado_por": 3, "id_producto": 95, "observacion": "", "revisado_en": "2026-09-28T21:10:22.011933-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.012682-05
236	1	96	1	revisar	{"estado": "HECHO", "contado": 4.2, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.831643-05:00", "contado_por": 3, "id_producto": 96, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 4.2, "teorico": 4.3, "version": 3, "id_ronda": 1, "corregido": 4.2, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.831643-05:00", "contado_por": 3, "id_producto": 96, "observacion": "", "revisado_en": "2026-09-28T21:10:22.013397-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.014257-05
237	1	97	1	revisar	{"estado": "HECHO", "contado": 4.4, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.833267-05:00", "contado_por": 3, "id_producto": 97, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 4.4, "teorico": 4.3, "version": 3, "id_ronda": 1, "corregido": 4.4, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.833267-05:00", "contado_por": 3, "id_producto": 97, "observacion": "", "revisado_en": "2026-09-28T21:10:22.014620-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.01536-05
238	1	98	1	revisar	{"estado": "HECHO", "contado": 4.3, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.834829-05:00", "contado_por": 3, "id_producto": 98, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 4.3, "teorico": 4.3, "version": 3, "id_ronda": 1, "corregido": 4.3, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.834829-05:00", "contado_por": 3, "id_producto": 98, "observacion": "", "revisado_en": "2026-09-28T21:10:22.015705-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.01621-05
239	1	99	1	revisar	{"estado": "HECHO", "contado": 4.3, "teorico": 4.3, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.836662-05:00", "contado_por": 3, "id_producto": 99, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 4.3, "teorico": 4.3, "version": 3, "id_ronda": 1, "corregido": 4.3, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.836662-05:00", "contado_por": 3, "id_producto": 99, "observacion": "", "revisado_en": "2026-09-28T21:10:22.016743-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.017744-05
240	1	100	1	revisar	{"estado": "HECHO", "contado": 4.4, "teorico": 4.4, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.838415-05:00", "contado_por": 3, "id_producto": 100, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 4.4, "teorico": 4.4, "version": 3, "id_ronda": 1, "corregido": 4.4, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.838415-05:00", "contado_por": 3, "id_producto": 100, "observacion": "", "revisado_en": "2026-09-28T21:10:22.018171-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.018924-05
241	1	101	1	revisar	{"estado": "HECHO", "contado": 13.9, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.840458-05:00", "contado_por": 3, "id_producto": 101, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 13.9, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 13.9, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.840458-05:00", "contado_por": 3, "id_producto": 101, "observacion": "", "revisado_en": "2026-09-28T21:10:22.019304-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.019815-05
242	1	102	1	revisar	{"estado": "HECHO", "contado": 14.1, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.842556-05:00", "contado_por": 3, "id_producto": 102, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.1, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.1, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.842556-05:00", "contado_por": 3, "id_producto": 102, "observacion": "", "revisado_en": "2026-09-28T21:10:22.020410-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.021274-05
243	1	103	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.843697-05:00", "contado_por": 3, "id_producto": 103, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.843697-05:00", "contado_por": 3, "id_producto": 103, "observacion": "", "revisado_en": "2026-09-28T21:10:22.021766-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.022526-05
244	1	104	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.845576-05:00", "contado_por": 3, "id_producto": 104, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.845576-05:00", "contado_por": 3, "id_producto": 104, "observacion": "", "revisado_en": "2026-09-28T21:10:22.022899-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.023589-05
245	1	105	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.847380-05:00", "contado_por": 3, "id_producto": 105, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.847380-05:00", "contado_por": 3, "id_producto": 105, "observacion": "", "revisado_en": "2026-09-28T21:10:22.024207-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.024878-05
246	1	106	1	revisar	{"estado": "HECHO", "contado": 13.9, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.848767-05:00", "contado_por": 3, "id_producto": 106, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 13.9, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 13.9, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.848767-05:00", "contado_por": 3, "id_producto": 106, "observacion": "", "revisado_en": "2026-09-28T21:10:22.025184-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.025709-05
247	1	107	1	revisar	{"estado": "HECHO", "contado": 4.1, "teorico": 4.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.850618-05:00", "contado_por": 3, "id_producto": 107, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 4.1, "teorico": 4.0, "version": 3, "id_ronda": 1, "corregido": 4.1, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.850618-05:00", "contado_por": 3, "id_producto": 107, "observacion": "", "revisado_en": "2026-09-28T21:10:22.026031-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.026543-05
248	1	108	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.852590-05:00", "contado_por": 3, "id_producto": 108, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.852590-05:00", "contado_por": 3, "id_producto": 108, "observacion": "", "revisado_en": "2026-09-28T21:10:22.027681-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.028657-05
249	1	109	1	revisar	{"estado": "HECHO", "contado": 12.0, "teorico": 12.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.854621-05:00", "contado_por": 3, "id_producto": 109, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 12.0, "teorico": 12.0, "version": 3, "id_ronda": 1, "corregido": 12.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.854621-05:00", "contado_por": 3, "id_producto": 109, "observacion": "", "revisado_en": "2026-09-28T21:10:22.029272-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.03024-05
250	1	110	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.856931-05:00", "contado_por": 3, "id_producto": 110, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.856931-05:00", "contado_por": 3, "id_producto": 110, "observacion": "", "revisado_en": "2026-09-28T21:10:22.030901-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.031499-05
251	1	111	1	revisar	{"estado": "HECHO", "contado": 13.9, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.858334-05:00", "contado_por": 3, "id_producto": 111, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 13.9, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 13.9, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.858334-05:00", "contado_por": 3, "id_producto": 111, "observacion": "", "revisado_en": "2026-09-28T21:10:22.032403-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.033293-05
252	1	112	1	revisar	{"estado": "HECHO", "contado": 14.1, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.860156-05:00", "contado_por": 3, "id_producto": 112, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.1, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.1, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.860156-05:00", "contado_por": 3, "id_producto": 112, "observacion": "", "revisado_en": "2026-09-28T21:10:22.033801-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.034607-05
253	1	113	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.861778-05:00", "contado_por": 3, "id_producto": 113, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.861778-05:00", "contado_por": 3, "id_producto": 113, "observacion": "", "revisado_en": "2026-09-28T21:10:22.035097-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.03595-05
254	1	114	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.863469-05:00", "contado_por": 3, "id_producto": 114, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.863469-05:00", "contado_por": 3, "id_producto": 114, "observacion": "", "revisado_en": "2026-09-28T21:10:22.036387-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.036947-05
255	1	115	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.865068-05:00", "contado_por": 3, "id_producto": 115, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.865068-05:00", "contado_por": 3, "id_producto": 115, "observacion": "", "revisado_en": "2026-09-28T21:10:22.037339-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.037865-05
256	1	116	1	revisar	{"estado": "HECHO", "contado": 13.9, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.867637-05:00", "contado_por": 3, "id_producto": 116, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 13.9, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 13.9, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.867637-05:00", "contado_por": 3, "id_producto": 116, "observacion": "", "revisado_en": "2026-09-28T21:10:22.038210-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.039058-05
257	1	117	1	revisar	{"estado": "HECHO", "contado": 14.1, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.869899-05:00", "contado_por": 3, "id_producto": 117, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.1, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.1, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.869899-05:00", "contado_por": 3, "id_producto": 117, "observacion": "", "revisado_en": "2026-09-28T21:10:22.039533-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.040388-05
258	1	118	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.871358-05:00", "contado_por": 3, "id_producto": 118, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.871358-05:00", "contado_por": 3, "id_producto": 118, "observacion": "", "revisado_en": "2026-09-28T21:10:22.040882-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.041556-05
259	1	119	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.872604-05:00", "contado_por": 3, "id_producto": 119, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.872604-05:00", "contado_por": 3, "id_producto": 119, "observacion": "", "revisado_en": "2026-09-28T21:10:22.042056-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.042758-05
260	1	120	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.874533-05:00", "contado_por": 3, "id_producto": 120, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.874533-05:00", "contado_por": 3, "id_producto": 120, "observacion": "", "revisado_en": "2026-09-28T21:10:22.043407-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.044229-05
261	1	121	1	revisar	{"estado": "HECHO", "contado": 13.9, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.875905-05:00", "contado_por": 3, "id_producto": 121, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 13.9, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 13.9, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.875905-05:00", "contado_por": 3, "id_producto": 121, "observacion": "", "revisado_en": "2026-09-28T21:10:22.044601-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.04518-05
262	1	122	1	revisar	{"estado": "HECHO", "contado": 14.1, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.877962-05:00", "contado_por": 3, "id_producto": 122, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.1, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.1, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.877962-05:00", "contado_por": 3, "id_producto": 122, "observacion": "", "revisado_en": "2026-09-28T21:10:22.045546-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.046125-05
263	1	123	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.880067-05:00", "contado_por": 3, "id_producto": 123, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.880067-05:00", "contado_por": 3, "id_producto": 123, "observacion": "", "revisado_en": "2026-09-28T21:10:22.046483-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.047136-05
264	1	124	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.881898-05:00", "contado_por": 3, "id_producto": 124, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.881898-05:00", "contado_por": 3, "id_producto": 124, "observacion": "", "revisado_en": "2026-09-28T21:10:22.047802-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.0488-05
265	1	125	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.883114-05:00", "contado_por": 3, "id_producto": 125, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.883114-05:00", "contado_por": 3, "id_producto": 125, "observacion": "", "revisado_en": "2026-09-28T21:10:22.049193-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.049745-05
266	1	126	1	revisar	{"estado": "HECHO", "contado": 13.9, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.884419-05:00", "contado_por": 3, "id_producto": 126, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 13.9, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 13.9, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.884419-05:00", "contado_por": 3, "id_producto": 126, "observacion": "", "revisado_en": "2026-09-28T21:10:22.050124-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.050683-05
267	1	127	1	revisar	{"estado": "HECHO", "contado": 14.1, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.885559-05:00", "contado_por": 3, "id_producto": 127, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.1, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.1, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.885559-05:00", "contado_por": 3, "id_producto": 127, "observacion": "", "revisado_en": "2026-09-28T21:10:22.051041-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.051655-05
268	1	128	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.887302-05:00", "contado_por": 3, "id_producto": 128, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.887302-05:00", "contado_por": 3, "id_producto": 128, "observacion": "", "revisado_en": "2026-09-28T21:10:22.052099-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.052645-05
269	1	129	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.889565-05:00", "contado_por": 3, "id_producto": 129, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.889565-05:00", "contado_por": 3, "id_producto": 129, "observacion": "", "revisado_en": "2026-09-28T21:10:22.053000-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.053568-05
270	1	130	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.891996-05:00", "contado_por": 3, "id_producto": 130, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.891996-05:00", "contado_por": 3, "id_producto": 130, "observacion": "", "revisado_en": "2026-09-28T21:10:22.054054-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.054771-05
271	1	131	1	revisar	{"estado": "HECHO", "contado": 13.9, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.893452-05:00", "contado_por": 3, "id_producto": 131, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 13.9, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 13.9, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.893452-05:00", "contado_por": 3, "id_producto": 131, "observacion": "", "revisado_en": "2026-09-28T21:10:22.055123-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.056195-05
272	1	132	1	revisar	{"estado": "HECHO", "contado": 14.1, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.895426-05:00", "contado_por": 3, "id_producto": 132, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.1, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.1, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.895426-05:00", "contado_por": 3, "id_producto": 132, "observacion": "", "revisado_en": "2026-09-28T21:10:22.056759-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.057965-05
273	1	133	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.896560-05:00", "contado_por": 3, "id_producto": 133, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.896560-05:00", "contado_por": 3, "id_producto": 133, "observacion": "", "revisado_en": "2026-09-28T21:10:22.058367-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.058982-05
274	1	134	1	revisar	{"estado": "HECHO", "contado": 14.0, "teorico": 14.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.897818-05:00", "contado_por": 3, "id_producto": 134, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 14.0, "teorico": 14.0, "version": 3, "id_ronda": 1, "corregido": 14.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.897818-05:00", "contado_por": 3, "id_producto": 134, "observacion": "", "revisado_en": "2026-09-28T21:10:22.059533-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.060089-05
275	1	135	1	revisar	{"estado": "HECHO", "contado": 3.0, "teorico": 3.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.898719-05:00", "contado_por": 3, "id_producto": 135, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 3.0, "teorico": 3.0, "version": 3, "id_ronda": 1, "corregido": 3.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.898719-05:00", "contado_por": 3, "id_producto": 135, "observacion": "", "revisado_en": "2026-09-28T21:10:22.060424-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.060868-05
276	1	136	1	revisar	{"estado": "HECHO", "contado": 7.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.900038-05:00", "contado_por": 3, "id_producto": 136, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 7.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 7.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.900038-05:00", "contado_por": 3, "id_producto": 136, "observacion": "", "revisado_en": "2026-09-28T21:10:22.061362-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.06219-05
277	1	137	1	revisar	{"estado": "HECHO", "contado": 7.0, "teorico": 6.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.902214-05:00", "contado_por": 3, "id_producto": 137, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 7.0, "teorico": 6.0, "version": 3, "id_ronda": 1, "corregido": 7.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.902214-05:00", "contado_por": 3, "id_producto": 137, "observacion": "", "revisado_en": "2026-09-28T21:10:22.062662-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.063284-05
278	1	138	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.904900-05:00", "contado_por": 3, "id_producto": 138, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.904900-05:00", "contado_por": 3, "id_producto": 138, "observacion": "", "revisado_en": "2026-09-28T21:10:22.063899-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.064743-05
279	1	139	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.906711-05:00", "contado_por": 3, "id_producto": 139, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.906711-05:00", "contado_por": 3, "id_producto": 139, "observacion": "", "revisado_en": "2026-09-28T21:10:22.065301-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Bartender", "contado_perfil": 4, "contado_puesto": 2, "justificado_en": null, "justificado_por": null, "puesto_asignado": 2, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Bartender"}	2026-09-28 21:10:22.066193-05
280	1	140	1	revisar	{"estado": "HECHO", "contado": 8.0, "teorico": 8.0, "version": 2, "id_ronda": 1, "corregido": null, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.908677-05:00", "contado_por": 2, "id_producto": 140, "observacion": "", "revisado_en": null, "revisado_por": null, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	{"estado": "REVISADO", "contado": 8.0, "teorico": 8.0, "version": 3, "id_ronda": 1, "corregido": 8.0, "asignado_a": null, "contado_en": "2026-09-28T21:00:09.908677-05:00", "contado_por": 2, "id_producto": 140, "observacion": "", "revisado_en": "2026-09-28T21:10:22.066741-05:00", "revisado_por": 1, "justificacion": "", "puesto_nombre": "Cocina", "contado_perfil": 4, "contado_puesto": 3, "justificado_en": null, "justificado_por": null, "puesto_asignado": 3, "contado_perfil_nombre": "Miembro de equipo", "contado_puesto_nombre": "Cocina"}	2026-09-28 21:10:22.067364-05
\.


--
-- Data for Name: inventario_evento; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventario_evento (id_evento, id_local, id_jornada, id_producto, cantidad, motivo, origen, id_origen, registrado_en) FROM stdin;
1	1	8	107	-1.600	VENTA_SALON	MOVIMIENTO	6	2026-09-28 20:51:28.79342-05
2	1	8	82	-1.000	VENTA_SALON	MOVIMIENTO	6	2026-09-28 20:51:28.795747-05
3	1	8	135	-1.000	VENTA_SALON	MOVIMIENTO	6	2026-09-28 20:51:28.796528-05
4	1	8	36	-1.000	VENTA_SALON	MOVIMIENTO	6	2026-09-28 20:51:28.797266-05
5	1	8	109	-0.400	VENTA_SALON	MOVIMIENTO	7	2026-09-28 20:51:28.816311-05
6	1	9	107	-1.800	VENTA_SALON	MOVIMIENTO	8	2026-09-28 20:51:28.852028-05
7	1	9	82	-2.000	VENTA_SALON	MOVIMIENTO	8	2026-09-28 20:51:28.852474-05
8	1	9	135	-1.000	VENTA_SALON	MOVIMIENTO	8	2026-09-28 20:51:28.852766-05
9	1	9	36	-1.000	VENTA_SALON	MOVIMIENTO	8	2026-09-28 20:51:28.853048-05
10	1	9	109	-0.400	VENTA_SALON	MOVIMIENTO	9	2026-09-28 20:51:28.861102-05
11	1	9	81	-1.000	VENTA_SALON	MOVIMIENTO	9	2026-09-28 20:51:28.861719-05
12	1	9	137	-1.000	VENTA_SALON	MOVIMIENTO	9	2026-09-28 20:51:28.862152-05
13	1	10	107	-2.000	VENTA_SALON	MOVIMIENTO	10	2026-09-28 20:51:28.884195-05
14	1	10	82	-1.000	VENTA_SALON	MOVIMIENTO	10	2026-09-28 20:51:28.885087-05
15	1	10	135	-1.000	VENTA_SALON	MOVIMIENTO	10	2026-09-28 20:51:28.885743-05
16	1	10	36	-1.000	VENTA_SALON	MOVIMIENTO	10	2026-09-28 20:51:28.886112-05
17	1	10	109	-0.600	VENTA_SALON	MOVIMIENTO	11	2026-09-28 20:51:28.890412-05
18	1	11	107	-2.200	VENTA_SALON	MOVIMIENTO	12	2026-09-28 20:51:28.914922-05
19	1	11	82	-1.000	VENTA_SALON	MOVIMIENTO	12	2026-09-28 20:51:28.915407-05
20	1	11	135	-1.000	VENTA_SALON	MOVIMIENTO	12	2026-09-28 20:51:28.915927-05
21	1	11	36	-1.000	VENTA_SALON	MOVIMIENTO	12	2026-09-28 20:51:28.916362-05
22	1	11	109	-0.400	VENTA_SALON	MOVIMIENTO	13	2026-09-28 20:51:28.925841-05
23	1	11	81	-1.000	VENTA_SALON	MOVIMIENTO	13	2026-09-28 20:51:28.926725-05
24	1	11	137	-1.000	VENTA_SALON	MOVIMIENTO	13	2026-09-28 20:51:28.927383-05
25	1	12	107	-2.400	VENTA_SALON	MOVIMIENTO	14	2026-09-28 20:51:28.951254-05
26	1	12	82	-1.000	VENTA_SALON	MOVIMIENTO	14	2026-09-28 20:51:28.951576-05
27	1	12	135	-1.000	VENTA_SALON	MOVIMIENTO	14	2026-09-28 20:51:28.951868-05
28	1	12	36	-1.000	VENTA_SALON	MOVIMIENTO	14	2026-09-28 20:51:28.952137-05
29	1	12	109	-0.200	VENTA_SALON	MOVIMIENTO	15	2026-09-28 20:51:28.957752-05
30	1	13	84	-12.000	CORRECCION_RECEPCION	RECEPCION	7	2026-10-03 17:31:13.552981-05
31	1	13	84	12.000	RECEPCION_COMPRA	RECEPCION	10	2026-10-03 17:31:43.756758-05
32	1	13	29	-1.000	VENTA_SALON	MOVIMIENTO	16	2026-10-03 19:25:24.343696-05
33	1	13	31	-1.000	VENTA_SALON	MOVIMIENTO	16	2026-10-03 19:25:24.347094-05
34	1	13	34	-1.000	VENTA_SALON	MOVIMIENTO	16	2026-10-03 19:25:24.348182-05
35	1	13	36	-2.000	VENTA_SALON	MOVIMIENTO	16	2026-10-03 19:25:24.349518-05
36	1	13	107	-0.200	VENTA_SALON	MOVIMIENTO	16	2026-10-03 19:25:24.350894-05
37	1	13	138	-1.000	VENTA_SALON	MOVIMIENTO	16	2026-10-03 19:25:24.352008-05
38	1	13	139	-1.000	VENTA_SALON	MOVIMIENTO	16	2026-10-03 19:25:24.352766-05
\.


--
-- Data for Name: inventario_jornada; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventario_jornada (id_jornada, id_local, fecha, abierto_en, cerrado_en, abierto_por, cerrado_por, reporte) FROM stdin;
2	2	2026-09-26	2026-09-26 13:53:03.849566-05	\N	\N	\N	\N
4	4	2026-09-26	2026-09-26 13:53:03.856682-05	\N	\N	\N	\N
1	1	2026-09-26	2026-09-26 13:53:03.840542-05	2026-09-27 13:21:19.041733-05	\N	1	{"ventas": [], "inventario": [{"final": 14.0, "codigo": "CV-007", "nombre": "174 IPA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 107}, {"final": 14.0, "codigo": "CV-009", "nombre": "2 Más", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 109}, {"final": 14.0, "codigo": "B-008", "nombre": "Agua con Gas", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 82}, {"final": 14.0, "codigo": "B-007", "nombre": "Agua sin gas", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 81}, {"final": 8.0, "codigo": "B-002", "nombre": "Agua tonica", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 76}, {"final": 4.0, "codigo": "SS-010", "nombre": "Aliño", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 46}, {"final": 14.0, "codigo": "C-009", "nombre": "Alitas", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 72}, {"final": 14.0, "codigo": "CV-029", "nombre": "Apagón", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 129}, {"final": 4.3, "codigo": "T-007", "nombre": "Aperol", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 96}, {"final": 8.0, "codigo": "PR-004", "nombre": "Aros de cebolla", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 61}, {"final": 4.0, "codigo": "S-009", "nombre": "Arroz", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 19}, {"final": 14.0, "codigo": "CV-004", "nombre": "Barbarian Red Ale", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 104}, {"final": 14.0, "codigo": "CV-016", "nombre": "Barbarov", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 116}, {"final": 4.0, "codigo": "SS-009", "nombre": "BBQ", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 45}, {"final": 14.0, "codigo": "CV-010", "nombre": "Belga Pa’ Ti", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 110}, {"final": 4.0, "codigo": "C-007", "nombre": "Bife angosto", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 70}, {"final": 4.0, "codigo": "L-005", "nombre": "Blue cheese", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 55}, {"final": 14.0, "codigo": "CV-020", "nombre": "Blueberry Gose", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 120}, {"final": 8.0, "codigo": "CV-035", "nombre": "Botella de 174 IPA", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 135}, {"final": 8.0, "codigo": "CV-037", "nombre": "Botella de L.I.M.A. Pale Ale", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 137}, {"final": 8.0, "codigo": "CV-036", "nombre": "Botella de La Nena Trigo", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 136}, {"final": 8.0, "codigo": "CV-038", "nombre": "Botella de Magic Quinua", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 138}, {"final": 8.0, "codigo": "CV-039", "nombre": "Botella de Red", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 139}, {"final": 4.3, "codigo": "T-009", "nombre": "Campari", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 98}, {"final": 14.0, "codigo": "CV-021", "nombre": "Camu Camu Maracuyá", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 121}, {"final": 4.0, "codigo": "V-004", "nombre": "Cebolla", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 4}, {"final": 4.0, "codigo": "V-010", "nombre": "Champiñones", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 10}, {"final": 14.0, "codigo": "CV-006", "nombre": "Chaski", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 106}, {"final": 14.0, "codigo": "CV-027", "nombre": "Chelón de Doña Pepa", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 127}, {"final": 14.0, "codigo": "CV-015", "nombre": "Chicha Tu Mare", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 115}, {"final": 4.0, "codigo": "S-024", "nombre": "Chimay Roja", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 34}, {"final": 4.0, "codigo": "SS-007", "nombre": "Chimi churri", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 43}, {"final": 4.0, "codigo": "V-009", "nombre": "Choclo", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 9}, {"final": 4.0, "codigo": "C-002", "nombre": "Chorizo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 65}, {"final": 4.0, "codigo": "C-008", "nombre": "Chorizo finas hierbas", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 71}, {"final": 4.3, "codigo": "T-008", "nombre": "Cinzano", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 97}, {"final": 14.0, "codigo": "B-003", "nombre": "Coca Cola", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 77}, {"final": 14.0, "codigo": "B-005", "nombre": "Coca Cola sin Azucar", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 79}, {"final": 4.0, "codigo": "PR-006", "nombre": "Cordon Blue", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 63}, {"final": 14.0, "codigo": "CV-028", "nombre": "Crazy Llama", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 128}, {"final": 4.0, "codigo": "L-007", "nombre": "Crema de leche", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 57}, {"final": 14.0, "codigo": "CV-002", "nombre": "Dámela Siempre", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 102}, {"final": 14.0, "codigo": "CV-025", "nombre": "Dark Krieger", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 125}, {"final": 8.0, "codigo": "S-020", "nombre": "Daura Damm - Sin Gluten", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 30}, {"final": 14.0, "codigo": "CV-023", "nombre": "De la Selva Su Gose", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 123}, {"final": 14.0, "codigo": "CV-026", "nombre": "De Peso Pumpkin Ale", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 126}, {"final": 7.0, "codigo": "S-026", "nombre": "Delirium Tremens", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 36}, {"final": 4.0, "codigo": "S-006", "nombre": "Empanizado", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 16}, {"final": 4.0, "codigo": "S-018", "nombre": "Esencia de Chicha", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 28}, {"final": 7.0, "codigo": "S-019", "nombre": "Estrella Damm - Sin alcohol", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 29}, {"final": 8.0, "codigo": "S-008", "nombre": "Fideos canuto", "unidad": "Kg", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 18}, {"final": 4.0, "codigo": "C-006", "nombre": "Filete de pollo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 69}, {"final": 14.0, "codigo": "CV-008", "nombre": "Final Feliz", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 108}, {"final": 4.0, "codigo": "C-001", "nombre": "Frankfurter", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 64}, {"final": 4.0, "codigo": "S-005", "nombre": "Frejoles", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 15}, {"final": 4.4, "codigo": "T-011", "nombre": "Gin", "unidad": "L", "inicial": 4.4, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 100}, {"final": 14.0, "codigo": "CV-031", "nombre": "GRANADILLA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 131}, {"final": 4.0, "codigo": "C-005", "nombre": "Hamburguesa 100g", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 68}, {"final": 4.0, "codigo": "C-010", "nombre": "Hamburguesa 200g", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 73}, {"final": 4.0, "codigo": "V-002", "nombre": "Hierba buena", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 2}, {"final": 8.0, "codigo": "S-012", "nombre": "Huevo", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 22}, {"final": 14.0, "codigo": "B-004", "nombre": "Inca Kola", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 78}, {"final": 14.0, "codigo": "B-006", "nombre": "Inca Kola sin Azucar", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 80}, {"final": 14.0, "codigo": "CV-032", "nombre": "INTERESTELAGER", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 132}, {"final": 4.3, "codigo": "T-001", "nombre": "Jager", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 90}, {"final": 4.0, "codigo": "S-016", "nombre": "Jarabe de frambuesa", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 26}, {"final": 4.0, "codigo": "S-014", "nombre": "Jarabe de goma", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 24}, {"final": 4.0, "codigo": "S-015", "nombre": "Jarabe de Sandía", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 25}, {"final": 14.0, "codigo": "CV-011", "nombre": "K-7", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 111}, {"final": 14.0, "codigo": "CV-024", "nombre": "Krieger", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 124}, {"final": 14.0, "codigo": "CV-005", "nombre": "L.I.M.A", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 105}, {"final": 14.0, "codigo": "CV-003", "nombre": "La Nena", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 103}, {"final": 14.0, "codigo": "CV-022", "nombre": "La Última Chupada del Mango", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 122}, {"final": 4.0, "codigo": "V-008", "nombre": "Lechuga", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 8}, {"final": 3.5, "codigo": "V-001", "nombre": "Limón", "unidad": "Kg", "inicial": 3.5, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 1}, {"final": 8.0, "codigo": "S-021", "nombre": "Lindermans Kriek", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 31}, {"final": 14.0, "codigo": "CV-013", "nombre": "Lou", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 113}, {"final": 14.0, "codigo": "CV-001", "nombre": "Magic Quinua", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 101}, {"final": 14.0, "codigo": "CV-012", "nombre": "Mañanero", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 112}, {"final": 4.0, "codigo": "S-017", "nombre": "Maracuya", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 27}, {"final": 4.3, "codigo": "T-010", "nombre": "Martini", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 99}, {"final": 4.0, "codigo": "L-003", "nombre": "Mayonesa de Yogurt", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 53}, {"final": 4.0, "codigo": "C-011", "nombre": "Medallón de lomo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 74}, {"final": 8.0, "codigo": "B-015", "nombre": "Mr. Perkins Ginger Beer", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 89}, {"final": 8.0, "codigo": "B-014", "nombre": "Mr. Perkins Pink Soda", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 88}, {"final": 4.0, "codigo": "S-002", "nombre": "Nachos", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 12}, {"final": 4.0, "codigo": "S-013", "nombre": "Naranja deshidratada", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 23}, {"final": 14.0, "codigo": "CV-019", "nombre": "Oktu-Brefest", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 119}, {"final": 4.0, "codigo": "V-007", "nombre": "Palta", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 7}, {"final": 8.0, "codigo": "S-027", "nombre": "Pan Hamburguesa", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 140}, {"final": 9.0, "codigo": "V-003", "nombre": "Papa", "unidad": "Kg", "inicial": 9.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 3}, {"final": 14.0, "codigo": "CV-014", "nombre": "Peaky Biter", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 114}, {"final": 4.0, "codigo": "C-003", "nombre": "Pechuga de Pollo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 66}, {"final": 4.0, "codigo": "S-007", "nombre": "Pepinillos", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 17}, {"final": 8.0, "codigo": "S-025", "nombre": "Petrus Choco Cherry", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 35}, {"final": 8.0, "codigo": "S-004", "nombre": "Petti pan", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 14}, {"final": 4.0, "codigo": "V-006", "nombre": "Pimiento", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 6}, {"final": 4.0, "codigo": "T-005", "nombre": "Pisco", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 94}, {"final": 14.0, "codigo": "CV-033", "nombre": "POLVO ESTELAR", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 133}, {"final": 4.0, "codigo": "SS-008", "nombre": "Pulled Pork", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 44}, {"final": 4.0, "codigo": "PR-005", "nombre": "Pure", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 62}, {"final": 4.0, "codigo": "L-001", "nombre": "Queso cheddar", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 51}, {"final": 4.0, "codigo": "L-004", "nombre": "Queso fresco", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 54}, {"final": 4.0, "codigo": "L-002", "nombre": "Queso gouda", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 52}, {"final": 4.0, "codigo": "L-006", "nombre": "Queso parmesano", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 56}, {"final": 8.0, "codigo": "B-009", "nombre": "Red bull", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 83}, {"final": 8.0, "codigo": "B-013", "nombre": "Red Bull Green Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 87}, {"final": 8.0, "codigo": "B-012", "nombre": "Red bull Red Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 86}, {"final": 8.0, "codigo": "B-011", "nombre": "Red bull Sugar Free", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 85}, {"final": 8.0, "codigo": "B-010", "nombre": "Red bull Tropical Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 84}, {"final": 4.3, "codigo": "T-003", "nombre": "Ron", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 92}, {"final": 4.0, "codigo": "S-001", "nombre": "Sal", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 11}, {"final": 4.0, "codigo": "SS-013", "nombre": "Salsa 4 piminetas", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 49}, {"final": 4.0, "codigo": "SS-003", "nombre": "Salsa Acevichada", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 39}, {"final": 4.0, "codigo": "SS-002", "nombre": "Salsa BBQ IPA", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 38}, {"final": 4.0, "codigo": "SS-004", "nombre": "Salsa Buffalo", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 40}, {"final": 4.0, "codigo": "SS-001", "nombre": "Salsa cheddar", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 37}, {"final": 4.0, "codigo": "SS-012", "nombre": "Salsa de chapiñón", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 48}, {"final": 4.0, "codigo": "SS-014", "nombre": "Salsa de ostión", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 50}, {"final": 4.0, "codigo": "SS-006", "nombre": "Salsa Mango Charapita", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 42}, {"final": 4.0, "codigo": "SS-011", "nombre": "Salsa mediterránea", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 47}, {"final": 4.0, "codigo": "SS-005", "nombre": "Salsa Picante Agridulce", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 41}, {"final": 8.0, "codigo": "S-022", "nombre": "San Bernardus ABT 12", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 32}, {"final": 8.0, "codigo": "B-001", "nombre": "Schweppes", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 75}, {"final": 4.0, "codigo": "S-010", "nombre": "Sillao", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 20}, {"final": 14.0, "codigo": "CV-018", "nombre": "St Patrick’s", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 118}, {"final": 8.0, "codigo": "PR-002", "nombre": "Tequeños de Queso", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 59}, {"final": 8.0, "codigo": "PR-003", "nombre": "Tequeños Pulled Pork", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 60}, {"final": 8.0, "codigo": "PR-001", "nombre": "Tequeños Ruleta Rusa", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 58}, {"final": 4.3, "codigo": "T-004", "nombre": "Tequila", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 93}, {"final": 14.0, "codigo": "CV-034", "nombre": "TINTO DE VERANO", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 134}, {"final": 4.0, "codigo": "C-004", "nombre": "Tocino", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 67}, {"final": 0.8, "codigo": "V-005", "nombre": "Tomate", "unidad": "Kg", "inicial": 0.8, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 5}, {"final": 4.0, "codigo": "S-003", "nombre": "Tortilla de maiz", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 13}, {"final": 14.0, "codigo": "CV-017", "nombre": "Tropical Nordic", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 117}, {"final": 14.0, "codigo": "CV-030", "nombre": "VALKIRIA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 130}, {"final": 4.0, "codigo": "S-011", "nombre": "Vinagre tinto", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 21}, {"final": 4.3, "codigo": "T-006", "nombre": "Vodka", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 95}, {"final": 7.0, "codigo": "S-023", "nombre": "Westmalle Tripel", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 33}, {"final": 4.3, "codigo": "T-002", "nombre": "Whisky", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 91}]}
5	1	2026-09-28	2026-09-28 11:44:35.884358-05	2026-09-28 18:49:24.306409-05	1	1	{"ventas": [], "inventario": [{"final": 14.0, "codigo": "CV-007", "nombre": "174 IPA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 107}, {"final": 14.0, "codigo": "CV-009", "nombre": "2 Más", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 109}, {"final": 14.0, "codigo": "B-008", "nombre": "Agua con Gas", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 82}, {"final": 14.0, "codigo": "B-007", "nombre": "Agua sin gas", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 81}, {"final": 8.0, "codigo": "B-002", "nombre": "Agua tonica", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 76}, {"final": 4.0, "codigo": "SS-010", "nombre": "Aliño", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 46}, {"final": 14.0, "codigo": "C-009", "nombre": "Alitas", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 72}, {"final": 14.0, "codigo": "CV-029", "nombre": "Apagón", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 129}, {"final": 4.3, "codigo": "T-007", "nombre": "Aperol", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 96}, {"final": 8.0, "codigo": "PR-004", "nombre": "Aros de cebolla", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 61}, {"final": 4.0, "codigo": "S-009", "nombre": "Arroz", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 19}, {"final": 14.0, "codigo": "CV-004", "nombre": "Barbarian Red Ale", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 104}, {"final": 14.0, "codigo": "CV-016", "nombre": "Barbarov", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 116}, {"final": 4.0, "codigo": "SS-009", "nombre": "BBQ", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 45}, {"final": 14.0, "codigo": "CV-010", "nombre": "Belga Pa’ Ti", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 110}, {"final": 4.0, "codigo": "C-007", "nombre": "Bife angosto", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 70}, {"final": 4.0, "codigo": "L-005", "nombre": "Blue cheese", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 55}, {"final": 14.0, "codigo": "CV-020", "nombre": "Blueberry Gose", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 120}, {"final": 8.0, "codigo": "CV-035", "nombre": "Botella de 174 IPA", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 135}, {"final": 8.0, "codigo": "CV-037", "nombre": "Botella de L.I.M.A. Pale Ale", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 137}, {"final": 8.0, "codigo": "CV-036", "nombre": "Botella de La Nena Trigo", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 136}, {"final": 8.0, "codigo": "CV-038", "nombre": "Botella de Magic Quinua", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 138}, {"final": 8.0, "codigo": "CV-039", "nombre": "Botella de Red", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 139}, {"final": 4.3, "codigo": "T-009", "nombre": "Campari", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 98}, {"final": 14.0, "codigo": "CV-021", "nombre": "Camu Camu Maracuyá", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 121}, {"final": 4.0, "codigo": "V-004", "nombre": "Cebolla", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 4}, {"final": 4.0, "codigo": "V-010", "nombre": "Champiñones", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 10}, {"final": 14.0, "codigo": "CV-006", "nombre": "Chaski", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 106}, {"final": 14.0, "codigo": "CV-027", "nombre": "Chelón de Doña Pepa", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 127}, {"final": 14.0, "codigo": "CV-015", "nombre": "Chicha Tu Mare", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 115}, {"final": 4.0, "codigo": "S-024", "nombre": "Chimay Roja", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 34}, {"final": 4.0, "codigo": "SS-007", "nombre": "Chimi churri", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 43}, {"final": 4.0, "codigo": "V-009", "nombre": "Choclo", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 9}, {"final": 4.0, "codigo": "C-002", "nombre": "Chorizo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 65}, {"final": 4.0, "codigo": "C-008", "nombre": "Chorizo finas hierbas", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 71}, {"final": 4.3, "codigo": "T-008", "nombre": "Cinzano", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 97}, {"final": 14.0, "codigo": "B-003", "nombre": "Coca Cola", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 77}, {"final": 14.0, "codigo": "B-005", "nombre": "Coca Cola sin Azucar", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 79}, {"final": 4.0, "codigo": "PR-006", "nombre": "Cordon Blue", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 63}, {"final": 14.0, "codigo": "CV-028", "nombre": "Crazy Llama", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 128}, {"final": 4.0, "codigo": "L-007", "nombre": "Crema de leche", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 57}, {"final": 14.0, "codigo": "CV-002", "nombre": "Dámela Siempre", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 102}, {"final": 14.0, "codigo": "CV-025", "nombre": "Dark Krieger", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 125}, {"final": 8.0, "codigo": "S-020", "nombre": "Daura Damm - Sin Gluten", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 30}, {"final": 14.0, "codigo": "CV-023", "nombre": "De la Selva Su Gose", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 123}, {"final": 14.0, "codigo": "CV-026", "nombre": "De Peso Pumpkin Ale", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 126}, {"final": 7.0, "codigo": "S-026", "nombre": "Delirium Tremens", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 36}, {"final": 4.0, "codigo": "S-006", "nombre": "Empanizado", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 16}, {"final": 4.0, "codigo": "S-018", "nombre": "Esencia de Chicha", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 28}, {"final": 7.0, "codigo": "S-019", "nombre": "Estrella Damm - Sin alcohol", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 29}, {"final": 8.0, "codigo": "S-008", "nombre": "Fideos canuto", "unidad": "Kg", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 18}, {"final": 4.0, "codigo": "C-006", "nombre": "Filete de pollo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 69}, {"final": 14.0, "codigo": "CV-008", "nombre": "Final Feliz", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 108}, {"final": 4.0, "codigo": "C-001", "nombre": "Frankfurter", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 64}, {"final": 4.0, "codigo": "S-005", "nombre": "Frejoles", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 15}, {"final": 4.4, "codigo": "T-011", "nombre": "Gin", "unidad": "L", "inicial": 4.4, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 100}, {"final": 14.0, "codigo": "CV-031", "nombre": "GRANADILLA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 131}, {"final": 4.0, "codigo": "C-005", "nombre": "Hamburguesa 100g", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 68}, {"final": 4.0, "codigo": "C-010", "nombre": "Hamburguesa 200g", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 73}, {"final": 4.0, "codigo": "V-002", "nombre": "Hierba buena", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 2}, {"final": 8.0, "codigo": "S-012", "nombre": "Huevo", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 22}, {"final": 14.0, "codigo": "B-004", "nombre": "Inca Kola", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 78}, {"final": 14.0, "codigo": "B-006", "nombre": "Inca Kola sin Azucar", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 80}, {"final": 14.0, "codigo": "CV-032", "nombre": "INTERESTELAGER", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 132}, {"final": 4.3, "codigo": "T-001", "nombre": "Jager", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 90}, {"final": 4.0, "codigo": "S-016", "nombre": "Jarabe de frambuesa", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 26}, {"final": 4.0, "codigo": "S-014", "nombre": "Jarabe de goma", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 24}, {"final": 4.0, "codigo": "S-015", "nombre": "Jarabe de Sandía", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 25}, {"final": 14.0, "codigo": "CV-011", "nombre": "K-7", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 111}, {"final": 14.0, "codigo": "CV-024", "nombre": "Krieger", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 124}, {"final": 14.0, "codigo": "CV-005", "nombre": "L.I.M.A", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 105}, {"final": 14.0, "codigo": "CV-003", "nombre": "La Nena", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 103}, {"final": 14.0, "codigo": "CV-022", "nombre": "La Última Chupada del Mango", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 122}, {"final": 4.0, "codigo": "V-008", "nombre": "Lechuga", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 8}, {"final": 3.5, "codigo": "V-001", "nombre": "Limón", "unidad": "Kg", "inicial": 3.5, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 1}, {"final": 8.0, "codigo": "S-021", "nombre": "Lindermans Kriek", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 31}, {"final": 14.0, "codigo": "CV-013", "nombre": "Lou", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 113}, {"final": 14.0, "codigo": "CV-001", "nombre": "Magic Quinua", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 101}, {"final": 14.0, "codigo": "CV-012", "nombre": "Mañanero", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 112}, {"final": 4.0, "codigo": "S-017", "nombre": "Maracuya", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 27}, {"final": 4.3, "codigo": "T-010", "nombre": "Martini", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 99}, {"final": 4.0, "codigo": "L-003", "nombre": "Mayonesa de Yogurt", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 53}, {"final": 4.0, "codigo": "C-011", "nombre": "Medallón de lomo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 74}, {"final": 8.0, "codigo": "B-015", "nombre": "Mr. Perkins Ginger Beer", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 89}, {"final": 8.0, "codigo": "B-014", "nombre": "Mr. Perkins Pink Soda", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 88}, {"final": 4.0, "codigo": "S-002", "nombre": "Nachos", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 12}, {"final": 4.0, "codigo": "S-013", "nombre": "Naranja deshidratada", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 23}, {"final": 14.0, "codigo": "CV-019", "nombre": "Oktu-Brefest", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 119}, {"final": 4.0, "codigo": "V-007", "nombre": "Palta", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 7}, {"final": 8.0, "codigo": "S-027", "nombre": "Pan Hamburguesa", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 140}, {"final": 9.0, "codigo": "V-003", "nombre": "Papa", "unidad": "Kg", "inicial": 9.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 3}, {"final": 14.0, "codigo": "CV-014", "nombre": "Peaky Biter", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 114}, {"final": 4.0, "codigo": "C-003", "nombre": "Pechuga de Pollo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 66}, {"final": 4.0, "codigo": "S-007", "nombre": "Pepinillos", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 17}, {"final": 8.0, "codigo": "S-025", "nombre": "Petrus Choco Cherry", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 35}, {"final": 8.0, "codigo": "S-004", "nombre": "Petti pan", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 14}, {"final": 4.0, "codigo": "V-006", "nombre": "Pimiento", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 6}, {"final": 4.0, "codigo": "T-005", "nombre": "Pisco", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 94}, {"final": 14.0, "codigo": "CV-033", "nombre": "POLVO ESTELAR", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 133}, {"final": 4.0, "codigo": "SS-008", "nombre": "Pulled Pork", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 44}, {"final": 4.0, "codigo": "PR-005", "nombre": "Pure", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 62}, {"final": 4.0, "codigo": "L-001", "nombre": "Queso cheddar", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 51}, {"final": 4.0, "codigo": "L-004", "nombre": "Queso fresco", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 54}, {"final": 4.0, "codigo": "L-002", "nombre": "Queso gouda", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 52}, {"final": 4.0, "codigo": "L-006", "nombre": "Queso parmesano", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 56}, {"final": 8.0, "codigo": "B-009", "nombre": "Red bull", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 83}, {"final": 8.0, "codigo": "B-013", "nombre": "Red Bull Green Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 87}, {"final": 8.0, "codigo": "B-012", "nombre": "Red bull Red Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 86}, {"final": 8.0, "codigo": "B-011", "nombre": "Red bull Sugar Free", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 85}, {"final": 8.0, "codigo": "B-010", "nombre": "Red bull Tropical Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 84}, {"final": 4.3, "codigo": "T-003", "nombre": "Ron", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 92}, {"final": 4.0, "codigo": "S-001", "nombre": "Sal", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 11}, {"final": 4.0, "codigo": "SS-013", "nombre": "Salsa 4 piminetas", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 49}, {"final": 4.0, "codigo": "SS-003", "nombre": "Salsa Acevichada", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 39}, {"final": 4.0, "codigo": "SS-002", "nombre": "Salsa BBQ IPA", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 38}, {"final": 4.0, "codigo": "SS-004", "nombre": "Salsa Buffalo", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 40}, {"final": 4.0, "codigo": "SS-001", "nombre": "Salsa cheddar", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 37}, {"final": 4.0, "codigo": "SS-012", "nombre": "Salsa de chapiñón", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 48}, {"final": 4.0, "codigo": "SS-014", "nombre": "Salsa de ostión", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 50}, {"final": 4.0, "codigo": "SS-006", "nombre": "Salsa Mango Charapita", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 42}, {"final": 4.0, "codigo": "SS-011", "nombre": "Salsa mediterránea", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 47}, {"final": 4.0, "codigo": "SS-005", "nombre": "Salsa Picante Agridulce", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 41}, {"final": 8.0, "codigo": "S-022", "nombre": "San Bernardus ABT 12", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 32}, {"final": 8.0, "codigo": "B-001", "nombre": "Schweppes", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 75}, {"final": 4.0, "codigo": "S-010", "nombre": "Sillao", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 20}, {"final": 14.0, "codigo": "CV-018", "nombre": "St Patrick’s", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 118}, {"final": 8.0, "codigo": "PR-002", "nombre": "Tequeños de Queso", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 59}, {"final": 8.0, "codigo": "PR-003", "nombre": "Tequeños Pulled Pork", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 60}, {"final": 8.0, "codigo": "PR-001", "nombre": "Tequeños Ruleta Rusa", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 58}, {"final": 4.3, "codigo": "T-004", "nombre": "Tequila", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 93}, {"final": 14.0, "codigo": "CV-034", "nombre": "TINTO DE VERANO", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 134}, {"final": 4.0, "codigo": "C-004", "nombre": "Tocino", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 67}, {"final": 0.8, "codigo": "V-005", "nombre": "Tomate", "unidad": "Kg", "inicial": 0.8, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 5}, {"final": 4.0, "codigo": "S-003", "nombre": "Tortilla de maiz", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 13}, {"final": 14.0, "codigo": "CV-017", "nombre": "Tropical Nordic", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 117}, {"final": 14.0, "codigo": "CV-030", "nombre": "VALKIRIA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 130}, {"final": 4.0, "codigo": "S-011", "nombre": "Vinagre tinto", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 21}, {"final": 4.3, "codigo": "T-006", "nombre": "Vodka", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 95}, {"final": 7.0, "codigo": "S-023", "nombre": "Westmalle Tripel", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 33}, {"final": 4.3, "codigo": "T-002", "nombre": "Whisky", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 91}]}
3	3	2026-09-26	2026-09-26 13:53:03.853229-05	2026-09-28 20:45:55.991934-05	\N	1	{"ventas": [], "inventario": [{"final": 0.0, "codigo": "CV-007", "nombre": "174 IPA", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 107}, {"final": 0.0, "codigo": "CV-009", "nombre": "2 Más", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 109}, {"final": 0.0, "codigo": "B-008", "nombre": "Agua con Gas", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 82}, {"final": 0.0, "codigo": "B-007", "nombre": "Agua sin gas", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 81}, {"final": 0.0, "codigo": "B-002", "nombre": "Agua tonica", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 76}, {"final": 0.0, "codigo": "SS-010", "nombre": "Aliño", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 46}, {"final": 0.0, "codigo": "C-009", "nombre": "Alitas", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 72}, {"final": 0.0, "codigo": "CV-029", "nombre": "Apagón", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 129}, {"final": 0.0, "codigo": "T-007", "nombre": "Aperol", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 96}, {"final": 0.0, "codigo": "PR-004", "nombre": "Aros de cebolla", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 61}, {"final": 0.0, "codigo": "S-009", "nombre": "Arroz", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 19}, {"final": 0.0, "codigo": "CV-004", "nombre": "Barbarian Red Ale", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 104}, {"final": 0.0, "codigo": "CV-016", "nombre": "Barbarov", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 116}, {"final": 0.0, "codigo": "SS-009", "nombre": "BBQ", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 45}, {"final": 0.0, "codigo": "CV-010", "nombre": "Belga Pa’ Ti", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 110}, {"final": 0.0, "codigo": "C-007", "nombre": "Bife angosto", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 70}, {"final": 0.0, "codigo": "L-005", "nombre": "Blue cheese", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 55}, {"final": 0.0, "codigo": "CV-020", "nombre": "Blueberry Gose", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 120}, {"final": 0.0, "codigo": "CV-035", "nombre": "Botella de 174 IPA", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 135}, {"final": 0.0, "codigo": "CV-037", "nombre": "Botella de L.I.M.A. Pale Ale", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 137}, {"final": 0.0, "codigo": "CV-036", "nombre": "Botella de La Nena Trigo", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 136}, {"final": 0.0, "codigo": "CV-038", "nombre": "Botella de Magic Quinua", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 138}, {"final": 0.0, "codigo": "CV-039", "nombre": "Botella de Red", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 139}, {"final": 0.0, "codigo": "T-009", "nombre": "Campari", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 98}, {"final": 0.0, "codigo": "CV-021", "nombre": "Camu Camu Maracuyá", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 121}, {"final": 0.0, "codigo": "V-004", "nombre": "Cebolla", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 4}, {"final": 0.0, "codigo": "V-010", "nombre": "Champiñones", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 10}, {"final": 0.0, "codigo": "CV-006", "nombre": "Chaski", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 106}, {"final": 0.0, "codigo": "CV-027", "nombre": "Chelón de Doña Pepa", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 127}, {"final": 0.0, "codigo": "CV-015", "nombre": "Chicha Tu Mare", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 115}, {"final": 0.0, "codigo": "S-024", "nombre": "Chimay Roja", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 34}, {"final": 0.0, "codigo": "SS-007", "nombre": "Chimi churri", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 43}, {"final": 0.0, "codigo": "V-009", "nombre": "Choclo", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 9}, {"final": 0.0, "codigo": "C-002", "nombre": "Chorizo", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 65}, {"final": 0.0, "codigo": "C-008", "nombre": "Chorizo finas hierbas", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 71}, {"final": 0.0, "codigo": "T-008", "nombre": "Cinzano", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 97}, {"final": 0.0, "codigo": "B-003", "nombre": "Coca Cola", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 77}, {"final": 0.0, "codigo": "B-005", "nombre": "Coca Cola sin Azucar", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 79}, {"final": 0.0, "codigo": "PR-006", "nombre": "Cordon Blue", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 63}, {"final": 0.0, "codigo": "CV-028", "nombre": "Crazy Llama", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 128}, {"final": 0.0, "codigo": "L-007", "nombre": "Crema de leche", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 57}, {"final": 0.0, "codigo": "CV-002", "nombre": "Dámela Siempre", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 102}, {"final": 0.0, "codigo": "CV-025", "nombre": "Dark Krieger", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 125}, {"final": 0.0, "codigo": "S-020", "nombre": "Daura Damm - Sin Gluten", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 30}, {"final": 0.0, "codigo": "CV-023", "nombre": "De la Selva Su Gose", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 123}, {"final": 0.0, "codigo": "CV-026", "nombre": "De Peso Pumpkin Ale", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 126}, {"final": 0.0, "codigo": "S-026", "nombre": "Delirium Tremens", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 36}, {"final": 0.0, "codigo": "S-006", "nombre": "Empanizado", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 16}, {"final": 0.0, "codigo": "S-018", "nombre": "Esencia de Chicha", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 28}, {"final": 0.0, "codigo": "S-019", "nombre": "Estrella Damm - Sin alcohol", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 29}, {"final": 0.0, "codigo": "S-008", "nombre": "Fideos canuto", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 18}, {"final": 0.0, "codigo": "C-006", "nombre": "Filete de pollo", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 69}, {"final": 0.0, "codigo": "CV-008", "nombre": "Final Feliz", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 108}, {"final": 0.0, "codigo": "C-001", "nombre": "Frankfurter", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 64}, {"final": 0.0, "codigo": "S-005", "nombre": "Frejoles", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 15}, {"final": 0.0, "codigo": "T-011", "nombre": "Gin", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 100}, {"final": 0.0, "codigo": "CV-031", "nombre": "GRANADILLA", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 131}, {"final": 0.0, "codigo": "C-005", "nombre": "Hamburguesa 100g", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 68}, {"final": 0.0, "codigo": "C-010", "nombre": "Hamburguesa 200g", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 73}, {"final": 0.0, "codigo": "V-002", "nombre": "Hierba buena", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 2}, {"final": 0.0, "codigo": "S-012", "nombre": "Huevo", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 22}, {"final": 0.0, "codigo": "B-004", "nombre": "Inca Kola", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 78}, {"final": 0.0, "codigo": "B-006", "nombre": "Inca Kola sin Azucar", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 80}, {"final": 0.0, "codigo": "CV-032", "nombre": "INTERESTELAGER", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 132}, {"final": 0.0, "codigo": "T-001", "nombre": "Jager", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 90}, {"final": 0.0, "codigo": "S-016", "nombre": "Jarabe de frambuesa", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 26}, {"final": 0.0, "codigo": "S-014", "nombre": "Jarabe de goma", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 24}, {"final": 0.0, "codigo": "S-015", "nombre": "Jarabe de Sandía", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 25}, {"final": 0.0, "codigo": "CV-011", "nombre": "K-7", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 111}, {"final": 0.0, "codigo": "CV-024", "nombre": "Krieger", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 124}, {"final": 0.0, "codigo": "CV-005", "nombre": "L.I.M.A", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 105}, {"final": 0.0, "codigo": "CV-003", "nombre": "La Nena", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 103}, {"final": 0.0, "codigo": "CV-022", "nombre": "La Última Chupada del Mango", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 122}, {"final": 0.0, "codigo": "V-008", "nombre": "Lechuga", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 8}, {"final": 0.0, "codigo": "V-001", "nombre": "Limón", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 1}, {"final": 0.0, "codigo": "S-021", "nombre": "Lindermans Kriek", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 31}, {"final": 0.0, "codigo": "CV-013", "nombre": "Lou", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 113}, {"final": 0.0, "codigo": "CV-001", "nombre": "Magic Quinua", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 101}, {"final": 0.0, "codigo": "CV-012", "nombre": "Mañanero", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 112}, {"final": 0.0, "codigo": "S-017", "nombre": "Maracuya", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 27}, {"final": 0.0, "codigo": "T-010", "nombre": "Martini", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 99}, {"final": 0.0, "codigo": "L-003", "nombre": "Mayonesa de Yogurt", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 53}, {"final": 0.0, "codigo": "C-011", "nombre": "Medallón de lomo", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 74}, {"final": 0.0, "codigo": "B-015", "nombre": "Mr. Perkins Ginger Beer", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 89}, {"final": 0.0, "codigo": "B-014", "nombre": "Mr. Perkins Pink Soda", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 88}, {"final": 0.0, "codigo": "S-002", "nombre": "Nachos", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 12}, {"final": 0.0, "codigo": "S-013", "nombre": "Naranja deshidratada", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 23}, {"final": 0.0, "codigo": "CV-019", "nombre": "Oktu-Brefest", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 119}, {"final": 0.0, "codigo": "V-007", "nombre": "Palta", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 7}, {"final": 0.0, "codigo": "S-027", "nombre": "Pan Hamburguesa", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 140}, {"final": 0.0, "codigo": "V-003", "nombre": "Papa", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 3}, {"final": 0.0, "codigo": "CV-014", "nombre": "Peaky Biter", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 114}, {"final": 0.0, "codigo": "C-003", "nombre": "Pechuga de Pollo", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 66}, {"final": 0.0, "codigo": "S-007", "nombre": "Pepinillos", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 17}, {"final": 0.0, "codigo": "S-025", "nombre": "Petrus Choco Cherry", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 35}, {"final": 0.0, "codigo": "S-004", "nombre": "Petti pan", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 14}, {"final": 0.0, "codigo": "V-006", "nombre": "Pimiento", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 6}, {"final": 0.0, "codigo": "T-005", "nombre": "Pisco", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 94}, {"final": 0.0, "codigo": "CV-033", "nombre": "POLVO ESTELAR", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 133}, {"final": 0.0, "codigo": "SS-008", "nombre": "Pulled Pork", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 44}, {"final": 0.0, "codigo": "PR-005", "nombre": "Pure", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 62}, {"final": 0.0, "codigo": "L-001", "nombre": "Queso cheddar", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 51}, {"final": 0.0, "codigo": "L-004", "nombre": "Queso fresco", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 54}, {"final": 0.0, "codigo": "L-002", "nombre": "Queso gouda", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 52}, {"final": 0.0, "codigo": "L-006", "nombre": "Queso parmesano", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 56}, {"final": 0.0, "codigo": "B-009", "nombre": "Red bull", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 83}, {"final": 0.0, "codigo": "B-013", "nombre": "Red Bull Green Edition", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 87}, {"final": 0.0, "codigo": "B-012", "nombre": "Red bull Red Edition", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 86}, {"final": 0.0, "codigo": "B-011", "nombre": "Red bull Sugar Free", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 85}, {"final": 0.0, "codigo": "B-010", "nombre": "Red bull Tropical Edition", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 84}, {"final": 0.0, "codigo": "T-003", "nombre": "Ron", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 92}, {"final": 0.0, "codigo": "S-001", "nombre": "Sal", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 11}, {"final": 0.0, "codigo": "SS-013", "nombre": "Salsa 4 piminetas", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 49}, {"final": 0.0, "codigo": "SS-003", "nombre": "Salsa Acevichada", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 39}, {"final": 0.0, "codigo": "SS-002", "nombre": "Salsa BBQ IPA", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 38}, {"final": 0.0, "codigo": "SS-004", "nombre": "Salsa Buffalo", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 40}, {"final": 0.0, "codigo": "SS-001", "nombre": "Salsa cheddar", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 37}, {"final": 0.0, "codigo": "SS-012", "nombre": "Salsa de chapiñón", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 48}, {"final": 0.0, "codigo": "SS-014", "nombre": "Salsa de ostión", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 50}, {"final": 0.0, "codigo": "SS-006", "nombre": "Salsa Mango Charapita", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 42}, {"final": 0.0, "codigo": "SS-011", "nombre": "Salsa mediterránea", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 47}, {"final": 0.0, "codigo": "SS-005", "nombre": "Salsa Picante Agridulce", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 41}, {"final": 0.0, "codigo": "S-022", "nombre": "San Bernardus ABT 12", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 32}, {"final": 0.0, "codigo": "B-001", "nombre": "Schweppes", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 75}, {"final": 0.0, "codigo": "S-010", "nombre": "Sillao", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 20}, {"final": 0.0, "codigo": "CV-018", "nombre": "St Patrick’s", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 118}, {"final": 0.0, "codigo": "PR-002", "nombre": "Tequeños de Queso", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 59}, {"final": 0.0, "codigo": "PR-003", "nombre": "Tequeños Pulled Pork", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 60}, {"final": 0.0, "codigo": "PR-001", "nombre": "Tequeños Ruleta Rusa", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 58}, {"final": 0.0, "codigo": "T-004", "nombre": "Tequila", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 93}, {"final": 0.0, "codigo": "CV-034", "nombre": "TINTO DE VERANO", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 134}, {"final": 0.0, "codigo": "C-004", "nombre": "Tocino", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 67}, {"final": 0.0, "codigo": "V-005", "nombre": "Tomate", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 5}, {"final": 0.0, "codigo": "S-003", "nombre": "Tortilla de maiz", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 13}, {"final": 0.0, "codigo": "CV-017", "nombre": "Tropical Nordic", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 117}, {"final": 0.0, "codigo": "CV-030", "nombre": "VALKIRIA", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 130}, {"final": 0.0, "codigo": "S-011", "nombre": "Vinagre tinto", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 21}, {"final": 0.0, "codigo": "T-006", "nombre": "Vodka", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 95}, {"final": 0.0, "codigo": "S-023", "nombre": "Westmalle Tripel", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 33}, {"final": 0.0, "codigo": "T-002", "nombre": "Whisky", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 91}]}
6	3	2026-09-28	2026-09-28 20:45:59.626757-05	2026-09-28 20:46:02.366552-05	1	1	{"ventas": [], "inventario": [{"final": 0.0, "codigo": "CV-007", "nombre": "174 IPA", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 107}, {"final": 0.0, "codigo": "CV-009", "nombre": "2 Más", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 109}, {"final": 0.0, "codigo": "B-008", "nombre": "Agua con Gas", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 82}, {"final": 0.0, "codigo": "B-007", "nombre": "Agua sin gas", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 81}, {"final": 0.0, "codigo": "B-002", "nombre": "Agua tonica", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 76}, {"final": 0.0, "codigo": "SS-010", "nombre": "Aliño", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 46}, {"final": 0.0, "codigo": "C-009", "nombre": "Alitas", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 72}, {"final": 0.0, "codigo": "CV-029", "nombre": "Apagón", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 129}, {"final": 0.0, "codigo": "T-007", "nombre": "Aperol", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 96}, {"final": 0.0, "codigo": "PR-004", "nombre": "Aros de cebolla", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 61}, {"final": 0.0, "codigo": "S-009", "nombre": "Arroz", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 19}, {"final": 0.0, "codigo": "CV-004", "nombre": "Barbarian Red Ale", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 104}, {"final": 0.0, "codigo": "CV-016", "nombre": "Barbarov", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 116}, {"final": 0.0, "codigo": "SS-009", "nombre": "BBQ", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 45}, {"final": 0.0, "codigo": "CV-010", "nombre": "Belga Pa’ Ti", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 110}, {"final": 0.0, "codigo": "C-007", "nombre": "Bife angosto", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 70}, {"final": 0.0, "codigo": "L-005", "nombre": "Blue cheese", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 55}, {"final": 0.0, "codigo": "CV-020", "nombre": "Blueberry Gose", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 120}, {"final": 0.0, "codigo": "CV-035", "nombre": "Botella de 174 IPA", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 135}, {"final": 0.0, "codigo": "CV-037", "nombre": "Botella de L.I.M.A. Pale Ale", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 137}, {"final": 0.0, "codigo": "CV-036", "nombre": "Botella de La Nena Trigo", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 136}, {"final": 0.0, "codigo": "CV-038", "nombre": "Botella de Magic Quinua", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 138}, {"final": 0.0, "codigo": "CV-039", "nombre": "Botella de Red", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 139}, {"final": 0.0, "codigo": "T-009", "nombre": "Campari", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 98}, {"final": 0.0, "codigo": "CV-021", "nombre": "Camu Camu Maracuyá", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 121}, {"final": 0.0, "codigo": "V-004", "nombre": "Cebolla", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 4}, {"final": 0.0, "codigo": "V-010", "nombre": "Champiñones", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 10}, {"final": 0.0, "codigo": "CV-006", "nombre": "Chaski", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 106}, {"final": 0.0, "codigo": "CV-027", "nombre": "Chelón de Doña Pepa", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 127}, {"final": 0.0, "codigo": "CV-015", "nombre": "Chicha Tu Mare", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 115}, {"final": 0.0, "codigo": "S-024", "nombre": "Chimay Roja", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 34}, {"final": 0.0, "codigo": "SS-007", "nombre": "Chimi churri", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 43}, {"final": 0.0, "codigo": "V-009", "nombre": "Choclo", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 9}, {"final": 0.0, "codigo": "C-002", "nombre": "Chorizo", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 65}, {"final": 0.0, "codigo": "C-008", "nombre": "Chorizo finas hierbas", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 71}, {"final": 0.0, "codigo": "T-008", "nombre": "Cinzano", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 97}, {"final": 0.0, "codigo": "B-003", "nombre": "Coca Cola", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 77}, {"final": 0.0, "codigo": "B-005", "nombre": "Coca Cola sin Azucar", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 79}, {"final": 0.0, "codigo": "PR-006", "nombre": "Cordon Blue", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 63}, {"final": 0.0, "codigo": "CV-028", "nombre": "Crazy Llama", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 128}, {"final": 0.0, "codigo": "L-007", "nombre": "Crema de leche", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 57}, {"final": 0.0, "codigo": "CV-002", "nombre": "Dámela Siempre", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 102}, {"final": 0.0, "codigo": "CV-025", "nombre": "Dark Krieger", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 125}, {"final": 0.0, "codigo": "S-020", "nombre": "Daura Damm - Sin Gluten", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 30}, {"final": 0.0, "codigo": "CV-023", "nombre": "De la Selva Su Gose", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 123}, {"final": 0.0, "codigo": "CV-026", "nombre": "De Peso Pumpkin Ale", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 126}, {"final": 0.0, "codigo": "S-026", "nombre": "Delirium Tremens", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 36}, {"final": 0.0, "codigo": "S-006", "nombre": "Empanizado", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 16}, {"final": 0.0, "codigo": "S-018", "nombre": "Esencia de Chicha", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 28}, {"final": 0.0, "codigo": "S-019", "nombre": "Estrella Damm - Sin alcohol", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 29}, {"final": 0.0, "codigo": "S-008", "nombre": "Fideos canuto", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 18}, {"final": 0.0, "codigo": "C-006", "nombre": "Filete de pollo", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 69}, {"final": 0.0, "codigo": "CV-008", "nombre": "Final Feliz", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 108}, {"final": 0.0, "codigo": "C-001", "nombre": "Frankfurter", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 64}, {"final": 0.0, "codigo": "S-005", "nombre": "Frejoles", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 15}, {"final": 0.0, "codigo": "T-011", "nombre": "Gin", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 100}, {"final": 0.0, "codigo": "CV-031", "nombre": "GRANADILLA", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 131}, {"final": 0.0, "codigo": "C-005", "nombre": "Hamburguesa 100g", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 68}, {"final": 0.0, "codigo": "C-010", "nombre": "Hamburguesa 200g", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 73}, {"final": 0.0, "codigo": "V-002", "nombre": "Hierba buena", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 2}, {"final": 0.0, "codigo": "S-012", "nombre": "Huevo", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 22}, {"final": 0.0, "codigo": "B-004", "nombre": "Inca Kola", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 78}, {"final": 0.0, "codigo": "B-006", "nombre": "Inca Kola sin Azucar", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 80}, {"final": 0.0, "codigo": "CV-032", "nombre": "INTERESTELAGER", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 132}, {"final": 0.0, "codigo": "T-001", "nombre": "Jager", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 90}, {"final": 0.0, "codigo": "S-016", "nombre": "Jarabe de frambuesa", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 26}, {"final": 0.0, "codigo": "S-014", "nombre": "Jarabe de goma", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 24}, {"final": 0.0, "codigo": "S-015", "nombre": "Jarabe de Sandía", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 25}, {"final": 0.0, "codigo": "CV-011", "nombre": "K-7", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 111}, {"final": 0.0, "codigo": "CV-024", "nombre": "Krieger", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 124}, {"final": 0.0, "codigo": "CV-005", "nombre": "L.I.M.A", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 105}, {"final": 0.0, "codigo": "CV-003", "nombre": "La Nena", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 103}, {"final": 0.0, "codigo": "CV-022", "nombre": "La Última Chupada del Mango", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 122}, {"final": 0.0, "codigo": "V-008", "nombre": "Lechuga", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 8}, {"final": 0.0, "codigo": "V-001", "nombre": "Limón", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 1}, {"final": 0.0, "codigo": "S-021", "nombre": "Lindermans Kriek", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 31}, {"final": 0.0, "codigo": "CV-013", "nombre": "Lou", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 113}, {"final": 0.0, "codigo": "CV-001", "nombre": "Magic Quinua", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 101}, {"final": 0.0, "codigo": "CV-012", "nombre": "Mañanero", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 112}, {"final": 0.0, "codigo": "S-017", "nombre": "Maracuya", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 27}, {"final": 0.0, "codigo": "T-010", "nombre": "Martini", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 99}, {"final": 0.0, "codigo": "L-003", "nombre": "Mayonesa de Yogurt", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 53}, {"final": 0.0, "codigo": "C-011", "nombre": "Medallón de lomo", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 74}, {"final": 0.0, "codigo": "B-015", "nombre": "Mr. Perkins Ginger Beer", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 89}, {"final": 0.0, "codigo": "B-014", "nombre": "Mr. Perkins Pink Soda", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 88}, {"final": 0.0, "codigo": "S-002", "nombre": "Nachos", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 12}, {"final": 0.0, "codigo": "S-013", "nombre": "Naranja deshidratada", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 23}, {"final": 0.0, "codigo": "CV-019", "nombre": "Oktu-Brefest", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 119}, {"final": 0.0, "codigo": "V-007", "nombre": "Palta", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 7}, {"final": 0.0, "codigo": "S-027", "nombre": "Pan Hamburguesa", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 140}, {"final": 0.0, "codigo": "V-003", "nombre": "Papa", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 3}, {"final": 0.0, "codigo": "CV-014", "nombre": "Peaky Biter", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 114}, {"final": 0.0, "codigo": "C-003", "nombre": "Pechuga de Pollo", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 66}, {"final": 0.0, "codigo": "S-007", "nombre": "Pepinillos", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 17}, {"final": 0.0, "codigo": "S-025", "nombre": "Petrus Choco Cherry", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 35}, {"final": 0.0, "codigo": "S-004", "nombre": "Petti pan", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 14}, {"final": 0.0, "codigo": "V-006", "nombre": "Pimiento", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 6}, {"final": 0.0, "codigo": "T-005", "nombre": "Pisco", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 94}, {"final": 0.0, "codigo": "CV-033", "nombre": "POLVO ESTELAR", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 133}, {"final": 0.0, "codigo": "SS-008", "nombre": "Pulled Pork", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 44}, {"final": 0.0, "codigo": "PR-005", "nombre": "Pure", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 62}, {"final": 0.0, "codigo": "L-001", "nombre": "Queso cheddar", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 51}, {"final": 0.0, "codigo": "L-004", "nombre": "Queso fresco", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 54}, {"final": 0.0, "codigo": "L-002", "nombre": "Queso gouda", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 52}, {"final": 0.0, "codigo": "L-006", "nombre": "Queso parmesano", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 56}, {"final": 0.0, "codigo": "B-009", "nombre": "Red bull", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 83}, {"final": 0.0, "codigo": "B-013", "nombre": "Red Bull Green Edition", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 87}, {"final": 0.0, "codigo": "B-012", "nombre": "Red bull Red Edition", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 86}, {"final": 0.0, "codigo": "B-011", "nombre": "Red bull Sugar Free", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 85}, {"final": 0.0, "codigo": "B-010", "nombre": "Red bull Tropical Edition", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 84}, {"final": 0.0, "codigo": "T-003", "nombre": "Ron", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 92}, {"final": 0.0, "codigo": "S-001", "nombre": "Sal", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 11}, {"final": 0.0, "codigo": "SS-013", "nombre": "Salsa 4 piminetas", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 49}, {"final": 0.0, "codigo": "SS-003", "nombre": "Salsa Acevichada", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 39}, {"final": 0.0, "codigo": "SS-002", "nombre": "Salsa BBQ IPA", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 38}, {"final": 0.0, "codigo": "SS-004", "nombre": "Salsa Buffalo", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 40}, {"final": 0.0, "codigo": "SS-001", "nombre": "Salsa cheddar", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 37}, {"final": 0.0, "codigo": "SS-012", "nombre": "Salsa de chapiñón", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 48}, {"final": 0.0, "codigo": "SS-014", "nombre": "Salsa de ostión", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 50}, {"final": 0.0, "codigo": "SS-006", "nombre": "Salsa Mango Charapita", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 42}, {"final": 0.0, "codigo": "SS-011", "nombre": "Salsa mediterránea", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 47}, {"final": 0.0, "codigo": "SS-005", "nombre": "Salsa Picante Agridulce", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 41}, {"final": 0.0, "codigo": "S-022", "nombre": "San Bernardus ABT 12", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 32}, {"final": 0.0, "codigo": "B-001", "nombre": "Schweppes", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 75}, {"final": 0.0, "codigo": "S-010", "nombre": "Sillao", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 20}, {"final": 0.0, "codigo": "CV-018", "nombre": "St Patrick’s", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 118}, {"final": 0.0, "codigo": "PR-002", "nombre": "Tequeños de Queso", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 59}, {"final": 0.0, "codigo": "PR-003", "nombre": "Tequeños Pulled Pork", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 60}, {"final": 0.0, "codigo": "PR-001", "nombre": "Tequeños Ruleta Rusa", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 58}, {"final": 0.0, "codigo": "T-004", "nombre": "Tequila", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 93}, {"final": 0.0, "codigo": "CV-034", "nombre": "TINTO DE VERANO", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 134}, {"final": 0.0, "codigo": "C-004", "nombre": "Tocino", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 67}, {"final": 0.0, "codigo": "V-005", "nombre": "Tomate", "unidad": "Kg", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 5}, {"final": 0.0, "codigo": "S-003", "nombre": "Tortilla de maiz", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 13}, {"final": 0.0, "codigo": "CV-017", "nombre": "Tropical Nordic", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 117}, {"final": 0.0, "codigo": "CV-030", "nombre": "VALKIRIA", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 130}, {"final": 0.0, "codigo": "S-011", "nombre": "Vinagre tinto", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 21}, {"final": 0.0, "codigo": "T-006", "nombre": "Vodka", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 95}, {"final": 0.0, "codigo": "S-023", "nombre": "Westmalle Tripel", "unidad": "UNI", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 33}, {"final": 0.0, "codigo": "T-002", "nombre": "Whisky", "unidad": "L", "inicial": 0.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 91}]}
7	3	2026-09-29	2026-09-28 20:46:04.474283-05	\N	1	\N	\N
8	1	2026-09-29	2026-09-29 17:00:00-05	2026-09-30 04:30:00-05	1	1	{"ventas": [{"hora": null, "total": 96.0, "nombre": "174 IPA · 0.2 L", "cantidad": 8.0, "id_presentacion": 118}, {"hora": null, "total": 24.0, "nombre": "2 Más · 0.2 L", "cantidad": 2.0, "id_presentacion": 124}, {"hora": null, "total": 49.0, "nombre": "Delirium Tremens · 1 UNI", "cantidad": 1.0, "id_presentacion": 46}, {"hora": null, "total": 16.0, "nombre": "Botella de 174 IPA · 1 UNI", "cantidad": 1.0, "id_presentacion": 34}, {"hora": null, "total": 7.9, "nombre": "Agua con Gas · 1 UNI", "cantidad": 1.0, "id_presentacion": 53}], "inventario": [{"final": 12.4, "codigo": "CV-007", "nombre": "174 IPA", "unidad": "L", "inicial": 14.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.6, "entradas": 0.0, "id_producto": 107}], "salidas": 1.6, "entradas": 0.0, "id_producto": 107}, {"final": 13.6, "codigo": "CV-009", "nombre": "2 Más", "unidad": "L", "inicial": 14.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 0.4, "entradas": 0.0, "id_producto": 109}], "salidas": 0.4, "entradas": 0.0, "id_producto": 109}, {"final": 13.0, "codigo": "B-008", "nombre": "Agua con Gas", "unidad": "UNI", "inicial": 14.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 82}], "salidas": 1.0, "entradas": 0.0, "id_producto": 82}, {"final": 14.0, "codigo": "B-007", "nombre": "Agua sin gas", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 81}, {"final": 8.0, "codigo": "B-002", "nombre": "Agua tonica", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 76}, {"final": 4.0, "codigo": "SS-010", "nombre": "Aliño", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 46}, {"final": 14.0, "codigo": "C-009", "nombre": "Alitas", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 72}, {"final": 14.0, "codigo": "CV-029", "nombre": "Apagón", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 129}, {"final": 4.3, "codigo": "T-007", "nombre": "Aperol", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 96}, {"final": 8.0, "codigo": "PR-004", "nombre": "Aros de cebolla", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 61}, {"final": 4.0, "codigo": "S-009", "nombre": "Arroz", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 19}, {"final": 14.0, "codigo": "CV-004", "nombre": "Barbarian Red Ale", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 104}, {"final": 14.0, "codigo": "CV-016", "nombre": "Barbarov", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 116}, {"final": 4.0, "codigo": "SS-009", "nombre": "BBQ", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 45}, {"final": 14.0, "codigo": "CV-010", "nombre": "Belga Pa’ Ti", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 110}, {"final": 4.0, "codigo": "C-007", "nombre": "Bife angosto", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 70}, {"final": 4.0, "codigo": "L-005", "nombre": "Blue cheese", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 55}, {"final": 14.0, "codigo": "CV-020", "nombre": "Blueberry Gose", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 120}, {"final": 7.0, "codigo": "CV-035", "nombre": "Botella de 174 IPA", "unidad": "UNI", "inicial": 8.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 135}], "salidas": 1.0, "entradas": 0.0, "id_producto": 135}, {"final": 8.0, "codigo": "CV-037", "nombre": "Botella de L.I.M.A. Pale Ale", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 137}, {"final": 8.0, "codigo": "CV-036", "nombre": "Botella de La Nena Trigo", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 136}, {"final": 8.0, "codigo": "CV-038", "nombre": "Botella de Magic Quinua", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 138}, {"final": 8.0, "codigo": "CV-039", "nombre": "Botella de Red", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 139}, {"final": 4.3, "codigo": "T-009", "nombre": "Campari", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 98}, {"final": 14.0, "codigo": "CV-021", "nombre": "Camu Camu Maracuyá", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 121}, {"final": 4.0, "codigo": "V-004", "nombre": "Cebolla", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 4}, {"final": 4.0, "codigo": "V-010", "nombre": "Champiñones", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 10}, {"final": 14.0, "codigo": "CV-006", "nombre": "Chaski", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 106}, {"final": 14.0, "codigo": "CV-027", "nombre": "Chelón de Doña Pepa", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 127}, {"final": 14.0, "codigo": "CV-015", "nombre": "Chicha Tu Mare", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 115}, {"final": 4.0, "codigo": "S-024", "nombre": "Chimay Roja", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 34}, {"final": 4.0, "codigo": "SS-007", "nombre": "Chimi churri", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 43}, {"final": 4.0, "codigo": "V-009", "nombre": "Choclo", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 9}, {"final": 4.0, "codigo": "C-002", "nombre": "Chorizo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 65}, {"final": 4.0, "codigo": "C-008", "nombre": "Chorizo finas hierbas", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 71}, {"final": 4.3, "codigo": "T-008", "nombre": "Cinzano", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 97}, {"final": 14.0, "codigo": "B-003", "nombre": "Coca Cola", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 77}, {"final": 14.0, "codigo": "B-005", "nombre": "Coca Cola sin Azucar", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 79}, {"final": 4.0, "codigo": "PR-006", "nombre": "Cordon Blue", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 63}, {"final": 14.0, "codigo": "CV-028", "nombre": "Crazy Llama", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 128}, {"final": 4.0, "codigo": "L-007", "nombre": "Crema de leche", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 57}, {"final": 14.0, "codigo": "CV-002", "nombre": "Dámela Siempre", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 102}, {"final": 14.0, "codigo": "CV-025", "nombre": "Dark Krieger", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 125}, {"final": 8.0, "codigo": "S-020", "nombre": "Daura Damm - Sin Gluten", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 30}, {"final": 14.0, "codigo": "CV-023", "nombre": "De la Selva Su Gose", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 123}, {"final": 14.0, "codigo": "CV-026", "nombre": "De Peso Pumpkin Ale", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 126}, {"final": 6.0, "codigo": "S-026", "nombre": "Delirium Tremens", "unidad": "UNI", "inicial": 7.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 36}], "salidas": 1.0, "entradas": 0.0, "id_producto": 36}, {"final": 4.0, "codigo": "S-006", "nombre": "Empanizado", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 16}, {"final": 4.0, "codigo": "S-018", "nombre": "Esencia de Chicha", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 28}, {"final": 7.0, "codigo": "S-019", "nombre": "Estrella Damm - Sin alcohol", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 29}, {"final": 8.0, "codigo": "S-008", "nombre": "Fideos canuto", "unidad": "Kg", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 18}, {"final": 4.0, "codigo": "C-006", "nombre": "Filete de pollo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 69}, {"final": 14.0, "codigo": "CV-008", "nombre": "Final Feliz", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 108}, {"final": 4.0, "codigo": "C-001", "nombre": "Frankfurter", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 64}, {"final": 4.0, "codigo": "S-005", "nombre": "Frejoles", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 15}, {"final": 4.4, "codigo": "T-011", "nombre": "Gin", "unidad": "L", "inicial": 4.4, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 100}, {"final": 14.0, "codigo": "CV-031", "nombre": "GRANADILLA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 131}, {"final": 4.0, "codigo": "C-005", "nombre": "Hamburguesa 100g", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 68}, {"final": 4.0, "codigo": "C-010", "nombre": "Hamburguesa 200g", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 73}, {"final": 4.0, "codigo": "V-002", "nombre": "Hierba buena", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 2}, {"final": 8.0, "codigo": "S-012", "nombre": "Huevo", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 22}, {"final": 14.0, "codigo": "B-004", "nombre": "Inca Kola", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 78}, {"final": 14.0, "codigo": "B-006", "nombre": "Inca Kola sin Azucar", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 80}, {"final": 14.0, "codigo": "CV-032", "nombre": "INTERESTELAGER", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 132}, {"final": 4.3, "codigo": "T-001", "nombre": "Jager", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 90}, {"final": 4.0, "codigo": "S-016", "nombre": "Jarabe de frambuesa", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 26}, {"final": 4.0, "codigo": "S-014", "nombre": "Jarabe de goma", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 24}, {"final": 4.0, "codigo": "S-015", "nombre": "Jarabe de Sandía", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 25}, {"final": 14.0, "codigo": "CV-011", "nombre": "K-7", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 111}, {"final": 14.0, "codigo": "CV-024", "nombre": "Krieger", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 124}, {"final": 14.0, "codigo": "CV-005", "nombre": "L.I.M.A", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 105}, {"final": 14.0, "codigo": "CV-003", "nombre": "La Nena", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 103}, {"final": 14.0, "codigo": "CV-022", "nombre": "La Última Chupada del Mango", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 122}, {"final": 4.0, "codigo": "V-008", "nombre": "Lechuga", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 8}, {"final": 3.5, "codigo": "V-001", "nombre": "Limón", "unidad": "Kg", "inicial": 3.5, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 1}, {"final": 8.0, "codigo": "S-021", "nombre": "Lindermans Kriek", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 31}, {"final": 14.0, "codigo": "CV-013", "nombre": "Lou", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 113}, {"final": 14.0, "codigo": "CV-001", "nombre": "Magic Quinua", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 101}, {"final": 14.0, "codigo": "CV-012", "nombre": "Mañanero", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 112}, {"final": 4.0, "codigo": "S-017", "nombre": "Maracuya", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 27}, {"final": 4.3, "codigo": "T-010", "nombre": "Martini", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 99}, {"final": 4.0, "codigo": "L-003", "nombre": "Mayonesa de Yogurt", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 53}, {"final": 4.0, "codigo": "C-011", "nombre": "Medallón de lomo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 74}, {"final": 8.0, "codigo": "B-015", "nombre": "Mr. Perkins Ginger Beer", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 89}, {"final": 8.0, "codigo": "B-014", "nombre": "Mr. Perkins Pink Soda", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 88}, {"final": 4.0, "codigo": "S-002", "nombre": "Nachos", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 12}, {"final": 4.0, "codigo": "S-013", "nombre": "Naranja deshidratada", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 23}, {"final": 14.0, "codigo": "CV-019", "nombre": "Oktu-Brefest", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 119}, {"final": 4.0, "codigo": "V-007", "nombre": "Palta", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 7}, {"final": 8.0, "codigo": "S-027", "nombre": "Pan Hamburguesa", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 140}, {"final": 9.0, "codigo": "V-003", "nombre": "Papa", "unidad": "Kg", "inicial": 9.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 3}, {"final": 14.0, "codigo": "CV-014", "nombre": "Peaky Biter", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 114}, {"final": 4.0, "codigo": "C-003", "nombre": "Pechuga de Pollo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 66}, {"final": 4.0, "codigo": "S-007", "nombre": "Pepinillos", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 17}, {"final": 8.0, "codigo": "S-025", "nombre": "Petrus Choco Cherry", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 35}, {"final": 8.0, "codigo": "S-004", "nombre": "Petti pan", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 14}, {"final": 4.0, "codigo": "V-006", "nombre": "Pimiento", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 6}, {"final": 4.0, "codigo": "T-005", "nombre": "Pisco", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 94}, {"final": 14.0, "codigo": "CV-033", "nombre": "POLVO ESTELAR", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 133}, {"final": 4.0, "codigo": "SS-008", "nombre": "Pulled Pork", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 44}, {"final": 4.0, "codigo": "PR-005", "nombre": "Pure", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 62}, {"final": 4.0, "codigo": "L-001", "nombre": "Queso cheddar", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 51}, {"final": 4.0, "codigo": "L-004", "nombre": "Queso fresco", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 54}, {"final": 4.0, "codigo": "L-002", "nombre": "Queso gouda", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 52}, {"final": 4.0, "codigo": "L-006", "nombre": "Queso parmesano", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 56}, {"final": 8.0, "codigo": "B-009", "nombre": "Red bull", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 83}, {"final": 8.0, "codigo": "B-013", "nombre": "Red Bull Green Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 87}, {"final": 8.0, "codigo": "B-012", "nombre": "Red bull Red Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 86}, {"final": 8.0, "codigo": "B-011", "nombre": "Red bull Sugar Free", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 85}, {"final": 8.0, "codigo": "B-010", "nombre": "Red bull Tropical Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 84}, {"final": 4.3, "codigo": "T-003", "nombre": "Ron", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 92}, {"final": 4.0, "codigo": "S-001", "nombre": "Sal", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 11}, {"final": 4.0, "codigo": "SS-013", "nombre": "Salsa 4 piminetas", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 49}, {"final": 4.0, "codigo": "SS-003", "nombre": "Salsa Acevichada", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 39}, {"final": 4.0, "codigo": "SS-002", "nombre": "Salsa BBQ IPA", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 38}, {"final": 4.0, "codigo": "SS-004", "nombre": "Salsa Buffalo", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 40}, {"final": 4.0, "codigo": "SS-001", "nombre": "Salsa cheddar", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 37}, {"final": 4.0, "codigo": "SS-012", "nombre": "Salsa de chapiñón", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 48}, {"final": 4.0, "codigo": "SS-014", "nombre": "Salsa de ostión", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 50}, {"final": 4.0, "codigo": "SS-006", "nombre": "Salsa Mango Charapita", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 42}, {"final": 4.0, "codigo": "SS-011", "nombre": "Salsa mediterránea", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 47}, {"final": 4.0, "codigo": "SS-005", "nombre": "Salsa Picante Agridulce", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 41}, {"final": 8.0, "codigo": "S-022", "nombre": "San Bernardus ABT 12", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 32}, {"final": 8.0, "codigo": "B-001", "nombre": "Schweppes", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 75}, {"final": 4.0, "codigo": "S-010", "nombre": "Sillao", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 20}, {"final": 14.0, "codigo": "CV-018", "nombre": "St Patrick’s", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 118}, {"final": 8.0, "codigo": "PR-002", "nombre": "Tequeños de Queso", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 59}, {"final": 8.0, "codigo": "PR-003", "nombre": "Tequeños Pulled Pork", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 60}, {"final": 8.0, "codigo": "PR-001", "nombre": "Tequeños Ruleta Rusa", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 58}, {"final": 4.3, "codigo": "T-004", "nombre": "Tequila", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 93}, {"final": 14.0, "codigo": "CV-034", "nombre": "TINTO DE VERANO", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 134}, {"final": 4.0, "codigo": "C-004", "nombre": "Tocino", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 67}, {"final": 0.8, "codigo": "V-005", "nombre": "Tomate", "unidad": "Kg", "inicial": 0.8, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 5}, {"final": 4.0, "codigo": "S-003", "nombre": "Tortilla de maiz", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 13}, {"final": 14.0, "codigo": "CV-017", "nombre": "Tropical Nordic", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 117}, {"final": 14.0, "codigo": "CV-030", "nombre": "VALKIRIA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 130}, {"final": 4.0, "codigo": "S-011", "nombre": "Vinagre tinto", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 21}, {"final": 4.3, "codigo": "T-006", "nombre": "Vodka", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 95}, {"final": 7.0, "codigo": "S-023", "nombre": "Westmalle Tripel", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 33}, {"final": 4.3, "codigo": "T-002", "nombre": "Whisky", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 91}]}
9	1	2026-09-30	2026-09-30 17:00:00-05	2026-10-01 04:30:00-05	1	1	{"ventas": [{"hora": null, "total": 108.0, "nombre": "174 IPA · 0.2 L", "cantidad": 9.0, "id_presentacion": 118}, {"hora": null, "total": 24.0, "nombre": "2 Más · 0.2 L", "cantidad": 2.0, "id_presentacion": 124}, {"hora": null, "total": 15.8, "nombre": "Agua con Gas · 1 UNI", "cantidad": 2.0, "id_presentacion": 53}, {"hora": null, "total": 49.0, "nombre": "Delirium Tremens · 1 UNI", "cantidad": 1.0, "id_presentacion": 46}, {"hora": null, "total": 16.0, "nombre": "Botella de 174 IPA · 1 UNI", "cantidad": 1.0, "id_presentacion": 34}, {"hora": null, "total": 16.0, "nombre": "Botella de L.I.M.A. Pale Ale · 1 UNI", "cantidad": 1.0, "id_presentacion": 36}, {"hora": null, "total": 7.9, "nombre": "Agua sin gas · 1 UNI", "cantidad": 1.0, "id_presentacion": 52}], "inventario": [{"final": 10.6, "codigo": "CV-007", "nombre": "174 IPA", "unidad": "L", "inicial": 12.4, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.8, "entradas": 0.0, "id_producto": 107}], "salidas": 1.8, "entradas": 0.0, "id_producto": 107}, {"final": 13.2, "codigo": "CV-009", "nombre": "2 Más", "unidad": "L", "inicial": 13.6, "motivos": [{"motivo": "VENTA_SALON", "salidas": 0.4, "entradas": 0.0, "id_producto": 109}], "salidas": 0.4, "entradas": 0.0, "id_producto": 109}, {"final": 11.0, "codigo": "B-008", "nombre": "Agua con Gas", "unidad": "UNI", "inicial": 13.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 2.0, "entradas": 0.0, "id_producto": 82}], "salidas": 2.0, "entradas": 0.0, "id_producto": 82}, {"final": 13.0, "codigo": "B-007", "nombre": "Agua sin gas", "unidad": "UNI", "inicial": 14.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 81}], "salidas": 1.0, "entradas": 0.0, "id_producto": 81}, {"final": 8.0, "codigo": "B-002", "nombre": "Agua tonica", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 76}, {"final": 4.0, "codigo": "SS-010", "nombre": "Aliño", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 46}, {"final": 14.0, "codigo": "C-009", "nombre": "Alitas", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 72}, {"final": 14.0, "codigo": "CV-029", "nombre": "Apagón", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 129}, {"final": 4.3, "codigo": "T-007", "nombre": "Aperol", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 96}, {"final": 8.0, "codigo": "PR-004", "nombre": "Aros de cebolla", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 61}, {"final": 4.0, "codigo": "S-009", "nombre": "Arroz", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 19}, {"final": 14.0, "codigo": "CV-004", "nombre": "Barbarian Red Ale", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 104}, {"final": 14.0, "codigo": "CV-016", "nombre": "Barbarov", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 116}, {"final": 4.0, "codigo": "SS-009", "nombre": "BBQ", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 45}, {"final": 14.0, "codigo": "CV-010", "nombre": "Belga Pa’ Ti", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 110}, {"final": 4.0, "codigo": "C-007", "nombre": "Bife angosto", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 70}, {"final": 4.0, "codigo": "L-005", "nombre": "Blue cheese", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 55}, {"final": 14.0, "codigo": "CV-020", "nombre": "Blueberry Gose", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 120}, {"final": 6.0, "codigo": "CV-035", "nombre": "Botella de 174 IPA", "unidad": "UNI", "inicial": 7.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 135}], "salidas": 1.0, "entradas": 0.0, "id_producto": 135}, {"final": 7.0, "codigo": "CV-037", "nombre": "Botella de L.I.M.A. Pale Ale", "unidad": "UNI", "inicial": 8.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 137}], "salidas": 1.0, "entradas": 0.0, "id_producto": 137}, {"final": 8.0, "codigo": "CV-036", "nombre": "Botella de La Nena Trigo", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 136}, {"final": 8.0, "codigo": "CV-038", "nombre": "Botella de Magic Quinua", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 138}, {"final": 8.0, "codigo": "CV-039", "nombre": "Botella de Red", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 139}, {"final": 4.3, "codigo": "T-009", "nombre": "Campari", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 98}, {"final": 14.0, "codigo": "CV-021", "nombre": "Camu Camu Maracuyá", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 121}, {"final": 4.0, "codigo": "V-004", "nombre": "Cebolla", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 4}, {"final": 4.0, "codigo": "V-010", "nombre": "Champiñones", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 10}, {"final": 14.0, "codigo": "CV-006", "nombre": "Chaski", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 106}, {"final": 14.0, "codigo": "CV-027", "nombre": "Chelón de Doña Pepa", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 127}, {"final": 14.0, "codigo": "CV-015", "nombre": "Chicha Tu Mare", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 115}, {"final": 4.0, "codigo": "S-024", "nombre": "Chimay Roja", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 34}, {"final": 4.0, "codigo": "SS-007", "nombre": "Chimi churri", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 43}, {"final": 4.0, "codigo": "V-009", "nombre": "Choclo", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 9}, {"final": 4.0, "codigo": "C-002", "nombre": "Chorizo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 65}, {"final": 4.0, "codigo": "C-008", "nombre": "Chorizo finas hierbas", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 71}, {"final": 4.3, "codigo": "T-008", "nombre": "Cinzano", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 97}, {"final": 14.0, "codigo": "B-003", "nombre": "Coca Cola", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 77}, {"final": 14.0, "codigo": "B-005", "nombre": "Coca Cola sin Azucar", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 79}, {"final": 4.0, "codigo": "PR-006", "nombre": "Cordon Blue", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 63}, {"final": 14.0, "codigo": "CV-028", "nombre": "Crazy Llama", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 128}, {"final": 4.0, "codigo": "L-007", "nombre": "Crema de leche", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 57}, {"final": 14.0, "codigo": "CV-002", "nombre": "Dámela Siempre", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 102}, {"final": 14.0, "codigo": "CV-025", "nombre": "Dark Krieger", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 125}, {"final": 8.0, "codigo": "S-020", "nombre": "Daura Damm - Sin Gluten", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 30}, {"final": 14.0, "codigo": "CV-023", "nombre": "De la Selva Su Gose", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 123}, {"final": 14.0, "codigo": "CV-026", "nombre": "De Peso Pumpkin Ale", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 126}, {"final": 5.0, "codigo": "S-026", "nombre": "Delirium Tremens", "unidad": "UNI", "inicial": 6.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 36}], "salidas": 1.0, "entradas": 0.0, "id_producto": 36}, {"final": 4.0, "codigo": "S-006", "nombre": "Empanizado", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 16}, {"final": 4.0, "codigo": "S-018", "nombre": "Esencia de Chicha", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 28}, {"final": 7.0, "codigo": "S-019", "nombre": "Estrella Damm - Sin alcohol", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 29}, {"final": 8.0, "codigo": "S-008", "nombre": "Fideos canuto", "unidad": "Kg", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 18}, {"final": 4.0, "codigo": "C-006", "nombre": "Filete de pollo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 69}, {"final": 14.0, "codigo": "CV-008", "nombre": "Final Feliz", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 108}, {"final": 4.0, "codigo": "C-001", "nombre": "Frankfurter", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 64}, {"final": 4.0, "codigo": "S-005", "nombre": "Frejoles", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 15}, {"final": 4.4, "codigo": "T-011", "nombre": "Gin", "unidad": "L", "inicial": 4.4, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 100}, {"final": 14.0, "codigo": "CV-031", "nombre": "GRANADILLA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 131}, {"final": 4.0, "codigo": "C-005", "nombre": "Hamburguesa 100g", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 68}, {"final": 4.0, "codigo": "C-010", "nombre": "Hamburguesa 200g", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 73}, {"final": 4.0, "codigo": "V-002", "nombre": "Hierba buena", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 2}, {"final": 8.0, "codigo": "S-012", "nombre": "Huevo", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 22}, {"final": 14.0, "codigo": "B-004", "nombre": "Inca Kola", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 78}, {"final": 14.0, "codigo": "B-006", "nombre": "Inca Kola sin Azucar", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 80}, {"final": 14.0, "codigo": "CV-032", "nombre": "INTERESTELAGER", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 132}, {"final": 4.3, "codigo": "T-001", "nombre": "Jager", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 90}, {"final": 4.0, "codigo": "S-016", "nombre": "Jarabe de frambuesa", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 26}, {"final": 4.0, "codigo": "S-014", "nombre": "Jarabe de goma", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 24}, {"final": 4.0, "codigo": "S-015", "nombre": "Jarabe de Sandía", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 25}, {"final": 14.0, "codigo": "CV-011", "nombre": "K-7", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 111}, {"final": 14.0, "codigo": "CV-024", "nombre": "Krieger", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 124}, {"final": 14.0, "codigo": "CV-005", "nombre": "L.I.M.A", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 105}, {"final": 14.0, "codigo": "CV-003", "nombre": "La Nena", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 103}, {"final": 14.0, "codigo": "CV-022", "nombre": "La Última Chupada del Mango", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 122}, {"final": 4.0, "codigo": "V-008", "nombre": "Lechuga", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 8}, {"final": 3.5, "codigo": "V-001", "nombre": "Limón", "unidad": "Kg", "inicial": 3.5, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 1}, {"final": 8.0, "codigo": "S-021", "nombre": "Lindermans Kriek", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 31}, {"final": 14.0, "codigo": "CV-013", "nombre": "Lou", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 113}, {"final": 14.0, "codigo": "CV-001", "nombre": "Magic Quinua", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 101}, {"final": 14.0, "codigo": "CV-012", "nombre": "Mañanero", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 112}, {"final": 4.0, "codigo": "S-017", "nombre": "Maracuya", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 27}, {"final": 4.3, "codigo": "T-010", "nombre": "Martini", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 99}, {"final": 4.0, "codigo": "L-003", "nombre": "Mayonesa de Yogurt", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 53}, {"final": 4.0, "codigo": "C-011", "nombre": "Medallón de lomo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 74}, {"final": 8.0, "codigo": "B-015", "nombre": "Mr. Perkins Ginger Beer", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 89}, {"final": 8.0, "codigo": "B-014", "nombre": "Mr. Perkins Pink Soda", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 88}, {"final": 4.0, "codigo": "S-002", "nombre": "Nachos", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 12}, {"final": 4.0, "codigo": "S-013", "nombre": "Naranja deshidratada", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 23}, {"final": 14.0, "codigo": "CV-019", "nombre": "Oktu-Brefest", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 119}, {"final": 4.0, "codigo": "V-007", "nombre": "Palta", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 7}, {"final": 8.0, "codigo": "S-027", "nombre": "Pan Hamburguesa", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 140}, {"final": 9.0, "codigo": "V-003", "nombre": "Papa", "unidad": "Kg", "inicial": 9.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 3}, {"final": 14.0, "codigo": "CV-014", "nombre": "Peaky Biter", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 114}, {"final": 4.0, "codigo": "C-003", "nombre": "Pechuga de Pollo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 66}, {"final": 4.0, "codigo": "S-007", "nombre": "Pepinillos", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 17}, {"final": 8.0, "codigo": "S-025", "nombre": "Petrus Choco Cherry", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 35}, {"final": 8.0, "codigo": "S-004", "nombre": "Petti pan", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 14}, {"final": 4.0, "codigo": "V-006", "nombre": "Pimiento", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 6}, {"final": 4.0, "codigo": "T-005", "nombre": "Pisco", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 94}, {"final": 14.0, "codigo": "CV-033", "nombre": "POLVO ESTELAR", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 133}, {"final": 4.0, "codigo": "SS-008", "nombre": "Pulled Pork", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 44}, {"final": 4.0, "codigo": "PR-005", "nombre": "Pure", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 62}, {"final": 4.0, "codigo": "L-001", "nombre": "Queso cheddar", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 51}, {"final": 4.0, "codigo": "L-004", "nombre": "Queso fresco", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 54}, {"final": 4.0, "codigo": "L-002", "nombre": "Queso gouda", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 52}, {"final": 4.0, "codigo": "L-006", "nombre": "Queso parmesano", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 56}, {"final": 8.0, "codigo": "B-009", "nombre": "Red bull", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 83}, {"final": 8.0, "codigo": "B-013", "nombre": "Red Bull Green Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 87}, {"final": 8.0, "codigo": "B-012", "nombre": "Red bull Red Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 86}, {"final": 8.0, "codigo": "B-011", "nombre": "Red bull Sugar Free", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 85}, {"final": 8.0, "codigo": "B-010", "nombre": "Red bull Tropical Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 84}, {"final": 4.3, "codigo": "T-003", "nombre": "Ron", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 92}, {"final": 4.0, "codigo": "S-001", "nombre": "Sal", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 11}, {"final": 4.0, "codigo": "SS-013", "nombre": "Salsa 4 piminetas", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 49}, {"final": 4.0, "codigo": "SS-003", "nombre": "Salsa Acevichada", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 39}, {"final": 4.0, "codigo": "SS-002", "nombre": "Salsa BBQ IPA", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 38}, {"final": 4.0, "codigo": "SS-004", "nombre": "Salsa Buffalo", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 40}, {"final": 4.0, "codigo": "SS-001", "nombre": "Salsa cheddar", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 37}, {"final": 4.0, "codigo": "SS-012", "nombre": "Salsa de chapiñón", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 48}, {"final": 4.0, "codigo": "SS-014", "nombre": "Salsa de ostión", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 50}, {"final": 4.0, "codigo": "SS-006", "nombre": "Salsa Mango Charapita", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 42}, {"final": 4.0, "codigo": "SS-011", "nombre": "Salsa mediterránea", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 47}, {"final": 4.0, "codigo": "SS-005", "nombre": "Salsa Picante Agridulce", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 41}, {"final": 8.0, "codigo": "S-022", "nombre": "San Bernardus ABT 12", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 32}, {"final": 8.0, "codigo": "B-001", "nombre": "Schweppes", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 75}, {"final": 4.0, "codigo": "S-010", "nombre": "Sillao", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 20}, {"final": 14.0, "codigo": "CV-018", "nombre": "St Patrick’s", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 118}, {"final": 8.0, "codigo": "PR-002", "nombre": "Tequeños de Queso", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 59}, {"final": 8.0, "codigo": "PR-003", "nombre": "Tequeños Pulled Pork", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 60}, {"final": 8.0, "codigo": "PR-001", "nombre": "Tequeños Ruleta Rusa", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 58}, {"final": 4.3, "codigo": "T-004", "nombre": "Tequila", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 93}, {"final": 14.0, "codigo": "CV-034", "nombre": "TINTO DE VERANO", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 134}, {"final": 4.0, "codigo": "C-004", "nombre": "Tocino", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 67}, {"final": 0.8, "codigo": "V-005", "nombre": "Tomate", "unidad": "Kg", "inicial": 0.8, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 5}, {"final": 4.0, "codigo": "S-003", "nombre": "Tortilla de maiz", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 13}, {"final": 14.0, "codigo": "CV-017", "nombre": "Tropical Nordic", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 117}, {"final": 14.0, "codigo": "CV-030", "nombre": "VALKIRIA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 130}, {"final": 4.0, "codigo": "S-011", "nombre": "Vinagre tinto", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 21}, {"final": 4.3, "codigo": "T-006", "nombre": "Vodka", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 95}, {"final": 7.0, "codigo": "S-023", "nombre": "Westmalle Tripel", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 33}, {"final": 4.3, "codigo": "T-002", "nombre": "Whisky", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 91}]}
10	1	2026-10-01	2026-10-01 17:00:00-05	2026-10-02 04:30:00-05	1	1	{"ventas": [{"hora": null, "total": 120.0, "nombre": "174 IPA · 0.2 L", "cantidad": 10.0, "id_presentacion": 118}, {"hora": null, "total": 36.0, "nombre": "2 Más · 0.2 L", "cantidad": 3.0, "id_presentacion": 124}, {"hora": null, "total": 49.0, "nombre": "Delirium Tremens · 1 UNI", "cantidad": 1.0, "id_presentacion": 46}, {"hora": null, "total": 16.0, "nombre": "Botella de 174 IPA · 1 UNI", "cantidad": 1.0, "id_presentacion": 34}, {"hora": null, "total": 7.9, "nombre": "Agua con Gas · 1 UNI", "cantidad": 1.0, "id_presentacion": 53}], "inventario": [{"final": 8.6, "codigo": "CV-007", "nombre": "174 IPA", "unidad": "L", "inicial": 10.6, "motivos": [{"motivo": "VENTA_SALON", "salidas": 2.0, "entradas": 0.0, "id_producto": 107}], "salidas": 2.0, "entradas": 0.0, "id_producto": 107}, {"final": 12.6, "codigo": "CV-009", "nombre": "2 Más", "unidad": "L", "inicial": 13.2, "motivos": [{"motivo": "VENTA_SALON", "salidas": 0.6, "entradas": 0.0, "id_producto": 109}], "salidas": 0.6, "entradas": 0.0, "id_producto": 109}, {"final": 10.0, "codigo": "B-008", "nombre": "Agua con Gas", "unidad": "UNI", "inicial": 11.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 82}], "salidas": 1.0, "entradas": 0.0, "id_producto": 82}, {"final": 13.0, "codigo": "B-007", "nombre": "Agua sin gas", "unidad": "UNI", "inicial": 13.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 81}, {"final": 8.0, "codigo": "B-002", "nombre": "Agua tonica", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 76}, {"final": 4.0, "codigo": "SS-010", "nombre": "Aliño", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 46}, {"final": 14.0, "codigo": "C-009", "nombre": "Alitas", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 72}, {"final": 14.0, "codigo": "CV-029", "nombre": "Apagón", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 129}, {"final": 4.3, "codigo": "T-007", "nombre": "Aperol", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 96}, {"final": 8.0, "codigo": "PR-004", "nombre": "Aros de cebolla", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 61}, {"final": 4.0, "codigo": "S-009", "nombre": "Arroz", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 19}, {"final": 14.0, "codigo": "CV-004", "nombre": "Barbarian Red Ale", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 104}, {"final": 14.0, "codigo": "CV-016", "nombre": "Barbarov", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 116}, {"final": 4.0, "codigo": "SS-009", "nombre": "BBQ", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 45}, {"final": 14.0, "codigo": "CV-010", "nombre": "Belga Pa’ Ti", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 110}, {"final": 4.0, "codigo": "C-007", "nombre": "Bife angosto", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 70}, {"final": 4.0, "codigo": "L-005", "nombre": "Blue cheese", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 55}, {"final": 14.0, "codigo": "CV-020", "nombre": "Blueberry Gose", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 120}, {"final": 5.0, "codigo": "CV-035", "nombre": "Botella de 174 IPA", "unidad": "UNI", "inicial": 6.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 135}], "salidas": 1.0, "entradas": 0.0, "id_producto": 135}, {"final": 7.0, "codigo": "CV-037", "nombre": "Botella de L.I.M.A. Pale Ale", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 137}, {"final": 8.0, "codigo": "CV-036", "nombre": "Botella de La Nena Trigo", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 136}, {"final": 8.0, "codigo": "CV-038", "nombre": "Botella de Magic Quinua", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 138}, {"final": 8.0, "codigo": "CV-039", "nombre": "Botella de Red", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 139}, {"final": 4.3, "codigo": "T-009", "nombre": "Campari", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 98}, {"final": 14.0, "codigo": "CV-021", "nombre": "Camu Camu Maracuyá", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 121}, {"final": 4.0, "codigo": "V-004", "nombre": "Cebolla", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 4}, {"final": 4.0, "codigo": "V-010", "nombre": "Champiñones", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 10}, {"final": 14.0, "codigo": "CV-006", "nombre": "Chaski", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 106}, {"final": 14.0, "codigo": "CV-027", "nombre": "Chelón de Doña Pepa", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 127}, {"final": 14.0, "codigo": "CV-015", "nombre": "Chicha Tu Mare", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 115}, {"final": 4.0, "codigo": "S-024", "nombre": "Chimay Roja", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 34}, {"final": 4.0, "codigo": "SS-007", "nombre": "Chimi churri", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 43}, {"final": 4.0, "codigo": "V-009", "nombre": "Choclo", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 9}, {"final": 4.0, "codigo": "C-002", "nombre": "Chorizo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 65}, {"final": 4.0, "codigo": "C-008", "nombre": "Chorizo finas hierbas", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 71}, {"final": 4.3, "codigo": "T-008", "nombre": "Cinzano", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 97}, {"final": 14.0, "codigo": "B-003", "nombre": "Coca Cola", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 77}, {"final": 14.0, "codigo": "B-005", "nombre": "Coca Cola sin Azucar", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 79}, {"final": 4.0, "codigo": "PR-006", "nombre": "Cordon Blue", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 63}, {"final": 14.0, "codigo": "CV-028", "nombre": "Crazy Llama", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 128}, {"final": 4.0, "codigo": "L-007", "nombre": "Crema de leche", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 57}, {"final": 14.0, "codigo": "CV-002", "nombre": "Dámela Siempre", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 102}, {"final": 14.0, "codigo": "CV-025", "nombre": "Dark Krieger", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 125}, {"final": 8.0, "codigo": "S-020", "nombre": "Daura Damm - Sin Gluten", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 30}, {"final": 14.0, "codigo": "CV-023", "nombre": "De la Selva Su Gose", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 123}, {"final": 14.0, "codigo": "CV-026", "nombre": "De Peso Pumpkin Ale", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 126}, {"final": 4.0, "codigo": "S-026", "nombre": "Delirium Tremens", "unidad": "UNI", "inicial": 5.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 36}], "salidas": 1.0, "entradas": 0.0, "id_producto": 36}, {"final": 4.0, "codigo": "S-006", "nombre": "Empanizado", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 16}, {"final": 4.0, "codigo": "S-018", "nombre": "Esencia de Chicha", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 28}, {"final": 7.0, "codigo": "S-019", "nombre": "Estrella Damm - Sin alcohol", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 29}, {"final": 8.0, "codigo": "S-008", "nombre": "Fideos canuto", "unidad": "Kg", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 18}, {"final": 4.0, "codigo": "C-006", "nombre": "Filete de pollo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 69}, {"final": 14.0, "codigo": "CV-008", "nombre": "Final Feliz", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 108}, {"final": 4.0, "codigo": "C-001", "nombre": "Frankfurter", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 64}, {"final": 4.0, "codigo": "S-005", "nombre": "Frejoles", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 15}, {"final": 4.4, "codigo": "T-011", "nombre": "Gin", "unidad": "L", "inicial": 4.4, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 100}, {"final": 14.0, "codigo": "CV-031", "nombre": "GRANADILLA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 131}, {"final": 4.0, "codigo": "C-005", "nombre": "Hamburguesa 100g", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 68}, {"final": 4.0, "codigo": "C-010", "nombre": "Hamburguesa 200g", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 73}, {"final": 4.0, "codigo": "V-002", "nombre": "Hierba buena", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 2}, {"final": 8.0, "codigo": "S-012", "nombre": "Huevo", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 22}, {"final": 14.0, "codigo": "B-004", "nombre": "Inca Kola", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 78}, {"final": 14.0, "codigo": "B-006", "nombre": "Inca Kola sin Azucar", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 80}, {"final": 14.0, "codigo": "CV-032", "nombre": "INTERESTELAGER", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 132}, {"final": 4.3, "codigo": "T-001", "nombre": "Jager", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 90}, {"final": 4.0, "codigo": "S-016", "nombre": "Jarabe de frambuesa", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 26}, {"final": 4.0, "codigo": "S-014", "nombre": "Jarabe de goma", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 24}, {"final": 4.0, "codigo": "S-015", "nombre": "Jarabe de Sandía", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 25}, {"final": 14.0, "codigo": "CV-011", "nombre": "K-7", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 111}, {"final": 14.0, "codigo": "CV-024", "nombre": "Krieger", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 124}, {"final": 14.0, "codigo": "CV-005", "nombre": "L.I.M.A", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 105}, {"final": 14.0, "codigo": "CV-003", "nombre": "La Nena", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 103}, {"final": 14.0, "codigo": "CV-022", "nombre": "La Última Chupada del Mango", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 122}, {"final": 4.0, "codigo": "V-008", "nombre": "Lechuga", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 8}, {"final": 3.5, "codigo": "V-001", "nombre": "Limón", "unidad": "Kg", "inicial": 3.5, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 1}, {"final": 8.0, "codigo": "S-021", "nombre": "Lindermans Kriek", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 31}, {"final": 14.0, "codigo": "CV-013", "nombre": "Lou", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 113}, {"final": 14.0, "codigo": "CV-001", "nombre": "Magic Quinua", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 101}, {"final": 14.0, "codigo": "CV-012", "nombre": "Mañanero", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 112}, {"final": 4.0, "codigo": "S-017", "nombre": "Maracuya", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 27}, {"final": 4.3, "codigo": "T-010", "nombre": "Martini", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 99}, {"final": 4.0, "codigo": "L-003", "nombre": "Mayonesa de Yogurt", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 53}, {"final": 4.0, "codigo": "C-011", "nombre": "Medallón de lomo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 74}, {"final": 8.0, "codigo": "B-015", "nombre": "Mr. Perkins Ginger Beer", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 89}, {"final": 8.0, "codigo": "B-014", "nombre": "Mr. Perkins Pink Soda", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 88}, {"final": 4.0, "codigo": "S-002", "nombre": "Nachos", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 12}, {"final": 4.0, "codigo": "S-013", "nombre": "Naranja deshidratada", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 23}, {"final": 14.0, "codigo": "CV-019", "nombre": "Oktu-Brefest", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 119}, {"final": 4.0, "codigo": "V-007", "nombre": "Palta", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 7}, {"final": 8.0, "codigo": "S-027", "nombre": "Pan Hamburguesa", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 140}, {"final": 9.0, "codigo": "V-003", "nombre": "Papa", "unidad": "Kg", "inicial": 9.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 3}, {"final": 14.0, "codigo": "CV-014", "nombre": "Peaky Biter", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 114}, {"final": 4.0, "codigo": "C-003", "nombre": "Pechuga de Pollo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 66}, {"final": 4.0, "codigo": "S-007", "nombre": "Pepinillos", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 17}, {"final": 8.0, "codigo": "S-025", "nombre": "Petrus Choco Cherry", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 35}, {"final": 8.0, "codigo": "S-004", "nombre": "Petti pan", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 14}, {"final": 4.0, "codigo": "V-006", "nombre": "Pimiento", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 6}, {"final": 4.0, "codigo": "T-005", "nombre": "Pisco", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 94}, {"final": 14.0, "codigo": "CV-033", "nombre": "POLVO ESTELAR", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 133}, {"final": 4.0, "codigo": "SS-008", "nombre": "Pulled Pork", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 44}, {"final": 4.0, "codigo": "PR-005", "nombre": "Pure", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 62}, {"final": 4.0, "codigo": "L-001", "nombre": "Queso cheddar", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 51}, {"final": 4.0, "codigo": "L-004", "nombre": "Queso fresco", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 54}, {"final": 4.0, "codigo": "L-002", "nombre": "Queso gouda", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 52}, {"final": 4.0, "codigo": "L-006", "nombre": "Queso parmesano", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 56}, {"final": 8.0, "codigo": "B-009", "nombre": "Red bull", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 83}, {"final": 8.0, "codigo": "B-013", "nombre": "Red Bull Green Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 87}, {"final": 8.0, "codigo": "B-012", "nombre": "Red bull Red Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 86}, {"final": 8.0, "codigo": "B-011", "nombre": "Red bull Sugar Free", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 85}, {"final": 8.0, "codigo": "B-010", "nombre": "Red bull Tropical Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 84}, {"final": 4.3, "codigo": "T-003", "nombre": "Ron", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 92}, {"final": 4.0, "codigo": "S-001", "nombre": "Sal", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 11}, {"final": 4.0, "codigo": "SS-013", "nombre": "Salsa 4 piminetas", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 49}, {"final": 4.0, "codigo": "SS-003", "nombre": "Salsa Acevichada", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 39}, {"final": 4.0, "codigo": "SS-002", "nombre": "Salsa BBQ IPA", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 38}, {"final": 4.0, "codigo": "SS-004", "nombre": "Salsa Buffalo", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 40}, {"final": 4.0, "codigo": "SS-001", "nombre": "Salsa cheddar", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 37}, {"final": 4.0, "codigo": "SS-012", "nombre": "Salsa de chapiñón", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 48}, {"final": 4.0, "codigo": "SS-014", "nombre": "Salsa de ostión", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 50}, {"final": 4.0, "codigo": "SS-006", "nombre": "Salsa Mango Charapita", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 42}, {"final": 4.0, "codigo": "SS-011", "nombre": "Salsa mediterránea", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 47}, {"final": 4.0, "codigo": "SS-005", "nombre": "Salsa Picante Agridulce", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 41}, {"final": 8.0, "codigo": "S-022", "nombre": "San Bernardus ABT 12", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 32}, {"final": 8.0, "codigo": "B-001", "nombre": "Schweppes", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 75}, {"final": 4.0, "codigo": "S-010", "nombre": "Sillao", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 20}, {"final": 14.0, "codigo": "CV-018", "nombre": "St Patrick’s", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 118}, {"final": 8.0, "codigo": "PR-002", "nombre": "Tequeños de Queso", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 59}, {"final": 8.0, "codigo": "PR-003", "nombre": "Tequeños Pulled Pork", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 60}, {"final": 8.0, "codigo": "PR-001", "nombre": "Tequeños Ruleta Rusa", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 58}, {"final": 4.3, "codigo": "T-004", "nombre": "Tequila", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 93}, {"final": 14.0, "codigo": "CV-034", "nombre": "TINTO DE VERANO", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 134}, {"final": 4.0, "codigo": "C-004", "nombre": "Tocino", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 67}, {"final": 0.8, "codigo": "V-005", "nombre": "Tomate", "unidad": "Kg", "inicial": 0.8, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 5}, {"final": 4.0, "codigo": "S-003", "nombre": "Tortilla de maiz", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 13}, {"final": 14.0, "codigo": "CV-017", "nombre": "Tropical Nordic", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 117}, {"final": 14.0, "codigo": "CV-030", "nombre": "VALKIRIA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 130}, {"final": 4.0, "codigo": "S-011", "nombre": "Vinagre tinto", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 21}, {"final": 4.3, "codigo": "T-006", "nombre": "Vodka", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 95}, {"final": 7.0, "codigo": "S-023", "nombre": "Westmalle Tripel", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 33}, {"final": 4.3, "codigo": "T-002", "nombre": "Whisky", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 91}]}
11	1	2026-10-02	2026-10-02 17:00:00-05	2026-10-03 04:30:00-05	1	1	{"ventas": [{"hora": null, "total": 132.0, "nombre": "174 IPA · 0.2 L", "cantidad": 11.0, "id_presentacion": 118}, {"hora": null, "total": 24.0, "nombre": "2 Más · 0.2 L", "cantidad": 2.0, "id_presentacion": 124}, {"hora": null, "total": 49.0, "nombre": "Delirium Tremens · 1 UNI", "cantidad": 1.0, "id_presentacion": 46}, {"hora": null, "total": 16.0, "nombre": "Botella de 174 IPA · 1 UNI", "cantidad": 1.0, "id_presentacion": 34}, {"hora": null, "total": 16.0, "nombre": "Botella de L.I.M.A. Pale Ale · 1 UNI", "cantidad": 1.0, "id_presentacion": 36}, {"hora": null, "total": 7.9, "nombre": "Agua con Gas · 1 UNI", "cantidad": 1.0, "id_presentacion": 53}, {"hora": null, "total": 7.9, "nombre": "Agua sin gas · 1 UNI", "cantidad": 1.0, "id_presentacion": 52}], "inventario": [{"final": 6.4, "codigo": "CV-007", "nombre": "174 IPA", "unidad": "L", "inicial": 8.6, "motivos": [{"motivo": "VENTA_SALON", "salidas": 2.2, "entradas": 0.0, "id_producto": 107}], "salidas": 2.2, "entradas": 0.0, "id_producto": 107}, {"final": 12.2, "codigo": "CV-009", "nombre": "2 Más", "unidad": "L", "inicial": 12.6, "motivos": [{"motivo": "VENTA_SALON", "salidas": 0.4, "entradas": 0.0, "id_producto": 109}], "salidas": 0.4, "entradas": 0.0, "id_producto": 109}, {"final": 9.0, "codigo": "B-008", "nombre": "Agua con Gas", "unidad": "UNI", "inicial": 10.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 82}], "salidas": 1.0, "entradas": 0.0, "id_producto": 82}, {"final": 12.0, "codigo": "B-007", "nombre": "Agua sin gas", "unidad": "UNI", "inicial": 13.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 81}], "salidas": 1.0, "entradas": 0.0, "id_producto": 81}, {"final": 8.0, "codigo": "B-002", "nombre": "Agua tonica", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 76}, {"final": 4.0, "codigo": "SS-010", "nombre": "Aliño", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 46}, {"final": 14.0, "codigo": "C-009", "nombre": "Alitas", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 72}, {"final": 14.0, "codigo": "CV-029", "nombre": "Apagón", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 129}, {"final": 4.3, "codigo": "T-007", "nombre": "Aperol", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 96}, {"final": 8.0, "codigo": "PR-004", "nombre": "Aros de cebolla", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 61}, {"final": 4.0, "codigo": "S-009", "nombre": "Arroz", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 19}, {"final": 14.0, "codigo": "CV-004", "nombre": "Barbarian Red Ale", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 104}, {"final": 14.0, "codigo": "CV-016", "nombre": "Barbarov", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 116}, {"final": 4.0, "codigo": "SS-009", "nombre": "BBQ", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 45}, {"final": 14.0, "codigo": "CV-010", "nombre": "Belga Pa’ Ti", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 110}, {"final": 4.0, "codigo": "C-007", "nombre": "Bife angosto", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 70}, {"final": 4.0, "codigo": "L-005", "nombre": "Blue cheese", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 55}, {"final": 14.0, "codigo": "CV-020", "nombre": "Blueberry Gose", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 120}, {"final": 4.0, "codigo": "CV-035", "nombre": "Botella de 174 IPA", "unidad": "UNI", "inicial": 5.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 135}], "salidas": 1.0, "entradas": 0.0, "id_producto": 135}, {"final": 6.0, "codigo": "CV-037", "nombre": "Botella de L.I.M.A. Pale Ale", "unidad": "UNI", "inicial": 7.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 137}], "salidas": 1.0, "entradas": 0.0, "id_producto": 137}, {"final": 8.0, "codigo": "CV-036", "nombre": "Botella de La Nena Trigo", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 136}, {"final": 8.0, "codigo": "CV-038", "nombre": "Botella de Magic Quinua", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 138}, {"final": 8.0, "codigo": "CV-039", "nombre": "Botella de Red", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 139}, {"final": 4.3, "codigo": "T-009", "nombre": "Campari", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 98}, {"final": 14.0, "codigo": "CV-021", "nombre": "Camu Camu Maracuyá", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 121}, {"final": 4.0, "codigo": "V-004", "nombre": "Cebolla", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 4}, {"final": 4.0, "codigo": "V-010", "nombre": "Champiñones", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 10}, {"final": 14.0, "codigo": "CV-006", "nombre": "Chaski", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 106}, {"final": 14.0, "codigo": "CV-027", "nombre": "Chelón de Doña Pepa", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 127}, {"final": 14.0, "codigo": "CV-015", "nombre": "Chicha Tu Mare", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 115}, {"final": 4.0, "codigo": "S-024", "nombre": "Chimay Roja", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 34}, {"final": 4.0, "codigo": "SS-007", "nombre": "Chimi churri", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 43}, {"final": 4.0, "codigo": "V-009", "nombre": "Choclo", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 9}, {"final": 4.0, "codigo": "C-002", "nombre": "Chorizo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 65}, {"final": 4.0, "codigo": "C-008", "nombre": "Chorizo finas hierbas", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 71}, {"final": 4.3, "codigo": "T-008", "nombre": "Cinzano", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 97}, {"final": 14.0, "codigo": "B-003", "nombre": "Coca Cola", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 77}, {"final": 14.0, "codigo": "B-005", "nombre": "Coca Cola sin Azucar", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 79}, {"final": 4.0, "codigo": "PR-006", "nombre": "Cordon Blue", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 63}, {"final": 14.0, "codigo": "CV-028", "nombre": "Crazy Llama", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 128}, {"final": 4.0, "codigo": "L-007", "nombre": "Crema de leche", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 57}, {"final": 14.0, "codigo": "CV-002", "nombre": "Dámela Siempre", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 102}, {"final": 14.0, "codigo": "CV-025", "nombre": "Dark Krieger", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 125}, {"final": 8.0, "codigo": "S-020", "nombre": "Daura Damm - Sin Gluten", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 30}, {"final": 14.0, "codigo": "CV-023", "nombre": "De la Selva Su Gose", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 123}, {"final": 14.0, "codigo": "CV-026", "nombre": "De Peso Pumpkin Ale", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 126}, {"final": 3.0, "codigo": "S-026", "nombre": "Delirium Tremens", "unidad": "UNI", "inicial": 4.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 36}], "salidas": 1.0, "entradas": 0.0, "id_producto": 36}, {"final": 4.0, "codigo": "S-006", "nombre": "Empanizado", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 16}, {"final": 4.0, "codigo": "S-018", "nombre": "Esencia de Chicha", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 28}, {"final": 7.0, "codigo": "S-019", "nombre": "Estrella Damm - Sin alcohol", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 29}, {"final": 8.0, "codigo": "S-008", "nombre": "Fideos canuto", "unidad": "Kg", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 18}, {"final": 4.0, "codigo": "C-006", "nombre": "Filete de pollo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 69}, {"final": 14.0, "codigo": "CV-008", "nombre": "Final Feliz", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 108}, {"final": 4.0, "codigo": "C-001", "nombre": "Frankfurter", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 64}, {"final": 4.0, "codigo": "S-005", "nombre": "Frejoles", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 15}, {"final": 4.4, "codigo": "T-011", "nombre": "Gin", "unidad": "L", "inicial": 4.4, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 100}, {"final": 14.0, "codigo": "CV-031", "nombre": "GRANADILLA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 131}, {"final": 4.0, "codigo": "C-005", "nombre": "Hamburguesa 100g", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 68}, {"final": 4.0, "codigo": "C-010", "nombre": "Hamburguesa 200g", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 73}, {"final": 4.0, "codigo": "V-002", "nombre": "Hierba buena", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 2}, {"final": 8.0, "codigo": "S-012", "nombre": "Huevo", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 22}, {"final": 14.0, "codigo": "B-004", "nombre": "Inca Kola", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 78}, {"final": 14.0, "codigo": "B-006", "nombre": "Inca Kola sin Azucar", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 80}, {"final": 14.0, "codigo": "CV-032", "nombre": "INTERESTELAGER", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 132}, {"final": 4.3, "codigo": "T-001", "nombre": "Jager", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 90}, {"final": 4.0, "codigo": "S-016", "nombre": "Jarabe de frambuesa", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 26}, {"final": 4.0, "codigo": "S-014", "nombre": "Jarabe de goma", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 24}, {"final": 4.0, "codigo": "S-015", "nombre": "Jarabe de Sandía", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 25}, {"final": 14.0, "codigo": "CV-011", "nombre": "K-7", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 111}, {"final": 14.0, "codigo": "CV-024", "nombre": "Krieger", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 124}, {"final": 14.0, "codigo": "CV-005", "nombre": "L.I.M.A", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 105}, {"final": 14.0, "codigo": "CV-003", "nombre": "La Nena", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 103}, {"final": 14.0, "codigo": "CV-022", "nombre": "La Última Chupada del Mango", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 122}, {"final": 4.0, "codigo": "V-008", "nombre": "Lechuga", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 8}, {"final": 3.5, "codigo": "V-001", "nombre": "Limón", "unidad": "Kg", "inicial": 3.5, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 1}, {"final": 8.0, "codigo": "S-021", "nombre": "Lindermans Kriek", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 31}, {"final": 14.0, "codigo": "CV-013", "nombre": "Lou", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 113}, {"final": 14.0, "codigo": "CV-001", "nombre": "Magic Quinua", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 101}, {"final": 14.0, "codigo": "CV-012", "nombre": "Mañanero", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 112}, {"final": 4.0, "codigo": "S-017", "nombre": "Maracuya", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 27}, {"final": 4.3, "codigo": "T-010", "nombre": "Martini", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 99}, {"final": 4.0, "codigo": "L-003", "nombre": "Mayonesa de Yogurt", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 53}, {"final": 4.0, "codigo": "C-011", "nombre": "Medallón de lomo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 74}, {"final": 8.0, "codigo": "B-015", "nombre": "Mr. Perkins Ginger Beer", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 89}, {"final": 8.0, "codigo": "B-014", "nombre": "Mr. Perkins Pink Soda", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 88}, {"final": 4.0, "codigo": "S-002", "nombre": "Nachos", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 12}, {"final": 4.0, "codigo": "S-013", "nombre": "Naranja deshidratada", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 23}, {"final": 14.0, "codigo": "CV-019", "nombre": "Oktu-Brefest", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 119}, {"final": 4.0, "codigo": "V-007", "nombre": "Palta", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 7}, {"final": 8.0, "codigo": "S-027", "nombre": "Pan Hamburguesa", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 140}, {"final": 9.0, "codigo": "V-003", "nombre": "Papa", "unidad": "Kg", "inicial": 9.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 3}, {"final": 14.0, "codigo": "CV-014", "nombre": "Peaky Biter", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 114}, {"final": 4.0, "codigo": "C-003", "nombre": "Pechuga de Pollo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 66}, {"final": 4.0, "codigo": "S-007", "nombre": "Pepinillos", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 17}, {"final": 8.0, "codigo": "S-025", "nombre": "Petrus Choco Cherry", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 35}, {"final": 8.0, "codigo": "S-004", "nombre": "Petti pan", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 14}, {"final": 4.0, "codigo": "V-006", "nombre": "Pimiento", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 6}, {"final": 4.0, "codigo": "T-005", "nombre": "Pisco", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 94}, {"final": 14.0, "codigo": "CV-033", "nombre": "POLVO ESTELAR", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 133}, {"final": 4.0, "codigo": "SS-008", "nombre": "Pulled Pork", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 44}, {"final": 4.0, "codigo": "PR-005", "nombre": "Pure", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 62}, {"final": 4.0, "codigo": "L-001", "nombre": "Queso cheddar", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 51}, {"final": 4.0, "codigo": "L-004", "nombre": "Queso fresco", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 54}, {"final": 4.0, "codigo": "L-002", "nombre": "Queso gouda", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 52}, {"final": 4.0, "codigo": "L-006", "nombre": "Queso parmesano", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 56}, {"final": 8.0, "codigo": "B-009", "nombre": "Red bull", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 83}, {"final": 8.0, "codigo": "B-013", "nombre": "Red Bull Green Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 87}, {"final": 8.0, "codigo": "B-012", "nombre": "Red bull Red Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 86}, {"final": 8.0, "codigo": "B-011", "nombre": "Red bull Sugar Free", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 85}, {"final": 8.0, "codigo": "B-010", "nombre": "Red bull Tropical Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 84}, {"final": 4.3, "codigo": "T-003", "nombre": "Ron", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 92}, {"final": 4.0, "codigo": "S-001", "nombre": "Sal", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 11}, {"final": 4.0, "codigo": "SS-013", "nombre": "Salsa 4 piminetas", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 49}, {"final": 4.0, "codigo": "SS-003", "nombre": "Salsa Acevichada", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 39}, {"final": 4.0, "codigo": "SS-002", "nombre": "Salsa BBQ IPA", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 38}, {"final": 4.0, "codigo": "SS-004", "nombre": "Salsa Buffalo", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 40}, {"final": 4.0, "codigo": "SS-001", "nombre": "Salsa cheddar", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 37}, {"final": 4.0, "codigo": "SS-012", "nombre": "Salsa de chapiñón", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 48}, {"final": 4.0, "codigo": "SS-014", "nombre": "Salsa de ostión", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 50}, {"final": 4.0, "codigo": "SS-006", "nombre": "Salsa Mango Charapita", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 42}, {"final": 4.0, "codigo": "SS-011", "nombre": "Salsa mediterránea", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 47}, {"final": 4.0, "codigo": "SS-005", "nombre": "Salsa Picante Agridulce", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 41}, {"final": 8.0, "codigo": "S-022", "nombre": "San Bernardus ABT 12", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 32}, {"final": 8.0, "codigo": "B-001", "nombre": "Schweppes", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 75}, {"final": 4.0, "codigo": "S-010", "nombre": "Sillao", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 20}, {"final": 14.0, "codigo": "CV-018", "nombre": "St Patrick’s", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 118}, {"final": 8.0, "codigo": "PR-002", "nombre": "Tequeños de Queso", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 59}, {"final": 8.0, "codigo": "PR-003", "nombre": "Tequeños Pulled Pork", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 60}, {"final": 8.0, "codigo": "PR-001", "nombre": "Tequeños Ruleta Rusa", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 58}, {"final": 4.3, "codigo": "T-004", "nombre": "Tequila", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 93}, {"final": 14.0, "codigo": "CV-034", "nombre": "TINTO DE VERANO", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 134}, {"final": 4.0, "codigo": "C-004", "nombre": "Tocino", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 67}, {"final": 0.8, "codigo": "V-005", "nombre": "Tomate", "unidad": "Kg", "inicial": 0.8, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 5}, {"final": 4.0, "codigo": "S-003", "nombre": "Tortilla de maiz", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 13}, {"final": 14.0, "codigo": "CV-017", "nombre": "Tropical Nordic", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 117}, {"final": 14.0, "codigo": "CV-030", "nombre": "VALKIRIA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 130}, {"final": 4.0, "codigo": "S-011", "nombre": "Vinagre tinto", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 21}, {"final": 4.3, "codigo": "T-006", "nombre": "Vodka", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 95}, {"final": 7.0, "codigo": "S-023", "nombre": "Westmalle Tripel", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 33}, {"final": 4.3, "codigo": "T-002", "nombre": "Whisky", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 91}]}
12	1	2026-10-03	2026-10-03 17:00:00-05	2026-10-04 04:30:00-05	1	1	{"ventas": [{"hora": null, "total": 144.0, "nombre": "174 IPA · 0.2 L", "cantidad": 12.0, "id_presentacion": 118}, {"hora": null, "total": 49.0, "nombre": "Delirium Tremens · 1 UNI", "cantidad": 1.0, "id_presentacion": 46}, {"hora": null, "total": 16.0, "nombre": "Botella de 174 IPA · 1 UNI", "cantidad": 1.0, "id_presentacion": 34}, {"hora": null, "total": 12.0, "nombre": "2 Más · 0.2 L", "cantidad": 1.0, "id_presentacion": 124}, {"hora": null, "total": 7.9, "nombre": "Agua con Gas · 1 UNI", "cantidad": 1.0, "id_presentacion": 53}], "inventario": [{"final": 4.0, "codigo": "CV-007", "nombre": "174 IPA", "unidad": "L", "inicial": 6.4, "motivos": [{"motivo": "VENTA_SALON", "salidas": 2.4, "entradas": 0.0, "id_producto": 107}], "salidas": 2.4, "entradas": 0.0, "id_producto": 107}, {"final": 12.0, "codigo": "CV-009", "nombre": "2 Más", "unidad": "L", "inicial": 12.2, "motivos": [{"motivo": "VENTA_SALON", "salidas": 0.2, "entradas": 0.0, "id_producto": 109}], "salidas": 0.2, "entradas": 0.0, "id_producto": 109}, {"final": 8.0, "codigo": "B-008", "nombre": "Agua con Gas", "unidad": "UNI", "inicial": 9.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 82}], "salidas": 1.0, "entradas": 0.0, "id_producto": 82}, {"final": 12.0, "codigo": "B-007", "nombre": "Agua sin gas", "unidad": "UNI", "inicial": 12.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 81}, {"final": 8.0, "codigo": "B-002", "nombre": "Agua tonica", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 76}, {"final": 4.0, "codigo": "SS-010", "nombre": "Aliño", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 46}, {"final": 14.0, "codigo": "C-009", "nombre": "Alitas", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 72}, {"final": 14.0, "codigo": "CV-029", "nombre": "Apagón", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 129}, {"final": 4.3, "codigo": "T-007", "nombre": "Aperol", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 96}, {"final": 8.0, "codigo": "PR-004", "nombre": "Aros de cebolla", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 61}, {"final": 4.0, "codigo": "S-009", "nombre": "Arroz", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 19}, {"final": 14.0, "codigo": "CV-004", "nombre": "Barbarian Red Ale", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 104}, {"final": 14.0, "codigo": "CV-016", "nombre": "Barbarov", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 116}, {"final": 4.0, "codigo": "SS-009", "nombre": "BBQ", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 45}, {"final": 14.0, "codigo": "CV-010", "nombre": "Belga Pa’ Ti", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 110}, {"final": 4.0, "codigo": "C-007", "nombre": "Bife angosto", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 70}, {"final": 4.0, "codigo": "L-005", "nombre": "Blue cheese", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 55}, {"final": 14.0, "codigo": "CV-020", "nombre": "Blueberry Gose", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 120}, {"final": 3.0, "codigo": "CV-035", "nombre": "Botella de 174 IPA", "unidad": "UNI", "inicial": 4.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 135}], "salidas": 1.0, "entradas": 0.0, "id_producto": 135}, {"final": 6.0, "codigo": "CV-037", "nombre": "Botella de L.I.M.A. Pale Ale", "unidad": "UNI", "inicial": 6.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 137}, {"final": 8.0, "codigo": "CV-036", "nombre": "Botella de La Nena Trigo", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 136}, {"final": 8.0, "codigo": "CV-038", "nombre": "Botella de Magic Quinua", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 138}, {"final": 8.0, "codigo": "CV-039", "nombre": "Botella de Red", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 139}, {"final": 4.3, "codigo": "T-009", "nombre": "Campari", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 98}, {"final": 14.0, "codigo": "CV-021", "nombre": "Camu Camu Maracuyá", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 121}, {"final": 4.0, "codigo": "V-004", "nombre": "Cebolla", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 4}, {"final": 4.0, "codigo": "V-010", "nombre": "Champiñones", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 10}, {"final": 14.0, "codigo": "CV-006", "nombre": "Chaski", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 106}, {"final": 14.0, "codigo": "CV-027", "nombre": "Chelón de Doña Pepa", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 127}, {"final": 14.0, "codigo": "CV-015", "nombre": "Chicha Tu Mare", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 115}, {"final": 4.0, "codigo": "S-024", "nombre": "Chimay Roja", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 34}, {"final": 4.0, "codigo": "SS-007", "nombre": "Chimi churri", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 43}, {"final": 4.0, "codigo": "V-009", "nombre": "Choclo", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 9}, {"final": 4.0, "codigo": "C-002", "nombre": "Chorizo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 65}, {"final": 4.0, "codigo": "C-008", "nombre": "Chorizo finas hierbas", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 71}, {"final": 4.3, "codigo": "T-008", "nombre": "Cinzano", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 97}, {"final": 14.0, "codigo": "B-003", "nombre": "Coca Cola", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 77}, {"final": 14.0, "codigo": "B-005", "nombre": "Coca Cola sin Azucar", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 79}, {"final": 4.0, "codigo": "PR-006", "nombre": "Cordon Blue", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 63}, {"final": 14.0, "codigo": "CV-028", "nombre": "Crazy Llama", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 128}, {"final": 4.0, "codigo": "L-007", "nombre": "Crema de leche", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 57}, {"final": 14.0, "codigo": "CV-002", "nombre": "Dámela Siempre", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 102}, {"final": 14.0, "codigo": "CV-025", "nombre": "Dark Krieger", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 125}, {"final": 8.0, "codigo": "S-020", "nombre": "Daura Damm - Sin Gluten", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 30}, {"final": 14.0, "codigo": "CV-023", "nombre": "De la Selva Su Gose", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 123}, {"final": 14.0, "codigo": "CV-026", "nombre": "De Peso Pumpkin Ale", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 126}, {"final": 2.0, "codigo": "S-026", "nombre": "Delirium Tremens", "unidad": "UNI", "inicial": 3.0, "motivos": [{"motivo": "VENTA_SALON", "salidas": 1.0, "entradas": 0.0, "id_producto": 36}], "salidas": 1.0, "entradas": 0.0, "id_producto": 36}, {"final": 4.0, "codigo": "S-006", "nombre": "Empanizado", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 16}, {"final": 4.0, "codigo": "S-018", "nombre": "Esencia de Chicha", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 28}, {"final": 7.0, "codigo": "S-019", "nombre": "Estrella Damm - Sin alcohol", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 29}, {"final": 8.0, "codigo": "S-008", "nombre": "Fideos canuto", "unidad": "Kg", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 18}, {"final": 4.0, "codigo": "C-006", "nombre": "Filete de pollo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 69}, {"final": 14.0, "codigo": "CV-008", "nombre": "Final Feliz", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 108}, {"final": 4.0, "codigo": "C-001", "nombre": "Frankfurter", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 64}, {"final": 4.0, "codigo": "S-005", "nombre": "Frejoles", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 15}, {"final": 4.4, "codigo": "T-011", "nombre": "Gin", "unidad": "L", "inicial": 4.4, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 100}, {"final": 14.0, "codigo": "CV-031", "nombre": "GRANADILLA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 131}, {"final": 4.0, "codigo": "C-005", "nombre": "Hamburguesa 100g", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 68}, {"final": 4.0, "codigo": "C-010", "nombre": "Hamburguesa 200g", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 73}, {"final": 4.0, "codigo": "V-002", "nombre": "Hierba buena", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 2}, {"final": 8.0, "codigo": "S-012", "nombre": "Huevo", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 22}, {"final": 14.0, "codigo": "B-004", "nombre": "Inca Kola", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 78}, {"final": 14.0, "codigo": "B-006", "nombre": "Inca Kola sin Azucar", "unidad": "UNI", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 80}, {"final": 14.0, "codigo": "CV-032", "nombre": "INTERESTELAGER", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 132}, {"final": 4.3, "codigo": "T-001", "nombre": "Jager", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 90}, {"final": 4.0, "codigo": "S-016", "nombre": "Jarabe de frambuesa", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 26}, {"final": 4.0, "codigo": "S-014", "nombre": "Jarabe de goma", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 24}, {"final": 4.0, "codigo": "S-015", "nombre": "Jarabe de Sandía", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 25}, {"final": 14.0, "codigo": "CV-011", "nombre": "K-7", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 111}, {"final": 14.0, "codigo": "CV-024", "nombre": "Krieger", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 124}, {"final": 14.0, "codigo": "CV-005", "nombre": "L.I.M.A", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 105}, {"final": 14.0, "codigo": "CV-003", "nombre": "La Nena", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 103}, {"final": 14.0, "codigo": "CV-022", "nombre": "La Última Chupada del Mango", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 122}, {"final": 4.0, "codigo": "V-008", "nombre": "Lechuga", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 8}, {"final": 3.5, "codigo": "V-001", "nombre": "Limón", "unidad": "Kg", "inicial": 3.5, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 1}, {"final": 8.0, "codigo": "S-021", "nombre": "Lindermans Kriek", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 31}, {"final": 14.0, "codigo": "CV-013", "nombre": "Lou", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 113}, {"final": 14.0, "codigo": "CV-001", "nombre": "Magic Quinua", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 101}, {"final": 14.0, "codigo": "CV-012", "nombre": "Mañanero", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 112}, {"final": 4.0, "codigo": "S-017", "nombre": "Maracuya", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 27}, {"final": 4.3, "codigo": "T-010", "nombre": "Martini", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 99}, {"final": 4.0, "codigo": "L-003", "nombre": "Mayonesa de Yogurt", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 53}, {"final": 4.0, "codigo": "C-011", "nombre": "Medallón de lomo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 74}, {"final": 8.0, "codigo": "B-015", "nombre": "Mr. Perkins Ginger Beer", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 89}, {"final": 8.0, "codigo": "B-014", "nombre": "Mr. Perkins Pink Soda", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 88}, {"final": 4.0, "codigo": "S-002", "nombre": "Nachos", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 12}, {"final": 4.0, "codigo": "S-013", "nombre": "Naranja deshidratada", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 23}, {"final": 14.0, "codigo": "CV-019", "nombre": "Oktu-Brefest", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 119}, {"final": 4.0, "codigo": "V-007", "nombre": "Palta", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 7}, {"final": 8.0, "codigo": "S-027", "nombre": "Pan Hamburguesa", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 140}, {"final": 9.0, "codigo": "V-003", "nombre": "Papa", "unidad": "Kg", "inicial": 9.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 3}, {"final": 14.0, "codigo": "CV-014", "nombre": "Peaky Biter", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 114}, {"final": 4.0, "codigo": "C-003", "nombre": "Pechuga de Pollo", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 66}, {"final": 4.0, "codigo": "S-007", "nombre": "Pepinillos", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 17}, {"final": 8.0, "codigo": "S-025", "nombre": "Petrus Choco Cherry", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 35}, {"final": 8.0, "codigo": "S-004", "nombre": "Petti pan", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 14}, {"final": 4.0, "codigo": "V-006", "nombre": "Pimiento", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 6}, {"final": 4.0, "codigo": "T-005", "nombre": "Pisco", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 94}, {"final": 14.0, "codigo": "CV-033", "nombre": "POLVO ESTELAR", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 133}, {"final": 4.0, "codigo": "SS-008", "nombre": "Pulled Pork", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 44}, {"final": 4.0, "codigo": "PR-005", "nombre": "Pure", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 62}, {"final": 4.0, "codigo": "L-001", "nombre": "Queso cheddar", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 51}, {"final": 4.0, "codigo": "L-004", "nombre": "Queso fresco", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 54}, {"final": 4.0, "codigo": "L-002", "nombre": "Queso gouda", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 52}, {"final": 4.0, "codigo": "L-006", "nombre": "Queso parmesano", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 56}, {"final": 8.0, "codigo": "B-009", "nombre": "Red bull", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 83}, {"final": 8.0, "codigo": "B-013", "nombre": "Red Bull Green Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 87}, {"final": 8.0, "codigo": "B-012", "nombre": "Red bull Red Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 86}, {"final": 8.0, "codigo": "B-011", "nombre": "Red bull Sugar Free", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 85}, {"final": 8.0, "codigo": "B-010", "nombre": "Red bull Tropical Edition", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 84}, {"final": 4.3, "codigo": "T-003", "nombre": "Ron", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 92}, {"final": 4.0, "codigo": "S-001", "nombre": "Sal", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 11}, {"final": 4.0, "codigo": "SS-013", "nombre": "Salsa 4 piminetas", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 49}, {"final": 4.0, "codigo": "SS-003", "nombre": "Salsa Acevichada", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 39}, {"final": 4.0, "codigo": "SS-002", "nombre": "Salsa BBQ IPA", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 38}, {"final": 4.0, "codigo": "SS-004", "nombre": "Salsa Buffalo", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 40}, {"final": 4.0, "codigo": "SS-001", "nombre": "Salsa cheddar", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 37}, {"final": 4.0, "codigo": "SS-012", "nombre": "Salsa de chapiñón", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 48}, {"final": 4.0, "codigo": "SS-014", "nombre": "Salsa de ostión", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 50}, {"final": 4.0, "codigo": "SS-006", "nombre": "Salsa Mango Charapita", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 42}, {"final": 4.0, "codigo": "SS-011", "nombre": "Salsa mediterránea", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 47}, {"final": 4.0, "codigo": "SS-005", "nombre": "Salsa Picante Agridulce", "unidad": "Kg", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 41}, {"final": 8.0, "codigo": "S-022", "nombre": "San Bernardus ABT 12", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 32}, {"final": 8.0, "codigo": "B-001", "nombre": "Schweppes", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 75}, {"final": 4.0, "codigo": "S-010", "nombre": "Sillao", "unidad": "L", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 20}, {"final": 14.0, "codigo": "CV-018", "nombre": "St Patrick’s", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 118}, {"final": 8.0, "codigo": "PR-002", "nombre": "Tequeños de Queso", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 59}, {"final": 8.0, "codigo": "PR-003", "nombre": "Tequeños Pulled Pork", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 60}, {"final": 8.0, "codigo": "PR-001", "nombre": "Tequeños Ruleta Rusa", "unidad": "UNI", "inicial": 8.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 58}, {"final": 4.3, "codigo": "T-004", "nombre": "Tequila", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 93}, {"final": 14.0, "codigo": "CV-034", "nombre": "TINTO DE VERANO", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 134}, {"final": 4.0, "codigo": "C-004", "nombre": "Tocino", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 67}, {"final": 0.8, "codigo": "V-005", "nombre": "Tomate", "unidad": "Kg", "inicial": 0.8, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 5}, {"final": 4.0, "codigo": "S-003", "nombre": "Tortilla de maiz", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 13}, {"final": 14.0, "codigo": "CV-017", "nombre": "Tropical Nordic", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 117}, {"final": 14.0, "codigo": "CV-030", "nombre": "VALKIRIA", "unidad": "L", "inicial": 14.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 130}, {"final": 4.0, "codigo": "S-011", "nombre": "Vinagre tinto", "unidad": "UNI", "inicial": 4.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 21}, {"final": 4.3, "codigo": "T-006", "nombre": "Vodka", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 95}, {"final": 7.0, "codigo": "S-023", "nombre": "Westmalle Tripel", "unidad": "UNI", "inicial": 7.0, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 33}, {"final": 4.3, "codigo": "T-002", "nombre": "Whisky", "unidad": "L", "inicial": 4.3, "motivos": [], "salidas": 0.0, "entradas": 0.0, "id_producto": 91}]}
13	1	2026-10-04	2026-10-03 17:06:20.837244-05	\N	1	\N	\N
\.


--
-- Data for Name: inventario_jornada_inicio; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventario_jornada_inicio (id_jornada, id_producto, cantidad) FROM stdin;
1	1	3.500
1	2	4.000
1	3	9.000
1	4	4.000
1	5	0.800
1	6	4.000
1	7	4.000
1	8	4.000
1	9	4.000
1	10	4.000
1	11	4.000
1	12	4.000
1	13	4.000
1	14	8.000
1	15	4.000
1	16	4.000
1	17	4.000
1	18	8.000
1	19	4.000
1	20	4.000
1	21	4.000
1	22	8.000
1	23	4.000
1	24	4.000
1	25	4.000
1	26	4.000
1	27	4.000
1	28	4.000
1	29	7.000
1	30	8.000
1	31	8.000
1	32	8.000
1	33	7.000
1	34	4.000
1	35	8.000
1	36	7.000
1	37	4.000
1	38	4.000
1	39	4.000
1	40	4.000
1	41	4.000
1	42	4.000
1	43	4.000
1	44	4.000
1	45	4.000
1	46	4.000
1	47	4.000
1	48	4.000
1	49	4.000
1	50	4.000
1	51	4.000
1	52	4.000
1	53	4.000
1	54	4.000
1	55	4.000
1	56	4.000
1	57	4.000
1	58	8.000
1	59	8.000
1	60	8.000
1	61	8.000
1	62	4.000
1	63	4.000
1	64	4.000
1	65	4.000
1	66	4.000
1	67	4.000
1	68	4.000
1	69	4.000
1	70	4.000
1	71	4.000
1	72	14.000
1	73	4.000
1	74	4.000
1	75	8.000
1	76	8.000
1	77	14.000
1	78	14.000
1	79	14.000
1	80	14.000
1	81	14.000
1	82	14.000
1	83	8.000
1	84	8.000
1	85	8.000
1	86	8.000
1	87	8.000
1	88	8.000
1	89	8.000
1	90	4.300
1	91	4.300
1	92	4.300
1	93	4.300
1	94	4.000
1	95	4.300
1	96	4.300
1	97	4.300
1	98	4.300
1	99	4.300
1	100	4.400
1	101	14.000
1	102	14.000
1	103	14.000
1	104	14.000
1	105	14.000
1	106	14.000
1	107	14.000
1	108	14.000
1	109	14.000
1	110	14.000
1	111	14.000
1	112	14.000
1	113	14.000
1	114	14.000
1	115	14.000
1	116	14.000
1	117	14.000
1	118	14.000
1	119	14.000
1	120	14.000
1	121	14.000
1	122	14.000
1	123	14.000
1	124	14.000
1	125	14.000
1	126	14.000
1	127	14.000
1	128	14.000
1	129	14.000
1	130	14.000
1	131	14.000
1	132	14.000
1	133	14.000
1	134	14.000
1	135	8.000
1	136	8.000
1	137	8.000
1	138	8.000
1	139	8.000
1	140	8.000
2	1	0.000
2	2	0.000
2	3	0.000
2	4	0.000
2	5	0.000
2	6	0.000
2	7	0.000
2	8	0.000
2	9	0.000
2	10	0.000
2	11	0.000
2	12	0.000
2	13	0.000
2	14	0.000
2	15	0.000
2	16	0.000
2	17	0.000
2	18	0.000
2	19	0.000
2	20	0.000
2	21	0.000
2	22	0.000
2	23	0.000
2	24	0.000
2	25	0.000
2	26	0.000
2	27	0.000
2	28	0.000
2	29	0.000
2	30	0.000
2	31	0.000
2	32	0.000
2	33	0.000
2	34	0.000
2	35	0.000
2	36	0.000
2	37	0.000
2	38	0.000
2	39	0.000
2	40	0.000
2	41	0.000
2	42	0.000
2	43	0.000
2	44	0.000
2	45	0.000
2	46	0.000
2	47	0.000
2	48	0.000
2	49	0.000
2	50	0.000
2	51	0.000
2	52	0.000
2	53	0.000
2	54	0.000
2	55	0.000
2	56	0.000
2	57	0.000
2	58	0.000
2	59	0.000
2	60	0.000
2	61	0.000
2	62	0.000
2	63	0.000
2	64	0.000
2	65	0.000
2	66	0.000
2	67	0.000
2	68	0.000
2	69	0.000
2	70	0.000
2	71	0.000
2	72	0.000
2	73	0.000
2	74	0.000
2	75	0.000
2	76	0.000
2	77	0.000
2	78	0.000
2	79	0.000
2	80	0.000
2	81	0.000
2	82	0.000
2	83	0.000
2	84	0.000
2	85	0.000
2	86	0.000
2	87	0.000
2	88	0.000
2	89	0.000
2	90	0.000
2	91	0.000
2	92	0.000
2	93	0.000
2	94	0.000
2	95	0.000
2	96	0.000
2	97	0.000
2	98	0.000
2	99	0.000
2	100	0.000
2	101	0.000
2	102	0.000
2	103	0.000
2	104	0.000
2	105	0.000
2	106	0.000
2	107	0.000
2	108	0.000
2	109	0.000
2	110	0.000
2	111	0.000
2	112	0.000
2	113	0.000
2	114	0.000
2	115	0.000
2	116	0.000
2	117	0.000
2	118	0.000
2	119	0.000
2	120	0.000
2	121	0.000
2	122	0.000
2	123	0.000
2	124	0.000
2	125	0.000
2	126	0.000
2	127	0.000
2	128	0.000
2	129	0.000
2	130	0.000
2	131	0.000
2	132	0.000
2	133	0.000
2	134	0.000
2	135	0.000
2	136	0.000
2	137	0.000
2	138	0.000
2	139	0.000
2	140	0.000
3	1	0.000
3	2	0.000
3	3	0.000
3	4	0.000
3	5	0.000
3	6	0.000
3	7	0.000
3	8	0.000
3	9	0.000
3	10	0.000
3	11	0.000
3	12	0.000
3	13	0.000
3	14	0.000
3	15	0.000
3	16	0.000
3	17	0.000
3	18	0.000
3	19	0.000
3	20	0.000
3	21	0.000
3	22	0.000
3	23	0.000
3	24	0.000
3	25	0.000
3	26	0.000
3	27	0.000
3	28	0.000
3	29	0.000
3	30	0.000
3	31	0.000
3	32	0.000
3	33	0.000
3	34	0.000
3	35	0.000
3	36	0.000
3	37	0.000
3	38	0.000
3	39	0.000
3	40	0.000
3	41	0.000
3	42	0.000
3	43	0.000
3	44	0.000
3	45	0.000
3	46	0.000
3	47	0.000
3	48	0.000
3	49	0.000
3	50	0.000
3	51	0.000
3	52	0.000
3	53	0.000
3	54	0.000
3	55	0.000
3	56	0.000
3	57	0.000
3	58	0.000
3	59	0.000
3	60	0.000
3	61	0.000
3	62	0.000
3	63	0.000
3	64	0.000
3	65	0.000
3	66	0.000
3	67	0.000
3	68	0.000
3	69	0.000
3	70	0.000
3	71	0.000
3	72	0.000
3	73	0.000
3	74	0.000
3	75	0.000
3	76	0.000
3	77	0.000
3	78	0.000
3	79	0.000
3	80	0.000
3	81	0.000
3	82	0.000
3	83	0.000
3	84	0.000
3	85	0.000
3	86	0.000
3	87	0.000
3	88	0.000
3	89	0.000
3	90	0.000
3	91	0.000
3	92	0.000
3	93	0.000
3	94	0.000
3	95	0.000
3	96	0.000
3	97	0.000
3	98	0.000
3	99	0.000
3	100	0.000
3	101	0.000
3	102	0.000
3	103	0.000
3	104	0.000
3	105	0.000
3	106	0.000
3	107	0.000
3	108	0.000
3	109	0.000
3	110	0.000
3	111	0.000
3	112	0.000
3	113	0.000
3	114	0.000
3	115	0.000
3	116	0.000
3	117	0.000
3	118	0.000
3	119	0.000
3	120	0.000
3	121	0.000
3	122	0.000
3	123	0.000
3	124	0.000
3	125	0.000
3	126	0.000
3	127	0.000
3	128	0.000
3	129	0.000
3	130	0.000
3	131	0.000
3	132	0.000
3	133	0.000
3	134	0.000
3	135	0.000
3	136	0.000
3	137	0.000
3	138	0.000
3	139	0.000
3	140	0.000
4	1	0.000
4	2	0.000
4	3	0.000
4	4	0.000
4	5	0.000
4	6	0.000
4	7	0.000
4	8	0.000
4	9	0.000
4	10	0.000
4	11	0.000
4	12	0.000
4	13	0.000
4	14	0.000
4	15	0.000
4	16	0.000
4	17	0.000
4	18	0.000
4	19	0.000
4	20	0.000
4	21	0.000
4	22	0.000
4	23	0.000
4	24	0.000
4	25	0.000
4	26	0.000
4	27	0.000
4	28	0.000
4	29	0.000
4	30	0.000
4	31	0.000
4	32	0.000
4	33	0.000
4	34	0.000
4	35	0.000
4	36	0.000
4	37	0.000
4	38	0.000
4	39	0.000
4	40	0.000
4	41	0.000
4	42	0.000
4	43	0.000
4	44	0.000
4	45	0.000
4	46	0.000
4	47	0.000
4	48	0.000
4	49	0.000
4	50	0.000
4	51	0.000
4	52	0.000
4	53	0.000
4	54	0.000
4	55	0.000
4	56	0.000
4	57	0.000
4	58	0.000
4	59	0.000
4	60	0.000
4	61	0.000
4	62	0.000
4	63	0.000
4	64	0.000
4	65	0.000
4	66	0.000
4	67	0.000
4	68	0.000
4	69	0.000
4	70	0.000
4	71	0.000
4	72	0.000
4	73	0.000
4	74	0.000
4	75	0.000
4	76	0.000
4	77	0.000
4	78	0.000
4	79	0.000
4	80	0.000
4	81	0.000
4	82	0.000
4	83	0.000
4	84	0.000
4	85	0.000
4	86	0.000
4	87	0.000
4	88	0.000
4	89	0.000
4	90	0.000
4	91	0.000
4	92	0.000
4	93	0.000
4	94	0.000
4	95	0.000
4	96	0.000
4	97	0.000
4	98	0.000
4	99	0.000
4	100	0.000
4	101	0.000
4	102	0.000
4	103	0.000
4	104	0.000
4	105	0.000
4	106	0.000
4	107	0.000
4	108	0.000
4	109	0.000
4	110	0.000
4	111	0.000
4	112	0.000
4	113	0.000
4	114	0.000
4	115	0.000
4	116	0.000
4	117	0.000
4	118	0.000
4	119	0.000
4	120	0.000
4	121	0.000
4	122	0.000
4	123	0.000
4	124	0.000
4	125	0.000
4	126	0.000
4	127	0.000
4	128	0.000
4	129	0.000
4	130	0.000
4	131	0.000
4	132	0.000
4	133	0.000
4	134	0.000
4	135	0.000
4	136	0.000
4	137	0.000
4	138	0.000
4	139	0.000
4	140	0.000
5	1	3.500
5	2	4.000
5	3	9.000
5	4	4.000
5	5	0.800
5	6	4.000
5	7	4.000
5	8	4.000
5	9	4.000
5	10	4.000
5	11	4.000
5	12	4.000
5	13	4.000
5	14	8.000
5	15	4.000
5	16	4.000
5	17	4.000
5	18	8.000
5	19	4.000
5	20	4.000
5	21	4.000
5	22	8.000
5	23	4.000
5	24	4.000
5	25	4.000
5	26	4.000
5	27	4.000
5	28	4.000
5	29	7.000
5	30	8.000
5	31	8.000
5	32	8.000
5	33	7.000
5	34	4.000
5	35	8.000
5	36	7.000
5	37	4.000
5	38	4.000
5	39	4.000
5	40	4.000
5	41	4.000
5	42	4.000
5	43	4.000
5	44	4.000
5	45	4.000
5	46	4.000
5	47	4.000
5	48	4.000
5	49	4.000
5	50	4.000
5	51	4.000
5	52	4.000
5	53	4.000
5	54	4.000
5	55	4.000
5	56	4.000
5	57	4.000
5	58	8.000
5	59	8.000
5	60	8.000
5	61	8.000
5	62	4.000
5	63	4.000
5	64	4.000
5	65	4.000
5	66	4.000
5	67	4.000
5	68	4.000
5	69	4.000
5	70	4.000
5	71	4.000
5	72	14.000
5	73	4.000
5	74	4.000
5	75	8.000
5	76	8.000
5	77	14.000
5	78	14.000
5	79	14.000
5	80	14.000
5	81	14.000
5	82	14.000
5	83	8.000
5	84	8.000
5	85	8.000
5	86	8.000
5	87	8.000
5	88	8.000
5	89	8.000
5	90	4.300
5	91	4.300
5	92	4.300
5	93	4.300
5	94	4.000
5	95	4.300
5	96	4.300
5	97	4.300
5	98	4.300
5	99	4.300
5	100	4.400
5	101	14.000
5	102	14.000
5	103	14.000
5	104	14.000
5	105	14.000
5	106	14.000
5	107	14.000
5	108	14.000
5	109	14.000
5	110	14.000
5	111	14.000
5	112	14.000
5	113	14.000
5	114	14.000
5	115	14.000
5	116	14.000
5	117	14.000
5	118	14.000
5	119	14.000
5	120	14.000
5	121	14.000
5	122	14.000
5	123	14.000
5	124	14.000
5	125	14.000
5	126	14.000
5	127	14.000
5	128	14.000
5	129	14.000
5	130	14.000
5	131	14.000
5	132	14.000
5	133	14.000
5	134	14.000
5	135	8.000
5	136	8.000
5	137	8.000
5	138	8.000
5	139	8.000
5	140	8.000
6	1	0.000
6	2	0.000
6	3	0.000
6	4	0.000
6	5	0.000
6	6	0.000
6	7	0.000
6	8	0.000
6	9	0.000
6	10	0.000
6	11	0.000
6	12	0.000
6	13	0.000
6	14	0.000
6	15	0.000
6	16	0.000
6	17	0.000
6	18	0.000
6	19	0.000
6	20	0.000
6	21	0.000
6	22	0.000
6	23	0.000
6	24	0.000
6	25	0.000
6	26	0.000
6	27	0.000
6	28	0.000
6	29	0.000
6	30	0.000
6	31	0.000
6	32	0.000
6	33	0.000
6	34	0.000
6	35	0.000
6	36	0.000
6	37	0.000
6	38	0.000
6	39	0.000
6	40	0.000
6	41	0.000
6	42	0.000
6	43	0.000
6	44	0.000
6	45	0.000
6	46	0.000
6	47	0.000
6	48	0.000
6	49	0.000
6	50	0.000
6	51	0.000
6	52	0.000
6	53	0.000
6	54	0.000
6	55	0.000
6	56	0.000
6	57	0.000
6	58	0.000
6	59	0.000
6	60	0.000
6	61	0.000
6	62	0.000
6	63	0.000
6	64	0.000
6	65	0.000
6	66	0.000
6	67	0.000
6	68	0.000
6	69	0.000
6	70	0.000
6	71	0.000
6	72	0.000
6	73	0.000
6	74	0.000
6	75	0.000
6	76	0.000
6	77	0.000
6	78	0.000
6	79	0.000
6	80	0.000
6	81	0.000
6	82	0.000
6	83	0.000
6	84	0.000
6	85	0.000
6	86	0.000
6	87	0.000
6	88	0.000
6	89	0.000
6	90	0.000
6	91	0.000
6	92	0.000
6	93	0.000
6	94	0.000
6	95	0.000
6	96	0.000
6	97	0.000
6	98	0.000
6	99	0.000
6	100	0.000
6	101	0.000
6	102	0.000
6	103	0.000
6	104	0.000
6	105	0.000
6	106	0.000
6	107	0.000
6	108	0.000
6	109	0.000
6	110	0.000
6	111	0.000
6	112	0.000
6	113	0.000
6	114	0.000
6	115	0.000
6	116	0.000
6	117	0.000
6	118	0.000
6	119	0.000
6	120	0.000
6	121	0.000
6	122	0.000
6	123	0.000
6	124	0.000
6	125	0.000
6	126	0.000
6	127	0.000
6	128	0.000
6	129	0.000
6	130	0.000
6	131	0.000
6	132	0.000
6	133	0.000
6	134	0.000
6	135	0.000
6	136	0.000
6	137	0.000
6	138	0.000
6	139	0.000
6	140	0.000
7	1	0.000
7	2	0.000
7	3	0.000
7	4	0.000
7	5	0.000
7	6	0.000
7	7	0.000
7	8	0.000
7	9	0.000
7	10	0.000
7	11	0.000
7	12	0.000
7	13	0.000
7	14	0.000
7	15	0.000
7	16	0.000
7	17	0.000
7	18	0.000
7	19	0.000
7	20	0.000
7	21	0.000
7	22	0.000
7	23	0.000
7	24	0.000
7	25	0.000
7	26	0.000
7	27	0.000
7	28	0.000
7	29	0.000
7	30	0.000
7	31	0.000
7	32	0.000
7	33	0.000
7	34	0.000
7	35	0.000
7	36	0.000
7	37	0.000
7	38	0.000
7	39	0.000
7	40	0.000
7	41	0.000
7	42	0.000
7	43	0.000
7	44	0.000
7	45	0.000
7	46	0.000
7	47	0.000
7	48	0.000
7	49	0.000
7	50	0.000
7	51	0.000
7	52	0.000
7	53	0.000
7	54	0.000
7	55	0.000
7	56	0.000
7	57	0.000
7	58	0.000
7	59	0.000
7	60	0.000
7	61	0.000
7	62	0.000
7	63	0.000
7	64	0.000
7	65	0.000
7	66	0.000
7	67	0.000
7	68	0.000
7	69	0.000
7	70	0.000
7	71	0.000
7	72	0.000
7	73	0.000
7	74	0.000
7	75	0.000
7	76	0.000
7	77	0.000
7	78	0.000
7	79	0.000
7	80	0.000
7	81	0.000
7	82	0.000
7	83	0.000
7	84	0.000
7	85	0.000
7	86	0.000
7	87	0.000
7	88	0.000
7	89	0.000
7	90	0.000
7	91	0.000
7	92	0.000
7	93	0.000
7	94	0.000
7	95	0.000
7	96	0.000
7	97	0.000
7	98	0.000
7	99	0.000
7	100	0.000
7	101	0.000
7	102	0.000
7	103	0.000
7	104	0.000
7	105	0.000
7	106	0.000
7	107	0.000
7	108	0.000
7	109	0.000
7	110	0.000
7	111	0.000
7	112	0.000
7	113	0.000
7	114	0.000
7	115	0.000
7	116	0.000
7	117	0.000
7	118	0.000
7	119	0.000
7	120	0.000
7	121	0.000
7	122	0.000
7	123	0.000
7	124	0.000
7	125	0.000
7	126	0.000
7	127	0.000
7	128	0.000
7	129	0.000
7	130	0.000
7	131	0.000
7	132	0.000
7	133	0.000
7	134	0.000
7	135	0.000
7	136	0.000
7	137	0.000
7	138	0.000
7	139	0.000
7	140	0.000
8	1	3.500
8	2	4.000
8	3	9.000
8	4	4.000
8	5	0.800
8	6	4.000
8	7	4.000
8	8	4.000
8	9	4.000
8	10	4.000
8	11	4.000
8	12	4.000
8	13	4.000
8	14	8.000
8	15	4.000
8	16	4.000
8	17	4.000
8	18	8.000
8	19	4.000
8	20	4.000
8	21	4.000
8	22	8.000
8	23	4.000
8	24	4.000
8	25	4.000
8	26	4.000
8	27	4.000
8	28	4.000
8	29	7.000
8	30	8.000
8	31	8.000
8	32	8.000
8	33	7.000
8	34	4.000
8	35	8.000
8	36	7.000
8	37	4.000
8	38	4.000
8	39	4.000
8	40	4.000
8	41	4.000
8	42	4.000
8	43	4.000
8	44	4.000
8	45	4.000
8	46	4.000
8	47	4.000
8	48	4.000
8	49	4.000
8	50	4.000
8	51	4.000
8	52	4.000
8	53	4.000
8	54	4.000
8	55	4.000
8	56	4.000
8	57	4.000
8	58	8.000
8	59	8.000
8	60	8.000
8	61	8.000
8	62	4.000
8	63	4.000
8	64	4.000
8	65	4.000
8	66	4.000
8	67	4.000
8	68	4.000
8	69	4.000
8	70	4.000
8	71	4.000
8	72	14.000
8	73	4.000
8	74	4.000
8	75	8.000
8	76	8.000
8	77	14.000
8	78	14.000
8	79	14.000
8	80	14.000
8	81	14.000
8	82	14.000
8	83	8.000
8	84	8.000
8	85	8.000
8	86	8.000
8	87	8.000
8	88	8.000
8	89	8.000
8	90	4.300
8	91	4.300
8	92	4.300
8	93	4.300
8	94	4.000
8	95	4.300
8	96	4.300
8	97	4.300
8	98	4.300
8	99	4.300
8	100	4.400
8	101	14.000
8	102	14.000
8	103	14.000
8	104	14.000
8	105	14.000
8	106	14.000
8	107	14.000
8	108	14.000
8	109	14.000
8	110	14.000
8	111	14.000
8	112	14.000
8	113	14.000
8	114	14.000
8	115	14.000
8	116	14.000
8	117	14.000
8	118	14.000
8	119	14.000
8	120	14.000
8	121	14.000
8	122	14.000
8	123	14.000
8	124	14.000
8	125	14.000
8	126	14.000
8	127	14.000
8	128	14.000
8	129	14.000
8	130	14.000
8	131	14.000
8	132	14.000
8	133	14.000
8	134	14.000
8	135	8.000
8	136	8.000
8	137	8.000
8	138	8.000
8	139	8.000
8	140	8.000
9	1	3.500
9	2	4.000
9	3	9.000
9	4	4.000
9	5	0.800
9	6	4.000
9	7	4.000
9	8	4.000
9	9	4.000
9	10	4.000
9	11	4.000
9	12	4.000
9	13	4.000
9	14	8.000
9	15	4.000
9	16	4.000
9	17	4.000
9	18	8.000
9	19	4.000
9	20	4.000
9	21	4.000
9	22	8.000
9	23	4.000
9	24	4.000
9	25	4.000
9	26	4.000
9	27	4.000
9	28	4.000
9	29	7.000
9	30	8.000
9	31	8.000
9	32	8.000
9	33	7.000
9	34	4.000
9	35	8.000
9	36	6.000
9	37	4.000
9	38	4.000
9	39	4.000
9	40	4.000
9	41	4.000
9	42	4.000
9	43	4.000
9	44	4.000
9	45	4.000
9	46	4.000
9	47	4.000
9	48	4.000
9	49	4.000
9	50	4.000
9	51	4.000
9	52	4.000
9	53	4.000
9	54	4.000
9	55	4.000
9	56	4.000
9	57	4.000
9	58	8.000
9	59	8.000
9	60	8.000
9	61	8.000
9	62	4.000
9	63	4.000
9	64	4.000
9	65	4.000
9	66	4.000
9	67	4.000
9	68	4.000
9	69	4.000
9	70	4.000
9	71	4.000
9	72	14.000
9	73	4.000
9	74	4.000
9	75	8.000
9	76	8.000
9	77	14.000
9	78	14.000
9	79	14.000
9	80	14.000
9	81	14.000
9	82	13.000
9	83	8.000
9	84	8.000
9	85	8.000
9	86	8.000
9	87	8.000
9	88	8.000
9	89	8.000
9	90	4.300
9	91	4.300
9	92	4.300
9	93	4.300
9	94	4.000
9	95	4.300
9	96	4.300
9	97	4.300
9	98	4.300
9	99	4.300
9	100	4.400
9	101	14.000
9	102	14.000
9	103	14.000
9	104	14.000
9	105	14.000
9	106	14.000
9	107	12.400
9	108	14.000
9	109	13.600
9	110	14.000
9	111	14.000
9	112	14.000
9	113	14.000
9	114	14.000
9	115	14.000
9	116	14.000
9	117	14.000
9	118	14.000
9	119	14.000
9	120	14.000
9	121	14.000
9	122	14.000
9	123	14.000
9	124	14.000
9	125	14.000
9	126	14.000
9	127	14.000
9	128	14.000
9	129	14.000
9	130	14.000
9	131	14.000
9	132	14.000
9	133	14.000
9	134	14.000
9	135	7.000
9	136	8.000
9	137	8.000
9	138	8.000
9	139	8.000
9	140	8.000
10	1	3.500
10	2	4.000
10	3	9.000
10	4	4.000
10	5	0.800
10	6	4.000
10	7	4.000
10	8	4.000
10	9	4.000
10	10	4.000
10	11	4.000
10	12	4.000
10	13	4.000
10	14	8.000
10	15	4.000
10	16	4.000
10	17	4.000
10	18	8.000
10	19	4.000
10	20	4.000
10	21	4.000
10	22	8.000
10	23	4.000
10	24	4.000
10	25	4.000
10	26	4.000
10	27	4.000
10	28	4.000
10	29	7.000
10	30	8.000
10	31	8.000
10	32	8.000
10	33	7.000
10	34	4.000
10	35	8.000
10	36	5.000
10	37	4.000
10	38	4.000
10	39	4.000
10	40	4.000
10	41	4.000
10	42	4.000
10	43	4.000
10	44	4.000
10	45	4.000
10	46	4.000
10	47	4.000
10	48	4.000
10	49	4.000
10	50	4.000
10	51	4.000
10	52	4.000
10	53	4.000
10	54	4.000
10	55	4.000
10	56	4.000
10	57	4.000
10	58	8.000
10	59	8.000
10	60	8.000
10	61	8.000
10	62	4.000
10	63	4.000
10	64	4.000
10	65	4.000
10	66	4.000
10	67	4.000
10	68	4.000
10	69	4.000
10	70	4.000
10	71	4.000
10	72	14.000
10	73	4.000
10	74	4.000
10	75	8.000
10	76	8.000
10	77	14.000
10	78	14.000
10	79	14.000
10	80	14.000
10	81	13.000
10	82	11.000
10	83	8.000
10	84	8.000
10	85	8.000
10	86	8.000
10	87	8.000
10	88	8.000
10	89	8.000
10	90	4.300
10	91	4.300
10	92	4.300
10	93	4.300
10	94	4.000
10	95	4.300
10	96	4.300
10	97	4.300
10	98	4.300
10	99	4.300
10	100	4.400
10	101	14.000
10	102	14.000
10	103	14.000
10	104	14.000
10	105	14.000
10	106	14.000
10	107	10.600
10	108	14.000
10	109	13.200
10	110	14.000
10	111	14.000
10	112	14.000
10	113	14.000
10	114	14.000
10	115	14.000
10	116	14.000
10	117	14.000
10	118	14.000
10	119	14.000
10	120	14.000
10	121	14.000
10	122	14.000
10	123	14.000
10	124	14.000
10	125	14.000
10	126	14.000
10	127	14.000
10	128	14.000
10	129	14.000
10	130	14.000
10	131	14.000
10	132	14.000
10	133	14.000
10	134	14.000
10	135	6.000
10	136	8.000
10	137	7.000
10	138	8.000
10	139	8.000
10	140	8.000
11	1	3.500
11	2	4.000
11	3	9.000
11	4	4.000
11	5	0.800
11	6	4.000
11	7	4.000
11	8	4.000
11	9	4.000
11	10	4.000
11	11	4.000
11	12	4.000
11	13	4.000
11	14	8.000
11	15	4.000
11	16	4.000
11	17	4.000
11	18	8.000
11	19	4.000
11	20	4.000
11	21	4.000
11	22	8.000
11	23	4.000
11	24	4.000
11	25	4.000
11	26	4.000
11	27	4.000
11	28	4.000
11	29	7.000
11	30	8.000
11	31	8.000
11	32	8.000
11	33	7.000
11	34	4.000
11	35	8.000
11	36	4.000
11	37	4.000
11	38	4.000
11	39	4.000
11	40	4.000
11	41	4.000
11	42	4.000
11	43	4.000
11	44	4.000
11	45	4.000
11	46	4.000
11	47	4.000
11	48	4.000
11	49	4.000
11	50	4.000
11	51	4.000
11	52	4.000
11	53	4.000
11	54	4.000
11	55	4.000
11	56	4.000
11	57	4.000
11	58	8.000
11	59	8.000
11	60	8.000
11	61	8.000
11	62	4.000
11	63	4.000
11	64	4.000
11	65	4.000
11	66	4.000
11	67	4.000
11	68	4.000
11	69	4.000
11	70	4.000
11	71	4.000
11	72	14.000
11	73	4.000
11	74	4.000
11	75	8.000
11	76	8.000
11	77	14.000
11	78	14.000
11	79	14.000
11	80	14.000
11	81	13.000
11	82	10.000
11	83	8.000
11	84	8.000
11	85	8.000
11	86	8.000
11	87	8.000
11	88	8.000
11	89	8.000
11	90	4.300
11	91	4.300
11	92	4.300
11	93	4.300
11	94	4.000
11	95	4.300
11	96	4.300
11	97	4.300
11	98	4.300
11	99	4.300
11	100	4.400
11	101	14.000
11	102	14.000
11	103	14.000
11	104	14.000
11	105	14.000
11	106	14.000
11	107	8.600
11	108	14.000
11	109	12.600
11	110	14.000
11	111	14.000
11	112	14.000
11	113	14.000
11	114	14.000
11	115	14.000
11	116	14.000
11	117	14.000
11	118	14.000
11	119	14.000
11	120	14.000
11	121	14.000
11	122	14.000
11	123	14.000
11	124	14.000
11	125	14.000
11	126	14.000
11	127	14.000
11	128	14.000
11	129	14.000
11	130	14.000
11	131	14.000
11	132	14.000
11	133	14.000
11	134	14.000
11	135	5.000
11	136	8.000
11	137	7.000
11	138	8.000
11	139	8.000
11	140	8.000
12	1	3.500
12	2	4.000
12	3	9.000
12	4	4.000
12	5	0.800
12	6	4.000
12	7	4.000
12	8	4.000
12	9	4.000
12	10	4.000
12	11	4.000
12	12	4.000
12	13	4.000
12	14	8.000
12	15	4.000
12	16	4.000
12	17	4.000
12	18	8.000
12	19	4.000
12	20	4.000
12	21	4.000
12	22	8.000
12	23	4.000
12	24	4.000
12	25	4.000
12	26	4.000
12	27	4.000
12	28	4.000
12	29	7.000
12	30	8.000
12	31	8.000
12	32	8.000
12	33	7.000
12	34	4.000
12	35	8.000
12	36	3.000
12	37	4.000
12	38	4.000
12	39	4.000
12	40	4.000
12	41	4.000
12	42	4.000
12	43	4.000
12	44	4.000
12	45	4.000
12	46	4.000
12	47	4.000
12	48	4.000
12	49	4.000
12	50	4.000
12	51	4.000
12	52	4.000
12	53	4.000
12	54	4.000
12	55	4.000
12	56	4.000
12	57	4.000
12	58	8.000
12	59	8.000
12	60	8.000
12	61	8.000
12	62	4.000
12	63	4.000
12	64	4.000
12	65	4.000
12	66	4.000
12	67	4.000
12	68	4.000
12	69	4.000
12	70	4.000
12	71	4.000
12	72	14.000
12	73	4.000
12	74	4.000
12	75	8.000
12	76	8.000
12	77	14.000
12	78	14.000
12	79	14.000
12	80	14.000
12	81	12.000
12	82	9.000
12	83	8.000
12	84	8.000
12	85	8.000
12	86	8.000
12	87	8.000
12	88	8.000
12	89	8.000
12	90	4.300
12	91	4.300
12	92	4.300
12	93	4.300
12	94	4.000
12	95	4.300
12	96	4.300
12	97	4.300
12	98	4.300
12	99	4.300
12	100	4.400
12	101	14.000
12	102	14.000
12	103	14.000
12	104	14.000
12	105	14.000
12	106	14.000
12	107	6.400
12	108	14.000
12	109	12.200
12	110	14.000
12	111	14.000
12	112	14.000
12	113	14.000
12	114	14.000
12	115	14.000
12	116	14.000
12	117	14.000
12	118	14.000
12	119	14.000
12	120	14.000
12	121	14.000
12	122	14.000
12	123	14.000
12	124	14.000
12	125	14.000
12	126	14.000
12	127	14.000
12	128	14.000
12	129	14.000
12	130	14.000
12	131	14.000
12	132	14.000
12	133	14.000
12	134	14.000
12	135	4.000
12	136	8.000
12	137	6.000
12	138	8.000
12	139	8.000
12	140	8.000
13	1	3.500
13	2	4.000
13	3	9.000
13	4	4.000
13	5	0.800
13	6	4.000
13	7	4.000
13	8	4.000
13	9	4.000
13	10	4.000
13	11	4.000
13	12	4.000
13	13	4.000
13	14	8.000
13	15	4.000
13	16	4.000
13	17	4.000
13	18	8.000
13	19	4.000
13	20	4.000
13	21	4.000
13	22	8.000
13	23	4.000
13	24	4.000
13	25	4.000
13	26	4.000
13	27	4.000
13	28	4.000
13	29	7.000
13	30	8.000
13	31	8.000
13	32	8.000
13	33	7.000
13	34	4.000
13	35	8.000
13	36	2.000
13	37	4.000
13	38	4.000
13	39	4.000
13	40	4.000
13	41	4.000
13	42	4.000
13	43	4.000
13	44	4.000
13	45	4.000
13	46	4.000
13	47	4.000
13	48	4.000
13	49	4.000
13	50	4.000
13	51	4.000
13	52	4.000
13	53	4.000
13	54	4.000
13	55	4.000
13	56	4.000
13	57	4.000
13	58	8.000
13	59	8.000
13	60	8.000
13	61	8.000
13	62	4.000
13	63	4.000
13	64	4.000
13	65	4.000
13	66	4.000
13	67	4.000
13	68	4.000
13	69	4.000
13	70	4.000
13	71	4.000
13	72	14.000
13	73	4.000
13	74	4.000
13	75	8.000
13	76	8.000
13	77	14.000
13	78	14.000
13	79	14.000
13	80	14.000
13	81	12.000
13	82	8.000
13	83	8.000
13	84	8.000
13	85	8.000
13	86	8.000
13	87	8.000
13	88	8.000
13	89	8.000
13	90	4.300
13	91	4.300
13	92	4.300
13	93	4.300
13	94	4.000
13	95	4.300
13	96	4.300
13	97	4.300
13	98	4.300
13	99	4.300
13	100	4.400
13	101	14.000
13	102	14.000
13	103	14.000
13	104	14.000
13	105	14.000
13	106	14.000
13	107	4.000
13	108	14.000
13	109	12.000
13	110	14.000
13	111	14.000
13	112	14.000
13	113	14.000
13	114	14.000
13	115	14.000
13	116	14.000
13	117	14.000
13	118	14.000
13	119	14.000
13	120	14.000
13	121	14.000
13	122	14.000
13	123	14.000
13	124	14.000
13	125	14.000
13	126	14.000
13	127	14.000
13	128	14.000
13	129	14.000
13	130	14.000
13	131	14.000
13	132	14.000
13	133	14.000
13	134	14.000
13	135	3.000
13	136	8.000
13	137	6.000
13	138	8.000
13	139	8.000
13	140	8.000
\.


--
-- Data for Name: inventario_ronda; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventario_ronda (id_ronda, id_local, nombre, creado_por, creado_en, cerrado_en, por_puesto) FROM stdin;
1	1	Conteo de inventario - Miraflores - 28/09/2026	4	2026-09-28 21:00:09.679767-05	2026-09-28 21:10:22.068751-05	t
\.


--
-- Data for Name: inventario_saldo_inicial; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventario_saldo_inicial (id_local, id_producto, cantidad, creado_en) FROM stdin;
1	1	3.500	2026-09-26 13:53:03.737168-05
2	1	0.000	2026-09-26 13:53:03.739249-05
3	1	0.000	2026-09-26 13:53:03.739296-05
4	1	0.000	2026-09-26 13:53:03.739381-05
1	2	4.000	2026-09-26 13:53:03.739478-05
2	2	0.000	2026-09-26 13:53:03.739517-05
3	2	0.000	2026-09-26 13:53:03.739548-05
4	2	0.000	2026-09-26 13:53:03.739587-05
1	3	9.000	2026-09-26 13:53:03.739671-05
2	3	0.000	2026-09-26 13:53:03.739709-05
3	3	0.000	2026-09-26 13:53:03.739739-05
4	3	0.000	2026-09-26 13:53:03.739766-05
1	4	4.000	2026-09-26 13:53:03.739824-05
2	4	0.000	2026-09-26 13:53:03.739854-05
3	4	0.000	2026-09-26 13:53:03.739881-05
4	4	0.000	2026-09-26 13:53:03.739908-05
1	5	0.800	2026-09-26 13:53:03.739967-05
2	5	0.000	2026-09-26 13:53:03.739995-05
3	5	0.000	2026-09-26 13:53:03.740025-05
4	5	0.000	2026-09-26 13:53:03.740051-05
1	6	4.000	2026-09-26 13:53:03.740106-05
2	6	0.000	2026-09-26 13:53:03.740134-05
3	6	0.000	2026-09-26 13:53:03.74016-05
4	6	0.000	2026-09-26 13:53:03.740186-05
1	7	4.000	2026-09-26 13:53:03.740238-05
2	7	0.000	2026-09-26 13:53:03.740266-05
3	7	0.000	2026-09-26 13:53:03.740293-05
4	7	0.000	2026-09-26 13:53:03.740319-05
1	8	4.000	2026-09-26 13:53:03.74037-05
2	8	0.000	2026-09-26 13:53:03.740407-05
3	8	0.000	2026-09-26 13:53:03.740465-05
4	8	0.000	2026-09-26 13:53:03.740491-05
1	9	4.000	2026-09-26 13:53:03.740545-05
2	9	0.000	2026-09-26 13:53:03.740571-05
3	9	0.000	2026-09-26 13:53:03.740597-05
4	9	0.000	2026-09-26 13:53:03.740621-05
1	10	4.000	2026-09-26 13:53:03.740672-05
2	10	0.000	2026-09-26 13:53:03.740698-05
3	10	0.000	2026-09-26 13:53:03.740723-05
4	10	0.000	2026-09-26 13:53:03.740748-05
1	11	4.000	2026-09-26 13:53:03.740798-05
2	11	0.000	2026-09-26 13:53:03.740824-05
3	11	0.000	2026-09-26 13:53:03.740849-05
4	11	0.000	2026-09-26 13:53:03.740874-05
1	12	4.000	2026-09-26 13:53:03.740925-05
2	12	0.000	2026-09-26 13:53:03.74095-05
3	12	0.000	2026-09-26 13:53:03.740975-05
4	12	0.000	2026-09-26 13:53:03.741-05
1	13	4.000	2026-09-26 13:53:03.741051-05
2	13	0.000	2026-09-26 13:53:03.741076-05
3	13	0.000	2026-09-26 13:53:03.741101-05
4	13	0.000	2026-09-26 13:53:03.741126-05
1	14	8.000	2026-09-26 13:53:03.741177-05
2	14	0.000	2026-09-26 13:53:03.741203-05
3	14	0.000	2026-09-26 13:53:03.741228-05
4	14	0.000	2026-09-26 13:53:03.741253-05
1	15	4.000	2026-09-26 13:53:03.741305-05
2	15	0.000	2026-09-26 13:53:03.74133-05
3	15	0.000	2026-09-26 13:53:03.74136-05
4	15	0.000	2026-09-26 13:53:03.741394-05
1	16	4.000	2026-09-26 13:53:03.741447-05
2	16	0.000	2026-09-26 13:53:03.741473-05
3	16	0.000	2026-09-26 13:53:03.741498-05
4	16	0.000	2026-09-26 13:53:03.741524-05
1	17	4.000	2026-09-26 13:53:03.741576-05
2	17	0.000	2026-09-26 13:53:03.741601-05
3	17	0.000	2026-09-26 13:53:03.741626-05
4	17	0.000	2026-09-26 13:53:03.741651-05
1	18	8.000	2026-09-26 13:53:03.741707-05
2	18	0.000	2026-09-26 13:53:03.741733-05
3	18	0.000	2026-09-26 13:53:03.741758-05
4	18	0.000	2026-09-26 13:53:03.741783-05
1	19	4.000	2026-09-26 13:53:03.741834-05
2	19	0.000	2026-09-26 13:53:03.74186-05
3	19	0.000	2026-09-26 13:53:03.741885-05
4	19	0.000	2026-09-26 13:53:03.741909-05
1	20	4.000	2026-09-26 13:53:03.74196-05
2	20	0.000	2026-09-26 13:53:03.74199-05
3	20	0.000	2026-09-26 13:53:03.742016-05
4	20	0.000	2026-09-26 13:53:03.742041-05
1	21	4.000	2026-09-26 13:53:03.742093-05
2	21	0.000	2026-09-26 13:53:03.742118-05
3	21	0.000	2026-09-26 13:53:03.742143-05
4	21	0.000	2026-09-26 13:53:03.742168-05
1	22	8.000	2026-09-26 13:53:03.742219-05
2	22	0.000	2026-09-26 13:53:03.742245-05
3	22	0.000	2026-09-26 13:53:03.74229-05
4	22	0.000	2026-09-26 13:53:03.742316-05
1	23	4.000	2026-09-26 13:53:03.74237-05
2	23	0.000	2026-09-26 13:53:03.742395-05
3	23	0.000	2026-09-26 13:53:03.74242-05
4	23	0.000	2026-09-26 13:53:03.742445-05
1	24	4.000	2026-09-26 13:53:03.742496-05
2	24	0.000	2026-09-26 13:53:03.742521-05
3	24	0.000	2026-09-26 13:53:03.742546-05
4	24	0.000	2026-09-26 13:53:03.742571-05
1	25	4.000	2026-09-26 13:53:03.742622-05
2	25	0.000	2026-09-26 13:53:03.742647-05
3	25	0.000	2026-09-26 13:53:03.742672-05
4	25	0.000	2026-09-26 13:53:03.742697-05
1	26	4.000	2026-09-26 13:53:03.742749-05
2	26	0.000	2026-09-26 13:53:03.742775-05
3	26	0.000	2026-09-26 13:53:03.7428-05
4	26	0.000	2026-09-26 13:53:03.742825-05
1	27	4.000	2026-09-26 13:53:03.742876-05
2	27	0.000	2026-09-26 13:53:03.742902-05
3	27	0.000	2026-09-26 13:53:03.742928-05
4	27	0.000	2026-09-26 13:53:03.742954-05
1	28	4.000	2026-09-26 13:53:03.743008-05
2	28	0.000	2026-09-26 13:53:03.743038-05
3	28	0.000	2026-09-26 13:53:03.743065-05
4	28	0.000	2026-09-26 13:53:03.743094-05
1	29	7.000	2026-09-26 13:53:03.743162-05
2	29	0.000	2026-09-26 13:53:03.743194-05
3	29	0.000	2026-09-26 13:53:03.743222-05
4	29	0.000	2026-09-26 13:53:03.743252-05
1	30	8.000	2026-09-26 13:53:03.743314-05
2	30	0.000	2026-09-26 13:53:03.743342-05
3	30	0.000	2026-09-26 13:53:03.743369-05
4	30	0.000	2026-09-26 13:53:03.743404-05
1	31	8.000	2026-09-26 13:53:03.743459-05
2	31	0.000	2026-09-26 13:53:03.743485-05
3	31	0.000	2026-09-26 13:53:03.743511-05
4	31	0.000	2026-09-26 13:53:03.743538-05
1	32	8.000	2026-09-26 13:53:03.743591-05
2	32	0.000	2026-09-26 13:53:03.743618-05
3	32	0.000	2026-09-26 13:53:03.743648-05
4	32	0.000	2026-09-26 13:53:03.743676-05
1	33	7.000	2026-09-26 13:53:03.743732-05
2	33	0.000	2026-09-26 13:53:03.743759-05
3	33	0.000	2026-09-26 13:53:03.743785-05
4	33	0.000	2026-09-26 13:53:03.743811-05
1	34	4.000	2026-09-26 13:53:03.743866-05
2	34	0.000	2026-09-26 13:53:03.743892-05
3	34	0.000	2026-09-26 13:53:03.743917-05
4	34	0.000	2026-09-26 13:53:03.743942-05
1	35	8.000	2026-09-26 13:53:03.743999-05
2	35	0.000	2026-09-26 13:53:03.744026-05
3	35	0.000	2026-09-26 13:53:03.744051-05
4	35	0.000	2026-09-26 13:53:03.744077-05
1	36	7.000	2026-09-26 13:53:03.74413-05
2	36	0.000	2026-09-26 13:53:03.744156-05
3	36	0.000	2026-09-26 13:53:03.744181-05
4	36	0.000	2026-09-26 13:53:03.744565-05
1	37	4.000	2026-09-26 13:53:03.744677-05
2	37	0.000	2026-09-26 13:53:03.744726-05
3	37	0.000	2026-09-26 13:53:03.744771-05
4	37	0.000	2026-09-26 13:53:03.744815-05
1	38	4.000	2026-09-26 13:53:03.744917-05
2	38	0.000	2026-09-26 13:53:03.744965-05
3	38	0.000	2026-09-26 13:53:03.745009-05
4	38	0.000	2026-09-26 13:53:03.745053-05
1	39	4.000	2026-09-26 13:53:03.745144-05
2	39	0.000	2026-09-26 13:53:03.745201-05
3	39	0.000	2026-09-26 13:53:03.74525-05
4	39	0.000	2026-09-26 13:53:03.745293-05
1	40	4.000	2026-09-26 13:53:03.745391-05
2	40	0.000	2026-09-26 13:53:03.745473-05
3	40	0.000	2026-09-26 13:53:03.746201-05
4	40	0.000	2026-09-26 13:53:03.746234-05
1	41	4.000	2026-09-26 13:53:03.746301-05
2	41	0.000	2026-09-26 13:53:03.746331-05
3	41	0.000	2026-09-26 13:53:03.746356-05
4	41	0.000	2026-09-26 13:53:03.746383-05
1	42	4.000	2026-09-26 13:53:03.746437-05
2	42	0.000	2026-09-26 13:53:03.746463-05
3	42	0.000	2026-09-26 13:53:03.746489-05
4	42	0.000	2026-09-26 13:53:03.746514-05
1	43	4.000	2026-09-26 13:53:03.746585-05
2	43	0.000	2026-09-26 13:53:03.746619-05
3	43	0.000	2026-09-26 13:53:03.746653-05
4	43	0.000	2026-09-26 13:53:03.746685-05
1	44	4.000	2026-09-26 13:53:03.746744-05
2	44	0.000	2026-09-26 13:53:03.746777-05
3	44	0.000	2026-09-26 13:53:03.746804-05
4	44	0.000	2026-09-26 13:53:03.746829-05
1	45	4.000	2026-09-26 13:53:03.746881-05
2	45	0.000	2026-09-26 13:53:03.746907-05
3	45	0.000	2026-09-26 13:53:03.746948-05
4	45	0.000	2026-09-26 13:53:03.746977-05
1	46	4.000	2026-09-26 13:53:03.747035-05
2	46	0.000	2026-09-26 13:53:03.747063-05
3	46	0.000	2026-09-26 13:53:03.747088-05
4	46	0.000	2026-09-26 13:53:03.747113-05
1	47	4.000	2026-09-26 13:53:03.747164-05
2	47	0.000	2026-09-26 13:53:03.74719-05
3	47	0.000	2026-09-26 13:53:03.747215-05
4	47	0.000	2026-09-26 13:53:03.74724-05
1	48	4.000	2026-09-26 13:53:03.747291-05
2	48	0.000	2026-09-26 13:53:03.747316-05
3	48	0.000	2026-09-26 13:53:03.747342-05
4	48	0.000	2026-09-26 13:53:03.747366-05
1	49	4.000	2026-09-26 13:53:03.747417-05
2	49	0.000	2026-09-26 13:53:03.747442-05
3	49	0.000	2026-09-26 13:53:03.747467-05
4	49	0.000	2026-09-26 13:53:03.747491-05
1	50	4.000	2026-09-26 13:53:03.747549-05
2	50	0.000	2026-09-26 13:53:03.747576-05
3	50	0.000	2026-09-26 13:53:03.747601-05
4	50	0.000	2026-09-26 13:53:03.747626-05
1	51	4.000	2026-09-26 13:53:03.747704-05
2	51	0.000	2026-09-26 13:53:03.747731-05
3	51	0.000	2026-09-26 13:53:03.747757-05
4	51	0.000	2026-09-26 13:53:03.747782-05
1	52	4.000	2026-09-26 13:53:03.74784-05
2	52	0.000	2026-09-26 13:53:03.747867-05
3	52	0.000	2026-09-26 13:53:03.747892-05
4	52	0.000	2026-09-26 13:53:03.747918-05
1	53	4.000	2026-09-26 13:53:03.747971-05
2	53	0.000	2026-09-26 13:53:03.747997-05
3	53	0.000	2026-09-26 13:53:03.748022-05
4	53	0.000	2026-09-26 13:53:03.748047-05
1	54	4.000	2026-09-26 13:53:03.748098-05
2	54	0.000	2026-09-26 13:53:03.748124-05
3	54	0.000	2026-09-26 13:53:03.748149-05
4	54	0.000	2026-09-26 13:53:03.748174-05
1	55	4.000	2026-09-26 13:53:03.748225-05
2	55	0.000	2026-09-26 13:53:03.74825-05
3	55	0.000	2026-09-26 13:53:03.748281-05
4	55	0.000	2026-09-26 13:53:03.748308-05
1	56	4.000	2026-09-26 13:53:03.74836-05
2	56	0.000	2026-09-26 13:53:03.748386-05
3	56	0.000	2026-09-26 13:53:03.748411-05
4	56	0.000	2026-09-26 13:53:03.748436-05
1	57	4.000	2026-09-26 13:53:03.748486-05
2	57	0.000	2026-09-26 13:53:03.748512-05
3	57	0.000	2026-09-26 13:53:03.748537-05
4	57	0.000	2026-09-26 13:53:03.748563-05
1	58	8.000	2026-09-26 13:53:03.748617-05
2	58	0.000	2026-09-26 13:53:03.748643-05
3	58	0.000	2026-09-26 13:53:03.748668-05
4	58	0.000	2026-09-26 13:53:03.748693-05
1	59	8.000	2026-09-26 13:53:03.748744-05
2	59	0.000	2026-09-26 13:53:03.748769-05
3	59	0.000	2026-09-26 13:53:03.748794-05
4	59	0.000	2026-09-26 13:53:03.748819-05
1	60	8.000	2026-09-26 13:53:03.74887-05
2	60	0.000	2026-09-26 13:53:03.748895-05
3	60	0.000	2026-09-26 13:53:03.74892-05
4	60	0.000	2026-09-26 13:53:03.748945-05
1	61	8.000	2026-09-26 13:53:03.748995-05
2	61	0.000	2026-09-26 13:53:03.74902-05
3	61	0.000	2026-09-26 13:53:03.749046-05
4	61	0.000	2026-09-26 13:53:03.749071-05
1	62	4.000	2026-09-26 13:53:03.749123-05
2	62	0.000	2026-09-26 13:53:03.749149-05
3	62	0.000	2026-09-26 13:53:03.749174-05
4	62	0.000	2026-09-26 13:53:03.749199-05
1	63	4.000	2026-09-26 13:53:03.74925-05
2	63	0.000	2026-09-26 13:53:03.749276-05
3	63	0.000	2026-09-26 13:53:03.749301-05
4	63	0.000	2026-09-26 13:53:03.749326-05
1	64	4.000	2026-09-26 13:53:03.749376-05
2	64	0.000	2026-09-26 13:53:03.749401-05
3	64	0.000	2026-09-26 13:53:03.749427-05
4	64	0.000	2026-09-26 13:53:03.749452-05
1	65	4.000	2026-09-26 13:53:03.749532-05
2	65	0.000	2026-09-26 13:53:03.74956-05
3	65	0.000	2026-09-26 13:53:03.749586-05
4	65	0.000	2026-09-26 13:53:03.749612-05
1	66	4.000	2026-09-26 13:53:03.749663-05
2	66	0.000	2026-09-26 13:53:03.749689-05
3	66	0.000	2026-09-26 13:53:03.749713-05
4	66	0.000	2026-09-26 13:53:03.749739-05
1	67	4.000	2026-09-26 13:53:03.749789-05
2	67	0.000	2026-09-26 13:53:03.749814-05
3	67	0.000	2026-09-26 13:53:03.749839-05
4	67	0.000	2026-09-26 13:53:03.749869-05
1	68	4.000	2026-09-26 13:53:03.74992-05
2	68	0.000	2026-09-26 13:53:03.749946-05
3	68	0.000	2026-09-26 13:53:03.749971-05
4	68	0.000	2026-09-26 13:53:03.749996-05
1	69	4.000	2026-09-26 13:53:03.750046-05
2	69	0.000	2026-09-26 13:53:03.750073-05
3	69	0.000	2026-09-26 13:53:03.750098-05
4	69	0.000	2026-09-26 13:53:03.750123-05
1	70	4.000	2026-09-26 13:53:03.750174-05
2	70	0.000	2026-09-26 13:53:03.7502-05
3	70	0.000	2026-09-26 13:53:03.750231-05
4	70	0.000	2026-09-26 13:53:03.75026-05
1	71	4.000	2026-09-26 13:53:03.750318-05
2	71	0.000	2026-09-26 13:53:03.750345-05
3	71	0.000	2026-09-26 13:53:03.750371-05
4	71	0.000	2026-09-26 13:53:03.750397-05
1	72	14.000	2026-09-26 13:53:03.750452-05
2	72	0.000	2026-09-26 13:53:03.750483-05
3	72	0.000	2026-09-26 13:53:03.750509-05
4	72	0.000	2026-09-26 13:53:03.750534-05
1	73	4.000	2026-09-26 13:53:03.750588-05
2	73	0.000	2026-09-26 13:53:03.750615-05
3	73	0.000	2026-09-26 13:53:03.750641-05
4	73	0.000	2026-09-26 13:53:03.750668-05
1	74	4.000	2026-09-26 13:53:03.75072-05
2	74	0.000	2026-09-26 13:53:03.750745-05
3	74	0.000	2026-09-26 13:53:03.750771-05
4	74	0.000	2026-09-26 13:53:03.750796-05
1	75	8.000	2026-09-26 13:53:03.750847-05
2	75	0.000	2026-09-26 13:53:03.750873-05
3	75	0.000	2026-09-26 13:53:03.750899-05
4	75	0.000	2026-09-26 13:53:03.750924-05
1	76	8.000	2026-09-26 13:53:03.750975-05
2	76	0.000	2026-09-26 13:53:03.751-05
3	76	0.000	2026-09-26 13:53:03.751026-05
4	76	0.000	2026-09-26 13:53:03.751051-05
1	77	14.000	2026-09-26 13:53:03.751102-05
2	77	0.000	2026-09-26 13:53:03.751127-05
3	77	0.000	2026-09-26 13:53:03.751153-05
4	77	0.000	2026-09-26 13:53:03.751178-05
1	78	14.000	2026-09-26 13:53:03.751228-05
2	78	0.000	2026-09-26 13:53:03.751254-05
3	78	0.000	2026-09-26 13:53:03.751279-05
4	78	0.000	2026-09-26 13:53:03.751305-05
1	79	14.000	2026-09-26 13:53:03.751357-05
2	79	0.000	2026-09-26 13:53:03.7514-05
3	79	0.000	2026-09-26 13:53:03.751426-05
4	79	0.000	2026-09-26 13:53:03.751488-05
1	80	14.000	2026-09-26 13:53:03.751556-05
2	80	0.000	2026-09-26 13:53:03.751585-05
3	80	0.000	2026-09-26 13:53:03.751611-05
4	80	0.000	2026-09-26 13:53:03.751637-05
1	81	14.000	2026-09-26 13:53:03.75169-05
2	81	0.000	2026-09-26 13:53:03.751717-05
3	81	0.000	2026-09-26 13:53:03.751745-05
4	81	0.000	2026-09-26 13:53:03.75177-05
1	82	14.000	2026-09-26 13:53:03.751822-05
2	82	0.000	2026-09-26 13:53:03.751847-05
3	82	0.000	2026-09-26 13:53:03.751872-05
4	82	0.000	2026-09-26 13:53:03.751898-05
1	83	8.000	2026-09-26 13:53:03.751948-05
2	83	0.000	2026-09-26 13:53:03.751974-05
3	83	0.000	2026-09-26 13:53:03.751999-05
4	83	0.000	2026-09-26 13:53:03.752024-05
1	84	8.000	2026-09-26 13:53:03.752075-05
2	84	0.000	2026-09-26 13:53:03.7521-05
3	84	0.000	2026-09-26 13:53:03.752125-05
4	84	0.000	2026-09-26 13:53:03.752151-05
1	85	8.000	2026-09-26 13:53:03.752201-05
2	85	0.000	2026-09-26 13:53:03.752227-05
3	85	0.000	2026-09-26 13:53:03.752252-05
4	85	0.000	2026-09-26 13:53:03.752277-05
1	86	8.000	2026-09-26 13:53:03.752329-05
2	86	0.000	2026-09-26 13:53:03.752358-05
3	86	0.000	2026-09-26 13:53:03.752385-05
4	86	0.000	2026-09-26 13:53:03.75241-05
1	87	8.000	2026-09-26 13:53:03.752462-05
2	87	0.000	2026-09-26 13:53:03.752488-05
3	87	0.000	2026-09-26 13:53:03.752514-05
4	87	0.000	2026-09-26 13:53:03.752539-05
1	88	8.000	2026-09-26 13:53:03.75259-05
2	88	0.000	2026-09-26 13:53:03.752616-05
3	88	0.000	2026-09-26 13:53:03.752642-05
4	88	0.000	2026-09-26 13:53:03.752667-05
1	89	8.000	2026-09-26 13:53:03.752717-05
2	89	0.000	2026-09-26 13:53:03.752743-05
3	89	0.000	2026-09-26 13:53:03.752768-05
4	89	0.000	2026-09-26 13:53:03.752794-05
1	90	4.300	2026-09-26 13:53:03.752845-05
2	90	0.000	2026-09-26 13:53:03.752871-05
3	90	0.000	2026-09-26 13:53:03.752896-05
4	90	0.000	2026-09-26 13:53:03.752922-05
1	91	4.300	2026-09-26 13:53:03.752972-05
2	91	0.000	2026-09-26 13:53:03.752998-05
3	91	0.000	2026-09-26 13:53:03.753023-05
4	91	0.000	2026-09-26 13:53:03.753048-05
1	92	4.300	2026-09-26 13:53:03.753103-05
2	92	0.000	2026-09-26 13:53:03.753131-05
3	92	0.000	2026-09-26 13:53:03.753158-05
4	92	0.000	2026-09-26 13:53:03.753183-05
1	93	4.300	2026-09-26 13:53:03.753235-05
2	93	0.000	2026-09-26 13:53:03.753261-05
3	93	0.000	2026-09-26 13:53:03.753762-05
4	93	0.000	2026-09-26 13:53:03.753792-05
1	94	4.000	2026-09-26 13:53:03.753849-05
2	94	0.000	2026-09-26 13:53:03.753877-05
3	94	0.000	2026-09-26 13:53:03.753903-05
4	94	0.000	2026-09-26 13:53:03.753928-05
1	95	4.300	2026-09-26 13:53:03.753979-05
2	95	0.000	2026-09-26 13:53:03.754005-05
3	95	0.000	2026-09-26 13:53:03.75403-05
4	95	0.000	2026-09-26 13:53:03.754056-05
1	96	4.300	2026-09-26 13:53:03.754106-05
2	96	0.000	2026-09-26 13:53:03.754133-05
3	96	0.000	2026-09-26 13:53:03.754161-05
4	96	0.000	2026-09-26 13:53:03.754188-05
1	97	4.300	2026-09-26 13:53:03.754242-05
2	97	0.000	2026-09-26 13:53:03.754269-05
3	97	0.000	2026-09-26 13:53:03.754296-05
4	97	0.000	2026-09-26 13:53:03.754323-05
1	98	4.300	2026-09-26 13:53:03.754378-05
2	98	0.000	2026-09-26 13:53:03.754405-05
3	98	0.000	2026-09-26 13:53:03.754432-05
4	98	0.000	2026-09-26 13:53:03.75446-05
1	99	4.300	2026-09-26 13:53:03.754513-05
2	99	0.000	2026-09-26 13:53:03.75454-05
3	99	0.000	2026-09-26 13:53:03.754566-05
4	99	0.000	2026-09-26 13:53:03.754591-05
1	100	4.400	2026-09-26 13:53:03.754643-05
2	100	0.000	2026-09-26 13:53:03.754681-05
3	100	0.000	2026-09-26 13:53:03.754715-05
4	100	0.000	2026-09-26 13:53:03.754744-05
1	101	14.000	2026-09-26 13:53:03.754809-05
2	101	0.000	2026-09-26 13:53:03.754863-05
3	101	0.000	2026-09-26 13:53:03.754898-05
4	101	0.000	2026-09-26 13:53:03.75493-05
1	102	14.000	2026-09-26 13:53:03.754994-05
2	102	0.000	2026-09-26 13:53:03.755026-05
3	102	0.000	2026-09-26 13:53:03.755055-05
4	102	0.000	2026-09-26 13:53:03.755115-05
1	103	14.000	2026-09-26 13:53:03.755573-05
2	103	0.000	2026-09-26 13:53:03.755613-05
3	103	0.000	2026-09-26 13:53:03.755644-05
4	103	0.000	2026-09-26 13:53:03.755695-05
1	104	14.000	2026-09-26 13:53:03.755794-05
2	104	0.000	2026-09-26 13:53:03.755833-05
3	104	0.000	2026-09-26 13:53:03.75587-05
4	104	0.000	2026-09-26 13:53:03.7559-05
1	105	14.000	2026-09-26 13:53:03.755966-05
2	105	0.000	2026-09-26 13:53:03.755998-05
3	105	0.000	2026-09-26 13:53:03.756029-05
4	105	0.000	2026-09-26 13:53:03.756058-05
1	106	14.000	2026-09-26 13:53:03.756127-05
2	106	0.000	2026-09-26 13:53:03.756182-05
3	106	0.000	2026-09-26 13:53:03.756212-05
4	106	0.000	2026-09-26 13:53:03.756241-05
1	107	14.000	2026-09-26 13:53:03.7563-05
2	107	0.000	2026-09-26 13:53:03.75633-05
3	107	0.000	2026-09-26 13:53:03.756359-05
4	107	0.000	2026-09-26 13:53:03.756387-05
1	108	14.000	2026-09-26 13:53:03.756446-05
2	108	0.000	2026-09-26 13:53:03.756481-05
3	108	0.000	2026-09-26 13:53:03.756511-05
4	108	0.000	2026-09-26 13:53:03.756538-05
1	109	14.000	2026-09-26 13:53:03.756597-05
2	109	0.000	2026-09-26 13:53:03.756626-05
3	109	0.000	2026-09-26 13:53:03.756654-05
4	109	0.000	2026-09-26 13:53:03.756693-05
1	110	14.000	2026-09-26 13:53:03.756751-05
2	110	0.000	2026-09-26 13:53:03.75678-05
3	110	0.000	2026-09-26 13:53:03.756809-05
4	110	0.000	2026-09-26 13:53:03.756838-05
1	111	14.000	2026-09-26 13:53:03.756902-05
2	111	0.000	2026-09-26 13:53:03.756935-05
3	111	0.000	2026-09-26 13:53:03.756966-05
4	111	0.000	2026-09-26 13:53:03.756997-05
1	112	14.000	2026-09-26 13:53:03.757054-05
2	112	0.000	2026-09-26 13:53:03.757083-05
3	112	0.000	2026-09-26 13:53:03.757112-05
4	112	0.000	2026-09-26 13:53:03.75714-05
1	113	14.000	2026-09-26 13:53:03.757194-05
2	113	0.000	2026-09-26 13:53:03.757228-05
3	113	0.000	2026-09-26 13:53:03.757258-05
4	113	0.000	2026-09-26 13:53:03.757286-05
1	114	14.000	2026-09-26 13:53:03.757343-05
2	114	0.000	2026-09-26 13:53:03.75737-05
3	114	0.000	2026-09-26 13:53:03.757398-05
4	114	0.000	2026-09-26 13:53:03.757425-05
1	115	14.000	2026-09-26 13:53:03.757479-05
2	115	0.000	2026-09-26 13:53:03.757517-05
3	115	0.000	2026-09-26 13:53:03.757544-05
4	115	0.000	2026-09-26 13:53:03.757571-05
1	116	14.000	2026-09-26 13:53:03.75763-05
2	116	0.000	2026-09-26 13:53:03.757661-05
3	116	0.000	2026-09-26 13:53:03.75787-05
4	116	0.000	2026-09-26 13:53:03.757903-05
1	117	14.000	2026-09-26 13:53:03.757964-05
2	117	0.000	2026-09-26 13:53:03.757995-05
3	117	0.000	2026-09-26 13:53:03.758024-05
4	117	0.000	2026-09-26 13:53:03.758051-05
1	118	14.000	2026-09-26 13:53:03.758106-05
2	118	0.000	2026-09-26 13:53:03.758134-05
3	118	0.000	2026-09-26 13:53:03.758162-05
4	118	0.000	2026-09-26 13:53:03.758189-05
1	119	14.000	2026-09-26 13:53:03.758306-05
2	119	0.000	2026-09-26 13:53:03.758335-05
3	119	0.000	2026-09-26 13:53:03.758362-05
4	119	0.000	2026-09-26 13:53:03.758389-05
1	120	14.000	2026-09-26 13:53:03.758443-05
2	120	0.000	2026-09-26 13:53:03.758471-05
3	120	0.000	2026-09-26 13:53:03.758497-05
4	120	0.000	2026-09-26 13:53:03.758524-05
1	121	14.000	2026-09-26 13:53:03.758577-05
2	121	0.000	2026-09-26 13:53:03.758605-05
3	121	0.000	2026-09-26 13:53:03.758631-05
4	121	0.000	2026-09-26 13:53:03.758658-05
1	122	14.000	2026-09-26 13:53:03.758725-05
2	122	0.000	2026-09-26 13:53:03.758756-05
3	122	0.000	2026-09-26 13:53:03.758788-05
4	122	0.000	2026-09-26 13:53:03.758817-05
1	123	14.000	2026-09-26 13:53:03.758872-05
2	123	0.000	2026-09-26 13:53:03.7589-05
3	123	0.000	2026-09-26 13:53:03.758926-05
4	123	0.000	2026-09-26 13:53:03.758953-05
1	124	14.000	2026-09-26 13:53:03.759005-05
2	124	0.000	2026-09-26 13:53:03.759033-05
3	124	0.000	2026-09-26 13:53:03.759059-05
4	124	0.000	2026-09-26 13:53:03.759086-05
1	125	14.000	2026-09-26 13:53:03.759138-05
2	125	0.000	2026-09-26 13:53:03.759165-05
3	125	0.000	2026-09-26 13:53:03.759191-05
4	125	0.000	2026-09-26 13:53:03.759218-05
1	126	14.000	2026-09-26 13:53:03.759269-05
2	126	0.000	2026-09-26 13:53:03.759296-05
3	126	0.000	2026-09-26 13:53:03.759322-05
4	126	0.000	2026-09-26 13:53:03.759349-05
1	127	14.000	2026-09-26 13:53:03.759401-05
2	127	0.000	2026-09-26 13:53:03.759427-05
3	127	0.000	2026-09-26 13:53:03.759453-05
4	127	0.000	2026-09-26 13:53:03.759485-05
1	128	14.000	2026-09-26 13:53:03.759539-05
2	128	0.000	2026-09-26 13:53:03.759568-05
3	128	0.000	2026-09-26 13:53:03.759596-05
4	128	0.000	2026-09-26 13:53:03.759622-05
1	129	14.000	2026-09-26 13:53:03.759676-05
2	129	0.000	2026-09-26 13:53:03.759703-05
3	129	0.000	2026-09-26 13:53:03.759751-05
4	129	0.000	2026-09-26 13:53:03.759779-05
1	130	14.000	2026-09-26 13:53:03.759832-05
2	130	0.000	2026-09-26 13:53:03.75986-05
3	130	0.000	2026-09-26 13:53:03.759887-05
4	130	0.000	2026-09-26 13:53:03.759914-05
1	131	14.000	2026-09-26 13:53:03.759967-05
2	131	0.000	2026-09-26 13:53:03.759994-05
3	131	0.000	2026-09-26 13:53:03.760021-05
4	131	0.000	2026-09-26 13:53:03.760047-05
1	132	14.000	2026-09-26 13:53:03.760099-05
2	132	0.000	2026-09-26 13:53:03.760127-05
3	132	0.000	2026-09-26 13:53:03.760154-05
4	132	0.000	2026-09-26 13:53:03.760181-05
1	133	14.000	2026-09-26 13:53:03.760233-05
2	133	0.000	2026-09-26 13:53:03.760261-05
3	133	0.000	2026-09-26 13:53:03.760287-05
4	133	0.000	2026-09-26 13:53:03.760314-05
1	134	14.000	2026-09-26 13:53:03.760366-05
2	134	0.000	2026-09-26 13:53:03.760393-05
3	134	0.000	2026-09-26 13:53:03.76042-05
4	134	0.000	2026-09-26 13:53:03.760446-05
1	135	8.000	2026-09-26 13:53:03.760497-05
2	135	0.000	2026-09-26 13:53:03.760524-05
3	135	0.000	2026-09-26 13:53:03.76055-05
4	135	0.000	2026-09-26 13:53:03.760576-05
1	136	8.000	2026-09-26 13:53:03.760628-05
2	136	0.000	2026-09-26 13:53:03.760655-05
3	136	0.000	2026-09-26 13:53:03.760693-05
4	136	0.000	2026-09-26 13:53:03.760721-05
1	137	8.000	2026-09-26 13:53:03.760802-05
2	137	0.000	2026-09-26 13:53:03.760833-05
3	137	0.000	2026-09-26 13:53:03.76086-05
4	137	0.000	2026-09-26 13:53:03.760886-05
1	138	8.000	2026-09-26 13:53:03.76094-05
2	138	0.000	2026-09-26 13:53:03.760967-05
3	138	0.000	2026-09-26 13:53:03.760995-05
4	138	0.000	2026-09-26 13:53:03.761022-05
1	139	8.000	2026-09-26 13:53:03.761075-05
2	139	0.000	2026-09-26 13:53:03.761102-05
3	139	0.000	2026-09-26 13:53:03.761128-05
4	139	0.000	2026-09-26 13:53:03.761154-05
1	140	8.000	2026-09-26 13:53:03.76121-05
2	140	0.000	2026-09-26 13:53:03.761239-05
3	140	0.000	2026-09-26 13:53:03.761265-05
4	140	0.000	2026-09-26 13:53:03.76129-05
\.


--
-- Data for Name: item_carta; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.item_carta (id_item_carta, codigo, nombre, id_categoria_carta, tipo, activo) FROM stdin;
1	CT-001	Lanza Llamas	1	PREPARADO	t
2	CT-002	Coche Bomba	1	PREPARADO	t
3	CT-003	Shot de Ron	1	PORCIONADO	t
4	CT-004	Shot de Tequila	1	PORCIONADO	t
5	CT-005	Shot de Jager	1	PORCIONADO	t
6	CT-006	Shot de Pisco	1	PORCIONADO	t
7	CT-007	Shot de Vodka	1	PORCIONADO	t
8	CT-008	Chilcano de Maracuyá	1	PREPARADO	t
9	CT-009	Maracuyá Sour	1	PREPARADO	t
10	CT-010	Mojito de Maracuyá	1	PREPARADO	t
11	CT-011	Barbarian de Verano	1	PREPARADO	t
12	CT-012	Aperol Spritz	1	PREPARADO	t
13	CT-013	Cuba Libre	1	PREPARADO	t
14	CT-014	Negroni	1	PREPARADO	t
15	CT-015	Jagerbomb	1	PREPARADO	t
16	CT-016	Chilcano	1	PREPARADO	t
17	CT-017	Moscow Mule	1	PREPARADO	t
18	CT-018	Gin Tonic Barbarian	1	PREPARADO	t
19	CT-019	Paloma	1	PREPARADO	t
20	CT-020	Whisky en las Rocas	1	PORCIONADO	t
21	CT-021	Vodka Tonic	1	PREPARADO	t
22	CT-022	Paloma Rancher	1	PREPARADO	t
23	CT-023	Vodka con Redbull	1	PREPARADO	t
24	CT-024	Mojito	1	PREPARADO	t
25	CT-025	Blue Chilcano	1	PREPARADO	t
26	CT-026	Catedral	1	PREPARADO	t
27	CT-027	Pisco Sour	1	PREPARADO	t
28	CT-028	Ronsoco	1	PREPARADO	t
29	CT-029	Chilcanorte	1	PREPARADO	t
30	CT-030	Palomón	1	PREPARADO	t
31	CT-031	Mostro Mule	1	PREPARADO	t
32	CT-032	Blue Chilcanorte	1	PREPARADO	t
33	CT-033	Palomón Rancher	1	PREPARADO	t
34	BL-001	Botella de 174 IPA	2	DIRECTO	t
35	BL-002	Botella de La Nena Trigo	2	DIRECTO	t
36	BL-003	Botella de L.I.M.A. Pale Ale	2	DIRECTO	t
37	BL-004	Botella de Magic Quinua	2	DIRECTO	t
38	BL-005	Botella de Red	2	DIRECTO	t
39	BI-001	Estrella Damm - Sin alcohol	3	DIRECTO	t
40	BI-002	Daura Damm - Sin Gluten	3	DIRECTO	t
41	BI-003	Lindermans Kriek	3	DIRECTO	t
42	BI-004	San Bernardus ABT 12	3	DIRECTO	t
43	BI-005	Westmalle Tripel	3	DIRECTO	t
44	BI-006	Chimay Roja	3	DIRECTO	t
45	BI-007	Petrus Choco Cherry	3	DIRECTO	t
46	BI-008	Delirium Tremens	3	DIRECTO	t
47	SA-001	Vaso de Chicha	4	PREPARADO	t
48	SA-002	Coca Cola	4	DIRECTO	t
49	SA-003	Inca Kola	4	DIRECTO	t
50	SA-004	Coca Cola sin Azucar	4	DIRECTO	t
51	SA-005	Inca Kola sin Azucar	4	DIRECTO	t
52	SA-006	Agua sin gas	4	DIRECTO	t
53	SA-007	Agua con Gas	4	DIRECTO	t
54	SA-008	Red bull	4	DIRECTO	t
55	SA-009	Red bull Tropical Edition	4	DIRECTO	t
56	SA-010	Red bull Sugar Free	4	DIRECTO	t
57	SA-011	Red bull Red Edition	4	DIRECTO	t
58	SA-012	Red Bull Green Edition	4	DIRECTO	t
59	SA-013	Mr. Perkins Pink Soda	4	DIRECTO	t
60	SA-014	Mr. Perkins Ginger Beer	4	DIRECTO	t
61	ET-001	Papas Bárbaras	5	PREPARADO	t
62	ET-002	Cheese Fries	5	PREPARADO	t
63	ET-003	Salchipapón Bárbaro	5	PREPARADO	t
64	ET-004	Chorri Papas	5	PREPARADO	t
65	ET-005	Tequeños Ruleta Rusa	5	PREPARADO	t
66	ET-006	Tequeños con Queso	5	PREPARADO	t
67	ET-007	Tequeños Pulled Pork	5	PREPARADO	t
68	ET-008	Nachos Pulled Pork	5	PREPARADO	t
69	ET-009	Nachos de Queso	5	PREPARADO	t
70	ET-010	Quesadillas	5	PREPARADO	t
71	ET-011	Tacos	5	PREPARADO	t
72	ET-012	Tacos de Pollo	5	PREPARADO	t
73	ET-013	Burger Bites	5	PREPARADO	t
74	ET-014	Chicken Fingers	5	PREPARADO	t
75	ET-015	Parrillón Bárbaro	5	PREPARADO	t
76	ET-016	Piqueo Marrano	5	PREPARADO	t
77	ET-017	Piqueo Achorado	5	PREPARADO	t
78	ET-018	Piqueo Bárbaro	5	PREPARADO	t
79	ET-019	Alitas Broster	5	PREPARADO	t
80	ET-020	Alitas	5	PREPARADO	t
81	ET-021	Boneless	5	PREPARADO	t
82	PL-001	Ensalada Cobb	6	PREPARADO	t
83	PL-002	Hamburguesa Bárbara	6	PREPARADO	t
84	PL-003	Hamburguesa Mia	6	PREPARADO	t
85	PL-004	Hamburguesa Jenna	6	PREPARADO	t
86	PL-005	Hamburguesa Sasha	6	PREPARADO	t
87	PL-006	Hamburguesa Tori	6	PREPARADO	t
88	PL-007	Hamburguesa Jeremy	6	PREPARADO	t
89	PL-008	Hamburguesa Rocco	6	PREPARADO	t
90	PL-009	Pollo Bárbaro	6	PREPARADO	t
91	PL-010	Chiken Pasta Bárbaro	6	PREPARADO	t
92	PL-011	Barbarina Buffalo Pasta	6	PREPARADO	t
93	PL-012	Pollo al Champiñón	6	PREPARADO	t
94	PL-013	Pollo Parrillero	6	PREPARADO	t
95	PL-014	Cordon Blue	6	PREPARADO	t
96	PL-015	Pollo Saltado	6	PREPARADO	t
97	PL-016	Barbarian Steak	6	PREPARADO	t
98	PL-017	Lomo Saltado	6	PREPARADO	t
99	PL-018	Lomo 4 Pimientas	6	PREPARADO	t
100	CB-001	Magic Quinua	7	PORCIONADO	t
101	CB-002	Dámela Siempre	7	PORCIONADO	t
102	CB-003	La Nena	7	PORCIONADO	t
103	CB-004	Barbarian Red Ale	7	PORCIONADO	t
104	CB-005	L.I.M.A	7	PORCIONADO	t
105	CB-006	Chaski	7	PORCIONADO	t
106	CB-007	174 IPA	7	PORCIONADO	t
107	CB-008	Final Feliz	7	PORCIONADO	t
108	CB-009	2 Más	7	PORCIONADO	t
109	CB-010	Belga Pa’ Ti	7	PORCIONADO	t
110	CB-011	K-7	7	PORCIONADO	t
111	CB-012	Mañanero	7	PORCIONADO	t
112	CB-013	Lou	7	PORCIONADO	t
113	CB-014	Peaky Biter	7	PORCIONADO	t
114	CB-015	Chicha Tu Mare	7	PORCIONADO	t
115	CB-016	Barbarov	7	PORCIONADO	t
116	CB-017	Tropical Nordic	7	PORCIONADO	t
117	CB-018	St Patrick’s	7	PORCIONADO	t
118	CB-019	Oktu-Brefest	7	PORCIONADO	t
119	CB-020	Blueberry Gose	7	PORCIONADO	t
120	CB-021	Camu Camu Maracuyá	7	PORCIONADO	t
121	CB-022	La Última Chupada del Mango	7	PORCIONADO	t
122	CB-023	De la Selva Su Gose	7	PORCIONADO	t
123	CB-024	Krieger	7	PORCIONADO	t
124	CB-025	Dark Krieger	7	PORCIONADO	t
125	CB-026	De Peso Pumpkin Ale	7	PORCIONADO	t
126	CB-027	Chelón de Doña Pepa	7	PORCIONADO	t
127	CB-028	Crazy Llama	7	PORCIONADO	t
128	CB-029	Apagón	7	PORCIONADO	t
129	CB-030	VALKIRIA	7	PORCIONADO	t
130	CB-031	GRANADILLA	7	PORCIONADO	t
131	CB-032	INTERESTELAGER	7	PORCIONADO	t
132	CB-033	POLVO ESTELAR	7	PORCIONADO	t
133	CB-034	TINTO DE VERANO	7	PORCIONADO	t
\.


--
-- Data for Name: local; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.local (id_local, codigo, nombre, direccion, estado_registro, fecha_creacion, usuario_creacion, fecha_modificacion, usuario_modificacion) FROM stdin;
1	MIRAFLORES	Miraflores	\N	1	2026-09-22 11:03:25.78008	\N	\N	\N
2	SANTA_ANITA	Santa Anita	\N	1	2026-09-22 11:03:25.78008	\N	\N	\N
3	BARRANCO	Barranco	\N	1	2026-09-22 11:03:25.78008	\N	\N	\N
4	SHERATON	Sheraton	\N	1	2026-09-22 11:03:25.78008	\N	\N	\N
\.


--
-- Data for Name: menaje; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.menaje (id_menaje, nombre, activo) FROM stdin;
1	Bandeja	t
2	Botella	t
3	Chop	t
4	Copa	t
5	Copa alta	t
6	Lata	t
7	Plato hondo	t
8	Plato pequeño	t
9	Plato tendido	t
10	Shot	t
11	Soporte para tacos	t
12	Tabla grande	t
13	Tabla mediana	t
14	Vaso	t
15	Vaso de cobre	t
16	Vaso rockero	t
17	Vaso y shot	t
\.


--
-- Data for Name: movimiento_inventario; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.movimiento_inventario (id_movimiento_inventario, codigo, tipo_movimiento, motivo_movimiento, fecha_movimiento, usuario_registro, local_relacionado, id_proveedor, observacion, id_local, registrado_en) FROM stdin;
1	MI-001	ENTRADA	PRESTAMO_RECIBIDO	2026-09-10	3	Tienda Miraflores	\N	Préstamo recibido	1	\N
2	MI-002	SALIDA	MERMA	2026-09-10	3	\N	\N	Productos dañados	1	\N
3	MI-003	SALIDA	PRESTAMO_ENTREGADO	2026-09-11	2	Tienda Barranco	\N	Préstamo entregado	1	\N
4	MI-004	SALIDA	DEVOLUCION_PROVEEDOR	2026-09-12	3	\N	1	Productos antiguos devueltos al proveedor	1	\N
5	MI-005	SALIDA	VENTA_SALON	2026-09-26	1	\N	\N	Cobro de Salón, mesa M01	1	2026-09-26 05:19:00.303733
6	DEMO-0928-1-1	SALIDA	VENTA_SALON	2026-09-29	1	\N	\N	DEMO-MIRAFLORES-20260928 · venta simulada	1	2026-09-28 20:51:28.777293
7	DEMO-0928-1-2	SALIDA	VENTA_SALON	2026-09-29	1	\N	\N	DEMO-MIRAFLORES-20260928 · venta simulada	1	2026-09-28 20:51:28.815052
8	DEMO-0928-2-1	SALIDA	VENTA_SALON	2026-09-30	1	\N	\N	DEMO-MIRAFLORES-20260928 · venta simulada	1	2026-09-28 20:51:28.851403
9	DEMO-0928-2-2	SALIDA	VENTA_SALON	2026-09-30	1	\N	\N	DEMO-MIRAFLORES-20260928 · venta simulada	1	2026-09-28 20:51:28.859834
10	DEMO-0928-3-1	SALIDA	VENTA_SALON	2026-10-01	1	\N	\N	DEMO-MIRAFLORES-20260928 · venta simulada	1	2026-09-28 20:51:28.883651
11	DEMO-0928-3-2	SALIDA	VENTA_SALON	2026-10-01	1	\N	\N	DEMO-MIRAFLORES-20260928 · venta simulada	1	2026-09-28 20:51:28.889867
12	DEMO-0928-4-1	SALIDA	VENTA_SALON	2026-10-02	1	\N	\N	DEMO-MIRAFLORES-20260928 · venta simulada	1	2026-09-28 20:51:28.914476
13	DEMO-0928-4-2	SALIDA	VENTA_SALON	2026-10-02	1	\N	\N	DEMO-MIRAFLORES-20260928 · venta simulada	1	2026-09-28 20:51:28.925015
14	DEMO-0928-5-1	SALIDA	VENTA_SALON	2026-10-03	1	\N	\N	DEMO-MIRAFLORES-20260928 · venta simulada	1	2026-09-28 20:51:28.950789
15	DEMO-0928-5-2	SALIDA	VENTA_SALON	2026-10-03	1	\N	\N	DEMO-MIRAFLORES-20260928 · venta simulada	1	2026-09-28 20:51:28.956599
16	MI-006	SALIDA	VENTA_SALON	2026-10-03	1	\N	\N	Cobro de Salón, mesa M01	1	2026-10-03 19:25:24.328186
\.


--
-- Data for Name: movimiento_inventario_detalle; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.movimiento_inventario_detalle (id_movimiento_inventario_detalle, id_movimiento_inventario, id_producto, cantidad) FROM stdin;
1	1	72	12.000
2	1	3	5.000
3	2	1	0.500
4	2	5	1.200
5	3	72	6.000
6	4	5	2.000
7	5	29	1.000
8	5	33	1.000
9	5	34	4.000
10	5	36	1.000
11	6	107	1.600
12	6	82	1.000
13	6	135	1.000
14	6	36	1.000
15	7	109	0.400
16	8	107	1.800
17	8	82	2.000
18	8	135	1.000
19	8	36	1.000
20	9	109	0.400
21	9	81	1.000
22	9	137	1.000
23	10	107	2.000
24	10	82	1.000
25	10	135	1.000
26	10	36	1.000
27	11	109	0.600
28	12	107	2.200
29	12	82	1.000
30	12	135	1.000
31	12	36	1.000
32	13	109	0.400
33	13	81	1.000
34	13	137	1.000
35	14	107	2.400
36	14	82	1.000
37	14	135	1.000
38	14	36	1.000
39	15	109	0.200
40	16	29	1.000
41	16	31	1.000
42	16	34	1.000
43	16	36	2.000
44	16	107	0.200
45	16	138	1.000
46	16	139	1.000
\.


--
-- Data for Name: movimiento_reintegro; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.movimiento_reintegro (id_movimiento, id_salida, guia_proveedor, registrado_en) FROM stdin;
\.


--
-- Data for Name: movimiento_seguimiento; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.movimiento_seguimiento (id_movimiento, id_local_destino, estado) FROM stdin;
\.


--
-- Data for Name: opcion_menu; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.opcion_menu (id_opcion_menu, nombre, url_menu, descripcion, id_padre, estado_registro, codigo, icono, tipo_opcion, es_configurable, usuario_creacion, fecha_creacion, usuario_modificacion, fecha_modificacion) FROM stdin;
1	Inicio	/home	Muestra el panel principal correspondiente al perfil	\N	1	MENU_1	\N	ENLACE	f	\N	2026-09-10 18:15:46.276662	\N	\N
2	Usuarios	/home/usuarios	Permite consultar y administrar usuarios y perfiles	\N	1	MENU_2	\N	ENLACE	f	\N	2026-09-10 18:15:46.276662	\N	\N
33	Mínimos y máximos	/home/limites-stock	Configura los stocks mínimos y máximos de los productos del local activo.	16	1	LIMITES_STOCK	\N	ENLACE	f	\N	2026-09-22 14:13:11.937442	\N	\N
3	Catálogos	/home/catalogos	Agrupa los datos maestros del inventario	\N	1	MENU_3	\N	GRUPO	t	\N	2026-09-10 18:15:46.276662	\N	\N
4	Productos	/home/productos	Permite consultar y administrar productos	3	1	MENU_4	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
5	Categorías de productos	/home/categorias-productos	Permite consultar y administrar categorías de productos	3	1	MENU_5	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
6	Proveedores	/home/proveedores	Permite consultar y administrar proveedores	3	1	MENU_6	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
7	Carta	/home/carta	Agrupa la configuración de los productos ofrecidos	\N	1	MENU_7	\N	GRUPO	t	\N	2026-09-10 18:15:46.276662	\N	\N
8	Categorías de carta	/home/carta/categorias	Permite consultar y administrar categorías de carta	7	1	MENU_8	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
9	Presentaciones de venta	/home/carta/presentaciones	Permite consultar y administrar presentaciones, porciones y precios	7	1	MENU_9	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
10	Menajes	/home/carta/menajes	Permite consultar y administrar los menajes	7	1	MENU_10	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
12	Subproductos	/home/subproductos	Permite consultar y administrar preparaciones internas	11	1	MENU_12	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
17	Realizar inventario	/home/inventarios/realizar	Permite iniciar, guardar y cerrar un inventario	16	0	MENU_17	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
18	Revisar inventarios	/home/inventarios/revisar	Permite revisar inventarios cerrados y registrar observaciones	16	0	MENU_18	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
16	Inventario	\N	Permite consultar los inventarios registrados por fecha	\N	1	MENU_16	\N	GRUPO	t	\N	2026-09-10 18:15:46.276662	\N	\N
15	Stock actual	/home/stock	Permite consultar las existencias actuales calculadas	16	1	MENU_15	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
36	Cerrar día	/home/inventarios/dia	Día operativo y reportes	16	1	INVENTARIO_JORNADA	\N	ENLACE	f	\N	2026-09-26 13:53:03.598304	\N	\N
37	Mix de ventas	/home/inventarios/mix	Ventas por fechas y horas	16	1	VENTAS_MIX	\N	ENLACE	f	\N	2026-09-26 13:53:03.598304	\N	\N
38	Real vs. teórico	/home/inventarios/conteos	Conteos asignados y diferencias	16	1	CONTEO_FISICO	\N	ENLACE	f	\N	2026-09-26 13:53:03.598304	\N	\N
13	Grupos de salsa	/home/grupos-salsa	Permite consultar y configurar opciones de salsa	11	1	MENU_13	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
14	Promociones	/home/promociones	Permite consultar y administrar promociones	\N	1	MENU_14	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
19	Movimientos de inventario	/home/movimientos	Permite consultar entradas y salidas extraordinarias	\N	1	MENU_19	\N	GRUPO	t	\N	2026-09-10 18:15:46.276662	\N	\N
20	Registrar movimiento	/home/movimientos/registrar	Permite registrar préstamos, mermas y devoluciones	19	1	MENU_20	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
21	Órdenes de compra	/home/ordenes-compra	Permite consultar y preparar órdenes de compra	\N	1	MENU_21	\N	GRUPO	t	\N	2026-09-10 18:15:46.276662	\N	\N
23	Recepción de productos	/home/recepciones	Permite registrar facturas y productos recibidos	\N	1	MENU_23	\N	GRUPO	t	\N	2026-09-10 18:15:46.276662	\N	\N
25	Reportes	/home/reportes	Permite generar reportes con diferentes filtros	\N	1	MENU_25	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
26	Actividades del sistema	/home/actividades	Permite auditar acciones realizadas por los usuarios	\N	1	MENU_26	\N	ENLACE	f	\N	2026-09-10 18:15:46.276662	\N	\N
22	Crear orden de compra	/home/ordenes-compra/crear	Permite crear órdenes de compra manualmente o cargar un pedido sugerido.	21	1	MENU_22	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
24	Pendientes de recepción	/home/recepciones/pendientes	Muestra los productos solicitados pendientes de recepción	23	1	MENU_24	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
11	Recetas y producción	/home/recetas-produccion	Administración de recetas, subproductos y grupos de salsa	\N	1	MENU_11	\N	GRUPO	t	\N	2026-09-10 18:15:46.276662	\N	\N
28	Recetas	/home/recetas	Consulta y administración de recetas	11	1	MENU_28	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
31	Historial de órdenes	/home/ordenes-compra/historial	Consulta las órdenes de compra y sus estados	21	1	MENU_31	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
32	Historial de recepciones	/home/recepciones/historial	Consulta las facturas y recepciones registradas	23	1	MENU_32	\N	ENLACE	t	\N	2026-09-10 18:15:46.276662	\N	\N
\.


--
-- Data for Name: orden_compra; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.orden_compra (id_orden_compra, codigo, estado_orden_compra, usuario_registro, fecha_registro, motivo_cierre, usuario_modificacion, fecha_modificacion, id_local) FROM stdin;
1	OC-001	RECEPCIONADA	2	2026-08-29	\N	\N	\N	1
2	OC-002	ENVIADA	1	2026-10-03	\N	\N	\N	1
\.


--
-- Data for Name: orden_compra_detalle; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.orden_compra_detalle (id_orden_compra_detalle, id_orden_compra, id_producto, cantidad_solicitada, id_proveedor) FROM stdin;
141	2	135	6.000	9
142	2	36	6.000	2
1	1	1	20.000	1
2	1	2	20.000	1
3	1	3	20.000	1
4	1	4	20.000	1
5	1	5	20.000	1
6	1	6	20.000	1
7	1	7	20.000	1
8	1	8	20.000	1
9	1	9	20.000	1
10	1	10	20.000	1
11	1	11	20.000	2
12	1	12	20.000	2
13	1	13	20.000	2
14	1	14	24.000	2
15	1	15	20.000	2
16	1	16	20.000	2
17	1	17	20.000	2
18	1	18	24.000	2
19	1	19	20.000	2
20	1	20	20.000	2
21	1	21	20.000	2
22	1	22	24.000	2
23	1	23	20.000	2
24	1	24	20.000	2
25	1	25	20.000	2
26	1	26	20.000	2
27	1	27	20.000	2
28	1	28	20.000	2
29	1	29	24.000	2
30	1	30	24.000	2
31	1	31	24.000	2
32	1	32	24.000	2
33	1	33	24.000	2
34	1	34	24.000	2
35	1	35	24.000	2
36	1	36	24.000	2
37	1	37	20.000	3
38	1	38	20.000	3
39	1	39	20.000	3
40	1	40	20.000	3
41	1	41	20.000	3
42	1	42	20.000	3
43	1	43	20.000	3
44	1	44	20.000	3
45	1	45	20.000	3
46	1	46	20.000	3
47	1	47	20.000	3
48	1	48	20.000	3
49	1	49	20.000	3
50	1	50	20.000	3
51	1	51	20.000	4
52	1	52	20.000	4
53	1	53	20.000	4
54	1	54	20.000	4
55	1	55	20.000	4
56	1	56	20.000	4
57	1	57	20.000	4
58	1	58	24.000	5
59	1	59	24.000	5
60	1	60	24.000	5
61	1	61	24.000	5
62	1	62	20.000	5
63	1	63	20.000	5
64	1	64	20.000	6
65	1	65	20.000	6
66	1	66	20.000	6
67	1	67	20.000	6
68	1	68	20.000	6
69	1	69	20.000	6
70	1	70	20.000	6
71	1	71	20.000	6
72	1	72	24.000	6
73	1	73	20.000	6
74	1	74	20.000	6
75	1	75	24.000	7
76	1	76	24.000	7
77	1	77	30.000	7
78	1	78	30.000	7
79	1	79	30.000	7
80	1	80	30.000	7
81	1	81	30.000	7
82	1	82	30.000	7
83	1	83	24.000	7
84	1	84	24.000	7
85	1	85	24.000	7
86	1	86	24.000	7
87	1	87	24.000	7
88	1	88	24.000	7
89	1	89	24.000	7
90	1	90	20.300	8
91	1	91	20.300	8
92	1	92	20.300	8
93	1	93	20.300	8
94	1	94	20.000	8
95	1	95	20.300	8
96	1	96	20.300	8
97	1	97	20.300	8
98	1	98	20.300	8
99	1	99	20.300	8
100	1	100	20.400	8
101	1	101	30.000	9
102	1	102	30.000	9
103	1	103	30.000	9
104	1	104	30.000	9
105	1	105	30.000	9
106	1	106	30.000	9
107	1	107	30.000	9
108	1	108	30.000	9
109	1	109	30.000	9
110	1	110	30.000	9
111	1	111	30.000	9
112	1	112	30.000	9
113	1	113	30.000	9
114	1	114	30.000	9
115	1	115	30.000	9
116	1	116	30.000	9
117	1	117	30.000	9
118	1	118	30.000	9
119	1	119	30.000	9
120	1	120	30.000	9
121	1	121	30.000	9
122	1	122	30.000	9
123	1	123	30.000	9
124	1	124	30.000	9
125	1	125	30.000	9
126	1	126	30.000	9
127	1	127	30.000	9
128	1	128	30.000	9
129	1	129	30.000	9
130	1	130	30.000	9
131	1	131	30.000	9
132	1	132	30.000	9
133	1	133	30.000	9
134	1	134	30.000	9
135	1	135	24.000	9
136	1	136	24.000	9
137	1	137	24.000	9
138	1	138	24.000	9
139	1	139	24.000	9
140	1	140	24.000	2
\.


--
-- Data for Name: orden_compra_estado_historial; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.orden_compra_estado_historial (id_orden_compra_estado_historial, id_orden_compra, estado_anterior, estado_nuevo, motivo, usuario_modificacion, fecha_modificacion) FROM stdin;
\.


--
-- Data for Name: perfil_gestion_usuario; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.perfil_gestion_usuario (id_perfil_gestor, id_perfil_objetivo, puede_crear, puede_editar, estado_registro) FROM stdin;
1	1	t	t	1
1	2	t	t	1
1	3	t	t	1
1	4	t	t	1
2	3	t	t	1
2	4	t	t	1
\.


--
-- Data for Name: perfil_opcion_menu; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.perfil_opcion_menu (id_perfil, id_opcion_menu, puede_consultar, puede_crear, puede_editar, puede_revisar, puede_cerrar, orden, estado_registro, puede_desactivar, puede_reactivar, puede_eliminar, puede_configurar) FROM stdin;
2	1	t	f	f	f	f	1	1	f	f	f	f
2	3	t	f	f	f	f	3	1	f	f	f	f
2	4	t	f	f	f	f	1	1	f	f	f	f
2	6	t	f	f	f	f	3	1	f	f	f	f
2	7	t	f	f	f	f	4	1	f	f	f	f
2	9	t	f	f	f	f	2	1	f	f	f	f
2	10	t	f	f	f	f	3	1	f	f	f	f
2	12	t	f	f	f	f	1	1	f	f	f	f
2	14	t	f	f	f	f	6	1	f	f	f	f
2	15	t	f	f	f	f	7	1	f	f	f	f
2	16	t	f	f	f	f	8	1	f	f	f	f
2	17	t	t	t	f	t	1	1	f	f	f	f
2	18	t	f	t	t	f	2	1	f	f	f	f
2	19	t	f	f	f	f	9	1	f	f	f	f
2	20	t	t	f	f	f	1	1	f	f	f	f
2	21	t	t	t	f	t	10	1	f	f	f	f
2	22	t	t	t	f	f	1	1	f	f	f	f
2	23	t	t	f	f	f	11	1	f	f	f	f
2	25	t	f	f	f	f	12	1	f	f	f	f
3	1	t	f	f	f	f	1	1	f	f	f	f
3	3	t	f	f	f	f	2	1	f	f	f	f
3	4	t	f	f	f	f	1	1	f	f	f	f
3	6	t	f	f	f	f	3	1	f	f	f	f
3	7	t	f	f	f	f	3	1	f	f	f	f
3	9	t	f	f	f	f	2	1	f	f	f	f
3	10	t	f	f	f	f	3	1	f	f	f	f
3	12	t	f	f	f	f	1	1	f	f	f	f
3	14	t	f	f	f	f	5	1	f	f	f	f
3	15	t	f	f	f	f	6	1	f	f	f	f
3	16	t	f	f	f	f	7	1	f	f	f	f
3	17	t	t	t	f	t	1	1	f	f	f	f
3	19	t	f	f	f	f	8	1	f	f	f	f
3	20	t	t	f	f	f	1	1	f	f	f	f
3	25	t	f	f	f	f	11	1	f	f	f	f
4	1	t	f	f	f	f	1	1	f	f	f	f
4	15	t	f	f	f	f	2	1	f	f	f	f
4	16	t	f	f	f	f	3	1	f	f	f	f
4	17	t	t	t	f	t	1	1	f	f	f	f
3	18	t	f	f	t	f	2	1	f	f	f	f
2	24	t	t	f	f	f	1	1	f	f	f	f
2	2	t	t	t	f	f	2	1	f	f	f	f
2	11	t	f	f	f	f	5	1	f	f	f	f
3	11	t	f	f	f	f	4	1	f	f	f	f
4	11	t	f	f	f	f	3	1	f	f	f	f
2	28	t	f	f	f	f	3	1	f	f	f	f
3	28	t	f	f	f	f	3	1	f	f	f	f
4	28	t	f	f	f	f	3	1	f	f	f	f
2	31	t	f	t	f	t	2	1	f	f	f	f
2	32	t	f	t	f	f	2	1	f	f	f	f
3	31	t	f	f	f	f	2	1	f	f	f	f
3	32	t	f	f	f	f	2	1	f	f	f	f
3	22	f	f	f	f	f	1	1	f	f	f	f
3	24	t	f	f	f	f	1	1	f	f	f	f
3	21	t	f	f	f	f	9	1	f	f	f	f
3	23	t	f	f	f	f	10	1	f	f	f	f
1	1	t	t	t	t	t	1	1	t	t	t	t
1	2	t	t	t	t	t	2	1	t	t	t	t
1	3	t	t	t	t	t	3	1	t	t	t	t
1	4	t	t	t	t	t	1	1	t	t	t	t
1	5	t	t	t	t	t	2	1	t	t	t	t
1	6	t	t	t	t	t	3	1	t	t	t	t
1	7	t	t	t	t	t	4	1	t	t	t	t
1	8	t	t	t	t	t	1	1	t	t	t	t
1	9	t	t	t	t	t	2	1	t	t	t	t
1	10	t	t	t	t	t	3	1	t	t	t	t
1	12	t	t	t	t	t	1	1	t	t	t	t
1	13	t	t	t	t	t	2	1	t	t	t	t
1	14	t	t	t	t	t	6	1	t	t	t	t
1	15	t	t	t	t	t	7	1	t	t	t	t
1	16	t	t	t	t	t	8	1	t	t	t	t
1	18	t	t	t	t	t	1	1	t	t	t	t
1	25	t	t	t	t	t	9	1	t	t	t	t
1	26	t	t	t	t	t	10	1	t	t	t	t
1	11	t	t	t	t	t	5	1	t	t	t	t
1	28	t	t	t	t	t	3	1	t	t	t	t
1	31	t	t	t	t	t	2	1	t	t	t	t
1	32	t	t	t	t	t	2	1	t	t	t	t
1	19	t	t	t	t	t	11	1	t	t	t	t
1	21	t	t	t	t	t	12	1	t	t	t	t
1	23	t	t	t	t	t	13	1	t	t	t	t
1	17	t	t	t	t	t	14	1	t	t	t	t
1	20	t	t	t	t	t	15	1	t	t	t	t
1	22	t	t	t	t	t	16	1	t	t	t	t
1	24	t	t	t	t	t	17	1	t	t	t	t
2	33	t	f	f	f	f	16	1	f	f	f	t
2	36	t	t	t	t	t	36	1	f	f	f	t
2	37	t	t	t	t	t	37	1	f	f	f	t
2	38	t	t	t	t	t	38	1	f	f	f	t
3	36	t	f	t	t	t	36	1	f	f	f	f
3	37	t	f	t	t	t	37	1	f	f	f	f
3	38	t	f	t	t	t	38	1	f	f	f	f
4	38	t	t	t	f	f	38	1	f	f	f	f
\.


--
-- Data for Name: perfiles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.perfiles (id_perfil, nombre, descripcion, estado_registro) FROM stdin;
1	Administrador del sistema	Administra la configuración técnica, la base de datos, los usuarios, los perfiles, los permisos y los catálogos del sistema. Tiene acceso completo.	1
2	Gerente	Administra la operación del local. Puede gestionar usuarios operativos, inventarios, stock, movimientos, órdenes de compra, recepciones y reportes.	1
4	Miembro de equipo	Consulta el stock y registra conteos de inventario. No puede gestionar compras, recepciones, usuarios ni modificar directamente el stock.	1
3	Supervisor	Supervisa la operación del local. Puede consultar catálogos, carta, recetas, promociones, stock y reportes; realizar y revisar inventarios; registrar movimientos; preparar órdenes de compra y gestionar la recepción de productos. No puede administrar usuarios, perfiles, permisos ni modificar directamente el stock.	1
\.


--
-- Data for Name: presentacion_venta; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.presentacion_venta (id_presentacion_venta, id_item_carta, id_menaje, contenido, unidad, precio, activo) FROM stdin;
1	1	17	1.000	PORCION	29.90	t
2	2	17	1.000	PORCION	29.90	t
3	3	10	0.060	LTR	20.90	t
4	4	10	0.060	LTR	24.90	t
5	5	10	0.060	LTR	20.90	t
6	6	10	0.060	LTR	20.90	t
7	7	10	0.060	LTR	20.90	t
8	8	4	1.000	PORCION	26.90	t
9	9	14	1.000	PORCION	29.90	t
10	10	14	1.000	PORCION	29.90	t
11	11	5	1.000	PORCION	29.90	t
12	12	5	1.000	PORCION	29.90	t
13	13	4	1.000	PORCION	29.90	t
14	14	16	1.000	PORCION	34.90	t
15	15	17	1.000	PORCION	34.90	t
16	16	4	1.000	PORCION	26.90	t
17	17	15	1.000	PORCION	29.90	t
18	18	4	1.000	PORCION	34.90	t
19	19	14	1.000	PORCION	29.90	t
20	20	16	0.060	LTR	29.90	t
21	21	4	1.000	PORCION	29.90	t
22	22	14	1.000	PORCION	35.90	t
23	23	4	1.000	PORCION	29.90	t
24	24	14	1.000	PORCION	29.90	t
25	25	14	1.000	PORCION	35.90	t
26	26	14	1.000	PORCION	44.90	t
27	27	16	1.000	PORCION	29.90	t
28	28	3	1.000	PORCION	39.90	t
29	29	3	1.000	PORCION	39.90	t
30	30	3	1.000	PORCION	59.90	t
31	31	3	1.000	PORCION	59.90	t
32	32	3	1.000	PORCION	59.90	t
33	33	3	1.000	PORCION	59.90	t
34	34	2	1.000	C62	16.00	t
35	35	2	1.000	C62	16.00	t
36	36	2	1.000	C62	16.00	t
37	37	2	1.000	C62	16.00	t
38	38	2	1.000	C62	16.00	t
39	39	2	1.000	C62	16.00	t
40	40	2	1.000	C62	18.00	t
41	41	2	1.000	C62	36.00	t
42	42	2	1.000	C62	42.00	t
43	43	2	1.000	C62	42.00	t
44	44	2	1.000	C62	42.00	t
45	45	2	1.000	C62	42.00	t
46	46	2	1.000	C62	49.00	t
47	47	14	1.000	PORCION	6.90	t
48	48	2	1.000	C62	7.90	t
49	49	2	1.000	C62	7.90	t
50	50	2	1.000	C62	7.90	t
51	51	2	1.000	C62	7.90	t
52	52	2	1.000	C62	7.90	t
53	53	2	1.000	C62	7.90	t
54	54	6	1.000	C62	14.90	t
55	55	6	1.000	C62	14.90	t
56	56	6	1.000	C62	14.90	t
57	57	6	1.000	C62	14.90	t
58	58	6	1.000	C62	14.90	t
59	59	2	1.000	C62	14.90	t
60	60	2	1.000	C62	14.90	t
61	61	8	1.000	PORCION	15.90	t
62	62	8	1.000	PORCION	20.90	t
63	63	7	1.000	PORCION	41.90	t
64	64	8	1.000	PORCION	25.90	t
65	65	8	1.000	PORCION	25.90	t
66	66	8	1.000	PORCION	25.90	t
67	67	8	1.000	PORCION	25.90	t
68	68	7	1.000	PORCION	32.90	t
69	69	7	1.000	PORCION	29.90	t
70	70	8	1.000	PORCION	32.90	t
71	71	11	1.000	PORCION	39.90	t
72	72	11	1.000	PORCION	32.90	t
73	73	13	1.000	PORCION	45.90	t
74	74	8	1.000	PORCION	25.90	t
75	75	1	1.000	PORCION	99.90	t
76	76	1	1.000	PORCION	159.90	t
77	77	12	1.000	PORCION	69.90	t
78	78	12	1.000	PORCION	69.90	t
79	79	7	1.000	PORCION	39.90	t
80	80	13	1.000	PORCION	34.90	t
81	81	8	1.000	PORCION	25.90	t
82	82	7	1.000	PORCION	32.90	t
83	83	13	1.000	PORCION	35.90	t
84	84	13	1.000	PORCION	35.90	t
85	85	13	1.000	PORCION	35.90	t
86	86	13	1.000	PORCION	35.90	t
87	87	13	1.000	PORCION	35.90	t
88	88	13	1.000	PORCION	40.90	t
89	89	13	1.000	PORCION	40.90	t
90	90	13	1.000	PORCION	29.90	t
91	91	7	1.000	PORCION	32.90	t
92	92	7	1.000	PORCION	32.90	t
93	93	9	1.000	PORCION	32.90	t
94	94	9	1.000	PORCION	34.90	t
95	95	9	1.000	PORCION	36.90	t
96	96	9	1.000	PORCION	36.90	t
97	97	9	1.000	PORCION	42.90	t
98	98	9	1.000	PORCION	49.90	t
99	99	9	1.000	PORCION	49.90	t
100	100	4	0.200	LTR	14.00	t
101	100	14	0.400	LTR	20.00	t
102	100	3	0.900	LTR	40.00	t
103	101	4	0.200	LTR	25.00	t
104	101	14	0.400	LTR	33.00	t
105	101	3	0.900	LTR	42.00	t
106	102	4	0.200	LTR	12.00	t
107	102	14	0.400	LTR	19.00	t
108	102	3	0.900	LTR	38.00	t
109	103	4	0.200	LTR	12.00	t
110	103	14	0.400	LTR	19.00	t
111	103	3	0.900	LTR	38.00	t
112	104	4	0.200	LTR	12.00	t
113	104	14	0.400	LTR	19.00	t
114	104	3	0.900	LTR	38.00	t
115	105	4	0.200	LTR	14.00	t
116	105	14	0.400	LTR	20.00	t
117	105	3	0.900	LTR	40.00	t
118	106	4	0.200	LTR	12.00	t
119	106	14	0.400	LTR	19.00	t
120	106	3	0.900	LTR	38.00	t
121	107	4	0.200	LTR	15.00	t
122	107	14	0.400	LTR	22.00	t
123	107	3	0.900	LTR	42.00	t
124	108	4	0.200	LTR	12.00	t
125	108	14	0.400	LTR	19.00	t
126	108	3	0.900	LTR	38.00	t
127	109	4	0.200	LTR	14.00	t
128	109	14	0.400	LTR	20.00	t
129	109	3	0.900	LTR	40.00	t
130	110	4	0.200	LTR	12.00	t
131	110	14	0.400	LTR	19.00	t
132	110	3	0.900	LTR	38.00	t
133	111	4	0.200	LTR	15.00	t
134	111	14	0.400	LTR	22.00	t
135	111	3	0.900	LTR	42.00	t
136	112	4	0.200	LTR	14.00	t
137	112	14	0.400	LTR	20.00	t
138	112	3	0.900	LTR	40.00	t
139	113	4	0.200	LTR	12.00	t
140	113	14	0.400	LTR	19.00	t
141	113	3	0.900	LTR	38.00	t
142	114	4	0.200	LTR	15.00	t
143	114	14	0.400	LTR	22.00	t
144	114	3	0.900	LTR	42.00	t
145	115	4	0.200	LTR	12.00	t
146	115	14	0.400	LTR	19.00	t
147	115	3	0.900	LTR	38.00	t
148	116	4	0.200	LTR	14.00	t
149	116	14	0.400	LTR	20.00	t
150	116	3	0.900	LTR	40.00	t
151	117	4	0.200	LTR	14.00	t
152	117	14	0.400	LTR	20.00	t
153	117	3	0.900	LTR	40.00	t
154	118	4	0.200	LTR	12.00	t
155	118	14	0.400	LTR	19.00	t
156	118	3	0.900	LTR	38.00	t
157	119	4	0.200	LTR	15.00	t
158	119	14	0.400	LTR	22.00	t
159	119	3	0.900	LTR	42.00	t
160	120	4	0.200	LTR	12.00	t
161	120	14	0.400	LTR	19.00	t
162	120	3	0.900	LTR	38.00	t
163	121	4	0.200	LTR	14.00	t
164	121	14	0.400	LTR	20.00	t
165	121	3	0.900	LTR	40.00	t
166	122	4	0.200	LTR	15.00	t
167	122	14	0.400	LTR	22.00	t
168	122	3	0.900	LTR	42.00	t
169	123	4	0.200	LTR	12.00	t
170	123	14	0.400	LTR	19.00	t
171	123	3	0.900	LTR	38.00	t
172	124	4	0.200	LTR	14.00	t
173	124	14	0.400	LTR	20.00	t
174	124	3	0.900	LTR	40.00	t
175	125	4	0.200	LTR	15.00	t
176	125	14	0.400	LTR	22.00	t
177	125	3	0.900	LTR	42.00	t
178	126	4	0.200	LTR	12.00	t
179	126	14	0.400	LTR	19.00	t
180	126	3	0.900	LTR	38.00	t
181	127	4	0.200	LTR	14.00	t
182	127	14	0.400	LTR	20.00	t
183	127	3	0.900	LTR	40.00	t
184	128	4	0.200	LTR	15.00	t
185	128	14	0.400	LTR	22.00	t
186	128	3	0.900	LTR	42.00	t
187	129	4	0.200	LTR	12.00	t
188	129	14	0.400	LTR	19.00	t
189	129	3	0.900	LTR	38.00	t
190	130	4	0.200	LTR	14.00	t
191	130	14	0.400	LTR	20.00	t
192	130	3	0.900	LTR	40.00	t
193	131	4	0.200	LTR	12.00	t
194	131	14	0.400	LTR	19.00	t
195	131	3	0.900	LTR	38.00	t
196	132	4	0.200	LTR	12.00	t
197	132	14	0.400	LTR	19.00	t
198	132	3	0.900	LTR	39.00	t
199	133	5	0.300	LTR	29.90	t
\.


--
-- Data for Name: producto; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.producto (id_producto, codigo, nombre, id_categoria, id_proveedor, unidad, stock_minimo, presentacion, activo) FROM stdin;
143	AB-002	atún	11	12	C62	0.000	6.000	t
1	V-001	Limón	1	1	KGM	5.000	1.000	t
2	V-002	Hierba buena	1	1	KGM	1.000	0.500	t
3	V-003	Papa	1	1	KGM	20.000	10.000	t
4	V-004	Cebolla	1	1	KGM	10.000	5.000	t
5	V-005	Tomate	1	1	KGM	10.000	1.000	t
6	V-006	Pimiento	1	1	KGM	5.000	1.000	t
7	V-007	Palta	1	1	KGM	5.000	1.000	t
8	V-008	Lechuga	1	1	KGM	5.000	1.000	t
9	V-009	Choclo	1	1	KGM	5.000	1.000	t
10	V-010	Champiñones	1	1	KGM	2.000	0.500	t
11	S-001	Sal	2	2	KGM	1.000	1.000	t
12	S-002	Nachos	2	2	C62	10.000	5.000	t
13	S-003	Tortilla de maiz	2	2	C62	10.000	5.000	t
14	S-004	Petti pan	2	2	C62	30.000	12.000	t
15	S-005	Frejoles	2	2	KGM	3.000	1.000	t
16	S-006	Empanizado	2	2	C62	5.000	1.000	t
17	S-007	Pepinillos	2	2	KGM	2.000	1.000	t
18	S-008	Fideos canuto	2	2	KGM	10.000	12.000	t
19	S-009	Arroz	2	2	KGM	5.000	5.000	t
20	S-010	Sillao	2	2	LTR	3.000	1.000	t
21	S-011	Vinagre tinto	2	2	C62	3.000	1.000	t
22	S-012	Huevo	2	2	C62	10.000	12.000	t
23	S-013	Naranja deshidratada	2	2	KGM	0.400	1.000	t
24	S-014	Jarabe de goma	2	2	LTR	2.000	1.000	t
25	S-015	Jarabe de Sandía	2	2	LTR	1.000	1.000	t
26	S-016	Jarabe de frambuesa	2	2	LTR	1.000	1.000	t
27	S-017	Maracuya	2	2	LTR	2.000	5.000	t
28	S-018	Esencia de Chicha	2	2	LTR	4.000	10.000	t
29	S-019	Estrella Damm - Sin alcohol	2	2	C62	3.000	6.000	t
30	S-020	Daura Damm - Sin Gluten	2	2	C62	3.000	6.000	t
31	S-021	Lindermans Kriek	2	2	C62	3.000	6.000	t
32	S-022	San Bernardus ABT 12	2	2	C62	3.000	6.000	t
33	S-023	Westmalle Tripel	2	2	C62	3.000	6.000	t
34	S-024	Chimay Roja	2	2	C62	3.000	6.000	t
35	S-025	Petrus Choco Cherry	2	2	C62	3.000	6.000	t
36	S-026	Delirium Tremens	2	2	C62	3.000	6.000	t
37	SS-001	Salsa cheddar	3	3	KGM	2.000	1.000	t
38	SS-002	Salsa BBQ IPA	3	3	KGM	2.000	1.000	t
39	SS-003	Salsa Acevichada	3	3	KGM	2.000	1.000	t
40	SS-004	Salsa Buffalo	3	3	KGM	2.000	1.000	t
41	SS-005	Salsa Picante Agridulce	3	3	KGM	2.000	1.000	t
42	SS-006	Salsa Mango Charapita	3	3	KGM	2.000	1.000	t
43	SS-007	Chimi churri	3	3	KGM	2.000	1.000	t
44	SS-008	Pulled Pork	3	3	C62	2.000	1.000	t
45	SS-009	BBQ	3	3	KGM	2.000	1.000	t
46	SS-010	Aliño	3	3	C62	2.000	1.000	t
47	SS-011	Salsa mediterránea	3	3	KGM	2.000	1.000	t
48	SS-012	Salsa de chapiñón	3	3	KGM	2.000	1.000	t
49	SS-013	Salsa 4 piminetas	3	3	KGM	2.000	1.000	t
50	SS-014	Salsa de ostión	3	3	LTR	2.000	1.000	t
51	L-001	Queso cheddar	4	4	C62	20.000	10.000	t
52	L-002	Queso gouda	4	4	C62	20.000	10.000	t
53	L-003	Mayonesa de Yogurt	4	4	KGM	2.000	1.000	t
54	L-004	Queso fresco	4	4	KGM	1.000	1.000	t
55	L-005	Blue cheese	4	4	KGM	1.000	1.000	t
56	L-006	Queso parmesano	4	4	C62	1.000	1.000	t
57	L-007	Crema de leche	4	4	LTR	1.000	1.000	t
58	PR-001	Tequeños Ruleta Rusa	5	5	C62	36.000	6.000	t
59	PR-002	Tequeños de Queso	5	5	C62	36.000	6.000	t
60	PR-003	Tequeños Pulled Pork	5	5	C62	36.000	6.000	t
61	PR-004	Aros de cebolla	5	5	C62	36.000	6.000	t
62	PR-005	Pure	5	5	C62	10.000	1.000	t
63	PR-006	Cordon Blue	5	5	C62	10.000	1.000	t
105	CV-005	L.I.M.A	9	9	LTR	5.000	30.000	t
64	C-001	Frankfurter	6	6	C62	10.000	5.000	t
65	C-002	Chorizo	6	6	C62	10.000	4.000	t
66	C-003	Pechuga de Pollo	6	6	C62	10.000	10.000	t
67	C-004	Tocino	6	6	C62	10.000	10.000	t
68	C-005	Hamburguesa 100g	6	6	C62	10.000	20.000	t
69	C-006	Filete de pollo	6	6	C62	10.000	10.000	t
70	C-007	Bife angosto	6	6	C62	10.000	10.000	t
71	C-008	Chorizo finas hierbas	6	6	C62	10.000	4.000	t
72	C-009	Alitas	6	6	C62	10.000	24.000	t
73	C-010	Hamburguesa 200g	6	6	C62	10.000	20.000	t
74	C-011	Medallón de lomo	6	6	C62	10.000	10.000	t
75	B-001	Schweppes	7	7	C62	10.000	12.000	t
76	B-002	Agua tonica	7	7	C62	10.000	24.000	t
77	B-003	Coca Cola	7	7	C62	10.000	15.000	t
78	B-004	Inca Kola	7	7	C62	10.000	15.000	t
79	B-005	Coca Cola sin Azucar	7	7	C62	10.000	15.000	t
80	B-006	Inca Kola sin Azucar	7	7	C62	10.000	15.000	t
81	B-007	Agua sin gas	7	7	C62	10.000	15.000	t
82	B-008	Agua con Gas	7	7	C62	10.000	15.000	t
83	B-009	Red bull	7	7	C62	10.000	24.000	t
84	B-010	Red bull Tropical Edition	7	7	C62	10.000	24.000	t
85	B-011	Red bull Sugar Free	7	7	C62	10.000	24.000	t
86	B-012	Red bull Red Edition	7	7	C62	10.000	24.000	t
87	B-013	Red Bull Green Edition	7	7	C62	10.000	24.000	t
88	B-014	Mr. Perkins Pink Soda	7	7	C62	10.000	24.000	t
89	B-015	Mr. Perkins Ginger Beer	7	7	C62	10.000	24.000	t
90	T-001	Jager	8	8	LTR	0.700	0.700	t
91	T-002	Whisky	8	8	LTR	0.700	0.700	t
92	T-003	Ron	8	8	LTR	0.700	0.700	t
93	T-004	Tequila	8	8	LTR	0.700	0.700	t
94	T-005	Pisco	8	8	LTR	2.000	2.000	t
95	T-006	Vodka	8	8	LTR	0.700	0.700	t
96	T-007	Aperol	8	8	LTR	0.700	0.700	t
97	T-008	Cinzano	8	8	LTR	0.700	0.700	t
98	T-009	Campari	8	8	LTR	0.700	0.700	t
99	T-010	Martini	8	8	LTR	0.700	0.700	t
100	T-011	Gin	8	8	LTR	0.600	0.600	t
101	CV-001	Magic Quinua	9	9	LTR	5.000	30.000	t
102	CV-002	Dámela Siempre	9	9	LTR	5.000	30.000	t
103	CV-003	La Nena	9	9	LTR	5.000	30.000	t
104	CV-004	Barbarian Red Ale	9	9	LTR	5.000	30.000	t
106	CV-006	Chaski	9	9	LTR	5.000	30.000	t
107	CV-007	174 IPA	9	9	LTR	5.000	30.000	t
108	CV-008	Final Feliz	9	9	LTR	5.000	30.000	t
109	CV-009	2 Más	9	9	LTR	5.000	30.000	t
110	CV-010	Belga Pa’ Ti	9	9	LTR	5.000	30.000	t
111	CV-011	K-7	9	9	LTR	5.000	30.000	t
112	CV-012	Mañanero	9	9	LTR	5.000	30.000	t
113	CV-013	Lou	9	9	LTR	5.000	30.000	t
114	CV-014	Peaky Biter	9	9	LTR	5.000	30.000	t
115	CV-015	Chicha Tu Mare	9	9	LTR	5.000	30.000	t
116	CV-016	Barbarov	9	9	LTR	5.000	30.000	t
117	CV-017	Tropical Nordic	9	9	LTR	5.000	30.000	t
118	CV-018	St Patrick’s	9	9	LTR	5.000	30.000	t
119	CV-019	Oktu-Brefest	9	9	LTR	5.000	30.000	t
120	CV-020	Blueberry Gose	9	9	LTR	5.000	30.000	t
121	CV-021	Camu Camu Maracuyá	9	9	LTR	5.000	30.000	t
122	CV-022	La Última Chupada del Mango	9	9	LTR	5.000	30.000	t
123	CV-023	De la Selva Su Gose	9	9	LTR	5.000	30.000	t
124	CV-024	Krieger	9	9	LTR	5.000	30.000	t
125	CV-025	Dark Krieger	9	9	LTR	5.000	30.000	t
126	CV-026	De Peso Pumpkin Ale	9	9	LTR	5.000	30.000	t
127	CV-027	Chelón de Doña Pepa	9	9	LTR	5.000	30.000	t
128	CV-028	Crazy Llama	9	9	LTR	5.000	30.000	t
129	CV-029	Apagón	9	9	LTR	5.000	30.000	t
130	CV-030	VALKIRIA	9	9	LTR	5.000	30.000	t
131	CV-031	GRANADILLA	9	9	LTR	5.000	30.000	t
132	CV-032	INTERESTELAGER	9	9	LTR	5.000	30.000	t
133	CV-033	POLVO ESTELAR	9	9	LTR	5.000	30.000	t
134	CV-034	TINTO DE VERANO	9	9	LTR	5.000	30.000	t
135	CV-035	Botella de 174 IPA	9	9	C62	5.000	6.000	t
136	CV-036	Botella de La Nena Trigo	9	9	C62	5.000	6.000	t
137	CV-037	Botella de L.I.M.A. Pale Ale	9	9	C62	5.000	6.000	t
138	CV-038	Botella de Magic Quinua	9	9	C62	5.000	6.000	t
139	CV-039	Botella de Red	9	9	C62	5.000	6.000	t
140	S-027	Pan Hamburguesa	2	2	C62	12.000	24.000	t
\.


--
-- Data for Name: producto_categoria_historial; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.producto_categoria_historial (id_producto_categoria_historial, id_producto, id_categoria_anterior, id_categoria_nueva, usuario_cambio, fecha_cambio, motivo) FROM stdin;
\.


--
-- Data for Name: producto_proveedor_historial; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.producto_proveedor_historial (id_producto_proveedor_historial, id_producto, id_proveedor_anterior, id_proveedor_nuevo, usuario_cambio, fecha_cambio, motivo) FROM stdin;
\.


--
-- Data for Name: producto_stock_local; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.producto_stock_local (id_producto, id_local, stock_minimo, stock_maximo) FROM stdin;
1	1	5.000	\N
1	2	5.000	\N
1	3	5.000	\N
1	4	5.000	\N
2	1	1.000	\N
2	2	1.000	\N
2	3	1.000	\N
2	4	1.000	\N
3	1	20.000	\N
3	2	20.000	\N
3	3	20.000	\N
3	4	20.000	\N
4	1	10.000	\N
4	2	10.000	\N
4	3	10.000	\N
4	4	10.000	\N
5	1	10.000	\N
5	2	10.000	\N
5	3	10.000	\N
5	4	10.000	\N
6	1	5.000	\N
6	2	5.000	\N
6	3	5.000	\N
6	4	5.000	\N
7	1	5.000	\N
7	2	5.000	\N
7	3	5.000	\N
7	4	5.000	\N
8	1	5.000	\N
8	2	5.000	\N
8	3	5.000	\N
8	4	5.000	\N
9	1	5.000	\N
9	2	5.000	\N
9	3	5.000	\N
9	4	5.000	\N
10	1	2.000	\N
10	2	2.000	\N
10	3	2.000	\N
10	4	2.000	\N
11	1	1.000	\N
11	2	1.000	\N
11	3	1.000	\N
11	4	1.000	\N
12	1	10.000	\N
12	2	10.000	\N
12	3	10.000	\N
12	4	10.000	\N
13	1	10.000	\N
13	2	10.000	\N
13	3	10.000	\N
13	4	10.000	\N
14	1	30.000	\N
14	2	30.000	\N
14	3	30.000	\N
14	4	30.000	\N
15	1	3.000	\N
15	2	3.000	\N
15	3	3.000	\N
15	4	3.000	\N
16	1	5.000	\N
16	2	5.000	\N
16	3	5.000	\N
16	4	5.000	\N
17	1	2.000	\N
17	2	2.000	\N
17	3	2.000	\N
17	4	2.000	\N
18	1	10.000	\N
18	2	10.000	\N
18	3	10.000	\N
18	4	10.000	\N
19	1	5.000	\N
19	2	5.000	\N
19	3	5.000	\N
19	4	5.000	\N
20	1	3.000	\N
20	2	3.000	\N
20	3	3.000	\N
20	4	3.000	\N
21	1	3.000	\N
21	2	3.000	\N
21	3	3.000	\N
21	4	3.000	\N
22	1	10.000	\N
22	2	10.000	\N
22	3	10.000	\N
22	4	10.000	\N
23	1	0.400	\N
23	2	0.400	\N
23	3	0.400	\N
23	4	0.400	\N
24	1	2.000	\N
24	2	2.000	\N
24	3	2.000	\N
24	4	2.000	\N
25	1	1.000	\N
25	2	1.000	\N
25	3	1.000	\N
25	4	1.000	\N
26	1	1.000	\N
26	2	1.000	\N
26	3	1.000	\N
26	4	1.000	\N
27	1	2.000	\N
27	2	2.000	\N
27	3	2.000	\N
27	4	2.000	\N
28	1	4.000	\N
28	2	4.000	\N
28	3	4.000	\N
28	4	4.000	\N
29	1	3.000	\N
29	2	3.000	\N
29	3	3.000	\N
29	4	3.000	\N
30	1	3.000	\N
30	2	3.000	\N
30	3	3.000	\N
30	4	3.000	\N
31	1	3.000	\N
31	2	3.000	\N
31	3	3.000	\N
31	4	3.000	\N
32	1	3.000	\N
32	2	3.000	\N
32	3	3.000	\N
32	4	3.000	\N
33	1	3.000	\N
33	2	3.000	\N
33	3	3.000	\N
33	4	3.000	\N
34	1	3.000	\N
34	2	3.000	\N
34	3	3.000	\N
34	4	3.000	\N
35	1	3.000	\N
35	2	3.000	\N
35	3	3.000	\N
35	4	3.000	\N
36	1	3.000	\N
36	2	3.000	\N
36	3	3.000	\N
36	4	3.000	\N
37	1	2.000	\N
37	2	2.000	\N
37	3	2.000	\N
37	4	2.000	\N
38	1	2.000	\N
38	2	2.000	\N
38	3	2.000	\N
38	4	2.000	\N
39	1	2.000	\N
39	2	2.000	\N
39	3	2.000	\N
39	4	2.000	\N
40	1	2.000	\N
40	2	2.000	\N
40	3	2.000	\N
40	4	2.000	\N
41	1	2.000	\N
41	2	2.000	\N
41	3	2.000	\N
41	4	2.000	\N
42	1	2.000	\N
42	2	2.000	\N
42	3	2.000	\N
42	4	2.000	\N
43	1	2.000	\N
43	2	2.000	\N
43	3	2.000	\N
43	4	2.000	\N
44	1	2.000	\N
44	2	2.000	\N
44	3	2.000	\N
44	4	2.000	\N
45	1	2.000	\N
45	2	2.000	\N
45	3	2.000	\N
45	4	2.000	\N
46	1	2.000	\N
46	2	2.000	\N
46	3	2.000	\N
46	4	2.000	\N
47	1	2.000	\N
47	2	2.000	\N
47	3	2.000	\N
47	4	2.000	\N
48	1	2.000	\N
48	2	2.000	\N
48	3	2.000	\N
48	4	2.000	\N
49	1	2.000	\N
49	2	2.000	\N
49	3	2.000	\N
49	4	2.000	\N
50	1	2.000	\N
50	2	2.000	\N
50	3	2.000	\N
50	4	2.000	\N
51	1	20.000	\N
51	2	20.000	\N
51	3	20.000	\N
51	4	20.000	\N
52	1	20.000	\N
52	2	20.000	\N
52	3	20.000	\N
52	4	20.000	\N
53	1	2.000	\N
53	2	2.000	\N
53	3	2.000	\N
53	4	2.000	\N
54	1	1.000	\N
54	2	1.000	\N
54	3	1.000	\N
54	4	1.000	\N
55	1	1.000	\N
55	2	1.000	\N
55	3	1.000	\N
55	4	1.000	\N
56	1	1.000	\N
56	2	1.000	\N
56	3	1.000	\N
56	4	1.000	\N
57	1	1.000	\N
57	2	1.000	\N
57	3	1.000	\N
57	4	1.000	\N
58	1	36.000	\N
58	2	36.000	\N
58	3	36.000	\N
58	4	36.000	\N
59	1	36.000	\N
59	2	36.000	\N
59	3	36.000	\N
59	4	36.000	\N
60	1	36.000	\N
60	2	36.000	\N
60	3	36.000	\N
60	4	36.000	\N
61	1	36.000	\N
61	2	36.000	\N
61	3	36.000	\N
61	4	36.000	\N
62	1	10.000	\N
62	2	10.000	\N
62	3	10.000	\N
62	4	10.000	\N
63	1	10.000	\N
63	2	10.000	\N
63	3	10.000	\N
63	4	10.000	\N
64	1	10.000	\N
64	2	10.000	\N
64	3	10.000	\N
64	4	10.000	\N
65	1	10.000	\N
65	2	10.000	\N
65	3	10.000	\N
65	4	10.000	\N
66	1	10.000	\N
66	2	10.000	\N
66	3	10.000	\N
66	4	10.000	\N
67	1	10.000	\N
67	2	10.000	\N
67	3	10.000	\N
67	4	10.000	\N
68	1	10.000	\N
68	2	10.000	\N
68	3	10.000	\N
68	4	10.000	\N
69	1	10.000	\N
69	2	10.000	\N
69	3	10.000	\N
69	4	10.000	\N
70	1	10.000	\N
70	2	10.000	\N
70	3	10.000	\N
70	4	10.000	\N
71	1	10.000	\N
71	2	10.000	\N
71	3	10.000	\N
71	4	10.000	\N
72	1	10.000	\N
72	2	10.000	\N
72	3	10.000	\N
72	4	10.000	\N
73	1	10.000	\N
73	2	10.000	\N
73	3	10.000	\N
73	4	10.000	\N
74	1	10.000	\N
74	2	10.000	\N
74	3	10.000	\N
74	4	10.000	\N
75	1	10.000	\N
75	2	10.000	\N
75	3	10.000	\N
75	4	10.000	\N
76	1	10.000	\N
76	2	10.000	\N
76	3	10.000	\N
76	4	10.000	\N
77	1	10.000	\N
77	2	10.000	\N
77	3	10.000	\N
77	4	10.000	\N
78	1	10.000	\N
78	2	10.000	\N
78	3	10.000	\N
78	4	10.000	\N
79	1	10.000	\N
79	2	10.000	\N
79	3	10.000	\N
79	4	10.000	\N
80	1	10.000	\N
80	2	10.000	\N
80	3	10.000	\N
80	4	10.000	\N
81	1	10.000	\N
81	2	10.000	\N
81	3	10.000	\N
81	4	10.000	\N
82	1	10.000	\N
82	2	10.000	\N
82	3	10.000	\N
82	4	10.000	\N
83	1	10.000	\N
83	2	10.000	\N
83	3	10.000	\N
83	4	10.000	\N
84	1	10.000	\N
84	2	10.000	\N
84	3	10.000	\N
84	4	10.000	\N
85	1	10.000	\N
85	2	10.000	\N
85	3	10.000	\N
85	4	10.000	\N
86	1	10.000	\N
86	2	10.000	\N
86	3	10.000	\N
86	4	10.000	\N
87	1	10.000	\N
87	2	10.000	\N
87	3	10.000	\N
87	4	10.000	\N
88	1	10.000	\N
88	2	10.000	\N
88	3	10.000	\N
88	4	10.000	\N
89	1	10.000	\N
89	2	10.000	\N
89	3	10.000	\N
89	4	10.000	\N
90	1	0.700	\N
90	2	0.700	\N
90	3	0.700	\N
90	4	0.700	\N
91	1	0.700	\N
91	2	0.700	\N
91	3	0.700	\N
91	4	0.700	\N
92	1	0.700	\N
92	2	0.700	\N
92	3	0.700	\N
92	4	0.700	\N
93	1	0.700	\N
93	2	0.700	\N
93	3	0.700	\N
93	4	0.700	\N
94	1	2.000	\N
94	2	2.000	\N
94	3	2.000	\N
94	4	2.000	\N
95	1	0.700	\N
95	2	0.700	\N
95	3	0.700	\N
95	4	0.700	\N
96	1	0.700	\N
96	2	0.700	\N
96	3	0.700	\N
96	4	0.700	\N
97	1	0.700	\N
97	2	0.700	\N
97	3	0.700	\N
97	4	0.700	\N
98	1	0.700	\N
98	2	0.700	\N
98	3	0.700	\N
98	4	0.700	\N
99	1	0.700	\N
99	2	0.700	\N
99	3	0.700	\N
99	4	0.700	\N
100	1	0.600	\N
100	2	0.600	\N
100	3	0.600	\N
100	4	0.600	\N
101	1	5.000	\N
101	2	5.000	\N
101	3	5.000	\N
101	4	5.000	\N
102	1	5.000	\N
102	2	5.000	\N
102	3	5.000	\N
102	4	5.000	\N
103	1	5.000	\N
103	2	5.000	\N
103	3	5.000	\N
103	4	5.000	\N
104	1	5.000	\N
104	2	5.000	\N
104	3	5.000	\N
104	4	5.000	\N
105	1	5.000	\N
105	2	5.000	\N
105	3	5.000	\N
105	4	5.000	\N
106	1	5.000	\N
106	2	5.000	\N
106	3	5.000	\N
106	4	5.000	\N
107	2	5.000	\N
107	4	5.000	\N
108	1	5.000	\N
108	2	5.000	\N
108	3	5.000	\N
108	4	5.000	\N
109	2	5.000	\N
109	3	5.000	\N
109	4	5.000	\N
110	1	5.000	\N
110	2	5.000	\N
110	3	5.000	\N
110	4	5.000	\N
111	1	5.000	\N
111	2	5.000	\N
111	3	5.000	\N
111	4	5.000	\N
112	1	5.000	\N
112	2	5.000	\N
112	3	5.000	\N
112	4	5.000	\N
113	1	5.000	\N
113	2	5.000	\N
113	3	5.000	\N
113	4	5.000	\N
114	1	5.000	\N
114	2	5.000	\N
114	3	5.000	\N
114	4	5.000	\N
115	1	5.000	\N
115	2	5.000	\N
115	3	5.000	\N
115	4	5.000	\N
116	1	5.000	\N
116	2	5.000	\N
116	3	5.000	\N
116	4	5.000	\N
117	1	5.000	\N
117	2	5.000	\N
117	3	5.000	\N
117	4	5.000	\N
118	1	5.000	\N
118	2	5.000	\N
118	3	5.000	\N
118	4	5.000	\N
119	1	5.000	\N
119	2	5.000	\N
119	3	5.000	\N
119	4	5.000	\N
120	1	5.000	\N
120	2	5.000	\N
120	3	5.000	\N
120	4	5.000	\N
121	1	5.000	\N
121	2	5.000	\N
121	3	5.000	\N
121	4	5.000	\N
122	1	5.000	\N
122	2	5.000	\N
122	3	5.000	\N
122	4	5.000	\N
123	1	5.000	\N
123	2	5.000	\N
123	3	5.000	\N
123	4	5.000	\N
124	1	5.000	\N
124	2	5.000	\N
124	3	5.000	\N
124	4	5.000	\N
125	1	5.000	\N
125	2	5.000	\N
125	3	5.000	\N
125	4	5.000	\N
126	1	5.000	\N
126	2	5.000	\N
126	3	5.000	\N
126	4	5.000	\N
127	1	5.000	\N
127	2	5.000	\N
127	3	5.000	\N
127	4	5.000	\N
128	1	5.000	\N
128	2	5.000	\N
128	3	5.000	\N
128	4	5.000	\N
129	1	5.000	\N
129	2	5.000	\N
129	3	5.000	\N
129	4	5.000	\N
130	1	5.000	\N
130	2	5.000	\N
130	3	5.000	\N
130	4	5.000	\N
131	1	5.000	\N
131	2	5.000	\N
131	3	5.000	\N
131	4	5.000	\N
132	1	5.000	\N
132	2	5.000	\N
132	3	5.000	\N
132	4	5.000	\N
133	1	5.000	\N
133	2	5.000	\N
133	3	5.000	\N
133	4	5.000	\N
134	1	5.000	\N
134	2	5.000	\N
134	3	5.000	\N
134	4	5.000	\N
135	1	5.000	\N
135	2	5.000	\N
135	3	5.000	\N
135	4	5.000	\N
136	1	5.000	\N
136	2	5.000	\N
136	3	5.000	\N
136	4	5.000	\N
137	1	5.000	\N
137	2	5.000	\N
137	3	5.000	\N
137	4	5.000	\N
138	1	5.000	\N
138	2	5.000	\N
138	3	5.000	\N
138	4	5.000	\N
139	1	5.000	\N
139	2	5.000	\N
139	3	5.000	\N
109	1	5.000	100.000
107	3	10.000	10.000
139	4	5.000	\N
140	1	12.000	\N
140	2	12.000	\N
140	3	12.000	\N
140	4	12.000	\N
107	1	5.000	100.000
\.


--
-- Data for Name: promocion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.promocion (id_promocion, codigo, nombre, precio, hora_inicio, hora_fin, activo) FROM stdin;
1	P-001	Barbarian de Verano x2	39.90	\N	\N	t
2	P-002	Aperol Spritz x2	39.90	\N	\N	t
3	P-003	After Office	59.90	17:00:00	20:00:00	t
\.


--
-- Data for Name: promocion_grupo; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.promocion_grupo (id_promocion_grupo, id_promocion, cantidad_elegir, permite_repetir) FROM stdin;
1	1	2	t
2	2	2	t
3	3	2	t
\.


--
-- Data for Name: promocion_opcion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.promocion_opcion (id_promocion_opcion, id_promocion_grupo, id_presentacion_venta) FROM stdin;
1	1	11
2	2	12
3	3	28
4	3	29
5	3	30
6	3	31
7	3	32
8	3	33
\.


--
-- Data for Name: proveedor; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.proveedor (id_proveedor, nombre, activo) FROM stdin;
1	AgroVerde Santa Anita S.A.C.	t
2	Distribuidora Central Lima S.A.C.	t
3	Sabores Food Service Perú S.A.C.	t
4	Lácteos Andinos Horeca S.A.C.	t
5	Producción Interna – Cocina	t
6	Frigorífico Buen Corte S.A.C.	t
7	Bebidas Capital S.A.C.	t
8	Licores Premium Lima S.A.C.	t
9	Barriles Artesanales del Valle S.A.C.	t
12	pepito	t
\.


--
-- Data for Name: proveedor_categoria; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.proveedor_categoria (id_proveedor, id_categoria) FROM stdin;
8	8
2	2
5	5
1	1
4	4
7	7
3	3
9	9
6	6
12	11
\.


--
-- Data for Name: puesto_laboral; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.puesto_laboral (id_puesto_laboral, nombre, descripcion, estado_registro, usuario_creacion, fecha_creacion, usuario_modificacion, fecha_modificacion) FROM stdin;
1	Mesero	Atención de mesas y servicio al cliente.	1	\N	2026-09-20 12:12:29.76528	\N	\N
2	Bartender	Preparación y despacho de bebidas en barra.	1	\N	2026-09-20 12:12:29.76528	\N	\N
3	Cocina	Preparación y producción de alimentos.	1	\N	2026-09-20 12:12:29.76528	\N	\N
\.


--
-- Data for Name: receta; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.receta (id_receta, id_presentacion_venta, instrucciones, activo) FROM stdin;
1	1	Pendiente de registrar.	t
2	2	Pendiente de registrar.	t
3	3	Pendiente de registrar.	t
4	4	Pendiente de registrar.	t
5	5	Pendiente de registrar.	t
6	6	Pendiente de registrar.	t
7	7	Pendiente de registrar.	t
8	8	Pendiente de registrar.	t
9	9	Pendiente de registrar.	t
10	10	Pendiente de registrar.	t
11	11	Pendiente de registrar.	t
12	12	Pendiente de registrar.	t
13	13	Pendiente de registrar.	t
14	14	Pendiente de registrar.	t
15	15	Pendiente de registrar.	t
16	16	Pendiente de registrar.	t
17	17	Pendiente de registrar.	t
18	18	Pendiente de registrar.	t
19	19	Pendiente de registrar.	t
20	20	Pendiente de registrar.	t
21	21	Pendiente de registrar.	t
22	22	Pendiente de registrar.	t
23	23	Pendiente de registrar.	t
24	24	Pendiente de registrar.	t
25	25	Pendiente de registrar.	t
26	26	Pendiente de registrar.	t
27	27	Pendiente de registrar.	t
28	28	Pendiente de registrar.	t
29	29	Pendiente de registrar.	t
30	30	Pendiente de registrar.	t
31	31	Pendiente de registrar.	t
32	32	Pendiente de registrar.	t
33	33	Pendiente de registrar.	t
34	34	Pendiente de registrar.	t
35	35	Pendiente de registrar.	t
36	36	Pendiente de registrar.	t
37	37	Pendiente de registrar.	t
38	38	Pendiente de registrar.	t
39	39	Pendiente de registrar.	t
40	40	Pendiente de registrar.	t
41	41	Pendiente de registrar.	t
42	42	Pendiente de registrar.	t
43	43	Pendiente de registrar.	t
44	44	Pendiente de registrar.	t
45	45	Pendiente de registrar.	t
46	46	Pendiente de registrar.	t
47	47	Pendiente de registrar.	t
48	48	Pendiente de registrar.	t
49	49	Pendiente de registrar.	t
50	50	Pendiente de registrar.	t
51	51	Pendiente de registrar.	t
52	52	Pendiente de registrar.	t
53	53	Pendiente de registrar.	t
54	54	Pendiente de registrar.	t
55	55	Pendiente de registrar.	t
56	56	Pendiente de registrar.	t
57	57	Pendiente de registrar.	t
58	58	Pendiente de registrar.	t
59	59	Pendiente de registrar.	t
60	60	Pendiente de registrar.	t
61	61	Pendiente de registrar.	t
62	62	Pendiente de registrar.	t
63	63	Pendiente de registrar.	t
64	64	Pendiente de registrar.	t
65	65	Pendiente de registrar.	t
66	66	Pendiente de registrar.	t
67	67	Pendiente de registrar.	t
68	68	Pendiente de registrar.	t
69	69	Pendiente de registrar.	t
70	70	Pendiente de registrar.	t
71	71	Pendiente de registrar.	t
72	72	Pendiente de registrar.	t
73	73	Pendiente de registrar.	t
74	74	Pendiente de registrar.	t
75	75	Pendiente de registrar.	t
76	76	Pendiente de registrar.	t
77	77	Pendiente de registrar.	t
78	78	Pendiente de registrar.	t
79	79	Pendiente de registrar.	t
80	80	Pendiente de registrar.	t
81	81	Pendiente de registrar.	t
82	82	Pendiente de registrar.	t
83	83	Pendiente de registrar.	t
84	84	Pendiente de registrar.	t
85	85	Pendiente de registrar.	t
86	86	Pendiente de registrar.	t
87	87	Pendiente de registrar.	t
88	88	Pendiente de registrar.	t
89	89	Pendiente de registrar.	t
90	90	Pendiente de registrar.	t
91	91	Pendiente de registrar.	t
92	92	Pendiente de registrar.	t
93	93	Pendiente de registrar.	t
94	94	Pendiente de registrar.	t
95	95	Pendiente de registrar.	t
96	96	Pendiente de registrar.	t
97	97	Pendiente de registrar.	t
98	98	Pendiente de registrar.	t
99	99	Pendiente de registrar.	t
100	100	Pendiente de registrar.	t
101	101	Pendiente de registrar.	t
102	102	Pendiente de registrar.	t
103	103	Pendiente de registrar.	t
104	104	Pendiente de registrar.	t
105	105	Pendiente de registrar.	t
106	106	Pendiente de registrar.	t
107	107	Pendiente de registrar.	t
108	108	Pendiente de registrar.	t
109	109	Pendiente de registrar.	t
110	110	Pendiente de registrar.	t
111	111	Pendiente de registrar.	t
112	112	Pendiente de registrar.	t
113	113	Pendiente de registrar.	t
114	114	Pendiente de registrar.	t
115	115	Pendiente de registrar.	t
116	116	Pendiente de registrar.	t
117	117	Pendiente de registrar.	t
118	118	Pendiente de registrar.	t
119	119	Pendiente de registrar.	t
120	120	Pendiente de registrar.	t
121	121	Pendiente de registrar.	t
122	122	Pendiente de registrar.	t
123	123	Pendiente de registrar.	t
124	124	Pendiente de registrar.	t
125	125	Pendiente de registrar.	t
126	126	Pendiente de registrar.	t
127	127	Pendiente de registrar.	t
128	128	Pendiente de registrar.	t
129	129	Pendiente de registrar.	t
130	130	Pendiente de registrar.	t
131	131	Pendiente de registrar.	t
132	132	Pendiente de registrar.	t
133	133	Pendiente de registrar.	t
134	134	Pendiente de registrar.	t
135	135	Pendiente de registrar.	t
136	136	Pendiente de registrar.	t
137	137	Pendiente de registrar.	t
138	138	Pendiente de registrar.	t
139	139	Pendiente de registrar.	t
140	140	Pendiente de registrar.	t
141	141	Pendiente de registrar.	t
142	142	Pendiente de registrar.	t
143	143	Pendiente de registrar.	t
144	144	Pendiente de registrar.	t
145	145	Pendiente de registrar.	t
146	146	Pendiente de registrar.	t
147	147	Pendiente de registrar.	t
148	148	Pendiente de registrar.	t
149	149	Pendiente de registrar.	t
150	150	Pendiente de registrar.	t
151	151	Pendiente de registrar.	t
152	152	Pendiente de registrar.	t
153	153	Pendiente de registrar.	t
154	154	Pendiente de registrar.	t
155	155	Pendiente de registrar.	t
156	156	Pendiente de registrar.	t
157	157	Pendiente de registrar.	t
158	158	Pendiente de registrar.	t
159	159	Pendiente de registrar.	t
160	160	Pendiente de registrar.	t
161	161	Pendiente de registrar.	t
162	162	Pendiente de registrar.	t
163	163	Pendiente de registrar.	t
164	164	Pendiente de registrar.	t
165	165	Pendiente de registrar.	t
166	166	Pendiente de registrar.	t
167	167	Pendiente de registrar.	t
168	168	Pendiente de registrar.	t
169	169	Pendiente de registrar.	t
170	170	Pendiente de registrar.	t
171	171	Pendiente de registrar.	t
172	172	Pendiente de registrar.	t
173	173	Pendiente de registrar.	t
174	174	Pendiente de registrar.	t
175	175	Pendiente de registrar.	t
176	176	Pendiente de registrar.	t
177	177	Pendiente de registrar.	t
178	178	Pendiente de registrar.	t
179	179	Pendiente de registrar.	t
180	180	Pendiente de registrar.	t
181	181	Pendiente de registrar.	t
182	182	Pendiente de registrar.	t
183	183	Pendiente de registrar.	t
184	184	Pendiente de registrar.	t
185	185	Pendiente de registrar.	t
186	186	Pendiente de registrar.	t
187	187	Pendiente de registrar.	t
188	188	Pendiente de registrar.	t
189	189	Pendiente de registrar.	t
190	190	Pendiente de registrar.	t
191	191	Pendiente de registrar.	t
192	192	Pendiente de registrar.	t
193	193	Pendiente de registrar.	t
194	194	Pendiente de registrar.	t
195	195	Pendiente de registrar.	t
196	196	Pendiente de registrar.	t
197	197	Pendiente de registrar.	t
198	198	Pendiente de registrar.	t
199	199	Pendiente de registrar.	t
\.


--
-- Data for Name: receta_detalle; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.receta_detalle (id_receta_detalle, id_receta, tipo_componente, id_producto, id_subproducto, cantidad, unidad) FROM stdin;
1	1	PRODUCTO	105	\N	0.300	LTR
2	1	PRODUCTO	90	\N	0.030	LTR
3	2	PRODUCTO	106	\N	0.300	LTR
4	2	PRODUCTO	91	\N	0.060	LTR
5	3	PRODUCTO	92	\N	0.060	LTR
6	4	PRODUCTO	93	\N	0.070	LTR
7	5	PRODUCTO	90	\N	0.060	LTR
8	6	PRODUCTO	94	\N	0.060	LTR
9	7	PRODUCTO	95	\N	0.060	LTR
10	8	PRODUCTO	94	\N	0.060	LTR
11	8	PRODUCTO	1	\N	0.050	KGM
12	8	PRODUCTO	27	\N	0.030	LTR
13	8	PRODUCTO	75	\N	0.300	C62
14	9	PRODUCTO	94	\N	0.090	LTR
15	9	PRODUCTO	1	\N	0.050	KGM
16	9	PRODUCTO	22	\N	1.000	C62
17	9	PRODUCTO	24	\N	0.030	LTR
18	9	PRODUCTO	27	\N	0.030	LTR
19	10	PRODUCTO	1	\N	0.050	KGM
20	10	PRODUCTO	92	\N	0.090	LTR
21	10	PRODUCTO	24	\N	0.030	LTR
22	10	PRODUCTO	2	\N	0.010	KGM
23	10	PRODUCTO	27	\N	0.030	LTR
24	10	PRODUCTO	75	\N	0.500	C62
25	11	PRODUCTO	134	\N	0.300	LTR
26	11	PRODUCTO	23	\N	0.050	KGM
27	12	PRODUCTO	97	\N	0.060	LTR
28	12	PRODUCTO	96	\N	0.060	LTR
29	12	PRODUCTO	23	\N	0.050	KGM
30	12	PRODUCTO	82	\N	0.500	C62
31	13	PRODUCTO	1	\N	0.050	KGM
32	13	PRODUCTO	92	\N	0.060	LTR
33	13	PRODUCTO	77	\N	0.500	C62
34	14	PRODUCTO	23	\N	0.050	KGM
35	14	PRODUCTO	100	\N	0.030	LTR
36	14	PRODUCTO	98	\N	0.030	LTR
37	14	PRODUCTO	99	\N	0.030	LTR
38	15	PRODUCTO	83	\N	1.000	C62
39	15	PRODUCTO	90	\N	0.060	LTR
40	16	PRODUCTO	1	\N	0.050	KGM
41	16	PRODUCTO	94	\N	0.060	LTR
42	16	PRODUCTO	75	\N	0.500	C62
43	17	PRODUCTO	1	\N	0.050	KGM
44	17	PRODUCTO	95	\N	0.060	LTR
45	17	PRODUCTO	89	\N	1.000	C62
46	17	PRODUCTO	23	\N	0.050	KGM
47	18	PRODUCTO	1	\N	0.050	KGM
48	18	PRODUCTO	100	\N	0.600	LTR
49	18	PRODUCTO	76	\N	1.000	C62
50	19	PRODUCTO	1	\N	0.050	KGM
51	19	PRODUCTO	11	\N	0.050	KGM
52	19	PRODUCTO	23	\N	0.050	KGM
53	19	PRODUCTO	93	\N	0.060	LTR
54	19	PRODUCTO	88	\N	1.000	C62
55	20	PRODUCTO	23	\N	0.050	KGM
56	20	PRODUCTO	91	\N	0.060	LTR
57	21	PRODUCTO	95	\N	0.060	LTR
58	21	PRODUCTO	76	\N	0.500	C62
59	21	PRODUCTO	1	\N	0.050	KGM
60	22	PRODUCTO	1	\N	0.050	KGM
61	22	PRODUCTO	11	\N	0.050	KGM
62	22	PRODUCTO	23	\N	0.050	KGM
63	22	PRODUCTO	93	\N	0.060	LTR
64	22	PRODUCTO	82	\N	0.500	C62
65	22	PRODUCTO	25	\N	0.060	LTR
66	23	PRODUCTO	95	\N	0.060	LTR
67	23	PRODUCTO	83	\N	1.000	C62
68	24	PRODUCTO	92	\N	0.090	LTR
69	24	PRODUCTO	1	\N	0.050	KGM
70	24	PRODUCTO	24	\N	0.030	LTR
71	24	PRODUCTO	2	\N	0.050	KGM
72	25	PRODUCTO	94	\N	0.060	LTR
73	25	PRODUCTO	26	\N	0.060	LTR
74	25	PRODUCTO	82	\N	0.500	C62
75	25	PRODUCTO	23	\N	0.050	KGM
76	26	PRODUCTO	1	\N	0.050	KGM
77	26	PRODUCTO	24	\N	0.060	LTR
78	26	PRODUCTO	22	\N	2.000	C62
79	26	PRODUCTO	94	\N	0.180	LTR
80	27	PRODUCTO	1	\N	0.050	KGM
81	27	PRODUCTO	24	\N	0.030	LTR
82	27	PRODUCTO	22	\N	1.000	C62
83	27	PRODUCTO	94	\N	0.090	LTR
84	28	PRODUCTO	92	\N	0.120	LTR
85	28	PRODUCTO	1	\N	0.050	KGM
86	28	PRODUCTO	77	\N	1.000	C62
87	29	PRODUCTO	1	\N	0.050	KGM
88	29	PRODUCTO	94	\N	0.120	LTR
89	29	PRODUCTO	75	\N	1.000	C62
90	30	PRODUCTO	1	\N	0.050	KGM
91	30	PRODUCTO	11	\N	0.050	KGM
92	30	PRODUCTO	23	\N	0.050	KGM
93	30	PRODUCTO	93	\N	0.120	LTR
94	30	PRODUCTO	88	\N	2.000	C62
95	31	PRODUCTO	1	\N	0.050	KGM
96	31	PRODUCTO	95	\N	0.120	LTR
97	31	PRODUCTO	89	\N	2.000	C62
98	31	PRODUCTO	23	\N	0.050	KGM
99	32	PRODUCTO	94	\N	0.120	LTR
100	32	PRODUCTO	26	\N	0.120	LTR
101	32	PRODUCTO	82	\N	1.000	C62
102	32	PRODUCTO	23	\N	0.050	KGM
103	33	PRODUCTO	1	\N	0.050	KGM
104	33	PRODUCTO	11	\N	0.050	KGM
105	33	PRODUCTO	23	\N	0.050	KGM
106	33	PRODUCTO	93	\N	0.120	LTR
107	33	PRODUCTO	82	\N	1.000	C62
108	33	PRODUCTO	25	\N	0.120	LTR
109	34	PRODUCTO	135	\N	1.000	C62
110	35	PRODUCTO	136	\N	1.000	C62
111	36	PRODUCTO	137	\N	1.000	C62
112	37	PRODUCTO	138	\N	1.000	C62
113	38	PRODUCTO	139	\N	1.000	C62
114	39	PRODUCTO	29	\N	1.000	C62
115	40	PRODUCTO	30	\N	1.000	C62
116	41	PRODUCTO	31	\N	1.000	C62
117	42	PRODUCTO	32	\N	1.000	C62
118	43	PRODUCTO	33	\N	1.000	C62
119	44	PRODUCTO	34	\N	1.000	C62
120	45	PRODUCTO	35	\N	1.000	C62
121	46	PRODUCTO	36	\N	1.000	C62
122	47	SUBPRODUCTO	\N	9	0.400	LTR
123	48	PRODUCTO	77	\N	1.000	C62
124	49	PRODUCTO	78	\N	1.000	C62
125	50	PRODUCTO	79	\N	1.000	C62
126	51	PRODUCTO	80	\N	1.000	C62
127	52	PRODUCTO	81	\N	1.000	C62
128	53	PRODUCTO	82	\N	1.000	C62
129	54	PRODUCTO	83	\N	1.000	C62
130	55	PRODUCTO	84	\N	1.000	C62
131	56	PRODUCTO	85	\N	1.000	C62
132	57	PRODUCTO	86	\N	1.000	C62
133	58	PRODUCTO	87	\N	1.000	C62
134	59	PRODUCTO	88	\N	1.000	C62
135	60	PRODUCTO	89	\N	1.000	C62
136	61	PRODUCTO	3	\N	0.200	KGM
137	61	PRODUCTO	11	\N	0.050	KGM
138	62	PRODUCTO	3	\N	0.200	KGM
139	62	PRODUCTO	11	\N	0.050	KGM
140	62	PRODUCTO	37	\N	0.060	KGM
141	63	PRODUCTO	3	\N	0.500	KGM
142	63	PRODUCTO	11	\N	0.050	KGM
143	63	PRODUCTO	37	\N	0.060	KGM
144	63	PRODUCTO	67	\N	1.000	C62
145	63	PRODUCTO	65	\N	1.000	C62
146	63	PRODUCTO	64	\N	1.000	C62
147	63	PRODUCTO	66	\N	1.000	C62
148	64	PRODUCTO	3	\N	0.200	KGM
149	64	PRODUCTO	11	\N	0.050	KGM
150	64	PRODUCTO	65	\N	1.000	C62
151	65	PRODUCTO	58	\N	6.000	C62
152	65	SUBPRODUCTO	\N	1	0.060	KGM
153	66	PRODUCTO	59	\N	6.000	C62
154	66	SUBPRODUCTO	\N	1	0.060	KGM
155	67	PRODUCTO	60	\N	6.000	C62
156	67	PRODUCTO	45	\N	0.060	KGM
157	68	PRODUCTO	12	\N	1.000	C62
158	68	PRODUCTO	44	\N	1.000	C62
159	68	SUBPRODUCTO	\N	2	0.060	KGM
160	69	PRODUCTO	12	\N	1.000	C62
161	69	PRODUCTO	37	\N	0.060	KGM
162	69	PRODUCTO	67	\N	1.000	C62
163	70	PRODUCTO	5	\N	0.060	KGM
164	70	PRODUCTO	4	\N	0.060	KGM
165	70	PRODUCTO	51	\N	1.000	C62
166	70	PRODUCTO	52	\N	1.000	C62
167	70	PRODUCTO	66	\N	1.000	C62
168	70	PRODUCTO	13	\N	2.000	C62
169	70	SUBPRODUCTO	\N	1	0.060	KGM
170	71	PRODUCTO	13	\N	3.000	C62
171	71	PRODUCTO	8	\N	0.200	KGM
172	71	PRODUCTO	15	\N	0.100	KGM
173	71	PRODUCTO	44	\N	1.000	C62
174	71	PRODUCTO	66	\N	0.500	C62
175	71	PRODUCTO	37	\N	0.060	KGM
176	71	PRODUCTO	53	\N	0.060	KGM
177	71	SUBPRODUCTO	\N	2	0.060	KGM
178	71	SUBPRODUCTO	\N	1	0.060	KGM
179	72	SUBPRODUCTO	\N	2	0.060	KGM
180	72	PRODUCTO	13	\N	3.000	C62
181	72	PRODUCTO	8	\N	0.600	KGM
182	72	PRODUCTO	66	\N	1.000	C62
183	72	PRODUCTO	37	\N	0.060	KGM
184	72	PRODUCTO	53	\N	0.060	KGM
185	73	PRODUCTO	14	\N	4.000	C62
186	73	PRODUCTO	8	\N	0.020	KGM
187	73	PRODUCTO	5	\N	0.020	KGM
188	73	PRODUCTO	55	\N	0.020	KGM
189	73	PRODUCTO	68	\N	4.000	C62
190	73	PRODUCTO	3	\N	0.200	KGM
191	73	PRODUCTO	11	\N	0.050	KGM
192	73	PRODUCTO	51	\N	1.000	C62
193	73	PRODUCTO	52	\N	1.000	C62
194	74	PRODUCTO	66	\N	1.000	C62
195	74	PRODUCTO	16	\N	1.000	C62
196	74	PRODUCTO	3	\N	0.200	KGM
197	74	PRODUCTO	11	\N	0.050	KGM
198	75	PRODUCTO	8	\N	0.600	KGM
199	75	PRODUCTO	5	\N	0.060	KGM
200	75	PRODUCTO	7	\N	0.100	KGM
201	75	PRODUCTO	9	\N	0.100	KGM
202	75	PRODUCTO	71	\N	2.000	C62
203	75	PRODUCTO	69	\N	1.000	C62
204	75	PRODUCTO	70	\N	1.000	C62
205	75	PRODUCTO	61	\N	10.000	C62
206	75	PRODUCTO	43	\N	0.060	KGM
207	75	PRODUCTO	11	\N	0.050	KGM
208	75	PRODUCTO	1	\N	0.050	KGM
209	75	PRODUCTO	45	\N	0.050	KGM
210	76	PRODUCTO	3	\N	1.000	KGM
211	76	PRODUCTO	11	\N	0.050	KGM
212	76	PRODUCTO	37	\N	0.120	KGM
213	76	PRODUCTO	67	\N	2.000	C62
214	76	PRODUCTO	65	\N	2.000	C62
215	76	PRODUCTO	64	\N	2.000	C62
216	76	PRODUCTO	66	\N	3.000	C62
217	76	PRODUCTO	59	\N	6.000	C62
218	76	SUBPRODUCTO	\N	1	0.060	KGM
219	76	PRODUCTO	45	\N	0.050	KGM
220	76	PRODUCTO	72	\N	6.000	C62
221	76	PRODUCTO	16	\N	1.000	C62
222	76	PRODUCTO	61	\N	8.000	C62
223	77	PRODUCTO	66	\N	1.000	C62
224	77	PRODUCTO	16	\N	1.000	C62
225	77	PRODUCTO	65	\N	0.500	C62
226	77	PRODUCTO	11	\N	0.050	KGM
227	77	PRODUCTO	72	\N	4.000	C62
228	77	PRODUCTO	5	\N	0.060	KGM
229	77	PRODUCTO	4	\N	0.060	KGM
230	77	PRODUCTO	51	\N	1.000	C62
231	77	PRODUCTO	52	\N	1.000	C62
232	77	PRODUCTO	13	\N	2.000	C62
233	77	SUBPRODUCTO	\N	1	0.060	KGM
234	77	PRODUCTO	12	\N	1.000	C62
235	77	PRODUCTO	37	\N	0.060	KGM
236	78	PRODUCTO	61	\N	8.000	C62
237	78	PRODUCTO	66	\N	1.000	C62
238	78	PRODUCTO	16	\N	1.000	C62
239	78	SUBPRODUCTO	\N	1	0.060	KGM
240	78	PRODUCTO	59	\N	6.000	C62
241	78	PRODUCTO	11	\N	0.050	KGM
242	78	PRODUCTO	3	\N	1.000	KGM
243	78	PRODUCTO	72	\N	4.000	C62
244	78	PRODUCTO	45	\N	0.050	KGM
245	79	PRODUCTO	72	\N	8.000	C62
246	79	PRODUCTO	16	\N	1.000	C62
247	79	PRODUCTO	11	\N	0.050	KGM
248	79	PRODUCTO	3	\N	0.300	KGM
249	80	PRODUCTO	72	\N	8.000	C62
250	81	PRODUCTO	66	\N	1.000	C62
251	81	PRODUCTO	16	\N	1.000	C62
252	82	PRODUCTO	66	\N	1.000	C62
253	82	PRODUCTO	8	\N	0.600	KGM
254	82	PRODUCTO	5	\N	0.060	KGM
255	82	PRODUCTO	9	\N	0.100	KGM
256	82	PRODUCTO	67	\N	1.000	C62
257	82	PRODUCTO	7	\N	0.100	KGM
258	82	PRODUCTO	54	\N	0.100	KGM
259	82	PRODUCTO	22	\N	1.000	C62
260	82	PRODUCTO	53	\N	0.060	KGM
261	83	PRODUCTO	140	\N	1.000	C62
262	83	PRODUCTO	73	\N	1.000	C62
263	83	PRODUCTO	67	\N	1.000	C62
264	83	PRODUCTO	52	\N	1.000	C62
265	83	PRODUCTO	8	\N	0.060	KGM
266	83	PRODUCTO	5	\N	0.060	KGM
267	83	PRODUCTO	11	\N	0.050	KGM
268	83	PRODUCTO	3	\N	0.300	KGM
269	84	PRODUCTO	140	\N	1.000	C62
270	84	PRODUCTO	73	\N	1.000	C62
271	84	PRODUCTO	8	\N	0.060	KGM
272	84	PRODUCTO	5	\N	0.060	KGM
273	84	PRODUCTO	55	\N	0.020	KGM
274	84	PRODUCTO	4	\N	0.060	KGM
275	84	PRODUCTO	11	\N	0.050	KGM
276	84	PRODUCTO	3	\N	0.300	KGM
277	85	PRODUCTO	140	\N	1.000	C62
278	85	PRODUCTO	73	\N	1.000	C62
279	85	PRODUCTO	8	\N	0.060	KGM
280	85	PRODUCTO	5	\N	0.060	KGM
281	85	PRODUCTO	11	\N	0.050	KGM
282	85	PRODUCTO	3	\N	0.300	KGM
283	85	PRODUCTO	61	\N	2.000	C62
284	85	PRODUCTO	45	\N	0.050	KGM
285	86	PRODUCTO	140	\N	1.000	C62
286	86	PRODUCTO	73	\N	1.000	C62
287	86	PRODUCTO	8	\N	0.060	KGM
288	86	PRODUCTO	5	\N	0.060	KGM
289	86	PRODUCTO	11	\N	0.050	KGM
290	86	PRODUCTO	3	\N	0.300	KGM
291	86	SUBPRODUCTO	\N	1	0.060	KGM
292	86	PRODUCTO	10	\N	0.060	KGM
293	86	PRODUCTO	53	\N	0.060	KGM
294	87	PRODUCTO	140	\N	1.000	C62
295	87	PRODUCTO	73	\N	1.000	C62
296	87	PRODUCTO	47	\N	0.060	KGM
297	87	PRODUCTO	52	\N	1.000	C62
298	87	PRODUCTO	10	\N	0.060	KGM
299	87	PRODUCTO	4	\N	0.060	KGM
300	87	PRODUCTO	11	\N	0.050	KGM
301	87	PRODUCTO	3	\N	0.300	KGM
302	88	PRODUCTO	140	\N	1.000	C62
303	88	PRODUCTO	73	\N	1.000	C62
304	88	PRODUCTO	8	\N	0.060	KGM
305	88	PRODUCTO	5	\N	0.060	KGM
306	88	PRODUCTO	11	\N	0.050	KGM
307	88	PRODUCTO	3	\N	0.300	KGM
308	88	PRODUCTO	66	\N	1.000	C62
309	88	PRODUCTO	16	\N	1.000	C62
310	88	PRODUCTO	67	\N	1.000	C62
311	88	PRODUCTO	52	\N	1.000	C62
312	88	PRODUCTO	37	\N	0.060	KGM
313	89	PRODUCTO	140	\N	1.000	C62
314	89	PRODUCTO	73	\N	2.000	C62
315	89	PRODUCTO	11	\N	0.050	KGM
316	89	PRODUCTO	3	\N	0.300	KGM
317	89	PRODUCTO	51	\N	2.000	C62
318	89	PRODUCTO	17	\N	0.100	KGM
319	90	PRODUCTO	140	\N	1.000	C62
320	90	PRODUCTO	66	\N	1.000	C62
321	90	PRODUCTO	8	\N	0.060	KGM
322	90	PRODUCTO	5	\N	0.060	KGM
323	90	PRODUCTO	11	\N	0.050	KGM
324	90	PRODUCTO	3	\N	0.300	KGM
325	90	PRODUCTO	52	\N	1.000	C62
326	90	PRODUCTO	67	\N	1.000	C62
327	90	PRODUCTO	16	\N	1.000	C62
328	91	PRODUCTO	66	\N	1.000	C62
329	91	PRODUCTO	67	\N	1.000	C62
330	91	PRODUCTO	56	\N	0.300	C62
331	91	PRODUCTO	57	\N	0.400	LTR
332	91	PRODUCTO	18	\N	0.200	KGM
333	92	PRODUCTO	56	\N	0.300	C62
334	92	PRODUCTO	57	\N	0.400	LTR
335	92	PRODUCTO	18	\N	0.200	KGM
336	92	PRODUCTO	66	\N	1.000	C62
337	92	PRODUCTO	16	\N	1.000	C62
338	92	PRODUCTO	40	\N	0.060	KGM
339	93	PRODUCTO	69	\N	1.000	C62
340	93	PRODUCTO	62	\N	1.000	C62
341	93	PRODUCTO	19	\N	0.200	KGM
342	93	PRODUCTO	48	\N	0.090	KGM
343	94	PRODUCTO	69	\N	1.000	C62
344	94	PRODUCTO	62	\N	1.000	C62
345	94	PRODUCTO	19	\N	0.200	KGM
346	95	PRODUCTO	62	\N	1.000	C62
347	95	PRODUCTO	19	\N	0.200	KGM
348	95	PRODUCTO	48	\N	0.090	KGM
349	95	PRODUCTO	63	\N	1.000	C62
350	96	PRODUCTO	19	\N	0.200	KGM
351	96	PRODUCTO	11	\N	0.050	KGM
352	96	PRODUCTO	3	\N	0.300	KGM
353	96	PRODUCTO	5	\N	0.060	KGM
354	96	PRODUCTO	4	\N	0.060	KGM
355	96	PRODUCTO	69	\N	1.000	C62
356	96	PRODUCTO	20	\N	0.030	LTR
357	96	PRODUCTO	50	\N	0.030	LTR
358	97	PRODUCTO	19	\N	0.200	KGM
359	97	PRODUCTO	11	\N	0.050	KGM
360	97	PRODUCTO	3	\N	0.300	KGM
361	97	PRODUCTO	43	\N	0.060	KGM
362	97	PRODUCTO	70	\N	1.000	C62
363	98	PRODUCTO	19	\N	0.200	KGM
364	98	PRODUCTO	11	\N	0.050	KGM
365	98	PRODUCTO	3	\N	0.300	KGM
366	98	PRODUCTO	5	\N	0.060	KGM
367	98	PRODUCTO	4	\N	0.060	KGM
368	98	PRODUCTO	74	\N	1.000	C62
369	98	PRODUCTO	20	\N	0.030	LTR
370	98	PRODUCTO	50	\N	0.030	LTR
371	99	PRODUCTO	19	\N	0.200	KGM
372	99	PRODUCTO	11	\N	0.050	KGM
373	99	PRODUCTO	3	\N	0.300	KGM
374	99	PRODUCTO	74	\N	1.000	C62
375	99	PRODUCTO	49	\N	0.090	KGM
376	100	PRODUCTO	101	\N	0.200	LTR
377	101	PRODUCTO	101	\N	0.400	LTR
378	102	PRODUCTO	101	\N	0.900	LTR
379	103	PRODUCTO	102	\N	0.200	LTR
380	104	PRODUCTO	102	\N	0.400	LTR
381	105	PRODUCTO	102	\N	0.900	LTR
382	106	PRODUCTO	103	\N	0.200	LTR
383	107	PRODUCTO	103	\N	0.400	LTR
384	108	PRODUCTO	103	\N	0.900	LTR
385	109	PRODUCTO	104	\N	0.200	LTR
386	110	PRODUCTO	104	\N	0.400	LTR
387	111	PRODUCTO	104	\N	0.900	LTR
388	112	PRODUCTO	105	\N	0.200	LTR
389	113	PRODUCTO	105	\N	0.400	LTR
390	114	PRODUCTO	105	\N	0.900	LTR
391	115	PRODUCTO	106	\N	0.200	LTR
392	116	PRODUCTO	106	\N	0.400	LTR
393	117	PRODUCTO	106	\N	0.900	LTR
394	118	PRODUCTO	107	\N	0.200	LTR
395	119	PRODUCTO	107	\N	0.400	LTR
396	120	PRODUCTO	107	\N	0.900	LTR
397	121	PRODUCTO	108	\N	0.200	LTR
398	122	PRODUCTO	108	\N	0.400	LTR
399	123	PRODUCTO	108	\N	0.900	LTR
400	124	PRODUCTO	109	\N	0.200	LTR
401	125	PRODUCTO	109	\N	0.400	LTR
402	126	PRODUCTO	109	\N	0.900	LTR
403	127	PRODUCTO	110	\N	0.200	LTR
404	128	PRODUCTO	110	\N	0.400	LTR
405	129	PRODUCTO	110	\N	0.900	LTR
406	130	PRODUCTO	111	\N	0.200	LTR
407	131	PRODUCTO	111	\N	0.400	LTR
408	132	PRODUCTO	111	\N	0.900	LTR
409	133	PRODUCTO	112	\N	0.200	LTR
410	134	PRODUCTO	112	\N	0.400	LTR
411	135	PRODUCTO	112	\N	0.900	LTR
412	136	PRODUCTO	113	\N	0.200	LTR
413	137	PRODUCTO	113	\N	0.400	LTR
414	138	PRODUCTO	113	\N	0.900	LTR
415	139	PRODUCTO	114	\N	0.200	LTR
416	140	PRODUCTO	114	\N	0.400	LTR
417	141	PRODUCTO	114	\N	0.900	LTR
418	142	PRODUCTO	115	\N	0.200	LTR
419	143	PRODUCTO	115	\N	0.400	LTR
420	144	PRODUCTO	115	\N	0.900	LTR
421	145	PRODUCTO	116	\N	0.200	LTR
422	146	PRODUCTO	116	\N	0.400	LTR
423	147	PRODUCTO	116	\N	0.900	LTR
424	148	PRODUCTO	117	\N	0.200	LTR
425	149	PRODUCTO	117	\N	0.400	LTR
426	150	PRODUCTO	117	\N	0.900	LTR
427	151	PRODUCTO	118	\N	0.200	LTR
428	152	PRODUCTO	118	\N	0.400	LTR
429	153	PRODUCTO	118	\N	0.900	LTR
430	154	PRODUCTO	119	\N	0.200	LTR
431	155	PRODUCTO	119	\N	0.400	LTR
432	156	PRODUCTO	119	\N	0.900	LTR
433	157	PRODUCTO	120	\N	0.200	LTR
434	158	PRODUCTO	120	\N	0.400	LTR
435	159	PRODUCTO	120	\N	0.900	LTR
436	160	PRODUCTO	121	\N	0.200	LTR
437	161	PRODUCTO	121	\N	0.400	LTR
438	162	PRODUCTO	121	\N	0.900	LTR
439	163	PRODUCTO	122	\N	0.200	LTR
440	164	PRODUCTO	122	\N	0.400	LTR
441	165	PRODUCTO	122	\N	0.900	LTR
442	166	PRODUCTO	123	\N	0.200	LTR
443	167	PRODUCTO	123	\N	0.400	LTR
444	168	PRODUCTO	123	\N	0.900	LTR
445	169	PRODUCTO	124	\N	0.200	LTR
446	170	PRODUCTO	124	\N	0.400	LTR
447	171	PRODUCTO	124	\N	0.900	LTR
448	172	PRODUCTO	125	\N	0.200	LTR
449	173	PRODUCTO	125	\N	0.400	LTR
450	174	PRODUCTO	125	\N	0.900	LTR
451	175	PRODUCTO	126	\N	0.200	LTR
452	176	PRODUCTO	126	\N	0.400	LTR
453	177	PRODUCTO	126	\N	0.900	LTR
454	178	PRODUCTO	127	\N	0.200	LTR
455	179	PRODUCTO	127	\N	0.400	LTR
456	180	PRODUCTO	127	\N	0.900	LTR
457	181	PRODUCTO	128	\N	0.200	LTR
458	182	PRODUCTO	128	\N	0.400	LTR
459	183	PRODUCTO	128	\N	0.900	LTR
460	184	PRODUCTO	129	\N	0.200	LTR
461	185	PRODUCTO	129	\N	0.400	LTR
462	186	PRODUCTO	129	\N	0.900	LTR
463	187	PRODUCTO	130	\N	0.200	LTR
464	188	PRODUCTO	130	\N	0.400	LTR
465	189	PRODUCTO	130	\N	0.900	LTR
466	190	PRODUCTO	131	\N	0.200	LTR
467	191	PRODUCTO	131	\N	0.400	LTR
468	192	PRODUCTO	131	\N	0.900	LTR
469	193	PRODUCTO	132	\N	0.200	LTR
470	194	PRODUCTO	132	\N	0.400	LTR
471	195	PRODUCTO	132	\N	0.900	LTR
472	196	PRODUCTO	133	\N	0.200	LTR
473	197	PRODUCTO	133	\N	0.400	LTR
474	198	PRODUCTO	133	\N	0.900	LTR
475	199	PRODUCTO	134	\N	0.300	LTR
476	199	PRODUCTO	23	\N	0.050	KGM
\.


--
-- Data for Name: salon_autorizacion_usada; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.salon_autorizacion_usada (clave, fecha) FROM stdin;
39152555-86a5-4454-b144-eabd0aea5b98	2026-09-23 13:54:37.106888-05
153d089e-354c-4570-b9fd-f235a99270b0	2026-09-25 13:29:19.173561-05
\.


--
-- Data for Name: salon_cobro; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.salon_cobro (id_cobro, id_local, id_usuario, mesa, clave, solicitud_hash, tipo, metodo, documento, cliente, total, comprobante, id_movimiento, creado_en, id_jornada) FROM stdin;
1	1	1	M01	647dc5ad-2a87-418c-8ccc-90aa3bd3d57d	cc44b70152abc3d00c85b165b2b49d977eae3b4193eb921eef475c305846a326	BOLETA	TARJETA			275.00	{"mesa": "M01", "tipo": "BOLETA", "local": "Miraflores", "total": 275.0, "fiscal": false, "lineas": [{"nombre": "Chimay Roja · 1 UNI", "precio": 42.0, "enviada": true, "cantidad": 3, "opciones": [], "comentario": "hielo aparte", "ids_lineas": [1], "id_presentacion": 44}, {"nombre": "Chimay Roja · 1 UNI", "precio": 42.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "", "ids_lineas": [2], "id_presentacion": 44}, {"nombre": "Westmalle Tripel · 1 UNI", "precio": 42.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "con hielo aparte", "ids_lineas": [3], "id_presentacion": 43}, {"nombre": "Delirium Tremens · 1 UNI", "precio": 49.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "", "ids_lineas": [4], "id_presentacion": 46}, {"nombre": "Estrella Damm - Sin alcohol · 1 UNI", "precio": 16.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "", "ids_lineas": [5], "id_presentacion": 39}], "metodo": "TARJETA", "cliente": "", "usuario": "Carlos", "documento": ""}	5	2026-09-26 05:19:00.318392-05	\N
2	1	1	M01	b12c12c0-f3a2-5034-9aed-c4c4d05ffa02	50d06891c4b173a9c00ac9f7f5e6bbd401cf64d0dae63aa64cd5661af82e263c	BOLETA	EFECTIVO			168.90	{"mesa": "M01", "tipo": "BOLETA", "local": "Miraflores", "total": 168.9, "fiscal": false, "lineas": [{"nombre": "174 IPA · 0.2 L", "precio": 12.0, "enviada": true, "cantidad": 8, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [7], "id_presentacion": 118}, {"nombre": "Agua con Gas · 1 UNI", "precio": 7.9, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [8], "id_presentacion": 53}, {"nombre": "Botella de 174 IPA · 1 UNI", "precio": 16.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [9], "id_presentacion": 34}, {"nombre": "Delirium Tremens · 1 UNI", "precio": 49.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [10], "id_presentacion": 46}], "metodo": "EFECTIVO", "prueba": "DEMO-MIRAFLORES-20260928", "cliente": "", "usuario": "Carlos", "documento": ""}	6	2026-09-29 20:30:00-05	8
3	1	1	M01	e72a767e-8fcf-592a-8d76-fa2f7a7ac01e	6ed6062db4a58d6c3a6dc81973797dbb577987a3516c61bb79d0efb8fc10191b	BOLETA	TARJETA			24.00	{"mesa": "M01", "tipo": "BOLETA", "local": "Miraflores", "total": 24.0, "fiscal": false, "lineas": [{"nombre": "2 Más · 0.2 L", "precio": 12.0, "enviada": true, "cantidad": 2, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [11], "id_presentacion": 124}], "metodo": "TARJETA", "prueba": "DEMO-MIRAFLORES-20260928", "cliente": "", "usuario": "Carlos", "documento": ""}	7	2026-09-30 01:15:00-05	8
4	1	1	M01	1bb5ed19-a950-5f9b-9ecc-52ad396f61c5	a4cd7bef513fe316fde1db0c509b35af84e25e3e950d21c5cba3fbc7e313ad59	BOLETA	EFECTIVO			188.80	{"mesa": "M01", "tipo": "BOLETA", "local": "Miraflores", "total": 188.8, "fiscal": false, "lineas": [{"nombre": "174 IPA · 0.2 L", "precio": 12.0, "enviada": true, "cantidad": 9, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [12], "id_presentacion": 118}, {"nombre": "Agua con Gas · 1 UNI", "precio": 7.9, "enviada": true, "cantidad": 2, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [13], "id_presentacion": 53}, {"nombre": "Botella de 174 IPA · 1 UNI", "precio": 16.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [14], "id_presentacion": 34}, {"nombre": "Delirium Tremens · 1 UNI", "precio": 49.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [15], "id_presentacion": 46}], "metodo": "EFECTIVO", "prueba": "DEMO-MIRAFLORES-20260928", "cliente": "", "usuario": "Carlos", "documento": ""}	8	2026-09-30 20:30:00-05	9
5	1	1	M01	ce1b04e1-2f16-5fa4-aaa8-4becc0a896a3	caf01d85e95b4778d39ab233b32bb4ee91233b65c8c67ce6ba38e6524cffe3c5	BOLETA	TARJETA			47.90	{"mesa": "M01", "tipo": "BOLETA", "local": "Miraflores", "total": 47.9, "fiscal": false, "lineas": [{"nombre": "2 Más · 0.2 L", "precio": 12.0, "enviada": true, "cantidad": 2, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [16], "id_presentacion": 124}, {"nombre": "Agua sin gas · 1 UNI", "precio": 7.9, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [17], "id_presentacion": 52}, {"nombre": "Botella de L.I.M.A. Pale Ale · 1 UNI", "precio": 16.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [18], "id_presentacion": 36}], "metodo": "TARJETA", "prueba": "DEMO-MIRAFLORES-20260928", "cliente": "", "usuario": "Carlos", "documento": ""}	9	2026-10-01 01:15:00-05	9
6	1	1	M01	c347d85b-f946-54fe-a3b8-e8f419159fd9	29b62f6c8634d8b451dc98d871e9ae495e45ceaeaf9ec4b98b46b0bacb208e9b	BOLETA	EFECTIVO			192.90	{"mesa": "M01", "tipo": "BOLETA", "local": "Miraflores", "total": 192.9, "fiscal": false, "lineas": [{"nombre": "174 IPA · 0.2 L", "precio": 12.0, "enviada": true, "cantidad": 10, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [19], "id_presentacion": 118}, {"nombre": "Agua con Gas · 1 UNI", "precio": 7.9, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [20], "id_presentacion": 53}, {"nombre": "Botella de 174 IPA · 1 UNI", "precio": 16.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [21], "id_presentacion": 34}, {"nombre": "Delirium Tremens · 1 UNI", "precio": 49.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [22], "id_presentacion": 46}], "metodo": "EFECTIVO", "prueba": "DEMO-MIRAFLORES-20260928", "cliente": "", "usuario": "Carlos", "documento": ""}	10	2026-10-01 20:30:00-05	10
7	1	1	M01	9ed0b193-f22f-55a7-a0eb-e2f881b092ac	22e17f888c543d894470c3b22474c3bd26549e26e468c8efb08049ff43ed0665	BOLETA	TARJETA			36.00	{"mesa": "M01", "tipo": "BOLETA", "local": "Miraflores", "total": 36.0, "fiscal": false, "lineas": [{"nombre": "2 Más · 0.2 L", "precio": 12.0, "enviada": true, "cantidad": 3, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [23], "id_presentacion": 124}], "metodo": "TARJETA", "prueba": "DEMO-MIRAFLORES-20260928", "cliente": "", "usuario": "Carlos", "documento": ""}	11	2026-10-02 01:15:00-05	10
8	1	1	M01	37d205f4-0b7d-5487-acbb-4109169de789	0e4314e803cd434ba72581ce598b122a040ec22d5a9c042cb1dca4680da4112c	BOLETA	EFECTIVO			204.90	{"mesa": "M01", "tipo": "BOLETA", "local": "Miraflores", "total": 204.9, "fiscal": false, "lineas": [{"nombre": "174 IPA · 0.2 L", "precio": 12.0, "enviada": true, "cantidad": 11, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [24], "id_presentacion": 118}, {"nombre": "Agua con Gas · 1 UNI", "precio": 7.9, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [25], "id_presentacion": 53}, {"nombre": "Botella de 174 IPA · 1 UNI", "precio": 16.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [26], "id_presentacion": 34}, {"nombre": "Delirium Tremens · 1 UNI", "precio": 49.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [27], "id_presentacion": 46}], "metodo": "EFECTIVO", "prueba": "DEMO-MIRAFLORES-20260928", "cliente": "", "usuario": "Carlos", "documento": ""}	12	2026-10-02 20:30:00-05	11
9	1	1	M01	c6a70ec0-9043-5749-82ea-0040e0f541f0	d84233ddc79eeaf2e12f30c1d37fa54ec8e0e345ffd15de8dbbb93f08f48d96e	BOLETA	TARJETA			47.90	{"mesa": "M01", "tipo": "BOLETA", "local": "Miraflores", "total": 47.9, "fiscal": false, "lineas": [{"nombre": "2 Más · 0.2 L", "precio": 12.0, "enviada": true, "cantidad": 2, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [28], "id_presentacion": 124}, {"nombre": "Agua sin gas · 1 UNI", "precio": 7.9, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [29], "id_presentacion": 52}, {"nombre": "Botella de L.I.M.A. Pale Ale · 1 UNI", "precio": 16.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [30], "id_presentacion": 36}], "metodo": "TARJETA", "prueba": "DEMO-MIRAFLORES-20260928", "cliente": "", "usuario": "Carlos", "documento": ""}	13	2026-10-03 01:15:00-05	11
10	1	1	M01	f08528f3-cf65-5d77-95c1-0d94f40ac139	dc8817687da1ade3d3b13b20fb5c6fcffd8aa7af89ef3cfc7f272333a4d33f76	BOLETA	EFECTIVO			216.90	{"mesa": "M01", "tipo": "BOLETA", "local": "Miraflores", "total": 216.9, "fiscal": false, "lineas": [{"nombre": "174 IPA · 0.2 L", "precio": 12.0, "enviada": true, "cantidad": 12, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [31], "id_presentacion": 118}, {"nombre": "Agua con Gas · 1 UNI", "precio": 7.9, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [32], "id_presentacion": 53}, {"nombre": "Botella de 174 IPA · 1 UNI", "precio": 16.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [33], "id_presentacion": 34}, {"nombre": "Delirium Tremens · 1 UNI", "precio": 49.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [34], "id_presentacion": 46}], "metodo": "EFECTIVO", "prueba": "DEMO-MIRAFLORES-20260928", "cliente": "", "usuario": "Carlos", "documento": ""}	14	2026-10-03 20:30:00-05	12
11	1	1	M01	074cb14a-a94e-50df-b9b7-981aa61013a8	8538ad5d9a499c06b7e282defbfb241c0ab3744dc980122564f6bf8d4807b145	BOLETA	TARJETA			12.00	{"mesa": "M01", "tipo": "BOLETA", "local": "Miraflores", "total": 12.0, "fiscal": false, "lineas": [{"nombre": "2 Más · 0.2 L", "precio": 12.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "DEMO-MIRAFLORES-20260928 · VENTA SIMULADA", "ids_lineas": [35], "id_presentacion": 124}], "metodo": "TARJETA", "prueba": "DEMO-MIRAFLORES-20260928", "cliente": "", "usuario": "Carlos", "documento": ""}	15	2026-10-04 01:15:00-05	12
12	1	1	M01	7e04cc15-71ed-413b-a8af-72399848b0bf	cde40057bad3f81f6bd36f3b3ac0c733cd122074d27d54b5a04e5c4b18ea2f98	BOLETA	EFECTIVO			236.00	{"mesa": "M01", "tipo": "BOLETA", "local": "Miraflores", "total": 236.0, "fiscal": false, "lineas": [{"nombre": "Chimay Roja · 1 UNI", "precio": 42.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "", "ids_lineas": [36], "id_presentacion": 44}, {"nombre": "Delirium Tremens · 1 UNI", "precio": 49.0, "enviada": true, "cantidad": 2, "opciones": [], "comentario": "", "ids_lineas": [37, 41], "id_presentacion": 46}, {"nombre": "Botella de Magic Quinua · 1 UNI", "precio": 16.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "", "ids_lineas": [38], "id_presentacion": 37}, {"nombre": "Botella de Red · 1 UNI", "precio": 16.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "", "ids_lineas": [39], "id_presentacion": 38}, {"nombre": "174 IPA · 0.2 L", "precio": 12.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "", "ids_lineas": [40], "id_presentacion": 118}, {"nombre": "Estrella Damm - Sin alcohol · 1 UNI", "precio": 16.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "", "ids_lineas": [42], "id_presentacion": 39}, {"nombre": "Lindermans Kriek · 1 UNI", "precio": 36.0, "enviada": true, "cantidad": 1, "opciones": [], "comentario": "", "ids_lineas": [43], "id_presentacion": 41}], "metodo": "EFECTIVO", "cliente": "", "usuario": "Carlos", "documento": ""}	16	2026-10-03 19:25:24.355475-05	13
\.


--
-- Data for Name: salon_cobro_pedido; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.salon_cobro_pedido (id_pedido, id_cobro) FROM stdin;
1	1
2	1
3	1
4	1
5	1
6	2
7	3
8	4
9	5
10	6
11	7
12	8
13	9
14	10
15	11
16	12
17	12
\.


--
-- Data for Name: salon_distribucion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.salon_distribucion (id_local, version, elementos) FROM stdin;
1	1	[{"x": 1.0111910471622712, "y": 0.6258725929922775, "alto": 12, "tipo": "barra", "ancho": 50, "codigo": "BARRA"}, {"x": 2.174260591526778, "y": 14.222979125214987, "alto": 8, "tipo": "puesto", "ancho": 7, "codigo": "B01"}, {"x": 11.417266187050359, "y": 14.330894007351702, "alto": 8, "tipo": "puesto", "ancho": 7, "codigo": "B02"}, {"x": 20.420463629096723, "y": 14.438808889488415, "alto": 8, "tipo": "puesto", "ancho": 7, "codigo": "B03"}, {"x": 30.78257394084732, "y": 14.76255353589856, "alto": 8, "tipo": "puesto", "ancho": 7, "codigo": "B04"}, {"x": 41.7841726618705, "y": 14.870468418035275, "alto": 8, "tipo": "puesto", "ancho": 7, "codigo": "B05"}, {"x": 57.72022382094325, "y": 3.970896705223757, "alto": 14, "tipo": "mesa", "ancho": 14, "codigo": "M01"}, {"x": 78.32214228617106, "y": 4.6183859980440465, "alto": 14, "tipo": "mesa", "ancho": 14, "codigo": "M02"}, {"x": 57.67705835331735, "y": 21.45310761137153, "alto": 14, "tipo": "mesa", "ancho": 14, "codigo": "M03"}, {"x": 78.11910471622701, "y": 21.884767139918388, "alto": 14, "tipo": "mesa", "ancho": 14, "codigo": "M04"}, {"x": 57.32054356514788, "y": 39.89191650085995, "alto": 14, "tipo": "mesa", "ancho": 14, "codigo": "M05"}, {"x": 78.16227018385291, "y": 39.13651232590294, "alto": 14, "tipo": "mesa", "ancho": 14, "codigo": "M06"}, {"x": 57.43725019984013, "y": 56.72663811418744, "alto": 14, "tipo": "mesa", "ancho": 14, "codigo": "M07"}, {"x": 78.35891286970424, "y": 56.61872323205071, "alto": 14, "tipo": "mesa", "ancho": 14, "codigo": "M08"}, {"x": 36.29736211031175, "y": 56.496172394024214, "alto": 14, "tipo": "mesa", "ancho": 14, "codigo": "M09"}, {"x": 36.11590727418066, "y": 39.66145078069673, "alto": 14, "tipo": "mesa", "ancho": 14, "codigo": "M10"}, {"x": 17.150279776179058, "y": 39.101102755201836, "alto": 14, "tipo": "mesa", "ancho": 14, "codigo": "M11"}, {"x": 17.47002398081535, "y": 57.122888072033184, "alto": 14, "tipo": "mesa", "ancho": 14, "codigo": "M12"}, {"x": 0.7993605115907275, "y": 39.20901763733855, "alto": 14, "tipo": "mesa", "ancho": 14, "codigo": "M13"}, {"x": 1.3229416466826538, "y": 57.014973189896466, "alto": 14, "tipo": "mesa", "ancho": 14, "codigo": "M14"}]
\.


--
-- Data for Name: salon_intentos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.salon_intentos (origen, inicio, intentos) FROM stdin;
12ca17b49af2289436f303e0166030a21e525d266e209267433801a8fd4071a0	2026-10-03 19:25:07.566031-05	2
\.


--
-- Data for Name: salon_linea_anulada; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.salon_linea_anulada (id_linea, id_responsable, fecha) FROM stdin;
6	1	2026-09-25 13:29:19.195677-05
\.


--
-- Data for Name: salon_pedido; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.salon_pedido (id_pedido, id_local, mesa, id_usuario, estado, version, creado_en, enviado_en, envio_clave, envio_hash) FROM stdin;
1	1	B01	1	ENVIADO	1	2026-09-23 11:14:16.230489-05	2026-09-23 11:14:16.283656-05	174300e0-147f-4323-add6-b473e0a2fdbd	42956b14f0a3f4906df40901788d1861ef1a3c864828a6dcbaf1bae8823e33ba
2	1	B01	1	ENVIADO	1	2026-09-23 12:31:23.89411-05	2026-09-23 12:31:23.962157-05	963ea38e-2a2e-4fe5-a400-39ab77148289	8cad3e2946ca9ac6b4cf38594ee8bc5d0bc224bae93463439abb38e7c7eeba01
3	1	B01	1	ENVIADO	1	2026-09-23 13:54:12.910396-05	2026-09-23 13:54:12.97063-05	fa3f2629-1ef2-4c22-86a7-b6ba0a53c036	9317709260bbd8da3f01a1f8d2d21e61836c83198dfa9dabc3b0c0e50971a84f
4	1	M01	1	ENVIADO	1	2026-09-23 23:03:36.895855-05	2026-09-23 23:03:36.983928-05	08094a89-0449-47a9-9443-388a12507d0e	5b760fcaa58f4b74b21cfe7ae9c1bf3a0e6ce0e7c11e63b1d5bc0a1ca6e73614
5	1	M01	1	ENVIADO	1	2026-09-25 13:29:00.70023-05	2026-09-25 13:29:00.847621-05	a9dd78f7-fb28-4cb2-ab36-7f4d74a88820	13aed81e6dde370e817ad0aa49b69e32adb352bf31a1f1f4a49036a1c0139310
6	1	M01	1	ENVIADO	1	2026-09-29 20:30:00-05	2026-09-29 20:30:00-05	b12c12c0-f3a2-5034-9aed-c4c4d05ffa02	50d06891c4b173a9c00ac9f7f5e6bbd401cf64d0dae63aa64cd5661af82e263c
7	1	M01	1	ENVIADO	1	2026-09-30 01:15:00-05	2026-09-30 01:15:00-05	e72a767e-8fcf-592a-8d76-fa2f7a7ac01e	6ed6062db4a58d6c3a6dc81973797dbb577987a3516c61bb79d0efb8fc10191b
8	1	M01	1	ENVIADO	1	2026-09-30 20:30:00-05	2026-09-30 20:30:00-05	1bb5ed19-a950-5f9b-9ecc-52ad396f61c5	a4cd7bef513fe316fde1db0c509b35af84e25e3e950d21c5cba3fbc7e313ad59
9	1	M01	1	ENVIADO	1	2026-10-01 01:15:00-05	2026-10-01 01:15:00-05	ce1b04e1-2f16-5fa4-aaa8-4becc0a896a3	caf01d85e95b4778d39ab233b32bb4ee91233b65c8c67ce6ba38e6524cffe3c5
10	1	M01	1	ENVIADO	1	2026-10-01 20:30:00-05	2026-10-01 20:30:00-05	c347d85b-f946-54fe-a3b8-e8f419159fd9	29b62f6c8634d8b451dc98d871e9ae495e45ceaeaf9ec4b98b46b0bacb208e9b
11	1	M01	1	ENVIADO	1	2026-10-02 01:15:00-05	2026-10-02 01:15:00-05	9ed0b193-f22f-55a7-a0eb-e2f881b092ac	22e17f888c543d894470c3b22474c3bd26549e26e468c8efb08049ff43ed0665
12	1	M01	1	ENVIADO	1	2026-10-02 20:30:00-05	2026-10-02 20:30:00-05	37d205f4-0b7d-5487-acbb-4109169de789	0e4314e803cd434ba72581ce598b122a040ec22d5a9c042cb1dca4680da4112c
13	1	M01	1	ENVIADO	1	2026-10-03 01:15:00-05	2026-10-03 01:15:00-05	c6a70ec0-9043-5749-82ea-0040e0f541f0	d84233ddc79eeaf2e12f30c1d37fa54ec8e0e345ffd15de8dbbb93f08f48d96e
14	1	M01	1	ENVIADO	1	2026-10-03 20:30:00-05	2026-10-03 20:30:00-05	f08528f3-cf65-5d77-95c1-0d94f40ac139	dc8817687da1ade3d3b13b20fb5c6fcffd8aa7af89ef3cfc7f272333a4d33f76
15	1	M01	1	ENVIADO	1	2026-10-04 01:15:00-05	2026-10-04 01:15:00-05	074cb14a-a94e-50df-b9b7-981aa61013a8	8538ad5d9a499c06b7e282defbfb241c0ab3744dc980122564f6bf8d4807b145
16	1	M01	1	ENVIADO	1	2026-09-29 00:02:22.590407-05	2026-09-29 00:02:22.863212-05	162d4282-169d-4f16-8307-0bdf44d72b83	d25bcb4aa45099010864353f1fea1a2ef582f0a7aa7cd36d67246b1fd9fe17f0
17	1	M01	1	ENVIADO	1	2026-10-03 19:25:14.760129-05	2026-10-03 19:25:14.858988-05	044f16b4-7fb8-480e-b31f-d0cd138a875a	9dc356f43f7a16f42bc5c1b19abf3ab4a030a7273caa24c7e8d2440b8f296cad
18	3	M04	1	ENVIADO	1	2026-10-03 19:25:58.796537-05	2026-10-03 19:25:58.832178-05	af9f3547-f255-46dc-8221-ed760897699d	b113e57a2b20f92b08e9664248e6c98cff9fe8cfa305c4c9b081124dbb1c716f
\.


--
-- Data for Name: salon_pedido_asignacion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.salon_pedido_asignacion (id_pedido, mesa, id_usuario) FROM stdin;
1	M01	1
2	M01	1
3	M01	1
\.


--
-- Data for Name: salon_pedido_linea; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.salon_pedido_linea (id_linea, id_pedido, posicion, id_presentacion, nombre, precio, cantidad, comentario, opciones) FROM stdin;
1	1	0	44	Chimay Roja · 1.000 UNI	42.00	3	hielo aparte	[]
2	2	0	44	Chimay Roja · 1.000 UNI	42.00	1		[]
3	3	0	43	Westmalle Tripel · 1.000 UNI	42.00	1	con hielo aparte	[]
4	4	0	46	Delirium Tremens · 1.000 UNI	49.00	1		[]
5	4	1	39	Estrella Damm - Sin alcohol · 1.000 UNI	16.00	1		[]
6	5	0	53	Agua con Gas · 1.000 UNI	7.90	2	hielo aparte	[]
7	6	0	118	174 IPA · 0.2 L	12.00	8	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
8	6	1	53	Agua con Gas · 1 UNI	7.90	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
9	6	2	34	Botella de 174 IPA · 1 UNI	16.00	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
10	6	3	46	Delirium Tremens · 1 UNI	49.00	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
11	7	0	124	2 Más · 0.2 L	12.00	2	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
12	8	0	118	174 IPA · 0.2 L	12.00	9	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
13	8	1	53	Agua con Gas · 1 UNI	7.90	2	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
14	8	2	34	Botella de 174 IPA · 1 UNI	16.00	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
15	8	3	46	Delirium Tremens · 1 UNI	49.00	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
16	9	0	124	2 Más · 0.2 L	12.00	2	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
17	9	1	52	Agua sin gas · 1 UNI	7.90	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
18	9	2	36	Botella de L.I.M.A. Pale Ale · 1 UNI	16.00	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
19	10	0	118	174 IPA · 0.2 L	12.00	10	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
20	10	1	53	Agua con Gas · 1 UNI	7.90	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
21	10	2	34	Botella de 174 IPA · 1 UNI	16.00	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
22	10	3	46	Delirium Tremens · 1 UNI	49.00	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
23	11	0	124	2 Más · 0.2 L	12.00	3	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
24	12	0	118	174 IPA · 0.2 L	12.00	11	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
25	12	1	53	Agua con Gas · 1 UNI	7.90	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
26	12	2	34	Botella de 174 IPA · 1 UNI	16.00	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
27	12	3	46	Delirium Tremens · 1 UNI	49.00	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
28	13	0	124	2 Más · 0.2 L	12.00	2	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
29	13	1	52	Agua sin gas · 1 UNI	7.90	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
30	13	2	36	Botella de L.I.M.A. Pale Ale · 1 UNI	16.00	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
31	14	0	118	174 IPA · 0.2 L	12.00	12	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
32	14	1	53	Agua con Gas · 1 UNI	7.90	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
33	14	2	34	Botella de 174 IPA · 1 UNI	16.00	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
34	14	3	46	Delirium Tremens · 1 UNI	49.00	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
35	15	0	124	2 Más · 0.2 L	12.00	1	DEMO-MIRAFLORES-20260928 · VENTA SIMULADA	[]
36	16	0	44	Chimay Roja · 1 UNI	42.00	1		[]
37	16	1	46	Delirium Tremens · 1 UNI	49.00	1		[]
38	16	2	37	Botella de Magic Quinua · 1 UNI	16.00	1		[]
39	16	3	38	Botella de Red · 1 UNI	16.00	1		[]
40	16	4	118	174 IPA · 0.2 L	12.00	1		[]
41	17	0	46	Delirium Tremens · 1 UNI	49.00	1		[]
42	17	1	39	Estrella Damm - Sin alcohol · 1 UNI	16.00	1		[]
43	17	2	41	Lindermans Kriek · 1 UNI	36.00	1		[]
44	18	0	41	Lindermans Kriek · 1 UNI	36.00	1		[]
45	18	1	39	Estrella Damm - Sin alcohol · 1 UNI	16.00	1		[]
46	18	2	46	Delirium Tremens · 1 UNI	49.00	1		[]
47	18	3	36	Botella de L.I.M.A. Pale Ale · 1 UNI	16.00	1		[]
48	18	4	37	Botella de Magic Quinua · 1 UNI	16.00	1		[]
\.


--
-- Data for Name: subproducto; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.subproducto (id_subproducto, codigo, nombre, rendimiento, unidad, instruccion, activo) FROM stdin;
1	SP-001	Guacamole	1.000	KGM	\N	t
2	SP-002	Pico de gallo	1.000	KGM	\N	t
3	SP-003	Ensalada parrillera	1.000	PORCION	\N	t
4	SP-004	Ensaladita	1.000	PORCION	\N	t
5	SP-005	Nachos (pequeño)	1.000	PORCION	\N	t
6	SP-006	Tequeños (pequeño)	1.000	PORCION	\N	t
7	SP-007	Cheese Fries (pequeño)	1.000	PORCION	\N	t
9	SP-009	Chicha	12.000	LTR	Mezclar 2 L de esencia con 0.05 Kg de limón y completar con agua filtrada hasta alcanzar 12 L.	t
8	SP-008	Aros de cebolla (pequeño)	1.000	PORCION		t
\.


--
-- Data for Name: subproducto_detalle; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.subproducto_detalle (id_subproducto_detalle, id_subproducto, id_producto, cantidad, unidad) FROM stdin;
1	1	4	0.150	KGM
2	1	5	0.150	KGM
3	1	7	0.650	KGM
4	1	1	0.040	KGM
5	1	11	0.010	KGM
6	2	4	0.400	KGM
7	2	5	0.450	KGM
8	2	1	0.140	KGM
9	2	11	0.010	KGM
10	3	8	0.080	KGM
11	3	9	0.060	KGM
12	3	5	0.060	KGM
13	3	7	0.050	KGM
14	4	8	0.100	KGM
15	4	9	0.060	KGM
16	4	5	0.060	KGM
17	5	12	1.000	C62
18	5	37	0.080	KGM
19	5	67	1.000	C62
20	6	59	2.000	C62
21	7	3	0.250	KGM
22	7	37	0.080	KGM
24	9	28	2.000	LTR
25	9	1	0.050	KGM
27	8	61	5.000	C62
\.


--
-- Data for Name: unidad_medida; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.unidad_medida (codigo, nombre, simbolo, dimension, codigo_unece, codigo_base, factor_a_base) FROM stdin;
KGM	Kilogramo	kg	MASA	KGM	KGM	1.000000
GRM	Gramo	g	MASA	GRM	KGM	0.001000
LTR	Litro	L	VOLUMEN	LTR	LTR	1.000000
MLT	Mililitro	mL	VOLUMEN	MLT	LTR	0.001000
C62	Unidad	unidad	CONTEO	C62	C62	1.000000
PORCION	Porción	porción	CONTEO	\N	PORCION	1.000000
\.


--
-- Data for Name: usuario; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.usuario (id_usuario, dni, nombres, apellido_paterno, apellido_materno, celular, correo_electronico, clave, usuario_creacion, fecha_creacion, usuario_modificacion, fecha_modificacion, estado_registro, id_puesto_laboral) FROM stdin;
3	90157845	Roberto	Díaz	Guerrero	987456100	rdiaz@barbarian.pe	$2a$06$rvodE/9MAg/aCFak4vavIucUltGNnXAMJu4ifzE3maKjSbzc0ftrO	2	2026-08-28	1	2026-09-21	1	\N
2	56879826	José	Ríos	Martínez	923876122	jrios@barbarian.pe	$2a$06$9lv0HYEgkXwQM2kI8MHJvuBMaHr10B11KseQhW.7CFlWoC7S/fU4u	1	2026-08-28	1	2026-09-23	1	\N
4	74215689	María	López	Fernández	956321478	mlopez@barbarian.pe	$2a$06$GKwMSwWNHkddLDGM5e1pxuz0oq9z5YjCcB1.HX6JU8tRPUdZVoxey	2	2026-08-28	1	2026-09-23	1	1
1	90999999	Carlos	Rodríguez	Torres	987654321	crodriguez@barbarian.pe	$2a$06$fsqMVRxBP3Ri77a92OgYuOY9UDURvAP4ShCcf9m64edadmHPm6ogq	\N	2026-08-28	1	2026-09-25	1	1
\.


--
-- Data for Name: usuario_local; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.usuario_local (id_usuario_local, id_usuario, id_local, estado_registro, fecha_asignacion, usuario_asignacion, fecha_modificacion, usuario_modificacion) FROM stdin;
4	3	1	1	2026-09-22 11:05:17.075752	1	\N	\N
9	3	3	1	2026-09-22 11:05:25.72454	1	\N	\N
3	2	1	1	2026-09-22 11:05:17.075752	1	2026-09-23 08:23:15.605701	1
1	4	1	1	2026-09-22 11:05:17.075752	1	2026-09-23 08:23:24.974784	1
2	1	1	1	2026-09-22 11:05:17.075752	1	2026-09-25 13:32:08.45004	1
11	1	2	1	2026-09-22 11:05:33.494586	1	2026-09-25 13:32:08.45004	1
12	1	3	1	2026-09-22 11:05:33.494586	1	2026-09-25 13:32:08.45004	1
13	1	4	1	2026-09-22 11:05:33.494586	1	2026-09-25 13:32:08.45004	1
\.


--
-- Data for Name: usuario_perfiles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.usuario_perfiles (id_usuario, id_perfil, usuario_asignacion, fecha_asignacion, usuario_modificacion, fecha_modificacion, estado_registro) FROM stdin;
3	3	2	2026-08-28	1	2026-09-21	1
3	4	1	2026-09-21	\N	\N	1
2	2	1	2026-08-28	1	2026-09-23	1
2	3	1	2026-09-21	1	2026-09-23	1
2	4	1	2026-09-21	1	2026-09-23	1
4	4	2	2026-08-28	1	2026-09-23	1
1	1	1	2026-08-28	1	2026-09-25	1
1	2	1	2026-09-20	1	2026-09-25	1
1	3	1	2026-09-20	1	2026-09-25	1
1	4	1	2026-09-20	1	2026-09-25	1
\.


--
-- Data for Name: usuario_pin_salon; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.usuario_pin_salon (id_usuario, pin_hash, version, fallos, bloqueado_hasta, actualizado_en) FROM stdin;
2	scrypt:32768:8:1$Mqkz73d801yGD05x$1125c700b47858d32b6918599032df2ce8501ca7e3494e3a889e4c19cd07190ddfe5d3a2c5445a8d48e355fd5b5e342ec0bd2bfa738994dcc0c1ab8e482cab55	1	0	\N	2026-09-23 08:23:15.605701-05
4	scrypt:32768:8:1$W9yYaOLg1XuZCpRK$c64b11854efaa1d1a5cc5fd805c012aab85a0728749a80a4ce82e4804f819575eec4ca2f95d15ebe64d1d2a2bf095eca9722c948af55873e7f1f3c55f1421434	1	0	\N	2026-09-23 08:23:24.974784-05
1	scrypt:32768:8:1$Av9fAAY7L6RHfoNO$d365be3da09e471c65433735aff225a1c36747f0ffa72a0e07ab85f3f8f53530d91728c6bc01340117c6d929f6a54002807d41202aef8fbf054db1d50716d052	1	0	\N	2026-09-23 08:23:05.312809-05
\.


--
-- Data for Name: usuario_puestos_laborales; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.usuario_puestos_laborales (id_usuario, id_puesto_laboral, usuario_asignacion, fecha_asignacion, usuario_modificacion, fecha_modificacion, estado_registro) FROM stdin;
3	1	1	2026-09-21 13:26:38.537874	\N	\N	1
3	2	1	2026-09-21 13:26:38.537874	\N	\N	1
3	3	1	2026-09-21 13:26:38.537874	\N	\N	1
2	1	1	2026-09-21 13:26:14.155984	1	2026-09-23 00:00:00	1
2	2	1	2026-09-21 13:26:14.155984	1	2026-09-23 00:00:00	1
2	3	1	2026-09-21 13:26:14.155984	1	2026-09-23 00:00:00	1
4	1	1	2026-09-21 10:46:43.442381	1	2026-09-23 00:00:00	1
1	1	1	2026-09-21 10:46:43.442381	1	2026-09-25 00:00:00	1
1	2	1	2026-09-21 13:18:51.395538	1	2026-09-25 00:00:00	1
1	3	1	2026-09-21 13:18:51.395538	1	2026-09-25 00:00:00	1
\.


--
-- Name: actividad_usuario_id_actividad_usuario_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.actividad_usuario_id_actividad_usuario_seq', 378, true);


--
-- Name: auditoria_cambio_id_auditoria_cambio_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditoria_cambio_id_auditoria_cambio_seq', 24, true);


--
-- Name: categoria_carta_id_categoria_carta_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.categoria_carta_id_categoria_carta_seq', 8, true);


--
-- Name: categoria_producto_id_categoria_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.categoria_producto_id_categoria_seq', 11, true);


--
-- Name: factura_recepcion_detalle_his_id_factura_recepcion_detalle__seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.factura_recepcion_detalle_his_id_factura_recepcion_detalle__seq', 1, true);


--
-- Name: factura_recepcion_detalle_id_factura_recepcion_detalle_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.factura_recepcion_detalle_id_factura_recepcion_detalle_seq', 141, true);


--
-- Name: factura_recepcion_historial_id_factura_recepcion_historial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.factura_recepcion_historial_id_factura_recepcion_historial_seq', 1, true);


--
-- Name: factura_recepcion_id_factura_recepcion_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.factura_recepcion_id_factura_recepcion_seq', 10, true);


--
-- Name: grupo_salsa_id_grupo_salsa_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.grupo_salsa_id_grupo_salsa_seq', 7, true);


--
-- Name: grupo_salsa_opcion_id_grupo_salsa_opcion_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.grupo_salsa_opcion_id_grupo_salsa_opcion_seq', 35, true);


--
-- Name: inventario_cierre_correccion__id_inventario_cierre_correcci_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.inventario_cierre_correccion__id_inventario_cierre_correcci_seq', 1, false);


--
-- Name: inventario_cierre_correccion_id_inventario_cierre_correccio_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.inventario_cierre_correccion_id_inventario_cierre_correccio_seq', 1, false);


--
-- Name: inventario_cierre_detalle_id_inventario_cierre_detalle_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.inventario_cierre_detalle_id_inventario_cierre_detalle_seq', 1260, true);


--
-- Name: inventario_cierre_id_inventario_cierre_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.inventario_cierre_id_inventario_cierre_seq', 11, true);


--
-- Name: inventario_conteo_historial_id_historial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.inventario_conteo_historial_id_historial_seq', 280, true);


--
-- Name: inventario_evento_id_evento_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.inventario_evento_id_evento_seq', 38, true);


--
-- Name: inventario_jornada_id_jornada_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.inventario_jornada_id_jornada_seq', 13, true);


--
-- Name: inventario_ronda_id_ronda_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.inventario_ronda_id_ronda_seq', 1, true);


--
-- Name: item_carta_id_item_carta_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.item_carta_id_item_carta_seq', 133, true);


--
-- Name: local_id_local_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.local_id_local_seq', 4, true);


--
-- Name: menaje_id_menaje_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.menaje_id_menaje_seq', 17, true);


--
-- Name: movimiento_inventario_detalle_id_movimiento_inventario_deta_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.movimiento_inventario_detalle_id_movimiento_inventario_deta_seq', 46, true);


--
-- Name: movimiento_inventario_id_movimiento_inventario_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.movimiento_inventario_id_movimiento_inventario_seq', 16, true);


--
-- Name: opcion_menu_id_opcion_menu_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.opcion_menu_id_opcion_menu_seq', 38, true);


--
-- Name: orden_compra_detalle_id_orden_compra_detalle_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.orden_compra_detalle_id_orden_compra_detalle_seq', 142, true);


--
-- Name: orden_compra_estado_historial_id_orden_compra_estado_histor_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.orden_compra_estado_historial_id_orden_compra_estado_histor_seq', 1, false);


--
-- Name: orden_compra_id_orden_compra_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.orden_compra_id_orden_compra_seq', 2, true);


--
-- Name: perfiles_id_perfil_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.perfiles_id_perfil_seq', 4, true);


--
-- Name: presentacion_venta_id_presentacion_venta_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.presentacion_venta_id_presentacion_venta_seq', 199, true);


--
-- Name: producto_categoria_historial_id_producto_categoria_historia_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.producto_categoria_historial_id_producto_categoria_historia_seq', 1, false);


--
-- Name: producto_id_producto_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.producto_id_producto_seq', 143, true);


--
-- Name: producto_proveedor_historial_id_producto_proveedor_historia_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.producto_proveedor_historial_id_producto_proveedor_historia_seq', 1, false);


--
-- Name: promocion_grupo_id_promocion_grupo_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.promocion_grupo_id_promocion_grupo_seq', 4, true);


--
-- Name: promocion_id_promocion_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.promocion_id_promocion_seq', 4, true);


--
-- Name: promocion_opcion_id_promocion_opcion_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.promocion_opcion_id_promocion_opcion_seq', 9, true);


--
-- Name: proveedor_id_proveedor_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.proveedor_id_proveedor_seq', 12, true);


--
-- Name: puesto_laboral_id_puesto_laboral_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.puesto_laboral_id_puesto_laboral_seq', 3, true);


--
-- Name: receta_detalle_id_receta_detalle_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.receta_detalle_id_receta_detalle_seq', 476, true);


--
-- Name: receta_id_receta_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.receta_id_receta_seq', 199, true);


--
-- Name: salon_cobro_id_cobro_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.salon_cobro_id_cobro_seq', 12, true);


--
-- Name: salon_pedido_id_pedido_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.salon_pedido_id_pedido_seq', 18, true);


--
-- Name: salon_pedido_linea_id_linea_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.salon_pedido_linea_id_linea_seq', 48, true);


--
-- Name: subproducto_detalle_id_subproducto_detalle_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.subproducto_detalle_id_subproducto_detalle_seq', 27, true);


--
-- Name: subproducto_id_subproducto_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.subproducto_id_subproducto_seq', 9, true);


--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.usuario_id_usuario_seq', 4, true);


--
-- Name: usuario_local_id_usuario_local_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.usuario_local_id_usuario_local_seq', 28, true);


--
-- Name: actividad_usuario actividad_usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actividad_usuario
    ADD CONSTRAINT actividad_usuario_pkey PRIMARY KEY (id_actividad_usuario);


--
-- Name: asistente_ia_borrador asistente_ia_borrador_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistente_ia_borrador
    ADD CONSTRAINT asistente_ia_borrador_pkey PRIMARY KEY (id);


--
-- Name: auditoria_cambio auditoria_cambio_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_cambio
    ADD CONSTRAINT auditoria_cambio_pkey PRIMARY KEY (id_auditoria_cambio);


--
-- Name: factura_recepcion_detalle factura_recepcion_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle
    ADD CONSTRAINT factura_recepcion_detalle_pkey PRIMARY KEY (id_factura_recepcion_detalle);


--
-- Name: factura_recepcion factura_recepcion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion
    ADD CONSTRAINT factura_recepcion_pkey PRIMARY KEY (id_factura_recepcion);


--
-- Name: grupo_salsa grupo_salsa_id_presentacion_venta_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa
    ADD CONSTRAINT grupo_salsa_id_presentacion_venta_key UNIQUE (id_presentacion_venta);


--
-- Name: grupo_salsa_opcion grupo_salsa_opcion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa_opcion
    ADD CONSTRAINT grupo_salsa_opcion_pkey PRIMARY KEY (id_grupo_salsa_opcion);


--
-- Name: grupo_salsa grupo_salsa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa
    ADD CONSTRAINT grupo_salsa_pkey PRIMARY KEY (id_grupo_salsa);


--
-- Name: inventario_asignacion_puesto inventario_asignacion_puesto_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_asignacion_puesto
    ADD CONSTRAINT inventario_asignacion_puesto_pkey PRIMARY KEY (id_local, id_producto);


--
-- Name: inventario_cierre_detalle inventario_cierre_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_detalle
    ADD CONSTRAINT inventario_cierre_detalle_pkey PRIMARY KEY (id_inventario_cierre_detalle);


--
-- Name: inventario_cierre inventario_cierre_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre
    ADD CONSTRAINT inventario_cierre_pkey PRIMARY KEY (id_inventario_cierre);


--
-- Name: inventario_conteo_historial inventario_conteo_historial_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo_historial
    ADD CONSTRAINT inventario_conteo_historial_pkey PRIMARY KEY (id_historial);


--
-- Name: inventario_conteo inventario_conteo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_pkey PRIMARY KEY (id_ronda, id_producto);


--
-- Name: inventario_evento inventario_evento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_evento
    ADD CONSTRAINT inventario_evento_pkey PRIMARY KEY (id_evento);


--
-- Name: inventario_jornada inventario_jornada_id_local_fecha_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada
    ADD CONSTRAINT inventario_jornada_id_local_fecha_key UNIQUE (id_local, fecha);


--
-- Name: inventario_jornada_inicio inventario_jornada_inicio_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada_inicio
    ADD CONSTRAINT inventario_jornada_inicio_pkey PRIMARY KEY (id_jornada, id_producto);


--
-- Name: inventario_jornada inventario_jornada_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada
    ADD CONSTRAINT inventario_jornada_pkey PRIMARY KEY (id_jornada);


--
-- Name: inventario_ronda inventario_ronda_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_ronda
    ADD CONSTRAINT inventario_ronda_pkey PRIMARY KEY (id_ronda);


--
-- Name: inventario_saldo_inicial inventario_saldo_inicial_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_saldo_inicial
    ADD CONSTRAINT inventario_saldo_inicial_pkey PRIMARY KEY (id_local, id_producto);


--
-- Name: local local_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.local
    ADD CONSTRAINT local_codigo_key UNIQUE (codigo);


--
-- Name: local local_nombre_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.local
    ADD CONSTRAINT local_nombre_key UNIQUE (nombre);


--
-- Name: local local_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.local
    ADD CONSTRAINT local_pkey PRIMARY KEY (id_local);


--
-- Name: movimiento_inventario movimiento_inventario_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario
    ADD CONSTRAINT movimiento_inventario_codigo_key UNIQUE (codigo);


--
-- Name: movimiento_inventario_detalle movimiento_inventario_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario_detalle
    ADD CONSTRAINT movimiento_inventario_detalle_pkey PRIMARY KEY (id_movimiento_inventario_detalle);


--
-- Name: movimiento_inventario movimiento_inventario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario
    ADD CONSTRAINT movimiento_inventario_pkey PRIMARY KEY (id_movimiento_inventario);


--
-- Name: movimiento_reintegro movimiento_reintegro_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_reintegro
    ADD CONSTRAINT movimiento_reintegro_pkey PRIMARY KEY (id_movimiento);


--
-- Name: movimiento_seguimiento movimiento_seguimiento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_seguimiento
    ADD CONSTRAINT movimiento_seguimiento_pkey PRIMARY KEY (id_movimiento);


--
-- Name: opcion_menu opcion_menu_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opcion_menu
    ADD CONSTRAINT opcion_menu_pkey PRIMARY KEY (id_opcion_menu);


--
-- Name: orden_compra orden_compra_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra
    ADD CONSTRAINT orden_compra_codigo_key UNIQUE (codigo);


--
-- Name: orden_compra_detalle orden_compra_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_detalle
    ADD CONSTRAINT orden_compra_detalle_pkey PRIMARY KEY (id_orden_compra_detalle);


--
-- Name: orden_compra orden_compra_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra
    ADD CONSTRAINT orden_compra_pkey PRIMARY KEY (id_orden_compra);


--
-- Name: perfiles perfiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfiles
    ADD CONSTRAINT perfiles_pkey PRIMARY KEY (id_perfil);


--
-- Name: categoria_carta pk_categoria_carta; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categoria_carta
    ADD CONSTRAINT pk_categoria_carta PRIMARY KEY (id_categoria_carta);


--
-- Name: categoria_producto pk_categoria_producto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categoria_producto
    ADD CONSTRAINT pk_categoria_producto PRIMARY KEY (id_categoria);


--
-- Name: inventario_cierre_correccion_detalle pk_correccion_detalle; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_correccion_detalle
    ADD CONSTRAINT pk_correccion_detalle PRIMARY KEY (id_inventario_cierre_correccion_detalle);


--
-- Name: factura_recepcion_detalle_historial pk_factura_recepcion_detalle_historial; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle_historial
    ADD CONSTRAINT pk_factura_recepcion_detalle_historial PRIMARY KEY (id_factura_recepcion_detalle_historial);


--
-- Name: factura_recepcion_historial pk_factura_recepcion_historial; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_historial
    ADD CONSTRAINT pk_factura_recepcion_historial PRIMARY KEY (id_factura_recepcion_historial);


--
-- Name: inventario_cierre_correccion pk_inventario_cierre_correccion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_correccion
    ADD CONSTRAINT pk_inventario_cierre_correccion PRIMARY KEY (id_inventario_cierre_correccion);


--
-- Name: item_carta pk_item_carta; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_carta
    ADD CONSTRAINT pk_item_carta PRIMARY KEY (id_item_carta);


--
-- Name: menaje pk_menaje; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menaje
    ADD CONSTRAINT pk_menaje PRIMARY KEY (id_menaje);


--
-- Name: orden_compra_estado_historial pk_orden_compra_estado_historial; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_estado_historial
    ADD CONSTRAINT pk_orden_compra_estado_historial PRIMARY KEY (id_orden_compra_estado_historial);


--
-- Name: perfil_gestion_usuario pk_perfil_gestion_usuario; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfil_gestion_usuario
    ADD CONSTRAINT pk_perfil_gestion_usuario PRIMARY KEY (id_perfil_gestor, id_perfil_objetivo);


--
-- Name: perfil_opcion_menu pk_perfil_opcion_menu; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfil_opcion_menu
    ADD CONSTRAINT pk_perfil_opcion_menu PRIMARY KEY (id_perfil, id_opcion_menu);


--
-- Name: presentacion_venta pk_presentacion_venta; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presentacion_venta
    ADD CONSTRAINT pk_presentacion_venta PRIMARY KEY (id_presentacion_venta);


--
-- Name: producto pk_producto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto
    ADD CONSTRAINT pk_producto PRIMARY KEY (id_producto);


--
-- Name: proveedor pk_proveedor; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proveedor
    ADD CONSTRAINT pk_proveedor PRIMARY KEY (id_proveedor);


--
-- Name: receta pk_receta; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta
    ADD CONSTRAINT pk_receta PRIMARY KEY (id_receta);


--
-- Name: receta_detalle pk_receta_detalle; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta_detalle
    ADD CONSTRAINT pk_receta_detalle PRIMARY KEY (id_receta_detalle);


--
-- Name: subproducto pk_subproducto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto
    ADD CONSTRAINT pk_subproducto PRIMARY KEY (id_subproducto);


--
-- Name: subproducto_detalle pk_subproducto_detalle; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto_detalle
    ADD CONSTRAINT pk_subproducto_detalle PRIMARY KEY (id_subproducto_detalle);


--
-- Name: usuario_perfiles pk_usuario_perfiles; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_perfiles
    ADD CONSTRAINT pk_usuario_perfiles PRIMARY KEY (id_usuario, id_perfil);


--
-- Name: usuario_puestos_laborales pk_usuario_puestos_laborales; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_puestos_laborales
    ADD CONSTRAINT pk_usuario_puestos_laborales PRIMARY KEY (id_usuario, id_puesto_laboral);


--
-- Name: producto_categoria_historial producto_categoria_historial_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_categoria_historial
    ADD CONSTRAINT producto_categoria_historial_pkey PRIMARY KEY (id_producto_categoria_historial);


--
-- Name: producto_proveedor_historial producto_proveedor_historial_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_proveedor_historial
    ADD CONSTRAINT producto_proveedor_historial_pkey PRIMARY KEY (id_producto_proveedor_historial);


--
-- Name: producto_stock_local producto_stock_local_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_stock_local
    ADD CONSTRAINT producto_stock_local_pkey PRIMARY KEY (id_producto, id_local);


--
-- Name: promocion promocion_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion
    ADD CONSTRAINT promocion_codigo_key UNIQUE (codigo);


--
-- Name: promocion_grupo promocion_grupo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion_grupo
    ADD CONSTRAINT promocion_grupo_pkey PRIMARY KEY (id_promocion_grupo);


--
-- Name: promocion_opcion promocion_opcion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion_opcion
    ADD CONSTRAINT promocion_opcion_pkey PRIMARY KEY (id_promocion_opcion);


--
-- Name: promocion promocion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion
    ADD CONSTRAINT promocion_pkey PRIMARY KEY (id_promocion);


--
-- Name: proveedor_categoria proveedor_categoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proveedor_categoria
    ADD CONSTRAINT proveedor_categoria_pkey PRIMARY KEY (id_proveedor, id_categoria);


--
-- Name: puesto_laboral puesto_laboral_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.puesto_laboral
    ADD CONSTRAINT puesto_laboral_pkey PRIMARY KEY (id_puesto_laboral);


--
-- Name: salon_autorizacion_usada salon_autorizacion_usada_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_autorizacion_usada
    ADD CONSTRAINT salon_autorizacion_usada_pkey PRIMARY KEY (clave);


--
-- Name: salon_cobro salon_cobro_id_local_clave_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro
    ADD CONSTRAINT salon_cobro_id_local_clave_key UNIQUE (id_local, clave);


--
-- Name: salon_cobro salon_cobro_id_movimiento_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro
    ADD CONSTRAINT salon_cobro_id_movimiento_key UNIQUE (id_movimiento);


--
-- Name: salon_cobro_pedido salon_cobro_pedido_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro_pedido
    ADD CONSTRAINT salon_cobro_pedido_pkey PRIMARY KEY (id_pedido);


--
-- Name: salon_cobro salon_cobro_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro
    ADD CONSTRAINT salon_cobro_pkey PRIMARY KEY (id_cobro);


--
-- Name: salon_distribucion salon_distribucion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_distribucion
    ADD CONSTRAINT salon_distribucion_pkey PRIMARY KEY (id_local);


--
-- Name: salon_intentos salon_intentos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_intentos
    ADD CONSTRAINT salon_intentos_pkey PRIMARY KEY (origen);


--
-- Name: salon_linea_anulada salon_linea_anulada_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_linea_anulada
    ADD CONSTRAINT salon_linea_anulada_pkey PRIMARY KEY (id_linea);


--
-- Name: salon_pedido_asignacion salon_pedido_asignacion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_asignacion
    ADD CONSTRAINT salon_pedido_asignacion_pkey PRIMARY KEY (id_pedido);


--
-- Name: salon_pedido_linea salon_pedido_linea_id_pedido_posicion_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_linea
    ADD CONSTRAINT salon_pedido_linea_id_pedido_posicion_key UNIQUE (id_pedido, posicion);


--
-- Name: salon_pedido_linea salon_pedido_linea_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_linea
    ADD CONSTRAINT salon_pedido_linea_pkey PRIMARY KEY (id_linea);


--
-- Name: salon_pedido salon_pedido_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido
    ADD CONSTRAINT salon_pedido_pkey PRIMARY KEY (id_pedido);


--
-- Name: unidad_medida unidad_medida_codigo_unece_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unidad_medida
    ADD CONSTRAINT unidad_medida_codigo_unece_key UNIQUE (codigo_unece);


--
-- Name: unidad_medida unidad_medida_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unidad_medida
    ADD CONSTRAINT unidad_medida_pkey PRIMARY KEY (codigo);


--
-- Name: categoria_carta uq_categoria_carta_prefijo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categoria_carta
    ADD CONSTRAINT uq_categoria_carta_prefijo UNIQUE (prefijo);


--
-- Name: categoria_producto uq_categoria_producto_prefijo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categoria_producto
    ADD CONSTRAINT uq_categoria_producto_prefijo UNIQUE (prefijo);


--
-- Name: inventario_cierre_correccion_detalle uq_correccion_detalle_producto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_correccion_detalle
    ADD CONSTRAINT uq_correccion_detalle_producto UNIQUE (id_inventario_cierre_correccion, id_producto);


--
-- Name: factura_recepcion_detalle uq_factura_detalle; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle
    ADD CONSTRAINT uq_factura_detalle UNIQUE (id_factura_recepcion, id_producto);


--
-- Name: factura_recepcion uq_factura_proveedor_numero; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion
    ADD CONSTRAINT uq_factura_proveedor_numero UNIQUE (id_proveedor, numero_factura);


--
-- Name: factura_recepcion_detalle_historial uq_frdh_producto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle_historial
    ADD CONSTRAINT uq_frdh_producto UNIQUE (id_factura_recepcion_historial, id_producto);


--
-- Name: grupo_salsa_opcion uq_grupo_salsa_opcion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa_opcion
    ADD CONSTRAINT uq_grupo_salsa_opcion UNIQUE (id_grupo_salsa, id_producto);


--
-- Name: inventario_cierre_detalle uq_inventario_detalle; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_detalle
    ADD CONSTRAINT uq_inventario_detalle UNIQUE (id_inventario_cierre, id_producto);


--
-- Name: inventario_cierre uq_inventario_local_fecha; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre
    ADD CONSTRAINT uq_inventario_local_fecha UNIQUE (id_local, fecha_inventario);


--
-- Name: item_carta uq_item_carta_codigo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_carta
    ADD CONSTRAINT uq_item_carta_codigo UNIQUE (codigo);


--
-- Name: movimiento_inventario_detalle uq_movimiento_detalle; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario_detalle
    ADD CONSTRAINT uq_movimiento_detalle UNIQUE (id_movimiento_inventario, id_producto);


--
-- Name: orden_compra_detalle uq_orden_detalle; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_detalle
    ADD CONSTRAINT uq_orden_detalle UNIQUE (id_orden_compra, id_producto);


--
-- Name: presentacion_venta uq_presentacion_venta; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presentacion_venta
    ADD CONSTRAINT uq_presentacion_venta UNIQUE (id_item_carta, id_menaje, contenido, unidad);


--
-- Name: producto uq_producto_codigo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto
    ADD CONSTRAINT uq_producto_codigo UNIQUE (codigo);


--
-- Name: promocion_opcion uq_promocion_opcion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion_opcion
    ADD CONSTRAINT uq_promocion_opcion UNIQUE (id_promocion_grupo, id_presentacion_venta);


--
-- Name: puesto_laboral uq_puesto_laboral_nombre; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.puesto_laboral
    ADD CONSTRAINT uq_puesto_laboral_nombre UNIQUE (nombre);


--
-- Name: receta_detalle uq_receta_detalle_producto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta_detalle
    ADD CONSTRAINT uq_receta_detalle_producto UNIQUE (id_receta, id_producto);


--
-- Name: receta_detalle uq_receta_detalle_subproducto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta_detalle
    ADD CONSTRAINT uq_receta_detalle_subproducto UNIQUE (id_receta, id_subproducto);


--
-- Name: receta uq_receta_presentacion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta
    ADD CONSTRAINT uq_receta_presentacion UNIQUE (id_presentacion_venta);


--
-- Name: subproducto uq_subproducto_codigo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto
    ADD CONSTRAINT uq_subproducto_codigo UNIQUE (codigo);


--
-- Name: subproducto_detalle uq_subproducto_detalle_producto; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto_detalle
    ADD CONSTRAINT uq_subproducto_detalle_producto UNIQUE (id_subproducto, id_producto);


--
-- Name: usuario_local uq_usuario_local; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_local
    ADD CONSTRAINT uq_usuario_local UNIQUE (id_usuario, id_local);


--
-- Name: usuario usuario_dni_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_dni_key UNIQUE (dni);


--
-- Name: usuario_local usuario_local_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_local
    ADD CONSTRAINT usuario_local_pkey PRIMARY KEY (id_usuario_local);


--
-- Name: usuario_pin_salon usuario_pin_salon_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_pin_salon
    ADD CONSTRAINT usuario_pin_salon_pkey PRIMARY KEY (id_usuario);


--
-- Name: usuario usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_pkey PRIMARY KEY (id_usuario);


--
-- Name: idx_actividad_usuario_local; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_actividad_usuario_local ON public.actividad_usuario USING btree (id_local);


--
-- Name: idx_actividad_usuario_perfil; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_actividad_usuario_perfil ON public.actividad_usuario USING btree (id_perfil_utilizado);


--
-- Name: idx_actividad_usuario_puesto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_actividad_usuario_puesto ON public.actividad_usuario USING btree (id_puesto_laboral);


--
-- Name: idx_auditoria_cambio_local; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auditoria_cambio_local ON public.auditoria_cambio USING btree (id_local);


--
-- Name: idx_auditoria_cambio_perfil; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auditoria_cambio_perfil ON public.auditoria_cambio USING btree (id_perfil_utilizado);


--
-- Name: idx_auditoria_cambio_puesto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auditoria_cambio_puesto ON public.auditoria_cambio USING btree (id_puesto_laboral);


--
-- Name: idx_proveedor_categoria_categoria; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proveedor_categoria_categoria ON public.proveedor_categoria USING btree (id_categoria);


--
-- Name: idx_usuario_local_local; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usuario_local_local ON public.usuario_local USING btree (id_local) WHERE (estado_registro = 1);


--
-- Name: idx_usuario_local_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usuario_local_usuario ON public.usuario_local USING btree (id_usuario) WHERE (estado_registro = 1);


--
-- Name: idx_usuario_puesto_laboral; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usuario_puesto_laboral ON public.usuario USING btree (id_puesto_laboral);


--
-- Name: ix_actividad_modulo_registro; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_actividad_modulo_registro ON public.actividad_usuario USING btree (modulo, id_registro_afectado);


--
-- Name: ix_actividad_usuario_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_actividad_usuario_fecha ON public.actividad_usuario USING btree (id_usuario, fecha_actividad DESC);


--
-- Name: ix_asistente_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_asistente_usuario ON public.asistente_ia_borrador USING btree (id_usuario, creado_en);


--
-- Name: ix_auditoria_cambio_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_auditoria_cambio_fecha ON public.auditoria_cambio USING btree (fecha_cambio DESC);


--
-- Name: ix_auditoria_cambio_registro; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_auditoria_cambio_registro ON public.auditoria_cambio USING btree (tabla_afectada, id_registro_afectado);


--
-- Name: ix_cobro_jornada; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cobro_jornada ON public.salon_cobro USING btree (id_jornada);


--
-- Name: ix_conteo_puesto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_conteo_puesto ON public.inventario_conteo USING btree (puesto_asignado, id_ronda);


--
-- Name: ix_correccion_inventario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_correccion_inventario ON public.inventario_cierre_correccion USING btree (id_inventario_cierre, fecha_correccion DESC);


--
-- Name: ix_correccion_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_correccion_usuario ON public.inventario_cierre_correccion USING btree (usuario_correccion);


--
-- Name: ix_evento_jornada; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_evento_jornada ON public.inventario_evento USING btree (id_jornada, id_producto);


--
-- Name: ix_evento_saldo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_evento_saldo ON public.inventario_evento USING btree (id_local, id_producto);


--
-- Name: ix_factura_detalle_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_factura_detalle_producto ON public.factura_recepcion_detalle USING btree (id_producto);


--
-- Name: ix_factura_orden; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_factura_orden ON public.factura_recepcion USING btree (id_orden_compra);


--
-- Name: ix_factura_recepcion_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_factura_recepcion_fecha ON public.factura_recepcion USING btree (fecha_recepcion);


--
-- Name: ix_factura_recepcion_orden; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_factura_recepcion_orden ON public.factura_recepcion USING btree (id_orden_compra);


--
-- Name: ix_frh_factura; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_frh_factura ON public.factura_recepcion_historial USING btree (id_factura_recepcion);


--
-- Name: ix_grupo_salsa_opcion_grupo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_grupo_salsa_opcion_grupo ON public.grupo_salsa_opcion USING btree (id_grupo_salsa);


--
-- Name: ix_grupo_salsa_opcion_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_grupo_salsa_opcion_producto ON public.grupo_salsa_opcion USING btree (id_producto);


--
-- Name: ix_inventario_detalle_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inventario_detalle_producto ON public.inventario_cierre_detalle USING btree (id_producto);


--
-- Name: ix_item_carta_categoria; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_item_carta_categoria ON public.item_carta USING btree (id_categoria_carta);


--
-- Name: ix_movimiento_detalle_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimiento_detalle_producto ON public.movimiento_inventario_detalle USING btree (id_producto);


--
-- Name: ix_movimiento_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimiento_fecha ON public.movimiento_inventario USING btree (fecha_movimiento);


--
-- Name: ix_movimiento_local_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimiento_local_fecha ON public.movimiento_inventario USING btree (id_local, fecha_movimiento);


--
-- Name: ix_oceh_orden; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_oceh_orden ON public.orden_compra_estado_historial USING btree (id_orden_compra);


--
-- Name: ix_orden_compra_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_orden_compra_estado ON public.orden_compra USING btree (estado_orden_compra);


--
-- Name: ix_orden_compra_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_orden_compra_fecha ON public.orden_compra USING btree (fecha_registro);


--
-- Name: ix_orden_detalle_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_orden_detalle_producto ON public.orden_compra_detalle USING btree (id_producto);


--
-- Name: ix_orden_detalle_proveedor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_orden_detalle_proveedor ON public.orden_compra_detalle USING btree (id_proveedor);


--
-- Name: ix_orden_local_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_orden_local_fecha ON public.orden_compra USING btree (id_local, fecha_registro);


--
-- Name: ix_pch_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pch_fecha ON public.producto_categoria_historial USING btree (fecha_cambio DESC);


--
-- Name: ix_pch_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pch_producto ON public.producto_categoria_historial USING btree (id_producto);


--
-- Name: ix_pph_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pph_fecha ON public.producto_proveedor_historial USING btree (fecha_cambio DESC);


--
-- Name: ix_pph_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pph_producto ON public.producto_proveedor_historial USING btree (id_producto);


--
-- Name: ix_presentacion_venta_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_presentacion_venta_item ON public.presentacion_venta USING btree (id_item_carta);


--
-- Name: ix_presentacion_venta_menaje; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_presentacion_venta_menaje ON public.presentacion_venta USING btree (id_menaje);


--
-- Name: ix_producto_stock_local_local; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_producto_stock_local_local ON public.producto_stock_local USING btree (id_local);


--
-- Name: ix_promocion_grupo_promocion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_promocion_grupo_promocion ON public.promocion_grupo USING btree (id_promocion);


--
-- Name: ix_promocion_opcion_grupo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_promocion_opcion_grupo ON public.promocion_opcion USING btree (id_promocion_grupo);


--
-- Name: ix_promocion_opcion_presentacion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_promocion_opcion_presentacion ON public.promocion_opcion USING btree (id_presentacion_venta);


--
-- Name: ix_receta_detalle_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_receta_detalle_producto ON public.receta_detalle USING btree (id_producto) WHERE (id_producto IS NOT NULL);


--
-- Name: ix_receta_detalle_receta; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_receta_detalle_receta ON public.receta_detalle USING btree (id_receta);


--
-- Name: ix_receta_detalle_subproducto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_receta_detalle_subproducto ON public.receta_detalle USING btree (id_subproducto) WHERE (id_subproducto IS NOT NULL);


--
-- Name: ix_reintegro_salida; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_reintegro_salida ON public.movimiento_reintegro USING btree (id_salida);


--
-- Name: ix_salon_cobro_local; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_salon_cobro_local ON public.salon_cobro USING btree (id_local, creado_en);


--
-- Name: ix_salon_cobro_pedido; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_salon_cobro_pedido ON public.salon_cobro_pedido USING btree (id_cobro);


--
-- Name: ix_salon_mesa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_salon_mesa ON public.salon_pedido USING btree (id_local, mesa, id_pedido);


--
-- Name: ix_salon_pedido_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_salon_pedido_usuario ON public.salon_pedido USING btree (id_local, id_usuario);


--
-- Name: ix_seguimiento_destino; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_seguimiento_destino ON public.movimiento_seguimiento USING btree (id_local_destino, estado);


--
-- Name: ix_subproducto_detalle_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_subproducto_detalle_producto ON public.subproducto_detalle USING btree (id_producto);


--
-- Name: ix_subproducto_detalle_subproducto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_subproducto_detalle_subproducto ON public.subproducto_detalle USING btree (id_subproducto);


--
-- Name: ix_upl_usuario_activo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_upl_usuario_activo ON public.usuario_puestos_laborales USING btree (id_usuario, estado_registro);


--
-- Name: ix_usuario_perfiles_perfil; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_usuario_perfiles_perfil ON public.usuario_perfiles USING btree (id_perfil);


--
-- Name: ix_usuario_puestos_activos; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_usuario_puestos_activos ON public.usuario_puestos_laborales USING btree (id_usuario, estado_registro);


--
-- Name: uq_guia_reintegro; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_guia_reintegro ON public.movimiento_reintegro USING btree (id_salida, guia_proveedor) WHERE (guia_proveedor IS NOT NULL);


--
-- Name: uq_jornada_abierta; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_jornada_abierta ON public.inventario_jornada USING btree (id_local) WHERE (cerrado_en IS NULL);


--
-- Name: uq_ronda_abierta; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_ronda_abierta ON public.inventario_ronda USING btree (id_local) WHERE (cerrado_en IS NULL);


--
-- Name: uq_salon_borrador; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_salon_borrador ON public.salon_pedido USING btree (id_local, mesa) WHERE ((estado)::text = 'BORRADOR'::text);


--
-- Name: uq_salon_envio; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_salon_envio ON public.salon_pedido USING btree (id_local, mesa, envio_clave) WHERE (envio_clave IS NOT NULL);


--
-- Name: ux_categoria_carta_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_categoria_carta_nombre ON public.categoria_carta USING btree (lower((nombre)::text));


--
-- Name: ux_categoria_producto_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_categoria_producto_nombre ON public.categoria_producto USING btree (lower((nombre)::text));


--
-- Name: ux_inventario_cierre_detalle_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_inventario_cierre_detalle_producto ON public.inventario_cierre_detalle USING btree (id_inventario_cierre, id_producto);


--
-- Name: ux_menaje_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_menaje_nombre ON public.menaje USING btree (lower((nombre)::text));


--
-- Name: ux_opcion_menu_codigo; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_opcion_menu_codigo ON public.opcion_menu USING btree (lower((codigo)::text));


--
-- Name: ux_opcion_menu_url; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_opcion_menu_url ON public.opcion_menu USING btree (lower((url_menu)::text));


--
-- Name: ux_perfiles_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_perfiles_nombre ON public.perfiles USING btree (lower((nombre)::text));


--
-- Name: ux_proveedor_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_proveedor_nombre ON public.proveedor USING btree (lower((nombre)::text));


--
-- Name: ux_usuario_correo; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_usuario_correo ON public.usuario USING btree (lower((correo_electronico)::text));


--
-- Name: salon_cobro cobro_jornada; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER cobro_jornada BEFORE INSERT ON public.salon_cobro FOR EACH ROW EXECUTE FUNCTION public.inventario_cobro_jornada();


--
-- Name: movimiento_inventario_detalle movimiento_evento; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER movimiento_evento AFTER INSERT OR DELETE OR UPDATE ON public.movimiento_inventario_detalle FOR EACH ROW EXECUTE FUNCTION public.inventario_registrar_evento();


--
-- Name: salon_pedido_linea proteger_linea_salon; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER proteger_linea_salon BEFORE INSERT OR DELETE OR UPDATE ON public.salon_pedido_linea FOR EACH ROW EXECUTE FUNCTION public.proteger_linea_salon();


--
-- Name: salon_pedido proteger_pedido_salon; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER proteger_pedido_salon BEFORE DELETE OR UPDATE ON public.salon_pedido FOR EACH ROW EXECUTE FUNCTION public.proteger_pedido_salon();


--
-- Name: factura_recepcion_detalle recepcion_evento; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER recepcion_evento AFTER INSERT OR DELETE OR UPDATE ON public.factura_recepcion_detalle FOR EACH ROW EXECUTE FUNCTION public.inventario_registrar_evento();


--
-- Name: grupo_salsa_opcion trg_validar_unidad_grupo_salsa_opcion; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_unidad_grupo_salsa_opcion BEFORE INSERT OR UPDATE OF id_producto, unidad ON public.grupo_salsa_opcion FOR EACH ROW EXECUTE FUNCTION public.validar_unidad_grupo_salsa_opcion();


--
-- Name: receta_detalle trg_validar_unidad_receta_detalle; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_unidad_receta_detalle BEFORE INSERT OR UPDATE OF tipo_componente, id_producto, id_subproducto, unidad ON public.receta_detalle FOR EACH ROW EXECUTE FUNCTION public.validar_unidad_receta_detalle();


--
-- Name: subproducto_detalle trg_validar_unidad_subproducto_detalle; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_unidad_subproducto_detalle BEFORE INSERT OR UPDATE OF id_producto, unidad ON public.subproducto_detalle FOR EACH ROW EXECUTE FUNCTION public.validar_unidad_subproducto_detalle();


--
-- Name: asistente_ia_borrador asistente_ia_borrador_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistente_ia_borrador
    ADD CONSTRAINT asistente_ia_borrador_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: actividad_usuario fk_actividad_perfil_utilizado; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actividad_usuario
    ADD CONSTRAINT fk_actividad_perfil_utilizado FOREIGN KEY (id_perfil_utilizado) REFERENCES public.perfiles(id_perfil);


--
-- Name: actividad_usuario fk_actividad_puesto_laboral; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actividad_usuario
    ADD CONSTRAINT fk_actividad_puesto_laboral FOREIGN KEY (id_puesto_laboral) REFERENCES public.puesto_laboral(id_puesto_laboral);


--
-- Name: actividad_usuario fk_actividad_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actividad_usuario
    ADD CONSTRAINT fk_actividad_usuario FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: actividad_usuario fk_actividad_usuario_local; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actividad_usuario
    ADD CONSTRAINT fk_actividad_usuario_local FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: auditoria_cambio fk_auditoria_cambio_local; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_cambio
    ADD CONSTRAINT fk_auditoria_cambio_local FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: auditoria_cambio fk_auditoria_cambio_perfil; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_cambio
    ADD CONSTRAINT fk_auditoria_cambio_perfil FOREIGN KEY (id_perfil_utilizado) REFERENCES public.perfiles(id_perfil);


--
-- Name: auditoria_cambio fk_auditoria_cambio_puesto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_cambio
    ADD CONSTRAINT fk_auditoria_cambio_puesto FOREIGN KEY (id_puesto_laboral) REFERENCES public.puesto_laboral(id_puesto_laboral);


--
-- Name: auditoria_cambio fk_auditoria_cambio_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_cambio
    ADD CONSTRAINT fk_auditoria_cambio_usuario FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_cierre_correccion_detalle fk_correccion_detalle_cabecera; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_correccion_detalle
    ADD CONSTRAINT fk_correccion_detalle_cabecera FOREIGN KEY (id_inventario_cierre_correccion) REFERENCES public.inventario_cierre_correccion(id_inventario_cierre_correccion) ON DELETE CASCADE;


--
-- Name: inventario_cierre_correccion_detalle fk_correccion_detalle_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_correccion_detalle
    ADD CONSTRAINT fk_correccion_detalle_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: inventario_cierre_correccion fk_correccion_inventario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_correccion
    ADD CONSTRAINT fk_correccion_inventario FOREIGN KEY (id_inventario_cierre) REFERENCES public.inventario_cierre(id_inventario_cierre);


--
-- Name: inventario_cierre_correccion fk_correccion_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_correccion
    ADD CONSTRAINT fk_correccion_usuario FOREIGN KEY (usuario_correccion) REFERENCES public.usuario(id_usuario);


--
-- Name: factura_recepcion_detalle fk_factura_detalle_factura; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle
    ADD CONSTRAINT fk_factura_detalle_factura FOREIGN KEY (id_factura_recepcion) REFERENCES public.factura_recepcion(id_factura_recepcion) ON DELETE CASCADE;


--
-- Name: factura_recepcion_detalle fk_factura_detalle_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle
    ADD CONSTRAINT fk_factura_detalle_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: factura_recepcion fk_factura_orden; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion
    ADD CONSTRAINT fk_factura_orden FOREIGN KEY (id_orden_compra) REFERENCES public.orden_compra(id_orden_compra);


--
-- Name: factura_recepcion fk_factura_proveedor; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion
    ADD CONSTRAINT fk_factura_proveedor FOREIGN KEY (id_proveedor) REFERENCES public.proveedor(id_proveedor);


--
-- Name: factura_recepcion fk_factura_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion
    ADD CONSTRAINT fk_factura_usuario FOREIGN KEY (usuario_recepcion) REFERENCES public.usuario(id_usuario);


--
-- Name: factura_recepcion_detalle_historial fk_frdh_historial; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle_historial
    ADD CONSTRAINT fk_frdh_historial FOREIGN KEY (id_factura_recepcion_historial) REFERENCES public.factura_recepcion_historial(id_factura_recepcion_historial) ON DELETE CASCADE;


--
-- Name: factura_recepcion_detalle_historial fk_frdh_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_detalle_historial
    ADD CONSTRAINT fk_frdh_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: factura_recepcion_historial fk_frh_factura; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_historial
    ADD CONSTRAINT fk_frh_factura FOREIGN KEY (id_factura_recepcion) REFERENCES public.factura_recepcion(id_factura_recepcion);


--
-- Name: factura_recepcion_historial fk_frh_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_recepcion_historial
    ADD CONSTRAINT fk_frh_usuario FOREIGN KEY (usuario_correccion) REFERENCES public.usuario(id_usuario);


--
-- Name: grupo_salsa_opcion fk_grupo_salsa_opcion_unidad_medida; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa_opcion
    ADD CONSTRAINT fk_grupo_salsa_opcion_unidad_medida FOREIGN KEY (unidad) REFERENCES public.unidad_medida(codigo);


--
-- Name: inventario_cierre_detalle fk_inventario_detalle_cierre; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_detalle
    ADD CONSTRAINT fk_inventario_detalle_cierre FOREIGN KEY (id_inventario_cierre) REFERENCES public.inventario_cierre(id_inventario_cierre) ON DELETE CASCADE;


--
-- Name: inventario_cierre_detalle fk_inventario_detalle_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre_detalle
    ADD CONSTRAINT fk_inventario_detalle_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: inventario_cierre fk_inventario_usuario_registro; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre
    ADD CONSTRAINT fk_inventario_usuario_registro FOREIGN KEY (usuario_registro) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_cierre fk_inventario_usuario_revision; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre
    ADD CONSTRAINT fk_inventario_usuario_revision FOREIGN KEY (usuario_revision) REFERENCES public.usuario(id_usuario);


--
-- Name: item_carta fk_item_carta_categoria; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_carta
    ADD CONSTRAINT fk_item_carta_categoria FOREIGN KEY (id_categoria_carta) REFERENCES public.categoria_carta(id_categoria_carta);


--
-- Name: movimiento_inventario_detalle fk_movimiento_detalle_movimiento; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario_detalle
    ADD CONSTRAINT fk_movimiento_detalle_movimiento FOREIGN KEY (id_movimiento_inventario) REFERENCES public.movimiento_inventario(id_movimiento_inventario) ON DELETE CASCADE;


--
-- Name: movimiento_inventario_detalle fk_movimiento_detalle_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario_detalle
    ADD CONSTRAINT fk_movimiento_detalle_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: movimiento_inventario fk_movimiento_proveedor; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario
    ADD CONSTRAINT fk_movimiento_proveedor FOREIGN KEY (id_proveedor) REFERENCES public.proveedor(id_proveedor);


--
-- Name: movimiento_inventario fk_movimiento_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario
    ADD CONSTRAINT fk_movimiento_usuario FOREIGN KEY (usuario_registro) REFERENCES public.usuario(id_usuario);


--
-- Name: orden_compra_estado_historial fk_oceh_orden; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_estado_historial
    ADD CONSTRAINT fk_oceh_orden FOREIGN KEY (id_orden_compra) REFERENCES public.orden_compra(id_orden_compra);


--
-- Name: orden_compra_estado_historial fk_oceh_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_estado_historial
    ADD CONSTRAINT fk_oceh_usuario FOREIGN KEY (usuario_modificacion) REFERENCES public.usuario(id_usuario);


--
-- Name: opcion_menu fk_opcion_menu_padre; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opcion_menu
    ADD CONSTRAINT fk_opcion_menu_padre FOREIGN KEY (id_padre) REFERENCES public.opcion_menu(id_opcion_menu);


--
-- Name: opcion_menu fk_opcion_menu_usuario_creacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opcion_menu
    ADD CONSTRAINT fk_opcion_menu_usuario_creacion FOREIGN KEY (usuario_creacion) REFERENCES public.usuario(id_usuario);


--
-- Name: opcion_menu fk_opcion_menu_usuario_modificacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opcion_menu
    ADD CONSTRAINT fk_opcion_menu_usuario_modificacion FOREIGN KEY (usuario_modificacion) REFERENCES public.usuario(id_usuario);


--
-- Name: orden_compra_detalle fk_orden_detalle_orden; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_detalle
    ADD CONSTRAINT fk_orden_detalle_orden FOREIGN KEY (id_orden_compra) REFERENCES public.orden_compra(id_orden_compra) ON DELETE CASCADE;


--
-- Name: orden_compra_detalle fk_orden_detalle_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_detalle
    ADD CONSTRAINT fk_orden_detalle_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: orden_compra fk_orden_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra
    ADD CONSTRAINT fk_orden_usuario FOREIGN KEY (usuario_registro) REFERENCES public.usuario(id_usuario);


--
-- Name: orden_compra fk_orden_usuario_modificacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra
    ADD CONSTRAINT fk_orden_usuario_modificacion FOREIGN KEY (usuario_modificacion) REFERENCES public.usuario(id_usuario);


--
-- Name: producto_categoria_historial fk_pch_categoria_anterior; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_categoria_historial
    ADD CONSTRAINT fk_pch_categoria_anterior FOREIGN KEY (id_categoria_anterior) REFERENCES public.categoria_producto(id_categoria);


--
-- Name: producto_categoria_historial fk_pch_categoria_nueva; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_categoria_historial
    ADD CONSTRAINT fk_pch_categoria_nueva FOREIGN KEY (id_categoria_nueva) REFERENCES public.categoria_producto(id_categoria);


--
-- Name: producto_categoria_historial fk_pch_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_categoria_historial
    ADD CONSTRAINT fk_pch_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: producto_categoria_historial fk_pch_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_categoria_historial
    ADD CONSTRAINT fk_pch_usuario FOREIGN KEY (usuario_cambio) REFERENCES public.usuario(id_usuario);


--
-- Name: perfil_gestion_usuario fk_perfil_gestion_gestor; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfil_gestion_usuario
    ADD CONSTRAINT fk_perfil_gestion_gestor FOREIGN KEY (id_perfil_gestor) REFERENCES public.perfiles(id_perfil);


--
-- Name: perfil_gestion_usuario fk_perfil_gestion_objetivo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfil_gestion_usuario
    ADD CONSTRAINT fk_perfil_gestion_objetivo FOREIGN KEY (id_perfil_objetivo) REFERENCES public.perfiles(id_perfil);


--
-- Name: perfil_opcion_menu fk_perfil_opcion_menu; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfil_opcion_menu
    ADD CONSTRAINT fk_perfil_opcion_menu FOREIGN KEY (id_opcion_menu) REFERENCES public.opcion_menu(id_opcion_menu);


--
-- Name: perfil_opcion_menu fk_perfil_opcion_perfil; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfil_opcion_menu
    ADD CONSTRAINT fk_perfil_opcion_perfil FOREIGN KEY (id_perfil) REFERENCES public.perfiles(id_perfil);


--
-- Name: producto_proveedor_historial fk_pph_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_proveedor_historial
    ADD CONSTRAINT fk_pph_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: producto_proveedor_historial fk_pph_proveedor_anterior; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_proveedor_historial
    ADD CONSTRAINT fk_pph_proveedor_anterior FOREIGN KEY (id_proveedor_anterior) REFERENCES public.proveedor(id_proveedor);


--
-- Name: producto_proveedor_historial fk_pph_proveedor_nuevo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_proveedor_historial
    ADD CONSTRAINT fk_pph_proveedor_nuevo FOREIGN KEY (id_proveedor_nuevo) REFERENCES public.proveedor(id_proveedor);


--
-- Name: producto_proveedor_historial fk_pph_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_proveedor_historial
    ADD CONSTRAINT fk_pph_usuario FOREIGN KEY (usuario_cambio) REFERENCES public.usuario(id_usuario);


--
-- Name: presentacion_venta fk_presentacion_venta_item; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presentacion_venta
    ADD CONSTRAINT fk_presentacion_venta_item FOREIGN KEY (id_item_carta) REFERENCES public.item_carta(id_item_carta);


--
-- Name: presentacion_venta fk_presentacion_venta_menaje; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presentacion_venta
    ADD CONSTRAINT fk_presentacion_venta_menaje FOREIGN KEY (id_menaje) REFERENCES public.menaje(id_menaje);


--
-- Name: presentacion_venta fk_presentacion_venta_unidad_medida; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presentacion_venta
    ADD CONSTRAINT fk_presentacion_venta_unidad_medida FOREIGN KEY (unidad) REFERENCES public.unidad_medida(codigo);


--
-- Name: producto fk_producto_categoria; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto
    ADD CONSTRAINT fk_producto_categoria FOREIGN KEY (id_categoria) REFERENCES public.categoria_producto(id_categoria);


--
-- Name: producto fk_producto_proveedor; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto
    ADD CONSTRAINT fk_producto_proveedor FOREIGN KEY (id_proveedor) REFERENCES public.proveedor(id_proveedor);


--
-- Name: producto fk_producto_unidad_medida; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto
    ADD CONSTRAINT fk_producto_unidad_medida FOREIGN KEY (unidad) REFERENCES public.unidad_medida(codigo);


--
-- Name: puesto_laboral fk_puesto_laboral_usuario_creacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.puesto_laboral
    ADD CONSTRAINT fk_puesto_laboral_usuario_creacion FOREIGN KEY (usuario_creacion) REFERENCES public.usuario(id_usuario);


--
-- Name: puesto_laboral fk_puesto_laboral_usuario_modificacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.puesto_laboral
    ADD CONSTRAINT fk_puesto_laboral_usuario_modificacion FOREIGN KEY (usuario_modificacion) REFERENCES public.usuario(id_usuario);


--
-- Name: receta_detalle fk_receta_detalle_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta_detalle
    ADD CONSTRAINT fk_receta_detalle_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: receta_detalle fk_receta_detalle_receta; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta_detalle
    ADD CONSTRAINT fk_receta_detalle_receta FOREIGN KEY (id_receta) REFERENCES public.receta(id_receta);


--
-- Name: receta_detalle fk_receta_detalle_subproducto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta_detalle
    ADD CONSTRAINT fk_receta_detalle_subproducto FOREIGN KEY (id_subproducto) REFERENCES public.subproducto(id_subproducto);


--
-- Name: receta_detalle fk_receta_detalle_unidad_medida; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta_detalle
    ADD CONSTRAINT fk_receta_detalle_unidad_medida FOREIGN KEY (unidad) REFERENCES public.unidad_medida(codigo);


--
-- Name: receta fk_receta_presentacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receta
    ADD CONSTRAINT fk_receta_presentacion FOREIGN KEY (id_presentacion_venta) REFERENCES public.presentacion_venta(id_presentacion_venta);


--
-- Name: subproducto_detalle fk_subproducto_detalle_producto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto_detalle
    ADD CONSTRAINT fk_subproducto_detalle_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: subproducto_detalle fk_subproducto_detalle_subproducto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto_detalle
    ADD CONSTRAINT fk_subproducto_detalle_subproducto FOREIGN KEY (id_subproducto) REFERENCES public.subproducto(id_subproducto);


--
-- Name: subproducto_detalle fk_subproducto_detalle_unidad_medida; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto_detalle
    ADD CONSTRAINT fk_subproducto_detalle_unidad_medida FOREIGN KEY (unidad) REFERENCES public.unidad_medida(codigo);


--
-- Name: subproducto fk_subproducto_unidad_medida; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subproducto
    ADD CONSTRAINT fk_subproducto_unidad_medida FOREIGN KEY (unidad) REFERENCES public.unidad_medida(codigo);


--
-- Name: usuario_puestos_laborales fk_upl_asignador; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_puestos_laborales
    ADD CONSTRAINT fk_upl_asignador FOREIGN KEY (usuario_asignacion) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario_puestos_laborales fk_upl_modificador; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_puestos_laborales
    ADD CONSTRAINT fk_upl_modificador FOREIGN KEY (usuario_modificacion) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario_puestos_laborales fk_upl_puesto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_puestos_laborales
    ADD CONSTRAINT fk_upl_puesto FOREIGN KEY (id_puesto_laboral) REFERENCES public.puesto_laboral(id_puesto_laboral);


--
-- Name: usuario_puestos_laborales fk_upl_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_puestos_laborales
    ADD CONSTRAINT fk_upl_usuario FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario fk_usuario_creacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT fk_usuario_creacion FOREIGN KEY (usuario_creacion) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario_local fk_usuario_local_local; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_local
    ADD CONSTRAINT fk_usuario_local_local FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: usuario_local fk_usuario_local_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_local
    ADD CONSTRAINT fk_usuario_local_usuario FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario fk_usuario_modificacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT fk_usuario_modificacion FOREIGN KEY (usuario_modificacion) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario_perfiles fk_usuario_perfiles_asignacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_perfiles
    ADD CONSTRAINT fk_usuario_perfiles_asignacion FOREIGN KEY (usuario_asignacion) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario_perfiles fk_usuario_perfiles_modificacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_perfiles
    ADD CONSTRAINT fk_usuario_perfiles_modificacion FOREIGN KEY (usuario_modificacion) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario_perfiles fk_usuario_perfiles_perfil; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_perfiles
    ADD CONSTRAINT fk_usuario_perfiles_perfil FOREIGN KEY (id_perfil) REFERENCES public.perfiles(id_perfil);


--
-- Name: usuario_perfiles fk_usuario_perfiles_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_perfiles
    ADD CONSTRAINT fk_usuario_perfiles_usuario FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: usuario fk_usuario_puesto_laboral; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT fk_usuario_puesto_laboral FOREIGN KEY (id_puesto_laboral) REFERENCES public.puesto_laboral(id_puesto_laboral);


--
-- Name: grupo_salsa grupo_salsa_id_presentacion_venta_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa
    ADD CONSTRAINT grupo_salsa_id_presentacion_venta_fkey FOREIGN KEY (id_presentacion_venta) REFERENCES public.presentacion_venta(id_presentacion_venta);


--
-- Name: grupo_salsa_opcion grupo_salsa_opcion_id_grupo_salsa_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa_opcion
    ADD CONSTRAINT grupo_salsa_opcion_id_grupo_salsa_fkey FOREIGN KEY (id_grupo_salsa) REFERENCES public.grupo_salsa(id_grupo_salsa);


--
-- Name: grupo_salsa_opcion grupo_salsa_opcion_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_salsa_opcion
    ADD CONSTRAINT grupo_salsa_opcion_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: inventario_asignacion_puesto inventario_asignacion_puesto_actualizado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_asignacion_puesto
    ADD CONSTRAINT inventario_asignacion_puesto_actualizado_por_fkey FOREIGN KEY (actualizado_por) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_asignacion_puesto inventario_asignacion_puesto_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_asignacion_puesto
    ADD CONSTRAINT inventario_asignacion_puesto_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: inventario_asignacion_puesto inventario_asignacion_puesto_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_asignacion_puesto
    ADD CONSTRAINT inventario_asignacion_puesto_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: inventario_asignacion_puesto inventario_asignacion_puesto_id_puesto_laboral_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_asignacion_puesto
    ADD CONSTRAINT inventario_asignacion_puesto_id_puesto_laboral_fkey FOREIGN KEY (id_puesto_laboral) REFERENCES public.puesto_laboral(id_puesto_laboral);


--
-- Name: inventario_cierre inventario_cierre_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_cierre
    ADD CONSTRAINT inventario_cierre_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: inventario_conteo inventario_conteo_asignado_a_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_asignado_a_fkey FOREIGN KEY (asignado_a) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_conteo inventario_conteo_contado_perfil_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_contado_perfil_fkey FOREIGN KEY (contado_perfil) REFERENCES public.perfiles(id_perfil);


--
-- Name: inventario_conteo inventario_conteo_contado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_contado_por_fkey FOREIGN KEY (contado_por) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_conteo inventario_conteo_contado_puesto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_contado_puesto_fkey FOREIGN KEY (contado_puesto) REFERENCES public.puesto_laboral(id_puesto_laboral);


--
-- Name: inventario_conteo_historial inventario_conteo_historial_id_ronda_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo_historial
    ADD CONSTRAINT inventario_conteo_historial_id_ronda_id_producto_fkey FOREIGN KEY (id_ronda, id_producto) REFERENCES public.inventario_conteo(id_ronda, id_producto);


--
-- Name: inventario_conteo_historial inventario_conteo_historial_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo_historial
    ADD CONSTRAINT inventario_conteo_historial_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_conteo inventario_conteo_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: inventario_conteo inventario_conteo_id_ronda_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_id_ronda_fkey FOREIGN KEY (id_ronda) REFERENCES public.inventario_ronda(id_ronda);


--
-- Name: inventario_conteo inventario_conteo_justificado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_justificado_por_fkey FOREIGN KEY (justificado_por) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_conteo inventario_conteo_puesto_asignado_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_puesto_asignado_fkey FOREIGN KEY (puesto_asignado) REFERENCES public.puesto_laboral(id_puesto_laboral);


--
-- Name: inventario_conteo inventario_conteo_revisado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_conteo
    ADD CONSTRAINT inventario_conteo_revisado_por_fkey FOREIGN KEY (revisado_por) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_evento inventario_evento_id_jornada_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_evento
    ADD CONSTRAINT inventario_evento_id_jornada_fkey FOREIGN KEY (id_jornada) REFERENCES public.inventario_jornada(id_jornada);


--
-- Name: inventario_evento inventario_evento_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_evento
    ADD CONSTRAINT inventario_evento_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: inventario_evento inventario_evento_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_evento
    ADD CONSTRAINT inventario_evento_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: inventario_jornada inventario_jornada_abierto_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada
    ADD CONSTRAINT inventario_jornada_abierto_por_fkey FOREIGN KEY (abierto_por) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_jornada inventario_jornada_cerrado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada
    ADD CONSTRAINT inventario_jornada_cerrado_por_fkey FOREIGN KEY (cerrado_por) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_jornada inventario_jornada_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada
    ADD CONSTRAINT inventario_jornada_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: inventario_jornada_inicio inventario_jornada_inicio_id_jornada_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada_inicio
    ADD CONSTRAINT inventario_jornada_inicio_id_jornada_fkey FOREIGN KEY (id_jornada) REFERENCES public.inventario_jornada(id_jornada);


--
-- Name: inventario_jornada_inicio inventario_jornada_inicio_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_jornada_inicio
    ADD CONSTRAINT inventario_jornada_inicio_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: inventario_ronda inventario_ronda_creado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_ronda
    ADD CONSTRAINT inventario_ronda_creado_por_fkey FOREIGN KEY (creado_por) REFERENCES public.usuario(id_usuario);


--
-- Name: inventario_ronda inventario_ronda_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_ronda
    ADD CONSTRAINT inventario_ronda_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: inventario_saldo_inicial inventario_saldo_inicial_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_saldo_inicial
    ADD CONSTRAINT inventario_saldo_inicial_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: inventario_saldo_inicial inventario_saldo_inicial_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_saldo_inicial
    ADD CONSTRAINT inventario_saldo_inicial_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: movimiento_inventario movimiento_inventario_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario
    ADD CONSTRAINT movimiento_inventario_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: movimiento_reintegro movimiento_reintegro_id_movimiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_reintegro
    ADD CONSTRAINT movimiento_reintegro_id_movimiento_fkey FOREIGN KEY (id_movimiento) REFERENCES public.movimiento_inventario(id_movimiento_inventario);


--
-- Name: movimiento_reintegro movimiento_reintegro_id_salida_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_reintegro
    ADD CONSTRAINT movimiento_reintegro_id_salida_fkey FOREIGN KEY (id_salida) REFERENCES public.movimiento_seguimiento(id_movimiento);


--
-- Name: movimiento_seguimiento movimiento_seguimiento_id_local_destino_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_seguimiento
    ADD CONSTRAINT movimiento_seguimiento_id_local_destino_fkey FOREIGN KEY (id_local_destino) REFERENCES public.local(id_local);


--
-- Name: movimiento_seguimiento movimiento_seguimiento_id_movimiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_seguimiento
    ADD CONSTRAINT movimiento_seguimiento_id_movimiento_fkey FOREIGN KEY (id_movimiento) REFERENCES public.movimiento_inventario(id_movimiento_inventario);


--
-- Name: orden_compra_detalle orden_compra_detalle_id_proveedor_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra_detalle
    ADD CONSTRAINT orden_compra_detalle_id_proveedor_fkey FOREIGN KEY (id_proveedor) REFERENCES public.proveedor(id_proveedor);


--
-- Name: orden_compra orden_compra_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orden_compra
    ADD CONSTRAINT orden_compra_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: producto_stock_local producto_stock_local_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_stock_local
    ADD CONSTRAINT producto_stock_local_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: producto_stock_local producto_stock_local_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto_stock_local
    ADD CONSTRAINT producto_stock_local_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: promocion_grupo promocion_grupo_id_promocion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion_grupo
    ADD CONSTRAINT promocion_grupo_id_promocion_fkey FOREIGN KEY (id_promocion) REFERENCES public.promocion(id_promocion);


--
-- Name: promocion_opcion promocion_opcion_id_presentacion_venta_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion_opcion
    ADD CONSTRAINT promocion_opcion_id_presentacion_venta_fkey FOREIGN KEY (id_presentacion_venta) REFERENCES public.presentacion_venta(id_presentacion_venta);


--
-- Name: promocion_opcion promocion_opcion_id_promocion_grupo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promocion_opcion
    ADD CONSTRAINT promocion_opcion_id_promocion_grupo_fkey FOREIGN KEY (id_promocion_grupo) REFERENCES public.promocion_grupo(id_promocion_grupo);


--
-- Name: proveedor_categoria proveedor_categoria_id_categoria_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proveedor_categoria
    ADD CONSTRAINT proveedor_categoria_id_categoria_fkey FOREIGN KEY (id_categoria) REFERENCES public.categoria_producto(id_categoria);


--
-- Name: proveedor_categoria proveedor_categoria_id_proveedor_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proveedor_categoria
    ADD CONSTRAINT proveedor_categoria_id_proveedor_fkey FOREIGN KEY (id_proveedor) REFERENCES public.proveedor(id_proveedor) ON DELETE CASCADE;


--
-- Name: salon_cobro salon_cobro_id_jornada_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro
    ADD CONSTRAINT salon_cobro_id_jornada_fkey FOREIGN KEY (id_jornada) REFERENCES public.inventario_jornada(id_jornada);


--
-- Name: salon_cobro salon_cobro_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro
    ADD CONSTRAINT salon_cobro_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: salon_cobro salon_cobro_id_movimiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro
    ADD CONSTRAINT salon_cobro_id_movimiento_fkey FOREIGN KEY (id_movimiento) REFERENCES public.movimiento_inventario(id_movimiento_inventario);


--
-- Name: salon_cobro salon_cobro_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro
    ADD CONSTRAINT salon_cobro_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: salon_cobro_pedido salon_cobro_pedido_id_cobro_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro_pedido
    ADD CONSTRAINT salon_cobro_pedido_id_cobro_fkey FOREIGN KEY (id_cobro) REFERENCES public.salon_cobro(id_cobro);


--
-- Name: salon_cobro_pedido salon_cobro_pedido_id_pedido_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_cobro_pedido
    ADD CONSTRAINT salon_cobro_pedido_id_pedido_fkey FOREIGN KEY (id_pedido) REFERENCES public.salon_pedido(id_pedido);


--
-- Name: salon_distribucion salon_distribucion_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_distribucion
    ADD CONSTRAINT salon_distribucion_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: salon_linea_anulada salon_linea_anulada_id_linea_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_linea_anulada
    ADD CONSTRAINT salon_linea_anulada_id_linea_fkey FOREIGN KEY (id_linea) REFERENCES public.salon_pedido_linea(id_linea);


--
-- Name: salon_linea_anulada salon_linea_anulada_id_responsable_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_linea_anulada
    ADD CONSTRAINT salon_linea_anulada_id_responsable_fkey FOREIGN KEY (id_responsable) REFERENCES public.usuario(id_usuario);


--
-- Name: salon_pedido_asignacion salon_pedido_asignacion_id_pedido_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_asignacion
    ADD CONSTRAINT salon_pedido_asignacion_id_pedido_fkey FOREIGN KEY (id_pedido) REFERENCES public.salon_pedido(id_pedido);


--
-- Name: salon_pedido_asignacion salon_pedido_asignacion_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_asignacion
    ADD CONSTRAINT salon_pedido_asignacion_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: salon_pedido salon_pedido_id_local_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido
    ADD CONSTRAINT salon_pedido_id_local_fkey FOREIGN KEY (id_local) REFERENCES public.local(id_local);


--
-- Name: salon_pedido salon_pedido_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido
    ADD CONSTRAINT salon_pedido_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: salon_pedido_linea salon_pedido_linea_id_pedido_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_linea
    ADD CONSTRAINT salon_pedido_linea_id_pedido_fkey FOREIGN KEY (id_pedido) REFERENCES public.salon_pedido(id_pedido);


--
-- Name: salon_pedido_linea salon_pedido_linea_id_presentacion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salon_pedido_linea
    ADD CONSTRAINT salon_pedido_linea_id_presentacion_fkey FOREIGN KEY (id_presentacion) REFERENCES public.presentacion_venta(id_presentacion_venta);


--
-- Name: unidad_medida unidad_medida_codigo_base_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unidad_medida
    ADD CONSTRAINT unidad_medida_codigo_base_fkey FOREIGN KEY (codigo_base) REFERENCES public.unidad_medida(codigo);


--
-- Name: usuario_pin_salon usuario_pin_salon_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_pin_salon
    ADD CONSTRAINT usuario_pin_salon_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- PostgreSQL database dump complete
--

\unrestrict aJ0nFskcdHEa3sPL2kZUtz3CFiRDMameF2EFeGztEvXtaTMac289xzmO7xGbk2K


-- MIGRACIONES ADICIONALES DE OCTUBRE 2026 (SALON Y LOCALES)
CREATE TABLE IF NOT EXISTS promocion_reposicion (
 id_promocion integer NOT NULL REFERENCES promocion(id_promocion),
 id_presentacion_venta integer NOT NULL REFERENCES presentacion_venta(id_presentacion_venta),
 PRIMARY KEY(id_promocion,id_presentacion_venta)
);

DO $do$ BEGIN
  ALTER TABLE salon_pedido_linea ALTER COLUMN id_presentacion DROP NOT NULL;
EXCEPTION WHEN OTHERS THEN NULL;
END $do$;

DO $do$ BEGIN
  ALTER TABLE salon_pedido_linea ADD COLUMN id_promocion integer REFERENCES promocion(id_promocion);
EXCEPTION WHEN OTHERS THEN NULL;
END $do$;

DO $do$ BEGIN
  ALTER TABLE salon_pedido_linea ADD COLUMN selecciones_promocion jsonb NOT NULL DEFAULT '[]'::jsonb;
EXCEPTION WHEN OTHERS THEN NULL;
END $do$;

DO $do$ BEGIN
  ALTER TABLE salon_pedido_linea ADD COLUMN id_barra_libre bigint REFERENCES salon_pedido_linea(id_linea);
EXCEPTION WHEN OTHERS THEN NULL;
END $do$;

UPDATE local SET direccion = 'Av. Paseo de la República 170, Lima 01' WHERE upper(codigo) LIKE '%SHERATON%';
UPDATE local SET direccion = 'Av. Pedro de Osma 144, Lima 15063' WHERE upper(codigo) LIKE '%BARRANCO%';
UPDATE local SET direccion = 'Av. Nicolás Ayllón, Santa Anita 15008' WHERE upper(codigo) LIKE '%SANTA_ANITA%';
UPDATE local SET direccion = 'C. Manuel Bonilla 108, Miraflores 15074' WHERE upper(codigo) LIKE '%MIRAFLORES%';

UPDATE local SET codigo='TDA-001' WHERE codigo='MIRAFLORES';
UPDATE local SET codigo='TDA-002' WHERE codigo='BARRANCO';
UPDATE local SET codigo='TDA-003' WHERE codigo='SHERATON';
UPDATE local SET codigo='TDA-004' WHERE codigo='SANTA_ANITA';
