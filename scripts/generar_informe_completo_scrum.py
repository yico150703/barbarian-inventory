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

def create_full_scrum_report():
    doc = Document()
    
    for section in doc.sections:
        section.top_margin = Inches(0.85)
        section.bottom_margin = Inches(0.85)
        section.left_margin = Inches(0.85)
        section.right_margin = Inches(0.85)

    PRIMARY = RGBColor(26, 54, 93)     # Azul Marino Profundo
    SECONDARY = RGBColor(194, 65, 12)  # Ámbar Barbarian
    SUCCESS = RGBColor(22, 101, 52)    # Verde Éxito
    TEXT_DARK = RGBColor(15, 23, 42)   # Slate 900
    MUTED = RGBColor(100, 116, 139)    # Gris Medio

    # =========================================================================
    # PORTADA Y METADATOS
    # =========================================================================
    p_title = doc.add_paragraph()
    p_title.paragraph_format.space_before = Pt(8)
    p_title.paragraph_format.space_after = Pt(2)
    r_title = p_title.add_run("INFORME INTEGRAL DE GESTIÓN SCRUM Y PRODUCT BACKLOG")
    r_title.font.name = "Arial"
    r_title.font.size = Pt(18)
    r_title.font.bold = True
    r_title.font.color.rgb = PRIMARY

    p_sub = doc.add_paragraph()
    p_sub.paragraph_format.space_after = Pt(10)
    r_sub = p_sub.add_run("Sistema de Gestión de Inventarios, Abastecimiento y Salón — Barbarian Inventory")
    r_sub.font.name = "Arial"
    r_sub.font.size = Pt(11.5)
    r_sub.font.color.rgb = SECONDARY

    meta_tbl = doc.add_table(rows=6, cols=2)
    meta_tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    meta_data = [
        ("Proyecto / Empresa:", "Barbarian Inventory — Cervecería Barbarian (Lima, Perú)"),
        ("Marco Metodológico:", "Scrum Ágil (Guía SBOK) — Procesos 8.1 al 10.3"),
        ("Período del Sprint:", "03 de Octubre al 23 de Octubre de 2026 (10 Dailys de trabajo)"),
        ("Equipo de Desarrollo:", "3 Desarrolladores (Dev 1: Backend/DB, Dev 2: Frontend/UI, Dev 3: Pruebas y Nube)"),
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
        set_cell_margins(c0, 50, 50, 80, 80)
        set_cell_margins(c1, 50, 50, 80, 80)

    doc.add_paragraph().paragraph_format.space_after = Pt(6)

    # =========================================================================
    # SECCIÓN 1: PRODUCT BACKLOG OFICIAL Y REDEFINICIÓN (PROCESO 10.3)
    # =========================================================================
    h1 = doc.add_heading("1. Product Backlog Oficial y Redefinición (Proceso 10.3 SBOK)", level=1)
    h1.paragraph_format.space_before = Pt(12)
    h1.paragraph_format.space_after = Pt(4)

    p_pb_intro = doc.add_paragraph(
        "El Product Backlog es el inventario dinámico y priorizado de todos los requerimientos y mejoras "
        "del sistema Barbarian Inventory. Durante la sesión del 15 de octubre (Daily 7), se llevó a cabo el "
        "Proceso 10.3: Redefinición del Product Backlog, donde el Product Owner y el Equipo de Desarrollo "
        "incorporaron la operativa de comanda en salón (TPV) y la reposición de barra libre a costo cero (S/. 0.00), "
        "ordenando el alcance en 14 historias implementadas en este ciclo (73 SP) y 4 historias pendientes (26 SP) para el Release 2.0."
    )
    p_pb_intro.paragraph_format.space_after = Pt(6)

    tbl_pb = doc.add_table(rows=1, cols=6)
    tbl_pb.alignment = WD_TABLE_ALIGNMENT.CENTER
    pb_headers = ["ID", "Módulo", "Historia de Usuario", "SP", "Prioridad", "Estado"]
    for c_i, h_txt in enumerate(pb_headers):
        cell = tbl_pb.rows[0].cells[c_i]
        p = cell.paragraphs[0]
        p.paragraph_format.space_after = Pt(0)
        r = p.add_run(h_txt)
        r.font.name = "Arial"
        r.font.size = Pt(8.5)
        r.font.bold = True
        r.font.color.rgb = RGBColor(255, 255, 255)
        set_cell_background(cell, "1E3A8A")
        set_cell_margins(cell, 60, 60, 60, 60)

    pb_items = [
        ("HU-01", "Seguridad", "Autenticación segura y panel de control por sede", "3", "Must", "✅ Terminada"),
        ("HU-02", "Catálogo", "Catálogo unificado con unidades de medida estándar", "5", "Must", "✅ Terminada"),
        ("HU-03", "Inventario", "Control de stock multisede y alertas de reposición", "5", "Must", "✅ Terminada"),
        ("HU-04", "Compras", "Homologación de proveedores por categorías", "3", "Should", "✅ Terminada"),
        ("HU-05", "Compras", "Ciclo de órdenes de compra e ingreso a almacén", "8", "Must", "✅ Terminada"),
        ("HU-06", "Inventario", "Registro de mermas y ajustes directos de stock", "5", "Must", "✅ Terminada"),
        ("HU-08", "Catálogo", "Fichas técnicas de recetas y desglose de insumos", "8", "Must", "✅ Terminada"),
        ("HU-09", "Inventario", "Transferencias y préstamos entre sucursales", "5", "Should", "✅ Terminada"),
        ("HU-10", "Inventario", "Cuadre de turno y conciliación físico vs. teórico", "5", "Must", "✅ Terminada"),
        ("HU-11", "Analítica", "Módulo analítico de rotación y exportación Excel/PDF", "5", "Should", "✅ Terminada"),
        ("HU-13", "Seguridad", "Administración de usuarios y perfiles por rol", "5", "Must", "✅ Terminada"),
        ("HU-14", "Auditoría", "Bitácora de auditoría y trazabilidad de eventos", "3", "Should", "✅ Terminada"),
        ("HU-16", "Salón / POS", "Módulo de salón, mapa de mesas y comanda rápida (TPV)", "8", "Must", "✅ Terminada"),
        ("HU-17", "Salón / POS", "Promoción barra libre y reposición a costo cero (S/. 0.00)", "5", "Must", "✅ Terminada"),
        ("HU-07", "Inventario", "Conciliación y justificación formal de discrepancias", "8", "Must", "⏳ Pendiente"),
        ("HU-12", "Compras", "Anulación y cierre anticipado de órdenes de compra", "5", "Should", "⏳ Pendiente"),
        ("HU-15B", "Inventario", "Kardex valorizado y trazabilidad cronológica", "8", "Should", "⏳ Pendiente"),
        ("HU-17P", "Compras", "Exportación de orden de compra en PDF con membrete", "5", "Could", "⏳ Pendiente")
    ]

    for item in pb_items:
        row = tbl_pb.add_row()
        for col_i, val in enumerate(item):
            cell = row.cells[col_i]
            p = cell.paragraphs[0]
            p.paragraph_format.space_after = Pt(0)
            r = p.add_run(val)
            r.font.name = "Arial"
            r.font.size = Pt(8)
            if col_i == 5:
                r.bold = True
                if "Terminada" in val:
                    r.font.color.rgb = SUCCESS
                else:
                    r.font.color.rgb = SECONDARY
            set_cell_background(cell, "F8FAFC" if len(tbl_pb.rows) % 2 == 0 else "FFFFFF")
            set_cell_margins(cell, 40, 40, 50, 50)

    doc.add_paragraph().paragraph_format.space_after = Pt(6)

    # =========================================================================
    # SECCIÓN 2: HISTORIAS DE USUARIO POR MÓDULOS
    # =========================================================================
    h2 = doc.add_heading("2. Especificación de Historias de Usuario por Módulos", level=1)
    h2.paragraph_format.space_before = Pt(12)
    h2.paragraph_format.space_after = Pt(4)

    modulos_hu = [
        ("Módulo 1: Seguridad, Acceso y Plataforma", [
            ("HU-01: Autenticación Segura y Panel de Control por Sede", "3 SP | Must | ✅ Terminada",
             "Como usuario del sistema, quiero iniciar sesión con credenciales cifradas y seleccionar mi sede de trabajo para acceder únicamente a las funciones autorizadas.",
             "Validación de contraseña con hash seguro, emisión de JWT y carga del Dashboard según rol y sede asignada."),
            ("HU-13: Administración de Usuarios y Perfiles por Rol", "5 SP | Must | ✅ Terminada",
             "Como Administrador General, quiero crear, editar y asignar roles y sucursales permitidas al personal para controlar los privilegios de acceso y PIN de mozo.",
             "Matriz de roles (Administrador, Mozo, Cocinero, Almacén) y bloqueo estricto de opciones no autorizadas."),
            ("HU-14: Bitácora de Auditoría y Trazabilidad de Eventos", "3 SP | Should | ✅ Terminada",
             "Como Gerente o Auditor, quiero consultar un registro inmutable con el historial de eventos críticos para investigar cambios e identificar responsables.",
             "Registro de fecha/hora, usuario, IP, sede y detalle antes/después sin posibilidad de eliminación.")
        ]),
        ("Módulo 2: Catálogo de Productos y Recetas", [
            ("HU-02: Catálogo Unificado con Unidades de Medida Estándar", "5 SP | Must | ✅ Terminada",
             "Como Jefe de Almacén, quiero registrar productos con códigos de medida internacionales (KGM, LTR, C62) para evitar inconsistencias en el inventario.",
             "Selector con unidades estándar, clasificación por familias y precio de costo/venta."),
            ("HU-08: Fichas Técnicas de Recetas y Desglose de Insumos", "8 SP | Must | ✅ Terminada",
             "Como Maestro Cervecero o Cocinero, quiero registrar los ingredientes de cada plato o cerveza en gramos o mililitros para descontar stock automáticamente.",
             "Cálculo exacto hasta 3 decimales, soporte de subrecetas y explosión de insumos en cada venta.")
        ]),
        ("Módulo 3: Control de Inventario y Almacén Multisede", [
            ("HU-03: Control de Stock Multisede y Alertas de Reposición", "5 SP | Must | ✅ Terminada",
             "Como Encargado de Almacén, quiero consultar existencias en tiempo real por sede y recibir avisos visuales cuando el stock baje del mínimo.",
             "Filtro por tiendas (Miraflores, Barranco, Sheraton, Santa Anita) y banderas de alerta en rojo/naranja."),
            ("HU-06: Registro de Mermas y Ajustes Directos de Stock", "5 SP | Must | ✅ Terminada",
             "Como Jefe de Barra o Cocina, quiero registrar descartes por vencimiento o rotura con justificación para mantener el stock físico cuadrado.",
             "Motivos tipificados, descuento inmediato en kardex y aprobación administrativa en desvíos mayores."),
            ("HU-09: Transferencias y Préstamos entre Sucursales", "5 SP | Should | ✅ Terminada",
             "Como Administrador de Sede, quiero despachar y recepcionar insumos en préstamo hacia otros locales para apoyarnos sin incurrir en compras caras.",
             "Flujo con estados (En Tránsito -> Recibido), descuento en origen e ingreso en destino."),
            ("HU-10: Cierre Operativo de Turno y Conciliación Físico vs. Teórico", "5 SP | Must | ✅ Terminada",
             "Como Administrador de Turno, quiero registrar el conteo físico nocturno y compararlo contra el stock teórico para detectar desvíos en barra.",
             "Captura rápida de conteo físico, cálculo en pantalla de la diferencia y emisión del acta de cierre de jornada."),
            ("HU-07: Conciliación y Justificación de Discrepancias", "8 SP | Must | ⏳ Pendiente",
             "Como Auditor, quiero conciliar inventarios físicos cerrados con umbrales de tolerancia porcentual (5%) y bloqueo justificado.",
             "Programada para el Release 2.0."),
            ("HU-15B: Kardex y Trazabilidad Histórica por Producto", "8 SP | Should | ⏳ Pendiente",
             "Como Encargado de Costos, quiero consultar el kardex valorizado fila por fila de un insumo para auditar saldos acumulados.",
             "Programada para el Release 2.0.")
        ]),
        ("Módulo 4: Abastecimiento y Compras", [
            ("HU-04: Homologación de Proveedores por Categorías", "3 SP | Should | ✅ Terminada",
             "Como Encargado de Compras, quiero restringir a cada proveedor a sus categorías autorizadas para evitar compras no homologadas.",
             "Validación de RUC a 11 dígitos y bloqueo si la orden contiene insumos ajenos al giro del proveedor."),
            ("HU-05: Ciclo de Órdenes de Compra e Ingreso a Almacén", "8 SP | Must | ✅ Terminada",
             "Como Responsable de Compras, quiero emitir órdenes de compra y recepcionar mercadería para incrementar el stock y actualizar costos.",
             "Flujo formal de estados (Borrador -> Enviada -> Recepcionada) e incremento automático en el inventario local."),
            ("HU-12: Anulación y Cierre Anticipado de Órdenes", "5 SP | Should | ⏳ Pendiente",
             "Como Responsable de Compras, quiero anular órdenes erróneas o cerrar órdenes incompletas para liberar la bandeja de pendientes.",
             "Programada para el Release 2.0."),
            ("HU-17P: Exportación de Orden de Compra en PDF con Membrete", "5 SP | Could | ⏳ Pendiente",
             "Como Comprador, quiero generar el PDF oficial de la orden para enviarla al proveedor con logotipo y firmas.",
             "Programada para el Release 2.0.")
        ]),
        ("Módulo 5: Atención en Salón y Punto de Venta (TPV)", [
            ("HU-16: Módulo de Salón, Mapa de Mesas y Comanda Rápida", "8 SP | Must | ✅ Terminada",
             "Como Mozo, quiero abrir mesas interactivas en el plano del bar con mi PIN, registrar pedidos y enviar la comanda a cocina y barra.",
             "Mapa gráfico con colores de estado (Libre, Ocupada, Cuenta), pedidos rápidos y emisión de boleta visual."),
            ("HU-17: Promoción Barra Libre y Reposición a S/. 0.00", "5 SP | Must | ✅ Terminada",
             "Como Mozo y Barman, quiero aplicar la tarifa plana de barra libre y reponer rondas con un botón de S/. 0.00.",
             "Cobro único del paquete, reposiciones gratis en la cuenta y descuento exacto de mililitros del barril en almacén.")
        ]),
        ("Módulo 6: Analítica Gerencial y Reportes", [
            ("HU-11: Módulo Analítico de Rotación y Exportación de Datos", "5 SP | Should | ✅ Terminada",
             "Como Gerente de Operaciones, quiero visualizar gráficos de rotación y exportar datos en Excel y PDF para planificar compras.",
             "Filtros por fecha y local, gráficos de consumo y descarga limpia de archivos .xlsx y .pdf.")
        ])
    ]

    for mod_title, hu_list in modulos_hu:
        h_mod = doc.add_heading(mod_title, level=2)
        h_mod.paragraph_format.space_before = Pt(8)
        h_mod.paragraph_format.space_after = Pt(2)
        
        for hu_code_title, badges, narrative, criteria in hu_list:
            p_hu = doc.add_paragraph()
            p_hu.paragraph_format.left_indent = Inches(0.15)
            p_hu.paragraph_format.space_before = Pt(3)
            p_hu.paragraph_format.space_after = Pt(1)
            
            r_htit = p_hu.add_run(hu_code_title)
            r_htit.bold = True
            r_htit.font.name = "Arial"
            r_htit.font.size = Pt(9.5)
            r_htit.font.color.rgb = PRIMARY
            
            r_badge = p_hu.add_run(f"  [{badges}]\n")
            r_badge.font.name = "Arial"
            r_badge.font.size = Pt(8.5)
            r_badge.font.bold = True
            if "Terminada" in badges:
                r_badge.font.color.rgb = SUCCESS
            else:
                r_badge.font.color.rgb = SECONDARY
                
            r_desc = p_hu.add_run(f"Narrativa: {narrative}\n")
            r_desc.font.name = "Arial"
            r_desc.font.size = Pt(8.5)
            
            r_crit = p_hu.add_run(f"Criterio Clave: {criteria}")
            r_crit.font.name = "Arial"
            r_crit.font.size = Pt(8.5)
            r_crit.font.italic = True

    # =========================================================================
    # SECCIÓN 3: REGISTRO OFICIAL DE LAS 10 DAILYS (03 AL 23 DE OCTUBRE)
    # =========================================================================
    h3 = doc.add_heading("3. Registro Oficial de las 10 Dailys (03 al 23 de Octubre de 2026)", level=1)
    h3.paragraph_format.space_before = Pt(14)
    h3.paragraph_format.space_after = Pt(4)

    p_d_intro = doc.add_paragraph(
        "Las reuniones diarias se realizaron cumpliendo el Time-box de 15 minutos establecido en Scrum. "
        "A continuación se presenta el reporte técnico y directo de los 3 desarrolladores respondiendo a las "
        "tres preguntas oficiales, destacando en la Daily 7 la sesión de Redefinición del Product Backlog (Proceso 10.3):"
    )
    p_d_intro.paragraph_format.space_after = Pt(6)

    dailys_data = [
        ("Daily 1 — Lunes 06 de Octubre (Diagnóstico de unidades y estructura de datos)", [
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

        ("Daily 2 — Martes 07 de Octubre (Script de medidas estándar y componentes UI)", [
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
            ("Dev 3 (Pruebas y Nube):", [
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
            ("Dev 3 (Pruebas y Nube):", [
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
            ("Dev 3 (Pruebas y Nube):", [
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
            ("Dev 3 (Pruebas y Nube):", [
                "Probé los traslados y préstamos de insumos entre sedes para verificar la visualización.",
                "Voy a preparar los pasos y configuraciones necesarios para desplegar el proyecto en Render y Vercel.",
                "Ninguno."
            ])
        ]),

        ("Daily 10 — Jueves 23 de Octubre (Despliegue en la Nube y Salida a Producción)", [
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
            ("Dev 3 (Pruebas y Nube):", [
                "Estructuré el script unificado dump_para_render.sql, subí el código a GitHub y restauré las 69 tablas en la base de datos de Render.",
                "Voy a realizar la prueba final de humo (Smoke Testing) navegando en la URL pública para declarar el proyecto formalmente entregado.",
                "Ninguno. El sistema ya se encuentra 100% operativo en internet y el Sprint concluyó con éxito total."
            ])
        ])
    ]

    for title, dev_reports in dailys_data:
        h_d = doc.add_heading(title, level=2)
        h_d.paragraph_format.space_before = Pt(10)
        h_d.paragraph_format.space_after = Pt(2)
        
        for dev_name, answers in dev_reports:
            p_dev = doc.add_paragraph()
            p_dev.paragraph_format.left_indent = Inches(0.15)
            p_dev.paragraph_format.space_before = Pt(3)
            p_dev.paragraph_format.space_after = Pt(1)
            r_dev = p_dev.add_run(dev_name)
            r_dev.bold = True
            r_dev.font.name = "Arial"
            r_dev.font.size = Pt(9)
            r_dev.font.color.rgb = PRIMARY
            
            p_q1 = doc.add_paragraph()
            p_q1.paragraph_format.left_indent = Inches(0.3)
            p_q1.paragraph_format.space_after = Pt(1)
            r_q1 = p_q1.add_run("1. ¿Qué he hecho desde la última reunión?\n")
            r_q1.bold = True
            r_q1.font.name = "Arial"
            r_q1.font.size = Pt(8.5)
            r_ans1 = p_q1.add_run(answers[0])
            r_ans1.font.name = "Arial"
            r_ans1.font.size = Pt(8.5)
            
            p_q2 = doc.add_paragraph()
            p_q2.paragraph_format.left_indent = Inches(0.3)
            p_q2.paragraph_format.space_after = Pt(1)
            r_q2 = p_q2.add_run("2. ¿Qué tengo planeado hacer antes de la siguiente reunión?\n")
            r_q2.bold = True
            r_q2.font.name = "Arial"
            r_q2.font.size = Pt(8.5)
            r_ans2 = p_q2.add_run(answers[1])
            r_ans2.font.name = "Arial"
            r_ans2.font.size = Pt(8.5)
            
            p_q3 = doc.add_paragraph()
            p_q3.paragraph_format.left_indent = Inches(0.3)
            p_q3.paragraph_format.space_after = Pt(3)
            r_q3 = p_q3.add_run("3. ¿Qué impedimentos u obstáculos (si los hubiera) estoy enfrentando en la actualidad?\n")
            r_q3.bold = True
            r_q3.font.name = "Arial"
            r_q3.font.size = Pt(8.5)
            r_ans3 = p_q3.add_run(answers[2])
            r_ans3.font.name = "Arial"
            r_ans3.font.size = Pt(8.5)

    # =========================================================================
    # SECCIÓN 4: GUÍA DE EVIDENCIAS Y CAPTURAS
    # =========================================================================
    h4 = doc.add_heading("4. Guía de Evidencias y Capturas para la Entrega", level=1)
    h4.paragraph_format.space_before = Pt(12)
    h4.paragraph_format.space_after = Pt(4)

    p_ev_intro = doc.add_paragraph(
        "A continuación se detallan las capturas de pantalla exactas que deben adjuntarse para sustentar "
        "la conformidad de cada una de las 14 Historias de Usuario terminadas:"
    )
    p_ev_intro.paragraph_format.space_after = Pt(4)

    evidencias_data = [
        ("HU-01 (Autenticación y Dashboard):", "Captura del formulario de login corporativo y del panel principal (Dashboard) mostrando los módulos autorizados según la sede seleccionada."),
        ("HU-02 (Catálogo y Unidades Estándar):", "Captura de la tabla de productos mostrando el menú desplegable con códigos KGM, LTR, C62 y presentaciones estandarizadas."),
        ("HU-03 (Stock Multisede y Alertas):", "Captura de la vista de stock filtrada por sede (Miraflores, Barranco, etc.) con alertas visuales destacadas cuando el stock cae por debajo del mínimo."),
        ("HU-04 (Proveedores y Categorías):", "Captura del formulario de proveedores mostrando la validación que restringe a cada proveedor a sus categorías de suministro autorizadas."),
        ("HU-05 (Órdenes de Compra):", "Captura del listado y detalle de una orden de compra en estado 'Aprobada' o 'Recibida', mostrando los insumos y montos totales."),
        ("HU-06 (Mermas y Ajustes):", "Captura del registro de merma especificando motivo (vencimiento, derrame) y comprobando el descuento inmediato en la tarjeta de stock."),
        ("HU-08 (Recetas y Subrecetas):", "Captura de la ficha técnica de un plato o cóctel con la lista de insumos en gramos o mililitros, demostrando el descuento automático por preparación."),
        ("HU-09 (Movimientos entre Sedes):", "Captura del formulario de traslado o préstamo de insumos entre sucursales mostrando el estado 'En tránsito' y la actualización en destino."),
        ("HU-10 (Cierre de Turno Real vs. Teórico):", "Captura de la pantalla de cierre operativo mostrando la comparativa entre el conteo físico ingresado y el stock teórico calculado por el sistema."),
        ("HU-11 (Reportes y Exportación):", "Captura de la sección de reportes con filtros por fecha y sede, junto con la descarga generada en formato Excel o PDF."),
        ("HU-13 (Usuarios y Roles):", "Captura del panel de gestión de personal con los diferentes roles configurados (Administrador, Jefe de Cocina, Mozo, Almacenero)."),
        ("HU-14 (Auditoría y Trazabilidad):", "Captura del registro histórico de eventos (logs) donde se visualiza qué usuario realizó cada cambio con fecha y hora exacta."),
        ("HU-16 (Módulo Salón y TPV):", "Captura del mapa visual de mesas en salón con los estados (Libre, Ocupada, Cuenta solicitada) y la pantalla de ingreso rápido de comanda."),
        ("HU-17 (Barra Libre y Reposición a S/. 0.00):", "Captura del detalle de la comanda con promoción de barra libre y el botón de 'Reponer bebida gratis' reflejado con importe de S/. 0.00.")
    ]

    for hu_code, detail in evidencias_data:
        p_ev = doc.add_paragraph()
        p_ev.paragraph_format.left_indent = Inches(0.15)
        p_ev.paragraph_format.space_before = Pt(2)
        p_ev.paragraph_format.space_after = Pt(2)
        
        r_ecod = p_ev.add_run(hu_code + " ")
        r_ecod.bold = True
        r_ecod.font.name = "Arial"
        r_ecod.font.size = Pt(9)
        r_ecod.font.color.rgb = PRIMARY
        
        r_edet = p_ev.add_run(detail)
        r_edet.font.name = "Arial"
        r_edet.font.size = Pt(9)

    out_file = os.path.abspath("INFORME_BARBARIAN_INVENTORY_SCRUM.docx")
    doc.save(out_file)
    print(f"Informe completo generado con éxito en: {out_file}")

if __name__ == "__main__":
    create_full_scrum_report()
