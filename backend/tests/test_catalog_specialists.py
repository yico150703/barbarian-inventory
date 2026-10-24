import json
import unittest
from unittest.mock import patch

from app import create_app
from app.agents.catalog_specialists import SPECIALISTS
from app.agents.manifest import catalog
from app.agents.orchestrator.router import run
from app.modules.asistente_ia.provider import AssistantError


ANSWER = [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'Consulta lista.'}]}]


class CatalogSpecialistTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()

    def test_each_specialist_only_exposes_its_own_write_resource(self):
        for agent in SPECIALISTS.values():
            with self.subTest(agent=agent.identity), self.app.test_request_context(), \
                 patch('app.modules.asistente_ia.tools.allowed', return_value=True), \
                 patch('app.modules.asistente_ia.provider.respond', return_value=ANSWER) as model:
                agent.run({'menu': []}, 'Consulta')
                definitions = {t['name']: t for t in model.call_args.args[1]}
                self.assertEqual(definitions['preparar_cambio']['parameters']['properties']['recurso']['enum'], [agent.resource])
                self.assertEqual(definitions['consultar']['parameters']['properties']['recurso']['enum'], list(agent.resources))
                if agent.resource in ('categorias_carta', 'menajes', 'presentaciones'):
                    self.assertEqual(definitions['abrir_formulario']['parameters']['properties']['recurso']['enum'], [agent.resource])
                else:
                    self.assertNotIn('abrir_formulario', definitions)
                self.assertTrue(agent.skills[0].is_file())

    def test_dependency_write_is_rejected_before_prepare(self):
        call = {'type': 'function_call', 'call_id': 'foreign', 'name': 'preparar_cambio',
                'arguments': json.dumps({'recurso': 'productos', 'accion': 'crear', 'id': None,
                                         'datos_json': '{"nombre":"No permitido"}'})}
        with self.app.test_request_context(), \
             patch('app.modules.asistente_ia.tools.allowed', return_value=True), \
             patch('app.modules.asistente_ia.provider.respond', side_effect=[[call], ANSWER]), \
             patch('app.modules.asistente_ia.tools.prepare') as prepare:
            result = SPECIALISTS['recetas'].run({'menu': []}, 'Crear receta')
        self.assertIsNone(result['plan'])
        prepare.assert_not_called()

    def test_unrelated_query_is_rejected_before_query(self):
        call = {'type': 'function_call', 'call_id': 'foreign', 'name': 'consultar',
                'arguments': json.dumps({'recurso': 'usuarios', 'busqueda': '', 'desde': 0})}
        with self.app.test_request_context(), \
             patch('app.modules.asistente_ia.tools.allowed', return_value=True), \
             patch('app.modules.asistente_ia.provider.respond', side_effect=[[call], ANSWER]), \
             patch('app.modules.asistente_ia.tools.query') as query:
            SPECIALISTS['menajes'].run({'menu': []}, 'Consulta menajes')
        query.assert_not_called()

    def test_dependency_read_permission_does_not_grant_access_to_agent(self):
        with patch('app.modules.asistente_ia.tools.allowed', side_effect=lambda s, r: r == 'productos'), \
             self.assertRaises(AssistantError):
            run({'menu': []}, 'Crear receta')

    def test_read_only_session_has_no_write_tool(self):
        with self.app.test_request_context(), \
             patch('app.modules.asistente_ia.tools.allowed', side_effect=lambda s, r, a='consultar': a == 'consultar'), \
             patch('app.modules.asistente_ia.provider.respond', return_value=ANSWER) as model:
            SPECIALISTS['recetas'].run({'menu': []}, 'Consulta recetas')
        self.assertNotIn('preparar_cambio', [t['name'] for t in model.call_args.args[1]])

    def test_inspector_lists_five_independent_agents_and_skills(self):
        agents = {a['id']: a for a in catalog()['agentes']}
        for identity, specialist in SPECIALISTS.items():
            self.assertEqual(agents[identity]['recursos_modificables'], [specialist.resource])
            self.assertEqual(len(agents[identity]['skills']), 1)
        self.assertTrue(set(SPECIALISTS).isdisjoint(agents['carta_recetas']['recursos']))
