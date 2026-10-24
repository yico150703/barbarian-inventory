import os
import unittest
from datetime import date
from decimal import Decimal

from flask_jwt_extended import create_access_token, verify_jwt_in_request
from sqlalchemy import text
from werkzeug.exceptions import Forbidden, NotFound, Conflict

from app import create_app
from app.core.extensions import db
from app.core.local_scope import local_actual, exigir_migracion_locales
from app.modules.inventarios import repository as inv
from app.modules.compras import repository as compras
from app.modules.movimientos import repository as mov
from app.modules.recepciones import repository as recep
from app.modules.auth.repository import listar_locales_usuario
from app.modules.usuarios.repository import listar_usuarios_permitidos, buscar_usuario_gestionable


@unittest.skipUnless(os.environ.get('LOCAL_SCOPE_TEST_DB') == '1', 'Requiere PostgreSQL temporal del runner')
class LocalScopeIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()
        self.app.config.update(TESTING=True, JWT_SECRET_KEY='local-scope-test-secret-at-least-32-characters')
        self.ctx = self.app.app_context()
        self.ctx.push()
        self.assertEqual(db.session.execute(text('SELECT current_database()')).scalar(), 'barbarito_test')

    def tearDown(self):
        db.session.rollback()
        db.session.remove()
        self.ctx.pop()

    def session(self, local=1, user=1, profile=1):
        token = create_access_token(identity=str(user), additional_claims={
            'tipo_token': 'operativo', 'id_perfil': profile, 'id_local': local})
        return self.app.test_request_context(headers={'Authorization': 'Bearer ' + token})

    def test_read_queries_and_locks(self):
        with self.session():
            verify_jwt_in_request()
            for func, args in [
                (inv.contar_productos_activos,()), (inv.buscar_inventario_de_hoy,()),
                (inv.buscar_ultimo_inventario_cerrado,()), (inv.buscar_ultimos_inventarios,()),
                (inv.consultar_stock_actual,()), (inv.buscar_cabecera_inventario_actual,()),
                (inv.consultar_productos_para_inventario,(9,)), (inv.buscar_inventario_por_fecha,(date(2020,1,10),)),
                (inv.listar_inventarios_para_revision,()), (inv.buscar_inventario_cerrado_por_id,(9,)),
                (inv.listar_productos_revision,(9,)), (inv.bloquear_inventario_cerrado,(9,)),
                (inv.buscar_producto_para_correccion,(9,1)), (inv.listar_historial_correcciones,(9,)),
                (compras.listar_productos_para_compra,()), (compras.listar_historial_ordenes,()),
                (compras.obtener_detalle_orden_historial,(1,)), (compras.obtener_orden_historial,(1,True)),
                (compras.obtener_total_recibido_orden,(1,)), (recep.listar_pendientes_recepcion,()),
                (recep.bloquear_orden,(1,)), (recep.obtener_producto_pendiente,(1,1,1)),
                (recep.orden_tiene_cantidades_pendientes,(1,)), (recep.listar_historial_recepciones,()),
                (recep.obtener_factura_recepcion,(1,True)), (recep.listar_detalles_factura,(1,)),
                (recep.calcular_totales_orden,(1,)), (mov.buscar_movimiento_creado,(1,)),
                (mov.listar_detalles_movimiento_creado,(1,)),
            ]:
                with self.subTest(func=func.__name__), db.session.begin_nested():
                    func(*args)

    def test_empty_store_and_cross_store_ids(self):
        with self.session(local=2):
            verify_jwt_in_request()
            self.assertEqual(inv.buscar_ultimos_inventarios(), [])
            self.assertEqual(compras.listar_historial_ordenes(), [])
            self.assertEqual(recep.listar_historial_recepciones(), [])
            self.assertEqual(recep.listar_pendientes_recepcion(), [])
            stocks = inv.consultar_stock_actual()
            self.assertEqual(len(stocks), 1)  # Catalogo compartido.
            self.assertEqual(stocks[0]['stock_minimo'], Decimal(20))
            self.assertIn(stocks[0]['stock_actual'], (None, Decimal(0)))
            for func, args in [
                (inv.buscar_inventario_cerrado_por_id,(9,)),
                (inv.guardar_detalle_inventario,(9,1,99)),
                (inv.eliminar_inventario_provisional,(9,)),
                (compras.obtener_orden_historial,(1,)),
                (compras.crear_detalle_orden,(1,1,5)),
                (recep.obtener_factura_recepcion,(1,)),
                (recep.actualizar_cantidad_recepcion,(1,99)),
                (mov.listar_detalles_movimiento_creado,(1,)),
            ]:
                with self.subTest(func=func.__name__), self.assertRaises(NotFound):
                    func(*args)

    def test_new_records_keep_local_and_same_inventory_date(self):
        with self.session(local=2):
            verify_jwt_in_request()
            inventory = inv.crear_inventario_actual(1,date(2020,1,10))
            self.assertIsNotNone(inventory)
            inv.guardar_detalle_inventario(inventory,1,25)
            self.assertEqual(inv.contar_detalles_inventario(inventory),1)
            order = compras.crear_cabecera_orden(compras.generar_codigo_orden(),'ENVIADA',1,date.today())
            compras.crear_detalle_orden(order,1,10)
            receipt = recep.crear_factura_recepcion(order,1,'TEST-002',date.today(),1)
            recep.crear_detalle_recepcion(receipt,1,2)
            movement = mov.crear_cabecera_movimiento(mov.generar_codigo_movimiento(),
                'SALIDA','MERMA',date.today(),1,None,None,'Prueba')
            mov.crear_detalle_movimiento(movement,1,1)
            for table,pk,key in [('inventario_cierre','id_inventario_cierre',inventory),
                ('orden_compra','id_orden_compra',order),('movimiento_inventario','id_movimiento_inventario',movement)]:
                self.assertEqual(db.session.execute(text(f'SELECT id_local FROM {table} WHERE {pk}=:id'),{'id':key}).scalar(),2)
            self.assertEqual(len(recep.listar_historial_recepciones()),1)

    def test_supplier_history_survives_catalog_change(self):
        with self.session():
            verify_jwt_in_request()
            db.session.execute(text('UPDATE producto SET id_proveedor=2 WHERE id_producto=1'))
            self.assertEqual(compras.obtener_detalle_orden_historial(1)[0]['id_proveedor'],1)
            self.assertEqual(recep.listar_pendientes_recepcion()[0]['id_proveedor'],1)
            self.assertIsNotNone(recep.obtener_producto_pendiente(1,1,1))
            order=compras.crear_cabecera_orden(compras.generar_codigo_orden(),'ENVIADA',1,date.today())
            compras.crear_detalle_orden(order,1,5)
            self.assertEqual(compras.obtener_detalle_orden_historial(order)[0]['id_proveedor'],2)

    def test_global_admin_and_assigned_manager(self):
        self.assertEqual(len(listar_locales_usuario(1,1)),2)
        self.assertEqual(len(listar_locales_usuario(2,2)),1)
        self.assertEqual(len(listar_usuarios_permitidos(1,2)),2)
        self.assertEqual(len(listar_usuarios_permitidos(2,2)),0)
        self.assertIsNotNone(buscar_usuario_gestionable(2,1,2))
        with self.session(local=2,user=2,profile=2):
            verify_jwt_in_request()
            with self.assertRaises(Forbidden): local_actual()

    def test_revoked_local_denies_existing_token(self):
        db.session.execute(text('UPDATE usuario_local SET estado_registro=0 WHERE id_usuario=2'))
        with self.session(local=1,user=2,profile=2):
            verify_jwt_in_request()
            with self.assertRaises(Forbidden): local_actual()

    def test_api_cross_store_returns_json_404(self):
        db.session.execute(text('INSERT INTO usuario_local(id_usuario,id_local) VALUES(2,2) ON CONFLICT DO NOTHING'))
        token=create_access_token(identity='2', additional_claims={
            'tipo_token':'operativo','id_perfil':2,'id_local':2})
        response=self.app.test_client().get('/api/inventarios/revisiones/9',
            headers={'Authorization':'Bearer '+token})
        self.assertEqual(response.status_code,404)
        self.assertIn('mensaje',response.json)

    def test_api_pending_migration_returns_json_409(self):
        db.session.execute(text('ALTER TABLE inventario_cierre DROP CONSTRAINT uq_inventario_local_fecha'))
        token=create_access_token(identity='2', additional_claims={
            'tipo_token':'operativo','id_perfil':2,'id_local':1})
        response=self.app.test_client().get('/api/inventarios/stock',
            headers={'Authorization':'Bearer '+token})
        self.assertEqual(response.status_code,409)
        self.assertIn('archivo 03',response.json['mensaje'])

    def test_missing_migration_fails_cleanly(self):
        db.session.execute(text('ALTER TABLE inventario_cierre DROP CONSTRAINT uq_inventario_local_fecha'))
        with self.session():
            verify_jwt_in_request()
            with self.assertRaises(Conflict): exigir_migracion_locales()


class AdminOperationalRestrictionsTests(unittest.TestCase):
    def test_admin_denied_even_with_inventory_permissions(self):
        from unittest.mock import patch
        from app.modules.auth.service import cambiar_local_activo
        app = create_app()
        app.config.update(TESTING=True, JWT_SECRET_KEY='operational-restriction-test-secret-32-characters')
        with app.app_context():
            token = create_access_token(identity='1', additional_claims={'tipo_token':'operativo','id_perfil':1,'id_local':1})
            with patch.object(db.session, 'execute') as execute:
                for path in ['/api/inventarios/stock','/api/inventarios/resumen','/api/inventarios/revisiones/9','/api/movimientos/formulario','/api/movimientos/seguimiento','/api/ordenes-compra/formulario','/api/recepciones/pendientes']:
                    result = app.test_client().get(path, headers={'Authorization':'Bearer '+token})
                    self.assertEqual(result.status_code,403,result.json)
                execute.assert_not_called()
            self.assertEqual(cambiar_local_activo(1,{'tipo_token':'operativo','id_perfil':1},{'id_local':2})[1],403)
