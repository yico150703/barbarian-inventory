import unittest
import json
from unittest.mock import patch

from app.modules.asistente_ia import purchases
from app.modules.asistente_ia.provider import AssistantError
from app.agents.orchestrator.router import route
from app.agents.compras.agent import events


LOCAL = {'id_local': 1, 'codigo': 'MIRAFLORES', 'nombre': 'BarBarian Miraflores',
         'direccion': 'C. Manuel Bonilla 108, Miraflores 15074'}


class PurchaseAssistantTests(unittest.TestCase):
    def test_missing_address_does_not_search_another_restaurant(self):
        with patch('app.modules.asistente_ia.provider.call') as call:
            report = events(local={'nombre': 'Santa Anita', 'direccion': ' '})
        self.assertEqual(report['estado'], 'sin_direccion')
        call.assert_not_called()

    def test_search_uses_active_restaurant_address(self):
        for name, address in (
                ('Miraflores', 'C. Manuel Bonilla 108, Miraflores 15074'),
                ('Barranco', 'Av. Pedro de Osma 144, Lima 15063'),
                ('Santa Anita', 'Av. Nicolás Ayllón, Santa Anita 15008'),
                ('Sheraton', 'Av. Paseo de la República 170, Lima 01')):
            with self.subTest(local=name), patch('app.modules.asistente_ia.provider.call',
                    return_value={'status': 'completed', 'output': []}) as call:
                report = events(local={'nombre': name, 'direccion': address})
            prompt = json.loads(call.call_args.args[1])['input']
            self.assertIn(address, prompt)
            self.assertEqual(report['local']['nombre'], name)
            if name != 'Sheraton':
                self.assertNotIn('Sheraton', prompt)
                self.assertNotIn('Estadio Nacional', prompt)

    def test_permissions_follow_native_menu(self):
        session = {'menu': [{'id_opcion_menu': 22, 'permisos': {'consultar': True}}]}
        self.assertTrue(purchases.allowed(session, 'ordenes_compra', 'consultar'))
        self.assertFalse(purchases.allowed(session, 'ordenes_compra', 'crear'))
        self.assertFalse(purchases.allowed(session, 'pedido_sugerido', 'crear'))

    def test_specialist_passes_active_restaurant_to_event_search(self):
        from app.agents.compras.agent import run
        with patch('app.modules.asistente_ia.tools.authorize'), \
             patch('app.agents.compras.agent.events', return_value={'estado': 'consultado'}) as search, \
             patch('app.agents.compras.agent.run_specialist', return_value={
                 'respuesta': 'Informe', 'plan': None, 'consultas': []}) as specialist:
            run({'local_activo': LOCAL}, 'hacer un pedido')
        search.assert_called_once_with('hacer un pedido', '', LOCAL)
        from app.agents.compras.agent import SKILLS
        self.assertEqual(specialist.call_args.args[-1], SKILLS)
        self.assertTrue(SKILLS[0].is_file())

    def test_purchase_skill_is_visible_in_agent_catalog(self):
        from app.agents.manifest import catalog
        agent = next(a for a in catalog()['agentes'] if a['id'] == 'compras')
        self.assertEqual(len(agent['skills']), 1)
        self.assertIn('Santa Anita', agent['skills'][0]['contenido'])

    def test_event_queries_and_new_orders_route_to_purchases(self):
        for instruction in ('hacer nuevo pedido', 'eventos cercanos a mi tienda',
                            'eventos cerca de Barranco', 'conciertos cercanos'):
            with self.subTest(instruction=instruction):
                self.assertEqual(route(instruction), 'compras')

    def prepare(self, extras, general=20):
        rows = [{'id_producto': 1, 'cantidad_sugerida': 100, 'presentacion': 6,
                 'nombre': 'Insumo', 'unidad': 'LTR'}]
        with patch('app.modules.asistente_ia.tools.authorize'), \
             patch('app.modules.asistente_ia.tools.records', return_value=rows):
            return purchases.prepare({}, 'crear', None,
                                     {'porcentaje_general': general, 'adicionales': extras})

    def test_compound_percentage_and_package_rounding(self):
        plan = self.prepare([{'id_producto': 1, 'porcentaje': 10}])
        self.assertEqual(plan['revision_compra'][0]['antes_de_redondear'], 132)
        self.assertEqual(plan['datos']['detalles'][0]['cantidad_solicitada'], 132)
        self.assertEqual(plan['datos']['accion'], 'GUARDAR_BORRADOR')
        self.assertEqual(self.prepare([], 21)['datos']['detalles'][0]['cantidad_solicitada'], 126)

    def test_unknown_duplicate_and_nonfinite_are_rejected(self):
        for extras in ([{'id_producto': 2, 'porcentaje': 10}],
                       [{'id_producto': 1, 'porcentaje': 10}] * 2,
                       [{'id_producto': 1, 'porcentaje': 'NaN'}]):
            with self.subTest(extras=extras), self.assertRaises(AssistantError):
                self.prepare(extras)

    def test_failure_to_search_is_not_no_events(self):
        with patch('app.modules.asistente_ia.provider.call', side_effect=AssistantError('Offline')):
            report = events(local=LOCAL)
        self.assertEqual(report['estado'], 'no_disponible')
        self.assertEqual(report['motivo'], 'Offline')

    def test_truncated_search_retries_and_preserves_official_sources(self):
        complete = {'status': 'completed', 'output': [{'type': 'message', 'content': [{
            'type': 'output_text', 'text': 'Evento verificado', 'annotations': [{
                'type': 'url_citation', 'title': 'Organizador', 'url': 'https://example.org/evento'}]}]}]}
        with patch('app.modules.asistente_ia.provider.call', side_effect=[
                {'status': 'incomplete', 'incomplete_details': {'reason': 'max_output_tokens'}}, complete]) as call:
            report = events('Concierto de Iron Maiden', local=LOCAL)
        self.assertEqual(report['estado'], 'consultado')
        self.assertEqual(report['fuentes'][0]['titulo'], 'Organizador')
        first = json.loads(call.call_args_list[0].args[1])
        second = json.loads(call.call_args_list[1].args[1])
        self.assertIn('Iron Maiden', first['input'])
        self.assertGreater(second['max_output_tokens'], first['max_output_tokens'])

    def test_incomplete_search_is_distinct_from_missing_sources(self):
        with patch('app.modules.asistente_ia.provider.call', return_value={
                'status': 'incomplete', 'output': []}):
            self.assertEqual(events(local=LOCAL)['estado'], 'busqueda_incompleta')

    def test_temporary_connection_failure_is_retried(self):
        from app.agents.compras.agent import search_response
        with patch('app.modules.asistente_ia.provider.call', side_effect=[
                AssistantError('Tiempo agotado', 504, retryable=True), {'status': 'completed'}]) as call:
            self.assertEqual(search_response({'input': 'eventos'})['status'], 'completed')
        self.assertEqual(call.call_count, 2)
        self.assertEqual(call.call_args.kwargs['timeout'], 90)

    def test_configuration_failure_is_not_retried(self):
        from app.agents.compras.agent import search_response
        with patch('app.modules.asistente_ia.provider.call', side_effect=AssistantError('Clave inválida', 502)) as call:
            with self.assertRaises(AssistantError):
                search_response({'input': 'eventos'})
        self.assertEqual(call.call_count, 1)

    def test_provider_distinguishes_timeout_from_connection_failure(self):
        from app.modules.asistente_ia import provider
        from urllib.error import URLError
        for failure, status in ((TimeoutError(), 504), (URLError(TimeoutError()), 504),
                                (URLError('Disconnected'), 502)):
            with self.subTest(failure=type(failure).__name__), \
                 patch.dict('os.environ', {'OPENAI_API_KEY': 'test-only'}), \
                 patch.object(provider, 'urlopen', side_effect=failure):
                with self.assertRaises(AssistantError) as caught:
                    provider.call('responses', b'{}')
                self.assertEqual(caught.exception.status, status)
                self.assertTrue(caught.exception.retryable)

    def test_explicit_link_from_search_is_preserved_without_inline_citation(self):
        url = 'https://example.org/evento'
        response = {'status': 'completed', 'output': [
            {'type': 'web_search_call', 'action': {'sources': [{'url': url, 'title': 'Agenda'}]}},
            {'type': 'message', 'content': [{'type': 'output_text',
             'text': f'Evento — Recinto — 17/10 20:30 — [Más información]({url})', 'annotations': []}]}]}
        with patch('app.modules.asistente_ia.provider.call', return_value=response):
            report = events(local=LOCAL)
        self.assertEqual(report['estado'], 'consultado')
        self.assertEqual(report['fuentes'][0]['url'], url)

    def test_unsearched_link_does_not_become_verified_source(self):
        response = {'status': 'completed', 'output': [{'type': 'message', 'content': [
            {'type': 'output_text', 'text': '[Más información](https://example.org/inventado)', 'annotations': []}]}]}
        with patch('app.modules.asistente_ia.provider.call', return_value=response):
            self.assertEqual(events(local=LOCAL)['estado'], 'sin_fuentes_verificables')

    def test_missing_sources_are_not_reworded_as_technical_failure(self):
        from app.agents.compras.agent import run
        with patch('app.modules.asistente_ia.tools.authorize'), \
             patch('app.agents.compras.agent.events', return_value={'estado': 'sin_fuentes_verificables'}), \
             patch('app.agents.compras.agent.run_specialist', return_value={
                 'respuesta': 'FALLÓ la consulta técnica', 'plan': None, 'consultas': []}):
            result = run({}, 'hacer un pedido')
        self.assertNotIn('FALLÓ', result['respuesta'])
        self.assertIn('sin fuentes verificables', result['respuesta'])

    def test_purchase_routing_and_recipe_isolation(self):
        self.assertEqual(route('Orden de compra con 20% más y receta sour'), 'compras')
        self.assertEqual(route('Aumenta 10%', 'ordenes_compra'), 'compras')
        self.assertEqual(route('Edita la receta del sour'), 'recetas')

    def test_unspecified_management_orders_route_to_purchases(self):
        for instruction in ('HACER UN PEDIDO', 'quiero hacer un pedido',
                            'prepara mi pedido', 'crear pedidos'):
            with self.subTest(instruction=instruction):
                self.assertEqual(route(instruction), 'compras')
        self.assertEqual(route('hacer un pedido de mesa'), 'salon')

    def test_manager_with_purchase_permissions_reaches_purchase_specialist(self):
        from app.agents.orchestrator.router import run
        session = {'perfil_activo': {'id_perfil': 2, 'nombre': 'Gerente'},
                   'menu': [{'id_opcion_menu': 22, 'permisos': {'consultar': True, 'crear': True}}]}
        self.assertTrue(purchases.allowed(session, 'ordenes_compra', 'crear'))
        with patch('app.agents.compras.agent.run', return_value={
                'respuesta': 'Revisemos tu pedido.', 'consultas': [], 'plan': None}) as specialist:
            result = run(session, 'HACER UN PEDIDO')
        specialist.assert_called_once_with(session, 'HACER UN PEDIDO', '', '')
        self.assertEqual(result['agente'], 'compras')
