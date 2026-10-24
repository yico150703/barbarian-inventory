# Acceso rápido a Salón

## Activación pendiente

El asistente no ejecutó esta migración en la base real.

1. En pgAdmin selecciona **barbarito** con la cuenta propietaria.
2. Abre **Herramientas → Query Tool**.
3. Abre `database/migrations/20260923_acceso_salon.sql`.
4. Ejecuta **todo el archivo una sola vez** con F5. Debe terminar en `COMMIT`.
5. Si aparece un error, ejecuta `ROLLBACK;` y comparte el mensaje completo.
6. Reinicia el backend y recarga el frontend.

Esta migración es independiente de la migración de seguimiento de movimientos. No repitas las migraciones anteriores.

## Uso

- El acceso principal ofrece **Gestión e inventario** (correo y contraseña actuales) y **Salón**.
- Salón pide **local, usuario y PIN de 4 dígitos**. Puede conservar ceros iniciales, por ejemplo `0012`. El PIN no tiene que ser único porque se selecciona al usuario.
- En crear/editar usuario aparece el campo de PIN únicamente si seleccionas **Miembro de equipo** y el puesto **Mesero** o **Bartender**.
- El PIN es opcional. Una persona sin PIN asignado no aparece en el selector de Salón.
- Al editar, dejar el PIN vacío conserva el existente. Puedes reemplazarlo o marcar **Revocar acceso por PIN**. Nunca se muestra el PIN guardado.
- Se conservan los permisos actuales para crear/editar usuarios; no se habilita a nuevos perfiles para administrar personas.
- Desactivar al usuario, quitar su local o retirarle el perfil/puesto elegible impide continuar usando su sesión. Cambiar o revocar el PIN también invalida las sesiones anteriores.
- Las sesiones de Salón duran dos horas y se guardan por pestaña. **Salir de Salón** las retira del navegador. No permiten utilizar las API de Gestión e inventario.
- Cinco PIN incorrectos bloquean el usuario durante cinco minutos. Además hay un límite de quince intentos por conexión cada cinco minutos.
- Salón contiene únicamente una bienvenida y el local activo. Su menú de operaciones queda pendiente de definir.

## Almacenamiento

Se crean `usuario_pin_salon` y `salon_intentos`. El PIN se guarda como hash, sin texto legible. No se reutiliza ni cambia la contraseña de Gestión e inventario. No se generan PIN automáticamente para usuarios existentes.
