"""Jornadas persistentes, mix de ventas y conteos físicos sin ajuste de saldo."""
import json
from datetime import date
from decimal import Decimal, InvalidOperation
from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity
from sqlalchemy import text
from werkzeug.exceptions import BadRequest, Conflict, Forbidden, NotFound
from app.core.extensions import db
from app.core.local_scope import local_actual
from app.core.permissions import requiere_permiso
from app.modules.auditoria.service import registrar_actividad, registrar_cambio

operativo_bp = Blueprint('inventario_operativo', __name__)


def instalado():
    return bool(db.session.execute(text("SELECT to_regclass('public.inventario_evento')")).scalar())


def contexto(roles=(2, 3, 4)):
    if get_jwt().get('id_perfil') not in roles:
        raise Forbidden('Tu perfil no puede realizar esta operación')
    local = local_actual()
    if not instalado():
        raise Conflict('Ejecuta database/migrations/20260926_jornadas_conteos.sql')
    return local, int(get_jwt_identity()), get_jwt()['id_perfil']


def serial(valor):
    return json.loads(json.dumps(valor, default=lambda v: float(v) if isinstance(v, Decimal) else v.isoformat()))


def filas(sql, params=None):
    return [dict(r) for r in db.session.execute(text(sql), params or {}).mappings()]


def bloqueo(local):
    db.session.execute(text("SELECT pg_advisory_xact_lock(hashtext(:clave))"), {'clave': f'inventario-dia:{local}'})


def auditar(accion, identidad, detalle):
    registrar_actividad(int(get_jwt_identity()), 'INVENTARIO_OPERATIVO', accion, identidad, detalle,
                        id_perfil_utilizado=get_jwt()['id_perfil'], id_local=get_jwt()['id_local'])


def rango():
    try:
        desde = date.fromisoformat(request.args.get('desde', ''))
        hasta = date.fromisoformat(request.args.get('hasta', ''))
    except ValueError:
        raise BadRequest('Selecciona fechas válidas')
    if hasta < desde or (hasta-desde).days > 366:
        raise BadRequest('Selecciona un rango de hasta 367 días en orden cronológico')
    return desde, hasta


def datos_json():
    datos=request.get_json(silent=True)
    if not isinstance(datos,dict):raise BadRequest('Envía un objeto con los datos de la operación')
    return datos


def ventas(local, jornada=None, desde=None, hasta=None, horas=None, separar=False):
    return filas('''SELECT (linea->>'id_presentacion')::integer AS id_presentacion,
        linea->>'nombre' AS nombre,
        CASE WHEN :separar THEN extract(hour FROM c.creado_en AT TIME ZONE 'America/Lima')::int ELSE NULL END AS hora,
        sum((linea->>'cantidad')::numeric) AS cantidad,
        sum((linea->>'cantidad')::numeric*(linea->>'precio')::numeric) AS total
        FROM salon_cobro c LEFT JOIN inventario_jornada j USING(id_jornada)
        CROSS JOIN LATERAL jsonb_array_elements(c.comprobante->'lineas') linea
        WHERE c.id_local=:local AND
        ((CAST(:jornada AS bigint) IS NOT NULL AND c.id_jornada=:jornada) OR
         (CAST(:jornada AS bigint) IS NULL AND coalesce(j.fecha,(c.creado_en AT TIME ZONE 'America/Lima')::date) BETWEEN :desde AND :hasta))
        AND (:todas OR extract(hour FROM c.creado_en AT TIME ZONE 'America/Lima')::int=ANY(:horas))
        GROUP BY 1,2,3 ORDER BY cantidad DESC,total DESC,nombre,hora''',
        dict(local=local,jornada=jornada,desde=desde,hasta=hasta,horas=horas or [],todas=not horas,separar=separar))


