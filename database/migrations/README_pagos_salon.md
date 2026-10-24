# Pagos de Salón — 26/09/2026

## Activación

1. Tener aplicadas las migraciones de pedidos, envíos adicionales, distribución, control de Salón, seguimiento de movimientos y operaciones por local (03).
2. Ejecutar completo `20260926_pagos_salon.sql` **una sola vez**, como propietario, en `barbarito`.
3. Ejecutar completo `20261016_promociones_reposicion_salon.sql` **una sola vez**, como propietario, en `barbarito`.
4. Reiniciar el backend y recargar el frontend.

La migración no fue aplicada automáticamente a la base real. Si falta, el formulario muestra el archivo que debe ejecutarse.

## Flujo

- El pedido muestra `1 UNI` y `1 PORCIÓN`, sin ceros decimales sobrantes. También corrige la visualización de pedidos antiguos, conservando sus registros.
- `Pagar` abre una cuenta con productos enviados. Primero deben enviarse o descartarse los pendientes.
- Boleta: sin datos obligatorios del cliente. Boleta electrónica: DNI de ocho dígitos y nombres/apellidos. Factura: RUC de once dígitos y razón social.
- Seleccionar efectivo o tarjeta y pulsar `Emitir`. `Cancelar` vuelve a la cuenta sin cobrar.
- El comprobante se muestra como imagen SVG construida con los datos guardados. `Regresar al salón` vuelve al mapa y `Salir` cierra la sesión y vuelve al login.
- El propietario de la mesa puede cobrarla. Gerentes y supervisores también pueden cobrar mesas de su local. Otro miembro no puede consultar/cobrar una mesa ajena.

## Cobro y consumo

El total usa precios y cantidades de pedidos enviados, excluyendo líneas anuladas. El navegador no determina el importe ni el local. Cobro, salida de inventario, relación con los pedidos y auditoría se guardan en una transacción: ante un fallo se revierte todo.

Cada cobro tiene una clave de reintento y una huella de la cuenta. Repetir la misma solicitud devuelve el comprobante existente sin volver a descontar. Si cambian los productos, responsables o asignaciones después de abrir el pago, se exige revisar otra vez la cuenta. La vista `salon_pedido_actual` excluye pedidos pagados: libera la mesa y permite nuevos pedidos sin alterar el historial. Tampoco se admite reenviar como nuevo un envío previamente pagado.

El inventario recibe un movimiento `SALIDA / VENTA_SALON` únicamente en el local autenticado, con fecha y hora de Lima. Se utiliza el mecanismo existente de stock calculado, incluidos movimientos posteriores a un cierre del mismo día. No se modifican conteos históricos.

## Promociones con reposición en Salón

Las promociones activas y dentro de horario aparecen en la pestaña **Promociones** del pedido. Cada vez que se agrega una, representa una persona y una línea con el precio de promoción. Sus grupos y opciones de salsa se eligen para esa persona; una mesa puede tener varias barras libres con selecciones distintas.

En el editor de promociones, marca **Permitir reposición sin costo** solo en las presentaciones que se pueden reponer. Tras enviar la barra, el botón **Reponer** agrega una porción pendiente vinculada a esa barra; se vuelve a elegir la salsa cuando aplique. La reposición aparece a S/ 0.00, no incrementa el precio de la cuenta y sí se incluye en el consumo de inventario al cobrar. El comprobante conserva la barra a la que pertenece cada reposición.

Las promociones existentes no habilitan reposiciones por defecto. No ejecutes la migración en una base ya actualizada; primero comprueba si existe `promocion_reposicion`.

El consumo se calcula con **las recetas vigentes al cobrar**:

- Ingredientes por presentación × unidades pedidas.
- Subproductos: cantidad usada / rendimiento × ingredientes del subproducto.
- Opciones seleccionadas por producto, incluidas repeticiones autorizadas.
- Se acumula por producto y se redondea a tres decimales, como admite el inventario.

Si falta receta o no es posible identificar ingredientes/opciones o sus unidades, no se cobra. No se inventan equivalencias entre unidades ni relaciones basadas en nombres. Los pedidos nuevos conservan también la identidad del producto de cada opción; para pedidos anteriores se resuelve por el ID de opción guardado.

Se mantiene la política actual de movimientos: puede quedar stock negativo; no se implementó reserva ni bloqueo por stock insuficiente. El descuento ocurre al emitir, no al enviar el pedido ni al abrir el formulario.

## Alcance del comprobante

Por ahora se genera un **comprobante interno, sin validez tributaria** y con numeración `INT-…`. Elegir boleta electrónica o factura registra el tipo solicitado y sus datos, pero **no envía nada a SUNAT**. Falta definir/conectar el proveedor de emisión electrónica y su configuración fiscal. Esto se indica tanto en el formulario como en la imagen.

Tarjeta registra el medio de un pago ya recibido en el POS; no carga una tarjeta ni captura sus datos. No incluye pasarela, devolución de cobros, pagos parciales ni división de cuentas.

## Archivos y comprobaciones

- Backend: `backend/app/modules/auth/salon_payments.py`.
- Formulario e imagen: `frontend/src/features/salonPayments/`.
- Integración: `SalonOrderPage.tsx`, rutas de la aplicación y registro del blueprint.
- Pruebas: `backend/tests/test_salon_payments.py`, ejecutadas por `run_local_scope_integration.py` en PostgreSQL temporal con datos ficticios.

El recorrido visual con un usuario real queda para la comprobación manual después de activar la migración.

Validación completada: 125 pruebas aprobadas en PostgreSQL temporal (9 nuevas de pagos), compilación de producción del frontend correcta y lint de `features/salonPayments` sin observaciones. Evidencia en `database/normalizacion/VALIDACION_PAGOS_SALON_20260926.txt`. No se ejecutaron cobros ni migraciones sobre datos reales.
