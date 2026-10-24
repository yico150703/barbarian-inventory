"""Real inventory routes and drafts, simulated model, rollback-isolated fixtures."""
import json
import os
import unittest
from unittest.mock import patch
from flask import g
from sqlalchemy import text
from app.core.extensions import db
from app.modules.asistente_ia import routes
import test_count_positions as positions
from test_asistente_ia import proposal


def query(resource, filters=None):
    return [{'type':'function_call','call_id':'inventory-query','name':'consultar_inventario',
             'arguments':json.dumps({'recurso':resource,'filtros_json':json.dumps(filters or {})})}]


ANSWER=[{'type':'message','content':[{'type':'output_text','text':'Consulta terminada.'}]}]


@unittest.skipUnless(os.environ.get('POSITION_COUNTS_TEST_DB')=='1','Solo base temporal con asignaciones por puesto')
class InventoryAssistantTests(unittest.TestCase):
    login=positions.PositionCountTests.login
    api=positions.PositionCountTests.api
    token=positions.PositionCountTests.token
    count=positions.PositionCountTests.count
    change=positions.PositionCountTests.change
    round=positions.PositionCountTests.round
    member_token=positions.PositionCountTests.member_token
    assign=positions.PositionCountTests.assign

    def setUp(self):
        positions.PositionCountTests.setUp(self)
        routes._attempts.clear()

    def tearDown(self):positions.PositionCountTests.tearDown(self)

    def ask(self, calls, headers=None):
        g.pop('local_operativo',None)
        with patch('app.modules.asistente_ia.provider.respond',side_effect=[calls,ANSWER]) as model:
            result=self.client.post('/api/asistente-ia/preparar',headers=headers or self.manager,
                                    json={'instruccion':'Consulta de inventario: solicitud del usuario'})
            self.assertEqual(result.status_code,200,result.json)
            return result.json,model

    def confirm(self, draft, headers=None):
        g.pop('local_operativo',None)
        return self.client.post('/api/asistente-ia/realizar',headers=headers or self.manager,
                               json={'id':draft['id_borrador'],'confirmar':True})

    def balance(self):
        return db.session.execute(text('SELECT stock_actual FROM inventario_stock_teorico WHERE id_local=1 AND id_producto=1')).scalar_one()

    def test_open_requires_confirmation_and_retries_are_idempotent(self):
        self.assign()
        result,_=self.ask(proposal('conteos','crear',data={'nombre':'Conteo de barra'}))
        self.assertEqual(self.api('conteos').json['rondas'],[])
        draft=result['borrador'];self.assertIsNotNone(draft)
        first=self.confirm(draft)
        self.assertEqual(first.status_code,200,first.json)
        self.assertEqual(self.confirm(draft).json,first.json)
        self.assertEqual(len(self.api('conteos').json['rondas']),1)
        self.assertEqual(self.balance(),9)

    def test_member_cannot_prepare_open_and_only_sees_own_counts(self):
        self.assign();identity=self.round()
        result,_=self.ask(query('conteos',{'id':identity}),self.member)
        row=result['consultas'][0]['registros'][0]
        self.assertNotIn('teorico',row);self.assertNotIn('diferencia',row)
        result,model=self.ask(proposal('conteos','crear',data={'nombre':'No permitido'}),self.member)
        self.assertIsNone(result['borrador'])
        self.assertTrue(any('error' in m.get('output','') for m in model.call_args.args[0]))
        self.assertEqual(len(self.api('conteos').json['rondas']),1)

    def test_bulk_assignment_preview_and_stale_protection(self):
        result,_=self.ask(proposal('asignaciones_conteo','editar',data={'productos':[1],'id_puesto_laboral':9902}))
        draft=result['borrador']
        self.assertEqual(draft['vista']['puesto_destino'],'Cocina')
        self.assertIsNone(self.api('asignaciones').json['productos'][0]['id_puesto_laboral'])
        self.assign(9903)
        self.assertEqual(self.confirm(draft).status_code,409)
        result,_=self.ask(proposal('asignaciones_conteo','editar',data={'productos':[1],'id_puesto_laboral':9902}))
        done=self.confirm(result['borrador'])
        self.assertEqual(done.status_code,200,done.json)
        self.assertEqual(self.api('asignaciones').json['productos'][0]['id_puesto_laboral'],9902)

    def test_close_preserves_originals_and_does_not_adjust_stock(self):
        self.assign();identity=self.round()
        self.change(identity,'contar',headers=self.member,cantidad=7,estado='HECHO')
        result,_=self.ask(proposal('revision_conteo','editar',identity,{'correcciones':{'1':{'cantidad':8,'observacion':''}}}))
        draft=result['borrador'];self.assertIsNotNone(draft)
        self.assertIn('Cierra toda',draft['vista']['efecto'])
        self.assertIsNone(self.count(identity)['corregido'])
        done=self.confirm(draft);self.assertEqual(done.status_code,200,done.json)
        row=self.count(identity)
        self.assertEqual((row['contado'],row['corregido'],row['teorico'],row['diferencia']),(7,8,9,-1))
        self.assertIsNotNone(self.api(f'conteos/{identity}').json['ronda']['cerrado_en'])
        self.assertEqual(self.balance(),9)

    def test_pending_and_stale_reviews_cannot_close(self):
        self.assign();identity=self.round()
        command=proposal('revision_conteo','editar',identity,{'correcciones':{}})
        result,_=self.ask(command);self.assertIsNone(result['borrador'])
        self.change(identity,'contar',headers=self.member,cantidad=7,estado='HECHO')
        result,_=self.ask(command)
        self.change(identity,'revisar',cantidad=8,observacion='Reconteo')
        self.assertEqual(self.confirm(result['borrador']).status_code,409)
        self.assertIsNone(self.api(f'conteos/{identity}').json['ronda']['cerrado_en'])

    def test_filters_scope_and_totals(self):
        result,model=self.ask(query('stock',{'bajo_minimo':True}))
        self.assertEqual(result['agente'],'inventario')
        names={tool['name'] for tool in model.call_args.args[1]}
        self.assertIn('consultar_inventario',names)
        self.assertIn('preparar_cambio',names)
        self.assertNotIn('consultar',names)
        self.assertTrue(all(p['stock_actual']<p['stock_minimo'] for p in result['consultas'][0]['registros']))
        result,_=self.ask(query('mix_ventas',{'desde':'2026-09-01','hasta':'2026-09-28','horas':[1,2],'por_hora':True}))
        self.assertEqual(result['consultas'][0]['contexto']['total_ventas'],0)
        result,model=self.ask(query('stock',{'id_local':2}))
        self.assertEqual(result['consultas'],[])
        self.assertTrue(any('error' in m.get('output','') for m in model.call_args.args[0]))
        result,_=self.ask(query('mix_ventas',{'desde':'2026-09-01','hasta':'2026-09-28','horas':[24]}))
        self.assertEqual(result['consultas'],[])

    def test_wrong_local_and_revoked_permission_cannot_confirm(self):
        self.assign()
        result,_=self.ask(proposal('conteos','crear',data={'nombre':'Conteo autorizado'}))
        draft=result['borrador']
        db.session.execute(text('INSERT INTO usuario_local(id_usuario,id_local) VALUES(2,2)'))
        self.assertEqual(self.confirm(draft,self.token(2,2)).status_code,404)
        db.session.execute(text('UPDATE perfil_opcion_menu SET puede_crear=false WHERE id_perfil=2 AND id_opcion_menu=38'))
        self.assertEqual(self.confirm(draft).status_code,403)
        self.assertEqual(self.api('conteos').json['rondas'],[])

    def test_read_progress_and_assignment_filters_do_not_write(self):
        self.assign();identity=self.round()
        result,_=self.ask(query('revision_conteo',{'id':identity}))
        self.assertEqual(result['consultas'][0]['contexto']['avance'][0]['pendientes'],1)
        result,_=self.ask(query('asignaciones_conteo',{'sin_asignar':True}))
        self.assertEqual(result['consultas'][0]['total'],0)
        result,_=self.ask(query('asignaciones_conteo',{'puesto':9901}))
        self.assertEqual(result['consultas'][0]['total'],1)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM asistente_ia_borrador')).scalar(),0)
        self.assertEqual(self.balance(),9)
