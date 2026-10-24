import os
import unittest

from flask_jwt_extended import create_access_token
from sqlalchemy import text
from app import create_app
from app.core.extensions import db
from app.modules.catalogos import repository as repo
from app.modules.catalogos.service import obtener_catalogo_productos, obtener_proveedores


@unittest.skipUnless(os.environ.get("LOCAL_SCOPE_TEST_DB") == "1", "Requiere PostgreSQL temporal")
class CatalogSchemaCompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config.update(TESTING=True, JWT_SECRET_KEY="catalog-schema-tests-secret-at-least-32-chars")
        self.context = self.app.app_context()
        self.context.push()
        self.assertEqual(db.session.execute(text("SELECT current_database()")).scalar(), "barbarito_test")
        # Solo la copia temporal. El rollback restaura cualquier tabla previa.
        db.session.execute(text("DROP TABLE IF EXISTS proveedor_categoria"))

    def tearDown(self):
        db.session.rollback()
        db.session.remove()
        self.context.pop()

    def test_catalogs_load_without_supplier_category_table(self):
        self.assertFalse(repo.categorias_proveedor_disponibles())
        for consultar in (obtener_catalogo_productos, obtener_proveedores):
            datos, estado = consultar()
            self.assertEqual(estado, 200)
            self.assertFalse(datos["categorias_proveedor_configurables"])
            proveedor = next(p for p in datos["proveedores"] if p["id_proveedor"] == 1)
            self.assertEqual(proveedor["ids_categorias"], [1])
        self.assertEqual(repo.categorias_proveedor(1), [1])

    def test_explicit_assignments_take_priority_when_table_exists(self):
        db.session.execute(text("""
            CREATE TABLE proveedor_categoria (
                id_proveedor INTEGER REFERENCES proveedor(id_proveedor),
                id_categoria INTEGER REFERENCES categoria_producto(id_categoria),
                PRIMARY KEY(id_proveedor,id_categoria)
            );
            INSERT INTO proveedor_categoria VALUES(2,1);
        """))
        self.assertTrue(repo.categorias_proveedor_disponibles())
        datos, estado = obtener_proveedores()
        self.assertEqual(estado, 200)
        proveedor = next(p for p in datos["proveedores"] if p["id_proveedor"] == 2)
        self.assertEqual(proveedor["ids_categorias"], [1])
        self.assertEqual(proveedor["categorias"], ["Prueba"])
        self.assertEqual(proveedor["total_productos"], 0)

    def test_missing_migration_returns_readable_json_with_cors(self):
        with self.assertRaises(repo.CategoriasProveedorNoDisponibles):
            repo.asignar_categorias_proveedor(1, [1])
        token = create_access_token(identity="1", additional_claims={
            "tipo_token": "operativo", "id_perfil": 1, "id_local": 1,
        })
        cliente = self.app.test_client()
        headers = {"Authorization": "Bearer " + token, "Origin": "http://localhost:5173"}
        for ruta in ("productos", "proveedores"):
            respuesta = cliente.get("/api/catalogos/" + ruta, headers=headers)
            self.assertEqual(respuesta.status_code, 200, respuesta.json)
            self.assertIn("Access-Control-Allow-Origin", respuesta.headers)
        # La ruta pasa por permisos y rollback; no escribe cambios incompletos.
        respuesta = cliente.put("/api/catalogos/proveedores/1", headers=headers,
            json={"nombre": "Proveedor original", "ids_categorias": [1]})
        self.assertEqual(respuesta.status_code, 503, respuesta.json)
        self.assertIn("20261010_proveedor_categorias.sql", respuesta.json["mensaje"])
        self.assertIn("Access-Control-Allow-Origin", respuesta.headers)
