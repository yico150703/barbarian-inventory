# Contexto de Barbarito

## Unidades de medida - 10 de octubre de 2026

Productos usa un solo selector de unidad y un contenido por envase expresado
siempre en esa unidad: un barril de 30 L tiene unidad LTR y contenido 30.
La API devuelve los mismos identificadores que almacena la base migrada:
KGM (kg), LTR (L), C62 (conteo), segun UNECE Recommendation 20. Los simbolos
siguen SI/BIPM. PORCION es local y no recibe codigo UNECE. GRM (g) y MLT (mL)
se admiten como unidades de entrada en preparaciones y recetas, y se convierten
a su base con Decimal, manteniendo la precision existente de tres decimales.

La migracion database/migrations/20261010_unidades_unece.sql crea unidad_medida,
normaliza las seis tablas con columnas unidad, agrega claves foraneas y conserva
las restricciones por contexto. Cambia Kg/L/UNI/PORCION con tilde a
KGM/LTR/C62/PORCION sin tocar cantidades. Se ejecuta en una transaccion como
propietario de las tablas y puede repetirse. El codigo admite bases pendientes
de migracion: lee los identificadores antiguos, devuelve codigos estandar en la
API y conserva el formato de almacenamiento compatible hasta aplicar el SQL.
La unidad de productos existentes no se cambia arbitrariamente al editar.

El catalogo de backend/app/core/units.py define simbolos, dimensiones y factores.
GET /api/catalogos/unidades requiere permiso de consulta de productos. Las
respuestas operativas incluyen unidad_medida con los metadatos; la auditoria
historica queda intacta. Los formularios obtienen sus opciones del catalogo.

Las consultas de proveedores soportan bases con o sin proveedor_categoria.
Si falta, las categorias proceden de los productos existentes y la asignacion
explicita devuelve HTTP 503 con instrucciones; con la tabla, usan asignaciones
propias del proveedor. Esta migracion es independiente de la de unidades.

Fuentes: https://www.bipm.org/en/measurement-units,
https://unece.org/trade/uncefact/cl-recommendations,
https://vocabulary.uncefact.org/UnitMeasureCode.

Revisión: 22 de septiembre de 2026. Describe el código local, no una validación funcional completa contra la base de datos. Actualizar este documento cuando cambie la implementación.

## Propósito y arquitectura

Sistema web interno de Barbarian para gestionar inventarios, abastecimiento, catálogos y usuarios. La sesión incluye perfil, puesto laboral cuando corresponde y local activo.

- `frontend/`: React 19, TypeScript 6, Vite 8, React Router 7, iconos Lucide y CSS propio. Versiones declaradas en `package.json`.
- `backend/`: Python y Flask, JWT, Flask-SQLAlchemy, SQLAlchemy y psycopg2. Las consultas están escritas en SQL mediante `text()`; no se encontró una capa de modelos ORM.
- `database/`: dos respaldos PostgreSQL y dos diccionarios CSV. Los respaldos representan versiones anteriores al esquema que requiere el código actual.
- La raíz revisada no es un repositorio Git. No se encontraron instrucciones `AGENTS.md` en el proyecto.

Flujo habitual: página React → servicio TypeScript (`fetch`) → ruta Flask → servicio de negocio → repositorio SQL → PostgreSQL. Los servicios manejan las transacciones y registran actividades/cambios.

## Archivos de entrada

- `frontend/src/main.tsx`: arranque del cliente.
- `frontend/src/App.tsx`: rutas; pantallas protegidas bajo `/home`.
- `frontend/src/context/AuthContext.tsx`: sesión y cambios de perfil/local.
- `frontend/src/components/layout/`: menú lateral, barra superior y contenido.
- `frontend/src/services/`, `types/`, `pages/`: API, contratos y pantallas por dominio.
- `backend/run.py`: servidor local en `127.0.0.1:5000`, con depuración activada.
- `backend/app/__init__.py`: fábrica Flask y registro de módulos.
- `backend/app/core/config.py`: configuración por variables de entorno.
- `backend/app/core/permissions.py`: comprobación de permisos por opción de menú y acción.
- `backend/app/modules/<dominio>/{routes,service,repository}.py`: estructura de cada módulo.

## Funcionalidades presentes

| Dominio | Implementación observada |
| --- | --- |
| Autenticación | Usuario corporativo `barbarian.pe`, contraseña, sesión JWT, consulta de sesión, cambio de perfil y local. |
| Usuarios | Listado, creación, edición y cambio de estado; asignaciones de perfiles, puestos y locales. Formulario corregido para enviar `ids_locales`, proponer el local activo al crear y conservar asignaciones al editar. El administrador puede seleccionar varios locales. |
| Inventarios | Inicio, guardado de conteos, cierre, consulta de stock, revisión, correcciones e historial de correcciones. |
| Productos, categorías y proveedores | Consulta, creación, edición, desactivación/reactivación y comprobación de dependencias. Reasignación de productos entre categorías/proveedores. |
| Compras | Pedido sugerido, creación como borrador o enviada, historial, detalle y cambios de estado. |
| Recepciones | Pendientes agrupados por orden/proveedor, registro de factura y cantidades, historial, detalle y correcciones. |
| Movimientos | Registro de entradas/salidas por merma, préstamos, devoluciones y reposiciones de proveedores. |
| Carta | Consulta de categorías, presentaciones de venta y menajes. |
| Producción y recetas | Consulta de subproductos y grupos de salsa. Recetas permite crear/editar ítems y presentaciones con ingredientes, instrucciones, estado y opciones elegibles. |
| Promociones | Consulta de promociones y sus opciones. |
| Auditoría | Registro de actividades y cambios; endpoint de consulta. Sin pantalla específica conectada en `App.tsx`. |