def reporte(jornada):
    identidad = jornada['id_jornada']
    productos = filas('''SELECT p.id_producto,p.codigo,p.nombre,p.unidad,
        coalesce(i.cantidad,0) AS inicial,
        coalesce(e.entradas,0) AS entradas,coalesce(e.salidas,0) AS salidas,
        coalesce(i.cantidad,0)+coalesce(e.entradas,0)-coalesce(e.salidas,0) AS final
        FROM producto p LEFT JOIN inventario_jornada_inicio i ON i.id_producto=p.id_producto AND i.id_jornada=:id
        LEFT JOIN (SELECT id_producto,sum(greatest(cantidad,0)) entradas,sum(greatest(-cantidad,0)) salidas
          FROM inventario_evento WHERE id_jornada=:id GROUP BY id_producto) e ON e.id_producto=p.id_producto
        WHERE i.id_producto IS NOT NULL OR e.id_producto IS NOT NULL OR p.activo ORDER BY p.nombre''', {'id': identidad})
    motivos = filas('''SELECT id_producto,motivo,sum(greatest(cantidad,0)) entradas,sum(greatest(-cantidad,0)) salidas
        FROM inventario_evento WHERE id_jornada=:id GROUP BY id_producto,motivo ORDER BY motivo''', {'id': identidad})
    for p in productos:
        p['motivos'] = [m for m in motivos if m['id_producto'] == p['id_producto']]
    return serial({'inventario': productos, 'ventas': ventas(jornada['id_local'], jornada=identidad)})


@operativo_bp.get('/dias')
@requiere_permiso(36, 'consultar')
def dias():
    local, _, _ = contexto((2,3))
    return jsonify(dias=serial(filas('''SELECT id_jornada,fecha,abierto_en,cerrado_en FROM inventario_jornada
        WHERE id_local=:local ORDER BY fecha DESC LIMIT 366''', {'local':local})))


@operativo_bp.post('/dias/abrir')
@requiere_permiso(36, 'cerrar')
def abrir():
    local, usuario, _ = contexto((2,3))
    try:
        bloqueo(local)
        identidad=db.session.execute(text('SELECT inventario_abrir_jornada(:local,:usuario)'),dict(local=local,usuario=usuario)).scalar_one()
        auditar('ABRIR_DIA',identidad,'Abrió o consultó la jornada operativa')
        db.session.commit()
        return jsonify(id_jornada=identidad)
    except Exception:
        db.session.rollback();raise


def jornada_local(local, identidad):
    registros=filas('SELECT * FROM inventario_jornada WHERE id_jornada=:id AND id_local=:local',dict(id=identidad,local=local))
    if not registros: raise NotFound('Día no encontrado en este local')
    return registros[0]


@operativo_bp.get('/dias/<int:identidad>')
@requiere_permiso(36,'consultar')
def detalle_dia(identidad):
    local,_,_=contexto((2,3))
    bloqueo(local)
    dia=jornada_local(local,identidad)
    return jsonify(serial({**dia,'reporte':dia['reporte'] if dia['cerrado_en'] else reporte(dia)}))


@operativo_bp.post('/dias/<int:identidad>/cerrar')
@requiere_permiso(36,'cerrar')
def cerrar(identidad):
    local,usuario,_=contexto((2,3))
    try:
        bloqueo(local)
        dia=jornada_local(local,identidad)
        if dia['cerrado_en']: return jsonify(serial(dia))
        # Impide que aparezca un nuevo envío entre la comprobación y el cierre.
        db.session.execute(text('LOCK TABLE salon_pedido IN SHARE MODE'))
        pendientes=db.session.execute(text('''SELECT count(*) FROM salon_pedido_actual p WHERE p.id_local=:local
            AND EXISTS(SELECT 1 FROM salon_pedido_linea l WHERE l.id_pedido=p.id_pedido
            AND NOT EXISTS(SELECT 1 FROM salon_linea_anulada a WHERE a.id_linea=l.id_linea))'''),{'local':local}).scalar()
        if pendientes: raise Conflict('Hay mesas con pedidos sin cobrar. Resuélvelas antes de cerrar el día.')
        contenido=reporte(dia)
        db.session.execute(text('''UPDATE inventario_jornada SET cerrado_en=clock_timestamp(),cerrado_por=:usuario,
            reporte=CAST(:reporte AS jsonb) WHERE id_jornada=:id'''),dict(id=identidad,usuario=usuario,reporte=json.dumps(contenido)))
        auditar('CERRAR_DIA',identidad,f"Cerró el día operativo {dia['fecha']}")
        resultado=jornada_local(local,identidad)
        db.session.commit()
        return jsonify(serial(resultado))
    except Exception:
        db.session.rollback();raise


