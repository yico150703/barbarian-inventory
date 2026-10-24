import os
import unittest
from unittest.mock import patch
from flask_jwt_extended import create_access_token
from sqlalchemy import text
from app.core.extensions import db
import test_inventory_operations as operations


@unittest.skipUnless(os.environ.get('POSITION_COUNTS_TEST_DB')=='1','Requiere migración por puestos en base temporal')
class PositionCountTests(unittest.TestCase):
    login=operations.OperationalTests.login
    api=operations.OperationalTests.api
    token=operations.OperationalTests.token
    count=operations.OperationalTests.count
    change=operations.OperationalTests.change
    round=operations.OperationalTests.round

    def setUp(self):
        operations.OperationalTests.setUp(self)
        db.session.execute(text("INSERT INTO puesto_laboral(id_puesto_laboral,nombre) VALUES(9902,'Cocina'),(9903,'Bartender')"))
        self.member=self.member_token()

    def tearDown(self):operations.OperationalTests.tearDown(self)

    def member_token(self,user=2,position=9901,local=1):
        return {'Authorization':'Bearer '+create_access_token(identity=str(user),additional_claims={
            'tipo_token':'operativo','id_perfil':4,'id_local':local,'id_puesto_laboral':position})}

    def assign(self,position=9901,products=None,headers=None):
        return self.api('asignaciones',{'productos':products or [1],'id_puesto_laboral':position},'put',headers)

    def test_template_independent_of_round_and_local_snapshot(self):
        self.assertEqual(self.api('asignaciones').status_code,200)
        self.assertEqual(self.api('conteos').json['rondas'],[])
        self.assertEqual(self.assign().status_code,200)
        identity=self.round()
        self.assertEqual(self.count(identity)['puesto_asignado'],9901)
        self.assertEqual(self.assign(9902).status_code,200)
        self.assertEqual(self.count(identity)['puesto_asignado'],9901)
        db.session.execute(text('INSERT INTO usuario_local(id_usuario,id_local) VALUES(2,2)'))
        other=self.api('asignaciones',headers=self.token(2,2))
        self.assertTrue(all(p['id_puesto_laboral'] is None for p in other.json['productos']))
        self.change(identity,'contar',headers=self.member,cantidad=9,estado='HECHO')
        self.change(identity,'revisar',cantidad=9,observacion='Verificado')
        self.assertEqual(self.api(f'conteos/{identity}/finalizar',{}).status_code,200)
        second=self.round()
        self.assertEqual(self.count(second)['puesto_asignado'],9902)
        self.assertEqual(self.api(f'conteos/{second}',headers=self.member).json['productos'],[])

    def test_only_manager_opens_and_member_role_is_validated_live(self):
        self.assertEqual(self.api('conteos',{'nombre':'Mi conteo'},headers=self.member).status_code,403)
        self.assign()
        result=self.api('conteos',{'nombre':'Conteo meseros'},headers=self.member)
        self.assertEqual(result.status_code,403,result.json)
        self.assertEqual(self.api('conteos',{'nombre':'Conteo supervisor'},headers=self.token(3)).status_code,403)
        identity=self.round()
        self.assertEqual(self.api('conteos',{'nombre':'Otro conteo'}).status_code,409)
        product=self.count(identity,self.member)
        self.assertNotIn('teorico',product)
        self.assertEqual(self.change(identity,'contar',headers=self.member_token(position=9902),cantidad=1,estado='HECHO').status_code,403)
        db.session.execute(text('UPDATE usuario_puestos_laborales SET estado_registro=0 WHERE id_usuario=2'))
        self.assertEqual(self.api('conteos',headers=self.member).status_code,403)
        self.assertEqual(self.change(identity,'contar',headers=self.member,cantidad=1,estado='HECHO').status_code,403)

    def test_shared_count_tracks_actor_and_rejects_stale_or_finished_overwrite(self):
        self.assign();identity=self.round()
        db.session.execute(text('''INSERT INTO usuario_perfiles(id_usuario,id_perfil,usuario_asignacion) VALUES(1,4,1);
            INSERT INTO usuario_puestos_laborales(id_usuario,id_puesto_laboral,usuario_asignacion) VALUES(1,9901,1);
            INSERT INTO usuario_local(id_usuario,id_local) VALUES(1,1) ON CONFLICT DO NOTHING'''))
        second=self.member_token(user=1)
        original=self.count(identity,self.member)
        self.assertEqual(self.change(identity,'contar',headers=self.member,cantidad=3,estado='EN_PROCESO').status_code,200)
        stale=self.api(f'conteos/{identity}/productos/1',dict(accion='contar',cantidad=5,estado='HECHO',version=original['version']),'put',second)
        self.assertEqual(stale.status_code,409)
        self.assertEqual(self.change(identity,'contar',headers=second,cantidad=5,estado='HECHO').status_code,200)
        product=self.count(identity)
        self.assertEqual((product['contado_por'],product['contado_perfil'],product['contado_puesto']),(1,4,9901))
        self.assertEqual(product['contado_puesto_nombre'],'Mesero')
        self.assertEqual(self.change(identity,'contar',headers=self.member,cantidad=6,estado='HECHO').status_code,409)
        changes=self.api(f'conteos/{identity}/historial').json['historial']
        self.assertEqual({h['id_usuario'] for h in changes},{1,2})
        self.assertEqual(db.session.execute(text('SELECT stock_actual FROM inventario_stock_teorico WHERE id_local=1 AND id_producto=1')).scalar(),9)

    def test_bulk_validation_authorization_and_rollback(self):
        db.session.execute(text("""INSERT INTO producto(id_producto,codigo,nombre,id_categoria,id_proveedor,unidad,presentacion,stock_minimo)
            SELECT 9980,'P-9980','Segundo producto',id_categoria,id_proveedor,unidad,presentacion,stock_minimo FROM producto WHERE id_producto=1"""))
        self.assertEqual(self.assign(headers=self.member).status_code,403)
        self.assertEqual(self.assign(products=[1,999999]).status_code,400)
        self.assertIsNone(self.api('asignaciones').json['productos'][0]['id_puesto_laboral'])
        self.assertEqual(self.assign(position=999999).status_code,400)
        self.assertEqual(self.assign(products=[1,1]).status_code,200)
        self.assertEqual(self.assign(position=9903,products=[1,9980]).status_code,200)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM inventario_asignacion_puesto WHERE id_local=1 AND id_puesto_laboral=9903')).scalar(),2)
        self.assign()
        with patch('app.modules.inventarios.operativo.auditar',side_effect=RuntimeError('fallo')):
            with self.assertRaises(RuntimeError),db.session.begin_nested():self.assign(position=9902)
        self.assertEqual(self.api('asignaciones').json['productos'][0]['id_puesto_laboral'],9901)
        self.assertEqual(self.assign(position=None).status_code,200)
        self.assertIsNone(self.api('asignaciones').json['productos'][0]['id_puesto_laboral'])

    def test_round_override_does_not_change_template(self):
        self.assign();identity=self.round()
        self.assertEqual(self.change(identity,'asignar',id_puesto_laboral=9902).status_code,200)
        self.assertEqual(self.api('asignaciones').json['productos'][0]['id_puesto_laboral'],9901)
        self.assertEqual(self.api(f'conteos/{identity}',headers=self.member).json['productos'],[])

    def test_no_template_and_legacy_round_remains_personal(self):
        self.assertEqual(self.api('conteos',{'nombre':'Sin configuración'}).status_code,409)
        self.assign();identity=self.round()
        # Simula una ronda conservada desde antes de la migración.
        db.session.execute(text('UPDATE inventario_ronda SET por_puesto=false WHERE id_ronda=:id'),{'id':identity})
        db.session.execute(text('UPDATE inventario_conteo SET puesto_asignado=NULL,puesto_nombre=NULL WHERE id_ronda=:id'),{'id':identity})
        self.assertEqual(self.change(identity,'asignar',id_usuario=2).status_code,200)
        self.assertEqual(self.change(identity,'contar',headers=self.member,cantidad=2,estado='HECHO').status_code,200)
        self.assertEqual(self.count(identity)['asignado_a'],2)

    def test_close_review_accepts_submissions_preserving_original_and_stock(self):
        self.assign();identity=self.round()
        versions=lambda:{str(self.count(identity)['id_producto']):self.count(identity)['version']}
        close=lambda v:self.api(f'conteos/{identity}/finalizar',{'aceptar_entregados':True,'versiones':v})
        self.assertEqual(close(versions()).status_code,409)
        self.change(identity,'contar',headers=self.member,cantidad=7,estado='HECHO')
        stale=versions()
        self.change(identity,'revisar',cantidad=8,observacion='Mal conteo')
        self.assertEqual(close(stale).status_code,409)
        self.assertEqual(close(versions()).status_code,200)
        row=self.count(identity)
        self.assertEqual((row['contado'],row['corregido'],row['teorico'],row['diferencia']),(7,8,9,-1))
        self.assertEqual(self.change(identity,'revisar',cantidad=9,observacion='Otra').status_code,409)
        second=self.round()
        self.change(second,'contar',headers=self.member,cantidad=6,estado='HECHO')
        p=self.count(second)
        result=self.api(f'conteos/{second}/finalizar',{'aceptar_entregados':True,'versiones':{str(p['id_producto']):p['version']}})
        self.assertEqual(result.status_code,200,result.json)
        self.assertEqual(self.count(second)['corregido'],6)
        self.assertEqual(db.session.execute(text('SELECT stock_actual FROM inventario_stock_teorico WHERE id_local=1 AND id_producto=1')).scalar(),9)

    def test_save_and_close_batches_optional_notes_and_rejects_invalid_payload_atomically(self):
        db.session.execute(text("""INSERT INTO producto(id_producto,codigo,nombre,id_categoria,id_proveedor,unidad,presentacion,stock_minimo)
            SELECT 9980,'P-9980','Segundo producto',id_categoria,id_proveedor,unidad,presentacion,stock_minimo FROM producto WHERE id_producto=1"""))
        self.assign(products=[1,9980]);identity=self.round()
        for p in self.api(f'conteos/{identity}').json['productos']:
            r=self.api(f'conteos/{identity}/productos/{p["id_producto"]}',
                dict(accion='contar',cantidad=5,estado='HECHO',version=p['version']),'put',self.member)
            self.assertEqual(r.status_code,200)
        products=self.api(f'conteos/{identity}').json['productos']
        versions={str(p['id_producto']):p['version'] for p in products}
        changes={'1':{'cantidad':'6','observacion':''},'9980':{'cantidad':'2','observacion':'Reconteo de cocina'}}
        close=lambda edits:self.api(f'conteos/{identity}/finalizar',dict(aceptar_entregados=True,versiones=versions,correcciones=edits))
        bad={**changes,'9980':{'cantidad':'-1','observacion':''}}
        self.assertEqual(close(bad).status_code,400)
        self.assertTrue(all(p['corregido'] is None for p in self.api(f'conteos/{identity}').json['productos']))
        self.assertEqual(close({**changes,'999999':{'cantidad':1,'observacion':''}}).status_code,400)
        self.assertEqual(close({'1':{'cantidad':6,'observacion':'','teorico':0}}).status_code,400)
        with patch('app.modules.inventarios.operativo.auditar',side_effect=RuntimeError('fallo')):
            with self.assertRaises(RuntimeError),db.session.begin_nested():close(changes)
        self.assertTrue(all(p['corregido'] is None for p in self.api(f'conteos/{identity}').json['productos']))
        self.assertEqual(close(changes).status_code,200)
        rows={p['id_producto']:p for p in self.api(f'conteos/{identity}').json['productos']}
        self.assertEqual((rows[1]['contado'],rows[1]['corregido'],rows[1]['teorico'],rows[1]['diferencia']),(5,6,9,-3))
        self.assertEqual(rows[9980]['observacion'],'Reconteo de cocina')
        self.assertEqual(rows[9980]['corregido'],2)
        self.assertEqual(close(changes).status_code,200)