Las rutas sin una pantalla concreta dentro de `/home` muestran `ModulePlaceholderPage`. La existencia de una opción en el menú no significa que tenga una implementación completa.

## Reglas relevantes

- El login selecciona inicialmente el primer perfil disponible y el primer local de la lista devuelta. El usuario puede cambiar después.
- Los permisos corresponden al perfil activo: no se suman los permisos de todos los perfiles asignados.
- El backend verifica usuario, perfil, asignación y permiso activo en la base de datos. Acciones: consultar, crear, editar, revisar, cerrar, desactivar, reactivar, eliminar y configurar.
- El perfil con ID 4 corresponde a miembro de equipo y utiliza puesto laboral. Hay IDs de opciones/perfiles fijados en el código; deben coincidir con la base de datos.
- JWT de ocho horas; el cliente guarda la sesión en `sessionStorage` y la revalida mediante `/api/auth/me`.
- Inventarios: horario de Lima, UTC−5. Se permite seleccionar ayer hasta las 09:00 de hoy. Los borradores vencidos se eliminan desde la lógica de consulta/gestión de inventarios.
- Stock: último conteo cerrado por producto + recepciones posteriores + entradas manuales − salidas manuales. Sin conteo previo, el stock es desconocido (`null`). Los movimientos se comparan por fecha.
- Pedido sugerido: consumo calculado del período × 1,20 − stock del último cierre, convertido a paquetes según presentación y redondeado al entero más próximo (fracción ≥ 0,5 sube). Puede resultar cero. El repositorio incluye una fecha inicial alternativa fija: `2026-08-30`.
- Estados de compra: `BORRADOR`, `ENVIADA`, `RECEPCION_PARCIAL`, `RECEPCIONADA`, `CERRADA_INCOMPLETA`, `CANCELADA`.
- Las recepciones validan cantidades pendientes y recalculan el estado de la orden. Existen bloqueos SQL en operaciones de recepción/corrección.
- La interfaz usa una paleta verde/crema y componentes propios; los módulos mantienen su CSS junto a las páginas.

## Base de datos y alcance por local

Entidades principales: `producto`, `categoria_producto`, `proveedor`, `inventario_cierre` y detalle, `orden_compra` y detalle, `factura_recepcion` y detalle, `movimiento_inventario` y detalle; tablas de carta, recetas, subproductos, promociones; usuarios, perfiles, menú y permisos.

Ambos respaldos comienzan por `PGDMP`: incluso `barbarito.sql` es un archivo de respaldo binario PostgreSQL, no un script SQL de texto. La inspección de sus declaraciones encontró 31 tablas en ese archivo y 36 en `barbarito_respaldo_2026-09-10.backup`. El segundo añade historiales y correcciones.

El código actual también requiere tablas como `local`, `usuario_local`, `puesto_laboral`, `usuario_puestos_laborales` y `auditoria_cambio`, ausentes de las declaraciones de ambos respaldos. No se encontraron migraciones versionadas. No se inspeccionó el esquema de una base de datos en ejecución.

El soporte de locales está presente en autenticación, usuarios y auditoría, pero las consultas operativas de inventarios, compras, recepciones y movimientos no incluyen filtros por `id_local`. Seleccionar un local todavía no implica que esos datos queden separados por sede.

## Estado verificado

- `npm.cmd run build`: pasa después de corregir el manejo de `ids_locales` en `frontend/src/pages/UsersPage.tsx`. Vite requirió ejecutarse fuera del sandbox porque este bloqueaba la creación de procesos con `EPERM`.
- `npm.cmd run lint`: finaliza con código 0, con advertencias de efectos de React, dependencias, exportaciones y expresiones sin uso.
- Los 59 archivos Python de `backend/app` pasan análisis sintáctico con `ast.parse`.
- `create_app()` se inicializa y registra 63 reglas de rutas, incluyendo la ruta estática de Flask.
- Con el cliente de pruebas de Flask: `/api/health` devuelve 200; productos, stock y usuarios devuelven 401 sin token.
- Estas comprobaciones no validan conexión/esquema de PostgreSQL ni operaciones autenticadas de extremo a extremo.
- Se añadieron 15 pruebas en `backend/tests/test_stock_limits.py`; todas pasan. Cubren permisos, asignación del local, rechazo de local enviado por el cliente, validación, protección del catálogo, auditoría y compatibilidad antes de migrar, con dependencias simuladas.

## Otros pendientes observados

- Recetas: `editor_repository.py`, `editor_service.py` y `components/recipes/RecipeEditor.tsx` incorporan edición y creación con permisos de menú 28. El listado reemplaza precio por tipo e insumos por ingredientes. Permite seleccionar ítem/presentación existente o crear un ítem de carta y una presentación. El nombre/código de inventario se busca para añadir ingredientes y opciones elegibles; quitar filas se aplica al guardar. Se preservan los subproductos existentes y los porcionados con varios ingredientes. La unidad de cada ingrediente se obtiene en el servidor desde inventario, no se acepta la enviada por el cliente.
- El tipo pertenece al ítem de carta, compartido entre sus presentaciones. Se advierte en el formulario y se bloquea convertir a Directo si otras presentaciones tienen varios ingredientes. La edición conserva los precios existentes. Las presentaciones creadas desde Recetas se guardan inactivas para venta, con precio técnico cero hasta su configuración comercial; la pantalla actual de presentaciones sigue siendo de consulta.
- `database/migrations/20260922_recetas_unidad_kg.sql` está preparado, NO ejecutado: añade Kg a las unidades permitidas de presentaciones, conservando L, UNI y PORCIÓN. El formulario consulta las unidades y tipos permitidos por las restricciones de la base, por lo que Kg aparecerá solo después de aplicar ese SQL. No depende de la migración de límites de stock.
- Verificación de Recetas: metadatos y 199 recetas leídos de la base en transacción de solo lectura. Pruebas automatizadas de validación, permisos, creación, conservación de precios y rollback con dependencias simuladas; no se crearon ni modificaron recetas reales durante la implementación. «Nuevo producto» se interpretó como nuevo ítem de carta, pendiente de una aclaración distinta del usuario.

