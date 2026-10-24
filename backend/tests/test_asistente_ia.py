import json
import os
import unittest
from unittest.mock import patch
from flask_jwt_extended import create_access_token
from sqlalchemy import text
from app import create_app
from app.core.extensions import db
from app.modules.asistente_ia import routes, tools


def proposal(resource='menajes', action='crear', identity=None, data=None):
    return [{'type': 'function_call', 'call_id': 'test-call', 'name': 'preparar_cambio',
             'arguments': json.dumps({'recurso': resource, 'accion': action, 'id': identity,
                                      'datos_json': json.dumps(data or {'nombre': 'IA prueba'})})}]


@unittest.skipUnless(os.environ.get('LOCAL_SCOPE_TEST_DB') == '1', 'Solo PostgreSQL temporal')
class AssistantIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config.update(TESTING=True, JWT_SECRET_KEY='assistant-integration-secret-32-characters')
        self.ctx = self.app.app_context(); self.ctx.push()
        self.assertEqual(db.session.execute(text('SELECT current_database()')).scalar(), 'barbarito_test')
        self.client = self.app.test_client()
        self.headers = self.token(1)
        routes._attempts.clear()
        db.session.execute(text('UPDATE perfil_opcion_menu SET puede_editar=true,puede_crear=true,puede_consultar=true WHERE id_perfil=1'))
        db.session.commit()

    def tearDown(self):
        db.session.rollback()
        db.session.execute(text('DELETE FROM asistente_ia_borrador'))
        db.session.execute(text('''DELETE FROM receta_detalle WHERE id_receta IN
          (SELECT r.id_receta FROM receta r JOIN presentacion_venta p USING(id_presentacion_venta)
           JOIN item_carta i USING(id_item_carta) WHERE i.id_categoria_carta=9995)'''))
        db.session.execute(text('''DELETE FROM receta WHERE id_presentacion_venta IN
          (SELECT p.id_presentacion_venta FROM presentacion_venta p JOIN item_carta i USING(id_item_carta)
           WHERE i.id_categoria_carta=9995)'''))
        db.session.execute(text('DELETE FROM presentacion_venta WHERE id_item_carta IN (SELECT id_item_carta FROM item_carta WHERE id_categoria_carta=9995)'))
        db.session.execute(text('DELETE FROM item_carta WHERE id_categoria_carta=9995'))
        db.session.execute(text('DELETE FROM categoria_carta WHERE id_categoria_carta=9995'))
        db.session.execute(text("DELETE FROM menaje WHERE nombre LIKE 'IA %'"))
        db.session.execute(text('UPDATE perfil_opcion_menu SET puede_editar=true,puede_crear=true,puede_consultar=true WHERE id_perfil=1'))
        db.session.commit(); db.session.remove(); self.ctx.pop()

    def token(self, user, local=1):
        return {'Authorization': 'Bearer ' + create_access_token(identity=str(user), additional_claims={
            'tipo_token': 'operativo', 'id_perfil': user, 'id_local': local})}

    def prepare(self, output=None, **data):
        with patch('app.modules.asistente_ia.provider.respond', return_value=output or proposal()):
            return self.client.post('/api/asistente-ia/preparar', headers=self.headers,
                                    json={'instruccion': 'Crear un menaje IA prueba', **data})

    def perform(self, identity, headers=None, **data):
        return self.client.post('/api/asistente-ia/realizar', headers=headers or self.headers,
                                json={'id': identity, 'confirmar': True, **data})

    def test_prepare_does_not_write_and_execute_once_with_native_audit(self):
        r = self.prepare(); self.assertEqual(r.status_code, 200, r.json)
        self.assertEqual(r.json['agente'], 'carta_recetas')
        identity = r.json['borrador']['id_borrador']
        self.assertEqual(db.session.execute(text("SELECT count(*) FROM menaje WHERE nombre='IA prueba'")).scalar(), 0)
        self.assertEqual(self.perform(identity, confirmar=False).status_code, 400)
        first = self.perform(identity); self.assertEqual(first.status_code, 200, first.json)
        self.assertEqual(self.perform(identity).json, first.json)
        self.assertEqual(db.session.execute(text("SELECT count(*) FROM menaje WHERE nombre='IA prueba'")).scalar(), 1)
        self.assertEqual(db.session.execute(text("SELECT estado FROM asistente_ia_borrador WHERE id=:id"), {'id': identity}).scalar(), 'REALIZADO')

    def test_revoked_permission_cannot_confirm(self):
        identity = self.prepare().json['borrador']['id_borrador']
        db.session.execute(text('UPDATE perfil_opcion_menu SET puede_crear=false WHERE id_perfil=1 AND id_opcion_menu=10'))
        db.session.commit()
        self.assertEqual(self.perform(identity).status_code, 403)

    def test_wrong_user_and_local_cannot_reuse_draft(self):
        identity = self.prepare().json['borrador']['id_borrador']
        self.assertEqual(self.perform(identity, self.token(2)).status_code, 404)
        self.assertEqual(self.perform(identity, self.token(1, 2)).status_code, 404)

    def test_expiration_cancellation_and_unknown_outcome_do_not_execute(self):
        identity = self.prepare().json['borrador']['id_borrador']
        db.session.execute(text("UPDATE asistente_ia_borrador SET vence_en=now()-interval '1 minute' WHERE id=:id"), {'id': identity}); db.session.commit()
        self.assertEqual(self.perform(identity).status_code, 409)
        for state in ('CANCELADO', 'EJECUTANDO', 'FALLIDO'):
            db.session.execute(text('UPDATE asistente_ia_borrador SET estado=:state WHERE id=:id'), {'id': identity, 'state': state}); db.session.commit()
            self.assertEqual(self.perform(identity).status_code, 409)

    def test_correction_invalidates_old_plan_and_keeps_new_values(self):
        old = self.prepare().json['borrador']['id_borrador']
        corrected = self.prepare(proposal(data={'nombre': 'IA corregido'}), reemplaza=old,
                                 borrador_previo='Crear menaje IA prueba', instruccion='El nombre es IA corregido')
        self.assertEqual(corrected.status_code, 200, corrected.json)
        self.assertEqual(self.perform(old).status_code, 409)
        self.assertEqual(self.perform(corrected.json['borrador']['id_borrador']).status_code, 200)

    def test_stale_record_does_not_overwrite_new_data(self):
        row = db.session.execute(text("INSERT INTO menaje(nombre) VALUES('IA original') RETURNING id_menaje")).scalar(); db.session.commit()
        r = self.prepare(proposal(action='editar', identity=row, data={'nombre': 'IA editado'}))
        self.assertEqual(r.status_code, 200, r.json)
        db.session.execute(text("UPDATE menaje SET nombre='IA otro usuario' WHERE id_menaje=:id"), {'id': row}); db.session.commit()
        self.assertEqual(self.perform(r.json['borrador']['id_borrador']).status_code, 409)

    def test_native_validation_does_not_mark_failed_write_as_success(self):
        # The service rejects a duplicate. Confirmation cannot circumvent it.
        db.session.execute(text("INSERT INTO menaje(nombre) VALUES('IA prueba')")); db.session.commit()
        r = self.prepare(); identity = r.json['borrador']['id_borrador']
        response = self.perform(identity)
        self.assertEqual(response.status_code, 409, response.json)
        self.assertEqual(db.session.execute(text('SELECT estado FROM asistente_ia_borrador WHERE id=:id'), {'id': identity}).scalar(), 'FALLIDO')

    def test_manager_cannot_prepare_catalog_change_even_when_menu_grants_write(self):
        self.headers = self.token(2)
        with patch('app.modules.asistente_ia.provider.respond', side_effect=[proposal(),
                [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'Tu perfil no permite crear menajes.'}]}]]):
            r = self.client.post('/api/asistente-ia/preparar', headers=self.headers, json={'instruccion': 'Crear menaje'})
        self.assertEqual(r.status_code, 200, r.json)
        self.assertIsNone(r.json['borrador'])
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM asistente_ia_borrador')).scalar(), 0)

    def test_query_uses_scoped_native_route_and_strips_personal_fields(self):
        output = [{'type': 'function_call', 'call_id': 'query', 'name': 'consultar',
                   'arguments': json.dumps({'recurso': 'usuarios', 'busqueda': '', 'desde': 0})}]
        self.headers = self.token(2)
        with patch('app.modules.asistente_ia.provider.respond', side_effect=[output,
                [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'Usuarios del local.'}]}]]):
            r = self.client.post('/api/asistente-ia/preparar', headers=self.headers, json={'instruccion': 'Consultar usuarios'})
        self.assertEqual(r.status_code, 200, r.json)
        rows = r.json['consultas'][0]['registros']
        for row in rows:
            self.assertNotIn('dni', row); self.assertNotIn('clave', row); self.assertNotIn('correo_electronico', row)

    def test_catalog_agent_receives_only_catalog_tools(self):
        answer = [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'Consulta terminada.'}]}]
        with patch('app.modules.asistente_ia.provider.respond', side_effect=[answer]) as model:
            response = self.client.post('/api/asistente-ia/preparar', headers=self.headers,
                json={'instruccion': 'Consulta promociones'})
        self.assertEqual(response.status_code, 200, response.json)
        self.assertEqual(response.json['agente'], 'carta_recetas')
        names = {tool['name'] for tool in model.call_args.args[1]}
        self.assertIn('consultar', names)
        self.assertIn('preparar_cambio', names)
        self.assertNotIn('consultar_inventario', names)

    def test_agent_directory_is_only_visible_to_system_admin(self):
        response = self.client.get('/api/asistente-ia/agentes', headers=self.headers)
        self.assertEqual(response.status_code, 200, response.json)
        self.assertEqual({agent['id'] for agent in response.json['agentes']}, {'carta_recetas', 'inventario'})
        catalog = next(agent for agent in response.json['agentes'] if agent['id'] == 'carta_recetas')
        self.assertTrue(catalog['skills'][0]['contenido'])
        self.assertIn('orquestador', catalog['relaciones'])
        self.assertEqual(self.client.get('/api/asistente-ia/agentes', headers=self.token(2)).status_code, 403)

    def test_inventory_agent_receives_inventory_tools_and_queries_active_store(self):
        self.headers = self.token(2)
        calls = [{'type': 'function_call', 'call_id': 'inventory-stock',
                  'name': 'consultar_inventario', 'arguments': json.dumps({
                      'recurso': 'stock', 'filtros_json': json.dumps({'busqueda': 'Producto compartido'})})}]
        answer = [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'Stock consultado.'}]}]
        with patch('app.modules.asistente_ia.provider.respond', side_effect=[calls, answer]) as model:
            response = self.client.post('/api/asistente-ia/preparar', headers=self.headers,
                json={'instruccion': 'Consulta el stock de Producto compartido'})
        self.assertEqual(response.status_code, 200, response.json)
        self.assertEqual(response.json['agente'], 'inventario')
        self.assertEqual(response.json['consultas'][0]['recurso'], 'stock')
        names = {tool['name'] for tool in model.call_args.args[1]}
        self.assertIn('consultar_inventario', names)
        self.assertIn('preparar_cambio', names)
        self.assertNotIn('formulario', names)
        self.assertNotIn('consultar', names)

    def test_inventory_arbitrary_routes_and_unknown_fields_are_rejected(self):
        with self.app.test_request_context(headers=self.headers):
            from flask_jwt_extended import verify_jwt_in_request
            verify_jwt_in_request()
            session = {'menu': [{'id_opcion_menu': 10, 'permisos': {'consultar': True, 'crear': True}}]}
            with self.assertRaises(ValueError): tools.query(session, '../inventarios')
            with self.assertRaises(ValueError): tools.prepare(session, 'menajes', 'crear', None, {'nombre': 'IA prueba', 'sql': 'anything'})

    def test_provider_failure_returns_safe_message_and_no_writes(self):
        from app.modules.asistente_ia.provider import AssistantError
        with patch('app.modules.asistente_ia.provider.respond', side_effect=AssistantError('Sin saldo', 502)):
            r = self.client.post('/api/asistente-ia/preparar', headers=self.headers, json={'instruccion': 'Consulta'})
        self.assertEqual(r.status_code, 502); self.assertEqual(r.json['mensaje'], 'Sin saldo')

    def test_unknown_write_outcome_remains_claimed_and_is_not_replayed(self):
        from app.modules.asistente_ia.provider import AssistantError
        identity = self.prepare().json['borrador']['id_borrador']
        with patch('app.modules.asistente_ia.tools.execute', side_effect=AssistantError('Fallo interno', 500)) as execute:
            self.assertEqual(self.perform(identity).status_code, 503)
            self.assertEqual(self.perform(identity).status_code, 409)
            execute.assert_called_once()
        self.assertEqual(db.session.execute(text('SELECT estado FROM asistente_ia_borrador WHERE id=:id'), {'id': identity}).scalar(), 'EJECUTANDO')

    def test_audio_requires_auth_and_valid_file_and_stays_editable_text(self):
        from io import BytesIO
        self.assertEqual(self.client.post('/api/asistente-ia/transcribir').status_code, 401)
        self.assertEqual(self.client.post('/api/asistente-ia/transcribir', headers=self.headers).status_code, 400)
        with patch('app.modules.asistente_ia.provider.transcribe', return_value='Consulta las recetas') as audio:
            r = self.client.post('/api/asistente-ia/transcribir', headers=self.headers,
                data={'audio': (BytesIO(b'fake audio'), 'dictado.webm', 'audio/webm')})
        self.assertEqual(r.status_code, 200, r.json)
        self.assertEqual(r.json['texto'], 'Consulta las recetas'); audio.assert_called_once()

    def test_article_presentation_recipe_and_partial_edits_follow_native_flow(self):
        db.session.execute(text("INSERT INTO categoria_carta(id_categoria_carta,nombre,prefijo) VALUES(9995,'IA categoria','AI')"))
        mid = db.session.execute(text("INSERT INTO menaje(nombre) VALUES('IA vaso') RETURNING id_menaje")).scalar()
        db.session.commit()
        data = {'id_item_carta': None, 'nombre_item': 'IA bebida', 'tipo_item': 'DIRECTO',
                'id_categoria_carta': 9995, 'contenido': 1, 'unidad': 'UNI', 'id_menaje': mid,
                'precio': 10, 'activo': True}
        r = self.prepare(proposal('presentaciones', data=data)); self.assertEqual(r.status_code, 200, r.json)
        self.assertIn('IA categoria', r.json['borrador']['vista']['id_categoria_carta'])
        saved = self.perform(r.json['borrador']['id_borrador']); self.assertEqual(saved.status_code, 200, saved.json)
        pid = saved.json['id_presentacion_venta']
        recipe = {'id_presentacion_venta': pid, 'instrucciones': 'Servir',
                  'componentes': [{'tipo_componente': 'PRODUCTO', 'id': 1, 'cantidad': 1}], 'grupo_salsa': None}
        r = self.prepare(proposal('recetas', data=recipe)); self.assertEqual(r.status_code, 200, r.json)
        saved = self.perform(r.json['borrador']['id_borrador']); self.assertEqual(saved.status_code, 200, saved.json)
        rid = saved.json['id_receta']
        r = self.prepare(proposal('presentaciones', 'editar', pid, {'precio': 12.5}))
        self.assertEqual(r.status_code, 200, r.json)
        self.assertEqual(r.json['borrador']['datos']['nombre_item'], 'IA bebida')
        self.assertEqual(self.perform(r.json['borrador']['id_borrador']).status_code, 200)
        r = self.prepare(proposal('recetas', 'editar', rid, {'instrucciones': 'Servir frio'}))
        self.assertEqual(r.status_code, 200, r.json)
        self.assertEqual(r.json['borrador']['datos']['componentes'][0]['cantidad'], 1)
        self.assertEqual(self.perform(r.json['borrador']['id_borrador']).status_code, 200)
        self.assertEqual(float(db.session.execute(text('SELECT precio FROM presentacion_venta WHERE id_presentacion_venta=:id'), {'id': pid}).scalar()), 12.5)
