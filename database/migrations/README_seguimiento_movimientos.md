# Activar préstamos y devoluciones

El backend y el frontend incluyen el nuevo flujo. Falta ejecutar **una sola vez**
`20260922_seguimiento_movimientos.sql` en la base real. No fue ejecutado por el asistente.

1. En pgAdmin selecciona **barbarito**, con la cuenta propietaria de las tablas.
2. Abre **Herramientas → Query Tool**.
3. Abre el archivo `database/migrations/20260922_seguimiento_movimientos.sql`.
4. Ejecuta el archivo completo con **F5**, sin seleccionar fragmentos.
5. Debe finalizar en `COMMIT`. Si aparece un error, ejecuta `ROLLBACK;` y comparte el error completo.
6. Reinicia el backend y recarga el frontend. Selecciona Gerente o Supervisor.

No vuelvas a ejecutar las etapas 01, 02 ni 03 para este cambio.

## Uso

- **Registrar movimiento:** préstamo entregado, devolución a proveedor o merma.
- Los préstamos requieren elegir otro local registrado; no admiten texto libre.
- Préstamos y devoluciones se registran con la fecha del día y descuentan el stock al guardarse.
- **Préstamos y devoluciones → Préstamos por recibir:** el destinatario confirma la recepción completa. Solo entonces se genera una entrada en ese local. La salida permanece pendiente hasta esa confirmación.
- **Devoluciones a proveedor:** cada reintegro registra la guía del proveedor y cantidades positivas por producto. Puedes recibir parte de uno o varios productos. Lo restante queda pendiente. Se muestran `Devuelto · pendiente de reintegro`, `Reintegro parcial` y `Reintegrado`.
- La guía de salida interna se consulta e imprime desde el seguimiento; las recepciones quedan enlazadas a ella. El número `MI-...` identifica la guía interna.
- Los números de guía de proveedor no pueden repetirse dentro de la misma devolución. Las recepciones confirmadas no se sobrescriben: cada entrega adicional se registra por separado.
- Los movimientos antiguos conservan su efecto en stock; no se infiere si fueron recibidos ni se convierten automáticamente en pendientes.

## Permisos

Administrador no accede a movimientos, compras ni recepciones. Se mantienen los permisos actuales de gerente, supervisor y otros perfiles operativos, y la asignación del usuario al local. El seguimiento usa la opción 20: consultar para verlo y crear para confirmar recepciones. No se concedieron permisos nuevos al supervisor para crear compras o registrar facturas de recepción.

## Verificación después de ejecutar

```sql
SELECT to_regclass('public.movimiento_seguimiento') AS seguimiento,
       to_regclass('public.movimiento_reintegro') AS recepciones;
SELECT column_name, column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='movimiento_inventario'
  AND column_name='registrado_en';
```

Las pruebas automáticas aplican esta migración exclusivamente a PostgreSQL temporal con datos ficticios. La base habitual solo se consulta para exportar su estructura.
