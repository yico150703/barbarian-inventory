# Distribución de salón por local

Ejecuta **20260923_distribucion_salon.sql** completo, una sola vez, en `barbarito` como propietario, después de las migraciones de acceso, pedidos y envíos adicionales de Salón. El asistente no lo ejecutó en la base real. Al terminar en COMMIT, reinicia el backend y recarga el frontend.

En el perfil **Gerente**, selecciona el local y abre **Opciones de salón**:

- El mapa inicial tiene diez mesas, una barra y cinco puestos de barra.
- Agrega mesas o puestos con los botones del panel.
- Selecciona y arrastra los elementos para moverlos. Los campos de posición también permiten colocarlos sin arrastrar.
- Ajusta ancho y alto de mesas, barra o puestos. Las medidas son porcentajes del mapa, no metros.
- Cada puesto se mueve por separado; cambiar el tamaño de la barra no modifica automáticamente sus puestos.
- Guarda la distribución para ese local. Al volver a abrir Salón, los meseros y bartenders verán ese mapa.
- No se pueden quitar mesas con pedidos registrados; sí cambiar su posición y tamaño. Los códigos permanecen estables para conservar la asociación de sus pedidos.
- Si otro gerente guardó mientras editabas, se rechaza el guardado y debes recargar antes de continuar.

El acceso de edición se valida también en el backend: perfil Gerente vigente y local asignado. Los tokens de Salón solo pueden consultar la distribución de su propio local. No se habilita esta edición para administrador, supervisor ni miembro.

La migración agrega `salon_distribucion` y amplía los códigos permitidos en los pedidos para admitir mesas nuevas. No crea pedidos ni modifica los ya enviados. Hasta guardar una distribución, se utiliza el mapa inicial.
