import os
import unittest
from unittest.mock import patch

from flask_jwt_extended import create_access_token
from sqlalchemy import text

from app import create_app
from app.core.extensions import db
from app.modules.produccion.subproduct_editor import guardar_subproducto
from app.modules.produccion.service import obtener_subproductos


@unittest.skipUnless(os.environ.get('LOCAL_SCOPE_TEST_DB') == '1', 'Requiere PostgreSQL temporal')
class SubproductEditorTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config.update(TESTING=True, JWT_SECRET_KEY='subproduct-test-secret-at-least-32-characters')
        self.context = self.app.app_context()
        self.context.push()
        self.assertEqual(db.session.execute(text('SELECT current_database()')).scalar(), 'barbarito_test')
        self.data = {'nombre': 'Preparacion de prueba', 'rendimiento': '2.5', 'unidad': 'Kg',
                     'instruccion': 'Mezclar y cocinar.', 'activo': True,
                     'ingredientes': [{'id': 1, 'cantidad': '0.5', 'unidad': 'UNIDAD_FALSA'}]}

    def tearDown(self):
        db.session.rollback()
        db.session.execute(text('DELETE FROM subproducto_detalle'))
        db.session.execute(text('DELETE FROM subproducto'))
        db.session.execute(text('UPDATE producto SET activo=true WHERE id_producto=1'))
        db.session.commit()
        db.session.remove()
        self.context.pop()

    def test_create_edit_and_authoritative_unit(self):
        resultado, estado = guardar_subproducto(1, self.data)
        self.assertEqual(estado,201,resultado)
        identidad=resultado['id_subproducto']
        detalle=db.session.execute(text('SELECT cantidad,unidad FROM subproducto_detalle WHERE id_subproducto=:id'),{'id':identidad}).mappings().one()
        self.assertEqual(detalle['unidad'],'C62')
        original=resultado['codigo']
        datos={**self.data,'nombre':'Nombre editado','rendimiento':'3',
               'ingredientes':[{'id':1,'cantidad':'1.125'}]}
        respuesta,estado=guardar_subproducto(1,datos,identidad)
        self.assertEqual(estado,200,respuesta)
        self.assertEqual(respuesta['codigo'],original)
        listado,_=obtener_subproductos()
        item=next(s for s in listado['subproductos'] if s['id_subproducto']==identidad)
        self.assertEqual(item['instruccion'],'Mezclar y cocinar.')
        self.assertEqual(item['ingredientes'][0]['cantidad'],1.125)
        self.assertEqual(item['rendimiento'],3)

    def test_invalid_quantities_duplicates_and_non_inventory(self):
        for ingredients in [[], [{'id':1,'cantidad':0}], [{'id':1,'cantidad':'NaN'}],
                [{'id':1,'cantidad':'0.0001'}], [{'id':1,'cantidad':1}]*2,
                [{'id':1,'cantidad':1,'tipo_componente':'SUBPRODUCTO'}],
                [{'id':999999,'cantidad':1}]]:
            with self.subTest(ingredients=ingredients):
                result,status=guardar_subproducto(1,{**self.data,'ingredientes':ingredients})
                self.assertEqual(status,400,result)
        for value in ['Infinity',-1,'0.0001',0]:
            self.assertEqual(guardar_subproducto(1,{**self.data,'rendimiento':value})[1],400)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM subproducto')).scalar(),0)

    def test_edit_preserves_existing_inactive_ingredient(self):
        result,status=guardar_subproducto(1,self.data)
        self.assertEqual(status,201)
        db.session.execute(text('UPDATE producto SET activo=false WHERE id_producto=1'))
        db.session.commit()
        self.assertEqual(guardar_subproducto(1,self.data,result['id_subproducto'])[1],200)
        self.assertEqual(guardar_subproducto(1,{**self.data,'nombre':'Otra preparacion'})[1],400)

    def test_unit_cannot_reinterpret_existing_quantities(self):
        result,status=guardar_subproducto(1,self.data)
        self.assertEqual(status,201)
        self.assertEqual(guardar_subproducto(1,{**self.data,'unidad':'L'},result['id_subproducto'])[1],400)
        self.assertEqual(db.session.execute(text('SELECT unidad FROM subproducto')).scalar(),'Kg')

    def test_duplicate_name_and_missing_record(self):
        self.assertEqual(guardar_subproducto(1,self.data)[1],201)
        self.assertEqual(guardar_subproducto(1,{**self.data,'nombre':'  PREPARACION DE PRUEBA  '})[1],400)
        self.assertEqual(guardar_subproducto(1,self.data,999999)[1],404)

    def test_failure_rolls_back_header_and_details(self):
        with patch('app.modules.produccion.subproduct_editor.registrar_cambio', side_effect=RuntimeError('Prueba')):
            with self.assertRaises(RuntimeError): guardar_subproducto(1,self.data)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM subproducto')).scalar(),0)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM subproducto_detalle')).scalar(),0)

    def test_permissions_and_api_save(self):
        db.session.execute(text('UPDATE perfil_opcion_menu SET puede_crear=false,puede_editar=false WHERE id_perfil=2 AND id_opcion_menu=12'))
        db.session.commit()
        token=create_access_token(identity='2',additional_claims={'tipo_token':'operativo','id_perfil':2,'id_local':1})
        client=self.app.test_client()
        headers={'Authorization':'Bearer '+token}
        self.assertEqual(client.post('/api/produccion/subproductos',json=self.data,headers=headers).status_code,403)
        self.assertEqual(client.put('/api/produccion/subproductos/1',json=self.data,headers=headers).status_code,403)
        self.assertEqual(client.get('/api/produccion/subproductos/formulario',headers=headers).status_code,200)
        token=create_access_token(identity='1',additional_claims={'tipo_token':'operativo','id_perfil':1,'id_local':2})
        response=client.post('/api/produccion/subproductos',json=self.data,headers={'Authorization':'Bearer '+token})
        self.assertEqual(response.status_code,201,response.json)
        self.assertEqual(client.get('/api/produccion/subproductos/formulario').status_code,401)
