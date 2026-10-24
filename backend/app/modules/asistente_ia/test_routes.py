import unittest
from unittest.mock import patch
from flask_jwt_extended import create_access_token
from app import create_app

class AssistantRoutesTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config.update(TESTING=True, JWT_SECRET_KEY='assistant-test-key-with-at-least-32-characters')
        self.ctx = self.app.app_context(); self.ctx.push()
        self.client = self.app.test_client()
        token = create_access_token(identity='2', additional_claims={'tipo_token':'operativo','id_perfil':2,'id_local':1})
        self.headers = {'Authorization': 'Bearer '+token}
    def tearDown(self): self.ctx.pop()
    def test_requires_authentication(self):
        self.assertEqual(self.client.get('/api/asistente-ia/estado').status_code,401)
    @patch('app.modules.asistente_ia.routes.obtener_sesion_actual')
    def test_filters_access_and_does_not_claim_ai_is_ready(self,session):
        session.return_value = ({'menu':[
            {'id_opcion_menu':4,'nombre':'Productos','url_menu':'/home/productos','permisos':{'consultar':True}},
            {'id_opcion_menu':2,'nombre':'Usuarios','url_menu':'/home/usuarios','permisos':{'consultar':False}},
            {'id_opcion_menu':15,'nombre':'Stock','url_menu':'/home/stock','permisos':{'consultar':True}},
        ]},200)
        with patch('app.modules.asistente_ia.provider.configured', return_value=False), patch('app.modules.asistente_ia.drafts.ready', return_value=False):
            r=self.client.get('/api/asistente-ia/estado',headers=self.headers)
        self.assertEqual(r.status_code,200)
        self.assertFalse(r.json['ia_disponible']); self.assertFalse(r.json['ejecucion_disponible'])
        self.assertEqual([m['nombre'] for m in r.json['modulos_consultables']],['Productos','Stock'])
        self.assertEqual(r.json['capacidades']['stock'],['consultar'])
    @patch('app.modules.asistente_ia.routes.obtener_sesion_actual')
    def test_propagates_revoked_session(self,session):
        session.return_value=({'mensaje':'Perfil revocado'},403)
        r=self.client.get('/api/asistente-ia/estado',headers=self.headers)
        self.assertEqual(r.status_code,403);self.assertNotIn('modulos_consultables',r.json)
