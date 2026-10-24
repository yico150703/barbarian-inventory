# Asignación permanente de conteos por puesto

## Activación

Ejecutar manualmente `database/migrations/20260928_asignacion_conteos_puestos.sql` una sola vez en `barbarito`, después de `20260926_jornadas_conteos.sql`. Reiniciar el backend y volver a iniciar sesión para cargar los permisos. No se ejecutó esta migración en la base real durante el desarrollo.

## Uso

Con perfil Gerente, seleccionar el local y entrar a **Inventario → Real vs. teórico → Asignación por puesto**. Esta pestaña funciona antes de iniciar cualquier ronda.

Pulsar **Asignar varios productos**. La ventana emergente permite buscar por nombre/código, filtrar categorías y asignación actual, marcar productos individuales o todos los filtrados y elegir Cocina, Bartender o Mesero. La selección se conserva al cambiar filtros. Guardar reemplaza el puesto de los productos seleccionados; también existe Quitar asignación. Un producto tiene un único puesto responsable por local para evitar duplicar el conteo. Las categorías son filtros: productos creados posteriormente quedan sin asignar hasta seleccionarlos.

La configuración se guarda para próximos conteos; no cambia automáticamente las rondas abiertas ni las cerradas. Un gerente puede corregir puntualmente el puesto de un producto pendiente en una ronda, sin cambiar la plantilla permanente.

## Conteo compartido y trazabilidad

- Los nuevos conteos copian los puestos configurados y el saldo teórico del inicio. Los productos sin asignar permanecen visibles al gerente para detectar omisiones.
- Solo el gerente puede abrir una ronda mediante «Abrir conteo para el equipo». Miembros y supervisor no pueden crearla, incluso si un permiso anterior de creación permanece en la base. Solo hay una ronda abierta por local; el equipo trabaja en esa misma ronda, con su propia lista por puesto. Después de que el gerente la abra, los miembros pulsan Actualizar para verla. Este cambio de flujo no requiere SQL adicional.
- El miembro accede a los productos de su puesto activo, validado en la base en cada petición. Cambiar o revocar ese puesto cambia el acceso; conocer un ID de producto no permite contar otro puesto ni otro local.
- Cualquier miembro del mismo puesto puede registrar un avance sobre el mismo producto. Cada guardado reemplaza la cantidad total, no la suma. El historial conserva el usuario, perfil, puesto y hora de cada registro.
- La versión del producto evita que una pantalla desactualizada sobrescriba un cambio de otro usuario. Debe actualizar y revisar antes de reintentar.
- Un producto marcado Hecho ya no se sobrescribe como conteo original: gerente/supervisor lo revisa y corrige con observación. Los valores originales e historial se conservan.
- La tabla muestra quién contó, con qué perfil/puesto y cuándo. La exportación CSV filtrada incluye esos datos.
- Las rondas creadas antes de esta migración conservan sus asignaciones por persona. No se infiere un puesto de esos usuarios ni se reescribe su historial.
- Guardar asignaciones, contar o revisar no modifica el inventario teórico.

## Archivos y verificaciones

- Backend: `backend/app/modules/inventarios/operativo.py`.
- Interfaz: `frontend/src/features/inventoryOperations/AssignmentsPanel.tsx`, `assignments.css`, `CountsPanel.tsx`.
- Pruebas PostgreSQL temporal: `backend/tests/test_count_positions.py`, integradas al runner `backend/tests/run_local_scope_integration.py`.
- Validación de frontend: TypeScript, lint y compilación de producción. La compilación conserva la advertencia de tamaño de bundle existente.
- Las pruebas usan esquema y datos sintéticos en PostgreSQL temporal; no modifican datos reales. La comprobación visual en el navegador queda pendiente de activar la migración.
- Resultado final: 125 pruebas previas, 8 de inventario operativo y 6 de asignación por puestos aprobadas (139 en total, ejecutadas por etapas de migración). Cubren selección múltiple atómica, permisos, aislamiento por local, copia de plantilla, compatibilidad de rondas anteriores, inicio por miembro, revocación de puesto, conflictos de versión, trazabilidad y bloqueo de conteos entregados.