@operativo_bp.get('/mix')
@requiere_permiso(37,'consultar')
def mix():
    local,_,_=contexto((2,3))
    desde,hasta=rango()
    try: horas=sorted(set(int(h) for h in request.args.getlist('hora')))
    except ValueError: raise BadRequest('Horas inválidas')
    if any(h<0 or h>23 for h in horas): raise BadRequest('Las horas van de 0 a 23')
    resultados=ventas(local,desde=desde,hasta=hasta,horas=horas,separar=request.args.get('separar')=='1')
    return jsonify(serial({'productos':resultados,'total':sum((r['total'] for r in resultados),Decimal(0)),
                          'cantidad':sum((r['cantidad'] for r in resultados),Decimal(0))}))


def equipo(local):
    return filas('''SELECT u.id_usuario,concat_ws(' ',u.nombres,u.apellido_paterno) nombre
        FROM usuario u JOIN usuario_local ul USING(id_usuario) WHERE ul.id_local=:local AND ul.estado_registro=1
        AND u.estado_registro=1 AND EXISTS(SELECT 1 FROM usuario_perfiles up JOIN perfiles p USING(id_perfil)
        WHERE up.id_usuario=u.id_usuario AND up.id_perfil IN (2,3,4) AND up.estado_registro=1 AND p.estado_registro=1)
        ORDER BY nombre''',{'local':local})


def puestos_instalados():
    return bool(db.session.execute(text("SELECT to_regclass('public.inventario_asignacion_puesto')")).scalar())


def puestos_conteo():
    return filas('''SELECT id_puesto_laboral,nombre FROM puesto_laboral WHERE estado_registro=1
        AND lower(trim(nombre)) IN ('cocina','bartender','mesero') ORDER BY nombre''')


def puesto_actual(usuario,perfil):
    if perfil!=4:return None
    puesto=get_jwt().get('id_puesto_laboral')
    from app.modules.auth.repository import obtener_puesto_usuario
    if type(puesto) is not int or not obtener_puesto_usuario(usuario,puesto):
        raise Forbidden('Selecciona un puesto activo que tengas asignado')
    return puesto


@operativo_bp.get('/asignaciones')
@requiere_permiso(38,'configurar')
def asignaciones():
    local,_,_=contexto((2,))
    if not puestos_instalados():raise Conflict('Ejecuta database/migrations/20260928_asignacion_conteos_puestos.sql')
    return jsonify(puestos=puestos_conteo(),productos=filas('''SELECT p.id_producto,p.codigo,p.nombre,
        cp.nombre categoria,a.id_puesto_laboral,pl.nombre puesto
        FROM producto p JOIN categoria_producto cp USING(id_categoria)
        LEFT JOIN inventario_asignacion_puesto a ON a.id_producto=p.id_producto AND a.id_local=:local
        LEFT JOIN puesto_laboral pl ON pl.id_puesto_laboral=a.id_puesto_laboral
        WHERE p.activo ORDER BY p.nombre''',{'local':local}))


