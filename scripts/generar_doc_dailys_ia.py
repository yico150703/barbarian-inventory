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
    run_sub = sub_p.add_run("Barbarian Inventory — Registro de Reuniones Diarias y Ciclo de Sprint")
    run_sub.font.name = "Arial"
    run_sub.font.size = Pt(12)
    run_sub.font.color.rgb = SECONDARY_COLOR

    meta_table = doc.add_table(rows=5, cols=2)
    meta_table.alignment = WD_TABLE_ALIGNMENT.CENTER
    meta_data = [
        ("Proyecto / Empresa:", "Barbarian Inventory — Cervecería Barbarian (Lima, Perú)"),
        ("Repositorio Oficial:", "https://github.com/yico150703/barbarian-inventory"),
        ("Infraestructura en la Nube:", "Render (Base de Datos PostgreSQL y API Backend) + Vercel (Frontend Web)"),
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

    # 2. CONTEXTO OPERATIVO
    h1 = doc.add_heading("1. Marco Operativo del Sprint", level=1)
    h1.paragraph_format.space_before = Pt(14)
    h1.paragraph_format.space_after = Pt(4)
    
    p_contexto = doc.add_paragraph(
        "El presente Sprint se desarrolló entre el 03 y el 23 de octubre de 2026 bajo el marco de trabajo Scrum (Guía SBOK). "
        "El equipo de 3 desarrolladores coordinó de manera diaria la estandarización de medidas de inventario, "
        "la consistencia entre productos y proveedores, la atención de salón con barra libre, la normalización de sedes "
        "y la puesta en marcha del sistema en la nube."
    )
    p_contexto.paragraph_format.space_after = Pt(6)

    # 3. LAS 10 DAILYS COMPLETAS (LENGUAJE PROFESIONAL Y DISCRETO)
    h2 = doc.add_heading("2. Registro Oficial de las 10 Dailys (03 al 23 de Octubre de 2026)", level=1)
    h2.paragraph_format.space_before = Pt(14)
    h2.paragraph_format.space_after = Pt(4)

    intro_daily = doc.add_paragraph(
        "Las reuniones diarias se realizaron respetando el Time-box de 15 minutos establecido en Scrum. "
        "A continuación se presenta el reporte cronológico de los 3 desarrolladores respondiendo las tres preguntas oficiales, "
        "destacando en la Daily 7 la sesión de Redefinición del Product Backlog (Proceso 10.3):"
    )
    intro_daily.paragraph_format.space_after = Pt(6)

    dailys_claras = [
        ("Daily 1 — Lunes 06 de Octubre (Análisis y estructura de medidas)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Analicé el esquema de la base de datos para identificar en qué tablas teníamos unidades escritas en texto libre.",
                "Voy a preparar la estructura de una nueva tabla con códigos internacionales estándar (kilos, litros, unidades).",
                "Ninguno por el momento, las 6 tablas involucradas quedaron claramente mapeadas."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Revisé los formularios de productos donde las unidades estaban puestas como texto manual.",
                "Voy a diseñar un menú desplegable moderno para que el usuario seleccione la unidad con un solo clic.",
                "Estaba esperando que Dev 1 me confirme la lista oficial de medidas que usaremos."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Preparé el repositorio en GitHub y configuré el entorno local para compartir el avance del equipo.",
                "Voy a crear un conjunto de datos de prueba para ensayar ingresos de productos con decimales.",
                "Ninguno."
            ])
        ]),

        ("Daily 2 — Martes 07 de Octubre (Script de unidades y componentes visuales)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Elaboré el script SQL para crear la tabla de medidas estándar (KGM, LTR, C62 y PORCION).",
                "Voy a probar el script en la base de datos local y agregar las restricciones de seguridad para no admitir unidades inventadas.",
                "Ajusté el script inicial para asegurar que conserve todos los datos históricos existentes sin pérdida."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Terminé el componente de selección de unidades para la interfaz gráfica.",
                "Voy a integrarlo en la pantalla de productos y verificar que muestre símbolos limpios y fáciles de leer (kg, L, und).",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Diseñé las pruebas para validar qué ocurre cuando un usuario ingresa cantidades pequeñas como 0.050 kilos de un insumo.",
                "Voy a verificar que la base de datos guarde los números con todos sus decimales sin redondear de forma imprecisa.",
                "Ninguno."
            ])
        ]),

        ("Daily 3 — Miércoles 08 de Octubre (Cálculo exacto de gramos y mililitros en recetas)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Programé la función matemática en Python para convertir automáticamente gramos a kilos y mililitros a litros.",
                "Voy a revisar que el cálculo utilice precisión decimal exacta (Decimal) para que el almacén no pierda miligramos en las recetas.",
                "Ninguno, la fórmula se ajustó correctamente a 3 decimales."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Actualicé la pantalla del catálogo de productos con los nuevos nombres de medida.",
                "Voy a colocar el selector de unidades en el editor de recetas para que el cocinero elija si usa gramos o porciones.",
                "Necesitaba que la función de Dev 1 estuviera lista para conectar el botón."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Hice pruebas de recetas ingresando 50 gramos de carne y 200 mililitros de salsa.",
                "Voy a verificar que al guardar la receta, el almacén reste exactamente esa fracción y no kilos completos.",
                "Ninguno, las pruebas pasaron correctamente."
            ])
        ]),

        ("Daily 4 — Jueves 09 de Octubre (Reglas de validación para proveedores y categorías)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Habilité el endpoint para consultar unidades y programé la regla para que cada proveedor solo venda sus categorías asignadas.",
                "Voy a ajustar el backend para que devuelva un aviso claro si intentan comprarle verduras a un proveedor de cerveza.",
                "Ninguno."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Conecté la pantalla de recetas con las nuevas medidas.",
                "Voy a rediseñar la pantalla de proveedores con casillas de verificación para marcar qué categorías abastece cada uno.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Comprobé que los mozos y cocineros puedan ver las recetas sin errores.",
                "Voy a probar que si alguien intenta ponerle carne a un proveedor de cerveza, el sistema muestre un aviso de conflicto y no lo deje.",
                "Ninguno."
            ])
        ]),

        ("Daily 5 — Viernes 10 de Octubre (Consolidación de código y copia de seguridad)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Revisé todo el módulo de medidas y proveedores, limpiando consultas y asegurando la integridad referencial.",
                "Voy a dejar consolidada la base de datos local y verificar que todas las tablas queden enlazadas.",
                "Ninguno."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Terminé la pantalla de proveedores con sus avisos de validación claros.",
                "Voy a revisar que las pantallas se vean ordenadas tanto en computadoras de oficina como en tablets.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas y Nube):", [
                "Hice una revisión completa de las tablas y ninguna información se alteró.",
                "Voy a generar una copia de seguridad integral de toda la base de datos hasta este punto (barbarito_completa_20261010.backup).",
                "Ninguno, respaldo guardado con éxito."
            ])
        ]),

        ("Daily 6 — Lunes 13 de Octubre (Diseño de comanda y promociones en Salón)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Dejé la base de datos respaldada y lista el viernes.",
                "Voy a estructurar cómo se guardan los pedidos de salón para que admitan promociones de barra libre.",
                "Ninguno."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Verifiqué que el catálogo de productos siga funcionando bien con las nuevas unidades.",
                "Voy a diseñar una ventana emergente para que cuando el mozo seleccione una promoción, pueda marcar qué platos o cervezas eligió el cliente.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas, Integración y Nube):", [
                "Verifiqué que todas las pruebas de la semana pasada sigan operativas.",
                "Voy a armar un plan de pruebas para simular una mesa pidiendo promociones y platos a la carta a la vez.",
                "Ninguno."
            ])
        ]),

        ("Daily 7 — Miércoles 15 de Octubre (⭐ REDEFINICIÓN DEL PRODUCT BACKLOG Y BARRA LIBRE)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Participé junto al equipo en la sesión de Redefinición del Product Backlog (Proceso 10.3). Notamos que el backlog inicial no cubría la atención de salón ni el cobro de barra libre, por lo que redefinimos el Backlog agregando las historias de Salón (HU-16, HU-17) y reorganizamos prioridades con el Product Owner.",
                "Voy a programar la regla en base de datos para que las rondas adicionales de barra libre se guarden automáticamente con costo de S/. 0.00.",
                "Ninguno, tras redefinir el Backlog ahora el alcance está claro para todos."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Participé en la sesión de redefinición del Product Backlog, aportando en desglosar las pantallas de comanda en historias de usuario más pequeñas y manejables.",
                "Voy a diseñar el botón 'Reponer bebida gratis' en la mesa para que el mozo lo presione cuando el cliente solicite otra ronda.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas, Integración y Nube):", [
                "Actualicé el tablero de tareas con las nuevas Historias de Usuario redefinidas en el Product Backlog (sumando 29 puntos de historia para este sprint).",
                "Voy a preparar pruebas para intentar forzar un cobro en una reposición gratis y validar que el sistema lo impida.",
                "Ninguno."
            ])
        ]),

        ("Daily 8 — Viernes 17 de Octubre (Cobro de comanda y descuento de barril por receta)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Implementé la lógica para que al pagar la mesa, el sistema solo facture el costo base de la promoción y no cobre los vasos de reposición.",
                "Voy a validar que al cerrar la comanda, la receta descuente automáticamente los mililitros exactos del barril de cerveza en almacén.",
                "Ninguno."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Agregué el botón de reposición gratis en la comanda del mozo.",
                "Voy a diseñar la boleta de venta en formato visual SVG con los ítems ordenados.",
                "Ajusté las dimensiones del comprobante SVG para que tenga tamaño estándar de ticket de bar."
            ]),
            ("Dev 3 (Pruebas, Integración y Nube):", [
                "Hice la prueba completa de abrir una mesa, pedir barra libre y servir 3 rondas extras de cerveza.",
                "Voy a revisar en el inventario para confirmar que cada vaso servido se haya descontado de los litros del barril.",
                "Ninguno, el inventario descontó los litros exactos."
            ])
        ]),

        ("Daily 9 — Lunes 20 de Octubre (Actualización oficial de sedes y direcciones)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Dejé operativos los cobros de barra libre en el bar.",
                "Voy a preparar y ejecutar el script SQL para actualizar los códigos correlativos (TDA-001 a TDA-004) y las direcciones de Miraflores, Barranco, Sheraton y Santa Anita.",
                "Ninguno, el script se ejecutó sin alterar los identificadores internos."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Dejé listas las boletas de pago visuales.",
                "Voy a ajustar la barra superior para que muestre claramente el nombre y código de la tienda activa en la que está el usuario.",
                "Ninguno."
            ]),
            ("Dev 3 (Pruebas, Integración y Nube):", [
                "Probé los traslados y préstamos de insumos entre sedes para verificar la visualización.",
                "Voy a preparar los pasos y configuraciones necesarios para desplegar el proyecto en Render y Vercel.",
                "Ninguno."
            ])
        ]),

        ("Daily 10 — Jueves 23 de Octubre (Despliegue en Render y Vercel y salida a producción)", [
            ("Dev 1 (Lógica y Base de Datos):", [
                "Identifiqué y corregí la incompatibilidad de conexión en Render, normalizando la URL de postgres:// a postgresql:// en config.py.",
                "Voy a supervisar que el servidor en Render inicie con Gunicorn y que el endpoint /api/health responda 200 OK.",
                "Resuelto con éxito, la conexión a la base de datos en la nube quedó estable."
            ]),
            ("Dev 2 (Pantallas y Diseño):", [
                "Elaboré la configuración para Vercel (vercel.json) para evitar que la página dé error 404 al recargar rutas como /home/stock.",
                "Voy a enlazar la página web con el servidor de Render y probar el inicio de sesión con los 4 usuarios corporativos.",
                "Ninguno, la aplicación cargó de forma fluida."
            ]),
            ("Dev 3 (Pruebas, Integración y Nube):", [
                "Estructuré el script unificado dump_para_render.sql, subí el código a GitHub y restauré las 69 tablas en la base de datos de Render.",
                "Voy a realizar la prueba final de humo (Smoke Testing) navegando en la URL pública para declarar el proyecto formalmente entregado.",
                "Ninguno. El sistema ya se encuentra 100% operativo en internet y el Sprint concluyó con éxito total."
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

    # 4. SECCIÓN 3: ACTA DE REDEFINICIÓN DEL PRODUCT BACKLOG (PROCESO 10.3)
    h3 = doc.add_heading("3. Redefinición del Product Backlog (Proceso 10.3 SBOK)", level=1)
    h3.paragraph_format.space_before = Pt(14)
    h3.paragraph_format.space_after = Pt(4)

    p_redef = doc.add_paragraph(
        "Durante la sesión del 15 de octubre (Daily 7), el Product Owner y el Equipo de Desarrollo revisaron "
        "el Product Backlog original. Se identificó la necesidad operativa de incorporar la gestión de atención en salón "
        "(punto de venta rápido para mozos) y la mecánica de reposición de barra libre sin costo adicional, "
        "reorganizando el esfuerzo y priorizando las historias clave para la operación en bares."
    )
    p_redef.paragraph_format.space_after = Pt(6)

    # Tabla resumen del Backlog Redefinido
    tbl_backlog = doc.add_table(rows=1, cols=5)
    tbl_backlog.alignment = WD_TABLE_ALIGNMENT.CENTER
    headers = ["ID", "Historia de Usuario", "Prioridad", "SP", "Estado"]
    for col_idx, h_text in enumerate(headers):
        cell = tbl_backlog.rows[0].cells[col_idx]
        p = cell.paragraphs[0]
        r = p.add_run(h_text)
        r.bold = True
        r.font.size = Pt(9.5)
        r.font.color.rgb = RGBColor(255, 255, 255)
        set_cell_background(cell, "1E3A8A")
        set_cell_margins(cell, 60, 60, 80, 80)

    backlog_items = [
        ("HU-01", "Autenticación segura y panel de control por sede", "Alta", "3", "Terminada"),
        ("HU-02", "Catálogo unificado con unidades de medida estándar", "Alta", "5", "Terminada"),
        ("HU-03", "Control de stock multisede y alertas de reposición", "Alta", "5", "Terminada"),
        ("HU-04", "Homologación de proveedores por categorías", "Media", "3", "Terminada"),
        ("HU-05", "Ciclo de órdenes de compra e ingreso a almacén", "Alta", "8", "Terminada"),
        ("HU-06", "Registro de mermas y ajustes directos de inventario", "Alta", "5", "Terminada"),
        ("HU-08", "Fichas técnicas de recetas y desglose de insumos", "Alta", "8", "Terminada"),
        ("HU-09", "Transferencias y préstamos entre sucursales", "Media", "5", "Terminada"),
        ("HU-10", "Cuadre de turno y conciliación físico vs. teórico", "Alta", "5", "Terminada"),
        ("HU-11", "Módulo analítico de rotación y exportación de datos", "Media", "5", "Terminada"),
        ("HU-13", "Administración de usuarios y perfiles por rol", "Alta", "5", "Terminada"),
        ("HU-14", "Bitácora de auditoría y trazabilidad de eventos", "Media", "3", "Terminada"),
        ("HU-16", "Módulo de salón, mapa de mesas y comanda rápida (TPV)", "Alta", "8", "Terminada"),
        ("HU-17", "Gestión de barra libre y reposición a costo cero (S/. 0.00)", "Alta", "5", "Terminada")
    ]

    for item in backlog_items:
        row = tbl_backlog.add_row()
        for c_idx, val in enumerate(item):
            cell = row.cells[c_idx]
            p = cell.paragraphs[0]
            r = p.add_run(val)
            r.font.size = Pt(9)
            if c_idx == 4:
                r.bold = True
                r.font.color.rgb = RGBColor(22, 101, 52)
            set_cell_background(cell, "F8FAFC" if len(tbl_backlog.rows) % 2 == 0 else "FFFFFF")
            set_cell_margins(cell, 40, 40, 60, 60)

    doc.add_paragraph().paragraph_format.space_after = Pt(8)

    # 5. SECCIÓN 4: GUÍA DE EVIDENCIAS Y CAPTURAS POR HISTORIA TERMINADA
    h4 = doc.add_heading("4. Guía de Evidencias y Capturas para la Entrega", level=1)
    h4.paragraph_format.space_before = Pt(14)
    h4.paragraph_format.space_after = Pt(4)

    p_evid = doc.add_paragraph(
        "A fin de sustentar la conformidad de cada Historia de Usuario implementada, a continuación se detallan "
        "las capturas de pantalla exactas que deben adjuntarse como evidencia funcional del sistema operativo:"
    )
    p_evid.paragraph_format.space_after = Pt(6)

    evidencias = [
        ("HU-01 (Autenticación y Dashboard):", "Captura del formulario de inicio de sesión ingresando con credenciales corporativas y captura del panel principal (Dashboard) mostrando los accesos según la sede asignada."),
        ("HU-02 (Catálogo y Unidades Estándar):", "Captura de la tabla de productos mostrando el menú desplegable de unidades estandarizadas (kg, L, porción, unidad) y los códigos internacionales KGM/LTR."),
        ("HU-03 (Stock Multisede y Alertas):", "Captura de la vista de inventario con el selector de tienda (Miraflores, Barranco, Sheraton, Santa Anita) y las alertas visuales destacadas cuando el stock cae por debajo del mínimo."),
        ("HU-04 (Proveedores y Categorías):", "Captura del formulario de proveedores mostrando la validación que restringe a cada proveedor a sus categorías de suministro autorizadas."),
        ("HU-05 (Órdenes de Compra):", "Captura del listado y detalle de una orden de compra con estado 'Aprobada' o 'Recibida', mostrando los insumos y montos totales."),
        ("HU-06 (Mermas y Ajustes):", "Captura del registro de merma especificando motivo (vencimiento, merma operativa) y comprobando el descuento inmediato en la tarjeta de stock."),
        ("HU-08 (Recetas y Subrecetas):", "Captura de la ficha técnica de un plato o cóctel con la lista de insumos en gramos o mililitros, demostrando el descuento automático por preparación."),
        ("HU-09 (Movimientos entre Sedes):", "Captura del formulario de traslado o préstamo de insumos entre locales mostrando el estado de la transferencia y la actualización de stock en ambas sedes."),
        ("HU-10 (Cierre de Turno Real vs. Teórico):", "Captura de la pantalla de cierre operativo mostrando la comparativa entre el conteo físico ingresado y el stock teórico calculado por el sistema."),
        ("HU-11 (Reportes y Exportación):", "Captura de la sección de reportes con filtros por fecha y sede, junto con la descarga generada en formato Excel o PDF."),
        ("HU-13 (Usuarios y Roles):", "Captura del panel de gestión de personal con los diferentes roles configurados (Administrador, Jefe de Cocina, Mozo, Almacenero)."),
        ("HU-14 (Auditoría y Trazabilidad):", "Captura del registro histórico de eventos (logs) donde se visualiza qué usuario realizó cada cambio con fecha y hora exacta."),
        ("HU-16 (Módulo Salón y TPV):", "Captura del mapa visual de mesas en salón con los estados (Libre, Ocupada, Cuenta solicitada) y la pantalla de ingreso rápido de comanda."),
        ("HU-17 (Barra Libre y Reposición a S/. 0.00):", "Captura del detalle de la comanda con promoción de barra libre y el botón de 'Reponer bebida gratis' reflejado con importe de S/. 0.00.")
    ]

    for hu_titulo, detalle_captura in evidencias:
        p_item = doc.add_paragraph()
        p_item.paragraph_format.left_indent = Inches(0.2)
        p_item.paragraph_format.space_before = Pt(2)
        p_item.paragraph_format.space_after = Pt(2)
        r_tit = p_item.add_run(hu_titulo + " ")
        r_tit.bold = True
        r_tit.font.size = Pt(9.5)
        r_tit.font.color.rgb = PRIMARY_COLOR
        r_det = p_item.add_run(detalle_captura)
        r_det.font.size = Pt(9.5)

    output_path = os.path.abspath("INFORME_BARBARIAN_INVENTORY_SCRUM.docx")
    doc.save(output_path)
    print(f"Documento Word actualizado con lenguaje discreto y profesional en: {output_path}")

if __name__ == "__main__":
    create_document()
