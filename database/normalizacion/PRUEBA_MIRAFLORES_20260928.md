# Prueba cargada en Miraflores

## Conteo entregado para revisión (actualización)

Actualización de interfaz: las correcciones ahora se acumulan en la pantalla y se envían juntas mediante **Guardar y cerrar revisión**. Ya no hay guardado por producto en la revisión. **Añadir observación** abre el campo opcional; ocultarlo conserva lo escrito. Los cambios se mantienen al filtrar productos. Backend valida todas las cantidades, observaciones, identidades y versiones antes de aplicar el lote y cerrar en una transacción; preserva originales e historial y no modifica el stock. Las comprobaciones de este cambio se ejecutan en base temporal, sin cerrar la ronda de Miraflores.

Se cargó la ronda 1, `PRUEBA - Conteo entregado por el equipo de Miraflores`: 140 productos en HECHO, pendientes de revisión, sin correcciones ni cierre. Cocina: José (75); Bartender: Roberto (50); Mesero: María (15). Son registros simulados, identificados en el nombre de ronda y actividades, no conteos físicos realizados por esas personas. 84 cantidades coinciden con el sistema, 28 tienen faltantes y 28 sobrantes. No se cambió ningún saldo de stock ni ningún cierre de ventas.

Respaldo previo a esta entrega: `backend/.demo_backups/20260928_210009/antes.dump`; manifiesto `conteo_resultado.json`. Script idempotente de carga: `backend/scripts/demo_conteo_miraflores.py`.

La pantalla de gerente/supervisor muestra **Revisar conteos**, sin iniciar rondas ni registrar originales. Cantidad del sistema y diferencia son de solo lectura; la cantidad contada se puede corregir con observación, conservando original e historial. **Cerrar revisión** acepta todos los HECHO sin corrección y conserva las correcciones ya guardadas, en una transacción. Exige todas las entregas y versiones vigentes; la interfaz bloquea el cierre mientras haya ediciones sin guardar. Los miembros conservan su flujo para iniciar y entregar conteos. No requiere migración nueva.

Validación: 125 pruebas previas + 8 de inventario + 7 de puestos/revisión aprobadas en base temporal; build y lint correctos. Se comprobó por API que la ronda real de prueba tiene 140 HECHO y sigue abierta, sin cerrarla por el gerente.

Carga autorizada por el usuario en la base actual, local Miraflores (1). Identificador: `DEMO-MIRAFLORES-20260928`. Se confirmó en una única transacción después de un respaldo completo. No volver a ejecutar para duplicar datos: el script detecta la carga existente.

## Asignaciones permanentes

- Cocina: 75 productos (Carnes, Lácteos, Producción, Salsas, Secos, Vegetales).
- Bartender: 50 productos (Cervecera, Tragos).
- Mesero: 15 productos (Botellas).

Se asignó por puesto, no a personas. Configuración visible en Inventario → Real vs. teórico → Asignación por puesto. Las rondas ya abiertas conservan su distribución; las nuevas copian esta configuración.

## Jornadas y ventas simuladas

Se conservaron intactos los cierres del 26 y 28 de septiembre. Las nuevas fechas son **simuladas y futuras respecto a la carga**; continúan la secuencia operativa sin reescribir reportes previos. La siguiente apertura de Miraflores será **04/10/2026**.

| Día operativo | Jornada | Total |
|---|---:|---:|
| 29/09/2026 | 8 | S/ 192.90 |
| 30/09/2026 | 9 | S/ 236.70 |
| 01/10/2026 | 10 | S/ 228.90 |
| 02/10/2026 | 11 | S/ 252.80 |
| 03/10/2026 | 12 | S/ 228.90 |

Total: **S/ 1,140.20**, diez comprobantes internos INT-00000002 a INT-00000011. Dos ventas por jornada, a las 20:30 y 01:15 del día siguiente, efectivo y tarjeta respectivamente; cierres a las 04:30. Permiten probar el filtro horario y la fecha operativa nocturna. No son documentos fiscales.

Los pedidos, movimientos, comprobantes y actividades llevan la marca de prueba. Usuario responsable técnico de la carga: Carlos, perfil Gerente; no representan ventas efectivamente realizadas por esa persona. Los precios y consumos se obtuvieron de las presentaciones y recetas vigentes. Se conservaron mínimos, recetas, cierres anteriores y saldos de otros locales. Las mesas quedaron libres después del cobro.

## Stock resultante

| Producto | Stock inicial | Consumo | Stock final | Mínimo |
|---|---:|---:|---:|---:|
| 174 IPA | 14 L | 10 L | 4 L | 5 L |
| 2 Más | 14 L | 2 L | 12 L | 5 L |
| Agua con Gas | 14 UNI | 6 UNI | 8 UNI | 10 UNI |
| Agua sin gas | 14 UNI | 2 UNI | 12 UNI | 10 UNI |
| Botella de 174 IPA | 8 UNI | 5 UNI | 3 UNI | 5 UNI |
| Botella de L.I.M.A. Pale Ale | 8 UNI | 2 UNI | 6 UNI | 5 UNI |
| Delirium Tremens | 7 UNI | 5 UNI | 2 UNI | 3 UNI |

De los 140 productos: 47 bajo mínimo, 92 sobre mínimo y 1 exactamente en el mínimo. Antes había 43 bajo mínimo: cuatro productos adicionales cruzaron el umbral con las ventas. No se generaron saldos negativos.

## Respaldo y validación

- Respaldo previo: `backend/.demo_backups/20260928_205128/antes.dump`.
- Asignaciones anteriores y manifiesto de carga en esa misma carpeta (`asignaciones_antes.json`, `resultado.json`). Carpeta excluida de Git mediante su propio `.gitignore`.
- Script: `backend/scripts/demo_miraflores.py`; sin argumentos solo consulta el plan, `--apply` escribe con respaldo y comprobaciones. Después de esta carga rechaza nuevos intentos por su identificador.
- Se verificaron por API la asignación completa, los cinco cierres, las ecuaciones de stock, el total de ventas y los filtros de horas 01 y 20. Las comprobaciones transaccionales garantizaron que no cambiaran los cierres previos ni los saldos de otros locales.
- Restaurar el dump reemplazaría también cualquier operación posterior; no se ejecutó ninguna restauración.
