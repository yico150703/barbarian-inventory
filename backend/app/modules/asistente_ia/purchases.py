"""Purchase proposals reuse native permissions, validation and confirmation."""
from decimal import Decimal, InvalidOperation, ROUND_CEILING
from .provider import AssistantError

RESOURCES = {
    'ordenes_compra': (22, '/ordenes-compra/formulario', 'productos', 'id_producto'),
    'pedido_sugerido': (22, '/ordenes-compra/pedido-sugerido', 'productos', 'id_producto'),
}


def allowed(session, resource, action):
    if action not in (('consultar', 'crear') if resource == 'ordenes_compra' else ('consultar',)):
        return False
    return any(m['id_opcion_menu'] == 22 and m.get('permisos', {}).get(action, False)
               for m in session['menu'])


def percentage(value):
    try:
        result = Decimal(str(value))
    except InvalidOperation:
        raise AssistantError('Porcentaje inválido.') from None
    if not result.is_finite() or not 0 <= result <= 1000:
        raise AssistantError('El porcentaje debe estar entre 0 y 1000.')
    return result


def prepare(session, action, identity, changes):
    from . import tools
    tools.authorize(session, 'ordenes_compra', 'crear')
    tools.authorize(session, 'ordenes_compra')
    if action != 'crear' or identity is not None:
        raise AssistantError('Solo se permite preparar una nueva orden.')
    if not isinstance(changes, dict) or set(changes) != {'porcentaje_general', 'adicionales'}:
        raise AssistantError('Indica porcentaje_general y adicionales por producto.')
    general = percentage(changes['porcentaje_general'])
    extras = changes['adicionales']
    if not isinstance(extras, list):
        raise AssistantError('Los adicionales deben ser una lista.')
    extra_by_id = {}
    for extra in extras:
        if not isinstance(extra, dict) or set(extra) != {'id_producto', 'porcentaje'}:
            raise AssistantError('Cada adicional requiere id_producto y porcentaje.')
        pid = extra['id_producto']
        if type(pid) is not int or pid <= 0 or pid in extra_by_id:
            raise AssistantError('Producto adicional inválido o repetido.')
        extra_by_id[pid] = percentage(extra['porcentaje'])
    rows = tools.records(session, 'pedido_sugerido')
    if set(extra_by_id) - {r['id_producto'] for r in rows}:
        raise AssistantError('Un adicional no tiene cantidad base sugerida. Revisa el pedido en Compras.')
    details, review = [], []
    for row in rows:
        base = Decimal(str(row['cantidad_sugerida']))
        pack = Decimal(str(row['presentacion']))
        if pack <= 0:
            raise AssistantError('Revisa la presentación del producto antes de comprar.')
        extra = extra_by_id.get(row['id_producto'], Decimal(0))
        adjusted = base * (1 + general / 100) * (1 + extra / 100)
        final = (adjusted / pack).to_integral_value(rounding=ROUND_CEILING) * pack
        details.append({'id_producto': row['id_producto'], 'cantidad_solicitada': float(final)})
        review.append({'producto': row['nombre'], 'unidad': row['unidad'], 'base_sugerida': float(base),
                       'porcentaje_general': float(general), 'porcentaje_adicional': float(extra),
                       'antes_de_redondear': float(adjusted), 'cantidad_final': float(final),
                       'presentacion_compra': float(pack)})
    if not details:
        raise AssistantError('No hay productos con necesidad de compra sugerida.')
    return {'recurso': 'ordenes_compra', 'accion': 'crear', 'id': None, 'anterior': None,
            'datos': {'accion': 'GUARDAR_BORRADOR', 'detalles': details},
            'revision_compra': review,
            'advertencia': 'La base ya incluye margen de consumo del 20% menos stock. '
                           'Los aumentos se aplican sobre esa sugerencia y se redondean hacia arriba a presentaciones completas. '
                           'Se guardará como BORRADOR al pulsar Realizar.'}