@operativo_bp.put('/asignaciones')
@requiere_permiso(38,'configurar')
def guardar_asignaciones():
    local,usuario,_=contexto((2,))
    if not puestos_instalados():raise Conflict('Ejecuta database/migrations/20260928_asignacion_conteos_puestos.sql')
    d=datos_json();productos=d.get('productos');puesto=d.get('id_puesto_laboral')
    if 'id_puesto_laboral' not in d:raise BadRequest('Indica el puesto de destino o quita la asignación explícitamente')
    if not isinstance(productos,list) or not 1<=len(productos)<=5000 or any(type(p) is not int or p<=0 for p in productos):
        raise BadRequest('Selecciona entre 1 y 5000 productos')
    productos=list(set(productos))
    if puesto is not None and (type(puesto) is not int or puesto not in {p['id_puesto_laboral'] for p in puestos_conteo()}):
        raise BadRequest('Selecciona Cocina, Bartender o Mesero')
    try:
        bloqueo(local)
        if db.session.execute(text('SELECT count(*) FROM producto WHERE activo AND id_producto=ANY(:ids)'),{'ids':productos}).scalar()!=len(productos):
            raise BadRequest('Hay productos que ya no están disponibles; actualiza la lista')
        anterior=filas('SELECT * FROM inventario_asignacion_puesto WHERE id_local=:local AND id_producto=ANY(:ids)',dict(local=local,ids=productos))
        if puesto is None:
            db.session.execute(text('DELETE FROM inventario_asignacion_puesto WHERE id_local=:local AND id_producto=ANY(:ids)'),dict(local=local,ids=productos))
        else:
            db.session.execute(text('''INSERT INTO inventario_asignacion_puesto(id_local,id_producto,id_puesto_laboral,actualizado_por)
                SELECT :local,p.id_producto,:puesto,:usuario FROM producto p WHERE p.id_producto=ANY(:ids)
                ON CONFLICT(id_local,id_producto) DO UPDATE SET id_puesto_laboral=excluded.id_puesto_laboral,
                actualizado_por=excluded.actualizado_por,actualizado_en=clock_timestamp()'''),dict(local=local,ids=productos,puesto=puesto,usuario=usuario))
        auditar('ASIGNAR_PUESTOS',local,f'Actualizó la asignación por puesto de {len(productos)} productos')
        registrar_cambio(usuario,'INVENTARIO_OPERATIVO','ASIGNAR_PUESTOS','inventario_asignacion_puesto',local,
                         serial(anterior),dict(productos=productos,id_puesto_laboral=puesto),id_local=local)
        db.session.commit();return jsonify(mensaje='Asignación guardada para los próximos conteos')
    except Exception:db.session.rollback();raise


@operativo_bp.get('/conteos')
@requiere_permiso(38,'consultar')
def rondas():
    local,usuario,perfil=contexto()
    nuevo=puestos_instalados()
    puesto=puesto_actual(usuario,perfil) if nuevo else None
    filtro='c.asignado_a=:usuario'
    if nuevo:filtro='((r.por_puesto AND c.puesto_asignado=:puesto) OR (NOT r.por_puesto AND c.asignado_a=:usuario))'
    registros=filas(f'''SELECT r.* FROM inventario_ronda r WHERE id_local=:local
        AND (:gestor OR EXISTS(SELECT 1 FROM inventario_conteo c WHERE c.id_ronda=r.id_ronda AND {filtro}))
        ORDER BY creado_en DESC LIMIT 200''',dict(local=local,usuario=usuario,puesto=puesto,gestor=perfil in (2,3)))
    return jsonify(rondas=serial(registros),por_puesto=nuevo,equipo=equipo(local) if perfil==2 else [])


