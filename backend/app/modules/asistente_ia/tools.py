"""Explicit application capabilities; no arbitrary URLs, SQL or code from the model."""
import json
import unicodedata
from flask import current_app, request
from flask_jwt_extended import get_jwt
from .provider import AssistantError
from . import inventory, purchases

# menu permission, native URL, collection, primary key
RESOURCES = {
    'productos': (4, '/catalogos/productos', 'productos', 'id_producto'),
    'categorias_productos': (5, '/catalogos/categorias-productos', 'categorias', 'id_categoria'),
    'proveedores': (6, '/catalogos/proveedores', 'proveedores', 'id_proveedor'),
    'categorias_carta': (8, '/carta/categorias', 'categorias', 'id_categoria_carta'),
    'presentaciones': (9, '/carta/presentaciones', 'presentaciones', 'id_presentacion_venta'),
    'menajes': (10, '/carta/menajes', 'menajes', 'id_menaje'),
    'subproductos': (12, '/produccion/subproductos', 'subproductos', 'id_subproducto'),
    'recetas': (28, '/recetas', 'recetas', 'id_receta'),
    'promociones': (14, '/promociones', 'promociones', 'id_promocion'),
    'usuarios': (2, '/usuarios', 'usuarios', 'id_usuario'),
}
RESOURCES.update(inventory.RESOURCES)
RESOURCES.update(purchases.RESOURCES)
FIELDS = {
    'productos': 'nombre id_categoria id_proveedor unidad presentacion unidad_presentacion motivo',
    'categorias_productos': 'nombre prefijo', 'proveedores': 'nombre ids_categorias',
    'categorias_carta': 'nombre prefijo', 'menajes': 'nombre',
    'presentaciones': 'id_item_carta nombre_item tipo_item id_categoria_carta contenido unidad id_menaje precio activo',
    'recetas': 'id_presentacion_venta instrucciones componentes grupo_salsa',
    'subproductos': 'nombre unidad rendimiento instruccion activo ingredientes',
    'promociones': 'nombre precio activo hora_inicio hora_fin grupos',
}
REQUIRED = {k: set(v.split()) - {'motivo', 'id_item_carta', 'grupo_salsa', 'unidad_presentacion'} for k, v in FIELDS.items()}


def allowed(session, resource, action='consultar'):
    if resource in purchases.RESOURCES:return purchases.allowed(session,resource,action)
    if resource in inventory.RESOURCES:return inventory.allowed(session,resource,action)
    if resource not in RESOURCES:
        return False
    if action != 'consultar' and (resource == 'usuarios' or int(get_jwt().get('id_perfil', 0)) != 1):
        return False
    return any(m['id_opcion_menu'] == RESOURCES[resource][0] and
               m.get('permisos', {}).get(action, False) for m in session['menu'])


def authorize(session, resource, action='consultar'):
    if not allowed(session, resource, action):
        raise AssistantError('Tu perfil activo no tiene permiso para ' + action + ' ' + resource.replace('_', ' ') + '.', 403)


def native(path, method='GET', data=None):
    # Local dispatch reuses the REAL route, JWT decorators, local scope and audit.
    # Only callers below construct paths from RESOURCES + validated integer IDs.
    app = current_app._get_current_object()
    headers = {'Authorization': request.headers.get('Authorization', '')}
    with app.test_request_context('/api' + path, method=method, headers=headers, json=data):
        response = app.full_dispatch_request()
        result = response.get_json()
        if response.status_code >= 400:
            raise AssistantError((result or {}).get('mensaje', 'La operación no está disponible.'), response.status_code)
        return result


def records(session, resource):
    authorize(session, resource)
    result = native(RESOURCES[resource][1]).get(RESOURCES[resource][2], [])
    if resource == 'usuarios':
        fields = {'id_usuario', 'nombres', 'apellido_paterno', 'apellido_materno', 'perfiles',
                  'puestos_laborales', 'locales', 'estado_registro'}
        result = [{k: v for k, v in row.items() if k in fields} for row in result]
    return result


def normalized(value):
    return ''.join(c for c in unicodedata.normalize('NFD', value.lower()) if not unicodedata.combining(c))


def query(session, resource, search='', offset=0):
    if resource in inventory.RESOURCES:return inventory.read(session,resource,{'busqueda':search,'desde_registro':offset})
    if not isinstance(search, str) or len(search) > 200 or type(offset) is not int or offset < 0:
        raise AssistantError('Filtro de consulta inválido.')
    rows = records(session, resource)
    terms = normalized(search).split()
    rows = [r for r in rows if all(t in normalized(json.dumps(r, ensure_ascii=False)) for t in terms)]
    return {'recurso': resource, 'total': len(rows), 'desde': offset, 'registros': rows[offset:offset + 30],
            'hay_mas': len(rows) > offset + 30}


def current_record(session, resource, identity):
    if resource in inventory.RESOURCES:return inventory.current(session,resource,identity)
    return next((r for r in records(session, resource) if r[RESOURCES[resource][3]] == identity), None)


