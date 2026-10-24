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

def set_cell_margins(cell, top=80, bottom=80, left=120, right=120):
    tcPr = cell._tc.get_or_add_tcPr()
    tcMar = parse_xml(f'<w:tcMar {nsdecls("w")}><w:top w:w="{top}" w:type="dxa"/><w:bottom w:w="{bottom}" w:type="dxa"/><w:left w:w="{left}" w:type="dxa"/><w:right w:w="{right}" w:type="dxa"/></w:tcMar>')
    tcPr.append(tcMar)

def create_document():
    doc = Document()
    
    for section in doc.sections:
        section.top_margin = Inches(0.9)
        section.bottom_margin = Inches(0.9)
        section.left_margin = Inches(0.9)
        section.right_margin = Inches(0.9)

    PRIMARY_COLOR = RGBColor(26, 54, 93)     # Azul marino
    SECONDARY_COLOR = RGBColor(194, 65, 12)  # Ámbar
    TEXT_MUTED = RGBColor(100, 116, 139)

    # 1. PORTADA
    title_p = doc.add_paragraph()
    title_p.paragraph_format.space_before = Pt(10)
    title_p.paragraph_format.space_after = Pt(4)
    run_title = title_p.add_run("INFORME DE GESTIÓN ÁGIL SCRUM Y DAILYS")
    run_title.font.name = "Arial"
    run_title.font.size = Pt(20)
    run_title.font.bold = True
    run_title.font.color.rgb = PRIMARY_COLOR

    sub_p = doc.add_paragraph()
    sub_p.paragraph_format.space_after = Pt(12)
    run_sub = sub_p.add_run("Barbarian Inventory — Desarrollo Asistido por IA Generativa y Redefinición de Backlog")
    run_sub.font.name = "Arial"
    run_sub.font.size = Pt(12)
    run_sub.font.color.rgb = SECONDARY_COLOR

    meta_table = doc.add_table(rows=5, cols=2)
    meta_table.alignment = WD_TABLE_ALIGNMENT.CENTER
    meta_data = [
        ("Proyecto / Empresa:", "Barbarian Inventory — Cervecería Barbarian (Lima, Perú)"),
        ("Repositorio Oficial:", "https://github.com/yico150703/barbarian-inventory"),
        ("Metodología & Enfoque:", "Scrum (Guía SBOK) con Desarrollo Acelerado mediante IA Generativa"),
        ("Equipo de Desarrollo:", "3 Desarrolladores (Dev 1: Backend/DB, Dev 2: Frontend/UI, Dev 3: Pruebas y Nube)"),
        ("Período del Sprint:", "03 de Octubre al 23 de Octubre de 2026 (10 Dailys de trabajo)")
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

    # 2. CONTEXTO METODOLÓGICO Y USO DE IA GENERATIVA
    h1 = doc.add_heading("1. Contexto Metodológico: Desarrollo Asistido por IA Generativa", level=1)
    h1.paragraph_format.space_before = Pt(14)
    h1.paragraph_format.space_after = Pt(4)
    
    p_contexto = doc.add_paragraph(
        "En este proyecto, el equipo de desarrollo no programó el código línea por línea de manera artesanal desde cero, "
        "sino que utilizó un flujo de trabajo moderno basado en IA Generativa. El rol de los 3 desarrolladores se centró en: "
        "1) Diseñar prompts técnicos precisos, 2) Evaluar y validar la lógica generada por la IA, 3) Corregir inconsistencias o errores de sintaxis, "
        "4) Integrar los módulos en la arquitectura del sistema y 5) Probar el comportamiento real con la base de datos y la nube."
    )
    p_contexto.paragraph_format.space_after = Pt(6)

    # 3. LAS 10 DAILYS COMPLETAS CON PREGUNTAS CLARAS
    h2 = doc.add_heading("2. Registro Oficial de las 10 Dailys (03 al 23 de Octubre de 2026)", level=1)
    h2.paragraph_format.space_before = Pt(14)
    h2.paragraph_format.space_after = Pt(4)

    intro_daily = doc.add_paragraph(
        "Las reuniones diarias se realizaron respetando el Time-box de 15 minutos establecido en Scrum. "
        "A continuación se presenta el reporte exacto de los 3 desarrolladores respondiendo las tres preguntas obligatorias, "
        "destacando en la Daily 7 la sesión formal de Redefinición del Product Backlog (Proceso 10.3):"
    )
    intro_daily.paragraph_format.space_after = Pt(6)

    dailys_claras = [
        ("Daily 1 — Lunes 06 de Octubre (Análisis y diseño de prompts de medidas)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Le pasé a la IA el esquema de la base de datos para que analice en qué tablas teníamos unidades escritas en texto libre.",
                "Voy a pedirle a la IA que redacte la estructura de una nueva tabla con códigos internacionales estándar (kilos, litros, unidades).",
                "Ninguno por el momento, la IA mapeó rápido las 6 tablas involucradas."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Revisé con la IA las pantallas de productos donde las unidades estaban escritas a mano.",
                "Voy a generar con IA un menú desplegable moderno para que el usuario seleccione la unidad con un solo clic.",
                "Estaba esperando que Dev 1 me confirme cuáles medidas usaremos."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Creé la carpeta de trabajo en GitHub para que los tres compartamos el código que vayamos integrando con la IA.",
                "Voy a preparar una base de datos de prueba en mi computadora para verificar que el código generado no borre nada.",
                "Ninguno."
            ])
        ]),

        ("Daily 2 — Martes 07 de Octubre (Generación de script de unidades con IA)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Generé con la IA el script SQL para crear la tabla de medidas estándar (KGM, LTR, C62 y PORCION).",
                "Voy a probar el script en la base de datos local y pedirle a la IA que le agregue candados de seguridad para no admitir unidades inventadas.",
                "La primera versión que me dio la IA intentó borrar datos antiguos; le pedí que corrigiera el prompt para que conserve todo intacto."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Generé con la IA el componente de selección de unidades para la interfaz gráfica.",
                "Voy a pegar el componente en la pantalla de productos y verificar que muestre símbolos limpios y fáciles de leer (kg, L, und).",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Le pedí a la IA que redacte pruebas para verificar qué pasa si un usuario escribe 0.050 kilos de un insumo.",
                "Voy a verificar que la base de datos guarde los números con todos sus decimales sin redondear de golpe.",
                "Ninguno."
            ])
        ]),

        ("Daily 3 — Miércoles 08 de Octubre (Cálculo exacto de gramos y mililitros)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Le pedí a la IA la función matemática en Python para convertir automáticamente gramos a kilos y mililitros a litros.",
                "Voy a revisar que el código generado por la IA use precisión decimal exacta (Decimal) para que el almacén no pierda miligramos en las recetas.",
                "Ninguno, la IA ajustó la fórmula a 3 decimales exactos."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Actualicé la pantalla del catálogo de productos con los nuevos nombres generados.",
                "Con ayuda de la IA, voy a colocar el selector de medidas en el editor de recetas para que el cocinero elija gramos o porciones.",
                "Necesito que la conexión que hizo Dev 1 ya esté activa para probar el botón."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Hice pruebas de recetas ingresando 50 gramos de carne y 200 mililitros de salsa en una receta generada.",
                "Voy a verificar que al guardar la receta, el almacén reste exactamente esa fracción y no kilos completos.",
                "Ninguno, las pruebas pasaron correctamente."
            ])
        ]),

        ("Daily 4 — Jueves 09 de Octubre (Reglas de proveedores generadas con IA)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Creé con la IA el endpoint para consultar unidades y le pedí generar la regla para que cada proveedor solo venda sus categorías asignadas.",
                "Voy a ajustar el backend para que devuelva un aviso claro si intentan comprarle verduras a un proveedor de cerveza.",
                "Ninguno."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Conecté la pantalla de recetas con las nuevas medidas generadas.",
                "Voy a pedirle a la IA que rediseñe la pantalla de proveedores con casillas de verificación para marcar qué categorías trae cada uno.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Probé que los mozos y cocineros puedan ver las recetas sin errores.",
                "Voy a probar que si alguien intenta ponerle carne a un proveedor de cerveza, el sistema muestre un aviso y no lo deje.",
                "Ninguno."
            ])
        ]),

        ("Daily 5 — Viernes 10 de Octubre (Consolidación de código y copia de seguridad)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Revisé todo el código generado por la IA en la semana sobre medidas y proveedores, limpiando líneas repetidas.",
                "Voy a dejar consolidada la base de datos local y verificar que todas las tablas estén conectadas.",
                "Ninguno."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Terminé la pantalla de proveedores generada con IA y sus avisos de error.",
                "Voy a revisar que las pantallas se vean bien tanto en la computadora de oficina como en la tablet del bar.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Hice una revisión completa de las tablas y ninguna información se perdió.",
                "Voy a guardar una copia de seguridad completa de toda la base de datos hasta este punto (barbarito_completa_20261010.backup).",
                "Ninguno, copia de seguridad guardada con éxito."
            ])
        ]),

        ("Daily 6 — Lunes 13 de Octubre (Diseño con IA de comanda y promociones)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Dejé la base de datos respaldada y lista el viernes.",
                "Voy a pedirle a la IA que analice cómo se guardan los pedidos de salón para que admitan promociones de barra libre.",
                "Ninguno."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Revisé que el catálogo siga funcionando bien con las nuevas unidades.",
                "Voy a pedirle a la IA que genere una ventana emergente para que cuando el mozo toque una promoción, pueda marcar qué platos o cervezas eligió el cliente.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas, Integración y Nube):", [
                "Verifiqué que todas las pruebas de la semana pasada sigan en verde.",
                "Voy a armar con la IA un plan de pruebas para simular una mesa que pide barra libre y toma varias rondas.",
                "Ninguno."
            ])
        ]),

        ("Daily 7 — Miércoles 15 de Octubre (⭐ REDEFINICIÓN DEL PRODUCT BACKLOG Y BARRA LIBRE)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Participé junto al equipo en la reunión de Redefinición del Product Backlog (Proceso 10.3). Notamos que el backlog original no incluía la atención de salón ni el cobro de barra libre, por lo que redefinimos el Backlog agregando las historias de Salón y reorganizamos prioridades con el Product Owner.",
                "Voy a generar con la IA la regla en base de datos para que las rondas adicionales de barra libre se guarden automáticamente con costo de S/. 0.00.",
                "Ninguno, tras redefinir el Backlog ahora el alcance está claro para todos."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Participé en la sesión de redefinición del Product Backlog, aportando en desglosar las pantallas de comanda en historias de usuario más pequeñas.",
                "Voy a pedirle a la IA que genere el botón 'Reponer bebida gratis' en la mesa para que el mozo lo presione cuando el cliente pida otra cerveza.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas, Integración y Nube):", [
                "Actualicé el tablero de tareas con las nuevas Historias de Usuario redefinidas en el Product Backlog (sumando 29 puntos de historia para este sprint).",
                "Voy a pedirle a la IA pruebas para intentar forzar un cobro en una reposición gratis y validar que el sistema lo impida.",
                "Ninguno."
            ])
        ]),

        ("Daily 8 — Viernes 17 de Octubre (Cobro de mesa y descuento de barril)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Integré la lógica generada con IA para que al pagar la mesa, el sistema solo facture el costo base de la promo y no cobre los vasos de reposición.",
                "Voy a validar que al cerrar la comanda, la receta descuente automáticamente los mililitros exactos del barril de cerveza en el almacén.",
                "Ninguno."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Integré el botón de reposición gratis generado por la IA en la comanda del mozo.",
                "Voy a pedirle a la IA el componente para dibujar la boleta de venta en formato visual SVG con los ítems ordenados.",
                "La IA generó el comprobante muy grande al principio; le pedí un prompt de ajuste para que tenga tamaño estándar de ticket."
            ]),
            ("Dev 3 (Pruebas, Integración y Nube):", [
                "Hice la prueba completa de abrir una mesa, pedir barra libre y servir 3 rondas extras de cerveza.",
                "Voy a revisar en el inventario para confirmar que cada vaso servido se haya descontado de los litros del barril.",
                "Ninguno, el inventario descontó los litros exactos."
            ])
        ]),

        ("Daily 9 — Lunes 20 de Octubre (Generación con IA de sedes y direcciones)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Dejé funcionando los cobros de barra libre en el bar.",
                "Voy a pedirle a la IA que redacte el script SQL para actualizar los códigos correlativos (TDA-001 a TDA-004) y las direcciones de Miraflores, Barranco, Sheraton y Santa Anita.",
                "Ninguno, el script se generó y corrió sin tocar los identificadores internos."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Dejé listas las boletas de pago visuales.",
                "Voy a ajustar la barra superior con ayuda de la IA para que muestre claramente el nombre y código de la tienda activa.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas, Integración y Nube):", [
                "Comencé a preparar todo para subir el proyecto a internet.",
                "Voy a comenzar a pedirle a la IA los pasos y configuraciones para subir el proyecto a Render y Vercel.",
                "Ninguno."
            ])
        ]),

        ("Daily 10 — Jueves 23 de Octubre (Despliegue asistido por IA en Render y Vercel)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Le consulté a la IA por qué Render fallaba al conectar la base de datos; me explicó que Render entrega la URL con postgres:// y SQLAlchemy requiere postgresql://, así que le pedí la corrección automática en config.py.",
                "Voy a vigilar que el servidor en Render prenda correctamente y responda sin caídas.",
                "Resuelto con éxito gracias a la corrección sugerida por la IA."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Le pedí a la IA la configuración para Vercel (vercel.json) para evitar que la página dé error 404 al recargar rutas como /home/stock.",
                "Voy a conectar la página web con el servidor de Render y probar el inicio de sesión con los 4 usuarios.",
                "Ninguno, la página cargó fluido."
            ]),
            ("Dev 3 (Pruebas, Integración y Nube):", [
                "Le pedí a la IA el script unificado dump_para_render.sql, subí todo el código a GitHub y restauré las 69 tablas en la base de datos de Render.",
                "Voy a hacer la prueba final entrando desde el navegador a la página en vivo para declarar el proyecto formalmente entregado.",
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

    output_path = os.path.abspath("INFORME_BARBARIAN_INVENTORY_SCRUM.docx")
    doc.save(output_path)
    print(f"Documento Word actualizado exitosamente en: {output_path}")

if __name__ == "__main__":
    create_document()