@operativo_bp.post('/conteos')
@requiere_permiso(38,'crear')
def crear_ronda():
    local,usuario,_=contexto((2,))
    nuevo=puestos_instalados()
    datos=datos_json()
    nombre=datos.get('nombre','')
    if not isinstance(nombre,str) or not 1<=len(nombre.strip())<=120: raise BadRequest('Indica un nombre de hasta 120 caracteres')
    try:
        bloqueo(local)
        if nuevo and not db.session.execute(text('''SELECT 1 FROM inventario_asignacion_puesto a
                JOIN producto p USING(id_producto) JOIN puesto_laboral pl USING(id_puesto_laboral)
                WHERE a.id_local=:local AND p.activo AND pl.estado_registro=1 LIMIT 1'''),{'local':local}).scalar():
            raise Conflict('Primero configura los productos en Asignación por puesto')
        if db.session.execute(text('SELECT 1 FROM inventario_ronda WHERE id_local=:local AND cerrado_en IS NULL'),{'local':local}).scalar():
            raise Conflict('Ya existe una ronda abierta. Finalízala antes de iniciar otra.')
        identidad=db.session.execute(text('''INSERT INTO inventario_ronda(id_local,nombre,creado_por)
            VALUES(:local,:nombre,:usuario) RETURNING id_ronda'''),dict(local=local,nombre=nombre.strip(),usuario=usuario)).scalar_one()
        db.session.execute(text('''INSERT INTO inventario_conteo(id_ronda,id_producto,teorico)
            SELECT :id,s.id_producto,s.stock_actual FROM inventario_stock_teorico s JOIN producto p USING(id_producto)
            WHERE s.id_local=:local AND p.activo'''),dict(id=identidad,local=local))
        if nuevo:
            db.session.execute(text('UPDATE inventario_ronda SET por_puesto=true WHERE id_ronda=:id'),{'id':identidad})
            db.session.execute(text('''UPDATE inventario_conteo c SET puesto_asignado=a.id_puesto_laboral,puesto_nombre=p.nombre
                FROM inventario_asignacion_puesto a JOIN puesto_laboral p USING(id_puesto_laboral)
                WHERE c.id_ronda=:id AND c.id_producto=a.id_producto AND a.id_local=:local AND p.estado_registro=1'''),dict(id=identidad,local=local))
        auditar('INICIAR_CONTEO',identidad,nombre.strip())
        db.session.commit();return jsonify(id_ronda=identidad),201
    except Exception: db.session.rollback();raise


def ronda_local(local,identidad):
    registros=filas('SELECT * FROM inventario_ronda WHERE id_ronda=:id AND id_local=:local',dict(id=identidad,local=local))
    if not registros: raise NotFound('Conteo no encontrado en este local')
    return registros[0]


@operativo_bp.get('/conteos/<int:identidad>')
@requiere_permiso(38,'consultar')
def detalle_conteo(identidad):
    local,usuario,perfil=contexto()
    ronda=ronda_local(local,identidad)
    puesto=puesto_actual(usuario,perfil) if ronda.get('por_puesto') else None
    filtro='c.puesto_asignado=:puesto' if ronda.get('por_puesto') else 'c.asignado_a=:usuario'
    registros=filas(f'''SELECT c.*,p.nombre,p.codigo,p.unidad,cp.nombre AS categoria,
        concat_ws(' ',u.nombres,u.apellido_paterno) AS asignado_nombre,
        concat_ws(' ',contador.nombres,contador.apellido_paterno) AS contado_nombre,
        coalesce(c.corregido,c.contado)-c.teorico AS diferencia
        FROM inventario_conteo c JOIN producto p USING(id_producto) JOIN categoria_producto cp USING(id_categoria)
        LEFT JOIN usuario contador ON contador.id_usuario=c.contado_por
        LEFT JOIN usuario u ON u.id_usuario=c.asignado_a WHERE c.id_ronda=:id
        AND (:gestor OR {filtro}) ORDER BY p.nombre''',dict(id=identidad,usuario=usuario,puesto=puesto,gestor=perfil in (2,3)))
    if perfil==4:
        for r in registros:
            for k in ('teorico','diferencia','corregido','justificacion','justificado_por','justificado_en'):r.pop(k,None)
    return jsonify(serial({'ronda':ronda,'productos':registros,'equipo':equipo(local) if perfil==2 else [],
                           'puestos':puestos_conteo() if ronda.get('por_puesto') else []}))


def cantidad(valor):
    try: n=Decimal(str(valor))
    except (InvalidOperation,ValueError): raise BadRequest('Cantidad inválida')
    if not n.is_finite() or n<0 or n>Decimal('999999999.999') or n!=n.quantize(Decimal('.001')):
        raise BadRequest('Ingresa una cantidad no negativa con hasta tres decimales')
    return n


