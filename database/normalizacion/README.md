# Diagnóstico y propuesta para Barbarito — 22/09/2026

## Estado actual de implementaci?n

**Backend y frontend adaptados para la etapa 03 y validados con 40 pruebas y compilaci?n.** La migraci?n 03 se ensay? en PostgreSQL temporal, no en la base real. Instrucciones vigentes: [ACTIVAR_AHORA.md](ACTIVAR_AHORA.md). El 04 sigue pendiente y no debe ejecutarse.

Los apartados de diagn?stico siguientes describen el an?lisis y los requisitos originales; los requisitos de c?digo de 03 ya est?n cubiertos. La versi?n guardada de 03 tiene confirmaci?n `true`, mapa completo a Miraflores y correcciones de la tabla temporal y del ?ndice ?nico global.

## Confirmaciones posteriores del usuario

- Etapas 01 y 02 ejecutadas y verificadas. Etapas 03 y 04 siguen pendientes; el backend todavía requiere adaptación.
- Los inventarios, la orden de compra y las recepciones existentes pertenecen a **Miraflores (id_local 1)**. El mapa del archivo 03 refleja esta confirmación para los inventarios 1–9 y la orden 1; las recepciones heredan la tienda de la orden.
- El usuario confirmó también los movimientos 1–4 en **Miraflores (id_local 1)**. El mapa de las 14 operaciones está completo en el archivo 03; esta confirmación no cambia el texto de contraparte ni implica que el backend esté adaptado.
- Proveedores, productos, carta y recetas son compartidos. Usuarios con acceso según tienda asignada y administrador global. No crear inventarios ni copiar operaciones a las demás tiendas. El usuario prevé reiniciar inventarios después, pero no ha autorizado borrarlos ahora.
- Esta actualización solo modifica archivos; no ejecuta el mapa en la base.

## Resultado

**La base está bien encaminada y no necesita rehacerse. Sí necesita completar la separación por tienda, corregir dos restricciones y retirar algunas fuentes duplicadas de información de manera coordinada con el backend.**

Se revisó la base real mediante una transacción `REPEATABLE READ READ ONLY`, la estructura de todas sus tablas, restricciones, índices, funciones y triggers propios, y las consultas del backend relacionadas con los cambios. No se ejecutó ninguno de los SQL de esta carpeta. No se modificaron registros de negocio.

Evidencia reproducible: [auditoria_actual.json](auditoria_actual.json), generado por [auditar.py](auditar.py). Desde la raíz del proyecto:

```powershell
backend/.venv/Scripts/python.exe database/normalizacion/auditar.py
```

El programa usa la conexión del backend sin mostrar su contraseña. El JSON contiene metadatos, conteos e identificadores operativos para preparar el traslado por local; **no es un respaldo restaurable**.

## Estado observado ahora

- 44 tablas, 297 columnas, 84 relaciones con claves foráneas y 131 índices.
- Cero referencias huérfanas en las 84 relaciones.
- 140 productos, 4 locales, 133 ítems de carta, 199 presentaciones y 199 recetas.
- 476 ingredientes de recetas, 9 subproductos y 7 grupos de salsa.
- 9 inventarios con 1260 detalles, 1 orden con 140 detalles, 9 recepciones y 4 movimientos.
- Cero diferencias de unidades entre detalles de recetas/subproductos/salsas y sus componentes.
- Cero productos recibidos fuera de su orden y cero cantidades acumuladas superiores a lo solicitado.
- Cero grupos de salsa o promoción sin suficientes opciones según las comprobaciones realizadas.
- Cero grupos de nombres de producto duplicados al comparar sin mayúsculas ni espacios extremos.
- Dos usuarios conservan un puesto en la columna antigua; ambos ya tienen ese puesto activo en la tabla de asignaciones.
- Todas las restricciones están validadas. Se revisaron las secuencias sin llamar a `nextval`: la de `opcion_menu` propone 33, que ya existe. La etapa 01 la adelanta sin retrocederla si cambió desde la auditoría.

