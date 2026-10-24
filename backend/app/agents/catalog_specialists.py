"""Especialistas independientes con dependencias de solo lectura."""
from dataclasses import dataclass
from pathlib import Path

from app.agents.runtime import run_specialist
from app.modules.asistente_ia.agent import INSTRUCTIONS


@dataclass(frozen=True)
class Specialist:
    identity: str
    name: str
    resource: str
    dependencies: tuple[str, ...]
    description: str

    @property
    def resources(self):
        return (self.resource, *self.dependencies)

    @property
    def skills(self):
        return (Path(__file__).parents[1] / 'modules' / 'asistente_ia' / 'skills' / self.identity / 'SKILL.md',)

    @property
    def instructions(self):
        return INSTRUCTIONS + f'\nEres el especialista de {self.name}. Solo preparas cambios de {self.resource}. ' + (
            'Los demás recursos son exclusivamente de consulta para comprobar requisitos. '
            'Si falta un requisito y el usuario desea crearlo, usa solicitar_especialista para delegarlo al Coordinador. Nunca crees dependencias '
            'ni prepares cambios en otro módulo. No inventes datos ni equivalencias. '
            'Los campos faltantes se solicitan al usuario; Realizar confirma cada cambio.')

    def run(self, session, instruction, previous='', context=''):
        return run_specialist(session, instruction, previous, context, self.resources,
                              self.instructions, self.skills, writable_resources=(self.resource,),
                              dependencies=self.dependencies)


SPECIALISTS = {agent.identity: agent for agent in (
    Specialist('categorias_carta', 'Categorías de carta', 'categorias_carta', (),
               'Crea y edita las categorías que agrupan los artículos de la carta.'),
    Specialist('menajes', 'Menajes', 'menajes', (),
               'Crea y edita platos, vasos, copas y otros menajes para servir.'),
    Specialist('presentaciones', 'Presentaciones de venta', 'presentaciones', ('categorias_carta', 'menajes'),
               'Define artículo, contenido, unidad, precio, categoría y menaje; verifica que existan sus requisitos.'),
    Specialist('subproductos', 'Subproductos', 'subproductos', ('productos',),
               'Define preparaciones internas con productos, cantidades, rendimiento e instrucciones.'),
    Specialist('recetas', 'Recetas', 'recetas', ('presentaciones', 'productos', 'subproductos'),
               'Asocia ingredientes y cantidades a una presentación de venta existente.'),
    Specialist('promociones', 'Promociones', 'promociones', ('presentaciones',),
               'Crea y edita promociones con precio, horario y grupos de presentaciones existentes.'),
)}
