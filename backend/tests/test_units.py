from decimal import Decimal
import os
import unittest
from unittest.mock import patch

from flask import Flask, jsonify
from flask_jwt_extended import create_access_token
from sqlalchemy import text
from app import create_app
from app.core.extensions import db
from app.core.units import (
    catalogo_unidades, convertir_cantidad, describir_medidas,
    normalizar_medida, obtener_unidad, registrar_medidas_api,
)
from app.modules.catalogos import service as catalogos
from app.modules.recetas.editor_service import DatosInvalidos, validar_componentes
from app.modules.recetas.editor_service import guardar_receta
from app.modules.produccion.subproduct_editor import guardar_subproducto
from app.modules.carta.presentation_editor import guardar_presentacion


class UnitCatalogTests(unittest.TestCase):
    def test_international_codes_and_legacy_aliases(self):
        for alias, codigo, simbolo in (("Kg", "KGM", "kg"), ("kg", "KGM", "kg"),
                ("KGM", "KGM", "kg"), ("L", "LTR", "L"), ("UNI", "C62", "unidad"),
                ("C62", "C62", "unidad"), ("g", "GRM", "g"), ("mL", "MLT", "mL")):
            with self.subTest(alias=alias):
                unidad = obtener_unidad(alias)
                self.assertEqual(unidad.codigo_unece, codigo)
                self.assertEqual(unidad.simbolo, simbolo)
        self.assertIsNone(obtener_unidad("PORCIÓN").codigo_unece)
        self.assertEqual(obtener_unidad("PORCION").codigo_base, "PORCION")

    def test_conversions_use_decimal(self):
        self.assertEqual(convertir_cantidad("750", "MLT", "LTR"), Decimal("0.750"))
        self.assertEqual(convertir_cantidad("60", "GRM", "KGM"), Decimal("0.060"))
        self.assertEqual(convertir_cantidad("0.060", "kg", "g"), Decimal("60"))
        self.assertEqual(normalizar_medida("2500", "g", "subproducto"), (Decimal("2.500"), "Kg"))

    def test_no_density_or_packaging_assumptions(self):
        for origen, destino in (("kg", "L"), ("UNI", "PORCIÓN"), ("caja", "UNI"), ("mL", "Kg")):
            with self.subTest(origen=origen), self.assertRaises(ValueError):
                convertir_cantidad(1, origen, destino)
        for valor in (None, True, "NaN", "Infinity", ""):
            with self.subTest(valor=valor), self.assertRaises(ValueError):
                convertir_cantidad(valor, "g", "kg")

    def test_contexts_and_base_units(self):
        self.assertEqual([u["valor"] for u in catalogo_unidades("producto", True)], ["KGM", "LTR", "C62"])
        self.assertNotIn("UNI", [u["valor"] for u in catalogo_unidades("subproducto")])
        with self.assertRaises(ValueError):
            normalizar_medida(1, "PORCIÓN", "producto")
        with self.assertRaises(ValueError):
            catalogo_unidades("otro")

    def test_product_package_normalization_and_precision(self):
        datos = {"nombre": "Aceite", "id_categoria": 1, "id_proveedor": 1,
                 "unidad": "LTR", "presentacion": 750, "unidad_presentacion": "mL"}
        self.assertEqual(catalogos._datos_producto(datos)[-1], Decimal("0.750"))
        self.assertEqual(catalogos._datos_producto(datos)[3], "LTR")
        self.assertIsNone(catalogos._datos_producto({**datos, "unidad_presentacion": "g"}))
        self.assertIsNone(catalogos._datos_producto({**datos, "presentacion": "0.5"}))
        self.assertIsNone(catalogos._datos_producto({**datos, "presentacion": "1000000000000"}))

    @patch("app.modules.recetas.editor_service.repo.ingrediente")
    def test_recipe_uses_explicit_quantity_unit_and_inventory_base(self, ingrediente):
        ingrediente.return_value = {"unidad": "Kg", "activo": True}
        datos = {"id": 1, "cantidad": "60", "unidad_cantidad": "g"}
        fila = validar_componentes([datos])[0]
        self.assertEqual(fila["unidad"], "Kg")
        self.assertEqual(fila["cantidad"], Decimal("0.060"))
        for cambios in ({"unidad_cantidad": "L"}, {"cantidad": "0.5"}):
            with self.subTest(cambios=cambios), self.assertRaises(DatosInvalidos):
                validar_componentes([{**datos, **cambios}])

    def test_api_metadata_keeps_legacy_values_and_quantities(self):
        original = {"productos": [{"unidad": "Kg", "cantidad": 1.5}],
                    "unidad_presentacion": "PORCIÓN", "unidad": None}
        datos = describir_medidas(original)
        self.assertEqual(datos["productos"][0]["unidad"], "KGM")
        self.assertEqual(datos["productos"][0]["cantidad"], 1.5)
        self.assertEqual(datos["productos"][0]["unidad_medida"]["codigo_unece"], "KGM")
        self.assertIsNone(datos["unidad_presentacion_medida"]["codigo_unece"])
        self.assertNotIn("unidad_medida", original["productos"][0])
        self.assertEqual(describir_medidas(datos), datos)

    def test_response_adapter_leaves_audit_errors_and_non_api_untouched(self):
        app = Flask(__name__)
        registrar_medidas_api(app)

        @app.get("/api/prueba")
        @app.get("/api/actividades")
        @app.get("/prueba")
        def ejemplo():
            return jsonify({"unidad": "L", "cantidad": 0.75})

        @app.get("/api/error")
        def error():
            return jsonify({"unidad": "L"}), 400

        with app.test_client() as cliente:
            respuesta = cliente.get("/api/prueba")
            self.assertEqual(respuesta.json["unidad_medida"]["codigo_unece"], "LTR")
            self.assertEqual(int(respuesta.headers["Content-Length"]), len(respuesta.data))
            for ruta in ("/api/actividades", "/prueba", "/api/error"):
                self.assertNotIn("unidad_medida", cliente.get(ruta).json)

    def test_product_base_cannot_be_reinterpreted(self):
        datos = {"nombre": "Aceite", "id_categoria": 1, "id_proveedor": 1,
                 "unidad": "L", "presentacion": 1}
        with patch.object(catalogos, "repo") as repo, patch.object(catalogos, "db"):
            repo.obtener_producto.return_value = {"unidad": "Kg"}
            resultado, estado = catalogos.editar_producto_catalogo(1, 1, datos)
            self.assertEqual(estado, 409, resultado)
            repo.actualizar_producto_registro.assert_not_called()


