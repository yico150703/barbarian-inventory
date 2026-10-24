INSERT INTO perfiles(id_perfil,nombre,descripcion) VALUES(1,'Administrador','Prueba'),(2,'Gerente','Prueba');
INSERT INTO usuario(id_usuario,dni,nombres,apellido_paterno,celular,correo_electronico,clave)
VALUES(1,'00000001','Prueba','Admin','999999991','testadmin@barbarian.pe','solo-prueba'),
      (2,'00000002','Prueba','Gerente','999999992','testgerente@barbarian.pe','solo-prueba');
INSERT INTO usuario_perfiles(id_usuario,id_perfil,usuario_asignacion) VALUES(1,1,1),(2,2,1);
INSERT INTO local(id_local,codigo,nombre) VALUES(1,'MIRAFLORES','Miraflores'),(2,'OTRA','Otra');
INSERT INTO usuario_local(id_usuario,id_local) VALUES(2,1);
INSERT INTO opcion_menu(id_opcion_menu,codigo,nombre,url_menu,descripcion)
SELECT n,'TEST_'||n,'Prueba '||n,'/test/'||n,'Prueba' FROM generate_series(1,33) n;
INSERT INTO perfil_opcion_menu(id_perfil,id_opcion_menu,puede_consultar,puede_crear,puede_editar,puede_revisar,puede_cerrar,puede_configurar,orden)
SELECT p,n,true,true,true,true,true,true,1 FROM generate_series(1,2) p CROSS JOIN generate_series(1,33) n;
INSERT INTO perfil_gestion_usuario(id_perfil_gestor,id_perfil_objetivo,puede_crear,puede_editar)
VALUES(1,1,true,true),(1,2,true,true),(2,2,true,true);
INSERT INTO categoria_producto(id_categoria,nombre,prefijo) VALUES(1,'Prueba','P');
INSERT INTO proveedor(id_proveedor,nombre) VALUES(1,'Proveedor original'),(2,'Proveedor nuevo');
INSERT INTO producto(id_producto,codigo,nombre,id_categoria,id_proveedor,unidad,presentacion,stock_minimo)
VALUES(1,'P-001','Producto compartido',1,1,'C62',1,5);
INSERT INTO producto_stock_local(id_producto,id_local,stock_minimo) VALUES(1,1,5),(1,2,20);
INSERT INTO inventario_cierre(id_inventario_cierre,fecha_inventario,estado_inventario,usuario_registro,fecha_registro)
SELECT n,DATE '2020-01-01'+n,'CERRADO',1,CURRENT_TIMESTAMP FROM generate_series(1,9) n;
INSERT INTO inventario_cierre_detalle(id_inventario_cierre,id_producto,stock_contado)
SELECT n,1,10 FROM generate_series(1,9) n;
INSERT INTO orden_compra(id_orden_compra,codigo,estado_orden_compra,usuario_registro,fecha_registro)
VALUES(1,'OC-001','RECEPCION_PARCIAL',1,'2021-01-01');
INSERT INTO orden_compra_detalle(id_orden_compra,id_producto,cantidad_solicitada) VALUES(1,1,10);
INSERT INTO factura_recepcion(id_factura_recepcion,id_orden_compra,id_proveedor,numero_factura,fecha_recepcion,usuario_recepcion)
VALUES(1,1,1,'TEST-001','2021-01-02',1);
INSERT INTO factura_recepcion_detalle(id_factura_recepcion,id_producto,cantidad_recibida) VALUES(1,1,3);
INSERT INTO movimiento_inventario(id_movimiento_inventario,codigo,tipo_movimiento,motivo_movimiento,fecha_movimiento,usuario_registro)
SELECT n,'MI-00'||n,'SALIDA','MERMA',DATE '2021-01-03',1 FROM generate_series(1,4) n;
INSERT INTO movimiento_inventario_detalle(id_movimiento_inventario,id_producto,cantidad)
SELECT n,1,1 FROM generate_series(1,4) n;
-- Solo en la base ficticia: sincronizar identidades insertadas manualmente.
DO $$ DECLARE c record; sec text; maximo bigint; BEGIN
 FOR c IN SELECT table_name,column_name FROM information_schema.columns
          WHERE table_schema='public' AND is_identity='YES' LOOP
  sec := pg_get_serial_sequence(c.table_name,c.column_name);
  EXECUTE format('SELECT max(%I) FROM %I',c.column_name,c.table_name) INTO maximo;
  IF maximo IS NOT NULL THEN PERFORM setval(sec,maximo,true); END IF;
 END LOOP;
END $$;
