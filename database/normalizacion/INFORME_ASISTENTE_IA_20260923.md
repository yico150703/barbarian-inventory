# Informe de implementación — Asistente IA

Fecha: 23 de septiembre de 2026.

La pantalla del asistente está conectada a OpenAI. Se implementaron consultas con datos reales autorizados, dictado, revisión editable, correcciones y confirmación de un cambio por vez. La conexión real respondió correctamente con la clave del backend, sin mostrarla ni enviar datos del negocio en las pruebas externas.

## Qué permite

| Función | Comportamiento |
| --- | --- |
| Consultar | Productos, categorías de productos y carta, proveedores, presentaciones, menajes, subproductos, recetas, promociones y usuarios; según perfil y permisos vigentes. |
| Dictar | Grabación de hasta cinco minutos. Al detener, se transcribe y agrega al texto editable; todavía no se ejecuta nada. |
| Preparar | La IA interpreta la petición, consulta registros y propone un cambio concreto. Si faltan datos debe solicitarlos. |
| Corregir | Se puede editar el resumen o añadir instrucciones por texto/voz. Se prepara otra propuesta y se cancela la anterior. |
| Realizar | Requiere revisar los datos exactos, marcar la casilla y confirmar. El backend vuelve a validar permisos y utiliza los servicios existentes. |
| Flujo de receta | Primero artículo y presentación de carta. Después receta para esa presentación. Cada creación se confirma por separado. |
| Datos que se conservan | Cambiar solo precio conserva los demás datos comerciales; cambiar instrucciones conserva componentes y opciones de la receta. |

Las altas/ediciones de catálogos se permiten solo al administrador del sistema con el permiso correspondiente. Gerente, supervisor y miembros conservan únicamente las consultas que su perfil permite. La voz no concede permisos adicionales.

Los cambios habilitados son crear/editar productos, categorías de producto/carta, proveedores, presentaciones, menajes, subproductos, recetas y promociones. Las eliminaciones, reasignaciones masivas y gestión de usuarios/credenciales siguen en sus formularios. Usuarios en el asistente es solo consulta de nombre, perfiles, puestos, locales y estado; no transmite DNI, correo, teléfono, contraseña ni PIN.

## Activación pendiente a cargo del usuario

1. Ejecutar `database/migrations/20260923_asistente_ia.sql` en la base **barbarito**, con una cuenta propietaria/autorizada. No se ejecutó en la base real.
2. Reiniciar el backend para cargar el código y las variables de entorno.
3. Recargar el frontend y abrir **Asistente IA** en el menú de Gestión.
4. Probar primero una consulta: «Lista las presentaciones de cerveza de barril y sus precios».
5. Con perfil administrador, preparar un cambio concreto, revisar los datos y confirmar solo si se desea guardarlo.

La clave ya está configurada y fue comprobada. No se requieren paquetes adicionales. Sin la migración funcionan consultas/dictado, pero no se pueden guardar propuestas para confirmar cambios.

## Organización del código

- `backend/app/modules/asistente_ia/provider.py`: OpenAI Responses y transcripción, claves solo en servidor y errores sanitizados.
- `agent.py`: instrucciones, contexto de correcciones, herramientas y máximo de siete respuestas por preparación.
- `tools.py`: recursos/campos permitidos, consultas nativas, preparación y ejecución mediante las rutas ya existentes.
- `drafts.py`: registro persistente de borradores, usuario/perfil/local, vencimiento, cancelación y prevención de reejecución.
- `routes.py`: endpoints autenticados de estado, preparación, confirmación, cancelación y transcripción.
- `skills/operaciones_catalogo/SKILL.md`: reglas de operación que ahora carga el agente.
- `frontend/src/features/asistenteIA/`: interfaz, grabación, transcripción, resumen, revisión, enlaces de consulta y mensajes de estado.
- `backend/tests/test_asistente_ia.py`: pruebas de integración nuevas.
- `backend/tests/run_local_scope_integration.py`: aplica la migración únicamente en la base temporal de pruebas.

Se actualizaron los README del módulo y el contexto del proyecto. No se modificó `.env`, ni se añadieron secretos al frontend, al informe o a la auditoría.