@unittest.skipUnless(os.environ.get("LOCAL_SCOPE_TEST_DB") == "1", "Requiere PostgreSQL temporal")
class UnitDatabaseTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config.update(TESTING=True, JWT_SECRET_KEY="unit-tests-secret-at-least-32-characters")
        self.contexto = self.app.app_context()
        self.contexto.push()
        self.assertEqual(db.session.execute(text("SELECT current_database()")).scalar(), "barbarito_test")
        db.session.execute(text("""
            INSERT INTO categoria_carta(id_categoria_carta,nombre,prefijo) VALUES(9301,'Medidas prueba','UM');
            INSERT INTO menaje(id_menaje,nombre) VALUES(9301,'Envase prueba unidades');
            INSERT INTO producto(id_producto,codigo,nombre,id_categoria,id_proveedor,unidad,presentacion,stock_minimo)
            VALUES(9301,'UM-9301','Ingrediente masa prueba',1,1,'Kg',1,0);
        """))
        db.session.commit()
        self.subproductos = []
        self.carta = {"id_item_carta": None, "nombre_item": "Bebida prueba unidades",
                      "id_categoria_carta": 9301, "tipo_item": "PREPARADO", "contenido": "750",
                      "unidad": "MLT", "id_menaje": 9301, "precio": "10.00", "activo": True}

    def tearDown(self):
        db.session.rollback()
        db.session.execute(text("""
            DELETE FROM receta_detalle WHERE id_receta IN (SELECT r.id_receta FROM receta r
                JOIN presentacion_venta pv USING(id_presentacion_venta) WHERE pv.id_menaje=9301);
            DELETE FROM receta WHERE id_presentacion_venta IN
                (SELECT id_presentacion_venta FROM presentacion_venta WHERE id_menaje=9301);
            DELETE FROM presentacion_venta WHERE id_menaje=9301;
            DELETE FROM item_carta WHERE id_categoria_carta=9301;
            DELETE FROM categoria_carta WHERE id_categoria_carta=9301;
            DELETE FROM menaje WHERE id_menaje=9301;
        """))
        for identidad in self.subproductos:
            db.session.execute(text("DELETE FROM subproducto_detalle WHERE id_subproducto=:id"), {"id": identidad})
            db.session.execute(text("DELETE FROM subproducto WHERE id_subproducto=:id"), {"id": identidad})
        db.session.execute(text("DELETE FROM producto WHERE id_producto=9301"))
        db.session.commit()
        db.session.remove()
        self.contexto.pop()

    def test_presentation_and_recipe_conversions_persist_consistent_units(self):
        resultado, estado = guardar_presentacion(1, self.carta)
        self.assertEqual(estado, 201, resultado)
        identidad = resultado["id_presentacion_venta"]
        fila = db.session.execute(text("SELECT contenido,unidad FROM presentacion_venta WHERE id_presentacion_venta=:id"), {"id": identidad}).mappings().one()
        self.assertEqual((fila["contenido"], fila["unidad"]), (Decimal("0.750"), "L"))
        resultado, estado = guardar_receta(1, {
            "id_presentacion_venta": identidad, "instrucciones": "Mezclar ingredientes",
            "componentes": [{"id": 9301, "tipo_componente": "PRODUCTO", "cantidad": "60", "unidad_cantidad": "GRM"}],
        })
        self.assertEqual(estado, 201, resultado)
        fila = db.session.execute(text("SELECT cantidad,unidad FROM receta_detalle WHERE id_receta=:id"), {"id": resultado["id_receta"]}).mappings().one()
        self.assertEqual((fila["cantidad"], fila["unidad"]), (Decimal("0.060"), "Kg"))

    def test_subproduct_normalizes_yield_and_ingredient(self):
        resultado, estado = guardar_subproducto(1, {
            "nombre": "Preparación prueba unidades", "rendimiento": "2500", "unidad": "g",
            "instruccion": "Mezclar", "ingredientes": [{"id": 9301, "cantidad": "60", "unidad_cantidad": "g"}],
        })
        self.assertEqual(estado, 201, resultado)
        identidad = resultado["id_subproducto"]
        self.subproductos.append(identidad)
        fila = db.session.execute(text("SELECT rendimiento,unidad FROM subproducto WHERE id_subproducto=:id"), {"id": identidad}).mappings().one()
        self.assertEqual((fila["rendimiento"], fila["unidad"]), (Decimal("2.500"), "Kg"))
        fila = db.session.execute(text("SELECT cantidad,unidad FROM subproducto_detalle WHERE id_subproducto=:id"), {"id": identidad}).mappings().one()
        self.assertEqual((fila["cantidad"], fila["unidad"]), (Decimal("0.060"), "Kg"))

    def test_unit_api_permissions_and_metadata_from_actual_database(self):
        cliente = self.app.test_client()
        self.assertEqual(cliente.get("/api/catalogos/unidades").status_code, 401)
        token = create_access_token(identity="1", additional_claims={"tipo_token": "operativo", "id_perfil": 1, "id_local": 1})
        headers = {"Authorization": "Bearer " + token}
        respuesta = cliente.get("/api/catalogos/unidades?contexto=producto", headers=headers)
        self.assertEqual(respuesta.status_code, 200, respuesta.json)
        self.assertEqual({u["codigo"] for u in respuesta.json["unidades"]}, {"KGM", "GRM", "LTR", "MLT", "C62"})
        self.assertEqual(cliente.get("/api/catalogos/unidades?contexto=incorrecto", headers=headers).status_code, 400)
        respuesta = cliente.get("/api/produccion/subproductos/formulario", headers=headers)
        self.assertEqual(respuesta.status_code, 200, respuesta.json)
        producto = next(p for p in respuesta.json["productos"] if p["id"] == 9301)
        self.assertEqual(producto["unidad_medida"]["codigo_unece"], "KGM")