def editable(resource, row):
    result = {k: v for k, v in row.items() if k in FIELDS[resource].split()}
    if resource == 'presentaciones':
        result.update(nombre_item=row['item'], tipo_item=row['tipo'])
    if resource == 'recetas':
        result['componentes'] = [{'tipo_componente': c['tipo_componente'],
            'id': c['id_producto'] if c['tipo_componente'] == 'PRODUCTO' else c['id_subproducto'],
            'cantidad': c['cantidad']} for c in row['componentes']]
        g = row.get('grupo_salsa')
        result['grupo_salsa'] = None if not g else {
            'cantidad_maxima': g['cantidad_maxima'], 'permite_repetir': g['permite_repetir'],
            'opciones': [{'tipo_componente': 'PRODUCTO', 'id': o['id_producto'], 'cantidad': o['cantidad']} for o in g['opciones']]}
    if resource == 'subproductos':
        result['ingredientes'] = [{'tipo_componente': 'PRODUCTO', 'id': i['id_producto'], 'cantidad': i['cantidad']} for i in row['ingredientes']]
    if resource == 'promociones':
        result['grupos'] = [{**{k: g[k] for k in ('id_promocion_grupo', 'cantidad_elegir', 'permite_repetir')},
                             'opciones': [o['id_presentacion_venta'] for o in g['opciones']]} for g in row['grupos']]
        for k in ('hora_inicio', 'hora_fin'):
            if result.get(k): result[k] = result[k][:5]
    return result


def prepare(session, resource, action, identity, changes):
    if resource == 'ordenes_compra':return purchases.prepare(session,action,identity,changes)
    if resource in inventory.RESOURCES:return inventory.prepare(session,resource,action,identity,changes)
    if resource not in FIELDS or action not in ('crear', 'editar'):
        raise AssistantError('Esta acción no está habilitada en el asistente. Utiliza el módulo correspondiente.')
    authorize(session, resource, action)
    authorize(session, resource)
    if not isinstance(changes, dict) or not changes or set(changes) - set(FIELDS[resource].split()):
        raise AssistantError('Los campos propuestos no corresponden a esta operación.')
    previous = None
    if action == 'editar':
        if type(identity) is not int or identity <= 0:
            raise AssistantError('Selecciona un registro existente por su identificador.')
        previous = current_record(session, resource, identity)
        if previous is None:
            raise AssistantError('El registro no existe o no es accesible.', 404)
        if resource == 'presentaciones' and 'id_item_carta' in changes and changes['id_item_carta'] != previous['id_item_carta']:
            raise AssistantError('No se puede cambiar el artículo de una presentación existente.')
    elif identity is not None:
        raise AssistantError('Una creación no debe indicar un registro existente.')
    payload = {**(editable(resource, previous) if previous else {}), **changes}
    missing = REQUIRED[resource] - set(payload)
    if missing:
        raise AssistantError('Faltan datos: ' + ', '.join(sorted(missing)))
    # The service will validate values again. Never allow hidden extra fields.
    return {'recurso': resource, 'accion': action, 'id': identity, 'datos': payload, 'anterior': previous}


def execute(session, plan):
    if plan['recurso'] == 'ordenes_compra':
        authorize(session, 'ordenes_compra', 'crear')
        authorize(session, 'ordenes_compra')
        return native('/ordenes-compra', 'POST', plan['datos'])
    if plan['recurso'] in inventory.RESOURCES:return inventory.execute(session,plan)
    authorize(session, plan['recurso'], plan['accion'])
    resource, action, identity = plan['recurso'], plan['accion'], plan['id']
    path = RESOURCES[resource][1]
    if action == 'crear':
        return native(path, 'POST', plan['datos'])
    if resource in ('menajes', 'categorias_carta'):
        return native(f'{path}/{identity}/editar', 'POST', plan['datos'])
    return native(f'{path}/{identity}', 'PUT', plan['datos'])


def readable(session, plan):
    """Resolve references for the human review, independently of model prose."""
    if plan['recurso'] == 'ordenes_compra':
        authorize(session, 'ordenes_compra')
        return {'advertencia': plan['advertencia'], 'eventos_cercanos': plan.get('eventos_cercanos'),
                'productos': plan['revision_compra']}
    if plan['recurso'] in inventory.RESOURCES:return inventory.readable(session,plan)
    cache = {}
    references = {'id_categoria_carta': 'categorias_carta', 'id_menaje': 'menajes',
                  'id_presentacion_venta': 'presentaciones', 'id_categoria': 'categorias_productos',
                  'id_proveedor': 'proveedores'}

    def label(resource, identity):
        if identity is None: return 'Nuevo / sin asignar'
        if resource not in cache:
            cache[resource] = records(session, resource) if allowed(session, resource) else []
        row = next((r for r in cache[resource] if r[RESOURCES[resource][3]] == identity), None)
        if not row: return f'Registro {identity}'
        name = row.get('nombre', row.get('item', row.get('item_carta', 'Registro')))
        if resource == 'presentaciones':
            name += f" · {row['contenido']} {row['unidad']}"
        if resource in ('productos', 'subproductos'):
            name += f" · unidad {row['unidad']}"
        return f'{name} (#{identity})'

    def visit(value, key=''):
        if isinstance(value, list):
            if key == 'ids_categorias' and plan['recurso'] == 'proveedores':
                return [label('categorias_productos', v) for v in value]
            if key == 'opciones' and plan['recurso'] == 'promociones':
                return [label('presentaciones', v) for v in value]
            return [visit(v) for v in value]
        if isinstance(value, dict):
            result = {}
            for k, v in value.items():
                if k in references: result[k] = label(references[k], v)
                elif k == 'id' and 'tipo_componente' in value:
                    result['ingrediente'] = label('productos' if value['tipo_componente'] == 'PRODUCTO' else 'subproductos', v)
                else: result[k] = visit(v, k)
            return result
        return value
    return visit(plan['datos'])