@operativo_bp.put('/conteos/<int:identidad>/productos/<int:producto>')
@requiere_permiso(38,'editar')
def editar_conteo(identidad,producto):
    local,usuario,perfil=contexto()
    d=datos_json()
    accion=d.get('accion')
    if not isinstance(accion,str):raise BadRequest('Acción inválida')
    permiso={'asignar':'puede_configurar','revisar':'puede_revisar','justificar':'puede_revisar','contar':'puede_editar'}.get(accion)
    if not permiso: raise BadRequest('Acción inválida')
    if not db.session.execute(text(f'''SELECT {permiso} FROM perfil_opcion_menu WHERE id_perfil=:perfil
        AND id_opcion_menu=38 AND estado_registro=1'''),{'perfil':perfil}).scalar(): raise Forbidden('No tienes permiso para esta acción')
    try:
        # Serializa revisión/finalización de una ronda; evita corregir después de cerrarla.
        db.session.execute(text('SELECT id_ronda FROM inventario_ronda WHERE id_ronda=:id AND id_local=:local FOR UPDATE'),dict(id=identidad,local=local))
        ronda=ronda_local(local,identidad)
        rows=filas('SELECT * FROM inventario_conteo WHERE id_ronda=:id AND id_producto=:producto FOR UPDATE',dict(id=identidad,producto=producto))
        if not rows: raise NotFound('Producto no encontrado en el conteo')
        old=rows[0]
        if type(d.get('version')) is not int or d['version']!=old['version']:raise Conflict('El registro cambió. Actualiza antes de guardar.')
        if ronda['cerrado_en'] and accion!='justificar':raise Conflict('La ronda ya está finalizada')
        valores={}
        if accion=='asignar':
            if perfil!=2:raise Forbidden('Solo el gerente asigna conteos')
            if old['estado']!='PENDIENTE':raise Conflict('No reasignes un producto que ya tiene un conteo')
            if ronda.get('por_puesto'):
                asignado=d.get('id_puesto_laboral')
                puestos={p['id_puesto_laboral']:p['nombre'] for p in puestos_conteo()}
                if type(asignado) is not int or asignado not in puestos:raise BadRequest('Selecciona un puesto válido')
                valores={'puesto_asignado':asignado,'puesto_nombre':puestos[asignado]}
            else:
                asignado=d.get('id_usuario')
                if asignado is not None and (type(asignado) is not int or asignado not in {u['id_usuario'] for u in equipo(local)}):raise BadRequest('Usuario no disponible en este local')
                valores={'asignado_a':asignado}
        elif accion=='contar':
            puesto=puesto_actual(usuario,perfil) if ronda.get('por_puesto') else None
            if perfil==4 and (old.get('puesto_asignado')!=puesto if ronda.get('por_puesto') else old['asignado_a']!=usuario):raise Forbidden('Solo puedes contar los productos de tu puesto activo')
            if old['estado']=='REVISADO':raise Conflict('El conteo ya fue revisado')
            if ronda.get('por_puesto') and old['estado']=='HECHO':raise Conflict('Ya se entregó este conteo; un responsable debe revisarlo')
            if perfil in (2,3) and (old['estado']=='HECHO' or old['contado_por'] not in (None,usuario)):
                raise Conflict('Conserva el conteo original: espera a que esté Hecho y usa Revisar para corregirlo con una observación')
            estado=d.get('estado')
            if estado not in ('EN_PROCESO','HECHO'):raise BadRequest('Selecciona En proceso o Hecho')
            valores={'contado':cantidad(d.get('cantidad')),'contado_por':usuario,'estado':estado}
            if puestos_instalados():
                nombre_perfil=db.session.execute(text('SELECT nombre FROM perfiles WHERE id_perfil=:id'),{'id':perfil}).scalar()
                nombre_puesto=db.session.execute(text('SELECT nombre FROM puesto_laboral WHERE id_puesto_laboral=:id'),{'id':puesto}).scalar() if puesto else None
                valores.update(contado_perfil=perfil,contado_puesto=puesto,contado_perfil_nombre=nombre_perfil,contado_puesto_nombre=nombre_puesto)
        elif accion=='revisar':
            if perfil not in (2,3):raise Forbidden('Solo gerente o supervisor revisa')
            if old['estado'] not in ('HECHO','REVISADO'):raise Conflict('El miembro debe marcar el conteo como Hecho')
            observacion=d.get('observacion','')
            if not isinstance(observacion,str) or len(observacion)>2000:raise BadRequest('Observación inválida')
            nuevo=cantidad(d.get('cantidad'))
            if nuevo!=old['contado'] and not observacion.strip():raise BadRequest('Indica la observación de la corrección, por ejemplo: mal conteo')
            valores={'corregido':nuevo,'estado':'REVISADO','observacion':observacion.strip(),'revisado_por':usuario,
                     'justificacion':'','justificado_por':None,'justificado_en':None}
        else:
            if perfil not in (2,3) or old['estado']!='REVISADO':raise Forbidden('Primero debe estar revisado por un responsable')
            justificacion=d.get('justificacion','')
            if not isinstance(justificacion,str) or not 1<=len(justificacion.strip())<=2000:raise BadRequest('Escribe una justificación de hasta 2000 caracteres')
            valores={'justificacion':justificacion.strip(),'justificado_por':usuario}
        # Columnas escogidas en servidor; ninguna clave del cliente entra en el SQL.
        campos=','.join(f'{k}=:{k}' for k in valores)
        fecha={'contar':'contado_en','revisar':'revisado_en','justificar':'justificado_en'}.get(accion)
        if fecha:campos+=f',{fecha}=clock_timestamp()'
        nuevo=filas(f'UPDATE inventario_conteo SET {campos},version=version+1 WHERE id_ronda=:id AND id_producto=:producto RETURNING *',
                    {**valores,'id':identidad,'producto':producto})[0]
        db.session.execute(text('''INSERT INTO inventario_conteo_historial(id_ronda,id_producto,id_usuario,accion,anterior,nuevo)
            VALUES(:id,:producto,:usuario,:accion,CAST(:anterior AS jsonb),CAST(:nuevo AS jsonb))'''),
            dict(id=identidad,producto=producto,usuario=usuario,accion=accion,anterior=json.dumps(serial(old)),nuevo=json.dumps(serial(nuevo))))
        auditar(accion.upper(),identidad,f'Conteo {identidad}, producto {producto}')
        db.session.commit();return jsonify(mensaje='Guardado. El stock teórico no se modifica.')
    except Exception:db.session.rollback();raise


