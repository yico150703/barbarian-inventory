import os
import unittest
from datetime import date
from unittest.mock import patch
from flask import g
from flask_jwt_extended import create_access_token, verify_jwt_in_request
from sqlalchemy import text
from werkzeug.exceptions import BadRequest, Conflict, NotFound
from app import create_app
from app.core.extensions import db
from app.modules.movimientos.service import registrar_movimiento
from app.modules.movimientos.tracking import recibir, listar
from app.modules.inventarios.repository import consultar_stock_actual


@unittest.skipUnless(os.environ.get('LOCAL_SCOPE_TEST_DB') == '1', 'PostgreSQL temporal')
class MovementTrackingTests(unittest.TestCase):
    def setUp(self):
        self.app=create_app()
        self.app.config.update(TESTING=True, JWT_SECRET_KEY='tracking-test-secret-at-least-32-characters')
        self.ctx=self.app.app_context(); self.ctx.push()
        self.assertEqual(db.session.execute(text('SELECT current_database()')).scalar(),'barbarito_test')
        db.session.execute(text('INSERT INTO usuario_local(id_usuario,id_local) VALUES(2,2) ON CONFLICT DO NOTHING'))
        self.commit=patch.object(db.session,'commit'); self.commit.start()
        self.rollback=patch.object(db.session,'rollback'); self.rollback.start()

    def tearDown(self):
        self.commit.stop(); self.rollback.stop(); db.session.rollback(); db.session.remove(); self.ctx.pop()

    def session(self, local=1):
        g.pop('local_operativo', None)
        token=create_access_token(identity='2', additional_claims={'tipo_token':'operativo','id_perfil':2,'id_local':local})
        return self.app.test_request_context(headers={'Authorization':'Bearer '+token})

    def crear(self, proveedor=False):
        r,s=registrar_movimiento(2,{'motivo_movimiento':'DEVOLUCION_PROVEEDOR' if proveedor else 'PRESTAMO_ENTREGADO',
            'fecha_movimiento':date.today().isoformat(),'id_local_destino':2,'id_proveedor':1 if proveedor else None,
            'detalles':[{'id_producto':1,'cantidad':6}]})
        self.assertEqual(s,201,r)
        return r['movimiento']['id_movimiento_inventario']

    def test_transfer_stock_and_single_acceptance(self):
        with self.session():
            verify_jwt_in_request()
            antes=consultar_stock_actual()[0]['stock_actual']
            mid=self.crear()
            self.assertEqual(consultar_stock_actual()[0]['stock_actual'],antes-6)
            self.assertEqual(listar()['movimientos'][0]['estado'],'PENDIENTE_RECEPCION')
            with self.assertRaises(NotFound): recibir(mid,{},2)
        with self.session(2):
            verify_jwt_in_request()
            self.assertEqual(consultar_stock_actual()[0]['stock_actual'],0)
            self.assertEqual(recibir(mid,{},2)[1],201)
            self.assertEqual(consultar_stock_actual()[0]['stock_actual'],6)
            with self.assertRaises(Conflict): recibir(mid,{},2)
            self.assertEqual(consultar_stock_actual()[0]['stock_actual'],6)

    def test_partial_supplier_and_over_receipt(self):
        with self.session():
            verify_jwt_in_request(); mid=self.crear(True)
            payload={'guia_proveedor':'G-1','detalles':[{'id_producto':1,'cantidad':4}]}
            self.assertEqual(recibir(mid,payload,2)[0]['estado'],'REINTEGRO_PARCIAL')
            with self.assertRaises(Conflict): recibir(mid,payload,2)
            with self.assertRaises(BadRequest): recibir(mid,{**payload,'guia_proveedor':'G-2'},2)
            self.assertEqual(listar()['movimientos'][0]['detalles'][0]['recibido'],4)
            self.assertEqual(recibir(mid,{'guia_proveedor':'G-2','detalles':[{'id_producto':1,'cantidad':2}]},2)[0]['estado'],'REINTEGRADO')

    def test_same_day_closed_inventory(self):
        db.session.execute(text("UPDATE inventario_cierre SET fecha_inventario=CURRENT_DATE,fecha_registro=(clock_timestamp() AT TIME ZONE 'America/Lima')-interval '1 hour' WHERE id_inventario_cierre=9"))
        with self.session():
            verify_jwt_in_request(); self.crear()
            self.assertEqual(consultar_stock_actual()[0]['stock_actual'],4)

    def test_invalid_destination_and_independent_entries(self):
        with self.session():
            verify_jwt_in_request()
            for motivo in ('PRESTAMO_RECIBIDO','REPOSICION_PROVEEDOR'):
                self.assertEqual(registrar_movimiento(2,{'motivo_movimiento':motivo})[1],400)
            with self.assertRaises(BadRequest):
                registrar_movimiento(2,{'motivo_movimiento':'PRESTAMO_ENTREGADO','fecha_movimiento':date.today().isoformat(),'id_local_destino':1})