**Cambio respecto al informe anterior:** `producto_stock_local` ya existe y tiene 560 filas (140 productos × 4 locales). No hay que volver a crear esa solución. La restricción de presentaciones todavía no admite `Kg`. El informe antiguo de 43 tablas es una fotografía anterior, no el estado actual.

## Revisión de todas las áreas

| Área y tablas revisadas | Evaluación y decisión |
| --- | --- |
| `usuario`, `perfiles`, `usuario_perfiles`, `puesto_laboral`, `usuario_puestos_laborales`, `local`, `usuario_local` | Las relaciones de varios perfiles, puestos y locales están separadas correctamente. Sobra `usuario.id_puesto_laboral` si no representa un puesto principal distinto; el código revisado usa la relación múltiple. Retirarlo en etapa 04, conservando las asignaciones. |
| `opcion_menu`, `perfil_opcion_menu`, `perfil_gestion_usuario` | Estructura adecuada para los permisos actuales. Los permisos de la web no sustituyen los permisos del usuario PostgreSQL. No hace falta rehacer estas tablas. |
| `producto`, `categoria_producto`, `proveedor`, `producto_stock_local` | Catálogo general y límites por producto/local correctamente separados. El mínimo global de `producto` queda como compatibilidad temporal; eliminarlo cuando desaparezcan sus lecturas/escrituras. |
| `producto_categoria_historial`, `producto_proveedor_historial` | Conservar: representan cambios históricos, no duplicados que deban borrarse para normalizar. |
| `inventario_cierre`, `inventario_cierre_detalle`, `inventario_cierre_correccion`, `inventario_cierre_correccion_detalle` | Cabecera/detalles/correcciones bien separados. Falta el local en la cabecera. La fecha hoy es única para toda la empresa; debe ser única por `(id_local, fecha_inventario)`. Detalles y correcciones heredan local de su inventario. |
| `orden_compra`, `orden_compra_detalle`, `orden_compra_estado_historial` | Añadir local a la orden y proveedor pactado a cada línea. La orden actual agrupa productos de varios proveedores: no colocar un único proveedor en su cabecera. |
| `factura_recepcion`, `factura_recepcion_detalle`, `factura_recepcion_historial`, `factura_recepcion_detalle_historial` | Heredar local de la orden; no repetirlo en cada detalle. El proveedor de la factura es histórico y debe conservarse. Mantener validación transaccional de producto solicitado, proveedor y cantidades recibidas. |
| `movimiento_inventario`, `movimiento_inventario_detalle` | Añadir local propietario a la cabecera. Corregir el CHECK de reposiciones. La contraparte `local_relacionado` es otro concepto; no usar ese texto para adivinar el local propietario. |
| `categoria_carta`, `item_carta`, `presentacion_venta`, `menaje` | Separación adecuada entre ítem, presentación y precio. Añadir `Kg` a las unidades de presentación. Ocultar precio en Recetas no implica borrarlo de la base. |
| `receta`, `receta_detalle`, `subproducto`, `subproducto_detalle` | Receta por presentación e ingredientes como filas: adecuado. La unidad del ingrediente repite la unidad del componente; consultar mediante JOIN y retirar esas columnas en etapa 04. Conservar la unidad de rendimiento del subproducto y la unidad/contenido de presentación: tienen significado propio. |
| `grupo_salsa`, `grupo_salsa_opcion` | Ya permiten máximo de elecciones, repetición, productos elegibles y cantidad de cada uno. Un solo grupo por presentación, por restricción UNIQUE. El alcance pedido no necesita nuevas tablas; varios grupos independientes requerirían ampliar este diseño. Retirar solamente la unidad duplicada del detalle en etapa 04. |
| `promocion`, `promocion_grupo`, `promocion_opcion` | Grupos y opciones separados correctamente. Conservar. Verificar reglas de selección al guardar y al desactivar opciones. |
| `actividad_usuario`, `auditoria_cambio` | Conservar contexto e instantáneas JSON. El historial no debe reconstruirse exclusivamente desde datos actuales que pueden cambiar. |

### Qué significa normalizar aquí