@operativo_bp.post('/conteos/<int:identidad>/finalizar')
@requiere_permiso(38,'cerrar')
def finalizar_conteo(identidad):
    local,usuario,_=contexto((2,3))
    datos=datos_json()
    try:
        db.session.execute(text('SELECT id_ronda FROM inventario_ronda WHERE id_ronda=:id AND id_local=:local FOR UPDATE'),dict(id=identidad,local=local))
        ronda=ronda_local(local,identidad)
        if ronda['cerrado_en']:return jsonify(mensaje='La ronda ya está finalizada')
        if datos.get('aceptar_entregados') is True:
            registros=filas('SELECT * FROM inventario_conteo WHERE id_ronda=:id ORDER BY id_producto FOR UPDATE',{'id':identidad})
            versiones=datos.get('versiones')
            esperadas={str(r['id_producto']):r['version'] for r in registros}
            if not isinstance(versiones,dict) or versiones!=esperadas:
                raise Conflict('El conteo cambió. Actualiza y revisa los cambios antes de cerrar.')
            if not registros or any(r['estado'] not in ('HECHO','REVISADO') for r in registros):
                raise Conflict('Todavía hay productos pendientes de entregar por el equipo')
            cambios=datos.get('correcciones',{})
            if not isinstance(cambios,dict) or any(k not in esperadas for k in cambios):
                raise BadRequest('Correcciones inválidas para esta ronda')
            if cambios and not db.session.execute(text('''SELECT puede_revisar FROM perfil_opcion_menu
                WHERE id_perfil=:perfil AND id_opcion_menu=38 AND estado_registro=1'''),{'perfil':get_jwt()['id_perfil']}).scalar():
                raise Forbidden('No tienes permiso para corregir esta revisión')
            validados={}
            for clave,cambio in cambios.items():
                if not isinstance(cambio,dict) or set(cambio)!={'cantidad','observacion'}:
                    raise BadRequest('Solo puedes corregir cantidad y observación')
                nota=cambio['observacion']
                if not isinstance(nota,str) or len(nota)>2000:raise BadRequest('Observación inválida')
                validados[clave]=(cantidad(cambio['cantidad']),nota.strip())
            for old in registros:
                cambio=validados.get(str(old['id_producto']))
                if old['estado']=='REVISADO' and cambio is None:continue
                valor,nota=cambio if cambio is not None else (old['contado'],old['observacion'])
                nuevo=filas('''UPDATE inventario_conteo SET corregido=:valor,observacion=:nota,estado='REVISADO',
                    justificacion='',justificado_por=NULL,justificado_en=NULL,
                    revisado_por=:usuario,revisado_en=clock_timestamp(),version=version+1
                    WHERE id_ronda=:id AND id_producto=:producto RETURNING *''',
                    dict(id=identidad,producto=old['id_producto'],usuario=usuario,valor=valor,nota=nota))[0]
                db.session.execute(text('''INSERT INTO inventario_conteo_historial(id_ronda,id_producto,id_usuario,accion,anterior,nuevo)
                    VALUES(:id,:producto,:usuario,'revisar',CAST(:anterior AS jsonb),CAST(:nuevo AS jsonb))'''),
                    dict(id=identidad,producto=old['id_producto'],usuario=usuario,
                         anterior=json.dumps(serial(old)),nuevo=json.dumps(serial(nuevo))))
        if db.session.execute(text("SELECT count(*) FROM inventario_conteo WHERE id_ronda=:id AND estado<>'REVISADO'"),{'id':identidad}).scalar():
            raise Conflict('Revisa todos los productos antes de finalizar')
        db.session.execute(text('UPDATE inventario_ronda SET cerrado_en=clock_timestamp() WHERE id_ronda=:id'),{'id':identidad})
        auditar('FINALIZAR_CONTEO',identidad,'Finalizó la revisión del conteo físico sin ajustar stock')
        db.session.commit();return jsonify(mensaje='Conteo finalizado')
    except Exception:db.session.rollback();raise


