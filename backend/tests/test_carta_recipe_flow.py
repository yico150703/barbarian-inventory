import os
import unittest
from unittest.mock import patch

from flask_jwt_extended import create_access_token
from sqlalchemy import text

from app import create_app
from app.core.extensions import db
from app.modules.carta.presentation_editor import guardar_presentacion
from app.modules.carta.tableware_admin import guardar_menaje
from app.modules.recetas.editor_service import guardar_receta, obtener_formulario


@unittest.skipUnless(os.environ.get('LOCAL_SCOPE_TEST_DB') == '1', 'Requiere PostgreSQL temporal')
class CartaRecipeFlowTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config.update(TESTING=True, JWT_SECRET_KEY='carta-flow-test-secret-at-least-32-characters')
        self.context = self.app.app_context()
        self.context.push()
        self.assertEqual(db.session.execute(text('SELECT current_database()')).scalar(), 'barbarito_test')
        db.session.execute(text("INSERT INTO categoria_carta(id_categoria_carta,nombre,prefijo) VALUES (9001,'Categoria flujo','FL')"))
        db.session.execute(text("INSERT INTO categoria_carta(id_categoria_carta,nombre,prefijo) VALUES (9002,'Categoria destino','FD')"))
        db.session.execute(text("INSERT INTO menaje(id_menaje,nombre) VALUES (9001,'Plato flujo')"))
        db.session.commit()
        self.data = {'id_item_carta': None, 'nombre_item': 'Plato flujo', 'id_categoria_carta': 9001,
                     'tipo_item': 'PREPARADO', 'contenido': '1', 'unidad': 'UNI', 'id_menaje': 9001,
                     'precio': '15.50', 'activo': False}

    def tearDown(self):
        db.session.rollback()
        db.session.execute(text('DELETE FROM receta_detalle WHERE id_receta IN (SELECT r.id_receta FROM receta r JOIN presentacion_venta pv USING(id_presentacion_venta) WHERE pv.id_menaje=9001)'))
        db.session.execute(text('DELETE FROM receta WHERE id_presentacion_venta IN (SELECT id_presentacion_venta FROM presentacion_venta WHERE id_menaje=9001)'))
        db.session.execute(text('DELETE FROM presentacion_venta WHERE id_menaje=9001'))
        db.session.execute(text('DELETE FROM item_carta WHERE id_categoria_carta IN (9001,9002)'))
        db.session.execute(text('DELETE FROM categoria_carta WHERE id_categoria_carta IN (9001,9002)'))
        db.session.execute(text('DELETE FROM menaje WHERE id_menaje=9001'))
        db.session.commit()
        db.session.remove()
        self.context.pop()

    def crear(self):
        result, status = guardar_presentacion(1, self.data)
        self.assertEqual(status, 201, result)
        return result['id_presentacion_venta']

    def test_tableware_assigned_inactive_presentation_blocks_delete_and_deactivate(self):
        self.crear()
        for accion in ('desactivar', 'eliminar'):
            resultado, estado = guardar_menaje(1, accion, {}, 9001)
            self.assertEqual(estado, 409, resultado)
        self.assertEqual(guardar_menaje(1, 'editar', {'nombre':'Plato renombrado'}, 9001)[1],200)

    def test_tableware_create_duplicate_state_delete_and_audit_rollback(self):
        result,status = guardar_menaje(1,'crear',{'nombre':'Menaje nuevo'})
        self.assertEqual(status,201,result)
        identidad = result['id_menaje']
        try:
            self.assertEqual(guardar_menaje(1,'crear',{'nombre':'  MENAJE NUEVO  '})[1],409)
            self.assertEqual(guardar_menaje(1,'editar',{'nombre':' '},identidad)[1],400)
            self.assertEqual(guardar_menaje(1,'desactivar',{},identidad)[1],200)
            self.assertFalse(db.session.execute(text('SELECT activo FROM menaje WHERE id_menaje=:id'),{'id':identidad}).scalar())
            self.assertEqual(guardar_menaje(1,'reactivar',{},identidad)[1],200)
            with patch('app.modules.carta.tableware_admin.registrar_actividad',side_effect=RuntimeError('fallo')):
                with self.assertRaises(RuntimeError):
                    guardar_menaje(1,'eliminar',{},identidad)
            self.assertTrue(db.session.execute(text('SELECT activo FROM menaje WHERE id_menaje=:id'),{'id':identidad}).scalar())
            self.assertEqual(guardar_menaje(1,'eliminar',{},identidad)[1],200)
            self.assertEqual(guardar_menaje(1,'editar',{'nombre':'Otro'},identidad)[1],404)
        finally:
            db.session.execute(text('DELETE FROM menaje WHERE id_menaje=:id'),{'id':identidad})
            db.session.commit()

    def test_tableware_http_permissions(self):
        client=self.app.test_client()
        self.assertEqual(client.post('/api/carta/menajes',json={'nombre':'Nuevo'}).status_code,401)
        db.session.execute(text('UPDATE perfil_opcion_menu SET puede_crear=true,puede_editar=true,puede_eliminar=true WHERE id_opcion_menu=10'))
        db.session.commit()
        for perfil,status in ((2,403),(1,200)):
            token=create_access_token(identity=str(perfil),additional_claims={'tipo_token':'operativo','id_perfil':perfil,'id_local':1})
            headers={'Authorization':'Bearer '+token}
            response=client.post('/api/carta/menajes/9001/editar',json={'nombre':'Plato editado'},headers=headers)
            self.assertEqual(response.status_code,status,response.json)
        db.session.execute(text('UPDATE perfil_opcion_menu SET puede_eliminar=false WHERE id_perfil=1 AND id_opcion_menu=10'))
        db.session.commit()
        self.assertEqual(client.post('/api/carta/menajes/9001/eliminar',json={},headers=headers).status_code,403)

    def receta(self, presentacion):
        return {'id_presentacion_venta': presentacion, 'instrucciones': 'Preparar y servir', 'activo': False,
                'componentes': [{'tipo_componente':'PRODUCTO','id':1,'cantidad':'2'}], 'grupo_salsa':None}

    def test_full_flow_inactive_recipe_cannot_be_duplicated_and_states_are_independent(self):
        presentacion = self.crear()
        self.assertIn(presentacion, [p['id_presentacion_venta'] for p in obtener_formulario()[0]['presentaciones']])
        result, status = guardar_receta(1, self.receta(presentacion))
        self.assertEqual(status, 201, result)
        self.assertNotIn(presentacion, [p['id_presentacion_venta'] for p in obtener_formulario()[0]['presentaciones']])
        self.assertEqual(guardar_receta(1, self.receta(presentacion))[1], 400)
        self.assertEqual(guardar_receta(1, {**self.receta(presentacion), 'activo':True}, result['id_receta'])[1], 200)
        self.assertFalse(db.session.execute(text('SELECT activo FROM presentacion_venta WHERE id_presentacion_venta=:id'), {'id':presentacion}).scalar())
        self.assertEqual(guardar_presentacion(1, {**self.data, 'activo':True, 'precio':'20'}, presentacion)[1], 200)
        self.assertTrue(db.session.execute(text('SELECT activo FROM receta WHERE id_receta=:id'), {'id':result['id_receta']}).scalar())
        self.assertEqual(db.session.execute(text('SELECT cantidad FROM receta_detalle WHERE id_receta=:id'), {'id':result['id_receta']}).scalar(), 2)

    def test_duplicate_presentations_and_shared_item_permissions(self):
        presentacion = self.crear()
        item = db.session.execute(text('SELECT id_item_carta FROM presentacion_venta WHERE id_presentacion_venta=:id'), {'id':presentacion}).scalar()
        datos = {**self.data, 'id_item_carta':item}
        self.assertEqual(guardar_presentacion(1, datos)[1], 409)
        self.assertEqual(guardar_presentacion(1, {**datos, 'contenido':'2', 'nombre_item':'Cambio indebido'})[1], 400)
        self.assertEqual(guardar_presentacion(1, {**datos, 'contenido':'2'})[1], 201)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM item_carta WHERE id_categoria_carta=9001')).scalar(), 1)
        self.assertEqual(guardar_presentacion(1, self.data)[1], 400)

    def test_recipe_cannot_create_or_edit_commercial_data(self):
        self.assertEqual(guardar_receta(1, self.receta(None))[1], 400)
        presentacion = self.crear()
        for campo in ('tipo_item','nombre_item','contenido','unidad_presentacion','id_menaje'):
            self.assertEqual(guardar_receta(1, {**self.receta(presentacion), campo:'CAMBIO'})[1], 400)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM receta')).scalar(), 0)
        self.assertEqual(guardar_presentacion(1, {**self.data,'precio':'NaN'}, presentacion)[1],400)

    def test_audit_failure_rolls_back_item_presentation_and_counter(self):
        with patch('app.modules.carta.presentation_editor.registrar_cambio', side_effect=RuntimeError('fallo')):
            with self.assertRaises(RuntimeError):
                guardar_presentacion(1, self.data)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM item_carta WHERE id_categoria_carta=9001')).scalar(),0)
        self.assertEqual(db.session.execute(text('SELECT siguiente_numero FROM categoria_carta WHERE id_categoria_carta=9001')).scalar(),1)

    def test_http_permissions_and_create(self):
        client = self.app.test_client()
        self.assertEqual(client.post('/api/carta/presentaciones',json=self.data).status_code,401)
        db.session.execute(text('UPDATE perfil_opcion_menu SET puede_crear=false,puede_editar=false WHERE id_perfil=2 AND id_opcion_menu=9'))
        db.session.commit()
        manager = create_access_token(identity='2',additional_claims={'tipo_token':'operativo','id_perfil':2,'id_local':1})
        headers = {'Authorization':'Bearer '+manager}
        self.assertEqual(client.post('/api/carta/presentaciones',json=self.data,headers=headers).status_code,403)
        self.assertEqual(client.put('/api/carta/presentaciones/1',json=self.data,headers=headers).status_code,403)
        admin = create_access_token(identity='1',additional_claims={'tipo_token':'operativo','id_perfil':1,'id_local':1})
        headers = {'Authorization':'Bearer '+admin}
        self.assertEqual(client.get('/api/carta/presentaciones/formulario',headers=headers).status_code,200)
        response = client.post('/api/carta/presentaciones',json=self.data,headers=headers)
        self.assertEqual(response.status_code,201,response.json)

    def test_edit_category_preserves_code_and_recipe_and_rejects_inactive_destination(self):
        presentacion = self.crear()
        original = db.session.execute(text('SELECT codigo FROM item_carta WHERE id_categoria_carta=9001')).scalar()
        result, status = guardar_receta(1, self.receta(presentacion))
        self.assertEqual(status, 201, result)
        respuesta, status = guardar_presentacion(1, {**self.data, 'id_categoria_carta':9002}, presentacion)
        self.assertEqual(status, 200, respuesta)
        self.assertEqual(db.session.execute(text('SELECT codigo FROM item_carta WHERE id_categoria_carta=9002')).scalar(), original)
        self.assertEqual(db.session.execute(text('SELECT id_receta FROM receta WHERE id_presentacion_venta=:id'), {'id':presentacion}).scalar(), result['id_receta'])
        db.session.execute(text('UPDATE categoria_carta SET activo=false WHERE id_categoria_carta=9001'))
        db.session.commit()
        self.assertEqual(guardar_presentacion(1, self.data, presentacion)[1],400)
        # Editar ingredientes sin enviar estado no reactiva una receta antigua.
        entrada = self.receta(presentacion)
        del entrada['activo']
        self.assertEqual(guardar_receta(1, entrada, result['id_receta'])[1],200)
        self.assertFalse(db.session.execute(text('SELECT activo FROM receta WHERE id_receta=:id'), {'id':result['id_receta']}).scalar())
