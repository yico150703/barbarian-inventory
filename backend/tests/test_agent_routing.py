import unittest
from unittest.mock import patch

from app.agents.orchestrator.router import route
from app import create_app
from app.agents.carta_recetas.agent import run as run_catalog
from app.agents.inventario.agent import run as run_inventory


class AgentRoutingTests(unittest.TestCase):
    def test_inventory_requests_route_to_inventory_specialist(self):
        for request in ('Consulta el stock bajo mínimo', '¿Cómo va el conteo del equipo?',
                        '¿Cuántas ventas hubo ayer?', 'Stock actual del producto Alitas'):
            with self.subTest(request=request):
                self.assertEqual(route(request), 'inventario')

    def test_catalog_requests_route_to_catalog_specialist(self):
        for request in ('Crear producto', 'Cambia el proveedor del producto'):
            with self.subTest(request=request):
                self.assertEqual(route(request), 'carta_recetas')

    def test_five_specialists_are_routed_independently(self):
        for request, expected in (
            ('Crea una categoría de carta', 'categorias_carta'), ('Editar menaje Copa', 'menajes'),
            ('Agrega una presentación a la carta', 'presentaciones'), ('Crea un subproducto de salsa', 'subproductos'),
            ('Edita la receta de Alitas', 'recetas'), ('Crea una receta con subproductos', 'recetas'),
            ('Crea un subproducto para la receta', 'subproductos')):
            with self.subTest(request=request):
                self.assertEqual(route(request), expected)

    def test_corrections_keep_specialist_but_explicit_new_task_takes_precedence(self):
        self.assertEqual(route('Usa 0.5 kg', 'Crear recetas'), 'recetas')
        self.assertEqual(route('Crea un menaje', 'Crear recetas'), 'menajes')
        self.assertEqual(route('Crear producto', 'Crear recetas'), 'carta_recetas')
        self.assertEqual(route('Crear receta', 'Hacer un pedido de compra'), 'recetas')

    def test_cross_domain_request_is_left_for_orchestrator(self):
        self.assertEqual(route('Cambia la receta y revisa el stock'), 'orquestador')
        self.assertEqual(route('Crea un producto y consulta su stock'), 'orquestador')

    def test_short_correction_keeps_domain_from_previous_draft(self):
        self.assertEqual(route('Ponlo en 29.90', 'Editar promoción de Alitas'), 'promociones')

    def test_promotions_use_their_own_specialist(self):
        for request in ('Crea la promoción Barra libre', 'Crear promo', 'Consultar promociones',
                        'Editar promoción con presentaciones existentes'):
            with self.subTest(request=request):
                self.assertEqual(route(request), 'promociones')
        self.assertEqual(route('Crear presentación para una promoción'), 'presentaciones')

    def test_specialists_receive_only_their_domain_tools(self):
        app=create_app()
        answer=[{'type':'message','content':[{'type':'output_text','text':'Consulta lista.'}]}]
        for specialist,expected,forbidden in (
            (run_catalog,{'consultar','abrir_formulario','preparar_cambio'},{'consultar_inventario','formulario'}),
            (run_inventory,{'consultar_inventario','preparar_cambio'},{'consultar','formulario'}),
        ):
            with self.subTest(specialist=specialist.__module__), app.test_request_context():
                with patch('app.modules.asistente_ia.tools.allowed',return_value=True), \
                     patch('app.modules.asistente_ia.provider.respond',return_value=answer) as model:
                    specialist({'menu':[]},'Consulta')
                names={tool['name'] for tool in model.call_args.args[1]}
                self.assertTrue(expected.issubset(names))
                self.assertTrue(forbidden.isdisjoint(names))


if __name__ == '__main__':
    unittest.main()
