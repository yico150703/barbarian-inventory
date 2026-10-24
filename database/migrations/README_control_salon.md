# Control de salón y acciones de responsables

## SQL pendiente

Ejecuta **20260923_control_salon.sql** completo, una sola vez, como propietario en `barbarito`, después de las migraciones de acceso, pedidos, envíos adicionales y distribución de Salón. Este archivo no fue ejecutado en la base real por el asistente. Debe terminar en COMMIT. Reinicia el backend y recarga el frontend.

En **Usuarios → Editar usuario**, asigna un PIN de Salón de cuatro dígitos a gerente y supervisor, además de sus locales. También siguen habilitados los miembros con puesto Mesero o Bartender. Este PIN es independiente de la contraseña de Gestión. Cada responsable entra a Salón con su propio usuario, local y PIN.

## Pantallas

- El encabezado muestra Salón y el nombre del local. El mapa ocupa el espacio entre encabezado y acciones, sin desplazamiento de la página.
- Abajo del mapa: Listar mesas, Información y Salir. Listar mesas muestra las propias; Información permite seleccionar una mesa y consultar quién la atiende y desde cuándo.
- Gerente tiene además Mover mesa y Cambiar miembro. Ambas acciones solicitan nuevamente su PIN.
- Dentro de una mesa: Cancelar, Borrar, Añadir comentario, Salir y Enviar. Gerente y supervisor también ven Eliminar.
- Cancelar descarta los cambios pendientes y regresa al mapa sin confirmación. Enviar registra los productos pendientes y regresa al mapa solo después del éxito. Salir elimina la sesión de Salón del navegador y regresa al acceso.

## Permisos y operaciones

- **Borrar y comentar:** solo líneas pendientes del usuario responsable, antes de enviar. No altera productos enviados.
- **Eliminar:** gerente o supervisor selecciona una línea enviada, pulsa Eliminar e ingresa nuevamente su propio PIN. Se anulan todas las unidades de la línea seleccionada, incluidas sus líneas históricas agrupadas. Se conserva el pedido original y una anotación de anulación con responsable y fecha; el total visible excluye lo anulado.
- **Mover mesa:** gerente autoriza con PIN, selecciona origen y luego destino libre. Traslada los pedidos y mantiene al miembro responsable. No cambia la distribución física del mapa. No combina mesas ocupadas.
- **Cambiar miembro:** gerente autoriza, selecciona la mesa y elige un miembro en la lista con buscador. Solo aparecen meseros o bartenders activos, asignados al local, con acceso PIN. Se cambia la responsabilidad de todos los envíos de esa mesa.
- Un miembro no puede abrir ni modificar pedidos de otro. Gerente y supervisor pueden consultarlos y anular productos; no agregar pendientes ajenos. Para cambiar al responsable se usa la reasignación explícita.
- Si existe un borrador guardado por la versión antigua, debe enviarse o cancelarse antes de mover o reasignar.
- Las autorizaciones duran dos minutos y sirven para una sola operación exitosa. Se verifican usuario, local, acción y vigencia del PIN. Cinco intentos incorrectos bloquean temporalmente el PIN durante cinco minutos.
- Todas las acciones administrativas registran actividad. Los pedidos originales mantienen sus bloqueos de edición; asignaciones y anulaciones se guardan por separado.

Todavía no se implementan cobro, cierre de mesa, impresión ni cocina. Anular todos los productos no cierra automáticamente la mesa. Las pruebas se realizan en PostgreSQL temporal con datos ficticios.
