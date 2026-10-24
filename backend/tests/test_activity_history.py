import os
import unittest
from flask import g
from flask_jwt_extended import create_access_token, verify_jwt_in_request
from sqlalchemy import text
from werkzeug.exceptions import Forbidden, BadRequest
from app import create_app
from app.core.extensions import db
from app.modules.auditoria.history import historial, sanitizar
from app.modules.auditoria.service import registrar_actividad


class ActivitySanitizingTests(unittest.TestCase):
    def test_nested_credentials_not_exposed(self):
        self.assertEqual(sanitizar({'nombre':'Uno','clave':'x','detalle':[{'password_hash':'x','token':'x','cantidad':2}]}),
                         {'nombre':'Uno','detalle':[{'cantidad':2}]})


@unittest.skipUnless(os.environ.get('LOCAL_SCOPE_TEST_DB') == '1', 'PostgreSQL temporal')
class ActivityHistoryTests(unittest.TestCase):
    def setUp(self):
        self.app=create_app()
        self.app.config.update(TESTING=True,JWT_SECRET_KEY='activity-tests-secret-at-least-32-characters')
        self.ctx=self.app.app_context();self.ctx.push()
        self.assertEqual(db.session.execute(text('SELECT current_database()')).scalar(),'barbarito_test')
        db.session.execute(text('''INSERT INTO actividad_usuario(id_usuario,modulo,accion,id_registro_afectado,descripcion,id_perfil_utilizado,id_local)
          VALUES(1,'USUARIOS','EDITAR',2,'ACTIVITY_TEST global',1,NULL),
          (2,'USUARIOS','EDITAR',1,'ACTIVITY_TEST local uno',2,1),
          (1,'USUARIOS','EDITAR',2,'ACTIVITY_TEST local dos',1,2)'''))
        db.session.execute(text('''INSERT INTO auditoria_cambio(id_usuario,modulo,accion,tabla_afectada,id_registro_afectado,datos_anteriores,datos_nuevos,motivo,id_local)
          VALUES(1,'USUARIOS','EDITAR','usuario',2,'{"nombre":"Antes","clave":"secreto"}',
          '{"nombre":"Después","password":"secreto"}','ACTIVITY_TEST cambio',NULL)'''))

    def tearDown(self):
        db.session.rollback();db.session.remove();self.ctx.pop()

    def session(self, admin=True):
        g.pop('local_operativo',None)
        token=create_access_token(identity='1' if admin else '2',additional_claims={
            'tipo_token':'operativo','id_perfil':1 if admin else 2,'id_local':1})
        return self.app.test_request_context(headers={'Authorization':'Bearer '+token})

    def test_scope_target_and_changes(self):
        with self.session():
            verify_jwt_in_request()
            r=historial({'buscar':'ACTIVITY_TEST'})
            self.assertEqual(len(r['eventos']),4)
            self.assertTrue(all(e['usuario_afectado'] for e in r['eventos']))
            cambios=[e for e in r['eventos'] if e['origen']=='cambio'][0]
            self.assertEqual(cambios['antes'],{'nombre':'Antes'})
            self.assertEqual(cambios['despues'],{'nombre':'Después'})
            self.assertEqual(len(historial({'buscar':'ACTIVITY_TEST','local':'global'})['eventos']),2)
            self.assertEqual(len(historial({'buscar':'ACTIVITY_TEST','local':'2'})['eventos']),1)
        with self.session(False):
            verify_jwt_in_request()
            r=historial({'buscar':'ACTIVITY_TEST'})
            self.assertEqual(len(r['eventos']),1)
            self.assertEqual([l['id_local'] for l in r['locales']],[1])
            for local in ('global','2'):
                with self.assertRaises(Forbidden): historial({'local':local})

    def test_dates_pagination_and_global_admin_writes(self):
        with self.session():
            verify_jwt_in_request()
            for args in ({'pagina':'0'},{'desde':'mal'},{'desde':'2026-09-24','hasta':'2026-09-01'}):
                with self.assertRaises(BadRequest): historial(args)
            self.assertEqual(historial({'hasta':'1900-01-01'})['eventos'],[])
            mid=registrar_actividad(1,'PRUEBA','EDITAR',1,'ACTIVITY_TEST sin local')
            self.assertIsNone(db.session.execute(text('SELECT id_local FROM actividad_usuario WHERE id_actividad_usuario=:id'),{'id':mid}).scalar())
            db.session.execute(text("INSERT INTO actividad_usuario(id_usuario,modulo,accion,descripcion) SELECT 1,'PRUEBA','EDITAR','PAGE_TEST' FROM generate_series(1,55)"))
            primero=historial({'buscar':'PAGE_TEST'})
            segundo=historial({'buscar':'PAGE_TEST','pagina':'2'})
            self.assertEqual(len(primero['eventos']),50);self.assertTrue(primero['hay_mas'])
            self.assertEqual(len(segundo['eventos']),5);self.assertFalse(segundo['hay_mas'])
            self.assertFalse({e['id'] for e in primero['eventos']} & {e['id'] for e in segundo['eventos']})