- Límites de stock: el usuario confirmó que cada gerente configura los límites de su propia tienda. Nueva pantalla `/home/limites-stock` y API `/api/catalogos/limites-stock`, exclusivas del perfil Gerente (ID 2), opción de menú 33. La API toma el local del JWT y verifica la asignación activa a ese local; no acepta cambiarlo desde el cuerpo de la petición. Valida mínimo y máximo no negativos, máximo ≥ mínimo, hasta tres decimales y registra el local en auditoría. El catálogo rechaza intentos de escribir límites.
- Requiere aplicar la versión actualizada de `database/migrations/20260922_limites_stock.sql`: crea `producto_stock_local`, con clave compuesta producto/local, mínimo y máximo, permisos para la conexión `multi` y menú exclusivo del gerente. Copia el mínimo anterior como valor inicial independiente por cada local existente; el máximo queda sin definir. Reejecutar no sobrescribe configuraciones existentes. No modifica la estructura de `producto`. La versión inicial global falló y se revirtió; la versión por local NO se ejecutó, conforme a la instrucción del usuario.
- Stock, compras y revisión de inventarios consultarán el mínimo del local activo al existir la nueva tabla. Mientras la migración siga pendiente, conservan la lectura anterior mediante `core/stock_local.py`. Se verificaron las tres consultas en modo de solo lectura antes de migrar: devuelven 140 productos cada una. Esto separa los límites, no las cantidades y operaciones históricas, cuya separación por sede sigue pendiente.
- Pruebas del nuevo módulo, desde `backend`: `.venv/Scripts/python.exe -m unittest discover -s tests -v`.

- `backend/app/modules/inventarios/service.py` contiene dos definiciones de `_stocks_son_iguales` y una función de conversión anidada en una posición inalcanzable. Conviene limpiar duplicados al trabajar sobre ese módulo.
- `permisosDe` está duplicado entre `menuHelpers.ts` y `permissionHelpers.ts`.
- La URL base y el manejo de respuestas HTTP se repiten en varios servicios. Recetas utiliza `localhost` por defecto y los demás `127.0.0.1`.
- `backend/app/agents`, `skills` y los archivos de `tools` son estructuras vacías; no hay implementación de agentes/IA allí.
- El README existente es el de la plantilla de Vite; no documenta el negocio ni la instalación completa.

## Ejecución local prevista por los archivos

### Actualización: auditoría de normalización del 22/09/2026

- Confirmación posterior completa: inventarios, orden, recepciones y los cuatro movimientos actuales pertenecen a **Miraflores (1)**. Mapa 03 actualizado en archivo para inventarios 1–9, orden 1 y movimientos 1–4. No volver a preguntar la tienda de estos registros. 01/02 ya ejecutados por el usuario y verificados; 03/04 y adaptación del backend aún pendientes. Catálogos/proveedores/carta/recetas globales, usuarios por tienda y administrador global. No copiar operaciones a otras tiendas ni borrar inventarios para el futuro reinicio sin nueva instrucción.

- La nueva lectura real encontró **44 tablas y 84 FK**, sin huérfanos. `producto_stock_local` ya existe con 560 filas; las notas anteriores que la daban por pendiente describen un estado anterior. El asistente no aplicó esa migración en esta revisión.
- Diagnóstico completo y plan: `database/normalizacion/README.md`. Evidencia actual y herramienta reproducible de solo lectura: `auditoria_actual.json` y `auditar.py` en esa carpeta.
- Cuatro SQL preparados, **ninguno ejecutado**: 01 corrige reposiciones, Kg y secuencia de menú (siguiente 33 ya ocupado); 02 añade local operativo y proveedor histórico de compra; 03 exige mapa histórico y backend adaptado; 04 retira campos redundantes tras adaptar sus consumidores. 03/04 incluyen una confirmación desactivada que impide ejecutarlos accidentalmente.
- Sigue pendiente confirmar a qué tienda pertenecen los inventarios, orden y movimientos históricos. No se asignó Barranco ni otro local por suposición. La separación operativa por local y el retiro de campos NO están implementados en el backend; sus requisitos están detallados en el informe.

- Backend, desde `backend`: `.venv/Scripts/python.exe run.py`.
- Frontend, desde `frontend`: `npm.cmd run dev`.
- Variables del backend: `DATABASE_URL`, `SECRET_KEY`, `JWT_SECRET_KEY`.
- Variable del frontend: `VITE_API_URL`; alternativa habitual `http://127.0.0.1:5000/api`.

Existen archivos `.env`; este documento no copia sus valores. Tras el análisis, se corrigió el formulario de usuarios a petición del usuario. No se modificaron registros de negocio. Sigue pendiente la separación operativa por sede. El backend restringe a los gestores no administradores a enviar únicamente el local activo; editar usuarios asignados a varias sedes requiere un administrador con las autorizaciones correspondientes.


## Adaptaci?n operativa por local terminada (22/09/2026)

