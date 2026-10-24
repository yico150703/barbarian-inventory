import os
import unittest
from unittest.mock import patch
from flask_jwt_extended import create_access_token
from sqlalchemy import text
from app import create_app
from app.core.extensions import db
from app.modules.catalogos.deletion import eliminar_registro


@unittest.skipUnless(os.environ.get('LOCAL_SCOPE_TEST_DB') == '1', 'Requiere PostgreSQL temporal')
class CatalogDeletionTests(unittest.TestCase):
    def setUp(self):
        self.app=create_app()
        self.app.config.update(TESTING=True,JWT_SECRET_KEY='catalog-delete-test-secret-at-least-32-characters')
        self.ctx=self.app.app_context();self.ctx.push()
        self.assertEqual(db.session.execute(text('SELECT current_database()')).scalar(),'barbarito_test')
        db.session.execute(text("""
            INSERT INTO categoria_producto(id_categoria,nombre,prefijo) VALUES(9200,'Borrar categoria','BC');
            INSERT INTO proveedor(id_proveedor,nombre) VALUES(9200,'Borrar proveedor');
            INSERT INTO producto(id_producto,codigo,nombre,id_categoria,id_proveedor,unidad,presentacion,stock_minimo)
            VALUES(9200,'BC-001','Borrar producto',9200,9200,'C62',1,0);
            INSERT INTO producto_stock_local(id_producto,id_local,stock_minimo) VALUES(9200,1,0);
            INSERT INTO categoria_carta(id_categoria_carta,nombre,prefijo) VALUES(9200,'Borrar carta','BD');
            INSERT INTO menaje(id_menaje,nombre) VALUES(9200,'Borrar plato');
            INSERT INTO item_carta(id_item_carta,codigo,nombre,id_categoria_carta,tipo) VALUES(9200,'BD-001','Borrar item',9200,'PREPARADO');
            INSERT INTO presentacion_venta(id_presentacion_venta,id_item_carta,id_menaje,contenido,unidad,precio) VALUES(9200,9200,9200,1,'C62',1);
            INSERT INTO receta(id_receta,id_presentacion_venta,instrucciones) VALUES(9200,9200,'Prueba');
            INSERT INTO receta_detalle(id_receta,tipo_componente,id_producto,cantidad,unidad) VALUES(9200,'PRODUCTO',9200,1,'C62');
            INSERT INTO subproducto(id_subproducto,codigo,nombre,rendimiento,unidad,instruccion) VALUES(9200,'SP-9200','Borrar subproducto',1,'KGM','Prueba');
            INSERT INTO subproducto_detalle(id_subproducto,id_producto,cantidad,unidad) VALUES(9200,9200,1,'C62');
            INSERT INTO promocion(id_promocion,codigo,nombre,precio) VALUES(9200,'P-9200','Borrar promo',1);
            INSERT INTO promocion_grupo(id_promocion_grupo,id_promocion,cantidad_elegir,permite_repetir) VALUES(9200,9200,1,false);
            INSERT INTO promocion_opcion(id_promocion_grupo,id_presentacion_venta) VALUES(9200,9200);
            INSERT INTO promocion_reposicion(id_promocion,id_presentacion_venta) VALUES(9200,9200);
        """));db.session.commit()

    def tearDown(self):
        db.session.rollback()
        for tabla,col in [('promocion_reposicion','id_promocion'),('promocion_opcion','id_promocion_grupo'),('promocion_grupo','id_promocion'),('promocion','id_promocion'),
                          ('receta_detalle','id_receta'),('receta','id_receta'),('subproducto_detalle','id_subproducto'),('subproducto','id_subproducto'),
                          ('presentacion_venta','id_presentacion_venta'),('item_carta','id_item_carta'),('categoria_carta','id_categoria_carta'),('menaje','id_menaje'),
                          ('producto_stock_local','id_producto'),('producto','id_producto'),('categoria_producto','id_categoria'),('proveedor','id_proveedor')]:
            db.session.execute(text(f'DELETE FROM {tabla} WHERE {col}=9200'))
        db.session.commit();db.session.remove();self.ctx.pop()

    def test_used_and_historical_records_are_blocked(self):
        for entidad in ('productos','categorias-productos','proveedores','categorias-carta','presentaciones'):
            result,status=eliminar_registro(entidad,9200,1)
            self.assertEqual(status,409,(entidad,result))
            self.assertIn('asociados',result['mensaje'])
        self.assertEqual(eliminar_registro('productos',1,1)[1],409)

    def test_delete_compositions_then_unreferenced_catalogs(self):
        for entidad in ('promociones','recetas','subproductos','presentaciones','productos','categorias-productos','proveedores'):
            result,status=eliminar_registro(entidad,9200,1)
            self.assertEqual(status,200,(entidad,result))
        # Borrar presentacion conserva su articulo; la categoria sigue protegida.
        self.assertEqual(eliminar_registro('categorias-carta',9200,1)[1],409)
        db.session.execute(text('DELETE FROM item_carta WHERE id_item_carta=9200'));db.session.commit()
        self.assertEqual(eliminar_registro('categorias-carta',9200,1)[1],200)
        self.assertEqual(eliminar_registro('recetas',9200,1)[1],404)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM producto_stock_local WHERE id_producto=9200')).scalar(),0)

    def test_audit_failure_restores_promotion_children(self):
        with patch('app.modules.catalogos.deletion.registrar_actividad',side_effect=RuntimeError('fallo')):
            with self.assertRaises(RuntimeError): eliminar_registro('promociones',9200,1)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM promocion_opcion WHERE id_promocion_grupo=9200')).scalar(),1)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM promocion_reposicion WHERE id_promocion=9200')).scalar(),1)

    def test_http_permissions_and_delete(self):
        client=self.app.test_client()
        self.assertEqual(client.delete('/api/eliminaciones/promociones/9200').status_code,401)
        token=create_access_token(identity='1',additional_claims={'tipo_token':'operativo','id_perfil':1,'id_local':1})
        headers={'Authorization':'Bearer '+token}
        db.session.execute(text('UPDATE perfil_opcion_menu SET puede_eliminar=false WHERE id_perfil=1 AND id_opcion_menu=14'));db.session.commit()
        self.assertEqual(client.delete('/api/eliminaciones/promociones/9200',headers=headers).status_code,403)
        db.session.execute(text('UPDATE perfil_opcion_menu SET puede_eliminar=true WHERE id_perfil=1 AND id_opcion_menu=14'));db.session.commit()
        self.assertEqual(client.delete('/api/eliminaciones/promociones/9200',headers=headers).status_code,200)
