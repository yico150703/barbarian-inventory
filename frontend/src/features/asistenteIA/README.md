# Interfaz del asistente IA

Todo el código específico de la interfaz vive aquí: AssistantPage/AssistantWorkspace, VoiceButton, ReviewDetails, labels, CSS y service.
Ruta: /home/asistente-ia. Enlace en el menu lateral de Gestion.

Estado actual: consultas con IA, dictado mediante MediaRecorder y borradores confirmables. El texto y contexto de correcciones son temporales y se descartan al salir o cambiar sesión. Una corrección invalida la confirmación anterior; se requiere preparar una nueva propuesta. Se muestran los datos exactos y nombres de referencias antes de Realizar. Nueva consulta cancela el borrador pendiente.

Dictado requiere permiso del micrófono, navegador compatible y HTTPS o localhost. Las grabaciones terminan a los cinco minutos; tras transcribir se agregan al texto editable sin ejecutar acciones. Audio/mensajes se envían a través del backend. No almacenar claves API en este directorio ni usar variables VITE_ para secretos.

Realizar exige una propuesta vigente sin ediciones pendientes y marcar la revisión. Maneja errores sin afirmar que se guardó una operación no confirmada. Los reintentos utilizan el mismo ID de borrador. La interfaz se remonta al cambiar token para evitar mezclar datos de perfiles/locales.

Diseño de conversación vertical: encabezado compacto Barbarito, accesos plegables, mensajes del usuario a la derecha y respuestas en tarjetas. Conserva hasta diez turnos anteriores como lectura dentro de la sesión. RecipeCards presenta ingredientes/cantidades e instrucciones de recetas consultadas (hasta tres registros), sin datos de ejemplo. El resumen se edita bajo demanda. Compositor inferior con Dictar/Enviar y avisos/audio visibles, adaptable a móvil. Solo una propuesta vigente puede confirmarse; ninguna tarjeta histórica ejecuta acciones. Sin cambios de backend ni SQL para este rediseño.