- Backend y frontend adaptados para 01?03; 03 probado en PostgreSQL temporal y archivo habilitado (`true`), todav?a NO aplicado en la base real. Abrir el archivo guardado, no Untitled-1 antiguo. Instrucciones: database/normalizacion/ACTIVAR_AHORA.md.
- Nuevo core/local_scope.py valida usuario/perfil/local vigente (administrador global), comprueba migraci?n 03, inyecta par?metro local y protege accesos por ID. Repositorios de inventarios/compras/recepciones/movimientos filtran operaciones y guardan local en cabeceras. Proveedor pactado en detalle de compra. Correcciones de recepci?n bloquean orden.
- Autenticaci?n permite todas las tiendas activas al perfil administrador; otros perfiles requieren asignaci?n. Gesti?n de usuarios global para administrador y por local para otros; auditor?a filtrada por local salvo administrador. Respuestas HTTP JSON.
- MainLayout desmonta Outlet al cambiar sesi?n/local/perfil; mantiene URLs/puerto/conexi?n originales.
- SQL03 corrige FK inv?lida de tabla temporal e ?ndice redundante ux_inventario_cierre_fecha. Mapa completo de 14 operaciones a Miraflores, recepci?n por orden. SQL04 permanece bloqueado: sus campos todav?a son usados.
- Verificaci?n: 40 pruebas correctas en runner backend/tests/run_local_scope_integration.py (31 anteriores+9 integraci?n), build frontend correcto. No prueba visual de navegador ni prueba de carga concurrente. Datos reales intactos; servidor temporal detenido.


## Opciones de salsa integradas en Recetas

- Se retiro Grupos de salsa del menu devuelto por autenticacion y del arbol frontend (incluye sesiones antiguas). /home/grupos-salsa redirige a /home/recetas. El editor de recetas conserva grupos, cantidades, limite de elecciones y repeticion. No se borraron datos ni tablas, ni se requiere SQL para este cambio. El endpoint de consulta antiguo permanece por compatibilidad.


## Editor de subproductos (22/09/2026)

- Subproductos permite crear y editar con permisos de opcion 12, codigo SP automatico, nombre, rendimiento/unidad, instrucciones y estado. Ingredientes de inventario buscables por nombre/codigo, cantidad editable, unidad del catalogo y eliminacion de filas; componente visual compartido con Recetas.
- Nuevas rutas: GET /api/produccion/subproductos/formulario, POST /api/produccion/subproductos, PUT /api/produccion/subproductos/<id>. Se conservan el listado y el detalle anteriores y se muestran instrucciones.
- Guardado atomico con auditoria, bloqueo para codigos/nombres, validaciones de cantidades y duplicados, conservacion de ingredientes antiguos inactivos. No permite cambiar unidad base de un subproducto existente ni desactivar uno usado por recetas activas.
- Subproductos siguen compartidos entre tiendas. No requiere SQL ni se modificaron registros reales. La lectura actual confirma que el usuario YA aplico la etapa 03 (uq_inventario_local_fecha existe); 04 sigue sin autorizarse.
- Compilacion frontend correcta y 47 pruebas aprobadas en PostgreSQL temporal, incluidas 7 nuevas de subproductos. Sin prueba visual automatizada en navegador. Evidencia: database/normalizacion/VALIDACION_SUBPRODUCTOS_20260922.txt.

## Administracion de categorias de carta (22/09/2026)

- Tabla lineal con acciones solo para administrador y permisos vigentes de opcion 8. Editar nombre/prefijo y desactivar exigen cero articulos asignados, incluidos inactivos. Reactivar disponible.
- Reasignar mueve todos los articulos a otra categoria activa, conservando codigos, recetas y presentaciones. Confirmacion en formulario, validacion backend y auditoria atomica. Prefijos editados reservan los numeros de codigos antiguos aun existentes.
- Endpoint POST /api/carta/categorias/<id>/<accion>. No requiere migracion ni se alteraron datos reales. Permisos reales del administrador comprobados en solo lectura.
- Build frontend correcto; 52 pruebas aprobadas en PostgreSQL temporal (5 nuevas). Evidencia VALIDACION_CATEGORIAS_CARTA_20260922.txt. Sin verificacion visual de navegador.

## Flujo Carta antes de Recetas (22/09/2026)

- Carta / Presentaciones de venta permite crear articulo + presentacion o elegir articulo existente y agregar presentacion. Editar administra nombre/tipo compartidos, contenido, unidad, menaje, precio y estado de venta. Categoria de articulo existente se reasigna desde Categorias de carta. Permisos vigentes de opcion 9.
- Nuevas rutas GET /api/carta/presentaciones/formulario, POST /api/carta/presentaciones y PUT /api/carta/presentaciones/<id>. Guardado atomico con auditoria, duplicados y tipos/unidades validados. Alta de presentacion de articulo existente no permite modificar nombre/tipo con solo permiso crear.
- Recetas solo crea sobre id_presentacion_venta existente sin receta (incluye presentaciones fuera de venta). Selector excluye recetas activas e inactivas. No crea articulos/presentaciones ni modifica datos comerciales; muestra tipo, contenido y menaje como lectura. Edita ingredientes, instrucciones, opciones y estado de receta. Estados de venta y receta independientes.
- Se conserva una receta por presentacion y la unicidad de presentaciones existentes en PostgreSQL. No hace falta SQL. No se modificaron datos reales.
- Build correcto y 58 pruebas aprobadas en PostgreSQL temporal, incluidas pruebas nuevas del flujo. Evidencia database/normalizacion/VALIDACION_FLUJO_CARTA_RECETAS_20260922.txt. Sin validacion visual de navegador. Al cambiar contenido/unidad en Carta, revisar manualmente ingredientes: no hay escalado automatico.

### Ajuste de asignacion de categoria y editor de receta

