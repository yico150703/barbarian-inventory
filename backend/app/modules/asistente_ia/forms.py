"""Formularios del catálogo: opciones reales y propuestas sin llamadas al modelo."""
import re
from decimal import Decimal, InvalidOperation

from . import tools
from .provider import AssistantError

TITLES = {'categorias_productos': 'Crear categoría de productos',
          'proveedores': 'Crear proveedor', 'productos': 'Crear producto',
          'categorias_carta': 'Crear categoría de carta', 'menajes': 'Crear menaje',
          'presentaciones': 'Crear presentación de venta'}
CATEGORY_QUESTION = '¿Quieres crear una categoría de productos o una categoría de carta?'


def detect(instruction):
    value = tools.normalized(instruction)
    if not re.search(r'\b(crea|crear|hacer|agrega|agregar|registra|registrar|nuevo|nueva|anade|anadir)\b', value):
        return None
    if re.search(r'\b(edita|editar|elimina|eliminar|desactiva|desactivar|receta|promocion)\b', value):
        return None
    action = r'\b(?:crea|crear|hacer|agrega|agregar|registra|registrar|anade|anadir)\s+(?:(?:un|una|nuevo|nueva)\s+)*'
    if re.search(action + r'categorias?\b', value) or re.search(r'\bnueva\s+categorias?\b', value):
        qualifier = r'\bcategorias?\s+(?:(?:de|del|para|el|la)\s+)*'
        product = bool(re.search(qualifier + r'(?:productos?|inventario|insumos)\b', value))
        menu = bool(re.search(qualifier + r'(?:carta|menu)\b', value))
        if product == menu:
            return 'categoria_ambigua'
        return 'categorias_productos' if product else 'categorias_carta'
    for resource, entity in (('categorias_carta', r'categorias? (?:de )?carta'),
                             ('presentaciones', r'presentaci(?:on|ones)'), ('menajes', r'menajes?'),
                             ('categorias_productos', r'categorias?'), ('proveedores', r'proveedor(?:es)?'), ('productos', r'productos?')):
        if re.search(action + entity + r'\b', value) or re.search(r'\b(?:nuevo|nueva)\s+' + entity + r'\b', value):
            return resource
    return None


def category_choice(instruction, previous):
    question = tools.normalized(previous)
    # The model can phrase the same clarification differently. Only resolve a
    # short answer when the preceding response actually asks about both types.
    pending = tools.normalized(CATEGORY_QUESTION) in question or (
        len(question) <= 1200 and '?' in question
        and re.search(r'\bcategorias?\b', question)
        and re.search(r'\b(productos?|inventario|insumos)\b', question)
        and re.search(r'\b(carta|menu)\b', question))
    if not pending:
        return None
    value = tools.normalized(instruction).strip(' .!?¿¡')
    value = re.sub(r'^si,\s*', '', value)
    choice = re.fullmatch(
        r'(?:(?:si|es|son|seria|sera|quiero|de|del|el|la|los|las|un|una|para|categorias?|articulos?)\s+)*'
        r'(productos?|inventario|insumos|carta|menu)'
        r'(?:\s+de(?:l| la)?\s+(inventario|carta|menu))?', value)
    if not choice:
        return None
    return 'categorias_carta' if (choice[2] or choice[1]) in ('carta', 'menu') else 'categorias_productos'


def open_form(session, resource):
    if not isinstance(resource, str) or resource not in TITLES:
        raise AssistantError('Este formulario no está disponible.', 400)
    tools.authorize(session, resource, 'crear')
    tools.authorize(session, resource)
    result = tools.native(tools.RESOURCES[resource][1] + ('/formulario' if resource == 'presentaciones' else ''))
    categories = result.get('categorias', [])
    if resource in ('categorias_carta', 'presentaciones'):
        categories = [{**c, 'id_categoria': c['id_categoria_carta']} for c in categories]
    return {'recurso': resource, 'titulo': TITLES[resource],
            'categorias': categories,
            'proveedores': result.get('proveedores', []),
            'unidades_medida': result.get('unidades_medida', []),
            'menajes': result.get('menajes', []), 'items': result.get('items', []),
            'tipos': result.get('tipos', []),
            'dependencias_creables': [r for r in {
                'productos': ('categorias_productos', 'proveedores'),
                'proveedores': ('categorias_productos',),
                'presentaciones': ('categorias_carta', 'menajes'),
            }.get(resource, ()) if tools.allowed(session, r, 'crear') and tools.allowed(session, r)],
            'categorias_proveedor_configurables': result.get('categorias_proveedor_configurables', True)}


