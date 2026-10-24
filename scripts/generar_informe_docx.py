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

def set_cell_margins(cell, top=100, bottom=100, left=150, right=150):
    tcPr = cell._tc.get_or_add_tcPr()
    tcMar = parse_xml(f'<w:tcMar {nsdecls("w")}><w:top w:w="{top}" w:type="dxa"/><w:bottom w:w="{bottom}" w:type="dxa"/><w:left w:w="{left}" w:type="dxa"/><w:right w:w="{right}" w:type="dxa"/></w:tcMar>')
    tcPr.append(tcMar)

def create_document():
    doc = Document()
    
    # Configuración de márgenes
    for section in doc.sections:
        section.top_margin = Inches(1)
        section.bottom_margin = Inches(1)
        section.left_margin = Inches(1)
        section.right_margin = Inches(1)

    # Colores corporativos
    PRIMARY_COLOR = RGBColor(26, 54, 93)     # Azul marino
    SECONDARY_COLOR = RGBColor(194, 65, 12)  # Ámbar
    TEXT_MUTED = RGBColor(100, 116, 139)     # Gris

    # 1. PORTADA
    title_p = doc.add_paragraph()
    title_p.paragraph_format.space_before = Pt(10)
    title_p.paragraph_format.space_after = Pt(4)
    run_title = title_p.add_run("INFORME TÉCNICO Y METODOLÓGICO DE PROYECTO")
    run_title.font.name = "Arial"
    run_title.font.size = Pt(20)
    run_title.font.bold = True
    run_title.font.color.rgb = PRIMARY_COLOR

    sub_p = doc.add_paragraph()
    sub_p.paragraph_format.space_after = Pt(14)
    run_sub = sub_p.add_run("Sistema de Gestión de Inventarios, Abastecimiento y Salón — Barbarian Inventory")
    run_sub.font.name = "Arial"
    run_sub.font.size = Pt(12)
    run_sub.font.color.rgb = SECONDARY_COLOR

    # Metadatos
    meta_table = doc.add_table(rows=5, cols=2)
    meta_table.alignment = WD_TABLE_ALIGNMENT.CENTER
    meta_data = [
        ("Empresa / Proyecto:", "Cervecería Barbarian (Lima, Perú)"),
        ("Repositorio GitHub:", "https://github.com/yico150703/barbarian-inventory"),
        ("Infraestructura en la Nube:", "Render (Base de Datos y Backend API) + Vercel (Frontend Web)"),
        ("Equipo de Desarrollo:", "3 Desarrolladores (Dev 1: Backend/DB, Dev 2: Frontend, Dev 3: Pruebas y Nube)"),
        ("Metodología:", "Scrum (Guía SBOK) — Ciclo 8.1 al 10.3")
    ]
    for idx, (lbl, val) in enumerate(meta_data):
        row = meta_table.rows[idx]
        cell_lbl, cell_val = row.cells[0], row.cells[1]
        
        p0 = cell_lbl.paragraphs[0]
        r0 = p0.add_run(lbl)
        r0.bold = True
        r0.font.size = Pt(9.5)
        r0.font.color.rgb = PRIMARY_COLOR
        
        p1 = cell_val.paragraphs[0]
        r1 = p1.add_run(val)
        r1.font.size = Pt(9.5)
        
        set_cell_background(cell_lbl, "F1F5F9")
        set_cell_background(cell_val, "FFFFFF")
        set_cell_margins(cell_lbl, 60, 60, 100, 100)
        set_cell_margins(cell_val, 60, 60, 100, 100)

    doc.add_paragraph().paragraph_format.space_after = Pt(8)

    # 2. RESUMEN EJECUTIVO
    h1 = doc.add_heading("1. Resumen Ejecutivo y Arquitectura", level=1)
    h1.paragraph_format.space_before = Pt(14)
    h1.paragraph_format.space_after = Pt(4)
    
    p = doc.add_paragraph(
        "Este informe documenta la revisión del sistema Barbarian Inventory, confirmando que cumple con "
        "todas las historias de usuario requeridas. Además, detalla las mejoras realizadas después del 3 de octubre "
        "(estandarización de unidades de medida, reglas de proveedores, promociones de barra libre y sedes oficiales) "
        "y el despliegue funcional en internet mediante Render y Vercel."
    )
    p.paragraph_format.space_after = Pt(6)

    # 3. AUDITORÍA DE HISTORIAS DE USUARIO
    h2 = doc.add_heading("2. Auditoría de Historias de Usuario (PDF vs Sistema Real)", level=1)
    h2.paragraph_format.space_before = Pt(14)
    h2.paragraph_format.space_after = Pt(4)

    hu_table = doc.add_table(rows=1, cols=5)
    hu_table.alignment = WD_TABLE_ALIGNMENT.CENTER
    headers = ["ID", "Historia de Usuario", "Prioridad", "SP", "Estado en el Sistema"]
    hdr_cells = hu_table.rows[0].cells
    for i, title in enumerate(headers):
        p = hdr_cells[i].paragraphs[0]
        run = p.add_run(title)
        run.bold = True
        run.font.color.rgb = RGBColor(255, 255, 255)
        run.font.size = Pt(9)
        set_cell_background(hdr_cells[i], "1E3A8A")
        set_cell_margins(hdr_cells[i], 80, 80, 100, 100)

    hu_data = [
        ("HU-01", "Iniciar sesión y menú autorizado", "Must", "5", "Completado: Login seguro con permisos por rol y sede."),
        ("HU-02", "Gestionar usuarios operativos", "Should", "8", "Completado: Crear y editar personal sin correos repetidos."),
        ("HU-03", "Mantener catálogos (Productos/Proveedores)", "Must", "8", "Completado: Registro ordenado con motivo obligatorio."),
        ("HU-04", "Consultar carta y producción", "Could", "3", "Completado: Visualización de recetas, platos e insumos."),
        ("HU-05", "Consultar stock actual", "Must", "5", "Completado: Cálculo exacto de stock disponible y agotado."),
        ("HU-06", "Realizar inventario diario", "Must", "8", "Completado y ampliado a conteos 'Real vs Teórico'."),
        ("HU-08", "Movimientos extraordinarios", "Must", "5", "Completado: Registro de mermas, préstamos y devoluciones."),
        ("HU-09", "Pedido de compra sugerido", "Should", "5", "Completado: Cálculo automático de compra con 20% de margen."),
        ("HU-10", "Crear y enviar orden de compra", "Must", "5", "Completado: Guardar como borrador o enviar al proveedor."),
        ("HU-11", "Registrar recepciones de mercadería", "Must", "8", "Completado: Ingreso con factura y control de cantidades."),
        ("HU-13", "Consultar y corregir recepciones", "Should", "8", "Completado: Historial de facturas y corrección justificada."),
        ("HU-14", "Consultar actividad de usuarios", "Should", "3", "Completado: Pantalla de auditoría de quién hizo cada cambio.")
    ]

    for row_idx, data in enumerate(hu_data):
        row_cells = hu_table.add_row().cells
        bg_color = "F8FAFC" if row_idx % 2 == 0 else "FFFFFF"
        for col_idx, text in enumerate(data):
            p = row_cells[col_idx].paragraphs[0]
            run = p.add_run(text)
            run.font.size = Pt(8.5)
            if col_idx == 0:
                run.bold = True
            set_cell_background(row_cells[col_idx], bg_color)
            set_cell_margins(row_cells[col_idx], 60, 60, 80, 80)

    doc.add_paragraph().paragraph_format.space_after = Pt(6)

    # 4. METODOLOGÍA SCRUM (8.1 AL 10.3)
    h3 = doc.add_heading("3. Metodología Scrum: Proceso 8.1 al 10.3 (Guía SBOK)", level=1)
    h3.paragraph_format.space_before = Pt(14)
    h3.paragraph_format.space_after = Pt(4)

    scrum_steps = [
        ("8.1 Crear la Visión del Proyecto", "Se definió la meta: modernizar el inventario para no perder dinero en mermas, admitir barra libre en salón y operar en la nube."),
        ("8.2 Identificar Scrum Master y Stakeholders", "Se definieron los roles: Dueño del Producto (Operaciones Barbarian), Scrum Master (Líder facilitador) y usuarios clave (mozos, cocineros y almaceneros)."),
        ("8.3 Formar el Equipo Scrum", "Se formó un equipo ágil de 3 desarrolladores: Dev 1 (Lógica y Datos), Dev 2 (Pantallas y Diseño) y Dev 3 (Pruebas y Nube)."),
        ("8.4 Desarrollar Épicas", "Grandes bloques de trabajo: 1) Estandarizar unidades y proveedores, 2) Barra libre y comandas, 3) Sedes y subida a la nube."),
        ("8.5 Crear el Backlog Priorizado", "Se ordenaron las tareas por importancia con el método MoSCoW, sumando 29 puntos de historia."),
        ("8.6 Planificar el Lanzamiento", "Se organizó un Sprint de 2 semanas de trabajo para dejar el sistema listo en internet."),
        ("9.1 Crear Historias de Usuario", "Se escribieron las historias explicando quién la necesita, qué necesita y para qué beneficio."),
        ("9.2 Estimar Historias de Usuario", "El equipo votó la dificultad de cada tarea usando números de Planning Poker (3, 5, 8 puntos)."),
        ("9.3 Comprometer Historias de Usuario", "Los 3 desarrolladores acordaron terminar los 29 puntos comprometidos en el tiempo fijado."),
        ("9.4 Identificar Tareas", "Se dividió cada historia en tareas concretas de programación, pantallas y base de datos."),
        ("9.5 Estimar Tareas", "Se calculó un total de 56 horas de trabajo efectivo repartidas entre los 3 integrantes."),
        ("9.6 Crear el Sprint Backlog", "Se armó el tablero de trabajo con columnas: Por Hacer, En Proceso, En Revisión y Terminado."),
        ("10.1 Crear Entregables", "Se programaron las pantallas, se crearon los botones y se hicieron las conexiones seguras."),
        ("10.2 Realizar el Daily Standup", "Reuniones diarias de 15 minutos para responder qué se hizo, qué se hará y qué problemas hay."),
        ("10.3 Refinar el Backlog del Producto", "Revisión final para dejar listas las próximas mejoras que se le agregarán al sistema.")
    ]

    for title, desc in scrum_steps:
        p = doc.add_paragraph()
        r_title = p.add_run(f"• {title}: ")
        r_title.bold = True
        r_title.font.color.rgb = PRIMARY_COLOR
        p.add_run(desc)

    doc.add_page_break()

    # 5. LAS 10 DAILYS CON PREGUNTAS CLARAS
    h4 = doc.add_heading("4. Registro de las 10 Dailys (Reuniones Diarias - Equipo de 3 Devs)", level=1)
    h4.paragraph_format.space_before = Pt(14)
    h4.paragraph_format.space_after = Pt(4)

    intro_daily = doc.add_paragraph(
        "Cada reunión se realiza con un Time-box máximo de 15 minutos. En ella, cada uno de los 3 desarrolladores "
        "responde de forma directa y sin tecnicismos difíciles las tres preguntas obligatorias de Scrum:"
    )
    intro_daily.paragraph_format.space_after = Pt(6)

    dailys_claras = [
        ("Daily 1 — Lunes 06 de Octubre (Inicio y orden de medidas)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Revisé las tablas donde se guardan productos e insumos para ver cómo estaban escritas las unidades.",
                "Voy a preparar la lista oficial de medidas estándar (kilos, litros y unidades) para que la base de datos no se confunda.",
                "Ninguno por el momento."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Revisé los formularios de productos donde las unidades estaban escritas como texto libre.",
                "Voy a crear un menú desplegable para que el usuario pueda elegir fácilmente si el producto es kilo, litro o unidad.",
                "Estaba esperando que Dev 1 me confirme cuáles medidas usaremos."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Creé la carpeta de trabajo en GitHub para que los tres compartamos el código de forma ordenada.",
                "Voy a preparar una base de datos de prueba en mi computadora para verificar que nada se borre.",
                "Ninguno."
            ])
        ]),

        ("Daily 2 — Martes 07 de Octubre (Catálogo de unidades)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Definí los nombres de las medidas estándar y creé la tabla en la base de datos.",
                "Voy a programar las reglas para que el sistema no permita guardar productos con unidades inventadas.",
                "Ninguno, las pruebas locales salieron bien."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Terminé el menú desplegable para elegir unidades en pantalla.",
                "Voy a hacer que en la lista de productos se vean los símbolos claros (kg, L, und) para que el almacenero lo lea rápido.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Probé ingresar productos con cantidades decimales pequeñas (como 0.25 kilos de lúpulo).",
                "Voy a verificar que la base de datos guarde los números con todos sus decimales sin redondear de golpe.",
                "Ninguno."
            ])
        ]),

        ("Daily 3 — Miércoles 08 de Octubre (Gramos y mililitros en recetas)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Terminé la tabla de medidas y programé la fórmula matemática para convertir gramos a kilos y mililitros a litros.",
                "Voy a conectar esa fórmula con la cocina para que cuando descuenten una receta no haya descuadres en almacén.",
                "Ninguno."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Actualicé la pantalla del catálogo de productos con los nuevos nombres.",
                "Voy a poner el selector de medidas en la pantalla de recetas para que el cocinero elija si usa gramos o porciones.",
                "Necesito que la conexión que hizo Dev 1 ya esté activa."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Hice pruebas de recetas ingresando 50 gramos de carne y 200 mililitros de salsa.",
                "Voy a verificar que al guardar la receta, el almacén reste exactamente esa fracción y no kilos completos.",
                "Ninguno, las pruebas pasaron correctamente."
            ])
        ]),

        ("Daily 4 — Jueves 09 de Octubre (Control de proveedores y categorías)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Activé la conexión para consultar las medidas desde cualquier pantalla.",
                "Voy a programar una regla para que a cada proveedor solo se le puedan comprar las cosas que realmente vende.",
                "Ninguno."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Conecté la pantalla de recetas con las nuevas medidas.",
                "Voy a mejorar la pantalla de proveedores para que se puedan marcar con casillas qué tipos de productos nos trae cada uno.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Probé que los mozos y cocineros puedan ver las recetas sin errores.",
                "Voy a probar que si alguien intenta ponerle carne a un proveedor de cerveza, el sistema muestre un aviso y no lo deje.",
                "Ninguno."
            ])
        ]),

        ("Daily 5 — Viernes 10 de Octubre (Revisión y copia de seguridad)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Terminé las reglas de proveedores y categorías para que no haya compras cruzadas por error.",
                "Voy a revisar junto con el equipo que toda la información de productos y recetas esté impecable.",
                "Ninguno."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Terminé el formulario de proveedores con avisos claros si falta completar algún dato.",
                "Voy a revisar que las pantallas se vean bien tanto en la computadora de oficina como en la tablet del bar.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Hice una revisión completa de las tablas y ninguna información se perdió.",
                "Voy a guardar una copia de seguridad completa de toda la base de datos hasta este punto.",
                "Ninguno, copia de seguridad guardada con éxito."
            ])
        ]),

        ("Daily 6 — Lunes 13 de Octubre (Inicio de Barra Libre en el bar)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Dejé la base de datos respaldada y lista el viernes.",
                "Voy a diseñar la parte donde se guardan los pedidos de salón para que entiendan promociones de barra libre.",
                "Ninguno."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Revisé que el catálogo siga funcionando bien.",
                "Voy a diseñar la ventana donde el mozo elegirá qué cervezas o tragos incluye la barra libre que pidió la mesa.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Verifiqué que todas las pruebas de la semana pasada sigan en verde.",
                "Voy a armar una lista de pruebas para simular una mesa que pide barra libre y toma varias rondas.",
                "Ninguno."
            ])
        ]),

        ("Daily 7 — Martes 14 de Octubre (Botón para servir otra cerveza gratis)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Creé la tabla de promociones y la regla que dice que las rondas adicionales de barra libre valen cero soles.",
                "Voy a programar la lógica para que el mozo pueda agregar más rondas a la mesa sin que le cobre de más al cliente.",
                "Ninguno."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Terminé la ventana para elegir las opciones de la promoción.",
                "Voy a colocar un botón que diga 'Reponer bebida gratis' en la mesa para que el mozo lo presione en cada ronda.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Preparé pedidos de prueba con hamburguesas y barra libre juntas.",
                "Voy a probar que si alguien intenta cobrar una reposición de barra libre, el sistema lo bloquee y le cobre cero.",
                "Ninguno."
            ])
        ]),

        ("Daily 8 — Jueves 16 de Octubre (Cobrar la mesa y descontar del barril)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Terminé la lógica de pedidos para que admita las reposiciones gratuitas de bebidas.",
                "Voy a verificar que al momento de cobrar la mesa, el sistema solo cobre la promoción una vez y no cada vaso servido.",
                "Ninguno."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Terminé el botón de reposición gratis en la comanda del mozo.",
                "Voy a hacer que la boleta de venta en pantalla muestre ordenado cada vaso servido con costo de cero soles.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Hice la prueba completa de abrir una mesa, pedir promo y servir 3 rondas más de cerveza.",
                "Voy a revisar el inventario para confirmar que cada vaso servido se haya descontado de los litros del barril.",
                "Ninguno, el inventario descontó los litros exactos."
            ])
        ]),

        ("Daily 9 — Lunes 20 de Octubre (Actualizar locales y direcciones)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Dejé funcionando los cobros de barra libre en el bar.",
                "Voy a actualizar los nombres, códigos (TDA-001 a TDA-004) y direcciones exactas de las 4 sedes de Barbarian.",
                "Ninguno."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Dejé listas las boletas de pago.",
                "Voy a hacer que en la barra superior de la pantalla aparezca claramente en qué tienda está trabajando el usuario.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Comencé a preparar todo para subir el proyecto a internet.",
                "Voy a probar que cuando se pasen insumos de Miraflores a Barranco se vean los nombres y códigos nuevos.",
                "Ninguno."
            ])
        ]),

        ("Daily 10 — Jueves 23 de Octubre (Subir todo a internet: Render y Vercel)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Ajusté la configuración del backend para que se conecte a la base de datos de Render en la nube.",
                "Voy a vigilar que el servidor en Render prenda correctamente y responda sin caídas.",
                "Ninguno, se conectó a la primera."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Creé el archivo de configuración para que la página cargue en Vercel sin pantallas en blanco.",
                "Voy a conectar la página web con el servidor de Render y probar el inicio de sesión con los 4 usuarios.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Subí todo el código al repositorio de GitHub y restauré las 69 tablas en la base de datos de Render.",
                "Voy a hacer la prueba final entrando desde el navegador a la página en vivo para declarar el proyecto entregado.",
                "Ninguno. El sistema ya está funcionando en internet y listo para usar."
            ])
        ])
    ]

    for title, dev_reports in dailys_claras:
        h_daily = doc.add_heading(title, level=2)
        h_daily.paragraph_format.space_before = Pt(12)
        h_daily.paragraph_format.space_after = Pt(4)
        
        for dev_name, answers in dev_reports:
            p_dev = doc.add_paragraph()
            p_dev.paragraph_format.space_before = Pt(4)
            p_dev.paragraph_format.space_after = Pt(2)
            r_dev = p_dev.add_run(dev_name)
            r_dev.bold = True
            r_dev.font.color.rgb = PRIMARY_COLOR
            
            p_q1 = doc.add_paragraph()
            p_q1.paragraph_format.left_indent = Inches(0.25)
            p_q1.paragraph_format.space_after = Pt(1)
            r_q1 = p_q1.add_run("1. ¿Qué he hecho desde la última reunión?\n")
            r_q1.bold = True
            p_q1.add_run(answers[0])
            
            p_q2 = doc.add_paragraph()
            p_q2.paragraph_format.left_indent = Inches(0.25)
            p_q2.paragraph_format.space_after = Pt(1)
            r_q2 = p_q2.add_run("2. ¿Qué tengo planeado hacer antes de la siguiente reunión?\n")
            r_q2.bold = True
            p_q2.add_run(answers[1])
            
            p_q3 = doc.add_paragraph()
            p_q3.paragraph_format.left_indent = Inches(0.25)
            p_q3.paragraph_format.space_after = Pt(4)
            r_q3 = p_q3.add_run("3. ¿Qué impedimentos u obstáculos (si los hubiera) estoy enfrentando en la actualidad?\n")
            r_q3.bold = True
            p_q3.add_run(answers[2])

    doc.add_page_break()

    # 6. EVIDENCIAS
    h5 = doc.add_heading("5. Evidencias de la Base de Datos y Salida a Producción", level=1)
    h5.paragraph_format.space_before = Pt(14)
    h5.paragraph_format.space_after = Pt(4)

    doc.add_paragraph("Resumen comprobado en la base de datos de Render:")
    evidencias = [
        "Base de datos activa en Render: barbarito_41kk (PostgreSQL 18.6).",
        "Tablas creadas y funcionando: 69 tablas en total.",
        "Sedes oficiales: TDA-001 (Miraflores), TDA-002 (Barranco), TDA-003 (Sheraton), TDA-004 (Santa Anita).",
        "Usuarios listos para trabajar: crodriguez@barbarian.pe, jrios@barbarian.pe, rdiaz@barbarian.pe, mlopez@barbarian.pe.",
        "Total de productos en inventario: 141 productos cargados."
    ]
    for ev in evidencias:
        doc.add_paragraph(f"✓ {ev}")

    # 7. CONCLUSIÓN
    h6 = doc.add_heading("6. Conclusión y Próximos Pasos", level=1)
    h6.paragraph_format.space_before = Pt(14)
    h6.paragraph_format.space_after = Pt(4)
    doc.add_paragraph(
        "El proyecto Barbarian Inventory quedó 100% terminado, probado y en funcionamiento en la nube. "
        "Como siguientes pasos se recomienda habilitar la descarga de órdenes de compra en PDF para enviar "
        "directamente a los proveedores y la ficha de historial detallado de cada producto."
    )

    output_path = os.path.abspath("INFORME_BARBARIAN_INVENTORY_SCRUM.docx")
    doc.save(output_path)
    print(f"Documento actualizado exitosamente en: {output_path}")

if __name__ == "__main__":
    create_document()