- Editar presentacion permite cambiar categoria del articulo a otra activa; afecta todas sus presentaciones, conserva codigo y recetas y registra auditoria. Crear presentacion de articulo existente no modifica sus datos compartidos.
- Recetas retira los campos duplicados de tipo, contenido, menaje y estado. Usa el tipo registrado para validar ingredientes y mantiene identificacion de presentacion en encabezado. Guardar sin estado conserva el estado interno previo; no reactiva recetas antiguas silenciosamente. El estado de venta sigue editandose en Carta.
- Build correcto y 59 pruebas aprobadas en PostgreSQL temporal. No requiere SQL ni se modificaron datos reales.

## Gestion de menajes (22/09/2026)

- Menajes permite crear, editar nombre, desactivar, reactivar y eliminar con perfil administrador y permisos vigentes de opcion 10. Desactivar/eliminar bloqueados si existe cualquier presentacion asignada, incluso inactiva; cambiar menaje de esas presentaciones desde Carta para liberarlo. Detalle desplegable conservado.
- Backend valida nombres duplicados, referencias, permisos y registra auditoria en la misma transaccion. Al guardar presentaciones se bloquea lectura del menaje para evitar asignacion concurrente durante desactivacion/eliminacion.
- No requiere SQL; permisos reales de administrador comprobados en solo lectura. Build correcto y 62 pruebas aprobadas en PostgreSQL temporal. Evidencia VALIDACION_MENAJES_20260922.txt. No datos reales modificados ni validacion visual de navegador.

## Editor de promociones (22/09/2026)

- Promociones permite crear y editar con permisos de opcion 14. Codigo P automatico, nombre, precio, estado y horario opcional (ambas horas; admite cruce de medianoche).
- Grupos con cantidad a elegir, repetir, buscador por nombre/codigo de presentaciones de Carta, agregar/quitar opciones y grupos. No utiliza productos de inventario. Preserva IDs de grupos y opciones existentes; opciones antiguas inactivas pueden conservarse en su grupo, nuevas solo activas.
- Backend transaccional con auditoria, validacion de cantidades, duplicados, pertenencia de grupos, precios y horas. Rutas GET /api/promociones/formulario, POST /api/promociones, PUT /api/promociones/<id>.
- No requiere SQL ni se cambiaron datos reales. Build correcto y 66 pruebas aprobadas en PostgreSQL temporal. Evidencia VALIDACION_PROMOCIONES_20260922.txt. Sin validacion visual de navegador.

## Alta de categorias y estilos de encabezado

- Categorias de carta incorpora Nueva categoria (nombre/prefijo), con permiso crear de opcion 8 y perfil administrador. POST /api/carta/categorias; valida duplicados y audita en transaccion. Activa al crear.
- CSS de Subproductos y Promociones aplica a los botones dentro del contenedor de acciones, con estados hover/focus/disabled y ajuste movil. Antes el selector de hijos directos dejaba esos botones sin estilo.
- No requiere SQL. No se modificaron datos reales.

## Eliminacion de registros de catalogos

- Boton Eliminar con confirmacion para productos, categorias producto/carta, proveedores, presentaciones, subproductos, recetas y promociones. Menajes conserva su flujo existente. Permiso eliminar por opcion validado tambien en backend; administrador ya tiene esos permisos (lectura real).
- DELETE /api/eliminaciones/<entidad>/<id> usa lista cerrada de entidades y revisa FK entrantes antes de borrar, bloqueando dependencias activas/inactivas e historicas. Se eliminan solo configuraciones propias: stock local de producto sin uso, detalle receta/subproducto y grupos/opciones de promocion. No borra productos ingredientes ni articulos al borrar presentaciones. Auditoria atomica; error revierte todo.
- No requiere SQL. Build correcto y 72 pruebas aprobadas en PostgreSQL temporal; evidencia VALIDACION_ELIMINACIONES_20260922.txt. Datos reales intactos. Sin prueba visual de navegador.

## Administrador sin Stock/Inventarios ni selector de local

- Opciones 15/16/17/18 solo para perfiles operativos 2/3/4 y sus permisos existentes. Backend filtra menu y deniega endpoints al administrador incluso con permisos antiguos. Frontend filtra sesiones anteriores y redirige rutas directas de stock/inventarios a Inicio.
- Topbar muestra selector/nombre del local solo a perfiles 2/3/4. Cambiar local por API bloqueado para administrador. Se mantiene contexto interno de autenticacion para compatibilidad con cambio de perfil y otros modulos.
- Inicio no consulta inventarios si el perfil no tiene acceso; administrador ve bienvenida general. No se cambiaron permisos de perfiles operativos ni otros modulos.
- Sin SQL ni datos reales modificados. Build correcto y 73 pruebas aprobadas en PostgreSQL temporal. Evidencia VALIDACION_PERFILES_20260922.txt.

## Seguimiento de movimientos (2026-09-22)
Implementados prestamos entre locales con salida inmediata y entrada al aceptar el destino; devoluciones a proveedor con guias y reintegros parciales por producto. Nuevas tablas movimiento_seguimiento y movimiento_reintegro; fecha registrado_en en movimiento para movimientos posteriores al cierre del mismo dia. Stock sin conteo admite entradas efectivas. Pantalla /home/movimientos/seguimiento con permisos de opcion 20 y enlace en menu. Administrador bloqueado tambien en movimientos/compras/recepciones; se conservan permisos existentes de gerente y supervisor. Entradas manuales PRESTAMO_RECIBIDO/REPOSICION_PROVEEDOR bloqueadas: se generan desde guia original.
PENDIENTE USUARIO: ejecutar database/migrations/20260922_seguimiento_movimientos.sql una vez como propietario. NO se ejecuto en la base real. Instrucciones en README_seguimiento_movimientos.md. Movimientos antiguos no se convierten en pendientes. Frontend build OK y 77 pruebas PostgreSQL temporal OK; evidencia database/normalizacion/VALIDACION_MOVIMIENTOS_20260922.txt.