Las tablas ya tienen claves primarias y las listas de ingredientes, opciones, permisos y asignaciones se guardan en relaciones separadas. No aparecen listas de productos comprimidas en una columna. Las claves compuestas de las relaciones impiden varias clases de duplicados.

Las mejoras concretas consisten en que cada hecho tenga una fuente clara:

- Mínimo y máximo dependen del **producto y local**, no solo del producto.
- Unidad base depende del **producto o subproducto**, no de cada receta que lo utilice.
- Asignación laboral pertenece a **usuario/puesto**, no a dos representaciones paralelas.
- Proveedor acordado depende de la **línea de compra histórica**; no es equivalente al proveedor actual del catálogo.

No se certifica toda la base en tercera forma normal solo por contar claves: también hacen falta reglas de negocio confirmadas. Precio por tienda, proveedor múltiple por producto y perfiles distintos por tienda no se han solicitado ni confirmado; no se crean tablas para esas hipótesis.

## Problemas prioritarios y solución

### 1. Operación por tienda incompleta — prioridad alta

Guardar límites por tienda ya funciona a nivel de estructura. **Eso no separa todavía el stock, los inventarios, las compras ni los movimientos.** Las cabeceras operativas no tienen local y varias consultas usan máximos de fecha y acumulados globales.

Etapa 02 añade las columnas sin cambiar el comportamiento actual. Etapa 03 completa datos, exige local y cambia la unicidad de inventarios. Entre ambas debe adaptarse el backend. No se deduce una tienda del usuario creador: puede trabajar en varias.

Los locales observados son 1 Miraflores, 2 Santa Anita, 3 Barranco y 4 Sheraton. El usuario confirm? las 14 operaciones hist?ricas en Miraflores y el mapa SQL ya contiene local 1 en todas sus filas. Las recepciones heredan la tienda de la orden. Si aparecen registros hist?ricos adicionales sin local, el SQL detiene la migraci?n para completar su asignaci?n.

### 2. Reposiciones rechazadas y Kg ausente — prioridad alta

El backend ofrece `REPOSICION_PROVEEDOR`, y el CHECK de coherencia lo contempla, pero otro CHECK lo prohíbe. La etapa 01 corrige esa contradicción, permite `Kg` en presentaciones y ajusta la secuencia del menú para evitar el siguiente ID duplicado. No convierte cantidades, no cambia precios y no elimina unidades existentes.

### 3. Proveedor histórico — prioridad alta

Las consultas de compras/recepciones enlazan con `producto.id_proveedor`. Cambiar el proveedor del catálogo puede alterar pendientes de órdenes anteriores. La etapa 02 incorpora `orden_compra_detalle.id_proveedor`; la etapa 03 recupera el proveedor desde facturas únicamente cuando existe una respuesta única. Si no existe evidencia o hay varios proveedores para la misma línea, aborta y exige resolver el caso.

El backend debe registrar el proveedor al crear una línea y conservarlo al enviar la orden. Las facturas deben validarse contra ese proveedor, no contra el catálogo actual. No se impone una correspondencia histórica con el proveedor actual del producto.

### 4. Unidades y cantidades — prioridad alta antes de permitir conversiones

Los triggers actuales validan la unidad al editar detalles, pero no al cambiar la unidad del producto padre. Cambiar de `Kg` a `UNI` no convierte los números guardados en inventarios o compras.

La etapa 04 propone unidad base inmutable y lectura de unidades mediante JOIN, retirando la repetición de los detalles. Esto exige que el formulario deshabilite el cambio de unidad base y que la API lo explique con un error de validación. Si se necesitan conversiones, hay que diseñar factores y transformar cantidades con trazabilidad; este paquete no inventa equivalencias.

### 5. Campos antiguos — prioridad posterior

La etapa 04 elimina `usuario.id_puesto_laboral`, `producto.stock_minimo` y las tres unidades repetidas de los detalles. Comprueba las asignaciones laborales, la cobertura de límites locales y las unidades antes de eliminarlos. No elimina puestos, productos, recetas ni cantidades. El respaldo conserva la representación antigua si se necesita consultar después.

