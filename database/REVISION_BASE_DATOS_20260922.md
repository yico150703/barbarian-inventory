# Revisión de la base de datos Barbarito

Fecha: 22 de septiembre de 2026. Base en ejecución, no solo respaldos.

**Este documento conserva la revisión inicial. La auditoría posterior encontró 44 tablas, incluida `producto_stock_local` con 560 filas. Para el estado actualizado, diagnóstico de normalización y SQL por etapas, consultar [normalizacion/README.md](normalizacion/README.md).**

Actualización posterior a la revisión: el usuario confirmó que los límites deben ser independientes por tienda. Se adaptó el código y la migración pendiente para usar `producto_stock_local` con clave producto/local. La API verifica el local activo y la asignación vigente del gerente. Esta nueva versión del SQL no se ha ejecutado. Los hallazgos siguientes describen la base antes de migrar.

## Alcance y método

Consultas realizadas con la conexión del backend, usuario `multi`, en transacciones `REPEATABLE READ READ ONLY`, con límite de tiempo por sentencia. No se ejecutaron cambios de esquema ni de registros. Se inspeccionaron metadatos de todas las tablas de aplicación, columnas, restricciones, índices, secuencias, funciones propias, triggers, roles y permisos. Se contaron registros y se comprobaron relaciones y reglas seleccionadas sin exportar datos personales ni contraseñas.

Detalle estructural y resultados: `revision_esquema_20260922.json`. Es un inventario de metadatos, no un respaldo restaurable.

## Inventario

- PostgreSQL 18.4; base `barbarito`, aproximadamente 12 MB.
- Esquema de aplicación: `public`.
- 43 tablas y 293 columnas.
- 43 claves primarias, 82 claves foráneas, 29 restricciones de unicidad, 80 CHECK y 236 restricciones NOT NULL.
- 129 índices y 39 secuencias.
- 3 funciones propias y 3 triggers de validación de unidades.
- Sin vistas ni políticas de seguridad por fila. El acceso por perfil se controla en la aplicación.
- 140 productos activos, 9 categorías de productos, 9 proveedores, 4 locales y 4 perfiles.
- 9 inventarios cerrados con 1260 detalles; una orden recepcionada con 140 detalles; 9 recepciones y 4 movimientos.
- 199 recetas, 476 componentes de recetas, 9 subproductos, 7 grupos de salsa y 3 promociones.

## Organización

| Área | Tablas principales |
| --- | --- |
| Acceso | usuario, perfiles, usuario_perfiles, puesto_laboral, usuario_puestos_laborales, local, usuario_local, opcion_menu, perfil_opcion_menu, perfil_gestion_usuario |
| Catálogos | producto, categoria_producto, proveedor, producto_categoria_historial, producto_proveedor_historial |
| Inventarios | inventario_cierre, inventario_cierre_detalle y tablas de correcciones |
| Abastecimiento | orden_compra y detalle/historial, factura_recepcion y detalle/historiales |
| Movimientos | movimiento_inventario y detalle |
| Carta y producción | categoria_carta, item_carta, presentacion_venta, menaje, receta y detalle, subproducto y detalle, grupo_salsa y opciones |
| Promociones | promocion, promocion_grupo, promocion_opcion |
| Auditoría | actividad_usuario, auditoria_cambio |

## Comprobaciones de integridad

- Se comprobaron las 82 relaciones: cero referencias huérfanas.
- Todas las restricciones inspeccionadas están marcadas como validadas.
- Cero discrepancias de unidades entre ingredientes/componentes y sus productos o subproductos.
- Cero nombres de producto duplicados tras normalizar espacios extremos y mayúsculas.
- Cero mínimos negativos y cero presentaciones no positivas. Los 140 productos tienen mínimo mayor que cero, con precisión compatible con tres decimales.
- Cero usuarios activos sin un perfil activo o un local activo asignado.
- Cero líneas de compra con cantidades recibidas superiores a lo solicitado.

Estas comprobaciones no sustituyen una prueba completa de cada flujo ni una auditoría de rendimiento, recuperación o seguridad.

## Hallazgos para resolver antes de ampliar el sistema