## Actividades del sistema (2026-09-23)
Pagina /home/actividades conectada a GET /api/actividades/historial (permiso 26 consultar). Admin consulta marca completa, local especifico o registros sin local; otros perfiles solo local activo con validacion en backend. Filtros de texto y fechas, paginacion 50, usuario autor, perfil/puesto, usuario afectado en modulo USUARIOS, fecha y detalle antes/despues cuando auditoria_cambio los conserva. Eventos actividad y cambio separados, sin asociaciones historicas inferidas. Campos sensibles excluidos recursivamente de JSON. Nuevas acciones admin sin local explicitamente indicado se registran globales; historicos conservados. No requiere SQL ni modificaciones de la base real. Build correcto y 80 pruebas en PostgreSQL temporal aprobadas, evidencia VALIDACION_ACTIVIDADES_20260923.txt.

## Ruido de actividades (2026-09-23)
Por solicitud del usuario, cambiar perfil activo ya no inserta actividad CAMBIAR_PERFIL en auth/service.py. Los registros historicos de esa accion se excluyen de ambas consultas de actividades, sin borrarlos de la base. Navegar por menus ya no generaba registros. Se conservan auditorias de modificaciones administrativas, accesos y cambios de local. Validacion de sintaxis AST correcta; no requiere SQL.

## Acceso rapido Salon (2026-09-23)
Login ofrece Gestion e inventario y Salon. Implementacion inicial local + usuario + PIN, planteada al usuario como supuesto tras pregunta opcional sin respuesta. No se admite PIN como contraseña de Gestion. Solo perfil miembro 4 y puestos activos Mesero/Bartender, usuario/local/asignaciones activos. Usuarios puede asignar/reemplazar/revocar PIN bajo sus permisos existentes, campo opcional; vacio conserva. Hash werkzeug, limite usuario e IP en PostgreSQL. Tokens tipo salon separados por pestaña y 2 horas, version+fecha invalidan al rotar/revocar; /api/salon/me valida elegibilidad vigente. /salon es solo bienvenida, menu pendiente. No registrar PIN en auditoria.
PENDIENTE USUARIO: ejecutar una sola vez database/migrations/20260923_acceso_salon.sql en barbarito como propietario; NO ejecutado en base real. README_acceso_salon.md contiene instrucciones. Hasta entonces gestion habitual sigue disponible y Salon devuelve aviso de migracion pendiente. Build OK y 84 pruebas temporales aprobadas en VALIDACION_SALON_20260923.txt.

## Pedidos Salon (2026-09-23)
Mapa M01-M10/B01-B05 abre /salon/mesa/:mesa. Carta activa por categoria, nombre/formato/precio, busqueda nombre; lista lateral editable con cantidades, opciones del grupo de salsa (maximo/repeticion por unidad) y comentarios por linea. Borrador persistente con boton guardar y al volver usando boton del encabezado; advertencia antes de cerrar con cambios. Enviar bloquea pedido completo en API y triggers. Captura precio/nombre/opciones historicos, control de version evita sobreescritura, aislamiento local+usuario y bloqueo advisory por mesa. Listar mesas trae solo pedidos propios guardados. Borrador vacio guardado libera mesa. NO se implemento cobro/cierre/liberacion de enviada, cocina, impresion ni descuento de stock; siguiente etapa pendiente.
PENDIENTE USUARIO: ejecutar database/migrations/20260923_pedidos_salon.sql una vez como propietario. NO aplicado a base real. Requiere acceso Salon anterior para iniciar sesion. README_pedidos_salon.md explica ejecucion y alcance. Build OK; 88 pruebas temporales OK, evidencia VALIDACION_PEDIDOS_SALON_20260923.txt.

## Envios adicionales de Salon (2026-09-23)
Reemplaza el flujo anterior de pedido unico: tocar producto suma una unidad pendiente; seleccionar linea habilita comentario/borrar solo antes de enviar. Sin boton guardar borrador; Cancelar descarta pendientes. Permite nuevos envios inmutables por mesa y agrupa la vista de enviados solo si presentacion, nombre, precio, opciones y comentario coinciden. UUID y hash impiden duplicar reintentos. Borradores antiguos siguen compatibles y Cancelar elimina solo el borrador. No hay cierre/cobro ni cocina ni consumo de stock todavia.
PENDIENTE USUARIO: ejecutar database/migrations/20260923_envios_adicionales_salon.sql despues de pedidos_salon, una sola vez como propietario en barbarito. No ejecutado sobre base real. Build frontend OK y 90 pruebas PostgreSQL temporal OK. Evidencia VALIDACION_ENVIOS_SALON_20260923.txt.

## Distribucion de Salon por gerente (2026-09-23)
Nueva ruta /home/opciones-salon solo perfil Gerente; acceso backend exige perfil 2 y local vigente asignado. Editor de mapa con arrastre, campos de posicion/ancho/alto, agregar mesas y puestos, barra redimensionable. Mapa compartido SalonMap usado por SalonPage. Distribucion persistida por local como JSON validado, version optimista y bloqueo advisory compatible con registro de pedidos; no permite quitar mesas con pedidos. Mantiene mapa inicial 10 mesas/5 puestos si no hay configuracion. Codigos de mesa dinamicos, no renombrables. Cambio de perfil/local desmonta editor para evitar mezclar respuestas. Barra y puestos se ajustan individualmente.
PENDIENTE USUARIO: ejecutar database/migrations/20260923_distribucion_salon.sql una vez como propietario, despues de pedidos/envios. No aplicado en base real. README_distribucion_salon.md contiene instrucciones. Build OK y 94 pruebas PostgreSQL temporal OK; sin prueba visual automatizada. Evidencia VALIDACION_DISTRIBUCION_SALON_20260923.txt.

