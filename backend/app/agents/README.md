# Agentes del asistente Barbarito

## Formularios de catálogo en el chat

«Crear categoría de productos», «crear proveedor» y «crear producto» abren formularios
directos mediante `/api/asistente-ia/preparar`, sin llamada al modelo ni escritura.
El especialista también dispone de `abrir_formulario` para otras expresiones de la
misma intención. Las tres skills específicas se muestran en el inspector de agentes.
`POST /formulario` actualiza opciones reales; `POST /formulario/preparar` valida los
campos y guarda únicamente una propuesta en el almacenamiento de borradores existente.
El usuario revisa y confirma en `/realizar`, que conserva los permisos, la auditoría
y la protección contra reenvíos existentes. Los formularios no requieren una clave
del proveedor de IA; las consultas libres y el dictado mantienen su configuración.
Al cambiar un campo, la interfaz exige revisar otra vez antes de confirmar.

Los formularios incluyen pasos dependientes: Productos → Categoría de productos /
Proveedor; Proveedor → Categoría de productos; Presentaciones → Categoría de carta /
Menaje. `CatalogWorkflow.tsx` conserva los valores del paso padre al abrir otro,
confirma cada requisito mediante los borradores existentes, actualiza las opciones
y retoma el padre con la referencia creada. El usuario puede volver sin crear.
Solo se muestran dependencias creables autorizadas por el backend. Si una creación
se confirma pero falla actualizar opciones, el siguiente intento únicamente retoma
el flujo; no vuelve a crear el requisito.

El agente de compras carga `modules/asistente_ia/skills/compras_eventos/SKILL.md`.
Al iniciar un pedido presenta eventos para la dirección del local activo, con sede,
período, recinto y distrito, público, edades publicadas, descripción breve y fuente.
La cercanía se señala únicamente cuando hay sustento; Santa Anita conserva su dirección
sin número y no se asume un tramo preciso. Las festividades generales se separan de
los eventos locales. Los porcentajes de compra los decide el gerente.

`orchestrator/router.py` dirige las solicitudes a Catálogo de insumos,
Inventario, Compras o uno de seis especialistas independientes definidos en
`catalog_specialists.py`: Categorías de carta, Menajes, Presentaciones de venta,
Subproductos, Recetas y Promociones. Cada uno carga su propio `SKILL.md`. El enrutamiento no
requiere otra llamada al modelo y conserva el especialista en correcciones breves.
Una nueva tarea explícita tiene prioridad sobre el borrador anterior.

Cada especialista de carta tiene un único recurso modificable. Sus dependencias
son de solo lectura: Presentaciones consulta categorías y menajes; Subproductos
consulta productos; Recetas consulta presentaciones, productos y subproductos.
Si falta un requisito y el usuario desea crearlo, `solicitar_especialista` devuelve
al Coordinador una petición estructurada con recurso, instrucción y motivo. El runtime limita los
recursos tanto en los esquemas de herramientas como al ejecutar las llamadas.
Estas restricciones se suman a los permisos de la sesión y no los amplían.

`orchestrator/communication.py` conserva una pila de tareas mediante una continuación
firmada, con vigencia de dos horas y ligada a usuario, perfil y local. Solo delega
dependencias declaradas; limita la profundidad y rechaza ciclos. Abre el formulario
del requisito o invoca al especialista cuando requiere conversación. El chat muestra
los traspasos y la tarea pendiente. Las consultas simples conservan sus atajos de formulario.
Los pedidos que mencionan requisitos faltantes pasan por el especialista.

Cada borrador dependiente queda ligado al paso firmado. Tras `/realizar`, `/continuar`
verifica en el almacenamiento que ese mismo borrador fue REALIZADO y entrega su
resultado real al especialista padre. Soporta requisitos anidados y vuelve primero
al padre inmediato. No acepta resultados de creación enviados por el navegador.
Si falla retomar tras guardar, la interfaz ofrece reintentar solo la continuación;
no vuelve a ejecutar el cambio. Nueva consulta descarta la tarea pendiente.
Promociones consulta las presentaciones existentes y solo prepara cambios en
promociones: precio, horario y grupos de opciones. Ya no pertenece al agente de insumos.

Los especialistas no escriben directamente en la base. `preparar_cambio` pasa por la validación existente, produce un borrador y exige confirmación explícita en `/realizar`. El backend vuelve a validar permisos, local y vigencia antes de ejecutar por las rutas nativas con auditoría.

Los pedidos de Salón no se exponen todavía como herramientas del asistente: usan una sesión separada y autorización PIN para acciones de responsable. No se debe reutilizar el token operativo del asistente para saltarse ese control.