### 1. Separación por local incompleta

Existen `local` y `usuario_local`, y la auditoría identifica el local. Sin embargo, `producto`, `inventario_cierre`, `orden_compra`, `factura_recepcion` y `movimiento_inventario` no tienen `id_local`. El campo `local_relacionado` de movimientos es texto y describe la contraparte, no una sede propietaria del registro.

Consecuencia: agregar únicamente filtros al backend no basta para separar las operaciones por sede. Tras confirmar el usuario que los límites serán específicos de cada tienda, se adaptó la migración pendiente a una relación producto/local. No se debe asignar arbitrariamente una sede a los registros históricos; la separación de esos registros es un trabajo distinto del almacenamiento de límites.

### 2. Restricciones contradictorias para reposiciones

`ck_movimiento_coherencia` contempla `REPOSICION_PROVEEDOR`, pero `ck_movimiento_motivo` solo admite PRESTAMO_RECIBIDO, MERMA, PRESTAMO_ENTREGADO y DEVOLUCION_PROVEEDOR. El backend ofrece reposiciones. En el esquema actual, una reposición válida para la aplicación sería rechazada por la segunda restricción.

No se modificó esa restricción en esta revisión.

### 3. Cambiar unidades de productos requiere controlar dependencias

Los tres triggers validan al insertar o actualizar detalles de recetas, subproductos y salsas. No hay un trigger equivalente sobre `producto` que controle el cambio de su unidad. Actualmente las unidades son coherentes, pero editar la unidad de un producto ya utilizado puede dejar detalles incompatibles. El catálogo permite editar la unidad; debe definirse cómo bloquear o convertir esos cambios.

### 4. Respaldos locales anteriores al esquema vigente

La base actual tiene 43 tablas. Los respaldos locales inspeccionados anteriormente contienen declaraciones de 31 y 36 tablas. No incluyen toda la estructura actual. `barbarito.sql` también es un respaldo binario PGDMP, a pesar de su extensión.

Antes de aplicar cambios estructurales conviene generar un respaldo actualizado y conservar el SQL de migración. No se generó ni restauró un respaldo en esta revisión.

### 5. Permisos de conexión y perfiles son conceptos distintos

`multi` es el usuario PostgreSQL configurado en el backend. Tiene SELECT, INSERT, UPDATE y DELETE sobre las 43 tablas, pero todas pertenecen a `postgres`. Por eso puede operar datos y no puede ejecutar ALTER TABLE sobre `producto`.

El perfil Gerente (ID 2) y Administrador del sistema (ID 1) son perfiles del sistema web; no son usuarios PostgreSQL. El acceso exclusivo del gerente se aplica en la API y el menú. Una conexión directa con permisos de escritura no está sujeta a esos permisos de aplicación.

Para ejecutar cambios estructurales desde el asistente se necesita una conexión administrativa local autorizada, separada de la usada por el backend. No hace falta elevar permanentemente los permisos de `multi` ni ejecutar la aplicación como `postgres`. No compartir contraseñas por el chat; configurar las credenciales localmente cuando se acuerde ese paso.

### 6. Horario

PostgreSQL utiliza `America/Bogota`; el backend de inventarios calcula Lima con UTC−5. En las operaciones actuales ambos utilizan el mismo desplazamiento, pero hay lógica que usa CURRENT_DATE y otra que usa la fecha del sistema. Conviene mantener una política horaria consistente.

## Estado de la migración de límites

Se comprobó directamente:

- `producto.stock_maximo` no existe.
- No existe la opción 33 ni el código `LIMITES_STOCK`.
- El mínimo actual es `numeric(12,3) NOT NULL DEFAULT 0`.
- El perfil Gerente es el ID 2.

Por tanto, `migrations/20260922_limites_stock.sql` sigue pendiente. El intento anterior con `multi` falló por propiedad de la tabla y fue revertido. Esta revisión no volvió a ejecutar la migración.

Antes de ejecutar: conservar un respaldo actualizado, configurar el acceso administrativo local necesario y esperar la autorización del usuario. El diseño por producto/local ya fue confirmado y preparado; la migración permanece pendiente.