def prepare(session, resource, data):
    form = open_form(session, resource)
    fields = {'categorias_productos': {'nombre', 'prefijo'},
              'proveedores': {'nombre', 'ids_categorias'},
              'productos': {'nombre', 'id_categoria', 'id_proveedor', 'unidad', 'presentacion'},
              'categorias_carta': {'nombre', 'prefijo'}, 'menajes': {'nombre'},
              'presentaciones': {'id_item_carta', 'nombre_item', 'tipo_item', 'id_categoria_carta',
                                'contenido', 'unidad', 'id_menaje', 'precio', 'activo'}}[resource]
    if not isinstance(data, dict) or set(data) != fields:
        raise AssistantError('Completa los campos del formulario, sin datos adicionales.')
    data = dict(data)
    if resource == 'presentaciones':
        validate_presentation(form, data)
        return tools.prepare(session, resource, 'crear', None, data)
    if not isinstance(data['nombre'], str) or not 1 <= len(data['nombre'].strip()) <= 100:
        raise AssistantError('Indica un nombre de hasta 100 caracteres.')
    data['nombre'] = data['nombre'].strip()
    categories = {r['id_categoria']: r for r in form['categorias'] if r.get('activo')}
    if resource in ('categorias_productos', 'categorias_carta'):
        prefix = data['prefijo']
        maximum = 5 if resource == 'categorias_carta' else 3
        if not isinstance(prefix, str) or not prefix.isalpha() or not 1 <= len(prefix) <= maximum or (resource == 'categorias_carta' and not re.fullmatch('[A-Za-z]{1,5}', prefix)):
            raise AssistantError(f'El prefijo debe tener entre una y {maximum} letras.')
        data['prefijo'] = prefix.upper()
        if any(tools.normalized(r['nombre']) == tools.normalized(data['nombre']) or
               r['prefijo'].upper() == data['prefijo'] for r in form['categorias']):
            raise AssistantError('El nombre o prefijo ya está registrado.', 409)
    elif resource == 'proveedores':
        ids = data['ids_categorias']
        if not isinstance(ids, list) or not ids or any(type(i) is not int or i not in categories for i in ids) or len(ids) != len(set(ids)):
            raise AssistantError('Selecciona una o varias categorías activas, sin repetirlas.')
        if any(tools.normalized(r['nombre']) == tools.normalized(data['nombre']) for r in form['proveedores']):
            raise AssistantError('Ya existe un proveedor con ese nombre.', 409)
    elif resource == 'productos':
        from app.modules.catalogos.service import _datos_producto
        if (type(data['id_categoria']) is not int or type(data['id_proveedor']) is not int
                or data['id_categoria'] not in categories or _datos_producto(data) is None):
            raise AssistantError('Revisa categoría, proveedor, unidad y contenido de compra.')
        supplier = next((p for p in form['proveedores'] if p['id_proveedor'] == data['id_proveedor'] and p.get('activo')), None)
        if not supplier or data['id_categoria'] not in supplier.get('ids_categorias', []):
            raise AssistantError('Selecciona una categoría activa asignada a ese proveedor.')
    elif resource == 'menajes':
        if any(tools.normalized(r['nombre']) == tools.normalized(data['nombre']) for r in form['menajes']):
            raise AssistantError('Ya existe un menaje con ese nombre.', 409)
    return tools.prepare(session, resource, 'crear', None, data)


def validate_presentation(form, data):
    from app.core.units import normalizar_medida
    name = data['nombre_item']
    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 200:
        raise AssistantError('Indica el nombre del artículo (hasta 200 caracteres).')
    data['nombre_item'] = name.strip()
    if data['tipo_item'] not in form['tipos'] or type(data['activo']) is not bool:
        raise AssistantError('Selecciona tipo y estado válidos.')
    for field, rows, pk in (('id_categoria_carta', form['categorias'], 'id_categoria'), ('id_menaje', form['menajes'], 'id_menaje')):
        if type(data[field]) is not int or not any(r[pk] == data[field] and r.get('activo') for r in rows):
            raise AssistantError('Selecciona categoría de carta y menaje activos.')
    try:
        amount, _ = normalizar_medida(data['contenido'], data['unidad'], 'presentacion')
        price = Decimal(str(data['precio']))
        if amount <= 0 or amount > Decimal('999999999.999') or amount != amount.quantize(Decimal('.001')) or not price.is_finite() or price < 0 or price > Decimal('99999999.99') or price != price.quantize(Decimal('.01')):
            raise ValueError()
    except (ValueError, InvalidOperation, TypeError):
        raise AssistantError('Revisa contenido, unidad y precio de venta.') from None
    item_id = data['id_item_carta']
    if item_id is not None:
        item = next((i for i in form['items'] if type(item_id) is int and i['id_item_carta'] == item_id and i.get('activo')), None)
        if not item or (item['nombre'], item['tipo'], item['id_categoria_carta']) != (data['nombre_item'], data['tipo_item'], data['id_categoria_carta']):
            raise AssistantError('Conserva nombre, tipo y categoría del artículo existente.')
