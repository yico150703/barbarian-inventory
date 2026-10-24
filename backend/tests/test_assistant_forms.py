import unittest
from unittest.mock import patch

from flask_jwt_extended import create_access_token

from app import create_app
from app.modules.asistente_ia import forms, routes
from app.modules.asistente_ia.provider import AssistantError


CATEGORY = {'id_categoria': 1, 'nombre': 'Bebidas', 'prefijo': 'BEB', 'activo': True}
SUPPLIER = {'id_proveedor': 3, 'nombre': 'Proveedor real', 'activo': True, 'ids_categorias': [1]}
OPTIONS = {'categorias': [CATEGORY], 'proveedores': [SUPPLIER], 'unidades_medida': []}


class AssistantFormTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config.update(TESTING=True, JWT_SECRET_KEY='assistant-forms-secret-at-least-32-characters')
        routes._attempts.clear()
        with self.app.app_context():
            self.headers = {'Authorization': 'Bearer ' + create_access_token(identity='1',
                additional_claims={'id_perfil': 1, 'id_local': 1, 'tipo_token': 'operativo'})}
        self.client = self.app.test_client()

    def test_direct_intents(self):
        for text, expected in (
            ('Quiero crear una categoría de productos', 'categorias_productos'),
            ('Crear proveedor', 'proveedores'), ('agrega un nuevo producto', 'productos'),
            ('Necesito un nuevo proveedor', 'proveedores'),
            ('Crear producto del proveedor existente', 'productos'),
            ('Editar proveedor', None), ('crear categoría de carta', 'categorias_carta'),
            ('Crear presentación de venta', 'presentaciones'), ('Crear menaje', 'menajes'),
            ('ME GUSTARIA AGREGAR UNA NUEVA CATEGORIA', 'categoria_ambigua'),
            ('QUIERO HACER UNA CATEGORÍA', 'categoria_ambigua'),
            ('crear categoría', 'categoria_ambigua'), ('Nueva categoría para inventario', 'categorias_productos'),
            ('revisar productos', None), ('crear receta', None)):
            with self.subTest(text=text):
                self.assertEqual(forms.detect(text), expected)

    def test_ambiguous_category_asks_before_opening_any_form(self):
        with patch.object(routes, 'obtener_sesion_actual', return_value=({'menu': []}, 200)), \
             patch.object(routes.db.session, 'rollback'), patch.object(forms.tools, 'allowed', return_value=True), \
             patch.object(forms.tools, 'native') as native, patch.object(routes.agent, 'run') as model:
            response = self.client.post('/api/asistente-ia/preparar', headers=self.headers,
                json={'instruccion': 'ME GUSTARIA AGREGAR UNA NUEVA CATEGORIA'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json['respuesta'], forms.CATEGORY_QUESTION)
        self.assertEqual(len(response.json['opciones']), 2)
        self.assertNotIn('formulario', response.json)
        self.assertIsNone(response.json['borrador'])
        native.assert_not_called(); model.assert_not_called()

    def test_plain_category_answer_only_resolves_when_question_is_pending(self):
        self.assertIsNone(forms.category_choice('de carta', ''))
        self.assertEqual(forms.category_choice('de carta', forms.CATEGORY_QUESTION), 'categorias_carta')
        self.assertEqual(forms.category_choice('productos', forms.CATEGORY_QUESTION), 'categorias_productos')

    def test_natural_category_answers_resolve_both_question_wordings(self):
        for question in (forms.CATEGORY_QUESTION,
                         '¿La categoría es para productos de inventario o para artículos de la carta?'):
            for answer, expected in (
                ('ES PARA PRODUCTO', 'categorias_productos'),
                ('Es para los productos de inventario', 'categorias_productos'),
                ('sí, productos', 'categorias_productos'),
                ('Es para la carta', 'categorias_carta'),
                ('para artículos de la carta', 'categorias_carta'),
                ('producto de carta', 'categorias_carta'),
                ('productos o carta', None),
                ('no es para producto', None),
                ('crear proveedor', None),
            ):
                with self.subTest(question=question, answer=answer):
                    self.assertEqual(forms.category_choice(answer, question), expected)
        self.assertIsNone(forms.category_choice('es para producto', '¿Quieres consultar el inventario?'))

    def test_screenshot_category_followup_opens_form_without_mixed_domain_routing(self):
        with patch.object(routes, 'obtener_sesion_actual', return_value=({'menu': []}, 200)), \
             patch.object(routes.db.session, 'rollback'), patch.object(forms.tools, 'authorize'), \
             patch.object(forms.tools, 'allowed', return_value=True), \
             patch.object(forms.tools, 'native', return_value=OPTIONS), \
             patch.object(routes.agent, 'run') as model:
            first = self.client.post('/api/asistente-ia/preparar', headers=self.headers,
                json={'instruccion': 'QUIERO HACER UNA CATEGORÍA'})
            self.assertEqual(first.status_code, 200)
            self.assertEqual(len(first.json['opciones']), 2)
            for question in (first.json['respuesta'],
                             '¿La categoría es para productos de inventario o para artículos de la carta?'):
                result = self.client.post('/api/asistente-ia/preparar', headers=self.headers,
                    json={'instruccion': 'ES PARA PRODUCTO', 'borrador_previo': question})
                self.assertEqual(result.status_code, 200)
                self.assertEqual(result.json['formulario']['recurso'], 'categorias_productos')
        model.assert_not_called()

    def test_ambiguity_options_respect_permissions(self):
        with patch.object(routes, 'obtener_sesion_actual', return_value=({'menu': []}, 200)), \
             patch.object(routes.db.session, 'rollback'), \
             patch.object(forms.tools, 'allowed', side_effect=lambda s, r, a='consultar': r == 'categorias_carta'):
            response = self.client.post('/api/asistente-ia/preparar', headers=self.headers,
                json={'instruccion': 'crear categoría'})
        self.assertEqual(response.json['opciones'], [{'etiqueta': 'Categoría de carta', 'instruccion': 'Crear categoría de carta'}])

    def test_permission_checked_before_loading_options(self):
        with patch.object(forms.tools, 'authorize', side_effect=AssistantError('Sin permiso', 403)), \
             patch.object(forms.tools, 'native') as native, self.assertRaises(AssistantError):
            forms.open_form({}, 'proveedores')
        native.assert_not_called()

    def test_unknown_form_rejected(self):
        with self.assertRaises(AssistantError):
            forms.open_form({}, 'usuarios')

    def prepare(self, resource, data):
        with patch.object(forms.tools, 'authorize'), \
             patch.object(forms.tools, 'allowed', return_value=True), \
             patch.object(forms.tools, 'native', return_value=OPTIONS), \
             patch.object(forms.tools, 'prepare', return_value={'datos': data}) as prepare:
            result = forms.prepare({}, resource, data)
        return result, prepare

    def test_dependency_links_only_include_authorized_creations(self):
        with patch.object(forms.tools, 'authorize'), \
             patch.object(forms.tools, 'native', return_value=OPTIONS), \
             patch.object(forms.tools, 'allowed', side_effect=lambda s, r, a='consultar': r != 'proveedores'):
            form = forms.open_form({}, 'productos')
        self.assertEqual(form['dependencias_creables'], ['categorias_productos'])

    def test_presentation_loads_real_form_endpoint_and_normalizes_category_ids(self):
        options = {'categorias': [{'id_categoria_carta': 8, 'nombre': 'Piqueos', 'activo': True}],
                   'menajes': [{'id_menaje': 4, 'nombre': 'Plato', 'activo': True}]}
        with patch.object(forms.tools, 'authorize'), patch.object(forms.tools, 'allowed', return_value=True), \
             patch.object(forms.tools, 'native', return_value=options) as native:
            form = forms.open_form({}, 'presentaciones')
        native.assert_called_once_with('/carta/presentaciones/formulario')
        self.assertEqual(form['categorias'][0]['id_categoria'], 8)
        self.assertEqual(form['dependencias_creables'], ['categorias_carta', 'menajes'])

    def test_presentation_requires_valid_dependencies_and_preserves_existing_item(self):
        form = {'tipos': ['DIRECTO', 'PREPARADO'], 'categorias': [{'id_categoria': 8, 'activo': True}],
                'menajes': [{'id_menaje': 4, 'activo': True}],
                'items': [{'id_item_carta': 2, 'nombre': 'Alitas', 'tipo': 'PREPARADO', 'id_categoria_carta': 8, 'activo': True}]}
        data = {'id_item_carta': None, 'nombre_item': 'Alitas', 'tipo_item': 'PREPARADO', 'id_categoria_carta': 8,
                'id_menaje': 4, 'contenido': 12, 'unidad': 'C62', 'precio': 39.90, 'activo': True}
        forms.validate_presentation(form, dict(data))
        forms.validate_presentation(form, {**data, 'id_item_carta': 2})
        for change in ({'id_categoria_carta': 9}, {'id_menaje': 99}, {'precio': 'NaN'},
                       {'contenido': -1}, {'id_item_carta': 2, 'nombre_item': 'Otra'}, {'id_item_carta': True}):
            with self.subTest(change=change), self.assertRaises(AssistantError):
                forms.validate_presentation(form, {**data, **change})

    def test_category_duplicate_including_inactive_rejected(self):
        for data in ({'nombre': 'Bebidas', 'prefijo': 'ABC'}, {'nombre': 'Otra', 'prefijo': 'BEB'}):
            with self.subTest(data=data), self.assertRaises(AssistantError):
                self.prepare('categorias_productos', data)

    def test_category_normalizes_prefix_without_writing(self):
        _, prepare = self.prepare('categorias_productos', {'nombre': ' Nueva ', 'prefijo': 'nue'})
        self.assertEqual(prepare.call_args.args[4], {'nombre': 'Nueva', 'prefijo': 'NUE'})

    def test_supplier_requires_existing_categories(self):
        for ids in ([], [9], [1, 1], [True], '1'):
            with self.subTest(ids=ids), self.assertRaises(AssistantError):
                self.prepare('proveedores', {'nombre': 'Nuevo', 'ids_categorias': ids})
        _, prepare = self.prepare('proveedores', {'nombre': 'Nuevo', 'ids_categorias': [1]})
        self.assertEqual(prepare.call_args.args[1:4], ('proveedores', 'crear', None))

    def test_product_rejects_invalid_relationships_and_amounts(self):
        data = {'nombre': 'Producto', 'id_categoria': 1, 'id_proveedor': 3, 'unidad': 'KGM', 'presentacion': 1}
        for changes in ({'id_categoria': 9}, {'id_proveedor': 7}, {'presentacion': 0},
                        {'presentacion': 'NaN'}, {'unidad': 'GRM'}, {'id_categoria': True}):
            with self.subTest(changes=changes), self.assertRaises(AssistantError):
                self.prepare('productos', {**data, **changes})
        _, prepare = self.prepare('productos', data)
        self.assertEqual(prepare.call_args.args[4], data)

    def test_hidden_fields_are_rejected(self):
        with self.assertRaises(AssistantError):
            self.prepare('proveedores', {'nombre': 'Nuevo', 'ids_categorias': [1], 'id_local': 2})

    def test_direct_route_returns_form_without_model_or_draft(self):
        with patch.object(routes, 'obtener_sesion_actual', return_value=({'menu': []}, 200)), \
             patch.object(routes.db.session, 'rollback'), \
             patch.object(forms.tools, 'authorize'), \
             patch.object(forms.tools, 'native', return_value=OPTIONS), \
             patch.object(routes.agent, 'run') as model, \
             patch.object(routes.drafts, 'save') as save:
            result = self.client.post('/api/asistente-ia/preparar', headers=self.headers,
                json={'instruccion': 'crear proveedor', 'borrador_previo': 'Consulta anterior'})
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json['formulario']['proveedores'], [SUPPLIER])
        self.assertIsNone(result.json['borrador'])
        model.assert_not_called(); save.assert_not_called()

    def test_form_submission_only_saves_review_draft(self):
        plan = {'recurso': 'proveedores', 'accion': 'crear', 'id': None, 'anterior': None,
                'datos': {'nombre': 'Nuevo', 'ids_categorias': [1]}}
        with patch.object(routes, 'obtener_sesion_actual', return_value=({'menu': []}, 200)), \
             patch.object(forms, 'prepare', return_value=plan), \
             patch.object(routes.tools, 'readable', return_value={'nombre': 'Nuevo', 'ids_categorias': ['Bebidas']}), \
             patch.object(routes.drafts, 'save', return_value='draft-id') as save, \
             patch.object(routes.tools, 'execute') as execute:
            result = self.client.post('/api/asistente-ia/formulario/preparar', headers=self.headers,
                json={'recurso': 'proveedores', 'datos': plan['datos']})
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json['borrador']['id_borrador'], 'draft-id')
        save.assert_called_once_with(plan); execute.assert_not_called()

    def test_missing_authentication_rejected(self):
        for path in ('formulario', 'formulario/preparar'):
            self.assertEqual(self.client.post('/api/asistente-ia/' + path, json={}).status_code, 401)