## Control de Salon y consola (2026-09-23)
SalonPage ajustado a alto disponible, encabezado Salon/local, acciones inferiores e informacion de responsable/fecha por mesa; lista propia en modal. Pedido: Cancelar/Borrar/Comentario/Salir/Enviar abajo; Cancelar y enviar exitoso regresan al mapa, Salir al login. Gerente/supervisor ahora elegibles PIN sin exigir puesto mesero; formulario Usuarios y acceso actualizados. Perfil Salon efectivo 2/3/4 segun perfiles vigentes, sin privilegios de gestion por token Salon.
Gerente y supervisor consultan mesa ajena solo lectura y pueden anular lineas enviadas tras reautenticarse con PIN. Miembros solo sus pedidos. Gerente puede autorizar traslado de pedidos a mesa libre y reasignacion a miembro activo del local con PIN. Autorizacion separada 2 minutos/una operacion, ligada a usuario/local/accion/version+fecha de PIN, con contador de fallos. No se modifican pedidos enviados: vista salon_pedido_actual resuelve asignacion y salon_linea_anulada conserva anulaciones. Historial auditable y total sin anulados. Traslados usan bloqueos mapa/mesa y no modifican distribucion fisica. Borradores antiguos deben enviarse/cancelarse antes de mover.
PENDIENTE USUARIO: database/migrations/20260923_control_salon.sql despues de distribucion, NO aplicado en base real. Asignar PIN desde Usuarios a responsables. README_control_salon.md documenta permisos y limites. No cobro/cierre/cocina/impresion. Build OK, 102 pruebas temporales OK. No validacion visual automatizada. Evidencia VALIDACION_CONTROL_SALON_20260923.txt.

## Apartado Asistente IA (base separada)
Creada opcion lateral Asistente IA /home/asistente-ia. Frontend aislado en frontend/src/features/asistenteIA; backend en backend/app/modules/asistente_ia con routes, README, skill y tests propios. Unicos enlaces externos: App.tsx, Sidebar.tsx y registro blueprint app/__init__.py. GET /api/asistente-ia/estado revalida sesion con auth y lista solo enlaces consultables del alcance; inventarios y operaciones excluidos. Pantalla permite editar instruccion temporal, sin guardar ni enviar. IA, dictado, borradores automaticos y Realizar TODAVIA NO implementados, explicitamente pendientes en interfaz. No claves ni llamadas a proveedores ni SQL. Skill es especificacion futura, no agente activo. Build OK y 3 tests unitarios del modulo OK.

## Asistente IA conectado (2026-09-23; reemplaza el estado de preparación anterior)

Formato de respuestas actualizado 2026-09-28: mantener la estética de tarjetas en todas las respuestas, incluido el historial. AnswerContent y FormattedAnswer renderizan títulos, negritas, listas y tablas sin HTML crudo; recetas conservan RecipeCards, stock usa tarjeta por categoría con disponible/mínimo/faltante, páginas consultadas combinadas y aviso si falta mostrar productos. Retirado «Ver registros consultados» de la interfaz. Preservar explicaciones y avisos del asistente; no volver a mostrar asteriscos Markdown como texto sin formato. TypeScript, lint, build y comprobación de render estático aprobados.

Implementadas consultas con OpenAI Responses, dictado vía transcripción, contexto temporal para correcciones, resumen editable, propuesta exacta y confirmación Realizar. Modelo por defecto gpt-6-luna; transcripción gpt-4o-mini-transcribe. Clave en backend/.env sin cambios ni exposición. Conexión real y ciclo de herramienta verificados usando solo datos ficticios. Skill de operaciones cargada en cada preparación. Backend limita recursos/campos, revalida sesión y reutiliza rutas nativas con permisos, validaciones y auditoría.

Consultas por permisos; altas/ediciones de catálogos solo administrador con permisos. Usuarios solo consulta de campos no sensibles; gestión de usuarios, eliminaciones y reasignaciones masivas fuera del asistente. Inventarios y operaciones de tienda/salón excluidos. Receta exige presentación existente y cada paso requiere confirmación. Borradores persistentes ligados a usuario/perfil/local, veinte minutos para confirmar, reintentos de confirmación sin repetir éxitos y estado EJECUTANDO ante resultado incierto.

PENDIENTE USUARIO: ejecutar database/migrations/20260923_asistente_ia.sql en barbarito y reiniciar backend. NO aplicado en base real. Sin la migración consultas y dictado disponibles, propuestas de escritura no. Informe completo en database/normalizacion/INFORME_ASISTENTE_IA_20260923.md. Validación: 116 pruebas PostgreSQL temporal y 3 unitarias aprobadas; build, TypeScript y lint del módulo correctos. Micrófono real y validación visual manual pendientes. Código de interfaz/backend concentrado en las carpetas del asistente.

