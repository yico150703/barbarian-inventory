# PROGRAMACION-3

## Respaldo de PostgreSQL

El respaldo vigente es `database/barbarito_completa_20261010.backup`, generado
desde la base local `barbarito` con PostgreSQL 18.4. Incluye el esquema y los datos,
con las migraciones `20261010_unidades_unece.sql` y
`20261010_proveedor_categorias.sql` ya aplicadas.

Se verificó que el archivo se puede leer completamente con `pg_restore` y que
contiene el esquema y los datos de `unidad_medida` y `proveedor_categoria`.
Este archivo reemplaza el respaldo del 30 de septiembre de 2026.

Para restaurarlo en una base vacía con PostgreSQL 18 y los roles `postgres` y
`multi` creados:

```sh
pg_restore --exit-on-error --host localhost --username postgres --dbname barbarito database/barbarito_completa_20261010.backup
```

El respaldo no crea los roles de PostgreSQL. Cambia el nombre de la base y la
conexión según el entorno de destino.
