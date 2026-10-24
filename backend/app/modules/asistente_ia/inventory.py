"""Herramientas del agente de inventario. Siempre reutilizan rutas y permisos nativos."""
from datetime import date
from urllib.parse import urlencode
from flask_jwt_extended import get_jwt
from .provider import AssistantError

BASE='/inventario-operativo'
RESOURCES={
    'stock':(15,'/inventarios/stock','productos','id_producto'),
    'conteos':(38,BASE+'/conteos','rondas','id_ronda'),
    'asignaciones_conteo':(38,BASE+'/asignaciones','productos','id_producto'),
    'revision_conteo':(38,BASE+'/conteos','rondas','id_ronda'),
    'diferencias_conteo':(38,BASE+'/diferencias','productos','id_producto'),
    'jornadas':(36,BASE+'/dias','dias','id_jornada'),
    'mix_ventas':(37,BASE+'/mix','productos','id_presentacion'),
}


def allowed(session,resource,action):
    profile=get_jwt().get('id_perfil')
    if resource not in RESOURCES or profile not in (2,3,4):return False
    permissions={'consultar':'consultar'}
    if resource=='conteos' and profile==2:permissions['crear']='crear'
    if resource=='asignaciones_conteo':
        if profile!=2:return False
        permissions={'consultar':'configurar','editar':'configurar'}
    if resource in ('revision_conteo','diferencias_conteo'):
        if profile not in (2,3):return False
        permissions={'consultar':'revisar'}
        if resource=='revision_conteo':permissions['editar']='cerrar'
    if resource in ('jornadas','mix_ventas') and profile not in (2,3):return False
    permission=permissions.get(action)
    entry=next((m for m in session['menu'] if m['id_opcion_menu']==RESOURCES[resource][0]),None)
    return bool(permission and entry and entry.get('permisos',{}).get(permission) and
        (resource!='revision_conteo' or entry.get('permisos',{}).get('revisar')))


def positive(value):
    if type(value) is not int or value<=0:raise AssistantError('Indica un identificador válido.')
    return value


