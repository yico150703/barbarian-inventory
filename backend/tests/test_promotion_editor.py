import os
import unittest
from unittest.mock import patch
from flask_jwt_extended import create_access_token
from sqlalchemy import text
from app import create_app
from app.core.extensions import db
from app.modules.promociones.editor import guardar_promocion
from app.modules.promociones.service import obtener_promociones


@unittest.skipUnless(os.environ.get('LOCAL_SCOPE_TEST_DB') == '1', 'Requiere PostgreSQL temporal')
class PromotionEditorTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config.update(TESTING=True, JWT_SECRET_KEY='promotion-test-secret-at-least-32-characters')
        self.ctx = self.app.app_context(); self.ctx.push()
        self.assertEqual(db.session.execute(text('SELECT current_database()')).scalar(), 'barbarito_test')
        db.session.execute(text("INSERT INTO categoria_carta(id_categoria_carta,nombre,prefijo) VALUES(9100,'Promo test','PT'); INSERT INTO menaje(id_menaje,nombre) VALUES(9100,'Promo vaso'); INSERT INTO item_carta(id_item_carta,codigo,nombre,id_categoria_carta,tipo) VALUES(9100,'PT-001','Bebida promo',9100,'DIRECTO'); INSERT INTO presentacion_venta(id_presentacion_venta,id_item_carta,id_menaje,contenido,unidad,precio) VALUES(9100,9100,9100,1,'LTR',20),(9101,9100,9100,2,'LTR',30)"))
        db.session.commit()
        self.data = {'nombre':'Promo prueba','precio':'39.90','activo':True,'hora_inicio':None,'hora_fin':None,
                     'grupos':[{'cantidad_elegir':2,'permite_repetir':True,'opciones':[9100]}],
                     'reposiciones':[9100]}

    def tearDown(self):
        db.session.rollback()
        for sql in ('DELETE FROM promocion_reposicion','DELETE FROM promocion_opcion','DELETE FROM promocion_grupo','DELETE FROM promocion',
                    'DELETE FROM presentacion_venta WHERE id_item_carta=9100','DELETE FROM item_carta WHERE id_item_carta=9100',
                    'DELETE FROM menaje WHERE id_menaje=9100','DELETE FROM categoria_carta WHERE id_categoria_carta=9100'):
            db.session.execute(text(sql))
        db.session.commit(); db.session.remove(); self.ctx.pop()

    def test_create_edit_groups_and_code(self):
        r,s=guardar_promocion(1,self.data); self.assertEqual(s,201,r)
        promo=obtener_promociones()[0]['promociones'][0]
        grupo=promo['grupos'][0]['id_promocion_grupo']
        edit={**self.data,'hora_inicio':'22:00','hora_fin':'02:00','grupos':[
            {'id_promocion_grupo':grupo,'cantidad_elegir':1,'permite_repetir':False,'opciones':[9101]},
            {'cantidad_elegir':1,'permite_repetir':True,'opciones':[9100]}]}
        self.assertEqual(guardar_promocion(1,edit,r['id_promocion'])[1],200)
        actualizado=obtener_promociones()[0]['promociones'][0]
        self.assertEqual(actualizado['codigo'],promo['codigo'])
        self.assertEqual(actualizado['total_grupos'],2)
        self.assertEqual(actualizado['hora_fin'],'02:00')
        self.assertEqual(actualizado['grupos'][0]['id_promocion_grupo'],grupo)
        edit['grupos']=edit['grupos'][:1]
        edit['reposiciones']=[9101]
        self.assertEqual(guardar_promocion(1,edit,r['id_promocion'])[1],200)
        self.assertEqual(obtener_promociones()[0]['promociones'][0]['total_opciones'],1)

    def test_validation_and_atomic_rollback(self):
        for cambios in ({'precio':'NaN'}, {'hora_inicio':'17:00'}, {'hora_inicio':'25:00','hora_fin':'22:00'},
                         {'grupos':[]}, {'grupos':[{'cantidad_elegir':2,'permite_repetir':False,'opciones':[9100]}]},
                         {'grupos':[{'cantidad_elegir':1,'permite_repetir':True,'opciones':[9100,9100]}]},
                         {'grupos':[{'cantidad_elegir':1,'permite_repetir':True,'opciones':[999999]}]}):
            self.assertEqual(guardar_promocion(1,{**self.data,**cambios})[1],400,cambios)
        with patch('app.modules.promociones.editor.registrar_actividad',side_effect=RuntimeError('fallo')):
            with self.assertRaises(RuntimeError): guardar_promocion(1,self.data)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM promocion')).scalar(),0)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM promocion_opcion')).scalar(),0)

    def test_inactive_existing_option_preserved_but_not_added(self):
        r,s=guardar_promocion(1,self.data); self.assertEqual(s,201,r)
        grupo=obtener_promociones()[0]['promociones'][0]['grupos'][0]['id_promocion_grupo']
        db.session.execute(text('UPDATE presentacion_venta SET activo=false WHERE id_presentacion_venta=9100')); db.session.commit()
        edit={**self.data,'grupos':[{**self.data['grupos'][0],'id_promocion_grupo':grupo}]}
        self.assertEqual(guardar_promocion(1,edit,r['id_promocion'])[1],200)
        self.assertEqual(guardar_promocion(1,{**self.data,'nombre':'Otra'})[1],400)
        edit['grupos'][0]['id_promocion_grupo']=999999
        self.assertEqual(guardar_promocion(1,edit,r['id_promocion'])[1],400)

    def test_permissions(self):
        c=self.app.test_client()
        self.assertEqual(c.post('/api/promociones',json=self.data).status_code,401)
        db.session.execute(text('UPDATE perfil_opcion_menu SET puede_crear=false,puede_editar=false WHERE id_opcion_menu=14 AND id_perfil=2')); db.session.commit()
        for perfil,status in ((2,403),(1,201)):
            token=create_access_token(identity=str(perfil),additional_claims={'tipo_token':'operativo','id_perfil':perfil,'id_local':1})
            headers={'Authorization':'Bearer '+token}
            self.assertEqual(c.get('/api/promociones/formulario',headers=headers).status_code,200)
            respuesta=c.post('/api/promociones',json=self.data,headers=headers)
            self.assertEqual(respuesta.status_code,status,respuesta.json)
            if perfil==2:
                self.assertEqual(c.put('/api/promociones/1',json=self.data,headers=headers).status_code,403)