@operativo_bp.get('/diferencias')
@requiere_permiso(38,'revisar')
def diferencias():
    local,_,_=contexto((2,3));desde,hasta=rango()
    try:top=int(request.args.get('top','10'))
    except ValueError:raise BadRequest('Top inválido')
    if top not in (5,10,15,20):raise BadRequest('Elige top 5, 10, 15 o 20')
    datos=filas('''SELECT c.*,p.nombre,p.unidad,r.nombre AS ronda,r.creado_en,
        coalesce(c.corregido,c.contado)-c.teorico AS diferencia FROM inventario_conteo c
        JOIN inventario_ronda r USING(id_ronda) JOIN producto p USING(id_producto)
        WHERE r.id_local=:local AND (r.creado_en AT TIME ZONE 'America/Lima')::date BETWEEN :desde AND :hasta
        AND c.estado='REVISADO' AND coalesce(c.corregido,c.contado)<>c.teorico
        ORDER BY abs(coalesce(c.corregido,c.contado)-c.teorico) DESC,r.creado_en DESC,p.nombre LIMIT :top''',
        dict(local=local,desde=desde,hasta=hasta,top=top))
    return jsonify(productos=serial(datos))


@operativo_bp.get('/conteos/<int:identidad>/historial')
@requiere_permiso(38,'revisar')
def historial(identidad):
    local,_,_=contexto((2,3));ronda_local(local,identidad)
    return jsonify(historial=serial(filas('''SELECT h.*,concat_ws(' ',u.nombres,u.apellido_paterno) usuario,p.nombre producto
        FROM inventario_conteo_historial h JOIN usuario u USING(id_usuario) JOIN producto p USING(id_producto)
        WHERE h.id_ronda=:id ORDER BY h.id_historial DESC LIMIT 1000''',{'id':identidad})))
