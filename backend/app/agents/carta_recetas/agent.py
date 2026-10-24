from pathlib import Path

from app.agents.runtime import run_specialist
from app.modules.asistente_ia.agent import INSTRUCTIONS

RESOURCES = ('productos', 'categorias_productos', 'proveedores', 'usuarios')
SKILLS = tuple(Path(__file__).parents[2] / 'modules' / 'asistente_ia' / 'skills' / name / 'SKILL.md'
               for name in ('operaciones_catalogo', 'crear_categoria_producto', 'crear_proveedor', 'crear_producto'))


def run(session, instruction, previous='', context=''):
    instructions = INSTRUCTIONS + '\nPara crear categorías de productos, proveedores o productos, usa abrir_formulario para recoger datos del usuario. No hagas un cuestionario de texto si puedes abrir el formulario.'
    return run_specialist(session, instruction, previous, context, RESOURCES, instructions, SKILLS)