def read(session,resource,filters=None):
    from . import tools
    tools.authorize(session,resource)
    f={} if filters is None else filters
    permitted={'busqueda','desde_registro'}
    permitted|={'stock':{'bajo_minimo'},'conteos':{'id'},'revision_conteo':{'id'},
        'asignaciones_conteo':{'puesto','sin_asignar'},'jornadas':{'id'},
        'mix_ventas':{'desde','hasta','horas','por_hora'},'diferencias_conteo':{'desde','hasta','top'}}[resource]
    if not isinstance(f,dict) or set(f)-permitted:raise AssistantError('Filtros no permitidos. El local proviene de la sesión.')
    search=f.get('busqueda','');offset=f.get('desde_registro',0)
    if not isinstance(search,str) or len(search)>200 or type(offset) is not int or offset<0:raise AssistantError('Filtro inválido.')
    for key in ('bajo_minimo','sin_asignar','por_hora'):
        if key in f and type(f[key]) is not bool:raise AssistantError('Filtro booleano inválido.')
    path=RESOURCES[resource][1];metadata={}
    if resource in ('conteos','revision_conteo','jornadas') and f.get('id') is not None:
        path+=f"/{positive(f['id'])}"
    if resource in ('mix_ventas','diferencias_conteo'):
        try:start=date.fromisoformat(f.get('desde',''));end=date.fromisoformat(f.get('hasta',''))
        except (ValueError,TypeError):raise AssistantError('Indica fecha desde y hasta (AAAA-MM-DD).') from None
        if end<start or (end-start).days>366:raise AssistantError('El rango máximo es de 367 días.')
        params={'desde':start.isoformat(),'hasta':end.isoformat()}
        if resource=='diferencias_conteo':
            top=f.get('top',10)
            if type(top) is not int or top not in (5,10,15,20):raise AssistantError('Top permitido: 5, 10, 15 o 20.')
            params['top']=top
        else:
            hours=f.get('horas',[])
            if not isinstance(hours,list) or any(type(h) is not int or h<0 or h>23 for h in hours):raise AssistantError('Horas inválidas.')
            params.update(hora=hours,separar='1' if f.get('por_hora') else '0')
        path+='?'+urlencode(params,doseq=True)
    result=tools.native(path)
    if resource in ('conteos','revision_conteo') and f.get('id'):
        rows=result['productos'];metadata={'ronda':result['ronda'],
            'referencia':'Stock teórico al abrir la ronda; no se descuentan ventas nuevamente.',
            'avance':[{ 'puesto':position,'productos':len(group),
                'pendientes':sum(p['estado'] in ('PENDIENTE','EN_PROCESO') for p in group),
                'entregados':sum(p['estado'] in ('HECHO','REVISADO') for p in group)}
                for position in sorted({p.get('puesto_nombre') or p.get('asignado_nombre') or 'Sin asignar' for p in rows})
                for group in [[p for p in rows if (p.get('puesto_nombre') or p.get('asignado_nombre') or 'Sin asignar')==position]]]}
    elif resource=='jornadas' and f.get('id'):
        rows=result['reporte']['inventario'];metadata={'fecha':result['fecha'],'cerrado_en':result['cerrado_en'],
            'ventas':result['reporte']['ventas']}
    else:
        rows=result.get(RESOURCES[resource][2],[])
        if resource=='asignaciones_conteo':metadata['puestos']=result['puestos']
        if resource=='mix_ventas':metadata.update(total_ventas=result['total'],cantidad_vendida=result['cantidad'])
    if f.get('bajo_minimo'):rows=[p for p in rows if p.get('stock_actual',0)<(p.get('stock_minimo') or 0)]
    if f.get('sin_asignar'):rows=[p for p in rows if p.get('id_puesto_laboral') is None]
    if f.get('puesto') is not None:
        position=positive(f['puesto']);rows=[p for p in rows if p.get('id_puesto_laboral')==position]
    terms=tools.normalized(search).split()
    rows=[r for r in rows if all(t in tools.normalized(str(r)) for t in terms)]
    return {'recurso':resource,'total':len(rows),'desde':offset,'registros':rows[offset:offset+30],
        'hay_mas':len(rows)>offset+30,'contexto':metadata}


def current(session,resource,identity):
    from . import tools
    tools.authorize(session,resource)
    if resource=='asignaciones_conteo':return tools.native(BASE+'/asignaciones')
    if resource=='revision_conteo':return tools.native(f'{BASE}/conteos/{positive(identity)}')
    return None


