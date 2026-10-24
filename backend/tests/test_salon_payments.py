import os
import unittest
import uuid
from decimal import Decimal
from unittest.mock import patch

from flask_jwt_extended import create_access_token
from flask import g
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from app.core.extensions import db
import test_salon_orders as orders


@unittest.skipUnless(os.environ.get('LOCAL_SCOPE_TEST_DB') == '1', 'PostgreSQL temporal')
class SalonPaymentTests(unittest.TestCase):
    login = orders.SalonOrderTests.login
    guardar = orders.SalonOrderTests.guardar

    def setUp(self):
        orders.SalonOrderTests.setUp(self)
        db.session.execute(text('''INSERT INTO receta(id_receta,id_presentacion_venta) VALUES(9800,9800);
            INSERT INTO receta_detalle(id_receta,tipo_componente,id_producto,cantidad,unidad)
            VALUES(9800,'PRODUCTO',1,2,'C62');
            INSERT INTO usuario_perfiles(id_usuario,id_perfil,usuario_asignacion) VALUES(1,2,1);
            INSERT INTO usuario_local(id_usuario,id_local) VALUES(1,1),(1,2);'''))

    def tearDown(self):
        orders.SalonOrderTests.tearDown(self)

    def account(self):
        response = self.client.get('/api/salon/mesas/M01/cuenta', headers=self.headers)
        self.assertEqual(response.status_code, 200, response.json)
        return response.json

    def payload(self, **changes):
        return {'clave': str(uuid.uuid4()), 'revision': self.account()['revision'],
                'tipo': 'BOLETA', 'metodo': 'EFECTIVO', **changes}

    def pay(self, data):
        return self.client.post('/api/salon/mesas/M01/emitir', headers=self.headers, json=data)

    def stock(self, local):
        # setUp conserva un app_context para el rollback del fixture; cada petición
        # real tiene su propio g. Evita reutilizar aquí el local de la petición previa.
        g.pop('local_operativo', None)
        g.pop('hay_stock_local', None)
        token = create_access_token(identity='1', additional_claims={
            'tipo_token': 'operativo', 'id_perfil': 2, 'id_local': local})
        response = self.client.get('/api/inventarios/stock', headers={'Authorization': 'Bearer ' + token})
        self.assertEqual(response.status_code, 200, response.json)
        # Obtiene el stock sin depender de la envoltura del servicio.
        def find(value):
            if isinstance(value, dict):
                if value.get('id_producto') == 1 and 'stock_actual' in value:
                    return Decimal(str(value['stock_actual']))
                for nested in value.values():
                    match = find(nested)
                    if match is not None:
                        return match
            if isinstance(value, list):
                for nested in value:
                    match = find(nested)
                    if match is not None:
                        return match
        result = find(response.json)
        self.assertIsNotNone(result)
        return result

    def test_emit_once_stock_only_in_local_close_and_reopen(self):
        before, other = self.stock(1), self.stock(2)
        send_key = str(uuid.uuid4())
        self.assertEqual(self.guardar(enviar=True, clave=send_key).status_code, 200)
        self.assertEqual(self.stock(1), before)  # Enviar no descuenta.
        data = self.payload()
        result = self.pay(data)
        self.assertEqual(result.status_code, 201, result.json)
        self.assertEqual(result.json['total'], 31)
        self.assertFalse(result.json['fiscal'])
        self.assertEqual(self.stock(1), before - 6)  # 2 unidades * (2 receta + 1 salsa).
        self.assertEqual(self.stock(2), other)
        self.assertEqual(db.session.execute(text("SELECT id_local FROM movimiento_inventario WHERE motivo_movimiento='VENTA_SALON'")).scalar(), 1)
        retry = self.pay(data)
        self.assertEqual(retry.status_code, 200, retry.json)
        self.assertEqual(retry.json['id'], result.json['id'])
        self.assertEqual(self.stock(1), before - 6)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM salon_cobro')).scalar(), 1)
        self.assertEqual(self.account()['lineas'], [])
        self.assertEqual(self.client.get('/api/salon/estado-mesas', headers=self.headers).json['mesas'], [])
        self.assertEqual(self.guardar(enviar=True, clave=send_key).status_code, 409)
        self.assertEqual(self.guardar(enviar=True).status_code, 200)
        self.assertEqual(self.account()['total'], 31)
        # La imagen se reconstruye del snapshot aunque cambie el catálogo.
        db.session.execute(text('UPDATE presentacion_venta SET precio=99 WHERE id_presentacion_venta=9800'))
        receipt = self.client.get(f"/api/salon/comprobantes/{result.json['id']}", headers=self.headers)
        self.assertEqual(receipt.json['total'], 31)

    def test_stale_account_and_pending_drafts_rejected(self):
        self.guardar(enviar=True)
        data = self.payload()
        self.guardar(enviar=True)
        self.assertEqual(self.pay(data).status_code, 409)
        self.guardar()
        self.assertEqual(self.pay(self.payload()).status_code, 409)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM salon_cobro')).scalar(), 0)

    def test_missing_recipe_invalid_units_and_failure_roll_back_all(self):
        self.guardar(enviar=True)
        data = self.payload()
        db.session.execute(text('UPDATE receta SET activo=false WHERE id_receta=9800'))
        self.assertEqual(self.pay(data).status_code, 409)
        db.session.execute(text('UPDATE receta SET activo=true WHERE id_receta=9800'))
        with self.assertRaises(DBAPIError), db.session.begin_nested():
            db.session.execute(text("UPDATE receta_detalle SET unidad='Kg' WHERE id_receta=9800"))
        before = self.stock(1)
        with patch('app.modules.auth.salon_payments.registrar_actividad', side_effect=RuntimeError('fallo')):
            with self.assertRaises(RuntimeError), db.session.begin_nested():
                self.pay(data)
        self.assertEqual(self.stock(1), before)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM salon_cobro')).scalar(), 0)
        self.assertEqual(db.session.execute(text("SELECT count(*) FROM movimiento_inventario WHERE motivo_movimiento='VENTA_SALON'")).scalar(), 0)
        self.assertEqual(self.account()['total'], 31)

    def test_subproduct_yield_and_repeated_options(self):
        db.session.execute(text('''INSERT INTO subproducto(id_subproducto,codigo,nombre,rendimiento,unidad)
            VALUES(9800,'SP-9800','Mezcla prueba',4,'LTR');
            INSERT INTO subproducto_detalle(id_subproducto,id_producto,cantidad,unidad) VALUES(9800,1,8,'C62');
            INSERT INTO receta_detalle(id_receta,tipo_componente,id_subproducto,cantidad,unidad)
            VALUES(9800,'SUBPRODUCTO',9800,0.5,'LTR');
            UPDATE grupo_salsa SET permite_repetir=true WHERE id_grupo_salsa=9800;'''))
        self.guardar(enviar=True, lineas=[{**self.linea, 'opciones': [9800, 9800]}])
        before = self.stock(1)
        result = self.pay(self.payload())
        self.assertEqual(result.status_code, 201, result.json)
        self.assertEqual(self.stock(1), before - 10)  # (2 + .5*8/4 + 2 opciones) * 2

    def test_documents_methods_and_untrusted_total(self):
        self.guardar(enviar=True)
        data = self.payload()
        for changes in ({'metodo': 'OTRO'}, {'tipo': 'OTRO'}, {'tipo': 'FACTURA', 'documento': '123'},
                        {'tipo': 'BOLETA_ELECTRONICA', 'documento': '12345678', 'cliente': ''}):
            self.assertEqual(self.pay({**data, **changes}).status_code, 400)
        data.update(tipo='FACTURA', documento='20123456789', cliente='Empresa prueba', metodo='TARJETA', total=0.01, id_local=2)
        result = self.pay(data)
        self.assertEqual(result.status_code, 201, result.json)
        self.assertEqual(result.json['total'], 31)
        self.assertEqual(result.json['local'], 'Miraflores')
        self.assertEqual(result.json['cliente'], 'Empresa prueba')
        self.assertEqual(self.pay({**data, 'cliente': 'Otro'}).status_code, 409)

    def test_electronic_customer_and_local_read_access(self):
        self.guardar(enviar=True)
        result = self.pay(self.payload(tipo='BOLETA_ELECTRONICA', documento='12345678', cliente='Cliente prueba'))
        self.assertEqual(result.status_code, 201, result.json)
        db.session.execute(text('INSERT INTO usuario_local(id_usuario,id_local) VALUES(2,2)'))
        other = {'Authorization': 'Bearer ' + self.login(local=2).json['token']}
        self.assertEqual(self.client.get(f"/api/salon/comprobantes/{result.json['id']}", headers=other).status_code, 404)
        self.assertEqual(self.client.post('/api/salon/mesas/M01/emitir', headers=other, json=self.payload()).status_code, 409)
        self.assertEqual(self.client.get('/api/salon/mesas/M01/cuenta').status_code, 401)

    def test_other_waiter_cannot_charge_and_annulled_lines_not_charged(self):
        self.guardar(enviar=True)
        db.session.execute(text('INSERT INTO salon_pedido_asignacion SELECT id_pedido,mesa,1 FROM salon_pedido'))
        db.session.execute(text('UPDATE usuario_perfiles SET estado_registro=0 WHERE id_usuario=2 AND id_perfil=2'))
        self.assertEqual(self.client.get('/api/salon/mesas/M01/cuenta', headers=self.headers).status_code, 403)
        db.session.execute(text('UPDATE usuario_perfiles SET estado_registro=1 WHERE id_usuario=2 AND id_perfil=2'))
        # Gerente puede cobrar y no incluye las líneas anuladas.
        db.session.execute(text('INSERT INTO salon_linea_anulada(id_linea,id_responsable) SELECT id_linea,2 FROM salon_pedido_linea'))
        self.assertEqual(self.pay(self.payload()).status_code, 409)
        db.session.execute(text('DELETE FROM salon_pedido_asignacion'))
        self.guardar(enviar=True, lineas=[{**self.linea, 'cantidad': 1}])
        before = self.stock(1)
        result = self.pay(self.payload())
        self.assertEqual(result.status_code, 201, result.json)
        self.assertEqual(result.json['total'], 15.5)
        self.assertEqual(self.stock(1), before - 3)

    def test_integer_presentation_and_legacy_name(self):
        self.assertIn('1 PORCION', self.client.get('/api/salon/carta', headers=self.headers).json['productos'][0]['nombre'])
        self.guardar()
        db.session.execute(text("UPDATE salon_pedido_linea SET nombre='Prueba · 1.000 UNI'"))
        self.assertEqual(self.account()['lineas'][0]['nombre'], 'Prueba · 1 UNI')

    def test_promotion_charges_once_and_refills_consume_inventory(self):
                db.session.execute(text('''
                    INSERT INTO promocion(id_promocion,codigo,nombre,precio,activo)
                        VALUES(9800,'P-9800','Barra libre de alitas',29.90,true);
                    INSERT INTO promocion_grupo(id_promocion_grupo,id_promocion,cantidad_elegir,permite_repetir)
                        VALUES(9800,9800,1,false);
                    INSERT INTO promocion_opcion(id_promocion_grupo,id_presentacion_venta) VALUES(9800,9800);
                    INSERT INTO promocion_reposicion(id_promocion,id_presentacion_venta) VALUES(9800,9800);
                '''))
                promo={'id_promocion':9800,'cantidad':1,'selecciones':[
                        {'id_grupo':9800,'id_presentacion':9800,'opciones':[9800]}]}
                first=self.guardar(enviar=True,lineas=[promo])
                self.assertEqual(first.status_code,200,first.json)
                barra=next(l for l in first.json['lineas'] if l['id_promocion']==9800)
                refill={'id_presentacion':9800,'id_barra_libre':barra['ids_lineas'][0],
                                'cantidad':1,'comentario':'','opciones':[9800]}
                second=self.guardar(enviar=True,lineas=[refill])
                self.assertEqual(second.status_code,200,second.json)
                before=self.stock(1)
                result=self.pay(self.payload())
                self.assertEqual(result.status_code,201,result.json)
                self.assertEqual(result.json['total'],29.9)
                self.assertEqual(len(result.json['lineas']),2)
                reposicion=next(linea for linea in result.json['lineas'] if linea.get('barra_nombre'))
                self.assertEqual(reposicion['precio'],0)
                self.assertEqual(reposicion['barra_nombre'],'Barra libre de alitas')
                barra_cobrada=next(linea for linea in result.json['lineas'] if linea.get('id_promocion'))
                self.assertEqual(barra_cobrada['cantidad_reposiciones'],1)
                self.assertEqual(self.stock(1),before-6)

    def test_sale_after_count_on_same_day(self):
        db.session.execute(text("""UPDATE inventario_cierre SET
            fecha_inventario=(clock_timestamp() AT TIME ZONE 'America/Lima')::date,
            fecha_registro=(clock_timestamp() AT TIME ZONE 'America/Lima')-interval '1 hour'
            WHERE id_inventario_cierre=9"""))
        before = self.stock(1)
        self.guardar(enviar=True)
        self.assertEqual(self.pay(self.payload()).status_code, 201)
        self.assertEqual(self.stock(1), before - 6)
