"""Carga explícita e idempotente de la prueba autorizada de Miraflores.

Sin --apply solo muestra el plan. --apply exige respaldo previo y confirma en
una única transacción asignaciones, pedidos, cobros, salidas y cinco cierres.
No modifica cierres existentes, recetas, precios ni mínimos.
"""
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from decimal import Decimal
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'backend'))
from dotenv import load_dotenv
load_dotenv(ROOT / 'backend/.env')
from sqlalchemy import text
from sqlalchemy.engine import make_url
from app import create_app
from app.core.extensions import db
from app.modules.auth.salon_payments import consumos
from app.modules.inventarios.operativo import reporte, serial
from app.modules.auditoria.service import registrar_actividad

TAG = 'DEMO-MIRAFLORES-20260928'
LIMA = timezone(timedelta(hours=-5))
# Presentaciones existentes: cantidades pequeñas, sin opciones obligatorias.
SALES = {118: [8,9,10,11,12], 124: [2,2,3,2,1], 53: [1,2,1,1,1],
         52: [0,1,0,1,0], 34: [1,1,1,1,1], 36: [0,1,0,1,0], 46: [1,1,1,1,1]}


def query(sql, **params):
    return [dict(r) for r in db.session.execute(text(sql),params).mappings()]


def scalar(sql, **params):
    return db.session.execute(text(sql),params).scalar_one()


