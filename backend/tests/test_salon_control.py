import os
import unittest
import uuid
from unittest.mock import patch
from sqlalchemy import text
import test_salon_orders as orders
from app.core.extensions import db
from app.modules.auth.salon import guardar_pin

@unittest.skipUnless(os.environ.get('LOCAL_SCOPE_TEST_DB')=='1','PostgreSQL temporal')
class ControlSalonTests(unittest.TestCase):
 login=orders.SalonOrderTests.login
 guardar=orders.SalonOrderTests.guardar
 def setUp(self):orders.SalonOrderTests.setUp(self)
 def tearDown(self):orders.SalonOrderTests.tearDown(self)
 def autorizar(self,accion,pin='0012'):
  return self.client.post('/api/salon/autorizar',headers=self.headers,json={'accion':accion,'pin':pin})
 def accion(self,accion,token=None,mesa='M01',**datos):
  return self.client.post(f'/api/salon/mesas/{mesa}/{accion}',headers=self.headers,json={'autorizacion':token,**datos})
 def test_delete_sent_requires_fresh_pin_and_keeps_history(self):
  enviado=self.guardar(enviar=True).json
  ids=enviado['lineas'][0]['ids_lineas']
  self.assertEqual(self.accion('eliminar',ids_lineas=ids).status_code,403)
  self.assertEqual(self.autorizar('eliminar','9999').status_code,401)
  token=self.autorizar('eliminar').json['autorizacion']
  r=self.accion('eliminar',token,ids_lineas=ids)
  self.assertEqual(r.status_code,200,r.json);self.assertEqual(r.json['pedido']['total'],0)
  self.assertEqual(db.session.execute(text('SELECT count(*) FROM salon_pedido_linea')).scalar(),1)
  self.assertEqual(db.session.execute(text('SELECT count(*) FROM salon_linea_anulada')).scalar(),1)
  self.assertEqual(self.accion('eliminar',token,ids_lineas=ids).status_code,409)
 def test_move_preserves_sent_owner_and_frees_origin(self):
  clave=str(uuid.uuid4())
  self.guardar(enviar=True,clave=clave)
  token=self.autorizar('mover').json['autorizacion']
  r=self.accion('mover',token,destino='M02');self.assertEqual(r.status_code,200,r.json)
  self.assertEqual(self.client.get('/api/salon/mesas/M01/pedido',headers=self.headers).json['total'],0)
  self.assertEqual(self.client.get('/api/salon/mesas/M02/pedido',headers=self.headers).json['total'],31)
  self.assertEqual(db.session.execute(text('SELECT mesa FROM salon_pedido')).scalar(),'M01')
  self.assertEqual(self.guardar(enviar=True,clave=clave).status_code,409)
  self.assertEqual(self.guardar(enviar=True,mesa='M02').json['total'],62)
  self.assertEqual(self.guardar(enviar=True,mesa='M01').json['total'],31)
 def test_move_rejects_occupied_and_draft_destinations(self):
  self.guardar(enviar=True);self.guardar(mesa='M02')
  token=self.autorizar('mover').json['autorizacion']
  with db.session.begin_nested():self.assertEqual(self.accion('mover',token,destino='M02').status_code,409)
  self.assertEqual(self.autorizar('inventada').status_code,400)
 def test_reassign_and_member_cannot_open_foreign_table(self):
  db.session.execute(text("""INSERT INTO usuario_perfiles(id_usuario,id_perfil,usuario_asignacion) VALUES(1,4,1);
    INSERT INTO usuario_local(id_usuario,id_local) VALUES(1,1);
    INSERT INTO usuario_puestos_laborales(id_usuario,id_puesto_laboral,usuario_asignacion) VALUES(1,9901,1);"""))
  guardar_pin(1,{'pin_salon':'1234'})
  self.guardar(enviar=True)
  token=self.autorizar('reasignar').json['autorizacion']
  r=self.accion('reasignar',token,id_usuario=1);self.assertEqual(r.status_code,200,r.json)
  self.assertFalse(self.client.get('/api/salon/mesas/M01/pedido',headers=self.headers).json['puede_editar'])
  self.assertEqual(self.guardar(enviar=True).status_code,403)
  estado=self.client.get('/api/salon/estado-mesas',headers=self.headers).json
  self.assertEqual(estado['mesas'][0]['id_usuario'],1)
  db.session.execute(text('UPDATE usuario_perfiles SET estado_registro=0 WHERE id_usuario=2 AND id_perfil=2'))
  self.assertEqual(self.client.get('/api/salon/mesas/M01/pedido',headers=self.headers).status_code,403)
  self.assertEqual(self.autorizar('eliminar').status_code,403)
 def test_supervisor_can_delete_but_not_move(self):
  db.session.execute(text("""INSERT INTO perfiles(id_perfil,nombre,descripcion) VALUES(3,'Supervisor','Prueba') ON CONFLICT DO NOTHING;
   INSERT INTO usuario_perfiles(id_usuario,id_perfil,usuario_asignacion) VALUES(2,3,1);
   UPDATE usuario_perfiles SET estado_registro=0 WHERE id_usuario=2 AND id_perfil=2;"""))
  self.assertEqual(self.autorizar('eliminar').status_code,200)
  self.assertEqual(self.autorizar('mover').status_code,403)
  self.assertEqual(self.autorizar('reasignar').status_code,403)
 def test_pin_rate_limit_and_rotation_revoke_authorization(self):
  token=self.autorizar('mover').json['autorizacion']
  self.guardar(enviar=True)
  guardar_pin(2,{'pin_salon':'0023'});self.headers={'Authorization':'Bearer '+self.login('0023').json['token']}
  self.assertEqual(self.accion('mover',token,destino='M02').status_code,403)
  for _ in range(5):self.assertEqual(self.autorizar('mover','9999').status_code,401)
  self.assertEqual(self.autorizar('mover','0023').status_code,401)
 def test_audit_failure_rolls_back_annulment(self):
  ids=self.guardar(enviar=True).json['lineas'][0]['ids_lineas'];token=self.autorizar('eliminar').json['autorizacion']
  with patch('app.modules.auth.salon_control.registrar_actividad',side_effect=RuntimeError('fallo')):
   with self.assertRaises(RuntimeError),db.session.begin_nested():self.accion('eliminar',token,ids_lineas=ids)
  self.assertEqual(db.session.execute(text('SELECT count(*) FROM salon_linea_anulada')).scalar(),0)
  self.assertEqual(db.session.execute(text('SELECT count(*) FROM salon_autorizacion_usada')).scalar(),0)

 def test_authorization_cannot_delete_other_table_or_wrong_action(self):
  self.guardar(enviar=True)
  ids=self.guardar(enviar=True,mesa='M02').json['lineas'][0]['ids_lineas']
  token=self.autorizar('eliminar').json['autorizacion']
  self.assertEqual(self.accion('eliminar',token,ids_lineas=ids).status_code,409)
  token=self.autorizar('mover').json['autorizacion']
  self.assertEqual(self.accion('eliminar',token,ids_lineas=ids).status_code,403)
  self.assertEqual(db.session.execute(text('SELECT count(*) FROM salon_linea_anulada')).scalar(),0)
