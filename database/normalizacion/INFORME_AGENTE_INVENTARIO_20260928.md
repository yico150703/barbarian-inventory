# Agente de inventario integrado en Barbarito

## Uso

Entrar en Gestión, seleccionar el perfil Gerente y el local, y abrir **Asistente IA**.
Es el mismo chat y dictado existente, con herramientas de inventario. No requiere otra clave,
otro proveedor ni un proceso independiente. Reiniciar el backend y recargar el frontend.
No necesita SQL adicional si ya están aplicadas las migraciones del asistente, jornadas y
asignación por puestos. No se modificaron registros operativos reales durante esta ampliación.

Ejemplos de consultas:
- «Muéstrame los productos bajo el mínimo».
- «¿Cómo va el conteo abierto y qué puestos faltan por entregar?».
- «Muéstrame lo contado, lo que indica el sistema y las diferencias del último conteo».
- «¿Qué productos no tienen puesto asignado?».
- «Muéstrame las ventas del 26 al 28 de septiembre de 2026, separadas entre las horas 1 y 2».
- «Explícame las entradas y salidas de la jornada del 26 de septiembre».

Ejemplos de propuestas, que no se ejecutan hasta pulsar **Realizar**:
- Gerente: «Abre un conteo llamado Conteo de barra».
- Gerente: «Asigna estos productos a Bartender para los próximos conteos».
- Gerente/supervisor: «Guarda y cierra esta revisión aceptando las cantidades entregadas».
- Gerente/supervisor: «Antes de guardar y cerrar, corrige el contado de [producto] a [cantidad]».

La vista previa identifica el local, los productos y el alcance de la operación. Se puede corregir
mediante texto o dictado y preparar de nuevo. Cerrar revisión significa cerrar la ronda completa;
no equivale a guardar una sola fila. No permite cerrar si faltan entregas. Conserva lo contado
originalmente, sus autores y el historial. Las observaciones son opcionales.

## Permisos y exactitud

- Todas las herramientas despachan a las rutas nativas con la sesión actual. El modelo no recibe
  SQL ejecutable ni decide el local. Miembros ven solo sus conteos por puesto activo; no acceden
  al teórico ni a las diferencias de revisión. Gerente y supervisor conservan sus permisos reales.
- Abrir conteos y configurar asignaciones siguen siendo exclusivos del gerente. El administrador
  global no obtiene acceso operativo por usar el asistente.
- Borradores ligados a usuario, perfil y local; se revalidan permisos y datos al confirmar.
  Se bloquean propuestas desactualizadas. Repetir una confirmación exitosa devuelve su resultado.
- La diferencia es cantidad revisada (o contada) menos teórico. El teórico de una ronda es una
  fotografía al abrirla. Las ventas ya descuentan inventario al cobrar; el agente no vuelve a
  descontarlas. Si los períodos no coinciden, no debe presentar una conciliación exacta.
- Puede consultar jornadas y ventas para explicar movimientos; no inventa causas de faltantes,
  justificaciones ni cantidades. No ajusta stock ni cierra jornadas de venta.
- Las asignaciones masivas afectan próximos conteos; no cambian las rondas ya abiertas.
- Consultas paginadas de 30 registros; el modelo tiene un máximo de siete iteraciones. Para
  solicitudes extensas puede ser necesario dividir por categoría o producto.

## Archivos principales

- `backend/app/modules/asistente_ia/inventory.py`: adaptadores y validación de inventario.
- `backend/app/modules/asistente_ia/skills/inventario/SKILL.md`: instrucciones especializadas.
- `agent.py`, `tools.py`, `routes.py`: integración con el ciclo y los borradores existentes.
- `frontend/src/features/asistenteIA/`: capacidades, sugerencias y contexto de consultas.
- `backend/tests/test_inventory_assistant.py`: integración sobre PostgreSQL temporal.

Se conserva Responses API y las herramientas de función existentes, según la
[documentación oficial de function calling](https://developers.openai.com/api/docs/guides/function-calling).
La clave sigue exclusivamente en el backend. El dictado usa el transcriptor ya configurado.

## Validación

Resultado: 149 pruebas aprobadas entre las cuatro etapas de PostgreSQL temporal (incluidas
8 nuevas del agente), 3 unitarias de estado/autenticación, TypeScript, lint del módulo y
compilación de producción aprobados. Vite conserva la advertencia de tamaño del paquete
principal, superior a 500 kB; no impide compilar.

Las pruebas de integración simulan las respuestas del modelo y usan las rutas y la base de datos
reales en una instancia temporal. Verifican confirmación, permisos, local, asignaciones, conflictos,
conservación del original y ausencia de descuentos de stock. No prueban la interpretación de voz
ni la calidad de respuestas de un modelo en vivo; estas requieren comprobar el flujo en el navegador.