## Orden de los archivos

| Archivo | Cuándo ejecutarlo |
| --- | --- |
| `01_correcciones_compatibles.sql` | Después del respaldo y ensayo en copia. Compatible con el backend actual. Incluye la corrección de Kg; no hace falta ejecutar además `../migrations/20260922_recetas_unidad_kg.sql`. |
| `02_preparar_operaciones_por_local.sql` | Después de 01. Solo añade columnas nullable e índices. No habilita por sí solo la separación por tiendas. Ejecutar una sola vez. |
| `03_activar_locales_TRAS_ADAPTAR_BACKEND.sql` | **Pendiente.** Backend adaptado, escrituras detenidas y mapa histórico completado. Tiene confirmación `false` para impedir una activación accidental. |
| `04_retirar_redundancias_TRAS_ADAPTAR_BACKEND.sql` | **Pendiente.** Etapa 03 terminada, backend sin referencias a campos antiguos, formularios adaptados y pruebas aprobadas. También requiere cambiar su confirmación explícita. |

No ejecutar los cuatro archivos en bloque. Las confirmaciones son comprobaciones manuales del despliegue; SQL no puede verificar qué versión del backend está ejecutándose. Las etapas 03 y 04 son propuestas preparadas, no cambios compatibles con el código actual.

La migración antigua `../migrations/20260922_limites_stock.sql` ya no es una tarea pendiente según el estado observado. No se incluye su ejecución en esta secuencia.

## Cambios obligatorios de aplicación antes de 03

1. Resolver el local desde JWT y comprobar usuario activo, perfil vigente y asignación activa a ese local en cada operación. No aceptar como autoridad un `id_local` enviado por el cliente.
2. En `inventarios/repository.py`, filtrar inventarios, últimas fechas, stock, revisiones, correcciones y acumulados por local. Insertar el local y cambiar `ON CONFLICT (fecha_inventario)` a `ON CONFLICT (id_local, fecha_inventario)`.
3. En compras, movimientos y recepciones: filtrar listados, detalles, búsquedas, bloqueos `FOR UPDATE`, cambios de estado y escrituras por el local propietario. Una operación por ID también debe comprobarlo, aunque no aparezca en el listado.
4. Recepciones heredan el local mediante `factura_recepcion -> orden_compra`. Los detalles/historiales heredan el local por su cabecera. No agregar `id_local` repetido a cada tabla.
5. Guardar proveedor en `orden_compra_detalle`; cambiar agrupaciones y pendientes para usarlo. Mantener bloqueo de la orden/línea y validación acumulada al recibir o corregir, incluidos dos usuarios concurrentes.
6. Stock, sugerencias de compra y reportes deben sumar únicamente operaciones de la tienda activa. Los límites ya consultan `producto_stock_local`; eso no basta sin lo anterior.
7. Al cambiar de tienda, descartar los datos y formularios de la tienda anterior en frontend y volver a consultar.
8. Probar dos tiendas con inventarios de la misma fecha; acceso por ID de otra tienda rechazado; movimientos y recepciones sin mezcla; mismo producto con mínimos diferentes; cambio de proveedor sin alterar pendientes históricos.

## Cambios obligatorios antes de 04

- En catálogos, retirar todo SELECT/INSERT de `producto.stock_minimo` y quitar el fallback antiguo de `core/stock_local.py`. Definir explícitamente límites para los pares nuevos o mantener la política documentada de mínimo cero cuando no exista fila.
- En recetas, producción, salsas y sus consumidores, dejar de escribir `unidad` en los detalles. Obtenerla de `producto`/`subproducto` con JOIN y devolver el mismo campo en la respuesta API para mantener la UI.
- Buscar dependencias también en promociones, reportes y scripts de carga; no limitarse al editor nuevo.
- Hacer inmutable la unidad base de productos/subproductos en formularios y API. La restricción de etapa 04 es la última barrera, no el mensaje de usuario.
- Mantener unidades de presentación, cantidades, rendimientos y unidades en instantáneas históricas. No eliminar `id_puesto_laboral` del JWT ni de auditoría: esos campos representan el contexto usado en una acción.
- Verificar edición/creación de recetas DIRECTO, PORCIONADO y PREPARADO, ingredientes, opciones repetibles y no repetibles, y recetas antiguas con subproductos. No forzar que todas las recetas porcionadas tengan un solo ingrediente: existen casos históricos distintos.

