import os
import unittest
from unittest.mock import patch

from flask_jwt_extended import create_access_token
from sqlalchemy import text

from app import create_app
from app.core.extensions import db
from app.modules.carta.category_admin import modificar_categoria


@unittest.skipUnless(os.environ.get('LOCAL_SCOPE_TEST_DB') == '1', 'Requiere PostgreSQL temporal')
class MenuCategoryAdminTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config.update(TESTING=True, JWT_SECRET_KEY='category-test-secret-at-least-32-characters')
        self.context = self.app.app_context()
        self.context.push()
        self.assertEqual(db.session.execute(text('SELECT current_database()')).scalar(), 'barbarito_test')
        db.session.execute(text("INSERT INTO categoria_carta(id_categoria_carta,nombre,prefijo) VALUES (8001,'Origen prueba','AAA'),(8002,'Destino prueba','BBB')"))
        db.session.execute(text("INSERT INTO item_carta(id_item_carta,codigo,nombre,id_categoria_carta,tipo,activo) VALUES (8001,'AAA-001','Articulo prueba',8001,'PREPARADO',false)"))
        db.session.commit()

    def tearDown(self):
        db.session.rollback()
        db.session.execute(text('DELETE FROM item_carta WHERE id_item_carta=8001'))
        db.session.execute(text('DELETE FROM categoria_carta WHERE id_categoria_carta IN (8001,8002)'))
        db.session.commit()
        db.session.remove()
        self.context.pop()

    def test_assigned_inactive_item_blocks_edit_and_deactivation(self):
        for accion in ('editar', 'desactivar'):
            self.assertEqual(modificar_categoria(8001, 1, accion, {'nombre': 'Cambio', 'prefijo': 'NEW'})[1], 409)
        self.assertTrue(db.session.execute(text('SELECT activo FROM categoria_carta WHERE id_categoria_carta=8001')).scalar())

    def test_create_category_and_reject_duplicates(self):
        token = create_access_token(identity='1', additional_claims={'tipo_token':'operativo','id_perfil':1,'id_local':1})
        client = self.app.test_client()
        data = {'nombre':'Categoria nueva', 'prefijo':'CN'}
        response = client.post('/api/carta/categorias', json=data, headers={'Authorization':'Bearer '+token})
        self.assertEqual(response.status_code,201,response.json)
        identidad = response.json['id_categoria_carta']
        try:
            fila = db.session.execute(text('SELECT activo,siguiente_numero FROM categoria_carta WHERE id_categoria_carta=:id'),{'id':identidad}).one()
            self.assertEqual(tuple(fila),(True,1))
            self.assertEqual(modificar_categoria(0,1,'crear',data)[1],409)
            self.assertEqual(modificar_categoria(0,1,'crear',{'nombre':'Otra','prefijo':'CN'})[1],409)
            self.assertEqual(modificar_categoria(0,1,'crear',{'nombre':'','prefijo':'?'})[1],400)
        finally:
            db.session.execute(text('DELETE FROM categoria_carta WHERE id_categoria_carta=:id'),{'id':identidad})
            db.session.commit()

    def test_create_rolls_back_on_audit_failure(self):
        with patch('app.modules.carta.category_admin.registrar_actividad',side_effect=RuntimeError('fallo')):
            with self.assertRaises(RuntimeError):
                modificar_categoria(0,1,'crear',{'nombre':'Fallo nueva','prefijo':'FN'})
        self.assertFalse(db.session.execute(text("SELECT EXISTS(SELECT 1 FROM categoria_carta WHERE prefijo='FN')")).scalar())

    def test_reassign_preserves_codes_then_allows_edit_and_state(self):
        self.assertEqual(modificar_categoria(8001, 1, 'reasignar', {'id_categoria_nueva': 8002})[1], 200)
        item = db.session.execute(text('SELECT codigo,id_categoria_carta FROM item_carta WHERE id_item_carta=8001')).one()
        self.assertEqual(tuple(item), ('AAA-001', 8002))
        self.assertEqual(modificar_categoria(8001, 1, 'editar', {'nombre': 'Vacia', 'prefijo': 'AAA'})[1], 200)
        self.assertEqual(db.session.execute(text('SELECT siguiente_numero FROM categoria_carta WHERE id_categoria_carta=8001')).scalar(), 2)
        self.assertEqual(modificar_categoria(8001, 1, 'desactivar', {})[1], 200)
        self.assertFalse(db.session.execute(text('SELECT activo FROM categoria_carta WHERE id_categoria_carta=8001')).scalar())
        self.assertEqual(modificar_categoria(8001, 1, 'reactivar', {})[1], 200)

    def test_invalid_destinations_duplicates_and_payloads(self):
        for destino in (8001, 999999, True, '8002', None):
            self.assertEqual(modificar_categoria(8001, 1, 'reasignar', {'id_categoria_nueva': destino})[1], 400)
        db.session.execute(text('UPDATE categoria_carta SET activo=false WHERE id_categoria_carta=8002'))
        db.session.commit()
        self.assertEqual(modificar_categoria(8001, 1, 'reasignar', {'id_categoria_nueva': 8002})[1], 400)
        self.assertEqual(modificar_categoria(8002, 1, 'editar', {'nombre': 'Origen prueba', 'prefijo': 'BBB'})[1], 409)
        self.assertEqual(modificar_categoria(8002, 1, 'editar', {'nombre': '', 'prefijo': 'A-1'})[1], 400)
        self.assertEqual(modificar_categoria(999999, 1, 'editar', {})[1], 404)
        self.assertEqual(modificar_categoria(8002, 1, 'editar', [1])[1], 400)

    def test_audit_failure_rolls_back_reassignment(self):
        with patch('app.modules.carta.category_admin.registrar_actividad', side_effect=RuntimeError('fallo')):
            with self.assertRaises(RuntimeError):
                modificar_categoria(8001, 1, 'reasignar', {'id_categoria_nueva': 8002})
        self.assertEqual(db.session.execute(text('SELECT id_categoria_carta FROM item_carta WHERE id_item_carta=8001')).scalar(), 8001)

    def test_http_admin_only(self):
        # Autoriza permisos en el fixture para comprobar ademas la restriccion de perfil.
        db.session.execute(text('UPDATE perfil_opcion_menu SET puede_editar=true,puede_desactivar=true,puede_reactivar=true WHERE id_opcion_menu=8 AND id_perfil IN (1,2)'))
        db.session.commit()
        client = self.app.test_client()
        self.assertEqual(client.post('/api/carta/categorias/8002/editar', json={}).status_code, 401)
        for perfil, expected in ((2,403),(1,200)):
            token = create_access_token(identity=str(perfil), additional_claims={'tipo_token':'operativo','id_perfil':perfil,'id_local':1})
            response = client.post('/api/carta/categorias/8002/editar', json={'nombre':'Destino editado','prefijo':'BBB'}, headers={'Authorization':f'Bearer {token}'})
            self.assertEqual(response.status_code, expected, response.json)
