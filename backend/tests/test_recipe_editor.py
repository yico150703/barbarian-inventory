import unittest
from decimal import Decimal
from unittest.mock import patch

from flask_jwt_extended import create_access_token

from app import create_app
from app.core.extensions import db
from app.modules.recetas.editor_service import (
    DatosInvalidos, cantidad, guardar_receta, validar_componentes, validar_grupo,
)


class RecipeValidationTests(unittest.TestCase):
    def test_cantidades_validas(self):
        self.assertEqual(cantidad('0.060'), Decimal('0.060'))
        self.assertEqual(cantidad(8), Decimal(8))

    def test_cantidades_invalidas(self):
        for valor in [None, True, '', 0, -1, 'NaN', 'Infinity', '0.0001', '1000000000']:
            with self.subTest(valor=valor), self.assertRaises(DatosInvalidos):
                cantidad(valor)

    @patch('app.modules.recetas.editor_service.repo.ingrediente')
    def test_unidad_procede_de_inventario(self, ingrediente):
        ingrediente.return_value = {'unidad': 'Kg', 'activo': True}
        filas = validar_componentes([{'tipo_componente': 'PRODUCTO', 'id': 1, 'cantidad': '0.06', 'unidad': 'L'}])
        self.assertEqual(filas[0]['unidad'], 'Kg')

    @patch('app.modules.recetas.editor_service.repo.ingrediente')
    def test_no_acepta_productos_de_carta_ni_duplicados(self, ingrediente):
        ingrediente.return_value = {'unidad': 'Kg', 'activo': True}
        with self.assertRaises(DatosInvalidos):
            validar_componentes([{'tipo_componente': 'ITEM_CARTA', 'id': 1, 'cantidad': 2}])
        fila = {'tipo_componente': 'PRODUCTO', 'id': 1, 'cantidad': 2}
        with self.assertRaises(DatosInvalidos):
            validar_componentes([fila, fila])

    @patch('app.modules.recetas.editor_service.repo.ingrediente')
    def test_preserva_subproducto_inactivo_existente(self, ingrediente):
        ingrediente.return_value = {'unidad': 'Kg', 'activo': False}
        fila = {'tipo_componente': 'SUBPRODUCTO', 'id': 2, 'cantidad': 1}
        self.assertEqual(validar_componentes([fila], {('SUBPRODUCTO', 2)})[0]['id'], 2)
        with self.assertRaises(DatosInvalidos):
            validar_componentes([fila])

    @patch('app.modules.recetas.editor_service.repo.ingrediente')
    def test_salsas_limite_y_repeticion(self, ingrediente):
        ingrediente.return_value = {'unidad': 'Kg', 'activo': True}
        grupo = {'cantidad_maxima': 2, 'permite_repetir': False, 'opciones': [{'id': 1, 'cantidad': '0.06'}]}
        with self.assertRaises(DatosInvalidos):
            validar_grupo(grupo)
        grupo['permite_repetir'] = True
        self.assertEqual(validar_grupo(grupo)['cantidad_maxima'], 2)
        grupo['opciones'][0]['tipo_componente'] = 'SUBPRODUCTO'
        with self.assertRaises(DatosInvalidos):
            validar_grupo(grupo)

    def test_opciones_desactivadas(self):
        self.assertIsNone(validar_grupo(None))


class RecipeSavingTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config.update(TESTING=True, JWT_SECRET_KEY='recipe-test-key-at-least-32-characters-long')
        self.context = self.app.app_context()
        self.context.push()
        self.data = {
            'id_presentacion_venta': 9,
            'instrucciones': 'Mezclar y servir.', 'activo': True,
            'componentes': [{'tipo_componente': 'PRODUCTO', 'id': 1, 'cantidad': '2'}],
            'grupo_salsa': None,
        }
        self.previous = {'id_receta': 10, 'id_item_carta': 8, 'id_presentacion_venta': 9, 'id_menaje': 1, 'activo': True, 'tipo': 'PREPARADO', 'unidad': 'UNI', 'contenido': Decimal('1')}
        self.repo_patch = patch('app.modules.recetas.editor_service.repo')
        self.repo = self.repo_patch.start()
        self.repo.opciones_check.side_effect = lambda name: ['DIRECTO', 'PORCIONADO', 'PREPARADO'] if name == 'ck_item_carta_tipo' else ['UNI', 'L']
        self.repo.ingrediente.return_value = {'unidad': 'UNI', 'activo': True}
        self.repo.buscar_receta.return_value = self.previous
        self.repo.detalles.return_value = []
        self.repo.grupo.return_value = None
        self.repo.ejecutar.return_value.scalar.return_value = True
        self.repo.filas.return_value = [self.previous]
        self.commit_patch = patch.object(db.session, 'commit')
        self.commit = self.commit_patch.start()
        self.rollback_patch = patch.object(db.session, 'rollback')
        self.rollback = self.rollback_patch.start()
        self.audit_patch = patch('app.modules.recetas.editor_service.registrar_cambio')
        self.audit = self.audit_patch.start()
        self.activity_patch = patch('app.modules.recetas.editor_service.registrar_actividad')
        self.activity_patch.start()

    def tearDown(self):
        patch.stopall()
        self.context.pop()

    def test_editar_conserva_precio_y_registra_auditoria(self):
        respuesta, status = guardar_receta(1, self.data, 10)
        self.assertEqual(status, 200)
        self.assertEqual(respuesta['id_receta'], 10)
        self.repo.reemplazar_detalles.assert_called_once()
        self.repo.guardar_grupo.assert_called_once_with(9, None)
        sqls = [str(c.args[0]) for c in self.repo.ejecutar.call_args_list]
        self.assertFalse(any('UPDATE presentacion_venta' in s or 'UPDATE item_carta' in s for s in sqls))
        self.assertTrue(all('precio' not in s for s in sqls))
        self.audit.assert_called_once()
        self.commit.assert_called_once()

    def test_crear_solo_para_presentacion_existente(self):
        self.repo.ejecutar.return_value.scalar.return_value = False
        self.repo.ejecutar.return_value.scalar_one.return_value = 30
        respuesta, status = guardar_receta(1, self.data)
        self.assertEqual(status, 201)
        self.assertEqual(respuesta['id_receta'], 30)
        self.assertFalse(any('INSERT INTO presentacion_venta' in c.args[0] or 'INSERT INTO item_carta' in c.args[0] for c in self.repo.ejecutar.call_args_list))
        self.commit.assert_called_once()

    def test_rechaza_presentacion_sin_seleccionar_y_receta_duplicada(self):
        self.assertEqual(guardar_receta(1, {**self.data, 'id_presentacion_venta': None})[1], 400)
        self.assertEqual(guardar_receta(1, self.data)[1], 400)
        self.commit.assert_not_called()

    def test_receta_no_encontrada(self):
        self.repo.buscar_receta.return_value = None
        self.assertEqual(guardar_receta(1, self.data, 999)[1], 404)
        self.commit.assert_not_called()

    def test_directo_rechaza_multiples_ingredientes(self):
        self.previous['tipo'] = 'DIRECTO'
        self.data['componentes'].append({'tipo_componente': 'PRODUCTO', 'id': 2, 'cantidad': 1})
        self.assertEqual(guardar_receta(1, self.data, 10)[1], 400)
        self.repo.reemplazar_detalles.assert_not_called()
        self.commit.assert_not_called()

    def test_no_permite_editar_datos_de_carta(self):
        self.data['tipo_item'] = 'DIRECTO'
        respuesta, status = guardar_receta(1, self.data, 10)
        self.assertEqual(status, 400)
        self.assertIn('Carta', respuesta['mensaje'])
        self.repo.reemplazar_detalles.assert_not_called()

    def test_porcionado_conserva_varios_ingredientes(self):
        self.previous['tipo'] = 'PORCIONADO'
        self.data['componentes'].append({'tipo_componente': 'PRODUCTO', 'id': 2, 'cantidad': '0.05'})
        self.assertEqual(guardar_receta(1, self.data, 10)[1], 200)
        self.assertEqual(len(self.repo.reemplazar_detalles.call_args.args[1]), 2)

    def test_unidad_no_habilitada_rechazada(self):
        self.data['unidad_presentacion'] = 'Kg'
        self.assertEqual(guardar_receta(1, self.data, 10)[1], 400)
        self.commit.assert_not_called()

    def test_fallo_auditoria_revierte_todo(self):
        self.audit.side_effect = RuntimeError('fallo')
        with self.assertRaises(RuntimeError):
            guardar_receta(1, self.data, 10)
        self.rollback.assert_called_once()
        self.commit.assert_not_called()

    def test_guardado_exige_permiso_de_escritura(self):
        token = create_access_token(identity='1', additional_claims={'tipo_token': 'operativo', 'id_perfil': 2})
        with patch.object(db.session, 'execute') as execute:
            execute.return_value.scalar.return_value = False
            client = self.app.test_client()
            headers = {'Authorization': f'Bearer {token}'}
            self.assertEqual(client.post('/api/recetas', headers=headers, json=self.data).status_code, 403)
            self.assertEqual(client.put('/api/recetas/10', headers=headers, json=self.data).status_code, 403)
            self.repo.reemplazar_detalles.assert_not_called()


if __name__ == '__main__':
    unittest.main()
