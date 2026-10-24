import os
import docx
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml import parse_xml
from docx.oxml.ns import nsdecls

def set_cell_background(cell, fill_hex):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{fill_hex}"/>')
    tcPr.append(shd)

def set_cell_margins(cell, top=70, bottom=70, left=100, right=100):
    tcPr = cell._tc.get_or_add_tcPr()
    tcMar = parse_xml(f'<w:tcMar {nsdecls("w")}><w:top w:w="{top}" w:type="dxa"/><w:bottom w:w="{bottom}" w:type="dxa"/><w:left w:w="{left}" w:type="dxa"/><w:right w:w="{right}" w:type="dxa"/></w:tcMar>')
    tcPr.append(tcMar)

def create_coherent_dailys_doc():
    doc = Document()
    
    for section in doc.sections:
        section.top_margin = Inches(0.85)
        section.bottom_margin = Inches(0.85)
        section.left_margin = Inches(0.85)
        section.right_margin = Inches(0.85)

    PRIMARY = RGBColor(26, 54, 93)     # Azul Marino Profundo (#1A365D)
    SECONDARY = RGBColor(194, 65, 12)  # Ámbar Barbarian (#C2410C)
    SUCCESS = RGBColor(22, 101, 52)    # Verde Éxito (#166534)
    TEXT_DARK = RGBColor(15, 23, 42)   # Slate 900
    HIGHLIGHT = RGBColor(67, 56, 202)  # Índigo para Evidencias

    # =========================================================================
    # PORTADA
    # =========================================================================
    p_title = doc.add_paragraph()
    p_title.paragraph_format.space_before = Pt(8)
    p_title.paragraph_format.space_after = Pt(2)
    r_title = p_title.add_run("REGISTRO DE LAS 10 DAILYS SCRUM — ORDEN COHERENTE Y SUCESIVO")
    r_title.font.name = "Arial"
    r_title.font.size = Pt(16)
    r_title.font.bold = True
    r_title.font.color.rgb = PRIMARY

    p_sub = doc.add_paragraph()
    p_sub.paragraph_format.space_after = Pt(8)
    r_sub = p_sub.add_run("Barbarian Inventory — Cronología Priorizada por Dependencias de Negocio y Guía de Evidencias")
    r_sub.font.name = "Arial"
    r_sub.font.size = Pt(11)
    r_sub.font.color.rgb = SECONDARY

    meta_tbl = doc.add_table(rows=5, cols=2)
    meta_tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    meta_data = [
        ("Proyecto / Empresa:", "Barbarian Inventory — Cervecería Barbarian (Lima, Perú)"),
        ("Período del Sprint:", "03 de Octubre al 23 de Octubre de 2026 (10 Dailys de trabajo)"),
        ("Equipo de Desarrollo:", "3 Integrantes (Piero Montalvo: Backend/DB, Dev 2: Frontend/UI, Dev 3: QA/DevOps)"),
        ("Metodología:", "Scrum Ágil (Guía SBOK) — Cadena Sucesiva de Valor"),
        ("Infraestructura en la Nube:", "Render (PostgreSQL + API Backend) + Vercel (Frontend Web)")
    ]

    for idx, (label, val) in enumerate(meta_data):
        row = meta_tbl.rows[idx]
        c0, c1 = row.cells[0], row.cells[1]
        c0.width = Inches(2.2)
        c1.width = Inches(4.6)
        
        p0 = c0.paragraphs[0]
        p0.paragraph_format.space_after = Pt(0)
        r0 = p0.add_run(label)
        r0.font.name = "Arial"
        r0.font.size = Pt(9)
        r0.font.bold = True
        r0.font.color.rgb = PRIMARY
        
        p1 = c1.paragraphs[0]
        p1.paragraph_format.space_after = Pt(0)
        r1 = p1.add_run(val)
        r1.font.name = "Arial"
        r1.font.size = Pt(9)
        
        set_cell_background(c0, "F1F5F9")
        set_cell_background(c1, "FFFFFF")
        set_cell_margins(c0, 45, 45, 75, 75)
        set_cell_margins(c1, 45, 45, 75, 75)

    doc.add_paragraph().paragraph_format.space_after = Pt(6)

    # =========================================================================
    # TABLA RESUMEN DE LA CADENA DE DEPENDENCIAS
    # =========================================================================
    h_map = doc.add_heading("1. Matriz de Coherencia y Dependencias del Sprint", level=1)
    h_map.paragraph_format.space_before = Pt(10)
    h_map.paragraph_format.space_after = Pt(4)

    p_map = doc.add_paragraph(
        "El presente orden respeta la lógica de construcción de un restaurante cervecero: "
        "primero se normalizan los insumos base; con ellos se formulan subproductos y recetas; "
        "luego se homologan proveedores y se respalda el almacén; posteriormente se habilita la comanda de salón, "
        "se reacomoda el backlog para incorporar barra libre a costo cero, se descuentan los barriles de cerveza por receta, "
        "se escala a las 4 sedes oficiales y se culmina con el control de desabastecimiento y el despliegue final a producción."
    )
    p_map.paragraph_format.space_after = Pt(6)

    tbl_res = doc.add_table(rows=1, cols=4)
    tbl_res.alignment = WD_TABLE_ALIGNMENT.CENTER
    res_headers = ["Daily / Fecha", "Historia de Usuario", "Tema Central de la Sesión", "Dependencia Lógica"]
    for c_i, h_txt in enumerate(res_headers):
        cell = tbl_res.rows[0].cells[c_i]
        p = cell.paragraphs[0]
        p.paragraph_format.space_after = Pt(0)
        r = p.add_run(h_txt)
        r.font.name = "Arial"
        r.font.size = Pt(8.5)
        r.font.bold = True
        r.font.color.rgb = RGBColor(255, 255, 255)
        set_cell_background(cell, "1E3A8A")
        set_cell_margins(cell, 50, 50, 60, 60)

    res_items = [
        ("Daily 1 (06/10)", "HU-02", "Medidas Estándar (KGM/LTR) y Dropdown de Productos", "Cimiento de todo el catálogo."),
        ("Daily 2 (07/10)", "HU-04B", "Formulación de Subproductos de Cocina (SP-XXXX)", "Requiere insumos en KGM/LTR."),
        ("Daily 3 (08/10)", "HU-08", "Fichas Técnicas de Recetas en g y mL (Decimal)", "Usa los insumos y subproductos."),
        ("Daily 4 (09/10)", "HU-04", "Homologación de Proveedores y Categorías", "Define quién vende los insumos."),
        ("Daily 5 (10/10)", "HU-05", "Consolidación de Almacén y Backup de Base de Datos", "Cierra el catálogo de semana 1."),
        ("Daily 6 (13/10)", "HU-16/18", "Punto de Venta en Salón (Plano de Mesas y Comandas)", "Usa los platos de la carta."),
        ("Daily 7 (15/10)", "Proc 10.3", "⭐ Redefinición del Backlog y Barra Libre S/. 0.00", "Reorganización de prioridades."),
        ("Daily 8 (17/10)", "HU-17/08", "Cobro de Cuenta y Descuento de Barriles por Receta", "La venta descuenta el almacén."),
        ("Daily 9 (20/10)", "HU-08B", "Sedes Oficiales (TDA-001 a 004) y Transferencias", "Expande el flujo a la cadena."),
        ("Daily 10 (23/10)", "HU-04C/DoD", "Límites de Stock por Tienda y Despliegue en la Nube", "Cierre del Sprint en producción.")
    ]

    for item in res_items:
        row = tbl_res.add_row()
        for col_i, val in enumerate(item):
            cell = row.cells[col_i]
            p = cell.paragraphs[0]
            p.paragraph_format.space_after = Pt(0)
            r = p.add_run(val)
            r.font.name = "Arial"
            r.font.size = Pt(8)
            if col_i == 1:
                r.bold = True
                r.font.color.rgb = PRIMARY
            set_cell_background(cell, "F8FAFC" if len(tbl_res.rows) % 2 == 0 else "FFFFFF")
            set_cell_margins(cell, 35, 35, 50, 50)

    doc.add_paragraph().paragraph_format.space_after = Pt(8)

    # =========================================================================
    # DETALLE DE LAS 10 DAILYS
    # =========================================================================
    h_dailys = doc.add_heading("2. Desarrollo Detallado de las 10 Dailys con Guía de Evidencias", level=1)
    h_dailys.paragraph_format.space_before = Pt(12)
    h_dailys.paragraph_format.space_after = Pt(4)

    dailys_data = [
        ("Daily 1 — Lunes 06 de Octubre: Estandarización de Medidas y Catálogo Base",
         "HU-02: Catálogo con Unidades de Medida Estándar (KGM/LTR/C62)", [
            ("Piero Montalvo (Dev 1 — Backend & Base de Datos):",
             "Analicé la tabla producto y elaboré el script SQL (20261010_unidades_unece.sql) con los códigos internacionales estándar y la restricción ck_producto_unidad.",
             "Voy a estructurar la tabla de subproductos para preparaciones intermedias de cocina.",
             "Ninguno, las 6 tablas dependientes de productos quedaron mapeadas.",
             "Captura en pgAdmin o GitHub del script SQL mostrando la restricción CHECK (unidad IN ('KGM', 'LTR', 'C62'))."),
            ("Dev 2 (Frontend — Pantallas y Diseño):",
             "Reemplacé el cuadro de texto libre por el menú desplegable en el formulario de creación de productos (ProductsPage.tsx).",
             "Voy a maquetar la interfaz de subproductos de cocina.",
             "Ninguno, el selector muestra con claridad Kilogramo (kg), Litro (L) y Unidad.",
             "Captura de la ventana modal 'Nuevo producto' con el menú desplegable azul abierto mostrando Kilogramo (kg), Litro (L) y Unidad."),
            ("Dev 3 (Pruebas y Control de Calidad):",
             "Realicé la prueba de registrar el producto Prueba1 (AB-003) con presentación de 0.05 kg y comprobé que la base de datos lo guarde sin redondearlo a cero.",
             "Voy a preparar pruebas de rendimiento para subproductos de cocina.",
             "Ninguno, el registro y guardado funcionaron perfectamente.",
             "Captura de pantalla web mostrando Prueba1 con 0.05 kg y su consulta en pgAdmin (SELECT codigo, nombre, unidad, presentacion FROM producto WHERE codigo = 'AB-003';).")
        ]),

        ("Daily 2 — Martes 07 de Octubre: Formulación de Subproductos de Cocina",
         "HU-04B: Subproductos de Producción (SP-XXXX)", [
            ("Piero Montalvo (Dev 1 — Backend & Base de Datos):",
             "Creé la tabla subproducto y programé la generación automática del correlativo con prefijo SP- (ej. SP-0001) con su rendimiento.",
             "Voy a programar la función matemática de conversión decimal para recetas de platos finales.",
             "Ninguno, la estructura relacional de subproductos quedó validada.",
             "Captura en pgAdmin ejecutando: SELECT id_subproducto, codigo, nombre, rendimiento FROM subproducto LIMIT 5;"),
            ("Dev 2 (Frontend — Pantallas y Diseño):",
             "Diseñé la vista de Subproductos (SubproductsPage.tsx) con su modal para que el cocinero elija qué insumos componen cada salsa o jarabe.",
             "Voy a actualizar el editor de recetas de carta.",
             "Ninguno, el listado de subproductos carga de forma fluida.",
             "Captura de pantalla en la web en Recetas y producción ➡️ Subproductos."),
            ("Dev 3 (Pruebas y Control de Calidad):",
             "Verifiqué que al formular una salsa BBQ de prueba, el sistema sume los insumos en kilos y calcule el rendimiento total preparado.",
             "Voy a probar qué ocurre al ingresar ingredientes en gramos en recetas de platos.",
             "Ninguno.",
             "Captura del formulario web de un subproducto con sus ingredientes asociados o su registro en pgAdmin.")
        ]),

        ("Daily 3 — Miércoles 08 de Octubre: Recetas de Carta y Conversión Decimal (g y mL)",
         "HU-08: Fichas Técnicas de Recetas con Conversión Decimal", [
            ("Piero Montalvo (Dev 1 — Backend & Base de Datos):",
             "Programé la función en Python (units.py) con tipo Decimal para convertir automáticamente gramos a kilos y mililitros a litros a 3 decimales.",
             "Voy a estructurar la homologación de categorías por proveedor.",
             "Ninguno, la fórmula se ajustó correctamente.",
             "Captura del archivo units.py en VS Code mostrando la función matemática con tipo Decimal."),
            ("Dev 2 (Frontend — Pantallas y Diseño):",
             "Actualicé el editor de recetas (RecipeEditor.tsx) para permitir que el cocinero ingrese ingredientes fraccionados en gramos y mililitros.",
             "Voy a diseñar los checkboxes de categorías en la pantalla de proveedores.",
             "Ninguno.",
             "Captura de la pantalla web en Recetas y producción ➡️ Recetas, editando la ficha técnica de un plato."),
            ("Dev 3 (Pruebas y Control de Calidad):",
             "Hice pruebas ingresando 50 gramos de carne y 200 mililitros de salsa en una receta, validando que el sistema no lo tome como kilos completos.",
             "Voy a probar las restricciones de proveedores.",
             "Ninguno, la API respondió 200 OK.",
             "Captura de petición de prueba en Postman o pantalla de receta guardada con insumos fraccionados.")
        ]),

        ("Daily 4 — Jueves 09 de Octubre: Homologación de Proveedores y Categorías",
         "HU-04: Proveedores por Categorías Asignadas", [
            ("Piero Montalvo (Dev 1 — Backend & Base de Datos):",
             "Creé la tabla proveedor_categoria (20261010_proveedor_categorias.sql) y programé la validación para impedir compras de insumos ajenos al giro del proveedor.",
             "Voy a revisar las llaves foráneas y consolidar la base de datos de la primera semana.",
             "Ninguno, la relación quedó normalizada.",
             "Captura en pgAdmin: SELECT p.nombre, c.nombre FROM proveedor_categoria pc JOIN proveedor p USING(id_proveedor) JOIN categoria_producto c USING(id_categoria) LIMIT 5;"),
            ("Dev 2 (Frontend — Pantallas y Diseño):",
             "Agregué el selector de casillas de verificación (checkboxes) en la pantalla de proveedores (SuppliersPage.tsx) para marcar las categorías autorizadas.",
             "Voy a revisar que las pantallas de catálogo se adapten a tablets.",
             "Ninguno.",
             "Captura del formulario de Proveedores mostrando el bloque 'Categorías que atiende' con casillas de verificación."),
            ("Dev 3 (Pruebas y Control de Calidad):",
             "Probé asignarle la categoría ABARROTE al proveedor pepito y validé que el sistema bloquee si se intenta comprarle lúpulo cervecero.",
             "Voy a generar un respaldo consolidado de la base de datos de la primera semana.",
             "Ninguno.",
             "Captura de la lista de proveedores en la web mostrando a pepito con su categoría asociada.")
        ]),

        ("Daily 5 — Viernes 10 de Octubre: Consolidación de Almacén y Backup General",
         "HU-05: Consulta de Stock Actual y Consistencia de Inventario", [
            ("Piero Montalvo (Dev 1 — Backend & Base de Datos):",
             "Revisé todo el esquema de inventario, asegurando la consistencia de las Foreign Keys y evitando registros huérfanos.",
             "Voy a estructurar las tablas de pedidos y comandas de salón.",
             "Ninguno, la base de datos quedó íntegra.",
             "Captura en pgAdmin: SELECT conname, conrelid::regclass FROM pg_constraint WHERE contype = 'f' LIMIT 8;"),
            ("Dev 2 (Frontend — Pantallas y Diseño):",
             "Verifiqué el diseño responsivo de catálogos y proveedores en modo tablet (usando F12 del navegador).",
             "Voy a maquetar la interfaz táctil de comanda para mozos.",
             "Ninguno.",
             "Captura del navegador usando las herramientas de desarrollador (F12) en modo emulación tablet mostrando el catálogo."),
            ("Dev 3 (Pruebas y Control de Calidad):",
             "Ejecuté una revisión general y generé el respaldo oficial de la base de datos (barbarito_completa_20261010.backup).",
             "Voy a preparar los casos de prueba para el módulo de atención en salón.",
             "Ninguno, respaldo guardado con éxito.",
             "Captura del archivo físico barbarito_completa_20261010.backup en el explorador de archivos de Windows o GitHub.")
        ]),

        ("Daily 6 — Lunes 13 de Octubre: Punto de Venta en Salón (Mesas y Comandas)",
         "HU-16: Comandas por Mesa y HU-18: Plano de Mesas", [
            ("Piero Montalvo (Dev 1 — Backend & Base de Datos):",
             "Diseñé el modelo relacional de comandas de salón (comanda, comanda_item, mesa).",
             "Participar en la sesión de refinamiento del Product Backlog para ordenar las historias de salón.",
             "Ninguno.",
             "Captura en pgAdmin: SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'comanda_item' LIMIT 8;"),
            ("Dev 2 (Frontend — Pantallas y Diseño):",
             "Maqueté los botones táctiles de la comanda de salón (SalonOrderPage.tsx) con categorías de carta para pedidos rápidos de mozos.",
             "Participar en la redefinición del backlog para detallar las promociones de barra libre.",
             "Ninguno.",
             "Captura de la pantalla de comanda táctil con los botones de categorías y platos."),
            ("Dev 3 (Pruebas y Control de Calidad):",
             "Armé una matriz de casos de prueba para simular mesas pidiendo platos a la carta y bebidas en simultáneo.",
             "Actualizar el tablero Kanban con los requerimientos que surjan del refinamiento.",
             "Ninguno.",
             "Captura de la matriz de pruebas funcionales para pedidos de salón en Excel o Notion.")
        ]),

        ("Daily 7 — Miércoles 15 de Octubre: ⭐ Redefinición del Backlog y Barra Libre S/. 0.00",
         "Proceso 10.3: Redefinición del Product Backlog y HU-17: Barra Libre", [
            ("Piero Montalvo (Dev 1 — Backend & Base de Datos):",
             "Participé en la sesión de Redefinición del Product Backlog (Proceso 10.3). Programé el script SQL (20261016_promociones_reposicion_salon.sql) con la columna es_reposicion para registrar rondas de barra libre a costo de S/. 0.00.",
             "Conectar el cobro de la cuenta con el descuento automático de barriles en almacén.",
             "Ninguno, tras redefinir el Backlog el alcance de salón quedó claro.",
             "Captura del script 20261016_promociones_reposicion_salon.sql mostrando ALTER TABLE comanda_item ADD COLUMN es_reposicion BOOLEAN DEFAULT FALSE;"),
            ("Dev 2 (Frontend — Pantallas y Diseño):",
             "Participé en la redefinición del Backlog y diseñé el botón interactivo 'Reponer bebida gratis (S/. 0.00)' dentro de la mesa activa en la comanda.",
             "Diseñar el comprobante de venta visual en formato SVG.",
             "Ninguno.",
             "Captura de la comanda de mesa mostrando el botón de reposición gratuita de cerveza a S/. 0.00."),
            ("Dev 3 (Pruebas y Control de Calidad):",
             "Actualicé el tablero Kanban moviendo las nuevas Historias de Salón redefinidas (HU-16 y HU-17) al Sprint Backlog activo.",
             "Realizar una prueba de cobro de mesa con rondas de reposición gratuita.",
             "Ninguno.",
             "Captura del tablero Kanban (Jira/Trello/GitHub) mostrando las historias redefinidas agregadas.")
        ]),

        ("Daily 8 — Viernes 17 de Octubre: Cobro de Cuenta y Descuento de Barriles por Receta",
         "HU-17: Cobro y Descarga de Stock y HU-08: Explosión de Recetas", [
            ("Piero Montalvo (Dev 1 — Backend & Base de Datos):",
             "Implementé la función en Python (salon_payments.py) que ejecuta la explosión de recetas y descuenta de inmediato los mililitros consumidos en producto_stock_local.",
             "Actualizar las direcciones y códigos oficiales de las 4 tiendas físicas de Barbarian.",
             "Ninguno, la transacción se ejecuta de forma atómica.",
             "Captura de la función de cobro en salon_payments.py ejecutando el descuento de inventario en VS Code."),
            ("Dev 2 (Frontend — Pantallas y Diseño):",
             "Diseñé el comprobante de venta visual en formato SVG mostrando el desglose del consumo de la mesa y las rondas a costo cero.",
             "Colocar el selector de tiendas en la barra superior (Navbar).",
             "Ninguno.",
             "Captura del ticket visual de pago emitido en pantalla mostrando la cuenta de salón cerrada."),
            ("Dev 3 (Pruebas y Control de Calidad):",
             "Cobré una mesa con barra libre y verifiqué en la pantalla de Stock que el saldo del barril de cerveza disminuyera en exactamente 1.419 Litros (3 vasos servidos).",
             "Preparar las pruebas de transferencias de mercadería entre sedes.",
             "Ninguno, el stock restó los litros exactos.",
             "Captura de la pantalla de Stock antes y después de pagar demostrando el descuento del barril.")
        ]),

        ("Daily 9 — Lunes 20 de Octubre: Sedes Oficiales (TDA-001 a 004) y Transferencias",
         "HU-08B: Transferencias entre Sedes y HU-04C: Gestión de Tiendas", [
            ("Piero Montalvo (Dev 1 — Backend & Base de Datos):",
             "Ejecuté el script SQL (20261020_direcciones_locales.sql) actualizando los códigos oficiales (TDA-001 Miraflores, TDA-002 Barranco, TDA-003 Sheraton, TDA-004 Santa Anita) y sus direcciones físicas.",
             "Programar las validaciones de límites de stock (mínimo y máximo) por tienda.",
             "Ninguno, las 4 sedes quedaron normalizadas.",
             "Captura en pgAdmin: SELECT id_local, codigo, nombre, direccion, activo FROM local ORDER BY id_local ASC;"),
            ("Dev 2 (Frontend — Pantallas y Diseño):",
             "Actualicé el Navbar para mostrar la tienda activa seleccionada y construí la pantalla de tiendas (StoresPage.tsx).",
             "Diseñar la pantalla de Límites de Stock para que los gerentes ajusten sus umbrales.",
             "Ninguno.",
             "Captura de pantalla de Tiendas mostrando las 4 sedes registradas."),
            ("Dev 3 (Pruebas y Control de Calidad):",
             "Probé el formulario de transferencias entre sedes, simulando un préstamo de insumos desde Miraflores hacia Barranco en estado 'En tránsito'.",
             "Probar los límites de stock y preparar el despliegue final a producción.",
             "Ninguno, el stock en tránsito quedó reflejado en ambas tiendas.",
             "Captura del formulario de transferencias de inventario mostrando el movimiento entre sedes.")
        ]),

        ("Daily 10 — Jueves 23 de Octubre: Límites de Stock por Tienda y Salida a Producción",
         "HU-04C: Límites de Stock por Tienda y Cierre del Sprint (DoD)", [
            ("Piero Montalvo (Dev 1 — Backend & Base de Datos):",
             "Programé la lógica en el backend (stock_limits.py) para validar los límites de inventario en producto_stock_local, asegurando que el stock máximo sea mayor o igual al mínimo en cada sede.",
             "Brindar soporte técnico y verificar que las consultas en la base de datos de producción respondan rápido.",
             "Ninguno, las validaciones de stock por tienda quedaron operativas.",
             "Captura de la consulta a producto_stock_local en pgAdmin o archivo stock_limits.py: SELECT id_local, id_producto, stock_minimo, stock_maximo FROM producto_stock_local LIMIT 5;"),
            ("Dev 2 (Frontend — Pantallas y Diseño):",
             "Terminé la pantalla de Límites de Stock (StockLimitsPage.tsx), diseñando la tabla donde el gerente de cada tienda edita sus mínimos y máximos, y agregué las etiquetas visuales de alerta en rojo y ámbar.",
             "Revisar con el equipo los últimos detalles de la interfaz para la entrega final al Product Owner.",
             "Ninguno, la pantalla permite actualizar los umbrales de cada sucursal con un solo clic.",
             "Captura de la pantalla de Límites de Stock en la web mostrando los campos de stock mínimo y máximo."),
            ("Dev 3 (Pruebas y Nube — Despliegue Final):",
             "Probé la configuración de límites de stock simulando un insumo por debajo del mínimo para verificar que el sistema dispare la alerta visual de reposición.",
             "Como última acción del Sprint, ejecuté el despliegue final a producción: levanté el backend en Render con Gunicorn, desplegué la web en Vercel con las rutas configuradas en vercel.json y realicé la prueba final de humo (Smoke Testing) en la URL pública.",
             "Ninguno. El sistema completo se encuentra 100% operativo en internet y el Sprint concluyó con éxito total.",
             "Captura de pantalla de la aplicación web navegando en internet en el dominio público de Vercel con el mensaje 'Sistema conectado' en verde.")
        ])
    ]

    for title, hu_name, dev_reports in dailys_data:
        h_d = doc.add_heading(title, level=2)
        h_d.paragraph_format.space_before = Pt(11)
        h_d.paragraph_format.space_after = Pt(2)
        
        p_hu = doc.add_paragraph()
        p_hu.paragraph_format.left_indent = Inches(0.1)
        p_hu.paragraph_format.space_after = Pt(3)
        r_lbl_hu = p_hu.add_run("Historia de Usuario Asociada: ")
        r_lbl_hu.bold = True
        r_lbl_hu.font.size = Pt(9)
        r_lbl_hu.font.color.rgb = SECONDARY
        r_val_hu = p_hu.add_run(hu_name)
        r_val_hu.bold = True
        r_val_hu.font.size = Pt(9)
        r_val_hu.font.color.rgb = PRIMARY
        
        for dev_name, a1, a2, a3, evidence in dev_reports:
            p_dev = doc.add_paragraph()
            p_dev.paragraph_format.left_indent = Inches(0.1)
            p_dev.paragraph_format.space_before = Pt(3)
            p_dev.paragraph_format.space_after = Pt(1)
            r_dev = p_dev.add_run(dev_name)
            r_dev.bold = True
            r_dev.font.name = "Arial"
            r_dev.font.size = Pt(9.5)
            r_dev.font.color.rgb = PRIMARY
            
            p_q1 = doc.add_paragraph()
            p_q1.paragraph_format.left_indent = Inches(0.25)
            p_q1.paragraph_format.space_after = Pt(1)
            r_q1 = p_q1.add_run("1. ¿Qué he hecho desde la última reunión?\n")
            r_q1.bold = True
            r_q1.font.name = "Arial"
            r_q1.font.size = Pt(8.5)
            p_q1.add_run(a1).font.size = Pt(8.5)
            
            p_q2 = doc.add_paragraph()
            p_q2.paragraph_format.left_indent = Inches(0.25)
            p_q2.paragraph_format.space_after = Pt(1)
            r_q2 = p_q2.add_run("2. ¿Qué tengo planeado hacer antes de la siguiente reunión?\n")
            r_q2.bold = True
            r_q2.font.name = "Arial"
            r_q2.font.size = Pt(8.5)
            p_q2.add_run(a2).font.size = Pt(8.5)
            
            p_q3 = doc.add_paragraph()
            p_q3.paragraph_format.left_indent = Inches(0.25)
            p_q3.paragraph_format.space_after = Pt(2)
            r_q3 = p_q3.add_run("3. ¿Qué impedimentos u obstáculos estoy enfrentando en la actualidad?\n")
            r_q3.bold = True
            r_q3.font.name = "Arial"
            r_q3.font.size = Pt(8.5)
            p_q3.add_run(a3).font.size = Pt(8.5)

            p_ev = doc.add_paragraph()
            p_ev.paragraph_format.left_indent = Inches(0.25)
            p_ev.paragraph_format.space_before = Pt(1)
            p_ev.paragraph_format.space_after = Pt(4)
            r_ev_lbl = p_ev.add_run("📸 Captura / Evidencia requerida: ")
            r_ev_lbl.bold = True
            r_ev_lbl.font.name = "Arial"
            r_ev_lbl.font.size = Pt(8.5)
            r_ev_lbl.font.color.rgb = HIGHLIGHT
            r_ev_txt = p_ev.add_run(evidence)
            r_ev_txt.font.name = "Arial"
            r_ev_txt.font.size = Pt(8.5)
            r_ev_txt.font.italic = True

    out_file = os.path.abspath("DAILYS_SCRUM_BARBARIAN_ORDEN_COHERENTE.docx")
    doc.save(out_file)
    print(f"Documento de Dailys con orden coherente generado en: {out_file}")

if __name__ == "__main__":
    create_coherent_dailys_doc()
