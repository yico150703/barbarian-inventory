import json
import unittest
from unittest.mock import patch
from flask_jwt_extended import create_access_token

from app import create_app
from app.agents.catalog_specialists import SPECIALISTS
from app.agents.orchestrator import communication as coordinator
from app.modules.asistente_ia.provider import AssistantError


SCOPE = {'usuario': 1, 'perfil': 1, 'local': 1}
ANSWER = [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'Retomamos la receta.'}]}]


def handoff(agent='recetas', resource='presentaciones'):
    return {'agente': agent, 'plan': None, 'consultas': [], 'respuesta': '',
            'traspaso': {'recurso': resource, 'instruccion': 'Crear ' + resource,
                         'motivo': 'El usuario solicita crear el requisito que falta.'}}


class AgentCommunicationTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config['SECRET_KEY'] = 'communication-test-secret'
        self.context = self.app.test_request_context()
        self.context.push()
        self.addCleanup(self.context.pop)
        for target, kwargs in (
            ('app.modules.asistente_ia.drafts.scope', {'return_value': SCOPE}),
            ('app.modules.asistente_ia.tools.allowed', {'return_value': True}),
            ('app.modules.asistente_ia.tools.authorize', {}),
            ('app.modules.asistente_ia.forms.open_form', {'side_effect': lambda s, r: {'recurso': r}}),
            ('app.agents.orchestrator.communication.db.session.rollback', {}),
        ):
            mock = patch(target, **kwargs)
            mock.start()
            self.addCleanup(mock.stop)

    def start(self):
        return coordinator.coordinate({}, handoff(), 'Crear receta de hamburguesa', context='Precio indicado: 25')

    def test_handoff_keeps_original_task_and_opens_only_required_form(self):
        result = self.start()
        self.assertEqual(result['agente'], 'presentaciones')
        self.assertEqual(result['formulario']['recurso'], 'presentaciones')
        state = coordinator.load(result['continuacion'])
        self.assertEqual(state['pila'][0]['instruccion'], 'Crear receta de hamburguesa')
        self.assertIn('25', state['pila'][0]['contexto'])
        self.assertIsNone(result['plan'])

    def test_resume_passes_verified_result_to_original_specialist_without_executing(self):
        initial = self.start()
        state = coordinator.load(initial['continuacion'])
        plan = {'recurso': 'presentaciones', 'accion': 'crear', 'datos': {'nombre_item': 'Hamburguesa'}}
        coordinator.bind_plan(state, plan)
        with patch.object(coordinator.drafts, 'load', return_value={
            'estado': 'REALIZADO', 'plan': plan, 'resultado': {'id_presentacion_venta': 77}}), \
             patch('app.modules.asistente_ia.provider.respond', return_value=ANSWER) as model, \
             patch('app.modules.asistente_ia.tools.execute') as execute:
            result = coordinator.resume({}, initial['continuacion'], 'draft-id')
        self.assertEqual(result['agente'], 'recetas')
        self.assertNotIn('continuacion', result)
        self.assertIn('77', model.call_args.args[0][1]['content'])
        self.assertIn('25', model.call_args.args[0][1]['content'])
        execute.assert_not_called()

    def test_unconfirmed_or_foreign_draft_cannot_resume(self):
        initial = self.start()
        for row in (
            {'estado': 'PENDIENTE'},
            {'estado': 'REALIZADO', 'plan': {'recurso': 'presentaciones', 'accion': 'crear'}},
        ):
            with self.subTest(row=row), patch.object(coordinator.drafts, 'load', return_value=row), \
                 patch.object(coordinator, 'invoke') as invoke, self.assertRaises(AssistantError):
                coordinator.resume({}, initial['continuacion'], 'draft-id')
            invoke.assert_not_called()

    def test_scope_signature_and_expiration_are_checked(self):
        token = self.start()['continuacion']
        with patch.object(coordinator.drafts, 'scope', return_value={**SCOPE, 'local': 2}), self.assertRaises(AssistantError):
            coordinator.load(token)
        with self.assertRaises(AssistantError):
            coordinator.load(token + 'changed')
        with patch('itsdangerous.timed.time.time', return_value=9999999999), self.assertRaises(AssistantError):
            coordinator.load(token)

    def test_nested_handoff_returns_to_immediate_parent_before_root(self):
        first = self.start()
        state = coordinator.load(first['continuacion'])
        second = coordinator.coordinate({}, handoff('presentaciones', 'menajes'), 'Crear presentación', state=state)
        child = coordinator.load(second['continuacion'])
        self.assertEqual([f['agente'] for f in child['pila']], ['recetas', 'presentaciones'])
        plan = {'recurso': 'menajes', 'accion': 'crear', 'datos': {'nombre': 'Plato'}}
        coordinator.bind_plan(child, plan)
        with patch.object(coordinator.drafts, 'load', return_value={
            'estado': 'REALIZADO', 'plan': plan, 'resultado': {'id_menaje': 9}}), \
             patch('app.modules.asistente_ia.provider.respond', return_value=ANSWER):
            resumed = coordinator.resume({}, second['continuacion'], 'draft-id')
        self.assertEqual(resumed['agente'], 'presentaciones')
        self.assertEqual(coordinator.load(resumed['continuacion'])['pila'][0]['agente'], 'recetas')

    def test_unrelated_handoff_is_rejected(self):
        with self.assertRaises(AssistantError):
            coordinator.coordinate({}, handoff('recetas', 'menajes'), 'Crear receta')

    def test_runtime_exposes_only_authorized_dependency_handoffs(self):
        call = {'type': 'function_call', 'call_id': 'handoff', 'name': 'solicitar_especialista',
                'arguments': json.dumps(handoff()['traspaso'])}
        with patch('app.modules.asistente_ia.provider.respond', return_value=[call]) as model:
            result = SPECIALISTS['recetas'].run({}, 'Crear receta sin presentación existente')
        self.assertEqual(result['traspaso']['recurso'], 'presentaciones')
        definition = next(t for t in model.call_args.args[1] if t['name'] == 'solicitar_especialista')
        self.assertEqual(definition['parameters']['properties']['recurso']['enum'], ['presentaciones', 'productos', 'subproductos'])

    def test_runtime_rejects_unauthorized_handoff(self):
        call = {'type': 'function_call', 'call_id': 'handoff', 'name': 'solicitar_especialista',
                'arguments': json.dumps(handoff(resource='usuarios')['traspaso'])}
        with patch('app.modules.asistente_ia.provider.respond', side_effect=[[call], ANSWER]):
            result = SPECIALISTS['recetas'].run({}, 'Crear receta')
        self.assertNotIn('traspaso', result)

    def test_api_handoff_form_review_confirmation_and_return(self):
        from app.modules.asistente_ia import routes
        self.app.config['JWT_SECRET_KEY'] = 'communication-api-secret-at-least-32-characters'
        routes._attempts.clear()
        token = create_access_token(identity='1', additional_claims={'id_perfil': 1, 'id_local': 1})
        headers = {'Authorization': 'Bearer ' + token}
        client = self.app.test_client()
        call = {'type': 'function_call', 'call_id': 'delegate', 'name': 'solicitar_especialista',
                'arguments': json.dumps(handoff()['traspaso'])}
        plan = {'recurso': 'presentaciones', 'accion': 'crear', 'id': None, 'anterior': None,
                'datos': {'nombre_item': 'Hamburguesa'}}
        with patch.object(routes, 'obtener_sesion_actual', return_value=({}, 200)), \
             patch('app.modules.asistente_ia.provider.respond', side_effect=[[call], ANSWER]), \
             patch.object(routes.forms, 'prepare', return_value=plan), \
             patch.object(routes.tools, 'readable', return_value={}), \
             patch.object(routes.drafts, 'save', return_value='11111111-1111-4111-8111-111111111111'), \
             patch.object(routes.drafts, 'load') as stored:
            first = client.post('/api/asistente-ia/preparar', headers=headers,
                                json={'instruccion': 'Crear receta de hamburguesa'})
            self.assertEqual(first.status_code, 200)
            continuation = first.json['continuacion']
            review = client.post('/api/asistente-ia/formulario/preparar', headers=headers,
                                 json={'recurso': 'presentaciones', 'datos': {}, 'continuacion': continuation})
            self.assertEqual(review.status_code, 200)
            self.assertIn('_coordinacion', plan)
            stored.return_value = {'estado': 'PENDIENTE', 'plan': plan}
            args = {'continuacion': continuation, 'id_borrador': review.json['borrador']['id_borrador']}
            rejected = client.post('/api/asistente-ia/continuar', headers=headers, json=args)
            self.assertEqual(rejected.status_code, 409)
            stored.return_value = {'estado': 'REALIZADO', 'plan': plan,
                                   'resultado': {'id_presentacion_venta': 77}}
            resumed = client.post('/api/asistente-ia/continuar', headers=headers, json=args)
            self.assertEqual(resumed.status_code, 200)
            self.assertEqual(resumed.json['agente'], 'recetas')
            self.assertNotIn('continuacion', resumed.json)

    def test_missing_requirement_does_not_bypass_specialist_with_direct_form_shortcut(self):
        from app.modules.asistente_ia import routes
        self.app.config['JWT_SECRET_KEY'] = 'communication-api-secret-at-least-32-characters'
        routes._attempts.clear()
        token = create_access_token(identity='1', additional_claims={'id_perfil': 1, 'id_local': 1})
        call = {'type': 'function_call', 'call_id': 'delegate', 'name': 'solicitar_especialista',
                'arguments': json.dumps(handoff('presentaciones', 'menajes')['traspaso'])}
        with patch.object(routes, 'obtener_sesion_actual', return_value=({}, 200)), \
             patch('app.modules.asistente_ia.provider.respond', return_value=[call]) as model:
            response = self.app.test_client().post('/api/asistente-ia/preparar',
                headers={'Authorization': 'Bearer ' + token}, json={
                    'instruccion': 'Crear presentación de venta pero no existe el menaje, quiero crearlo'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json['agente'], 'menajes')
        self.assertIn('continuacion', response.json)
        model.assert_called_once()


if __name__ == '__main__':
    unittest.main()
