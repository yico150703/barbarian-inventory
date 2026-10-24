"""Entrega simulada de conteos por puesto, sin alterar stock ni cerrar revisión."""
import json
from decimal import Decimal
from demo_miraflores import backup, query, scalar
from app import create_app
from app.core.extensions import db
from app.modules.inventarios.operativo import serial
from app.modules.auditoria.service import registrar_actividad
from sqlalchemy import text

NAME='PRUEBA - Conteo entregado por el equipo de Miraflores'
ACTORS={1:4,2:3,3:2}  # Mesero María, Bartender Roberto, Cocina José.


def main():
    target=backup()
    with create_app().app_context():
        try:
            assert scalar('SELECT current_database()')=='barbarito'
            db.session.execute(text("SET LOCAL lock_timeout='5s'"))
            db.session.execute(text("SELECT pg_advisory_xact_lock(hashtext('inventario-dia:1'))"))
            if scalar('SELECT count(*) FROM inventario_ronda WHERE id_local=1 AND (nombre=:name OR cerrado_en IS NULL)',name=NAME):
                raise RuntimeError('Ya hay una ronda abierta o esta prueba fue cargada. No se modificó.')
            for position,user in ACTORS.items():
                assert scalar('''SELECT count(*) FROM usuario u JOIN usuario_local ul ON ul.id_usuario=u.id_usuario
                    JOIN usuario_perfiles up ON up.id_usuario=u.id_usuario
                    JOIN usuario_puestos_laborales upl ON upl.id_usuario=u.id_usuario
                    WHERE u.id_usuario=:user AND u.estado_registro=1 AND ul.id_local=1 AND ul.estado_registro=1
                    AND up.id_perfil=4 AND up.estado_registro=1 AND upl.id_puesto_laboral=:position AND upl.estado_registro=1''',user=user,position=position)==1
            stock=query('SELECT * FROM inventario_stock_teorico ORDER BY id_local,id_producto')
            identity=scalar('''INSERT INTO inventario_ronda(id_local,nombre,creado_por,por_puesto)
                VALUES(1,:name,4,true) RETURNING id_ronda''',name=NAME)
            db.session.execute(text('''INSERT INTO inventario_conteo(id_ronda,id_producto,teorico,puesto_asignado,puesto_nombre)
                SELECT :id,p.id_producto,s.stock_actual,a.id_puesto_laboral,pl.nombre
                FROM producto p JOIN inventario_stock_teorico s ON s.id_producto=p.id_producto AND s.id_local=1
                JOIN inventario_asignacion_puesto a ON a.id_producto=p.id_producto AND a.id_local=1
                JOIN puesto_laboral pl ON pl.id_puesto_laboral=a.id_puesto_laboral
                WHERE p.activo'''),{'id':identity})
            rows=query('''SELECT c.*,p.unidad FROM inventario_conteo c JOIN producto p USING(id_producto)
                WHERE id_ronda=:id ORDER BY id_producto''',id=identity)
            assert len(rows)==scalar('SELECT count(*) FROM producto WHERE activo')
            counts={'iguales':0,'faltantes':0,'sobrantes':0}
            for index,row in enumerate(rows):
                step=Decimal(1) if row.pop('unidad') in ('UNI','PORCIÓN') else Decimal('0.100')
                counted=max(Decimal(0),row['teorico']+(-step if index%5==0 else step if index%5==1 else Decimal(0)))
                counts['faltantes' if counted<row['teorico'] else 'sobrantes' if counted>row['teorico'] else 'iguales']+=1
                user=ACTORS[row['puesto_asignado']]
                updated=query('''UPDATE inventario_conteo SET contado=:counted,contado_por=:user,contado_en=clock_timestamp(),
                    contado_perfil=4,contado_perfil_nombre=(SELECT nombre FROM perfiles WHERE id_perfil=4),
                    contado_puesto=puesto_asignado,contado_puesto_nombre=puesto_nombre,estado='HECHO',version=version+1
                    WHERE id_ronda=:id AND id_producto=:product RETURNING *''',counted=counted,user=user,id=identity,product=row['id_producto'])[0]
                db.session.execute(text('''INSERT INTO inventario_conteo_historial(id_ronda,id_producto,id_usuario,accion,anterior,nuevo)
                    VALUES(:id,:product,:user,'contar',CAST(:old AS jsonb),CAST(:new AS jsonb))'''),
                    dict(id=identity,product=row['id_producto'],user=user,old=json.dumps(serial(row)),new=json.dumps(serial(updated))))
            for position,user in ACTORS.items():
                registrar_actividad(user,'INVENTARIO_OPERATIVO','CONTEO_PRUEBA',identity,
                    NAME+' - entrega simulada, no es un conteo físico real',id_perfil_utilizado=4,id_puesto_laboral=position,id_local=1)
            assert stock==query('SELECT * FROM inventario_stock_teorico ORDER BY id_local,id_producto')
            result={'ronda':identity,'nombre':NAME,'productos':len(rows),**counts,'actores_por_puesto':ACTORS,'estado':'HECHO, pendiente de revisión'}
            (target/'conteo_resultado.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
            db.session.commit()
            print(json.dumps(result,ensure_ascii=True));print('Respaldo:',target)
        except Exception:
            db.session.rollback();raise


if __name__=='__main__':main()