## Cobros de Salón (2026-09-26)
Implementado Pagar en el pedido, formulario de tipo de comprobante y efectivo/tarjeta, RUC/razón social o DNI/nombres, Cancelar a la cuenta y comprobante visual SVG con Regresar al mapa y Salir al login. Formato sin ceros decimales sobrantes para presentaciones y nombres antiguos. Backend salon_payments.py y frontend features/salonPayments separados.
Cobro interno, salida VENTA_SALON y cierre de mesa atómicos. Precios del pedido enviado, sin anulaciones; recetas vigentes al cobrar, subproductos según rendimiento y opciones seleccionadas. Solo descuenta del local autenticado al emitir. UUID, huella de cuenta y bloqueos evitan reintentos duplicados y cobros sobre cuentas modificadas. Pedidos pagados conservados fuera de salon_pedido_actual; mesa reutilizable. Falta de receta bloquea el cobro. Mantiene política existente que permite saldo de stock negativo.
PENDIENTE USUARIO: ejecutar database/migrations/20260926_pagos_salon.sql una sola vez en barbarito después de las migraciones previas, reiniciar backend y recargar frontend. NO aplicado a base real. Por ahora comprobantes INTERNOS SIN VALIDEZ TRIBUTARIA: falta definir proveedor e integrar emisión a SUNAT. Tarjeta registra un pago recibido por POS, no procesa una tarjeta. README_pagos_salon.md detalla alcance y activación. 125 pruebas temporales OK (9 de pagos), build frontend OK, lint del nuevo módulo OK; validación visual manual pendiente. Evidencia VALIDACION_PAGOS_SALON_20260926.txt.
## Inventario operativo, jornadas y conteos (2026-09-26)
Actualización 2026-09-28, agente: Asistente IA incluye especialización de inventario en el mismo chat/dictado. Adaptadores en backend/app/modules/asistente_ia/inventory.py y skill inventario/SKILL.md. Consulta stock/mínimos, rondas/avance, diferencias, asignaciones, jornadas y mix con sesión/local/permisos nativos. Gerente puede preparar apertura y asignación por puesto; gerente/supervisor guardar y cerrar revisión completa con correcciones explícitas. Todas las escrituras requieren borrador + Realizar, revalidan versiones/datos y preservan originales; nunca ajustan stock ni cierran jornadas. Miembros solo ven sus conteos sin teórico/diferencias. No requiere otra migración ni clave. Sustituye la exclusión anterior de inventarios del asistente. Informe: database/normalizacion/INFORME_AGENTE_INVENTARIO_20260928.md. Validación mediante PostgreSQL temporal y proveedor simulado; no se llama al proveedor ni se cambia inventario real al probar.
Regla vigente posterior: SOLO el gerente abre nuevas rondas mediante «Abrir conteo para el equipo». Miembros/supervisor rechazados en backend aunque exista un permiso antiguo de creación. Miembros esperan apertura y cuentan lo asignado a su puesto; gerente/supervisor revisan. La revisión permite editar varias cantidades, observación opcional bajo botón y un único «Guardar y cerrar revisión», atómico, con versiones e historial. Sustituye las descripciones anteriores de apertura por miembros y guardado de revisión por fila. No requiere otra migración.
Actualización 2026-09-28: la asignación habitual es POR PUESTO (Cocina, Bartender, Mesero), no por persona. Pestaña Asignación por puesto en Real vs. teórico, disponible al gerente antes de iniciar rondas. Configuración independiente por local/producto, ventana con filtros, checks y guardado masivo. Próximas rondas copian la configuración; rondas anteriores conservan asignaciones personales. Miembros pueden iniciar una ronda si tienen productos para su puesto activo; cualquier miembro del mismo puesto puede guardar avances con historial de usuario/perfil/puesto/hora y control de versión. Hecho bloquea el conteo original y exige revisión para corregir. Pendiente ejecutar manualmente 20260928_asignacion_conteos_puestos.sql DESPUÉS de jornadas_conteos, reiniciar y renovar sesión. No aplicado a la base real. Informe: database/normalizacion/INFORME_ASIGNACION_PUESTOS_20260928.md.
Reemplaza las opciones Realizar/Revisar inventarios por Cerrar día, Mix de ventas y Real vs. teórico; conserva Stock actual y mínimos/máximos. Inicio ya no consulta cierres antiguos. Backend operativo.py y frontend features/inventoryOperations; opciones 36/37/38 con permisos por perfil y local.
Migración 20260926_jornadas_conteos.sql captura stock vigente como saldo inicial, crea libro de eventos con triggers para movimientos y recepciones y vista de stock teórico usada también por compras. Ventas siguen descontando al emitir. Jornadas por local persisten pasada medianoche hasta cierre manual de gerente/supervisor. Reporte congelado con saldo inicial/entradas/salidas/motivos/final y ventas; se exige resolver mesas pendientes. Nueva operación abre siguiente jornada si no hay una abierta. Mix por fecha operativa y hora de cobro en Lima, selección múltiple, agrupación horaria y ranking; ventas históricas sin jornada usan fecha calendario.
Conteos físicos bajo indicación del gerente, una ronda abierta/local; referencia teórica fijada al iniciar. Asignación por producto; miembros solo sus asignados, avance o Hecho. Gerente/supervisor conserva original y revisa/corrige con observación, luego justifica diferencias positivas/negativas por fecha y top 5/10/15/20. Historial de cada cambio y versión optimista. Ni contar ni justificar ajusta stock. Finalizar exige todo revisado. Escrituras de cierres anteriores bloqueadas tras migrar; históricos conservados.
PENDIENTE USUARIO: ejecutar database/migrations/20260926_jornadas_conteos.sql después de pagos_salon, reiniciar backend y volver a iniciar sesión. NO aplicado en base real. Informe en database/normalizacion/INFORME_INVENTARIO_OPERATIVO_20260926.md. 125 pruebas previas y 8 nuevas posteriores a migración aprobadas en base temporal; build/TypeScript/lint del módulo correctos. Sin verificación visual manual. Evidencia VALIDACION_INVENTARIO_OPERATIVO_20260926.txt.
