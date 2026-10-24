import os
import unittest
import uuid
from unittest.mock import patch
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
import test_salon_access as access
from app.core.extensions import db


@unittest.skipUnless(os.environ.get('LOCAL_SCOPE_TEST_DB')=='1','PostgreSQL temporal')
class SalonOrderTests(unittest.TestCase):
    login=access.SalonTests.login

    def setUp(self):
        access.SalonTests.setUp(self)
        self.rollback=patch.object(db.session,'rollback');self.rollback.start()
        db.session.execute(text('''
          INSERT INTO categoria_carta(id_categoria_carta,nombre,prefijo) VALUES(9800,'Platos prueba','PT');
          INSERT INTO menaje(id_menaje,nombre) VALUES(9800,'Plato prueba');
          INSERT INTO item_carta(id_item_carta,codigo,nombre,id_categoria_carta,tipo)
            VALUES(9800,'PT-001','Alitas prueba',9800,'PREPARADO');
          INSERT INTO presentacion_venta(id_presentacion_venta,id_item_carta,id_menaje,contenido,unidad,precio)
                        VALUES(9800,9800,9800,1,'PORCION',15.50);
          INSERT INTO grupo_salsa(id_grupo_salsa,id_presentacion_venta,cantidad_maxima,permite_repetir)
            VALUES(9800,9800,2,false);
          INSERT INTO grupo_salsa_opcion(id_grupo_salsa_opcion,id_grupo_salsa,id_producto,cantidad,unidad)
                        VALUES(9800,9800,1,1,'C62');
        '''))
        self.headers={'Authorization':'Bearer '+self.login().json['token']}
        self.linea={'id_presentacion':9800,'cantidad':2,'comentario':'Sin sal','opciones':[9800],'precio':0.01}

    def tearDown(self):
        self.rollback.stop()
        access.SalonTests.tearDown(self)

    def guardar(self,version=0,enviar=False,lineas=None,mesa='M01',clave=None):
        return self.client.put(f'/api/salon/mesas/{mesa}/pedido',headers=self.headers,
            json={'version':version,'enviar':enviar,'envio_clave':clave or str(uuid.uuid4()),'lineas':lineas if lineas is not None else [self.linea]})

    def test_additional_sends_group_and_retry_without_duplicates(self):
        clave=str(uuid.uuid4())
        primero=self.guardar(enviar=True,clave=clave)
        self.assertEqual(primero.status_code,200,primero.json)
        self.assertTrue(primero.json['lineas'][0]['enviada'])
        self.assertEqual(self.guardar(enviar=True,clave=clave).json['total'],31)
        self.assertEqual(self.guardar(enviar=True,clave=clave,lineas=[{**self.linea,'cantidad':1}]).status_code,409)
        segundo=self.guardar(enviar=True,lineas=[{**self.linea,'cantidad':1}])
        self.assertEqual(segundo.status_code,200,segundo.json)
        self.assertEqual(len(segundo.json['lineas']),1)
        self.assertEqual(segundo.json['lineas'][0]['cantidad'],3)
        self.assertEqual(segundo.json['total'],46.5)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM salon_pedido')).scalar(),2)
        self.assertEqual(db.session.execute(text('SELECT cantidad FROM salon_pedido_linea ORDER BY id_pedido LIMIT 1')).scalar(),2)
        self.assertEqual(len(self.client.get('/api/salon/mis-mesas',headers=self.headers).json['mesas']),1)

    def test_cancel_only_draft_and_preserve_sent_variants(self):
        self.assertEqual(self.guardar(enviar=True).status_code,200)
        self.assertEqual(self.guardar(enviar=True,lineas=[{**self.linea,'comentario':'Otro comentario'}]).status_code,200)
        db.session.execute(text('UPDATE presentacion_venta SET precio=20 WHERE id_presentacion_venta=9800'))
        self.assertEqual(len(self.guardar(enviar=True).json['lineas']),3)
        draft=self.guardar()
        self.assertEqual(draft.status_code,200,draft.json)
        self.assertFalse(draft.json['lineas'][-1]['enviada'])
        url='/api/salon/mesas/M01/pedido'
        self.assertEqual(self.client.delete(url,headers=self.headers,json={'version':0}).status_code,409)
        cancel=self.client.delete(url,headers=self.headers,json={'version':1})
        self.assertEqual(cancel.status_code,200,cancel.json)
        self.assertEqual(len(cancel.json['lineas']),3)
        self.assertTrue(all(l['enviada'] for l in cancel.json['lineas']))
        self.assertEqual(cancel.json['total'],102)

    def test_draft_send_reopen_and_immutable(self):
        carta=self.client.get('/api/salon/carta',headers=self.headers)
        self.assertEqual(carta.status_code,200,carta.json)
        self.assertEqual(carta.json['productos'][0]['grupo']['maximo'],2)
        r=self.guardar();self.assertEqual(r.status_code,200,r.json)
        self.assertEqual(r.json['total'],31)
        self.assertEqual(r.json['lineas'][0]['comentario'],'Sin sal')
        self.assertEqual(r.json['lineas'][0]['opciones'][0]['id'],9800)
        self.assertEqual(self.client.get('/api/salon/mis-mesas',headers=self.headers).json['mesas'][0]['mesa'],'M01')
        r=self.guardar(1,True);self.assertEqual(r.status_code,200,r.json)
        self.assertEqual(r.json['estado'],'ENVIADO')
        self.assertEqual(self.guardar(2,True).status_code,409)
        self.assertEqual(self.guardar(2,lineas=[]).status_code,409)
        db.session.execute(text("UPDATE presentacion_venta SET precio=99 WHERE id_presentacion_venta=9800"))
        reabierto=self.client.get('/api/salon/mesas/M01/pedido',headers=self.headers).json
        self.assertEqual(reabierto['total'],31)
        self.assertEqual(reabierto['lineas'][0]['comentario'],'Sin sal')
        for sql in ("UPDATE salon_pedido SET estado='BORRADOR',enviado_en=NULL",'DELETE FROM salon_pedido_linea',"UPDATE salon_pedido_linea SET comentario='alterado'"):
            with self.assertRaises(DBAPIError), db.session.begin_nested():db.session.execute(text(sql))

    def test_options_validation_version_and_remove_draft(self):
        self.assertEqual(self.guardar(enviar=True,lineas=[]).status_code,400)
        for cambios in ({'opciones':[9999]},{'opciones':[9800,9800]},{'cantidad':0},{'comentario':'x'*501},{'id_presentacion':9999}):
            self.assertIn(self.guardar(lineas=[{**self.linea,**cambios}]).status_code,(400,409))
        db.session.execute(text('UPDATE grupo_salsa SET permite_repetir=true WHERE id_grupo_salsa=9800'))
        self.assertEqual(self.guardar(lineas=[{**self.linea,'opciones':[9800,9800]}]).status_code,200)
        self.assertEqual(self.guardar().status_code,409)
        self.assertEqual(self.guardar(1,lineas=[]).json['version'],0)
        self.assertEqual(self.client.get('/api/salon/mis-mesas',headers=self.headers).json['mesas'],[])

    def test_ownership_local_scope_and_inactive_product(self):
        db.session.execute(text('UPDATE usuario_perfiles SET estado_registro=0 WHERE id_usuario=2 AND id_perfil=2'))
        self.assertEqual(self.guardar(mesa='B05').status_code,200)
        db.session.execute(text('UPDATE salon_pedido SET id_usuario=1'))
        self.assertEqual(self.client.get('/api/salon/mesas/B05/pedido',headers=self.headers).status_code,403)
        self.assertEqual(self.guardar(1,mesa='B05').status_code,403)
        self.assertEqual(self.client.get('/api/salon/mis-mesas',headers=self.headers).json['mesas'],[])
        self.assertEqual(self.guardar(mesa='M99').status_code,400)
        db.session.execute(text('UPDATE salon_pedido SET id_local=2'))
        self.assertEqual(self.client.get('/api/salon/mesas/B05/pedido',headers=self.headers).json['version'],0)
        db.session.execute(text('UPDATE presentacion_venta SET activo=false WHERE id_presentacion_venta=9800'))
        self.assertEqual(self.guardar().status_code,409)

    def test_lines_keep_independent_comments_and_rollback_on_send_failure(self):
        lineas=[self.linea,{**self.linea,'comentario':'Bien cocido','cantidad':1}]
        r=self.guardar(lineas=lineas)
        self.assertEqual(r.status_code,200,r.json)
        self.assertEqual(len(r.json['lineas']),2)
        self.assertEqual(r.json['total'],46.5)
        with patch('app.modules.auth.salon_orders.registrar_actividad',side_effect=RuntimeError('fallo')):
            with self.assertRaises(RuntimeError),db.session.begin_nested():self.guardar(1,True,lineas)
        r=self.client.get('/api/salon/mesas/M01/pedido',headers=self.headers).json
        self.assertEqual(r['estado'],'BORRADOR')
        self.assertEqual(r['lineas'][1]['comentario'],'Bien cocido')

    def test_promotions_are_individual_and_refills_are_free_and_linked(self):
        db.session.execute(text('''
                    INSERT INTO presentacion_venta(id_presentacion_venta,id_item_carta,id_menaje,contenido,unidad,precio)
                        VALUES(9801,9800,9800,2,'C62',25);
                    INSERT INTO promocion(id_promocion,codigo,nombre,precio,activo)
                        VALUES(9800,'P-9800','Barra libre de alitas',29.90,true);
                    INSERT INTO promocion_grupo(id_promocion_grupo,id_promocion,cantidad_elegir,permite_repetir)
                        VALUES(9800,9800,1,false);
                    INSERT INTO promocion_opcion(id_promocion_grupo,id_presentacion_venta)
                        VALUES(9800,9800),(9800,9801);
                    INSERT INTO promocion_reposicion(id_promocion,id_presentacion_venta) VALUES(9800,9800);
                '''))
        carta=self.client.get('/api/salon/carta',headers=self.headers)
        self.assertEqual(carta.status_code,200,carta.json)
        self.assertEqual(carta.json['promociones'][0]['precio'],29.9)
        primera={'id_promocion':9800,'cantidad':1,'selecciones':[
            {'id_grupo':9800,'id_presentacion':9800,'opciones':[9800]}]}
        segunda={'id_promocion':9800,'cantidad':1,'selecciones':[
            {'id_grupo':9800,'id_presentacion':9801,'opciones':[]}]}
        enviado=self.guardar(enviar=True,lineas=[primera,segunda,primera])
        self.assertEqual(enviado.status_code,200,enviado.json)
        barras=[l for l in enviado.json['lineas'] if l['id_promocion']==9800]
        self.assertEqual(len(barras),3)
        self.assertEqual(len({l['ids_lineas'][0] for l in barras}),3)
        self.assertEqual(enviado.json['total'],89.7)
        refill={'id_presentacion':9800,'id_barra_libre':barras[0]['ids_lineas'][0],
                'cantidad':1,'comentario':'','opciones':[9800]}
        repuesto=self.guardar(enviar=True,lineas=[refill])
        self.assertEqual(repuesto.status_code,200,repuesto.json)
        self.assertEqual(repuesto.json['total'],89.7)
        linea_repuesta=next(l for l in repuesto.json['lineas'] if l['id_barra_libre'] is not None)
        self.assertEqual(linea_repuesta['precio'],0)
        refill_sin_permiso={**refill,'id_barra_libre':barras[1]['ids_lineas'][0]}
        self.assertEqual(self.guardar(lineas=[refill_sin_permiso]).status_code,409)
