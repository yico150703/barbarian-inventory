import unittest
from unittest.mock import patch
from app.modules.catalogos import service


class SupplierCategoryTests(unittest.TestCase):
    def test_supplier_requires_categories(self):
        for ids in (None, [], [True], ["1"], [0]):
            result, status = service.crear_proveedor_catalogo(1, {"nombre": "Proveedor", "ids_categorias": ids})
            self.assertEqual(status, 400, result)
        self.assertEqual(service._categorias_proveedor_validas({"ids_categorias": [2, 1, 2]}), [1, 2])

    def test_supplier_categories_saved_without_products(self):
        with patch.object(service, "repo") as repo, patch.object(service, "db") as db, patch.object(service, "registrar_cambio"), patch.object(service, "registrar_actividad"):
            repo.proveedor_repetido.return_value = False
            repo.obtener_categoria.return_value = {"activo": True}
            repo.crear_proveedor.return_value = 9
            repo.obtener_proveedor.return_value = {"id_proveedor": 9, "nombre": "Proveedor", "activo": True}
            result, status = service.crear_proveedor_catalogo(1, {"nombre": "Proveedor", "ids_categorias": [1, 2]})
            self.assertEqual(status, 201, result)
            repo.asignar_categorias_proveedor.assert_called_once_with(9, [1, 2])
            db.session.commit.assert_called_once()

    def test_cannot_remove_category_used_by_product(self):
        with patch.object(service, "repo") as repo, patch.object(service, "db"):
            repo.obtener_proveedor.return_value = {"id_proveedor": 9, "nombre": "Proveedor", "activo": True}
            repo.proveedor_repetido.return_value = False
            repo.categorias_proveedor.return_value = [1, 2]
            repo.obtener_categoria.return_value = {"activo": True}
            repo.productos_proveedor.return_value = [{"id_categoria": 2, "activo": False}]
            result, status = service.editar_proveedor_catalogo(9, 1, {"nombre": "Proveedor", "ids_categorias": [1]})
            self.assertEqual(status, 409, result)
            repo.asignar_categorias_proveedor.assert_not_called()

    def test_product_rejects_category_outside_supplier(self):
        datos = {"nombre": "Producto", "id_categoria": 2, "id_proveedor": 9, "unidad": "UNI", "presentacion": 1}
        with patch.object(service, "repo") as repo, patch.object(service, "db"):
            repo.producto_repetido.return_value = False
            repo.obtener_proveedor.return_value = {"activo": True}
            repo.obtener_producto.return_value = {"id_producto": 1, "unidad": "UNI"}
            repo.obtener_categoria.return_value = {"activo": True}
            repo.categorias_proveedor.return_value = [1]
            self.assertEqual(service.crear_producto_catalogo(1, datos)[1], 409)
            self.assertEqual(service.editar_producto_catalogo(1, 1, datos)[1], 409)
            repo.crear_producto_registro.assert_not_called()
            repo.actualizar_producto_registro.assert_not_called()

    def test_inactive_categories_only_preserved_when_already_assigned(self):
        with patch.object(service, "repo") as repo:
            repo.obtener_categoria.return_value = {"activo": False}
            self.assertFalse(service._validar_categorias_proveedor([1]))
            self.assertTrue(service._validar_categorias_proveedor([1], [1]))
