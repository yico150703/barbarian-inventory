import os
import unittest
from unittest.mock import patch
from flask_jwt_extended import create_access_token
from sqlalchemy import text
import test_salon_orders as orders
from app.core.extensions import db
from app.modules.auth.salon_layout import predeterminado,validar
from werkzeug.exceptions import BadRequest

class LayoutValidation(unittest.TestCase):
 def test_invalid_layout(self):
  for valor in (None,{}, {'version':0,'elementos':[]}, {'version':0,'elementos':[{'codigo':'M01'}]}):
   with self.assertRaises(BadRequest):validar(valor)
  d=predeterminado();d['elementos'][0]['ancho']=101
  with self.assertRaises(BadRequest):validar(d)
  d=predeterminado();d['elementos'].append(d['elementos'][1])
  with self.assertRaises(BadRequest):validar(d)

@unittest.skipUnless(os.environ.get('LOCAL_SCOPE_TEST_DB')=='1','PostgreSQL temporal')
class LayoutTests(unittest.TestCase):
 login=orders.SalonOrderTests.login
 guardar=orders.SalonOrderTests.guardar
 def setUp(self):
  orders.SalonOrderTests.setUp(self)
  token=create_access_token(identity='2',additional_claims={'tipo_token':'operativo','id_perfil':2,'id_local':1})
  self.manager={'Authorization':'Bearer '+token}
 def tearDown(self):orders.SalonOrderTests.tearDown(self)
 def save(self,d):return self.client.put('/api/salon/distribucion',headers=self.manager,json=d)
 def test_save_scope_version_and_dynamic_orders(self):
  d=predeterminado();d['elementos'].append(dict(codigo='M11',tipo='mesa',x=70,y=80,ancho=10,alto=10))
  r=self.save(d);self.assertEqual(r.status_code,200,r.json)
  self.assertEqual(r.json['version'],1)
  self.assertEqual(self.save(d).status_code,409)
  salon=self.client.get('/api/salon/distribucion',headers=self.headers)
  self.assertIn('M11',[e['codigo'] for e in salon.json['elementos']])
  self.assertEqual(self.guardar(mesa='M11',enviar=True).status_code,200)
  self.assertEqual(self.guardar(mesa='M12').status_code,400)
  self.assertEqual(db.session.execute(text('SELECT count(*) FROM salon_distribucion WHERE id_local=2')).scalar(),0)
  d=r.json;d['elementos']=[e for e in d['elementos'] if e['codigo']!='M11']
  self.assertEqual(self.save(d).status_code,409)
 def test_only_manager_and_assigned_local(self):
  for perfil in (1,3,4):
   token=create_access_token(identity='2',additional_claims={'tipo_token':'operativo','id_perfil':perfil,'id_local':1})
   h={'Authorization':'Bearer '+token}
   self.assertEqual(self.client.put('/api/salon/distribucion',headers=h,json=predeterminado()).status_code,403)
  self.assertEqual(self.client.put('/api/salon/distribucion',headers=self.headers,json=predeterminado()).status_code,403)
  token=create_access_token(identity='2',additional_claims={'tipo_token':'operativo','id_perfil':2,'id_local':2})
  self.assertEqual(self.client.get('/api/salon/distribucion',headers={'Authorization':'Bearer '+token}).status_code,403)
 def test_audit_failure_is_atomic(self):
  with patch('app.modules.auth.salon_layout.registrar_actividad',side_effect=RuntimeError('fallo')):
   with self.assertRaises(RuntimeError),db.session.begin_nested():self.save(predeterminado())
  self.assertEqual(db.session.execute(text('SELECT count(*) FROM salon_distribucion')).scalar(),0)
