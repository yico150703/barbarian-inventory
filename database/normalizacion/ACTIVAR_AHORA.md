# Activar operaciones por tienda

El backend y el frontend ya están adaptados para las etapas 01–03. Las rutas de la API, el puerto y la conexión del `.env` no cambiaron.

## Pasos pendientes en tu equipo

1. Detener el backend con Ctrl+C en su terminal, para evitar escrituras durante la migración.
2. Si la conexión SQL quedó en error, ejecutar `ROLLBACK;` en esa misma conexión.
3. Abrir **el archivo guardado** `03_activar_locales_TRAS_ADAPTAR_BACKEND.sql` de esta carpeta. No ejecutar el texto antiguo de `Untitled-1`: esa copia puede conservar la confirmación en `false` y los errores anteriores.
4. Ejecutar el archivo 03 completo en `barbarito` como propietario de las tablas. La versión actual tiene `backend_adaptado=true`. Asigna inventarios 1–9, orden 1 y movimientos 1–4 a Miraflores; las recepciones heredan el local de la orden. Conserva cantidades y obtiene proveedores históricos de las facturas.
5. Reiniciar el backend desde la carpeta `backend` con `.venv/Scripts/python.exe run.py`. Recargar el frontend e iniciar sesión nuevamente. Seleccionar **Miraflores** para ver las operaciones existentes.
6. Ejecutar `00_verificar_despues_de_01_y_02.sql`: las 14 operaciones deben tener local 1 y las líneas sin proveedor histórico deben ser 0. Las otras tiendas tendrán el catálogo compartido, pero ningún inventario ni operación copiada.

**No ejecutar el 04.** Retira columnas que esta versión todavía utiliza. No es necesario para activar las operaciones por tienda.

Antes de aplicar el 03, las pantallas operativas muestran un mensaje HTTP 409 que indica la migración pendiente. Esto impide usar consultas globales o escribir datos sin tienda. Los catálogos siguen disponibles.

## Cambios realizados

- Inventarios, stock, compras, recepciones y movimientos consultan la tienda del JWT y verifican su asignación vigente. Consultar o modificar un ID de otra tienda devuelve 404.
- Inventarios nuevos guardan el local y utilizan unicidad por tienda/fecha. Se corrigió el índice antiguo que impedía dos inventarios de tiendas diferentes el mismo día.
- Cada línea de compra conserva su proveedor; cambiar el proveedor del producto no reescribe las compras anteriores. La corrección de recepciones bloquea su orden, igual que las recepciones nuevas.
- Administrador: acceso a cualquier tienda activa y gestión global de usuarios. Otros perfiles: locales asignados. Actividades del sistema globales para administrador y filtradas para otros perfiles autorizados.
- Al cambiar tienda o perfil, el frontend desmonta los formularios anteriores y carga los datos con la sesión nueva.
- Productos, proveedores, carta y recetas mantienen su alcance compartido. No se vaciaron inventarios ni se copiaron operaciones a otras tiendas.
- SQL 03 corregido: la tabla temporal no usa una FK hacia una tabla permanente; valida los locales explícitamente.

## Verificación realizada

`npm.cmd run build`: correcto. No se realizó una prueba visual automatizada en navegador.

Desde `backend`: `.venv/Scripts/python.exe tests/run_local_scope_integration.py`.

El runner inicia PostgreSQL 18 temporal en otro puerto, exporta únicamente la estructura y crea datos ficticios. Aplica el 03 en esa base, ejecuta **40 pruebas correctas** (31 anteriores y 9 de integración) y detiene el servidor temporal. No copia registros reales ni ejecuta migraciones en la conexión habitual. Evidencia: `VALIDACION_LOCAL_20260922.txt`.

Se probaron consultas y bloqueos de los cuatro módulos, tienda vacía, IDs ajenos, altas con local, inventarios de tiendas diferentes en la misma fecha, proveedor histórico, administrador global, asignación revocada y respuestas JSON 404/409. Estas pruebas no constituyen una prueba de carga concurrente ni validan la etapa 04.
