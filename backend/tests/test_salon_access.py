import os
import unittest
from unittest.mock import patch
from flask_jwt_extended import create_access_token
from sqlalchemy import text
from werkzeug.exceptions import BadRequest
from app import create_app
from app.core.extensions import db
from app.modules.auth.salon import guardar_pin


@unittest.skipUnless(os.environ.get('LOCAL_SCOPE_TEST_DB')=='1','PostgreSQL temporal')
class SalonTests(unittest.TestCase):
    def setUp(self):
        self.app=create_app()
        self.app.config.update(TESTING=True,JWT_SECRET_KEY='salon-tests-at-least-32-secret-characters')
        self.ctx=self.app.app_context();self.ctx.push()
        self.assertEqual(db.session.execute(text('SELECT current_database()')).scalar(),'barbarito_test')
        db.session.execute(text("""INSERT INTO perfiles(id_perfil,nombre,descripcion) VALUES(4,'Miembro','Prueba') ON CONFLICT DO NOTHING;
          INSERT INTO usuario_perfiles(id_usuario,id_perfil,usuario_asignacion) VALUES(2,4,1);
          INSERT INTO puesto_laboral(id_puesto_laboral,nombre) VALUES(9901,'Mesero');
          INSERT INTO usuario_puestos_laborales(id_usuario,id_puesto_laboral,usuario_asignacion) VALUES(2,9901,1);"""))
        self.commit=patch.object(db.session,'commit');self.commit.start()
        self.client=self.app.test_client()
        guardar_pin(2,{'pin_salon':'0012'})

    def tearDown(self):
        self.commit.stop();db.session.rollback();db.session.remove();self.ctx.pop()

    def login(self,pin='0012',local=1):
        return self.client.post('/api/salon/login',json={'id_usuario':2,'id_local':local,'pin':pin})

    def test_access_and_management_separation(self):
        opciones=self.client.get('/api/salon/opciones?local=1').json
        self.assertEqual(opciones['usuarios'][0]['id_usuario'],2)
        self.assertNotIn('pin',str(opciones))
        r=self.login();self.assertEqual(r.status_code,200,r.json)
        h={'Authorization':'Bearer '+r.json['token']}
        self.assertEqual(self.client.get('/api/salon/me',headers=h).status_code,200)
        for path in ('/api/usuarios','/api/actividades/historial','/api/inventarios/stock'):
            self.assertEqual(self.client.get(path,headers=h).status_code,403)
        self.assertEqual(self.client.post('/api/auth/cambiar-perfil',headers=h,json={'id_perfil':2}).status_code,403)
        gestor=create_access_token(identity='2',additional_claims={'tipo_token':'operativo','id_perfil':2,'id_local':1})
        self.assertEqual(self.client.get('/api/salon/me',headers={'Authorization':'Bearer '+gestor}).status_code,403)

    def test_rotation_revocation_and_wrong_store(self):
        self.assertEqual(self.login(local=2).status_code,401)
        token=self.login().json['token'];h={'Authorization':'Bearer '+token}
        guardar_pin(2,{'pin_salon':'0023'})
        self.assertEqual(self.client.get('/api/salon/me',headers=h).status_code,403)
        self.assertEqual(self.login().status_code,401)
        self.assertEqual(self.login('0023').status_code,200)
        guardar_pin(2,{'revocar_pin_salon':True})
        self.assertEqual(self.login('0023').status_code,401)
        self.assertEqual(self.client.get('/api/salon/opciones?local=1').json['usuarios'],[])

    def test_eligibility_and_pin_validation(self):
        for pin in ('12','12345','abcd',1234):
            with self.assertRaises(BadRequest):guardar_pin(2,{'pin_salon':pin})
        with self.assertRaises(BadRequest):guardar_pin(1,{'pin_salon':'1234'})
        token=self.login().json['token']
        db.session.execute(text('UPDATE usuario_perfiles SET estado_registro=0 WHERE id_usuario=2 AND id_perfil=2'))
        db.session.execute(text('UPDATE usuario_puestos_laborales SET estado_registro=0 WHERE id_usuario=2'))
        self.assertEqual(self.client.get('/api/salon/me',headers={'Authorization':'Bearer '+token}).status_code,403)
        guardar_pin(2,{})
        self.assertIsNone(db.session.execute(text('SELECT pin_hash FROM usuario_pin_salon WHERE id_usuario=2')).scalar())

    def test_rate_limit_and_hash_storage(self):
        self.assertNotEqual(db.session.execute(text('SELECT pin_hash FROM usuario_pin_salon WHERE id_usuario=2')).scalar(),'0012')
        for _ in range(5):self.assertEqual(self.login('9999').status_code,401)
        self.assertEqual(self.login().status_code,401)
        for _ in range(10):self.login('9999')
        self.assertEqual(self.login().status_code,429)
