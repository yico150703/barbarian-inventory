import unittest
from unittest.mock import MagicMock, patch

from flask_jwt_extended import create_access_token
from sqlalchemy.exc import IntegrityError

from app import create_app
from app.modules.usuarios.locales import validar, siguiente_codigo


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config.update(TESTING=True, JWT_SECRET_KEY='stores-test-secret-at-least-32-characters')
        self.client = self.app.test_client()
        self.data = {'nombre': 'Nueva tienda', 'direccion': 'Calle 123, Lima'}

    def headers(self, perfil=1):
        with self.app.app_context():
            token = create_access_token(identity='1', additional_claims={
                'id_perfil': perfil, 'tipo_token': 'operativo', 'id_local': 1})
        return {'Authorization': 'Bearer ' + token}

    def test_requires_authentication(self):
        self.assertEqual(self.client.post('/api/locales', json=self.data).status_code, 401)

    def test_manager_cannot_create_or_list_even_with_menu_permission(self):
        with patch('app.core.permissions.db.session.execute') as execute:
            execute.return_value.scalar.return_value = True
            for method in ('get', 'post'):
                response = getattr(self.client, method)('/api/locales', headers=self.headers(2), json=self.data)
                self.assertEqual(response.status_code, 403)
            self.assertEqual(execute.call_count, 2)  # Only permission checks, no local query.

    def test_revoked_permission_is_rejected(self):
        with patch('app.core.permissions.db.session.execute') as execute:
            execute.return_value.scalar.return_value = False
            self.assertEqual(self.client.post('/api/locales', headers=self.headers(), json=self.data).status_code, 403)

    def test_invalid_and_missing_fields(self):
        for changes in ({'direccion': ' '}, {'codigo': 'DOS PALABRAS'}, {'nombre': 'x' * 101},
                        {'direccion': 'x' * 251}, {'codigo': 123}, {'id_local': 2}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validar({**self.data, **changes})
        self.assertEqual(validar({**self.data, 'nombre': ' Nueva '})['nombre'], 'Nueva')

    def test_codes_are_automatic_and_zero_padded(self):
        for number, expected in ((1, 'TDA-001'), (2, 'TDA-002'), (1000, 'TDA-1000')):
            with patch('app.modules.usuarios.locales.db.session.execute') as execute:
                execute.return_value.scalar_one.return_value = number
                self.assertEqual(siguiente_codigo(), expected)
                self.assertIn('LOCK TABLE', str(execute.call_args_list[0].args[0]))

    def test_creation_is_audited_and_committed(self):
        auth, lock, number, insert = MagicMock(), MagicMock(), MagicMock(), MagicMock()
        auth.scalar.return_value = True
        number.scalar_one.return_value = 5
        insert.mappings.return_value.one.return_value = {**self.data, 'id_local': 9, 'estado_registro': 1}
        with patch('app.core.permissions.db.session.execute', side_effect=[auth, lock, number, insert]), \
             patch('app.modules.usuarios.locales.registrar_actividad') as audit, \
             patch('app.modules.usuarios.locales.db.session.commit') as commit:
            response = self.client.post('/api/locales', headers=self.headers(), json=self.data)
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json['local']['id_local'], 9)
        self.assertNotIn('id_local', audit.call_args.kwargs)
        commit.assert_called_once()

    def test_concurrent_duplicate_rolls_back(self):
        auth, lock, number = MagicMock(), MagicMock(), MagicMock()
        auth.scalar.return_value = True
        number.scalar_one.return_value = 5
        with patch('app.core.permissions.db.session.execute', side_effect=[
                auth, lock, number, IntegrityError('insert', {}, Exception('duplicate'))]), \
             patch('app.modules.usuarios.locales.db.session.rollback') as rollback:
            response = self.client.post('/api/locales', headers=self.headers(), json=self.data)
        self.assertEqual(response.status_code, 409)
        rollback.assert_called_once()

    def test_audit_failure_rolls_back_store(self):
        auth, lock, number, insert = MagicMock(), MagicMock(), MagicMock(), MagicMock()
        auth.scalar.return_value = True
        number.scalar_one.return_value = 5
        insert.mappings.return_value.one.return_value = {**self.data, 'id_local': 9, 'estado_registro': 1}
        with patch('app.core.permissions.db.session.execute', side_effect=[auth, lock, number, insert]), \
             patch('app.modules.usuarios.locales.registrar_actividad', side_effect=RuntimeError('audit')), \
             patch('app.modules.usuarios.locales.db.session.rollback') as rollback, \
             self.assertRaises(RuntimeError):
            self.client.post('/api/locales', headers=self.headers(), json=self.data)
        rollback.assert_called_once()

    def mutation(self, method, path, values, data=None):
        auth = MagicMock(); auth.scalar.return_value = True
        with patch('app.core.permissions.db.session.execute', side_effect=[auth, MagicMock(), *values]), \
             patch('app.modules.usuarios.locales.db.session.commit') as commit, \
             patch('app.modules.usuarios.locales.db.session.rollback'), \
             patch('app.modules.usuarios.locales.registrar_actividad'), \
             patch('app.modules.auditoria.service.registrar_cambio'):
            response = getattr(self.client, method)(path, headers=self.headers(), json=data)
        return response, commit.called

    def row(self, value):
        result = MagicMock()
        result.mappings.return_value.first.return_value = value
        result.mappings.return_value.one.return_value = value
        result.scalar.return_value = value
        return result

    def test_edit_updates_existing_store(self):
        store = {**self.data, 'id_local': 9, 'estado_registro': 1}
        response, committed = self.mutation('put', '/api/locales/9',
            [self.row(store), self.row(store)], self.data)
        self.assertEqual(response.status_code, 200)
        self.assertTrue(committed)

    def test_cannot_set_code_manually(self):
        with patch('app.core.permissions.db.session.execute') as execute:
            execute.return_value.scalar.return_value = True
            response = self.client.put('/api/locales/9', headers=self.headers(),
                json={**self.data, 'codigo': 'TDA-999'})
        self.assertEqual(response.status_code, 400)

    def test_last_active_store_cannot_be_disabled(self):
        response, committed = self.mutation('patch', '/api/locales/9/estado',
            [self.row({**self.data, 'estado_registro': 1}), self.row(1)], {'estado_registro': 0})
        self.assertEqual(response.status_code, 409)
        self.assertFalse(committed)

    def test_disable_and_reactivate(self):
        for before, after in ((1, 0), (0, 1)):
            store = {**self.data, 'id_local': 9, 'estado_registro': before}
            values = [self.row(store)] + ([self.row(4)] if before else [])
            values.append(self.row({**store, 'estado_registro': after}))
            response, committed = self.mutation('patch', '/api/locales/9/estado', values, {'estado_registro': after})
            self.assertEqual(response.status_code, 200)
            self.assertTrue(committed)

    def test_missing_store_returns_not_found(self):
        response, committed = self.mutation('delete', '/api/locales/9', [self.row(None)])
        self.assertEqual(response.status_code, 404)
        self.assertFalse(committed)

    def test_associated_store_cannot_be_deleted(self):
        relations = MagicMock()
        relations.mappings.return_value.all.return_value = [
            {'esquema': 'public', 'tabla': 'usuario_local', 'columna': 'id_local', 'columnas': 1}]
        with self.app.app_context():
            response, committed = self.mutation('delete', '/api/locales/9', [
                self.row({**self.data, 'estado_registro': 0}), relations, self.row(True)])
        self.assertEqual(response.status_code, 409)
        self.assertFalse(committed)

    def test_unused_store_can_be_deleted(self):
        relations = MagicMock(); relations.mappings.return_value.all.return_value = []
        with self.app.app_context():
            response, committed = self.mutation('delete', '/api/locales/9', [
                self.row({**self.data, 'estado_registro': 0}), relations, self.row(None)])
        self.assertEqual(response.status_code, 200)
        self.assertTrue(committed)

    def test_managers_cannot_mutate_stores(self):
        with patch('app.core.permissions.db.session.execute') as execute:
            execute.return_value.scalar.return_value = True
            for method, path in (('put', '/api/locales/9'), ('patch', '/api/locales/9/estado'), ('delete', '/api/locales/9')):
                self.assertEqual(getattr(self.client, method)(path, headers=self.headers(2), json=self.data).status_code, 403)
