from pathlib import Path

from app.agents.carta_recetas import agent as catalog_agent
from app.agents.inventario import agent as inventory_agent
from app.agents.compras import agent as purchase_agent
from app.agents.orchestrator.router import CATALOG_HINTS, INVENTORY_HINTS, SPECIALIST_HINTS
from app.agents.catalog_specialists import SPECIALISTS


def _skills(paths, labels):
    return [
        {'nombre': label, 'archivo': Path(path).parent.name + '/' + Path(path).name,
         'contenido': Path(path).read_text(encoding='utf-8')}
        for path, label in zip(paths, labels)
    ]


def catalog():
    return {
        'coordinador': {
            'id': 'orquestador',
            'nombre': 'Coordinador',
            'descripcion': 'Selecciona especialistas, delega requisitos faltantes y retoma la tarea original con resultados confirmados. Cada cambio requiere confirmación humana.',
            'relaciones': ['carta_recetas', 'inventario', 'compras', *SPECIALISTS],
            'skills': [],
            'reglas_ruta': {
                'inventario': list(INVENTORY_HINTS),
                'carta_recetas': list(CATALOG_HINTS),
                **{key: list(value) for key, value in SPECIALIST_HINTS.items()},
            },
        },
        'agentes': [
            {
                'id': 'compras', 'nombre': 'Compras y eventos cercanos',
                'descripcion': 'Revisa eventos de los próximos siete días y prepara una compra con los aumentos indicados por el usuario.',
                'relaciones': ['orquestador'],
                'herramientas': ['consultar', 'formulario', 'preparar_cambio', 'web_search'],
                'recursos': ['ordenes_compra', 'pedido_sugerido', 'presentaciones', 'recetas', 'subproductos'],
                'instrucciones': purchase_agent.INSTRUCTIONS,
                'skills': _skills(purchase_agent.SKILLS, ['Compras y eventos por restaurante']),
            },
            {
                'id': 'carta_recetas',
                'nombre': 'Catálogo de insumos',
                'descripcion': 'Gestiona categorías de productos, proveedores y productos con los permisos del perfil.',
                'relaciones': ['orquestador'],
                'herramientas': ['consultar', 'abrir_formulario', 'preparar_cambio'],
                'recursos': list(catalog_agent.RESOURCES),
                'instrucciones': catalog_agent.INSTRUCTIONS,
                'skills': _skills(catalog_agent.SKILLS, ['Operaciones de catálogo', 'Crear categoría de productos',
                                                       'Crear proveedor', 'Crear producto']),
            },
            *[{
                'id': specialist.identity, 'nombre': specialist.name,
                'descripcion': specialist.description, 'relaciones': ['orquestador'],
                'herramientas': ['consultar', 'preparar_cambio'] +
                                (['solicitar_especialista'] if specialist.dependencies else []) +
                                (['abrir_formulario'] if specialist.resource in ('categorias_carta', 'menajes', 'presentaciones') else []) +
                                (['formulario'] if specialist.resource in ('presentaciones', 'subproductos', 'recetas', 'promociones') else []),
                'recursos': list(specialist.resources),
                'recursos_modificables': [specialist.resource],
                'recursos_solo_consulta': list(specialist.dependencies),
                'instrucciones': specialist.instructions,
                'skills': _skills(specialist.skills, [specialist.name]),
            } for specialist in SPECIALISTS.values()],
            {
                'id': 'inventario',
                'nombre': 'Inventario',
                'descripcion': 'Consulta stock, conteos, asignaciones, revisiones, jornadas y ventas; prepara las operaciones habilitadas para el perfil.',
                'relaciones': ['orquestador'],
                'herramientas': ['consultar_inventario', 'preparar_cambio'],
                'recursos': list(inventory_agent.RESOURCES),
                'instrucciones': inventory_agent.INSTRUCTIONS,
                'skills': _skills(inventory_agent.SKILLS, ['Operaciones de inventario']),
            },
        ],
        'limite_salon': 'Los pedidos de Salón no están conectados al asistente: usan sesión y autorización PIN separadas.',
        'regla_ejecucion': 'Los agentes solo preparan borradores. El backend revalida perfil y local; una persona debe confirmar para ejecutar.',
    }
