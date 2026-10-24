import os
import unittest
import uuid
from decimal import Decimal
from unittest.mock import patch
from flask import g
from flask_jwt_extended import create_access_token
from sqlalchemy import text
from app.core.extensions import db
import test_salon_orders as orders


@unittest.skipUnless(os.environ.get('OPERATIONAL_TEST_DB')=='1','Requiere migración de jornadas en PostgreSQL temporal')
class OperationalTests(unittest.TestCase):
    login=orders.SalonOrderTests.login
    guardar=orders.SalonOrderTests.guardar

    def setUp(self):
        orders.SalonOrderTests.setUp(self)
        self.manager=self.token(2)
        self.member=self.token(4)

    def tearDown(self):orders.SalonOrderTests.tearDown(self)

    def token(self,profile,local=1):
        return {'Authorization':'Bearer '+create_access_token(identity='2',additional_claims={'tipo_token':'operativo','id_perfil':profile,'id_local':local})}

    def api(self,path,body=None,method='post',headers=None):
        g.pop('local_operativo',None)
        return getattr(self.client,method if body is not None else 'get')('/api/inventario-operativo/'+path,headers=headers or self.manager,json=body)

    def current_day(self):return self.api('dias').json['dias'][0]['id_jornada']

    def balance(self,local=1):
        return db.session.execute(text('SELECT stock_actual FROM inventario_stock_teorico WHERE id_local=:local AND id_producto=1'),{'local':local}).scalar_one()

    def movement(self,quantity=1,local=1,reason='MERMA',kind='SALIDA'):
        identity=db.session.execute(text('''INSERT INTO movimiento_inventario(codigo,tipo_movimiento,motivo_movimiento,fecha_movimiento,usuario_registro,id_local)
            VALUES(:codigo,:tipo,:motivo,CURRENT_DATE,2,:local) RETURNING id_movimiento_inventario'''),dict(codigo='T-'+uuid.uuid4().hex[:10],tipo=kind,motivo=reason,local=local)).scalar_one()
        db.session.execute(text('INSERT INTO movimiento_inventario_detalle(id_movimiento_inventario,id_producto,cantidad) VALUES(:id,1,:q)'),dict(id=identity,q=quantity))
        return identity

    def round(self):
        r=self.api('conteos',{'nombre':'Conteo de prueba'})
        self.assertEqual(r.status_code,201,r.json)
        return r.json['id_ronda']

    def count(self,identity,headers=None):
        r=self.api(f'conteos/{identity}',headers=headers)
        self.assertEqual(r.status_code,200,r.json)
        return r.json['productos'][0]

    def change(self,identity,action,headers=None,**changes):
        p=self.count(identity)
        return self.api(f'conteos/{identity}/productos/{p["id_producto"]}',{'accion':action,'version':p['version'],**changes},'put',headers)

    def test_migration_baseline_and_all_stock_readers(self):
        self.assertEqual(self.balance(),Decimal(9))
        other=self.balance(2)
        self.movement(2)
        self.assertEqual(self.balance(),Decimal(7));self.assertEqual(self.balance(2),other)
        g.pop('local_operativo',None)
        r=self.client.get('/api/inventarios/stock',headers=self.manager)
        self.assertEqual(r.status_code,200,r.json)
        self.assertEqual(r.json['productos'][0]['stock_actual'],7)
        with self.app.test_request_context(headers=self.manager):
            from flask_jwt_extended import verify_jwt_in_request
            from app.modules.compras.repository import listar_productos_para_compra
            g.pop('local_operativo',None);verify_jwt_in_request()
            p=listar_productos_para_compra()[0]
            self.assertEqual(p['stock_actual'],7);self.assertEqual(p['consumo_total'],2)

    def test_midnight_keeps_day_and_reports_freeze(self):
        identity=self.current_day()
        db.session.execute(text("UPDATE inventario_jornada SET fecha=DATE '2026-09-26' WHERE id_jornada=:id"),{'id':identity})
        self.movement(2)
        self.assertEqual(db.session.execute(text('SELECT id_jornada FROM inventario_evento ORDER BY id_evento DESC LIMIT 1')).scalar(),identity)
        closed=self.api(f'dias/{identity}/cerrar',{})
        self.assertEqual(closed.status_code,200,closed.json)
        product=closed.json['reporte']['inventario'][0]
        self.assertEqual((product['inicial'],product['salidas'],product['final']),(9,2,7))
        self.assertEqual(product['motivos'][0]['motivo'],'MERMA')
        again=self.api(f'dias/{identity}/cerrar',{})
        self.assertEqual(again.json['cerrado_en'],closed.json['cerrado_en'])
        self.movement(1)
        new_id=self.current_day();self.assertNotEqual(new_id,identity)
        new_report=self.api(f'dias/{new_id}').json['reporte']['inventario'][0]
        self.assertEqual((new_report['inicial'],new_report['final']),(7,6))
        self.assertEqual(self.api(f'dias/{identity}').json['reporte'],closed.json['reporte'])

    def test_receipt_edit_is_delta_of_current_day_not_rewrite(self):
        identity=self.current_day();self.api(f'dias/{identity}/cerrar',{})
        before=self.balance()
        db.session.execute(text('UPDATE factura_recepcion_detalle SET cantidad_recibida=cantidad_recibida+2 WHERE id_factura_recepcion=1'))
        self.assertEqual(self.balance(),before+2)
        event=db.session.execute(text('SELECT * FROM inventario_evento ORDER BY id_evento DESC LIMIT 1')).mappings().one()
        self.assertEqual(event['motivo'],'CORRECCION_RECEPCION');self.assertNotEqual(event['id_jornada'],identity)
        self.assertEqual(self.api(f'dias/{identity}').json['reporte']['inventario'][0]['final'],9)

    def test_sent_sale_blocks_close_then_mix_uses_business_date_and_hours(self):
        identity=self.current_day()
        db.session.execute(text("UPDATE inventario_jornada SET fecha=DATE '2026-09-26' WHERE id_jornada=:id"),{'id':identity})
        self.guardar(enviar=True)
        self.assertEqual(self.api(f'dias/{identity}/cerrar',{}).status_code,409)
        db.session.execute(text("INSERT INTO receta(id_receta,id_presentacion_venta) VALUES(9800,9800); INSERT INTO receta_detalle(id_receta,tipo_componente,id_producto,cantidad,unidad) VALUES(9800,'PRODUCTO',1,2,'UNI')"))
        account=self.client.get('/api/salon/mesas/M01/cuenta',headers=self.headers).json
        data=dict(clave=str(uuid.uuid4()),revision=account['revision'],tipo='BOLETA',metodo='EFECTIVO')
        paid=self.client.post('/api/salon/mesas/M01/emitir',headers=self.headers,json=data)
        self.assertEqual(paid.status_code,201,paid.json);self.assertEqual(self.balance(),3)
        self.assertEqual(self.client.post('/api/salon/mesas/M01/emitir',headers=self.headers,json=data).status_code,200)
        self.assertEqual(self.balance(),3)
        db.session.execute(text("UPDATE salon_cobro SET creado_en=TIMESTAMPTZ '2026-09-27 04:30:00-05'"))
        mix=self.api('mix?desde=2026-09-26&hasta=2026-09-26&hora=4&hora=5&separar=1')
        self.assertEqual(mix.status_code,200,mix.json)
        self.assertEqual(mix.json['total'],31);self.assertEqual(mix.json['productos'][0]['hora'],4)
        self.assertEqual(self.api('mix?desde=2026-09-27&hasta=2026-09-27').json['total'],0)
        self.assertEqual(self.api('mix?desde=2026-09-26&hasta=2026-09-26&hora=5').json['total'],0)
        closed=self.api(f'dias/{identity}/cerrar',{})
        self.assertEqual(closed.status_code,200,closed.json)
        self.assertEqual(closed.json['reporte']['ventas'][0]['cantidad'],2)

    def test_assignment_draft_done_review_correction_justification(self):
        identity=self.round();before=self.balance()
        self.assertEqual(self.api(f'conteos/{identity}',headers=self.member).json['productos'],[])
        self.assertEqual(self.change(identity,'contar',headers=self.member,cantidad=4,estado='HECHO').status_code,403)
        self.assertEqual(self.change(identity,'asignar',id_usuario=2).status_code,200)
        p=self.count(identity,self.member);self.assertNotIn('teorico',p)
        self.assertEqual(self.change(identity,'contar',headers=self.member,cantidad='6.5',estado='EN_PROCESO').status_code,200)
        self.assertEqual(self.change(identity,'revisar',cantidad=7,observacion='Mal conteo').status_code,409)
        self.assertEqual(self.change(identity,'contar',headers=self.member,cantidad=6,estado='HECHO').status_code,200)
        self.assertEqual(self.change(identity,'contar',cantidad=7,estado='HECHO').status_code,409)
        self.assertEqual(self.change(identity,'revisar',cantidad=7,observacion='').status_code,400)
        self.assertEqual(self.change(identity,'revisar',cantidad=7,observacion='Mal conteo').status_code,200)
        p=self.count(identity);self.assertEqual((p['teorico'],p['contado'],p['corregido'],p['diferencia']),(9,6,7,-2))
        self.assertEqual(self.change(identity,'contar',headers=self.member,cantidad=10,estado='HECHO').status_code,409)
        self.assertEqual(self.change(identity,'justificar',justificacion='Merma pendiente de registrar').status_code,200)
        self.assertEqual(self.balance(),before)
        self.assertGreater(len(self.api(f'conteos/{identity}/historial').json['historial']),3)
        self.assertEqual(self.api(f'conteos/{identity}/finalizar',{}).status_code,200)
        self.assertEqual(self.change(identity,'contar',cantidad=5,estado='HECHO').status_code,409)
        self.assertEqual(self.change(identity,'justificar',justificacion='Justificación ampliada').status_code,200)

    def test_count_snapshot_stale_versions_and_top(self):
        identity=self.round();p=self.count(identity)
        self.movement(2)
        self.assertEqual(self.count(identity)['teorico'],9)
        self.change(identity,'contar',cantidad=12,estado='HECHO')
        stale=self.api(f'conteos/{identity}/productos/1',dict(accion='contar',version=p['version'],cantidad=10,estado='HECHO'),'put')
        self.assertEqual(stale.status_code,409)
        self.change(identity,'revisar',cantidad=12,observacion='Verificado')
        fecha=db.session.execute(text("SELECT (creado_en AT TIME ZONE 'America/Lima')::date FROM inventario_ronda WHERE id_ronda=:id"),{'id':identity}).scalar().isoformat()
        for top in (5,10,15,20):
            result=self.api(f'diferencias?desde={fecha}&hasta={fecha}&top={top}')
            self.assertEqual(result.status_code,200,result.json)
            self.assertEqual(result.json['productos'][0]['diferencia'],3)
        self.assertEqual(self.api(f'diferencias?desde={fecha}&hasta={fecha}&top=3').status_code,400)
        self.assertEqual(self.api('conteos',{'nombre':'Otra'}).status_code,409)

    def test_permissions_local_and_legacy_writes(self):
        for path in ('dias','mix?desde=2026-09-26&hasta=2026-09-26','diferencias?desde=2026-09-26&hasta=2026-09-26'):
            self.assertEqual(self.api(path,headers=self.member).status_code,403)
        self.assertEqual(self.api('conteos',{'nombre':'No autorizado'},headers=self.member).status_code,403)
        identity=self.round()
        self.assertEqual(self.api(f'conteos/{identity}',headers=self.token(2,2)).status_code,403)
        db.session.execute(text('INSERT INTO usuario_local(id_usuario,id_local) VALUES(2,2)'))
        self.assertEqual(self.api(f'conteos/{identity}',headers=self.token(2,2)).status_code,404)
        self.assertEqual(self.client.put('/api/inventarios/actual/guardar',headers=self.manager,json={}).status_code,409)
        self.assertEqual(self.api('dias',headers=self.token(1)).status_code,403)

    def test_failure_rolls_back_day_and_count_edits(self):
        identity=self.current_day()
        with patch('app.modules.inventarios.operativo.auditar',side_effect=RuntimeError('fallo')):
            with self.assertRaises(RuntimeError),db.session.begin_nested():self.api(f'dias/{identity}/cerrar',{})
        self.assertIsNone(self.api(f'dias/{identity}').json['cerrado_en'])
        round_id=self.round()
        with patch('app.modules.inventarios.operativo.auditar',side_effect=RuntimeError('fallo')):
            with self.assertRaises(RuntimeError),db.session.begin_nested():self.change(round_id,'contar',cantidad=4,estado='HECHO')
        self.assertIsNone(self.count(round_id)['contado'])
        self.assertEqual(self.balance(),9)
