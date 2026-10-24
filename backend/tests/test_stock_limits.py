import unittest
from decimal import Decimal
from unittest.mock import patch

from flask_jwt_extended import create_access_token, verify_jwt_in_request

from app import create_app
from app.core.extensions import db
from app.core.stock_local import minimo_del_local
from app.modules.catalogos.service import crear_producto_catalogo, editar_producto_catalogo
from app.modules.catalogos.stock_limits import validar_limites


class StockLimitsTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config.update(TESTING=True, JWT_SECRET_KEY="test-only-key-with-at-least-32-characters")
        self.context = self.app.app_context()
        self.context.push()
        self.client = self.app.test_client()

    def tearDown(self):
        self.context.pop()

    def headers(self, perfil, tipo="operativo", local=1):
        token = create_access_token(identity="1", additional_claims={
            "tipo_token": tipo, "id_perfil": perfil, "id_local": local,
        })
        return {"Authorization": f"Bearer {token}"}

    def test_validacion(self):
        self.assertEqual(validar_limites({"stock_minimo": 0, "stock_maximo": "0.001"}), (Decimal(0), Decimal("0.001")))
        self.assertEqual(validar_limites({"stock_minimo": "1.125", "stock_maximo": 5}), (Decimal("1.125"), Decimal(5)))
        for datos in [None, [], {}, {"stock_minimo": 5, "stock_maximo": 4},
                      {"stock_minimo": 0, "stock_maximo": 0},
                      {"stock_minimo": 5, "stock_maximo": 5},
                      {"stock_minimo": "1.125", "stock_maximo": "1.125"},
                      {"stock_minimo": -1, "stock_maximo": 4},
                      {"stock_minimo": "NaN", "stock_maximo": 4},
                      {"stock_minimo": 0, "stock_maximo": "Infinity"},
                      {"stock_minimo": 0, "stock_maximo": None},
                      {"stock_minimo": "0.0001", "stock_maximo": 1},
                      {"stock_minimo": 0, "stock_maximo": 1000000000}]:
            with self.subTest(datos=datos):
                self.assertIsNone(validar_limites(datos))

    def test_exige_sesion(self):
        self.assertEqual(self.client.get('/api/catalogos/limites-stock').status_code, 401)

    def test_otros_perfiles_denegados_incluso_con_permiso_accidental(self):
        with patch.object(db.session, 'execute') as execute:
            execute.return_value.scalar.return_value = True
            for perfil in [1, 3, 4]:
                with self.subTest(perfil=perfil):
                    headers = self.headers(perfil)
                    self.assertEqual(self.client.get('/api/catalogos/limites-stock', headers=headers).status_code, 403)
                    self.assertEqual(self.client.put('/api/catalogos/limites-stock/1', headers=headers,
                                                    json={'stock_minimo': 1, 'stock_maximo': 5}).status_code, 403)

    def test_gerente_necesita_permiso_vigente(self):
        with patch.object(db.session, 'execute') as execute:
            execute.return_value.scalar.return_value = False
            self.assertEqual(self.client.get('/api/catalogos/limites-stock', headers=self.headers(2)).status_code, 403)

    def test_gerente_puede_consultar(self):
        with patch.object(db.session, 'execute') as execute:
            execute.return_value.scalar.return_value = True
            execute.return_value.mappings.return_value.all.return_value = []
            response = self.client.get('/api/catalogos/limites-stock', headers=self.headers(2))
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json, {'productos': [], 'id_local': 1})
            self.assertEqual(execute.call_args.args[1], {'local': 1})

    def test_limites_invalidos_no_escriben(self):
        with patch.object(db.session, 'execute') as execute, patch.object(db.session, 'commit') as commit:
            execute.return_value.scalar.return_value = True
            response = self.client.put('/api/catalogos/limites-stock/1', headers=self.headers(2),
                                       json={'stock_minimo': 5, 'stock_maximo': 1})
            self.assertEqual(response.status_code, 400)
            self.assertEqual(execute.call_count, 2)  # Permisos y asignación de local.
            commit.assert_not_called()

    def test_catalogo_rechaza_limites_sin_escribir(self):
        with patch.object(db.session, 'execute') as execute:
            for campo in ['stock_minimo', 'stock_maximo']:
                self.assertEqual(crear_producto_catalogo(1, {campo: 2})[1], 403)
                self.assertEqual(editar_producto_catalogo(1, 1, {campo: 2})[1], 403)
            execute.assert_not_called()

    def test_guardar_registra_auditoria_y_confirma(self):
        with patch.object(db.session, 'execute') as execute, \
                patch.object(db.session, 'commit') as commit, \
                patch('app.modules.catalogos.stock_limits.registrar_cambio') as auditoria, \
                patch('app.modules.catalogos.stock_limits.registrar_actividad') as actividad:
            execute.return_value.scalar.return_value = True
            execute.return_value.mappings.return_value.first.return_value = {
                'id_producto': 1, 'codigo': 'TEST', 'stock_minimo': Decimal('2'), 'stock_maximo': None,
            }
            response = self.client.put('/api/catalogos/limites-stock/1', headers=self.headers(2),
                                       json={'stock_minimo': 3, 'stock_maximo': 10})
            self.assertEqual(response.status_code, 200)
            self.assertEqual(execute.call_args.args[1], {'id': 1, 'local': 1, 'minimo': Decimal(3), 'maximo': Decimal(10)})
            auditoria.assert_called_once()
            self.assertEqual(auditoria.call_args.args[5], {'id_local': 1, 'stock_minimo': '2', 'stock_maximo': None})
            self.assertEqual(auditoria.call_args.args[6], {'id_local': 1, 'stock_minimo': '3', 'stock_maximo': '10'})
            self.assertEqual(auditoria.call_args.kwargs['id_local'], 1)
            actividad.assert_called_once()
            commit.assert_called_once()

    def test_fallo_auditoria_revierte_cambio(self):
        with patch.object(db.session, 'execute') as execute, \
                patch.object(db.session, 'commit') as commit, \
                patch.object(db.session, 'rollback') as rollback, \
                patch('app.modules.catalogos.stock_limits.registrar_cambio', side_effect=RuntimeError('fallo')):
            execute.return_value.scalar.return_value = True
            execute.return_value.mappings.return_value.first.return_value = {
                'id_producto': 1, 'codigo': 'TEST', 'stock_minimo': 2, 'stock_maximo': None,
            }
            with self.assertRaises(RuntimeError):
                self.client.put('/api/catalogos/limites-stock/1', headers=self.headers(2),
                                json={'stock_minimo': 3, 'stock_maximo': 10})
            commit.assert_not_called()
            rollback.assert_called_once()

    def test_local_no_asignado_denegado(self):
        with patch.object(db.session, 'execute') as execute:
            for method in ['get', 'put']:
                execute.return_value.scalar.side_effect = [True, False]
                response = getattr(self.client, method)('/api/catalogos/limites-stock' + ('/1' if method == 'put' else ''),
                                                        headers=self.headers(2, local=9))
                self.assertEqual(response.status_code, 403)

    def test_no_se_puede_enviar_otro_local(self):
        with patch.object(db.session, 'execute') as execute, patch.object(db.session, 'commit') as commit:
            execute.return_value.scalar.return_value = True
            response = self.client.put('/api/catalogos/limites-stock/1', headers=self.headers(2),
                                       json={'id_local': 2, 'stock_minimo': 1, 'stock_maximo': 5})
            self.assertEqual(response.status_code, 400)
            commit.assert_not_called()

    def test_local_invalido_denegado(self):
        with patch.object(db.session, 'execute') as execute:
            execute.return_value.scalar.return_value = True
            for local in [None, 0, -1, '2', True]:
                self.assertEqual(self.client.get('/api/catalogos/limites-stock', headers=self.headers(2, local=local)).status_code, 403)

    def test_local_del_token_prevalece_sobre_query_string(self):
        with patch.object(db.session, 'execute') as execute:
            execute.return_value.scalar.return_value = True
            execute.return_value.mappings.return_value.all.return_value = []
            for local in [1, 2]:
                response = self.client.get('/api/catalogos/limites-stock?id_local=99', headers=self.headers(2, local=local))
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.json['id_local'], local)
                self.assertEqual(execute.call_args.args[1], {'local': local})

    def test_minimo_operativo_usa_local_sesion(self):
        for local in [1, 2]:
            with self.app.test_request_context(headers=self.headers(2, local=local)), \
                    patch.object(db.session, 'execute') as execute:
                verify_jwt_in_request()
                execute.return_value.scalar.return_value = True
                expresion, parametros = minimo_del_local()
                self.assertIn('producto_stock_local', expresion)
                self.assertEqual(parametros, {'id_local_stock': local})

    def test_consultas_compatibles_antes_de_migrar(self):
        with self.app.test_request_context(headers=self.headers(2)), patch.object(db.session, 'execute') as execute:
            verify_jwt_in_request()
            execute.return_value.scalar.return_value = False
            self.assertEqual(minimo_del_local(), ('p.stock_minimo', {}))


if __name__ == '__main__':
    unittest.main()
