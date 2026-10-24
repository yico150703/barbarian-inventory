import re

from app.modules.asistente_ia import inventory, tools
from app.modules.asistente_ia.provider import AssistantError
from app.agents.catalog_specialists import SPECIALISTS

INVENTORY_HINTS = (
    'inventario', 'stock', 'existencia', 'existencias', 'conteo', 'conteos',
    'asignar puesto', 'asignacion', 'asignaciones', 'puesto', 'diferencia',
    'diferencias', 'jornada', 'jornadas', 'mix de ventas', 'ventas', 'vendido',
    'faltante', 'merma', 'revision de conteo', 'bajo minimo', 'minimo de stock',
)
CATALOG_HINTS = (
    'catalogo', 'promocion', 'promociones', 'promo', 'promos', 'receta',
    'recetas', 'carta', 'presentacion', 'presentaciones', 'proveedor',
    'proveedores', 'categoria', 'categorias', 'subproducto', 'menaje',
    'crear producto', 'crear un producto', 'crea producto', 'crea un producto',
    'agregar producto', 'agregar un producto', 'agrega producto', 'agrega un producto',
    'editar producto', 'editar un producto', 'modificar producto', 'modifica el producto',
    'producto de carta', 'precio de venta',
)
PURCHASE_HINTS = ('compra', 'pedido sugerido', 'festividad', 'festividades', 'sheraton', 'estadio nacional',
                  'eventos cercanos', 'conciertos cercanos', 'eventos cerca')

SPECIALIST_HINTS = {
    'categorias_carta': ('categoria de carta', 'categorias de carta', 'categoria carta', 'categorias carta'),
    'menajes': ('menaje', 'menajes'),
    'presentaciones': ('presentacion', 'presentaciones', 'precio de venta', 'articulo de carta', 'producto de carta'),
    'subproductos': ('subproducto', 'subproductos'),
    'recetas': ('receta', 'recetas'),
    'promociones': ('promocion', 'promociones', 'promo', 'promos'),
}


def catalog_route(instruction):
    value = tools.normalized(instruction)
    # El objeto de la acción prevalece sobre sus dependencias mencionadas.
    action = r'\b(?:crea|crear|agrega|agregar|edita|editar|modifica|modificar|actualiza|actualizar)\s+(?:(?:un|una|el|la|los|las|nuevo|nueva)\s+)*'
    for identity, hints in SPECIALIST_HINTS.items():
        for hint in hints:
            if re.search(action + re.escape(hint) + r'\b', value):
                return identity
    for identity in ('promociones', 'recetas', 'subproductos', 'presentaciones', 'menajes', 'categorias_carta'):
        if any(re.search(r'\b' + re.escape(hint) + r'\b', value) for hint in SPECIALIST_HINTS[identity]):
            return identity
    return None


def _score(value, hints):
    normalized = tools.normalized(value)
    return sum(normalized.count(tools.normalized(hint)) for hint in hints)


def route(instruction, previous=''):
    explicit = _score(instruction, CATALOG_HINTS) or _score(instruction, INVENTORY_HINTS) or _score(instruction, PURCHASE_HINTS) or re.search(r'\bpedidos?\b', tools.normalized(instruction))
    request = instruction if explicit else f'{instruction} {previous}'
    normalized = tools.normalized(request)
    # In management, an unspecified pedido refers to purchasing supplies.
    # Explicit table/service orders belong to the separate Salon workflow.
    if re.search(r'\bpedidos?\b', normalized) and re.search(r'\b(salon|mesa|comanda|mesero)\b', normalized):
        return 'salon'
    if _score(request, PURCHASE_HINTS) or re.search(r'\bpedidos?\b', normalized):
        return 'compras'
    inventory_score = _score(request, INVENTORY_HINTS)
    catalog_score = _score(request, CATALOG_HINTS)
    if inventory_score and catalog_score:
        return 'orquestador'
    if inventory_score > catalog_score:
        return 'inventario'
    return catalog_route(instruction) or ('carta_recetas' if explicit else catalog_route(previous) or 'carta_recetas')


def run(session, instruction, previous='', context=''):
    selected = route(instruction, previous)
    if selected == 'salon':
        return {'respuesta': 'Los pedidos de mesa se registran desde Salón. Si deseas comprar insumos, indica «hacer un pedido de compra».',
                'consultas': [], 'plan': None, 'agente': 'orquestador'}
    if selected == 'carta_recetas' and not _score(instruction, CATALOG_HINTS) and context and route(context) == 'compras':
        selected = 'compras'
    if selected == 'carta_recetas' and not _score(instruction, CATALOG_HINTS) and context:
        selected = catalog_route(context) or selected
    if selected == 'compras':
        from app.agents.compras.agent import run as specialist
        result = specialist(session, instruction, previous, context)
        result['agente'] = selected
        return result
    if selected == 'orquestador':
        return {'respuesta': 'El pedido combina inventario y catálogo. Indica cuál de esas tareas quieres preparar primero.',
                'consultas': [], 'plan': None, 'agente': selected}

    if selected in SPECIALISTS:
        specialist = SPECIALISTS[selected]
        if not tools.allowed(session, specialist.resource):
            raise AssistantError('Tu perfil no tiene acceso a ' + specialist.name + '.', 403)
        result = specialist.run(session, instruction, previous, context)
        result['agente'] = selected
        return result

    available_catalog = any(tools.allowed(session, resource) for resource in tools.RESOURCES
                            if resource not in inventory.RESOURCES)
    available_inventory = any(tools.allowed(session, resource) for resource in inventory.RESOURCES)
    if selected == 'inventario' and not available_inventory:
        raise AssistantError('Tu perfil no tiene acceso a las acciones de inventario del asistente.', 403)
    if selected == 'carta_recetas' and not available_catalog:
        if available_inventory:
            selected = 'inventario'
        else:
            raise AssistantError('Tu perfil no tiene acceso a los agentes del asistente.', 403)

    if selected == 'inventario':
        from app.agents.inventario.agent import run as specialist
    else:
        from app.agents.carta_recetas.agent import run as specialist
    result = specialist(session, instruction, previous, context)
    result['agente'] = selected
    return result
