"""Catálogo de medidas: símbolos SI/BIPM y códigos UNECE Recommendation 20.

La migración sustituye identificadores históricos por códigos estándar sin tocar
cantidades. Una porción nunca equivale automáticamente a una pieza.
"""
from dataclasses import dataclass
from decimal import Decimal, DecimalException, InvalidOperation


@dataclass(frozen=True)
class Unidad:
    codigo: str
    valor: str
    nombre: str
    simbolo: str
    dimension: str
    codigo_unece: str | None
    codigo_base: str
    factor_a_base: Decimal = Decimal("1")

    def serializar(self):
        return {
            "codigo": self.codigo, "valor": self.codigo,
            "nombre": self.nombre, "simbolo": self.simbolo,
            "dimension": self.dimension, "codigo_unece": self.codigo_unece,
            "codigo_base": self.codigo_base,
            "factor_a_base": str(self.factor_a_base),
            "estandar": "UNECE Rec. 20" if self.codigo_unece else "LOCAL",
        }


CATALOGO = (
    Unidad("KGM", "Kg", "Kilogramo", "kg", "MASA", "KGM", "KGM"),
    Unidad("GRM", "g", "Gramo", "g", "MASA", "GRM", "KGM", Decimal("0.001")),
    Unidad("LTR", "L", "Litro", "L", "VOLUMEN", "LTR", "LTR"),
    Unidad("MLT", "mL", "Mililitro", "mL", "VOLUMEN", "MLT", "LTR", Decimal("0.001")),
    Unidad("C62", "UNI", "Unidad", "unidad", "CONTEO", "C62", "C62"),
    Unidad("PORCION", "PORCIÓN", "Porción", "porción", "CONTEO", None, "PORCION"),
)
_ALIAS = {}
for _unidad in CATALOGO:
    for _alias in (_unidad.codigo, _unidad.valor, _unidad.simbolo):
        _ALIAS[_alias] = _unidad
_ALIAS.update({"ml": _ALIAS["MLT"], "l": _ALIAS["LTR"], "PORCION": _ALIAS["PORCIÓN"]})

_BASES = {
    "producto": {"KGM", "LTR", "C62"},
    "subproducto": {"KGM", "LTR", "PORCION"},
    "presentacion": {"KGM", "LTR", "C62", "PORCION"},
}


def obtener_unidad(valor):
    return _ALIAS.get(valor.strip()) if isinstance(valor, str) else None


def catalogo_unidades(contexto=None, solo_base=False):
    if contexto is not None and contexto not in _BASES:
        raise ValueError("Contexto de unidades inválido")
    return [u.serializar() for u in CATALOGO
            if (contexto is None or u.codigo_base in _BASES[contexto])
            and (not solo_base or u.codigo == u.codigo_base)]


def valores_unidades(contexto, solo_base=False):
    return [u["valor"] for u in catalogo_unidades(contexto, solo_base)]


def unidad_base(valor, contexto):
    unidad = obtener_unidad(valor)
    if unidad is None or unidad.codigo_base not in _BASES[contexto]:
        raise ValueError("Selecciona una unidad válida")
    return _ALIAS[unidad.codigo_base].valor


def convertir_cantidad(cantidad, origen, destino):
    anterior, nueva = obtener_unidad(origen), obtener_unidad(destino)
    if anterior is None or nueva is None:
        raise ValueError("Unidad de medida desconocida")
    # Misma base, además de dimensión: porciones y piezas no son intercambiables.
    if anterior.codigo_base != nueva.codigo_base:
        raise ValueError("Las unidades no son compatibles; necesitan una equivalencia por producto")
    try:
        valor = Decimal(str(cantidad))
        if not valor.is_finite():
            raise InvalidOperation
        return valor * anterior.factor_a_base / nueva.factor_a_base
    except (DecimalException, TypeError, ValueError):
        raise ValueError("Cantidad inválida") from None


def normalizar_medida(cantidad, unidad, contexto):
    base = unidad_base(unidad, contexto)
    return convertir_cantidad(cantidad, unidad, base), base


def unidad_almacenamiento(valor):
    """Escribe códigos UNECE tras la migración y admite bases aún sin actualizar."""
    from sqlalchemy import text
    from app.core.extensions import db
    unidad = obtener_unidad(valor)
    if unidad is None:
        raise ValueError("Unidad desconocida")
    actualizado = db.session.execute(text(
        "SELECT to_regclass('public.unidad_medida') IS NOT NULL"
    )).scalar_one()
    return unidad.codigo if actualizado else unidad.valor


def describir_medidas(datos):
    """Expone códigos estables y sus símbolos, también sobre bases sin migrar."""
    if isinstance(datos, list):
        return [describir_medidas(d) for d in datos]
    if not isinstance(datos, dict):
        return datos
    resultado = {k: describir_medidas(v) for k, v in datos.items()}
    for campo in ("unidad", "unidad_presentacion"):
        unidad = obtener_unidad(datos.get(campo))
        if unidad is not None:
            resultado[campo] = unidad.codigo
            resultado[f"{campo}_medida"] = unidad.serializar()
    return resultado


def registrar_medidas_api(app):
    # Un único adaptador cubre los serializers de inventario, compras y recetas.
    # No se reescribe el contenido histórico de auditoría.
    from flask import request

    @app.after_request
    def describir_unidades_respuesta(respuesta):
        if (request.path.startswith("/api/")
                and not request.path.startswith("/api/actividades")
                and respuesta.is_json and 200 <= respuesta.status_code < 300):
            datos = respuesta.get_json()
            enriquecidos = describir_medidas(datos)
            if enriquecidos != datos:
                respuesta.set_data(app.json.dumps(enriquecidos))
        return respuesta
