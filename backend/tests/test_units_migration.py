import os
from pathlib import Path
import unittest
from decimal import Decimal
from flask_jwt_extended import create_access_token
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from app import create_app
from app.core.extensions import db
from app.core.units import unidad_almacenamiento
from app.modules.catalogos import repository as repo


@unittest.skipUnless(os.environ.get('LOCAL_SCOPE_TEST_DB') == '1', 'Requiere PostgreSQL temporal')
class StandardUnitMigrationTests(unittest.TestCase):
    def test_migration_preserves_quantities_and_is_repeatable(self):
        app = create_app()
        app.config.update(TESTING=True, JWT_SECRET_KEY='unit-migration-test-secret-at-least-32-characters')
        with app.app_context():
            self.assertEqual(db.session.execute(text('SELECT current_database()')).scalar(), 'barbarito_test')
            db.session.execute(text("DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='multi') THEN CREATE ROLE multi; END IF; END $$"))
            db.session.execute(text("""
                INSERT INTO producto(id_producto,codigo,nombre,id_categoria,id_proveedor,unidad,presentacion,stock_minimo)
                VALUES(9701,'UM-9701','Masa migracion',1,1,'Kg',2.5,0),(9702,'UM-9702','Volumen migracion',1,1,'L',30,0);
                INSERT INTO subproducto(id_subproducto,codigo,nombre,rendimiento,unidad,instruccion)
                VALUES(9701,'SP-9701','Porciones migracion',5,'PORCIÓN','Prueba');
                INSERT INTO subproducto_detalle(id_subproducto,id_producto,cantidad,unidad)
                VALUES(9701,9701,0.060,'Kg');
            """))
            db.session.commit()
            before = db.session.execute(text('SELECT id_producto,presentacion,stock_minimo FROM producto ORDER BY id_producto')).all()
            sql = (Path(__file__).resolve().parents[2] / 'database/migrations/20261010_unidades_unece.sql').read_text(encoding='utf-8')
            for _ in range(2):
                db.session.execute(text(sql))
                db.session.commit()
            self.assertEqual(db.session.execute(text('SELECT id_producto,presentacion,stock_minimo FROM producto ORDER BY id_producto')).all(), before)
            self.assertEqual(db.session.execute(text('SELECT unidad FROM producto WHERE id_producto=9701')).scalar(), 'KGM')
            self.assertEqual(db.session.execute(text('SELECT unidad FROM producto WHERE id_producto=9702')).scalar(), 'LTR')
            self.assertEqual(db.session.execute(text('SELECT unidad FROM producto WHERE id_producto=1')).scalar(), 'C62')
            self.assertEqual(db.session.execute(text('SELECT unidad FROM subproducto WHERE id_subproducto=9701')).scalar(), 'PORCION')
            fila = db.session.execute(text('SELECT cantidad,unidad FROM subproducto_detalle WHERE id_subproducto=9701')).first()
            self.assertEqual(tuple(fila), (Decimal('0.060'), 'KGM'))
            self.assertEqual(unidad_almacenamiento('Kg'), 'KGM')
            self.assertEqual(unidad_almacenamiento('L'), 'LTR')
            # Las nuevas altas guardan el código estándar, no el símbolo antiguo.
            identidad = repo.crear_producto_registro('UM-9703','Alta estandar',1,1,'LTR',Decimal('0.750'))
            self.assertEqual(repo.obtener_producto(identidad)['unidad'], 'LTR')
            db.session.commit()
            with self.assertRaises(IntegrityError):
                with db.session.begin_nested():
                    db.session.execute(text("UPDATE producto SET unidad='L' WHERE id_producto=9702"))
            token = create_access_token(identity='1', additional_claims={'tipo_token':'operativo','id_perfil':1,'id_local':1})
            with app.test_client() as client:
                response = client.get('/api/catalogos/productos', headers={'Authorization':'Bearer '+token})
                self.assertEqual(response.status_code, 200, response.json)
                producto = next(p for p in response.json['productos'] if p['id_producto'] == 9702)
                self.assertEqual(producto['unidad'], 'LTR')
                self.assertEqual(producto['presentacion'], 30)
                self.assertEqual(producto['unidad_medida']['simbolo'], 'L')