## Validación realizada

- **116 pruebas de integración aprobadas** en PostgreSQL temporal, incluyendo 14 del asistente y las regresiones existentes.
- **3 pruebas unitarias de estado/acceso aprobadas**.
- Compilación del frontend: `npm run build`, correcta; comprobación TypeScript posterior, correcta.
- Lint de `src/features/asistenteIA`: sin avisos después de separar las etiquetas compartidas.
- Prueba real mínima de OpenAI: `OPENAI_CONNECTION_OK`.
- Prueba real de ida y vuelta con una herramienta y un artículo ficticio: `OPENAI_TOOL_ROUNDTRIP_OK`.
- La suite verifica: preparar sin escribir catálogos; confirmar una sola vez; permiso revocado; otra sesión/local; vencimiento/cancelación; corrección; registro cambiado; errores nativos; exclusión de inventario/rutas arbitrarias; consulta acotada de usuarios; transcripción simulada; y creación de presentación seguida de receta y ediciones parciales.
- Se probó que un resultado de escritura incierto no vuelve a ejecutarse automáticamente.

La base temporal parte del esquema sin registros reales y usa datos ficticios. No se aplicaron migraciones ni cambios de negocio en la base real. El log de la suite se conserva en `VALIDACION_ASISTENTE_IA_20260923.txt`.

## Límites conocidos

- No se realizó prueba visual automatizada del navegador ni grabación real de micrófono. La transcripción se comprobó en integración con respuesta simulada; debe probarse con el micrófono del equipo. Requiere HTTPS o localhost y permiso del navegador.
- Las peticiones y los registros consultados necesarios se envían a OpenAI. El audio se envía para transcripción y no se guarda en el backend. Las respuestas utilizan `store=false`.
- Modelo por defecto: `gpt-6-luna`. Dictado: `gpt-4o-mini-transcribe`. Se pueden configurar con `OPENAI_MODEL` y `OPENAI_TRANSCRIPTION_MODEL` en el backend; la prueba real verificó el modelo de texto, no la disponibilidad del modelo de transcripción.
- La conversación es temporal; los borradores/resultados sí se conservan en PostgreSQL. Vencen para confirmación a los veinte minutos. No se agregó limpieza automática de ese historial.
- Si el proceso se interrumpe durante una escritura, el borrador puede quedar `EJECUTANDO`; se debe revisar el módulo y la auditoría antes de crear otra propuesta. No se reintenta automáticamente una escritura de resultado incierto.
- Una confirmación procesa una operación. No se implementó ejecución automática de cadenas completas ni transacción global de varias operaciones.
- El límite de ocho solicitudes por usuario/minuto es por proceso. Un despliegue con varios workers requerirá un limitador compartido. Los costos dependen del texto/audio y las llamadas necesarias; no se prometen consultas de precio fijo.
- Inventarios, stock, compras, movimientos, recepciones y operación del salón quedan fuera de las herramientas del asistente.

Referencias de implementación: [Function calling](https://developers.openai.com/api/docs/guides/function-calling) y [Transcripción](https://developers.openai.com/api/docs/guides/speech-to-text).

## Corrección del dictado sin texto (23 de septiembre)

Se detectó que el backend admitía respuestas vacías como éxito y que el frontend colocaba los errores únicamente arriba, fuera de la zona visible al desplazarse. Ahora la respuesta debe contener texto no vacío; los errores y la confirmación aparecen junto a Dictar. Se agregó reproducción local de la última grabación para comprobar qué captó el micrófono, validación de audio vacío y un tiempo máximo de espera en la interfaz. Las URL temporales de audio se liberan al reemplazar la grabación o salir.

Se probó el servicio real de transcripción con un WAV sintético en español: devolvió «Quiero consultar los productos de la carta». Esto verifica la disponibilidad del modelo de transcripción; no permite determinar qué ocurrió con el micrófono del usuario en el intento original. Siete pruebas unitarias (cuatro nuevas de transcripción y tres de estado) aprobadas y build correcto. No requiere SQL adicional. Reiniciar backend y recargar frontend.
