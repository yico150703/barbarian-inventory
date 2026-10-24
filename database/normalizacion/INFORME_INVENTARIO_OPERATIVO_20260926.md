# Inventario operativo, jornadas y conteos físicos

## Activación

1. Tener aplicadas las migraciones anteriores, incluida `database/migrations/20260926_pagos_salon.sql` y la activación de operaciones por local (03).
2. Ejecutar **una sola vez** `database/migrations/20260926_jornadas_conteos.sql`, completo, como propietario, en `barbarito`.
3. Reiniciar el backend y volver a iniciar sesión en la aplicación para renovar el menú y los permisos.

La migración **no se ha ejecutado en la base real**. Se verificó en PostgreSQL temporal con esquema del proyecto y registros ficticios. Conviene activarla entre operaciones: bloquea temporalmente las tablas fuente mientras captura el saldo inicial; si no consigue el bloqueo en diez segundos, revierte en lugar de capturar un saldo inconsistente. No elimina conteos ni comprobantes históricos.

## Nuevo menú

- **Stock actual:** existencias teóricas, mínimos y máximos por local.
- **Mínimos y máximos:** conserva la configuración existente del gerente.
- **Cerrar día:** jornada activa y consulta de jornadas cerradas; pestañas de inventario/motivos y productos vendidos.
- **Mix de ventas:** fechas operativas, horas de cobro, totalización, separación por hora y ranking de productos.
- **Real vs. teórico:** rondas solicitadas por el gerente, asignación, avance, entrega, revisión y justificación de diferencias.

Los antiguos accesos Realizar inventario/Revisar inventarios se retiran. Sus rutas web redirigen a los conteos nuevos. El backend bloquea escrituras del inventario antiguo después de activar la migración. Inicio ya no depende del antiguo resumen de cierres.

## Stock teórico

`inventario_saldo_inicial` captura, por producto y local, el saldo que calculaba el sistema al migrar: último conteo cerrado y operaciones posteriores, incluidos cobros de Salón. Esto evita volver a descontar ventas ya registradas. Si hay recepciones o movimientos con fecha futura, la migración pide revisarlos primero.

A partir de ahí, `inventario_evento` conserva las entradas y salidas. Los disparadores registran los cambios de detalle de movimientos y recepciones, dentro de sus propias transacciones. `inventario_stock_teorico` calcula saldo inicial más eventos. Stock actual y sugerencias de compras consultan ese mismo saldo. Para las sugerencias de compras, el consumo pasa a ser las salidas registradas durante los últimos treinta días.

Una orden de compra todavía no es entrada de stock: aumenta al recibirla. Los préstamos conservan el flujo existente: salida en origen y entrada en destino al aceptar. Las ventas descuentan al emitir el cobro. Mermas, devoluciones, reposiciones y correcciones de recepciones mantienen su motivo. Una corrección de cantidad de recepción registra su diferencia en el día abierto, sin reescribir reportes diarios ya cerrados. Cambiar únicamente la fecha o el número del documento no desplaza su stock entre días.

Los eventos pueden dejar saldo negativo, igual que el sistema anterior; no se agregó bloqueo de venta por stock insuficiente. Los conteos físicos y las justificaciones **no ajustan el saldo**. Para reflejar una merma o una entrada real se registra la operación correspondiente.

## Día operativo

- Cada local tiene como máximo una jornada abierta.
- La migración abre la jornada de activación con un saldo inicial por producto.
- No se cierra ni se cambia de fecha a medianoche. Por ejemplo, un cobro a las 04:30 del 27 pertenece a la jornada del 26 si esta sigue abierta.
- Gerente o supervisor con permiso de cierre puede pulsar **Cerrar día**. Deben resolverse primero las mesas que tengan pedidos pendientes de cobrar.
- El cierre conserva un reporte: inicial, entradas, salidas, saldo final, desglose por motivo y ventas por producto/presentación con sus cantidades e importes.
- El cierre no escribe un conteo ni cambia el stock. Reintentar el mismo cierre devuelve el cierre existente.
- Se puede abrir el siguiente día mediante el botón. Si aún no hay jornada abierta, la siguiente recepción, movimiento o cobro también la abre automáticamente. La fecha propuesta es la mayor entre la fecha actual en Lima y la fecha siguiente a la última jornada cerrada; nunca se reutiliza una fecha cerrada.
- La consulta de días ofrece las últimas 366 jornadas. Los reportes quedan guardados más allá de ese límite de visualización.

Los movimientos y el cierre comparten un bloqueo por local para no partir una operación entre jornadas. El cierre bloquea nuevos envíos mientras comprueba que no quedan mesas pendientes. El reporte cerrado es una copia persistida y no cambia cuando se corrigen documentos o catálogos después.