def prepare(session,resource,action,identity,changes):
    from . import tools
    tools.authorize(session,resource,action)
    if not isinstance(changes,dict):raise AssistantError('Datos inválidos.')
    previous=None
    if resource=='conteos' and action=='crear':
        if identity is not None or set(changes)!={'nombre'} or not isinstance(changes['nombre'],str) or not 1<=len(changes['nombre'].strip())<=120:
            raise AssistantError('Para abrir un conteo indica únicamente su nombre (hasta 120 caracteres).')
        if any(not r['cerrado_en'] for r in tools.native(BASE+'/conteos')['rondas']):raise AssistantError('Ya hay un conteo abierto. Revisa y cierra ese conteo primero.',409)
        payload={'nombre':changes['nombre'].strip()}
    elif resource=='asignaciones_conteo' and action=='editar':
        if identity is not None or set(changes)!={'productos','id_puesto_laboral'}:raise AssistantError('Indica productos e id_puesto_laboral.')
        previous=current(session,resource,None)
        ids=changes['productos'];position=changes['id_puesto_laboral']
        if not isinstance(ids,list) or not 1<=len(ids)<=5000 or any(type(p) is not int for p in ids):raise AssistantError('Selecciona productos existentes.')
        if not set(ids)<={p['id_producto'] for p in previous['productos']}:raise AssistantError('Algún producto no existe o está inactivo.')
        if position is not None and (type(position) is not int or position not in {p['id_puesto_laboral'] for p in previous['puestos']}):raise AssistantError('Selecciona un puesto existente.')
        payload={'productos':sorted(set(ids)),'id_puesto_laboral':position}
    elif resource=='revision_conteo' and action=='editar':
        if set(changes)!={'correcciones'} or not isinstance(changes['correcciones'],dict):raise AssistantError('Indica correcciones por ID de producto, o {} para aceptar lo entregado.')
        previous=current(session,resource,identity)
        if previous['ronda']['cerrado_en']:raise AssistantError('Esta revisión ya está cerrada.',409)
        rows=previous['productos'];by_id={str(p['id_producto']):p for p in rows}
        if not rows or any(p['estado'] not in ('HECHO','REVISADO') for p in rows):raise AssistantError('Faltan entregas del equipo; todavía no puedes cerrar la revisión.',409)
        from app.modules.inventarios.operativo import cantidad
        from werkzeug.exceptions import BadRequest
        corrections={}
        for key,change in changes['correcciones'].items():
            if key not in by_id or not isinstance(change,dict) or set(change)!={'cantidad','observacion'}:raise AssistantError('Solo puedes corregir cantidades y observaciones de productos del conteo.')
            note=change['observacion']
            if not isinstance(note,str) or len(note)>2000:raise AssistantError('Observación inválida.')
            try:value=cantidad(change['cantidad'])
            except BadRequest as e:raise AssistantError(e.description) from None
            corrections[key]={'cantidad':str(value),'observacion':note.strip()}
        payload={'aceptar_entregados':True,'versiones':{key:p['version'] for key,p in by_id.items()},'correcciones':corrections}
    else:raise AssistantError('Esta operación de inventario no está habilitada.')
    return dict(recurso=resource,accion=action,id=identity,datos=payload,anterior=previous)


def execute(session,plan):
    from . import tools
    resource=plan['recurso'];tools.authorize(session,resource,plan['accion'])
    if resource=='conteos':
        result=tools.native(BASE+'/conteos','POST',plan['datos'])
        return {**result,'mensaje':'Conteo abierto para el equipo del local activo.'}
    if resource=='asignaciones_conteo':
        from app.modules.inventarios.operativo import bloqueo
        from app.core.local_scope import local_actual
        bloqueo(local_actual())
        if current(session,resource,None)!=plan['anterior']:raise AssistantError('Las asignaciones cambiaron. Prepara nuevamente el borrador.',409)
        return tools.native(BASE+'/asignaciones','PUT',plan['datos'])
    if resource=='revision_conteo':return tools.native(f"{BASE}/conteos/{positive(plan['id'])}/finalizar",'POST',plan['datos'])
    raise AssistantError('Operación no permitida.')


def readable(session,plan):
    local=session.get('local_activo') or {}
    result={'local':local.get('nombre','Local activo')}
    resource=plan['recurso'];data=plan['datos'];old=plan['anterior']
    if resource=='conteos':return {**result,'operacion':'Abrir conteo para el equipo','nombre':data['nombre'],
        'distribucion':'Se copiarán los productos asignados a cada puesto. No cambia el stock.'}
    if resource=='asignaciones_conteo':
        position=next((p['nombre'] for p in old['puestos'] if p['id_puesto_laboral']==data['id_puesto_laboral']),'Sin asignar')
        return {**result,'operacion':'Asignar productos para los próximos conteos','puesto_destino':position,
            'productos':[{'nombre':p['nombre'],'puesto_anterior':p['puesto'] or 'Sin asignar'} for p in old['productos'] if p['id_producto'] in data['productos']]}
    return {**result,'operacion':'Guardar y cerrar revisión','conteo':old['ronda']['nombre'],
        'productos_aceptados':len(old['productos']), 'correcciones':[{'producto':p['nombre'],'sistema':p['teorico'],
            'contado_original':p['contado'],'cantidad_revisada':data['correcciones'][str(p['id_producto'])]['cantidad'],
            'observacion':data['correcciones'][str(p['id_producto'])]['observacion']} for p in old['productos'] if str(p['id_producto']) in data['correcciones']],
        'efecto':'Cierra toda la revisión, conserva originales e historial y no ajusta el stock.'}
