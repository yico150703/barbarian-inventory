import json
from pathlib import Path

from app.core.extensions import db
from app.modules.asistente_ia import inventory, provider, tools
from app.modules.asistente_ia.provider import AssistantError


def function(name, description, properties):
    return {'type': 'function', 'name': name, 'description': description, 'strict': True,
            'parameters': {'type': 'object', 'properties': properties,
                           'required': list(properties), 'additionalProperties': False}}


def run_specialist(session, instruction, previous, context, resources, instructions,
                   skills=(), inventory_specialist=False, writable_resources=None, dependencies=()):
    capabilities = {resource: [action for action in ('consultar', 'crear', 'editar')
                               if tools.allowed(session, resource, action)
                               and (action == 'consultar' or writable_resources is None or resource in writable_resources)]
                    for resource in resources if tools.allowed(session, resource)}
    if not capabilities:
        raise AssistantError('Tu perfil no tiene acceso a los módulos de este agente.', 403)

    enum = {'type': 'string', 'enum': list(capabilities)}
    definitions = []
    delegates = [r for r in dependencies if tools.allowed(session, r) and tools.allowed(session, r, 'crear')]
    if delegates:
        definitions.append(function('solicitar_especialista',
            'Pedir al Coordinador crear un requisito faltante con su especialista. Antes consulta si existe; '
            'si hay ambigüedad pregunta. Conserva la tarea original y espera confirmación humana. No inventes datos.', {
                'recurso': {'type': 'string', 'enum': delegates},
                'instruccion': {'type': 'string'},
                'motivo': {'type': 'string'}}))
    if inventory_specialist:
        inventory_resources = [resource for resource in capabilities if resource in inventory.RESOURCES]
        definitions.append(function('consultar_inventario',
            'Consultar inventario del local activo con filtros, detalle de conteo y reportes.', {
                'recurso': {'type': 'string', 'enum': inventory_resources},
                'filtros_json': {'type': 'string'}}))
    else:
        definitions.append(function('consultar', 'Buscar registros reales; 30 por página.', {
            'recurso': enum, 'busqueda': {'type': 'string'}, 'desde': {'type': 'integer'}}))
        direct_forms = [r for r in ('categorias_productos', 'proveedores', 'productos', 'categorias_carta', 'menajes', 'presentaciones')
                        if 'crear' in capabilities.get(r, [])]
        if direct_forms:
            definitions.append(function('abrir_formulario',
                'Mostrar un formulario interactivo para crear catálogos o presentaciones, con pasos para sus requisitos. No inventar datos.',
                {'recurso': {'type': 'string', 'enum': direct_forms}}))
        form_resources = [resource for resource in
                          ('presentaciones', 'recetas', 'subproductos', 'promociones')
                          if resource in capabilities]
        if form_resources:
            definitions.append(function('formulario',
                'Opciones válidas para crear presentaciones, recetas, subproductos o promociones.', {
                    'recurso': {'type': 'string', 'enum': form_resources}}))

    writable = [r for r, actions in capabilities.items() if 'crear' in actions or 'editar' in actions]
    if writable:
        definitions.append(function('preparar_cambio',
            'Preparar, sin ejecutar, un único cambio para revisión humana.', {
                'recurso': {'type': 'string', 'enum': writable}, 'accion': {'type': 'string', 'enum': ['crear', 'editar']},
                'id': {'type': ['integer', 'null']}, 'datos_json': {'type': 'string'}}))

    skill_text = '\n'.join(Path(path).read_text(encoding='utf-8') for path in skills)
    if inventory_specialist:
        from datetime import datetime, timedelta, timezone
        skill_text += '\nFecha actual en Lima: ' + datetime.now(timezone(timedelta(hours=-5))).date().isoformat()
        skill_text += '\nLocal activo: ' + json.dumps(session.get('local_activo'), ensure_ascii=False)

    messages = [
        {'role': 'system', 'content': instructions + '\n' + skill_text +
         '\nSi falta un requisito y el usuario desea crearlo, usa solicitar_especialista. '
         'El Coordinador conserva tu tarea y te devuelve el resultado confirmado para continuar. '
         'No delegues recursos existentes ni supongas que un traspaso ya creó registros.' +
         '\nCapacidades de este agente: ' + json.dumps(capabilities, ensure_ascii=False)},
        {'role': 'user', 'content': json.dumps({
            'contexto_previo': context, 'borrador_previo': previous, 'instruccion': instruction,
        }, ensure_ascii=False)},
    ]
    consulted = []
    for _ in range(7):
        db.session.rollback()
        output = provider.respond(messages, definitions)
        messages.extend(output)
        calls = [item for item in output if item.get('type') == 'function_call']
        if not calls:
            answer = '\n'.join(c.get('text', '') for item in output
                               for c in item.get('content', []) if c.get('type') == 'output_text')
            return {'respuesta': answer or 'No se pudo interpretar el pedido. Prueba con una instrucción más concreta.',
                    'consultas': consulted, 'plan': None}
        for item in calls:
            try:
                args = json.loads(item['arguments'])
                if not isinstance(args, dict):
                    raise ValueError()
                if item['name'] == 'solicitar_especialista':
                    if args['recurso'] not in delegates:
                        raise AssistantError('Traspaso no permitido para este agente.', 403)
                    if not all(isinstance(args.get(k), str) and 1 <= len(args[k].strip()) <= 4000
                               for k in ('instruccion', 'motivo')):
                        raise AssistantError('Indica la tarea y el motivo del traspaso.')
                    return {'respuesta': args['motivo'], 'consultas': consulted, 'plan': None,
                            'traspaso': args}
                elif item['name'] == 'abrir_formulario' and not inventory_specialist:
                    from app.modules.asistente_ia import forms
                    if args['recurso'] not in direct_forms:
                        raise AssistantError('Formulario no permitido.', 403)
                    return {'respuesta': 'Completa el formulario para revisar la propuesta.',
                            'formulario': forms.open_form(session, args['recurso']),
                            'consultas': consulted, 'plan': None}
                elif item['name'] == 'consultar' and not inventory_specialist:
                    if args['recurso'] not in capabilities:
                        raise AssistantError('Recurso no permitido para este agente.', 403)
                    result = tools.query(session, args['recurso'], args['busqueda'], args['desde'])
                    consulted.append(result)
                elif item['name'] == 'consultar_inventario' and inventory_specialist:
                    if args['recurso'] not in capabilities:
                        raise AssistantError('Recurso de inventario no permitido.', 403)
                    result = inventory.read(session, args['recurso'], json.loads(args['filtros_json']))
                    consulted.append(result)
                elif item['name'] == 'formulario' and not inventory_specialist:
                    resource = args['recurso']
                    tools.authorize(session, resource)
                    if resource not in form_resources:
                        raise AssistantError('Consulta los catálogos correspondientes para obtener las opciones.')
                    result = tools.native(tools.RESOURCES[resource][1] + '/formulario')
                elif item['name'] == 'preparar_cambio':
                    if args['accion'] not in ('crear', 'editar') or args['accion'] not in capabilities.get(args['recurso'], []):
                        raise AssistantError('Recurso no permitido para este agente.', 403)
                    plan = tools.prepare(session, args['recurso'], args['accion'], args['id'],
                                         json.loads(args['datos_json']))
                    return {'respuesta': 'Revisa los datos de la propuesta antes de realizarla.',
                            'consultas': consulted, 'plan': plan}
                else:
                    raise AssistantError('Herramienta no disponible para este agente.', 403)
            except AssistantError as error:
                result = {'error': str(error)}
            except (KeyError, ValueError, TypeError):
                result = {'error': 'Argumentos inválidos. Corrige los datos o pregunta al usuario.'}
            messages.append({'type': 'function_call_output', 'call_id': item['call_id'],
                             'output': json.dumps(result, ensure_ascii=False, default=str)})
    raise AssistantError('La consulta requiere demasiados pasos. Indica un artículo o tarea más concreta.', 422)
