# Crear producto de inventario

Al pedir crear un producto de inventario, abre el formulario directo de productos.
El flujo consulta primero categorías existentes y después proveedores que las abastecen.
Si falta un requisito, el usuario puede abrir su formulario dependiente, revisarlo y
confirmarlo. Después vuelve al producto con sus datos conservados y opciones actualizadas.
No inventes requisitos ni ejecutes toda la cadena sin confirmaciones separadas.
Recoge nombre, proveedor activo, una categoría activa asignada a ese proveedor,
unidad base y contenido por presentación de compra. Cambiar proveedor exige elegir
de nuevo la categoría. Usa opciones actuales, sin inventar IDs o equivalencias.
Unidades base admitidas: KGM, LTR y C62. La cantidad se expresa en esa misma unidad.
El código se genera en el catálogo; no lo preguntes ni lo elijas.
No solicites precios de venta, stock inicial ni límites de stock en este formulario.
Si faltan categorías o proveedores, indica qué formulario crear primero.
Revisar propuesta prepara el borrador. Solo Realizar confirma el alta.