def backup():
    target=ROOT/'backend/.demo_backups'/datetime.now().strftime('%Y%m%d_%H%M%S')
    target.mkdir(parents=True,exist_ok=False)
    (target.parent/'.gitignore').write_text('*\n',encoding='utf-8')
    url=make_url(os.environ['DATABASE_URL'])
    args=[str(Path(os.environ.get('POSTGRES_BIN','C:/Program Files/PostgreSQL/18/bin'))/'pg_dump.exe'),
          '-h',url.host or '127.0.0.1','-p',str(url.port or 5432),'-U',url.username,
          '-d',url.database,'--format=custom','--no-owner','--no-privileges','-f',str(target/'antes.dump')]
    run=subprocess.run(args,env={**os.environ,'PGPASSWORD':url.password or '',
                       'PGOPTIONS':'-c default_transaction_read_only=on'},capture_output=True,
                       creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
    if run.returncode:raise RuntimeError('No se pudo generar el respaldo; no se cargó la prueba')
    if (target/'antes.dump').stat().st_size<1000:raise RuntimeError('Respaldo vacío')
    return target


def prepare():
    if scalar('SELECT current_database()')!='barbarito':raise RuntimeError('Base inesperada')
    local=scalar("SELECT id_local FROM local WHERE lower(nombre)='miraflores' AND estado_registro=1")
    if scalar("SELECT count(*) FROM actividad_usuario WHERE accion='CARGAR_DEMO' AND descripcion=:tag",tag=TAG):
        raise RuntimeError('Esta prueba ya fue cargada; se evita duplicarla')
    if scalar('SELECT count(*) FROM salon_pedido_actual WHERE id_local=:local',local=local):
        raise RuntimeError('Hay pedidos abiertos; no se toca ninguna mesa')
    if scalar('SELECT count(*) FROM inventario_jornada WHERE id_local=:local AND cerrado_en IS NULL',local=local):
        raise RuntimeError('Hay una jornada abierta; no se cierra automáticamente')
    # Actor real autorizado por el solicitante, con todas las operaciones marcadas como prueba.
    manager=query('''SELECT u.id_usuario,u.nombres FROM usuario u JOIN usuario_local ul USING(id_usuario)
        JOIN usuario_perfiles up USING(id_usuario) WHERE ul.id_local=:local AND ul.estado_registro=1
        AND up.id_perfil=2 AND up.estado_registro=1 AND u.estado_registro=1 ORDER BY u.id_usuario''',local=local)[0]
    puestos={p['nombre'].lower():p['id_puesto_laboral'] for p in query('SELECT * FROM puesto_laboral WHERE estado_registro=1')}
    products=query('''SELECT p.id_producto,p.nombre,cp.nombre categoria FROM producto p
        JOIN categoria_producto cp USING(id_categoria) WHERE p.activo ORDER BY p.id_producto''')
    assignments={p['id_producto']:puestos['mesero' if p['categoria']=='Botellas' else
                   'bartender' if p['categoria'] in ('Cervecera','Tragos') else 'cocina'] for p in products}
    stock={p['id_producto']:p for p in query('''SELECT s.*,p.nombre,p.unidad,sl.stock_minimo
        FROM inventario_stock_teorico s JOIN producto p USING(id_producto)
        LEFT JOIN producto_stock_local sl USING(id_local,id_producto) WHERE s.id_local=:local''',local=local)}
    carta=query('''SELECT pv.id_presentacion_venta id_presentacion,ic.nombre,pv.contenido,pv.unidad,pv.precio
        FROM presentacion_venta pv JOIN item_carta ic USING(id_item_carta)
        JOIN categoria_carta cc USING(id_categoria_carta)
        WHERE pv.activo AND ic.activo AND cc.activo AND pv.id_presentacion_venta=ANY(:ids)''',ids=list(SALES))
    if len(carta)!=len(SALES):raise RuntimeError('Cambió la carta de la prueba')
    if scalar('SELECT count(*) FROM grupo_salsa WHERE activo AND id_presentacion_venta=ANY(:ids)',ids=list(SALES)):
        raise RuntimeError('La carta ahora exige opciones; revisa el plan')
    menu={p['id_presentacion']:{'id_presentacion':p['id_presentacion'],
        'nombre':f"{p['nombre']} · {format(p['contenido'].normalize(),'f')} {p['unidad']}",
        'precio':p['precio'],'comentario':TAG+' · VENTA SIMULADA','opciones':[]} for p in carta}
    expected=defaultdict(Decimal)
    for pid,quantities in SALES.items():
        for product,amount in consumos([{**menu[pid],'cantidad':sum(quantities)}]).items():expected[product]+=amount
    for product,amount in expected.items():
        if stock[product]['stock_actual']<amount:raise RuntimeError('La prueba produciría saldo negativo; ajusta cantidades')
    last=scalar('SELECT max(fecha) FROM inventario_jornada WHERE id_local=:local',local=local)
    dates=[last+timedelta(days=i) for i in range(1,6)]
    return local,manager,assignments,stock,menu,expected,dates


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--apply',action='store_true');args=parser.parse_args()
    app=create_app()
    with app.app_context():
        local,manager,assignments,stock,menu,expected,dates=prepare()
        plan={'marca':TAG,'local':local,'fechas':[str(d) for d in dates],
              'asignaciones_por_puesto':dict(Counter(assignments.values())),
              'productos_vendidos':[{'producto':stock[p]['nombre'],'inicial':stock[p]['stock_actual'],
               'consumo':q,'final':stock[p]['stock_actual']-q,'minimo':stock[p]['stock_minimo']} for p,q in expected.items()]}
        print(json.dumps(serial(plan),ensure_ascii=True,indent=2))
        db.session.rollback()
        if not args.apply:return
        target=backup()
        try:
            # Congela fuentes mientras se aplica el lote; si hay actividad concurrente, aborta.
            db.session.execute(text("SET LOCAL lock_timeout='5s'"))
            db.session.execute(text('''LOCK TABLE inventario_jornada,inventario_asignacion_puesto,salon_pedido,
                salon_pedido_linea,salon_cobro,movimiento_inventario,movimiento_inventario_detalle,
                factura_recepcion_detalle,receta,receta_detalle,subproducto,subproducto_detalle,producto,
                presentacion_venta,item_carta,grupo_salsa IN SHARE ROW EXCLUSIVE MODE'''))
            local,manager,assignments,current,menu,expected,dates=prepare()
            if current!=stock:raise RuntimeError('El stock cambió durante el respaldo; reintenta')
            untouched=query('SELECT * FROM inventario_stock_teorico WHERE id_local<>:local ORDER BY id_local,id_producto',local=local)
            original_days=query('SELECT * FROM inventario_jornada WHERE id_local=:local ORDER BY id_jornada',local=local)
            old_assignments=query('SELECT * FROM inventario_asignacion_puesto WHERE id_local=:local',local=local)
            (target/'asignaciones_antes.json').write_text(json.dumps(serial(old_assignments),ensure_ascii=False,indent=2),encoding='utf-8')
            for product,position in assignments.items():
                db.session.execute(text('''INSERT INTO inventario_asignacion_puesto(id_local,id_producto,id_puesto_laboral,actualizado_por)
                    VALUES(:local,:product,:position,:user) ON CONFLICT(id_local,id_producto) DO UPDATE
                    SET id_puesto_laboral=excluded.id_puesto_laboral,actualizado_por=excluded.actualizado_por,
                    actualizado_en=clock_timestamp()'''),dict(local=local,product=product,position=position,user=manager['id_usuario']))
            receipts=[];days=[]
            for day_index,date in enumerate(dates):
                day=scalar('SELECT inventario_abrir_jornada(:local,:user)',local=local,user=manager['id_usuario'])
                if scalar('SELECT fecha FROM inventario_jornada WHERE id_jornada=:day',day=day)!=date:
                    raise RuntimeError('La fecha operativa cambió')
                opening=datetime.combine(date,datetime.min.time(),LIMA)+timedelta(hours=17)
                db.session.execute(text('UPDATE inventario_jornada SET abierto_en=:opened WHERE id_jornada=:day'),dict(day=day,opened=opening))
                for slot in range(2):
                    moment=opening+timedelta(hours=3,minutes=30) if slot==0 else opening+timedelta(hours=8,minutes=15)
                    lines=[{**menu[pid],'cantidad':quantities[day_index]} for index,(pid,quantities) in enumerate(SALES.items()) if index%2==slot and quantities[day_index]]
                    if not lines:continue
                    consumed=consumos(lines)
                    key=str(uuid.uuid5(uuid.NAMESPACE_URL,f'{TAG}:{date}:{slot}'))
                    pedido=scalar('''INSERT INTO salon_pedido(id_local,mesa,id_usuario,creado_en,envio_clave,envio_hash)
                        VALUES(:local,'M01',:user,:moment,CAST(:key AS uuid),:hash) RETURNING id_pedido''',
                        local=local,user=manager['id_usuario'],moment=moment,key=key,hash=hashlib.sha256(key.encode()).hexdigest())
                    for pos,line in enumerate(lines):
                        lid=scalar('''INSERT INTO salon_pedido_linea(id_pedido,posicion,id_presentacion,nombre,precio,cantidad,comentario,opciones)
                            VALUES(:pedido,:pos,:id_presentacion,:nombre,:precio,:cantidad,:comentario,CAST(:options AS jsonb)) RETURNING id_linea''',
                            pedido=pedido,pos=pos,options='[]',**{k:v for k,v in line.items() if k!='opciones'})
                        line.update(ids_lineas=[lid],enviada=True)
                    db.session.execute(text("UPDATE salon_pedido SET estado='ENVIADO',enviado_en=:moment WHERE id_pedido=:pedido"),dict(pedido=pedido,moment=moment))
                    movement=scalar('''INSERT INTO movimiento_inventario(codigo,tipo_movimiento,motivo_movimiento,fecha_movimiento,usuario_registro,id_local,observacion)
                        VALUES(:code,'SALIDA','VENTA_SALON',:date,:user,:local,:note) RETURNING id_movimiento_inventario''',
                        code=f'DEMO-0928-{day_index+1}-{slot+1}',date=date,user=manager['id_usuario'],local=local,note=TAG+' · venta simulada')
                    for product,amount in consumed.items():
                        db.session.execute(text('INSERT INTO movimiento_inventario_detalle(id_movimiento_inventario,id_producto,cantidad) VALUES(:movement,:product,:amount)'),dict(movement=movement,product=product,amount=amount))
                    total=sum(l['precio']*l['cantidad'] for l in lines)
                    method='EFECTIVO' if slot==0 else 'TARJETA'
                    snapshot={'tipo':'BOLETA','metodo':method,'documento':'','cliente':'','local':'Miraflores','mesa':'M01',
                              'usuario':manager['nombres'],'total':float(total),'fiscal':False,'lineas':serial(lines),'prueba':TAG}
                    receipt=scalar('''INSERT INTO salon_cobro(id_local,id_usuario,mesa,clave,solicitud_hash,tipo,metodo,total,comprobante,id_movimiento,creado_en)
                        VALUES(:local,:user,'M01',CAST(:key AS uuid),:hash,'BOLETA',:method,:total,CAST(:snapshot AS jsonb),:movement,:moment) RETURNING id_cobro''',
                        local=local,user=manager['id_usuario'],key=key,hash=hashlib.sha256(key.encode()).hexdigest(),method=method,total=total,
                        snapshot=json.dumps(snapshot,ensure_ascii=False),movement=movement,moment=moment)
                    db.session.execute(text('INSERT INTO salon_cobro_pedido(id_pedido,id_cobro) VALUES(:pedido,:receipt)'),dict(pedido=pedido,receipt=receipt))
                    registrar_actividad(manager['id_usuario'],'SALON','COBRO_PRUEBA',receipt,TAG+f' · fecha simulada {date}',id_perfil_utilizado=2,id_local=local)
                    receipts.append({'id':receipt,'fecha':str(date),'total':float(total),'metodo':method})
                report=reporte({'id_jornada':day,'id_local':local})
                db.session.execute(text('''UPDATE inventario_jornada SET cerrado_en=:closed,cerrado_por=:user,reporte=CAST(:report AS jsonb)
                    WHERE id_jornada=:day'''),dict(day=day,closed=opening+timedelta(hours=11,minutes=30),user=manager['id_usuario'],report=json.dumps(report)))
                registrar_actividad(manager['id_usuario'],'INVENTARIO_OPERATIVO','CIERRE_PRUEBA',day,TAG+f' · fecha simulada {date}',id_perfil_utilizado=2,id_local=local)
                days.append(day)
            after={p['id_producto']:p['stock_actual'] for p in query('SELECT * FROM inventario_stock_teorico WHERE id_local=:local',local=local)}
            assert all(after[p]==s['stock_actual']-expected.get(p,0) for p,s in stock.items())
            assert untouched==query('SELECT * FROM inventario_stock_teorico WHERE id_local<>:local ORDER BY id_local,id_producto',local=local)
            assert original_days==query('SELECT * FROM inventario_jornada WHERE id_jornada=ANY(:ids) ORDER BY id_jornada',ids=[d['id_jornada'] for d in original_days])
            assert scalar('SELECT count(*) FROM salon_pedido_actual WHERE id_local=:local',local=local)==0
            registrar_actividad(manager['id_usuario'],'INVENTARIO_OPERATIVO','CARGAR_DEMO',local,TAG,id_perfil_utilizado=2,id_local=local)
            result={**plan,'jornadas':days,'comprobantes':receipts,'total_ventas':sum(r['total'] for r in receipts),
                    'bajo_minimo':sum(after[p]<s['stock_minimo'] for p,s in stock.items() if s['stock_minimo'] is not None),
                    'sobre_minimo':sum(after[p]>s['stock_minimo'] for p,s in stock.items() if s['stock_minimo'] is not None)}
            (target/'resultado.json').write_text(json.dumps(serial(result),ensure_ascii=False,indent=2),encoding='utf-8')
            db.session.commit()
            print('CARGA CONFIRMADA. Respaldo y resultado:',target)
            print(json.dumps(result,default=str,ensure_ascii=True))
        except Exception:
            db.session.rollback();raise


if __name__=='__main__':main()