## Decisiones que no deben inventarse

- **Contraparte de movimientos:** si todos los préstamos son entre las tiendas registradas, conviene sustituir el texto `local_relacionado` por una FK y diseñar la relación entre entrega y recepción. Si también existen locales externos, una FK exclusiva a `local` sería incorrecta. Se conserva el texto hasta confirmar esto; no se migra por coincidencia de nombres.
- **Perfiles por tienda:** hoy perfiles y locales están asignados independientemente al usuario. Si alguien debe ser gerente en una tienda y miembro en otra, se necesita una asignación usuario/local/perfil y adaptar la autenticación. No está confirmado ese requisito.
- **Productos con varios proveedores:** un proveedor actual por producto no viola por sí solo la normalización. Si realmente se compra simultáneamente a varios, hace falta relación producto/proveedor y revisar la unicidad de líneas de compra. El proveedor histórico propuesto resuelve un problema diferente.
- **Más de un grupo de opciones por receta:** el modelo actual admite uno. Para varios grupos con reglas independientes habría que retirar su UNIQUE por presentación y añadir nombre/orden del grupo, además de cambiar API/editor.

## Cómo ejecutar en pgAdmin

1. Conectar con el propietario de las tablas (`postgres` en la revisión anterior) o una cuenta autorizada para ALTER. No convertir al usuario habitual `multi` en superusuario.
2. En **Databases → barbarito → clic derecho → Backup…**, generar un respaldo nuevo en formato **Custom**. Los archivos antiguos del proyecto no reflejan toda la estructura actual. Conservarlo fuera de los SQL y ensayar la restauración en una base de prueba.
3. En la base de prueba restaurada, ensayar los archivos y las comprobaciones. Los SQL contienen una verificación `current_database() = 'barbarito'`: para una copia con otro nombre, cambiar esa comprobación solamente en una copia de los scripts, apuntando al nombre de prueba.
4. En producción, seleccionar **barbarito → Query Tool**. Con el icono de carpeta / **Open File**, abrir `database/normalizacion/01_correcciones_compatibles.sql`. Ejecutar **el archivo completo** con **F5**, sin seleccionar un fragmento.
5. Revisar **Messages** y el resultado final. Si ocurre un error y la sesión queda en transacción abortada, ejecutar `ROLLBACK;`, resolver la causa y volver a intentar el archivo completo.
6. Aplicar 02 únicamente cuando se vaya a continuar la adaptación por local. No ejecutar 03/04 hasta cumplir sus requisitos. Para esas etapas detener escrituras, completar mapas, ensayar con el backend nuevo, realizar el despliegue coordinado y después reabrir la aplicación.

Cada archivo usa una transacción; un error previo al COMMIT permite revertir ese archivo. Después de un COMMIT, especialmente de 04, la reversión requiere restaurar un respaldo compatible y la versión anterior de la aplicación, o una migración inversa que conserve los datos nuevos. No se entrega un “rollback” que borre operaciones nuevas.

## Límites de la validación

La auditoría se ejecutó contra la base real en modo solo lectura. Los SQL se revisaron contra sus nombres y relaciones actuales, pero **no se ejecutaron ni se ensayó su aplicación en una copia restaurada**. Las comprobaciones de datos no garantizan ausencia de problemas en todos los flujos concurrentes. No se hizo benchmark, auditoría completa de seguridad ni prueba de recuperación.

No se recomienda borrar índices o agregar índices a todas las FK sin medir consultas. Los nuevos índices por local corresponden al acceso previsto; el resto debe evaluarse con planes y carga real. Tampoco hace falta convertir todas las listas CHECK en tablas, renombrar toda la base o duplicar los catálogos por tienda para resolver lo solicitado.
