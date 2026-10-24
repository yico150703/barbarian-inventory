# Pedidos por mesa en Salón

## SQL que debes ejecutar

No se aplicaron migraciones a la base real desde el asistente.

Con la cuenta propietaria, en Query Tool de pgAdmin y sobre **barbarito**, ejecuta completos los archivos pendientes, en este orden:

1. `20260923_acceso_salon.sql`.
2. `20260923_pedidos_salon.sql`.
3. **`20260923_envios_adicionales_salon.sql`**, nuevo para permitir varios envíos en una mesa.

No repitas los archivos que ya terminaron correctamente. Cada archivo debe finalizar en COMMIT; si falla, ejecuta ROLLBACK y revisa el error antes de continuar. Después reinicia el backend y recarga el frontend.

## Funcionamiento

- M01–M10 y B01–B05 abren el pedido de la mesa.
- Cada toque en un producto agrega una unidad. Los siguientes toques aumentan su línea pendiente, hasta 99 unidades.
- Si tiene opciones, el primer toque abre su selector. Los siguientes repiten la combinación elegida para esa línea. Las opciones respetan el máximo y la posibilidad de repetir de la presentación.
- Seleccionar una línea la resalta. Debajo del listado aparecen **Agregar comentario** y **Borrar**. Solo funcionan para líneas pendientes. Borrar quita la línea completa; el comentario se aplica a todas sus unidades.
- **Cancelar** descarta los productos pendientes y vuelve al salón. No hay botón Guardar borrador ni guardado automático. Recargar sin enviar puede perder los cambios; el navegador muestra una advertencia.
- **Enviar pedido** registra únicamente las líneas pendientes. Las líneas enviadas, sus precios, opciones y comentarios son inmutables, también en PostgreSQL.
- Al volver a entrar se pueden agregar más productos. Aunque coincidan con otros enviados, se muestran primero en una línea pendiente distinta.
- Después de enviar, la vista suma líneas enviadas con igual presentación, nombre, precio, comentario y opciones. La base conserva cada envío separado. Las diferencias de comentarios, opciones o precios nunca se mezclan.
- Los reintentos del mismo envío usan un identificador único para evitar duplicarlo.
- El primer envío asigna la mesa al usuario y local actuales. Otro usuario no puede modificar ni consultar el pedido. Listar mesas muestra una sola entrada por mesa atendida por el usuario.
- Los borradores guardados con la versión anterior siguen visibles como pendientes y pueden enviarse o descartarse con Cancelar.

## Alcance

La disponibilidad de la carta depende del estado activo de sus registros, no del stock calculado por receta. Enviar registra el pedido en el sistema; todavía no imprime comandas, no lo remite a una pantalla de cocina ni descuenta inventario. Cobro y cierre/liberación de mesas siguen pendientes de implementar.

Las pruebas de persistencia se ejecutan en PostgreSQL temporal con datos ficticios.
