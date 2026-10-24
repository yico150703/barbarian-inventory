"""Consulta paginada de eventos y cambios conservando su procedencia."""
from datetime import date
from flask_jwt_extended import get_jwt
from sqlalchemy import text
from werkzeug.exceptions import BadRequest, Forbidden
from app.core.extensions import db
from app.core.local_scope import local_actual


def sanitizar(valor):
    if isinstance(valor, dict):
        return {k: sanitizar(v) for k, v in valor.items()
                if not any(s in k.lower() for s in ('clave', 'password', 'contras', 'token', 'secret', 'hash', 'pin_salon'))}
    if isinstance(valor, list):
        return [sanitizar(v) for v in valor]
    return valor


def historial(args):
    administrador = get_jwt().get('id_perfil') == 1
    local = None if administrador else local_actual()
    filtro = args.get('local', '')
    globales = filtro == 'global'
    if not administrador and globales:
        raise Forbidden('Solo puedes consultar la actividad de tu local')
    if filtro and not globales:
        try:
            elegido = int(filtro)
            if elegido <= 0: raise ValueError()
        except ValueError:
            raise BadRequest('Local inválido')
        if not administrador and elegido != local:
            raise Forbidden('Solo puedes consultar la actividad de tu local')
        local = elegido
    try:
        pagina = int(args.get('pagina', '1'))
        if not 1 <= pagina <= 100000: raise ValueError()
        desde = date.fromisoformat(args['desde']) if args.get('desde') else None
        hasta = date.fromisoformat(args['hasta']) if args.get('hasta') else None
        if desde and hasta and desde > hasta: raise ValueError()
    except ValueError:
        raise BadRequest('Revisa la página y el intervalo de fechas')
    q = args.get('buscar','').strip()[:150]
    registros = db.session.execute(text('''
        WITH eventos AS (
          SELECT 'actividad' AS origen, id_actividad_usuario AS id, id_usuario,
            id_perfil_utilizado,id_puesto_laboral,id_local,modulo,accion,id_registro_afectado,
            descripcion,fecha_actividad AS fecha,NULL::text AS tabla,
            NULL::jsonb AS antes,NULL::jsonb AS despues
          FROM actividad_usuario WHERE estado_registro=1
          UNION ALL
          SELECT 'cambio',id_auditoria_cambio,id_usuario,id_perfil_utilizado,id_puesto_laboral,
            id_local,modulo,accion,id_registro_afectado,COALESCE(motivo,'Cambio registrado'),
            fecha_cambio,tabla_afectada,datos_anteriores,datos_nuevos FROM auditoria_cambio
        )
        SELECT e.*,concat_ws(' ',u.nombres,u.apellido_paterno,u.apellido_materno) AS usuario,
          p.nombre AS perfil,pl.nombre AS puesto,l.nombre AS local,
          CASE WHEN objetivo.id_usuario IS NOT NULL THEN
            concat_ws(' ',objetivo.nombres,objetivo.apellido_paterno,objetivo.apellido_materno) END AS usuario_afectado
        FROM eventos e JOIN usuario u ON u.id_usuario=e.id_usuario
        LEFT JOIN perfiles p ON p.id_perfil=e.id_perfil_utilizado
        LEFT JOIN puesto_laboral pl ON pl.id_puesto_laboral=e.id_puesto_laboral
        LEFT JOIN local l ON l.id_local=e.id_local
        LEFT JOIN usuario objetivo ON objetivo.id_usuario=e.id_registro_afectado
          AND (e.modulo='USUARIOS' OR e.tabla='usuario')
        WHERE NOT (e.modulo='AUTENTICACION' AND e.accion='CAMBIAR_PERFIL')
          AND (CAST(:local AS integer) IS NULL OR e.id_local=:local)
          AND (NOT :globales OR e.id_local IS NULL)
          AND (CAST(:desde AS date) IS NULL OR e.fecha >= CAST(:desde AS date))
          AND (CAST(:hasta AS date) IS NULL OR e.fecha < CAST(:hasta AS date)+interval '1 day')
          AND (:q='' OR concat_ws(' ',u.nombres,u.apellido_paterno,objetivo.nombres,
              objetivo.apellido_paterno,e.modulo,e.accion,e.descripcion) ILIKE :patron)
        ORDER BY e.fecha DESC,e.origen,e.id DESC LIMIT 51 OFFSET :offset
    '''), {'local':local,'globales':globales,'desde':desde,'hasta':hasta,'q':q,
           'patron':f'%{q}%','offset':(pagina-1)*50}).mappings().all()
    eventos=[]
    for r in registros[:50]:
        item=dict(r)
        item['fecha']=r['fecha'].isoformat()
        item['antes']=sanitizar(r['antes'])
        item['despues']=sanitizar(r['despues'])
        eventos.append(item)
    locales=db.session.execute(text('SELECT id_local,nombre FROM local WHERE CAST(:local AS integer) IS NULL OR id_local=:local ORDER BY nombre'),
                               {'local':None if administrador else local}).mappings().all()
    return {'eventos':eventos,'pagina':pagina,'hay_mas':len(registros)>50,
            'marca_completa':administrador,'locales':[dict(l) for l in locales]}
