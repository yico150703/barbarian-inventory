import re

from sqlalchemy import text

from app.core.extensions import db
from app.core.units import catalogo_unidades, valores_unidades


def filas(sql, parametros=None):
    return [dict(f) for f in db.session.execute(text(sql), parametros or {}).mappings().all()]


def ejecutar(sql, parametros=None):
    return db.session.execute(text(sql), parametros or {})


def opciones_check(nombre):
    definicion = ejecutar("""
        SELECT pg_get_constraintdef(oid) FROM pg_constraint
        WHERE conname = :nombre AND connamespace = 'public'::regnamespace
    """, {"nombre": nombre}).scalar_one()
    return re.findall(r"'([^']+)'::character varying", definicion)


def formulario():
    return {
        "tipos": opciones_check("ck_item_carta_tipo"),
        "unidades_presentacion": valores_unidades("presentacion"),
        "unidades_medida": catalogo_unidades(),
        "categorias": filas("SELECT id_categoria_carta, nombre, activo FROM categoria_carta ORDER BY nombre"),
        "menajes": filas("SELECT id_menaje, nombre, activo FROM menaje ORDER BY nombre"),
        "items": filas("SELECT id_item_carta, codigo, nombre, id_categoria_carta, tipo, activo FROM item_carta ORDER BY nombre"),
        "presentaciones": filas("""
            SELECT pv.id_presentacion_venta, pv.id_item_carta, pv.id_menaje,
                   pv.contenido, pv.unidad, pv.activo, r.id_receta
            FROM presentacion_venta pv LEFT JOIN receta r USING (id_presentacion_venta)
            WHERE r.id_receta IS NULL
            ORDER BY pv.id_item_carta, pv.contenido
        """),
        "productos": filas("SELECT id_producto AS id, codigo, nombre, unidad, activo FROM producto ORDER BY nombre"),
        "subproductos": filas("SELECT id_subproducto AS id, codigo, nombre, unidad, activo FROM subproducto ORDER BY nombre"),
    }


def buscar_receta(id_receta):
    resultados = filas("""
        SELECT r.*, pv.id_item_carta, pv.contenido, pv.unidad, pv.id_menaje,
               ic.tipo, ic.nombre, ic.id_categoria_carta
        FROM receta r JOIN presentacion_venta pv USING(id_presentacion_venta)
        JOIN item_carta ic USING(id_item_carta)
        WHERE r.id_receta = :id FOR UPDATE OF r, pv, ic
    """, {"id": id_receta})
    return resultados[0] if resultados else None


def detalles(id_receta):
    return filas("SELECT * FROM receta_detalle WHERE id_receta=:id ORDER BY id_receta_detalle", {"id": id_receta})


def grupo(id_presentacion):
    resultados = filas("SELECT * FROM grupo_salsa WHERE id_presentacion_venta=:id FOR UPDATE", {"id": id_presentacion})
    if not resultados:
        return None
    resultado = resultados[0]
    resultado["opciones"] = filas("SELECT * FROM grupo_salsa_opcion WHERE id_grupo_salsa=:id ORDER BY id_producto", {"id": resultado["id_grupo_salsa"]})
    return resultado


def ingrediente(tipo, identidad):
    tabla, columna = ("producto", "id_producto") if tipo == "PRODUCTO" else ("subproducto", "id_subproducto")
    resultados = filas(f"SELECT {columna} AS id, codigo, nombre, unidad, activo FROM {tabla} WHERE {columna}=:id FOR SHARE", {"id": identidad})
    return resultados[0] if resultados else None


def reemplazar_detalles(id_receta, componentes):
    ejecutar("DELETE FROM receta_detalle WHERE id_receta=:id", {"id": id_receta})
    for c in componentes:
        ejecutar("""
            INSERT INTO receta_detalle (id_receta, tipo_componente, id_producto, id_subproducto, cantidad, unidad)
            VALUES (:receta, :tipo, :producto, :subproducto, :cantidad, :unidad)
        """, {"receta": id_receta, "tipo": c["tipo_componente"],
              "producto": c["id"] if c["tipo_componente"] == "PRODUCTO" else None,
              "subproducto": c["id"] if c["tipo_componente"] == "SUBPRODUCTO" else None,
              "cantidad": c["cantidad"], "unidad": c["unidad"]})


def guardar_grupo(id_presentacion, configuracion):
    if configuracion is None:
        ejecutar("UPDATE grupo_salsa SET activo=FALSE WHERE id_presentacion_venta=:id", {"id": id_presentacion})
        return
    id_grupo = ejecutar("""
        INSERT INTO grupo_salsa (id_presentacion_venta, cantidad_maxima, permite_repetir, activo)
        VALUES (:id, :maximo, :repetir, TRUE)
        ON CONFLICT (id_presentacion_venta) DO UPDATE
        SET cantidad_maxima=EXCLUDED.cantidad_maxima, permite_repetir=EXCLUDED.permite_repetir, activo=TRUE
        RETURNING id_grupo_salsa
    """, {"id": id_presentacion, "maximo": configuracion["cantidad_maxima"], "repetir": configuracion["permite_repetir"]}).scalar_one()
    ejecutar("UPDATE grupo_salsa_opcion SET activo=FALSE WHERE id_grupo_salsa=:id", {"id": id_grupo})
    for opcion in configuracion["opciones"]:
        ejecutar("""
            INSERT INTO grupo_salsa_opcion (id_grupo_salsa,id_producto,cantidad,unidad,activo)
            VALUES (:grupo,:producto,:cantidad,:unidad,TRUE)
            ON CONFLICT (id_grupo_salsa,id_producto) DO UPDATE
            SET cantidad=EXCLUDED.cantidad, unidad=EXCLUDED.unidad, activo=TRUE
        """, {"grupo": id_grupo, "producto": opcion["id"], "cantidad": opcion["cantidad"], "unidad": opcion["unidad"]})
