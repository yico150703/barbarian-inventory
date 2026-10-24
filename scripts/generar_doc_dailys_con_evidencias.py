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

def create_dailys_with_evidence_doc():
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
    r_title = p_title.add_run("REGISTRO OFICIAL DE 10 DAILYS SCRUM Y GUÍA DE EVIDENCIAS")
    r_title.font.name = "Arial"
    r_title.font.size = Pt(17)
    r_title.font.bold = True
    r_title.font.color.rgb = PRIMARY

    p_sub = doc.add_paragraph()
    p_sub.paragraph_format.space_after = Pt(10)
    r_sub = p_sub.add_run("Barbarian Inventory — Reporte de Reuniones Diarias y Capturas de Pantalla por Alumno")
    r_sub.font.name = "Arial"
    r_sub.font.size = Pt(11)
    r_sub.font.color.rgb = SECONDARY

    meta_tbl = doc.add_table(rows=5, cols=2)
    meta_tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    meta_data = [
        ("Proyecto / Empresa:", "Barbarian Inventory — Cervecería Barbarian (Lima, Perú)"),
        ("Período del Sprint:", "03 de Octubre al 23 de Octubre de 2026 (10 Reuniones Diarias)"),
        ("Equipo de Desarrollo:", "3 Alumnos / Desarrolladores con roles distribuidos"),
        ("Repositorio Oficial:", "https://github.com/yico150703/barbarian-inventory"),
        ("Infraestructura Desplegada:", "Render (Base de Datos PostgreSQL + API Backend) + Vercel (Frontend Web)")
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
    # ROL DE CADA ALUMNO EN EL EQUIPO
    # =========================================================================
    h_roles = doc.add_heading("1. Distribución de Roles por Alumno", level=1)
    h_roles.paragraph_format.space_before = Pt(10)
    h_roles.paragraph_format.space_after = Pt(4)

    p_roles_intro = doc.add_paragraph(
        "Para mantener una coherencia técnica y metodológica durante las 10 reuniones diarias, "
        "cada alumno asumió una responsabilidad funcional clara en el equipo de desarrollo:"
    )
    p_roles_intro.paragraph_format.space_after = Pt(4)

    roles_data = [
        ("Alumno 1 — Backend & Base de Datos (Lógica de Negocio):", 
         "Responsable del esquema relacional en PostgreSQL, modelos SQLAlchemy, migraciones SQL, endpoints REST en Flask/Python, funciones de cálculo con precisión decimal y reglas de negocio de almacén y cobro."),
        ("Alumno 2 — Frontend & Diseño UI/UX (Interfaz de Usuario):", 
         "Responsable de las vistas en React/TypeScript, componentes reutilizables, selector de unidades, maquetación del plano interactivo de mesas, modales de comanda táctil y comprobantes SVG."),
        ("Alumno 3 — Pruebas, QA & Nube (DevOps e Integración):", 
         "Responsable de la preparación del entorno, pruebas de integración y carga, verificación de decimales en recetas, gestión del repositorio en GitHub, restauración de base de datos y despliegue continuo en Render y Vercel.")
    ]

    for rol_tit, rol_desc in roles_data:
        p_r = doc.add_paragraph()
        p_r.paragraph_format.left_indent = Inches(0.15)
        p_r.paragraph_format.space_before = Pt(2)
        p_r.paragraph_format.space_after = Pt(2)
        r_rt = p_r.add_run(rol_tit + " ")
        r_rt.bold = True
        r_rt.font.name = "Arial"
        r_rt.font.size = Pt(9)
        r_rt.font.color.rgb = PRIMARY
        r_rd = p_r.add_run(rol_desc)
        r_rd.font.name = "Arial"
        r_rd.font.size = Pt(9)

    doc.add_paragraph().paragraph_format.space_after = Pt(6)

    # =========================================================================
    # LAS 10 DAILYS CON EVIDENCIAS DETALLADAS POR ALUMNO
    # =========================================================================
    h_dailys = doc.add_heading("2. Registro Oficial de las 10 Dailys con Evidencias por Alumno", level=1)
    h_dailys.paragraph_format.space_before = Pt(12)
    h_dailys.paragraph_format.space_after = Pt(4)

    intro_dailys = doc.add_paragraph(
        "A continuación se detallan las 10 Dailys respetando el Time-box de 15 minutos establecido en Scrum. "
        "Cada alumno responde a las tres preguntas oficiales y cuenta con la indicación exacta de la "
        "captura de pantalla o artefacto técnico que debe adjuntarse como evidencia de su trabajo diario:"
    )
    intro_dailys.paragraph_format.space_after = Pt(6)

    dailys = [
        ("Daily 1 — Lunes 06 de Octubre (Diagnóstico de unidades y esquema de datos)", [
            ("Alumno 1 (Backend & Base de Datos):",
             "Analicé el esquema de la base de datos para identificar en qué tablas teníamos unidades escritas en texto libre.",
             "Voy a preparar la estructura de una nueva tabla con códigos internacionales estándar (kilos, litros, unidades).",
             "Ninguno por el momento, las 6 tablas involucradas quedaron claramente mapeadas.",
             "Captura de pantalla de la consulta SQL ejecutada en pgAdmin/DBeaver analizando la tabla de productos (ej. SELECT DISTINCT unidad FROM producto;) mostrando los textos libres anteriores."),

            ("Alumno 2 (Frontend & UI):",
             "Revisé los formularios de productos donde las unidades estaban puestas como texto manual.",
             "Voy a diseñar un menú desplegable moderno para que el usuario seleccione la unidad con un solo clic.",
             "Estaba esperando que Alumno 1 me confirme la lista oficial de medidas que usaremos.",
             "Captura de pantalla del formulario en React (código o pantalla web) donde el campo 'Unidad' aún era un cuadro de texto libre editable."),

            ("Alumno 3 (Pruebas & DevOps):",
             "Preparé el repositorio en GitHub y configuré el entorno local para compartir el avance del equipo.",
             "Voy a crear un conjunto de datos de prueba para ensayar ingresos de productos con decimales.",
             "Ninguno.",
             "Captura de pantalla del repositorio oficial en GitHub con el primer commit del Sprint y la consola de Git clonando el proyecto en local.")
        ]),

        ("Daily 2 — Martes 07 de Octubre (Script de medidas estándar y selector visual)", [
            ("Alumno 1 (Backend & Base de Datos):",
             "Elaboré el script SQL para crear la tabla de medidas estándar (KGM, LTR, C62 y PORCION).",
             "Voy a probar el script en la base de datos local y agregar las restricciones de seguridad para no admitir unidades inventadas.",
             "Ajusté el script inicial para asegurar que conserve todos los datos históricos existentes sin pérdida.",
             "Captura del editor de código mostrando el script SQL con los CREATE TABLE y los INSERT de los códigos internacionales estándar."),

            ("Alumno 2 (Frontend & UI):",
             "Terminé el componente de selección de unidades para la interfaz gráfica.",
             "Voy a integrarlo en la pantalla de productos y verificar que muestre símbolos limpios y fáciles de leer (kg, L, und).",
             "Ninguno.",
             "Captura de la pantalla web mostrando el menú desplegable (Select) desplegando las opciones oficiales (KGM, LTR, C62, Porción)."),

            ("Alumno 3 (Pruebas & DevOps):",
             "Diseñé las pruebas para validar qué ocurre cuando un usuario ingresa cantidades pequeñas como 0.050 kilos de un insumo.",
             "Voy a verificar que la base de datos guarde los números con todos sus decimales sin redondear de forma imprecisa.",
             "Ninguno.",
             "Captura de la terminal ejecutando un script de prueba de inserción en base de datos o tabla verificando valores con decimales (0.050).")
        ]),

        ("Daily 3 — Miércoles 08 de Octubre (Cálculo exacto de gramos y mililitros en recetas)", [
            ("Alumno 1 (Backend & Base de Datos):",
             "Programé la función matemática en Python para convertir automáticamente gramos a kilos y mililitros a litros.",
             "Voy a revisar que el cálculo utilice precisión decimal exacta (Decimal) para que el almacén no pierda miligramos en las recetas.",
             "Ninguno, la fórmula se ajustó correctamente a 3 decimales.",
             "Captura del archivo de servicio Python del backend mostrando la función de conversión con Decimal y redondeo exacto a 3 decimales."),

            ("Alumno 2 (Frontend & UI):",
             "Actualicé la pantalla del catálogo de productos con los nuevos nombres de medida.",
             "Voy a colocar el selector de unidades en el editor de recetas para que el cocinero elija si usa gramos o porciones.",
             "Necesitaba que la función de Alumno 1 estuviera lista para conectar el botón.",
             "Captura del modal o pantalla de edición de recetas mostrando los campos fraccionados en gramos y mililitros."),

            ("Alumno 3 (Pruebas & DevOps):",
             "Hice pruebas de recetas ingresando 50 gramos de carne y 200 mililitros de salsa.",
             "Voy a verificar que al guardar la receta, el almacén reste exactamente esa fracción y no kilos completos.",
             "Ninguno, las pruebas pasaron correctamente.",
             "Captura de Postman / Thunder Client enviando un POST de prueba a la API de recetas con cantidades en gramos y recibiendo código 200 OK.")
        ]),

        ("Daily 4 — Jueves 09 de Octubre (Reglas de validación para proveedores y categorías)", [
            ("Alumno 1 (Backend & Base de Datos):",
             "Habilité el endpoint para consultar unidades y programé la regla para que cada proveedor solo venda sus categorías asignadas.",
             "Voy a ajustar el backend para que devuelva un aviso claro si intentan comprarle verduras a un proveedor de cerveza.",
             "Ninguno.",
             "Captura del endpoint en Python donde se implementa la validación de categorías permitidas por proveedor y el retorno de error 400."),

            ("Alumno 2 (Frontend & UI):",
             "Conecté la pantalla de recetas con las nuevas medidas.",
             "Voy a rediseñar la pantalla de proveedores con casillas de verificación para marcar qué categorías abastece cada uno.",
             "Ninguno.",
             "Captura de pantalla de la interfaz de gestión de proveedores mostrando los checkboxes de categorías asignadas (Cerveza, Carnes, etc.)."),

            ("Alumno 3 (Pruebas & DevOps):",
             "Comprobé que los mozos y cocineros puedan ver las recetas sin errores.",
             "Voy a probar que si alguien intenta ponerle carne a un proveedor de cerveza, el sistema muestre un aviso de conflicto y no lo deje.",
             "Ninguno.",
             "Captura de la alerta en pantalla en el navegador mostrando el mensaje visual: 'El producto no corresponde al giro comercial del proveedor'.")
        ]),

        ("Daily 5 — Viernes 10 de Octubre (Consolidación y copia de seguridad integral)", [
            ("Alumno 1 (Backend & Base de Datos):",
             "Revisé todo el módulo de medidas y proveedores, limpiando consultas y asegurando la integridad referencial.",
             "Voy a dejar consolidada la base de datos local y verificar que todas las tablas queden enlazadas.",
             "Ninguno.",
             "Captura de la herramienta de base de datos mostrando las restricciones de Foreign Keys activas entre tablas de productos y proveedores."),

            ("Alumno 2 (Frontend & UI):",
             "Terminé la pantalla de proveedores con sus avisos de validación claros.",
             "Voy a revisar que las pantallas se vean ordenadas tanto en computadoras de oficina como en tablets.",
             "Ninguno.",
             "Captura del navegador usando las herramientas de desarrollador (F12) en modo emulación de Tablet / iPad mostrando la interfaz responsiva."),

            ("Alumno 3 (Pruebas & DevOps):",
             "Hice una revisión completa de las tablas y ninguna información se alteró.",
             "Voy a generar una copia de seguridad integral de toda la base de datos hasta este punto (barbarito_completa_20261010.backup).",
             "Ninguno, respaldo guardado con éxito.",
             "Captura de pantalla del explorador de archivos mostrando el archivo generado 'barbarito_completa_20261010.backup' con fecha y tamaño.")
        ]),

        ("Daily 6 — Lunes 13 de Octubre (Diseño de comanda y pedidos de salón)", [
            ("Alumno 1 (Backend & Base de Datos):",
             "Dejé la base de datos respaldada y lista el viernes.",
             "Voy a estructurar cómo se guardan los pedidos de salón para que admitan promociones de barra libre.",
             "Ninguno.",
             "Captura del modelo de datos / tabla SQL de comandas de salón preparada para asociar items con costo regular y costo cero."),

            ("Alumno 2 (Frontend & UI):",
             "Verifiqué que el catálogo de productos siga funcionando bien con las nuevas unidades.",
             "Voy a diseñar una ventana emergente para que cuando el mozo seleccione una promoción, pueda marcar qué platos o cervezas eligió el cliente.",
             "Ninguno.",
             "Captura de la interfaz de comanda táctil con botones grandes de categorías de carta (Entradas, Cervezas, Promociones)."),

            ("Alumno 3 (Pruebas & DevOps):",
             "Verifiqué que todas las pruebas de la semana pasada sigan operativas.",
             "Voy a armar un plan de pruebas para simular una mesa pidiendo promociones y platos a la carta a la vez.",
             "Ninguno.",
             "Captura de la planilla o checklist de pruebas funcionales registrando los casos de prueba para el módulo de pedidos de salón.")
        ]),

        ("Daily 7 — Miércoles 15 de Octubre (⭐ REDEFINICIÓN DEL PRODUCT BACKLOG Y BARRA LIBRE)", [
            ("Alumno 1 (Backend & Base de Datos):",
             "Participé junto al equipo en la sesión de Redefinición del Product Backlog (Proceso 10.3). Notamos que el backlog inicial no cubría la atención de salón ni el cobro de barra libre, por lo que redefinimos el Backlog agregando las historias de Salón (HU-16, HU-17) y reorganizamos prioridades con el Product Owner.",
             "Voy a programar la regla en base de datos para que las rondas adicionales de barra libre se guarden automáticamente con costo de S/. 0.00.",
             "Ninguno, tras redefinir el Backlog ahora el alcance está claro para todos.",
             "Captura del script SQL de migración (20261016_promociones_reposicion_salon.sql) con la columna es_reposicion y precio_unitario en 0.00."),

            ("Alumno 2 (Frontend & UI):",
             "Participé en la sesión de redefinición del Product Backlog, aportando en desglosar las pantallas de comanda en historias de usuario más pequeñas y manejables.",
             "Voy a diseñar el botón 'Reponer bebida gratis' en la mesa para que el mozo lo presione cuando el cliente solicite otra ronda.",
             "Ninguno.",
             "Captura del diseño en React mostrando el botón visual 'Reponer bebida gratis (S/. 0.00)' dentro de la comanda de la mesa."),

            ("Alumno 3 (Pruebas & DevOps):",
             "Actualicé el tablero de tareas con las nuevas Historias de Usuario redefinidas en el Product Backlog (sumando 29 puntos de historia para este sprint).",
             "Voy a preparar pruebas para intentar forzar un cobro en una reposición gratis y validar que el sistema lo impida.",
             "Ninguno.",
             "Captura del tablero Kanban (Trello, Jira o GitHub Projects) mostrando las tarjetas HU-16 y HU-17 añadidas al Sprint Backlog.")
        ]),

        ("Daily 8 — Viernes 17 de Octubre (Cobro de comanda y descuento de barril por receta)", [
            ("Alumno 1 (Backend & Base de Datos):",
             "Implementé la lógica para que al pagar la mesa, el sistema solo facture el costo base de la promoción y no cobre los vasos de reposición.",
             "Voy a validar que al cerrar la comanda, la receta descuente automáticamente los mililitros exactos del barril de cerveza en almacén.",
             "Ninguno.",
             "Captura de la función en Python que ejecuta la explosión de recetas y el descuento automático en producto_stock_local al pagar."),

            ("Alumno 2 (Frontend & UI):",
             "Agregué el botón de reposición gratis en la comanda del mozo.",
             "Voy a diseñar la boleta de venta en formato visual SVG con los ítems ordenados.",
             "Ajusté las dimensiones del comprobante SVG para que tenga tamaño estándar de ticket de bar.",
             "Captura de pantalla del comprobante de venta emitido en pantalla (ticket visual) mostrando la promo cobrada y las rondas a S/. 0.00."),

            ("Alumno 3 (Pruebas & DevOps):",
             "Hice la prueba completa de abrir una mesa, pedir barra libre y servir 3 rondas extras de cerveza.",
             "Voy a revisar en el inventario para confirmar que cada vaso servido se haya descontado de los litros del barril.",
             "Ninguno, el inventario descontó los litros exactos.",
             "Captura de la pantalla de Stock antes y después de la venta demostrando que el saldo del barril disminuyó en 1.419 litros (3 vasos).")
        ]),

        ("Daily 9 — Lunes 20 de Octubre (Actualización oficial de sedes y direcciones)", [
            ("Alumno 1 (Backend & Base de Datos):",
             "Dejé operativos los cobros de barra libre en el bar.",
             "Voy a preparar y ejecutar el script SQL para actualizar los códigos correlativos (TDA-001 a TDA-004) y las direcciones de Miraflores, Barranco, Sheraton y Santa Anita.",
             "Ninguno, el script se ejecutó sin alterar los identificadores internos.",
             "Captura de pgAdmin ejecutando el script 20261020_direcciones_locales.sql mostrando las 4 sedes de Barbarian actualizadas."),

            ("Alumno 2 (Frontend & UI):",
             "Dejé listas las boletas de pago visuales.",
             "Voy a ajustar la barra superior para que muestre claramente el nombre y código de la tienda activa en la que está el usuario.",
             "Ninguno.",
             "Captura de pantalla de la barra superior (Navbar) de la aplicación web mostrando el selector de sede con 'TDA-001 - Miraflores' activo."),

            ("Alumno 3 (Pruebas & DevOps):",
             "Probé los traslados y préstamos de insumos entre sedes para verificar la visualización.",
             "Voy a preparar los pasos y configuraciones necesarios para desplegar el proyecto en Render y Vercel.",
             "Ninguno.",
             "Captura del formulario de transferencias entre sedes mostrando una guía interna de remisión en estado 'En tránsito' hacia Barranco.")
        ]),

        ("Daily 10 — Jueves 23 de Octubre (Despliegue en Render y Vercel y salida a producción)", [
            ("Alumno 1 (Backend & Base de Datos):",
             "Identifiqué y corregí la incompatibilidad de conexión en Render, normalizando la URL de postgres:// a postgresql:// en config.py.",
             "Voy a supervisar que el servidor en Render inicie con Gunicorn y que el endpoint /api/health responda 200 OK.",
             "Resuelto con éxito, la conexión a la base de datos en la nube quedó estable.",
             "Captura del panel de Render mostrando el servicio web backend 'Live' y la respuesta JSON del endpoint /api/health en el navegador."),

            ("Alumno 2 (Frontend & UI):",
             "Elaboré la configuración para Vercel (vercel.json) para evitar que la página dé error 404 al recargar rutas como /home/stock.",
             "Voy a enlazar la página web con el servidor de Render y probar el inicio de sesión con los 4 usuarios corporativos.",
             "Ninguno, la aplicación cargó de forma fluida.",
             "Captura del panel de Vercel mostrando el despliegue exitoso ('Production') y la pantalla de Login cargada en el dominio de Vercel."),

            ("Alumno 3 (Pruebas & DevOps):",
             "Estructuré el script unificado dump_para_render.sql, subí el código a GitHub y restauré las 69 tablas en la base de datos de Render.",
             "Voy a realizar la prueba final de humo (Smoke Testing) navegando en la URL pública para declarar el proyecto formalmente entregado.",
             "Ninguno. El sistema ya se encuentra 100% operativo en internet y el Sprint concluyó con éxito total.",
             "Captura de la base de datos en la nube de Render mostrando las 69 tablas restauradas y captura del Dashboard navegando en internet.")
        ])
    ]

    for title, dev_reports in dailys:
        h_d = doc.add_heading(title, level=2)
        h_d.paragraph_format.space_before = Pt(11)
        h_d.paragraph_format.space_after = Pt(3)
        
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
            r_ev_lbl = p_ev.add_run("📸 Captura / Evidencia requerida para el Alumno: ")
            r_ev_lbl.bold = True
            r_ev_lbl.font.name = "Arial"
            r_ev_lbl.font.size = Pt(8.5)
            r_ev_lbl.font.color.rgb = HIGHLIGHT
            r_ev_txt = p_ev.add_run(evidence)
            r_ev_txt.font.name = "Arial"
            r_ev_txt.font.size = Pt(8.5)
            r_ev_txt.font.italic = True

    out_file = os.path.abspath("REGISTRO_DAILYS_SCRUM_CON_EVIDENCIAS.docx")
    doc.save(out_file)
    print(f"Documento de Dailys con evidencias generado en: {out_file}")

if __name__ == "__main__":
    create_dailys_with_evidence_doc()