## Mix de ventas

Consulta por intervalo de hasta 367 días operativos. Las horas son horas de **cobro en Lima**, de 00 a 23; se pueden seleccionar varias, incluso a ambos lados de medianoche. Sin selección se incluyen todas. La vista permite sumar las horas elegidas o presentar cada producto por hora.

El ranking Top 5/10/15/20 se calcula por unidades de cada presentación en el filtro, incluyendo todas sus horas seleccionadas. Los totales superiores corresponden al filtro completo. Productos con distintas presentaciones se distinguen por identidad y nombre capturado en la venta.

Las ventas anteriores a la migración siguen disponibles por su fecha calendario de cobro, puesto que entonces no se guardaba una jornada operativa. No se les inventa un día de servicio retroactivo.

Los reportes de inventario, ventas y mix pueden descargarse en CSV para abrirlos en una hoja de cálculo.

## Real vs. teórico

1. El gerente inicia una ronda manualmente. No depende del cierre diario; solo se permite una ronda abierta por local.
2. La ronda incluye los productos activos y captura el stock teórico al **iniciar la ronda**. La pantalla muestra esa hora de referencia. Las operaciones posteriores no alteran esta referencia.
3. El gerente asigna cada producto a un usuario activo del local. Ve el conjunto completo. Un miembro ve y registra únicamente lo que tiene asignado, sin ver las cantidades teóricas ni diferencias.
4. El miembro guarda cantidades con estado **En proceso** o **Hecho**. Puede retomar su avance mientras no esté revisado.
5. Gerente/supervisor revisa lo marcado como Hecho. Se conserva el contado original, y el valor revisado se guarda aparte. Si cambia la cantidad, exige una observación, como “mal conteo”. No se sustituye silenciosamente lo entregado por el miembro.
6. La diferencia es **real revisado menos teórico**: negativa = faltante; positiva = sobrante.
7. En Diferencias y justificación, el responsable filtra por fecha de inicio de la ronda y selecciona Top 5, 10, 15 o 20 por magnitud absoluta. Se muestra la unidad de cada producto; este ranking no es por costo ni compara valores monetarios.
8. Se guarda la justificación con usuario y hora. Puede completarse después de finalizar la ronda. Una nueva revisión invalida la justificación anterior, que sigue conservada en el historial.
9. Para finalizar la ronda deben estar revisados todos los productos. Los miembros ya no pueden modificarla; se puede iniciar otra ronda.

Cada asignación, avance, entrega, corrección y justificación tiene historial. Se comprueba la versión antes de guardar para no sobrescribir cambios de otra ventana. Las rutas validan perfil, permiso vigente y local; no confían en un local enviado por el navegador. No hay edición de conteos ajenos por miembros ni acceso del administrador de sistemas a estos módulos operativos.

La referencia teórica es la del inicio de la ronda, no la hora en que cada miembro terminó de contar. Hay que coordinar el conteo con esa referencia para interpretar correctamente movimientos ocurridos durante la ronda. No se implementó ajuste automático de diferencias.

## Archivos principales

- Migración: `database/migrations/20260926_jornadas_conteos.sql`.
- Backend: `backend/app/modules/inventarios/operativo.py`.
- Pantallas: `frontend/src/features/inventoryOperations/`.
- Integraciones: stock, compras, permisos, menú, Inicio y redirección de rutas antiguas.
- Pruebas: `backend/tests/test_inventory_operations.py`.

## Validación

La asignación por usuario está en Inventario → Real vs. teórico → Conteos y revisión. El gerente selecciona una ronda abierta y asigna cada producto pendiente desde la columna «Asignado a». La vista permite filtrar por miembro (incluye «Sin asignar»), categoría, producto y estado; muestra cantidades por responsable y exporta a CSV únicamente los productos filtrados. Esta asignación corresponde a la ronda y al usuario individual, no es una plantilla automática por puesto. Los miembros continúan viendo solo sus productos asignados. Esta mejora de filtros no requiere SQL adicional; TypeScript y lint del componente fueron comprobados.

- 125 pruebas existentes aprobadas antes de activar la nueva estructura en la base temporal.
- 8 pruebas nuevas aprobadas después de ejecutar la migración: saldo inicial, aislamiento de locales, stock de compras, apertura/cierre, reportes congelados, venta de madrugada, filtros horarios, corrección de recepción, conteo asignado, revisión con observación, justificaciones, versiones, permisos y reversión ante fallos.
- Compilación de producción del frontend y TypeScript correctos; lint del módulo nuevo sin observaciones.
- Evidencia: `VALIDACION_INVENTARIO_OPERATIVO_20260926.txt`.
- No se realizaron movimientos, cobros ni migraciones sobre datos reales. El recorrido visual manual queda para después de la activación.
