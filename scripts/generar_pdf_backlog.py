import os
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether, HRFlowable
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.pdfgen import canvas

class NumberedCanvas(canvas.Canvas):
    def __init__(self, *args, **kwargs):
        super(NumberedCanvas, self).__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_page_number(num_pages)
            super(NumberedCanvas, self).showPage()
        super(NumberedCanvas, self).save()

    def draw_page_number(self, page_count):
        self.saveState()
        self.setFont("Helvetica", 8)
        self.setFillColor(colors.HexColor("#64748B"))
        
        # Header (en páginas > 1)
        if self._pageNumber > 1:
            self.drawString(40, 755, "Barbarian Inventory — Product Backlog Redefinido")
            self.setStrokeColor(colors.HexColor("#E2E8F0"))
            self.setLineWidth(0.5)
            self.line(40, 750, 572, 750)
            
        # Footer
        self.setStrokeColor(colors.HexColor("#E2E8F0"))
        self.setLineWidth(0.5)
        self.line(40, 42, 572, 42)
        
        footer_text = f"Página {self._pageNumber} de {page_count}"
        self.drawRightString(572, 30, footer_text)
        self.drawString(40, 30, "Documento de Gestión Ágil Scrum (SBOK Guide) — Sin módulo de IA")
        self.restoreState()

def build_pdf(filename="PRODUCT_BACKLOG_REDEFINIDO_BARBARIAN.pdf"):
    doc = SimpleDocTemplate(
        filename,
        pagesize=letter,
        leftMargin=40,
        rightMargin=40,
        topMargin=50,
        bottomMargin=50
    )

    styles = getSampleStyleSheet()

    # Estilos tipográficos
    style_title = ParagraphStyle(
        'DocTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=20,
        leading=24,
        textColor=colors.HexColor("#1E3A8A"),
        spaceAfter=4
    )
    style_subtitle = ParagraphStyle(
        'DocSub',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=11,
        leading=15,
        textColor=colors.HexColor("#C2410C"),
        spaceAfter=12
    )
    style_p = ParagraphStyle(
        'BodyP',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=9,
        leading=13,
        textColor=colors.HexColor("#1E293B"),
        spaceAfter=6
    )
    style_epic_hdr = ParagraphStyle(
        'EpicHeader',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=12,
        leading=16,
        textColor=colors.HexColor("#0F172A"),
        spaceBefore=14,
        spaceAfter=8
    )
    style_hu_title = ParagraphStyle(
        'HUTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=11,
        leading=14,
        textColor=colors.HexColor("#0F172A"),
        spaceBefore=10,
        spaceAfter=4
    )
    style_tbl_lbl = ParagraphStyle(
        'TblLbl',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=8.5,
        leading=11,
        textColor=colors.HexColor("#1E293B")
    )
    style_tbl_val = ParagraphStyle(
        'TblVal',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8.5,
        leading=11,
        textColor=colors.HexColor("#0F172A")
    )
    style_crit = ParagraphStyle(
        'CritP',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8.5,
        leading=12,
        textColor=colors.HexColor("#1E293B"),
        leftIndent=12,
        spaceAfter=3
    )

    story = []

    # 1. PORTADA / ENCABEZADO
    story.append(Paragraph("PRODUCT BACKLOG REDEFINIDO", style_title))
    story.append(Paragraph("Barbarian Inventory — Catálogo Estructurado de Requerimientos (Scrum SBOK)", style_subtitle))
    story.append(HRFlowable(width="100%", thickness=1.5, color=colors.HexColor("#1E3A8A"), spaceBefore=0, spaceAfter=12))

    intro_text = (
        "<b>Propósito de la Redefinición:</b> En la metodología Scrum, el <i>Product Backlog Refinement</i> "
        "(proceso 10.3) permite adaptar la lista maestra de requerimientos conforme madura el entendimiento operativo "
        "del negocio. El presente documento reestructura las Historias de Usuario (HU) en <b>7 Épicas coherentes</b> "
        "según el ciclo real de un restaurante/cervecería (Seguridad, Catálogos, Stock, Compras, Movimientos, Salón y Auditoría), "
        "clasificando con total transparencia cuáles están <b>✅ Hechas (Implementadas en el sistema)</b> y cuáles están "
        "<b>⏳ Faltantes (Pendientes de desarrollo)</b>. <i>(Nota: No se incluye el módulo de Inteligencia Artificial conforme a los alcances de la asignatura).</i>"
    )
    story.append(Paragraph(intro_text, style_p))
    story.append(Spacer(1, 10))

    # RESUMEN ESTADÍSTICO
    resumen_data = [
        [
            Paragraph("<b>Estado de la Historia</b>", style_tbl_lbl),
            Paragraph("<b>Cantidad</b>", style_tbl_lbl),
            Paragraph("<b>Story Points (Esfuerzo)</b>", style_tbl_lbl),
            Paragraph("<b>Porcentaje de Cobertura</b>", style_tbl_lbl)
        ],
        [
            Paragraph("<font color='#166534'><b>✅ IMPLEMENTADAS EN EL SISTEMA (HECHAS)</b></font>", style_tbl_val),
            Paragraph("<b>19 Historias</b>", style_tbl_val),
            Paragraph("<b>112 SP</b>", style_tbl_val),
            Paragraph("<b>81.2 %</b>", style_tbl_val)
        ],
        [
            Paragraph("<font color='#C2410C'><b>⏳ PENDIENTES DE DESARROLLO (FALTANTES)</b></font>", style_tbl_val),
            Paragraph("<b>4 Historias</b>", style_tbl_val),
            Paragraph("<b>26 SP</b>", style_tbl_val),
            Paragraph("<b>18.8 %</b>", style_tbl_val)
        ],
        [
            Paragraph("<b>TOTAL PRODUCT BACKLOG REDEFINIDO</b>", style_tbl_lbl),
            Paragraph("<b>23 Historias</b>", style_tbl_lbl),
            Paragraph("<b>138 SP</b>", style_tbl_lbl),
            Paragraph("<b>100.0 %</b>", style_tbl_lbl)
        ]
    ]

    t_resumen = Table(resumen_data, colWidths=[230, 90, 110, 102])
    t_resumen.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.HexColor("#F1F5F9")),
        ('BACKGROUND', (0,1), (-1,1), colors.HexColor("#F0FDF4")),
        ('BACKGROUND', (0,2), (-1,2), colors.HexColor("#FFF7ED")),
        ('BACKGROUND', (0,3), (-1,3), colors.HexColor("#E2E8F0")),
        ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
        ('TOPPADDING', (0,0), (-1,-1), 6),
        ('BOTTOMPADDING', (0,0), (-1,-1), 6),
        ('LEFTPADDING', (0,0), (-1,-1), 8),
        ('RIGHTPADDING', (0,0), (-1,-1), 8),
    ]))
    story.append(t_resumen)
    story.append(Spacer(1, 14))

    # LISTA DE TARJETAS DE HISTORIAS DE USUARIO
    historias = [
        # --- ÉPICA 1: SEGURIDAD Y ACCESOS ---
        {
            "epic": "ÉPICA 1: SEGURIDAD, PERFILES Y ACCESOS RÁPIDOS",
            "id": "HU-01",
            "nombre": "Iniciar sesión y cargar el menú autorizado",
            "sp": 5,
            "prioridad": "Must",
            "etiquetas": "Seguridad · Crítica",
            "dependencias": "Usuarios activos, perfiles, permisos y opciones de menú configurados",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como usuario autorizado, quiero iniciar sesión y visualizar únicamente las opciones habilitadas para mi perfil para acceder de forma segura a las funciones que me corresponden.",
            "valor": "Acceder de forma segura a las funciones que me corresponden.",
            "base_funcional": "API /api/auth/login, /api/auth/me y permisos por opción de menú (LoginPage.tsx).",
            "criterios": [
                "Dado que el usuario, su perfil y su cuenta están activos, cuando ingresa un correo y una contraseña válidos, entonces el sistema devuelve una sesión válida, sus datos de usuario y el menú permitido.",
                "Dado que las credenciales son incorrectas, cuando intenta iniciar sesión, entonces el sistema responde con un mensaje genérico y no revela si el correo existe.",
                "Dado que el usuario o su perfil está inactivo, cuando intenta autenticarse, entonces el acceso es rechazado y no se crea una sesión.",
                "Dado que un usuario autenticado intenta ejecutar una acción sin permiso, cuando invoca la operación, entonces la API responde 403 y no modifica datos."
            ]
        },
        {
            "epic": None,
            "id": "HU-02",
            "nombre": "Gestionar usuarios operativos",
            "sp": 8,
            "prioridad": "Should",
            "etiquetas": "Seguridad · Alta",
            "dependencias": "HU-01 y matriz de perfiles gestionables",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como administrador de usuarios, quiero crear, editar, activar y desactivar usuarios dentro de los perfiles que puedo gestionar para mantener el acceso del personal actualizado y controlado.",
            "valor": "Mantener el acceso del personal actualizado y controlado.",
            "base_funcional": "Módulo usuarios y perfil_gestion_usuario (UsersPage.tsx).",
            "criterios": [
                "Dado que el administrador tiene permiso para crear el perfil seleccionado, cuando registra DNI de 8 dígitos, celular de 9 a 15 dígitos, correo válido y contraseña de al menos 8 caracteres, entonces el usuario se crea con el perfil indicado.",
                "Dado que el DNI o correo ya está registrado, cuando se intenta crear o editar el usuario, entonces el sistema rechaza la operación con conflicto y conserva los datos existentes.",
                "Dado que el administrador no puede gestionar el perfil objetivo, cuando intenta crearlo, editarlo o asignarlo, entonces la API responde 403.",
                "Dado que un administrador intenta desactivar su propia cuenta, cuando confirma la acción, entonces el sistema la rechaza y registra únicamente los cambios de usuario permitidos en auditoría."
            ]
        },
        {
            "epic": None,
            "id": "HU-02B",
            "nombre": "Acceso rápido al salón mediante PIN operativo",
            "sp": 5,
            "prioridad": "Must",
            "etiquetas": "Salón · Seguridad",
            "dependencias": "HU-01 y asignación de puesto Mesero/Bartender",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como mesero o bartender, quiero iniciar sesión en el salón mediante un PIN numérico de 4 dígitos para acceder rápidamente a la atención de mesas sin escribir contraseñas largas en la pantalla del bar.",
            "valor": "Agilidad y rapidez en la toma de pedidos durante la atención al cliente.",
            "base_funcional": "API /api/salon/login, SalonAccess.tsx y SalonPinDialog.tsx.",
            "criterios": [
                "Dado un usuario con puesto Mesero o Bartender y PIN asignado, cuando ingresa su sede y PIN correcto, entonces el sistema genera una sesión de salón temporal de 2 horas.",
                "Dado que se ingresa un PIN erróneo más de 3 veces consecutivas, entonces la API bloquea temporalmente los intentos por seguridad.",
                "Dado que el administrador edita un usuario, cuando ingresa un nuevo PIN de 4 dígitos, entonces se actualiza y encripta en base de datos sin guardarse en texto plano."
            ]
        },

        # --- ÉPICA 2: CATÁLOGOS, PRODUCTOS Y RECETAS ---
        {
            "epic": "ÉPICA 2: CATÁLOGOS MAESTROS, PRODUCTOS Y RECETAS",
            "id": "HU-03",
            "nombre": "Mantener categorías proveedores y productos",
            "sp": 8,
            "prioridad": "Must",
            "etiquetas": "Catálogos · Crítica",
            "dependencias": "HU-01 y permisos de catálogo",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como responsable de catálogos, quiero crear, editar, desactivar y reactivar categorías, proveedores y productos para contar con un catálogo confiable para inventarios y compras.",
            "valor": "Contar con un catálogo confiable para inventarios y compras.",
            "base_funcional": "API /api/catalogos y pantallas de productos, categorías y proveedores.",
            "criterios": [
                "Dado que los datos son válidos y no duplicados, cuando se registra una categoría, proveedor o producto, entonces se genera el registro activo y se devuelve confirmación.",
                "Dado que se edita un producto, cuando se seleccionan una categoría y un proveedor activos, entonces se guardan nombre, unidad, presentación y stock mínimo válidos.",
                "Dado que una categoría o proveedor mantiene productos activos, cuando se solicita desactivarlo, entonces el sistema exige reasignar o desactivar primero sus dependencias.",
                "Dado que se desactiva o reactiva un registro, cuando se envía un motivo de al menos 10 caracteres, entonces se cambia el estado y se registra la actividad del usuario."
            ]
        },
        {
            "epic": None,
            "id": "HU-04",
            "nombre": "Consultar catálogos de carta y producción",
            "sp": 3,
            "prioridad": "Could",
            "etiquetas": "Carta y producción · Media",
            "dependencias": "HU-01 y datos maestros cargados",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como usuario operativo, quiero consultar categorías de carta, presentaciones, menajes, subproductos, grupos de salsa, recetas y promociones para conocer la composición operativa asociada a los insumos.",
            "valor": "Conocer la composición operativa asociada a los insumos.",
            "base_funcional": "Módulos carta, producción, recetas y promociones.",
            "criterios": [
                "Dado que el usuario tiene permiso de consulta, cuando abre un catálogo, entonces visualiza los registros activos con sus relaciones principales.",
                "Dado que una presentación tiene receta o grupo de salsa, cuando se consulta su detalle, entonces se muestran componentes, cantidades y unidades disponibles.",
                "Dado que existe una promoción con horario, cuando se consulta, entonces se muestran precio, intervalo horario, grupos y opciones configuradas.",
                "Dado que el perfil no tiene permiso para una opción, cuando intenta consultar su API, entonces recibe 403 y no obtiene el catálogo."
            ]
        },
        {
            "epic": None,
            "id": "HU-04B",
            "nombre": "Formulación de subproductos de producción",
            "sp": 5,
            "prioridad": "Should",
            "etiquetas": "Producción · Media",
            "dependencias": "HU-03 y HU-04",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como jefe de cocina o maestro cervecero, quiero formular subproductos (jarabes, salsas cocinadas, premezclas) con sus insumos de inventario y rendimiento para utilizarlos como ingredientes en recetas finales.",
            "valor": "Estandarización y control de costos de preparaciones intermedias.",
            "base_funcional": "API /api/produccion/subproductos y SubproductsPage.tsx.",
            "criterios": [
                "Dado que se registra un nuevo subproducto, entonces el sistema genera automáticamente el código correlativo SP-XXXX.",
                "Dado que se agregan ingredientes de inventario, cuando se guardan cantidades y rendimiento, entonces se calculan las equivalencias correspondientes.",
                "Dado que un subproducto está vinculado como ingrediente en una receta de carta activa, cuando se intenta desactivar, entonces el sistema rechaza la operación."
            ]
        },
        {
            "epic": None,
            "id": "HU-04C",
            "nombre": "Configuración de límites de stock por tienda",
            "sp": 5,
            "prioridad": "Must",
            "etiquetas": "Catálogos · Alta",
            "dependencias": "HU-03 y perfil Gerente",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como gerente de tienda, quiero configurar el stock mínimo y máximo de cada producto exclusivamente para mi local para adaptar el abastecimiento al volumen de ventas de mi sede.",
            "valor": "Gestión descentralizada y precisa de niveles de inventario por sede.",
            "base_funcional": "API /api/catalogos/limites-stock y StockLimitsPage.tsx.",
            "criterios": [
                "Dado un usuario con perfil Gerente (ID 2), cuando accede a límites de stock, entonces puede editar el mínimo y máximo de su sede activa.",
                "Dado que se ingresan valores de stock, cuando se confirma, entonces el sistema valida que el stock máximo sea mayor o igual al mínimo.",
                "Dado que se guardan los límites, cuando finaliza la transacción, entonces se actualiza la tabla producto_stock_local sin alterar los límites de otras tiendas."
            ]
        },

        # --- ÉPICA 3: CONTROL DE EXISTENCIAS E INVENTARIOS ---
        {
            "epic": "ÉPICA 3: CONTROL DE EXISTENCIAS E INVENTARIOS",
            "id": "HU-05",
            "nombre": "Consultar el stock actual",
            "sp": 5,
            "prioridad": "Must",
            "etiquetas": "Inventario · Crítica",
            "dependencias": "HU-03 y al menos un inventario cerrado",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como encargado de almacén, quiero consultar existencias y su estado por producto para detectar faltantes y tomar decisiones de reposición.",
            "valor": "Detectar faltantes y tomar decisiones de reposición.",
            "base_funcional": "API /api/inventarios/stock y StockPage.tsx.",
            "criterios": [
                "Dado que existe un último conteo cerrado, cuando se consulta el stock, entonces el sistema calcula: conteo + recepciones y entradas posteriores - salidas posteriores.",
                "Dado que un producto no tiene conteo cerrado previo, se muestra como SIN_CONTEO y no inventa existencia igual a cero.",
                "Dado que el stock calculado se compara con el stock mínimo, cada producto aparece como DISPONIBLE, STOCK_BAJO o AGOTADO.",
                "Permite filtrar por categoría y buscar por texto sin alterar los datos del inventario."
            ]
        },
        {
            "epic": None,
            "id": "HU-06",
            "nombre": "Realizar el inventario diario",
            "sp": 8,
            "prioridad": "Must",
            "etiquetas": "Inventario · Crítica",
            "dependencias": "HU-03 y HU-01",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como encargado de almacén, quiero iniciar, guardar y cerrar el conteo físico diario para establecer una base confiable para el stock del restaurante.",
            "valor": "Establecer una base confiable para el stock del restaurante.",
            "base_funcional": "API /api/inventarios/actual e InventoryPage.tsx.",
            "criterios": [
                "Permite seleccionar la fecha de hoy o ayer antes de las 9:00 a. m. hora de Lima para un único inventario.",
                "Permite guardar conteos no negativos en estado BORRADOR o INCOMPLETO actualizando el porcentaje de avance.",
                "Al llegar a las 9:00 a. m. del día siguiente, el borrador no cerrado expira y se descarta automáticamente.",
                "Al cerrar el inventario, queda en estado CERRADO con cantidades contadas y usuario responsable."
            ]
        },
        {
            "epic": None,
            "id": "HU-06B",
            "nombre": "Control de jornadas operativas y mix de ventas nocturno",
            "sp": 8,
            "prioridad": "Must",
            "etiquetas": "Inventario · Operativo",
            "dependencias": "HU-05 y ventas de salón",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como administrador de tienda, quiero abrir y cerrar jornadas operativas que resistan la atención de madrugada pasada la medianoche para analizar las ventas por franja horaria sin partirlas en dos días.",
            "valor": "Consistencia contable en atención nocturna de bares y restaurantes.",
            "base_funcional": "API /api/inventario-operativo y OperationalPage.tsx (DayPanel y MixPanel).",
            "criterios": [
                "Dado que la atención del bar se extiende de madrugada, cuando se consulta la jornada, entonces agrupa todos los pedidos y cobros hasta el cierre manual.",
                "Dado que existen mesas con comandas abiertas, cuando se intenta cerrar la jornada, entonces el sistema exige resolverlas antes de proceder.",
                "Dado que la jornada está cerrada, cuando se abre el Mix de ventas, entonces se visualizan los gráficos de consumo y ranking de platos/cervezas por franja horaria."
            ]
        },
        {
            "epic": None,
            "id": "HU-06C",
            "nombre": "Asignación y conteo físico por puesto de trabajo",
            "sp": 8,
            "prioridad": "Must",
            "etiquetas": "Inventario · Operativo",
            "dependencias": "HU-06B",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como gerente de tienda, quiero asignar listas de conteo físico a los puestos de trabajo (Cocina, Barra, Salón) para que el personal cuente solo lo que le corresponde y el sistema calcule el Real vs Teórico.",
            "valor": "Distribución eficiente del trabajo de inventario en el equipo operativo.",
            "base_funcional": "OperationalPage.tsx (CountsPanel y AssignmentsPanel).",
            "criterios": [
                "Dado el panel de asignación, cuando el gerente marca qué insumos cuenta Cocina, Barra o Almacén, entonces se guarda la plantilla por sede.",
                "Dado que un mesero o cocinero abre la pantalla de conteos, entonces visualiza únicamente los insumos asignados a su puesto activo.",
                "Dado que finaliza el conteo, cuando el gerente revisa, entonces el sistema muestra la comparativa Real vs Teórico y permite registrar justificaciones."
            ]
        },
        {
            "epic": None,
            "id": "HU-07",
            "nombre": "Conciliación y justificación de discrepancias de inventario",
            "sp": 8,
            "prioridad": "Must",
            "etiquetas": "Inventario · Control",
            "dependencias": "HU-05 y HU-06",
            "estado": "⏳ PENDIENTE DE DESARROLLO (FALTA HACER)",
            "descripcion": "Como jefe de tienda o auditor, quiero conciliar el inventario físico cerrado contra el stock teórico del sistema y registrar justificaciones por cada descuadre para auditar mermas ocultas y desvíos.",
            "valor": "Control de mermas, detección de pérdidas y auditoría de costos.",
            "base_funcional": "Módulo de Conciliación y Ajustes de Auditoría.",
            "criterios": [
                "Dado un inventario cerrado, cuando se ejecuta la conciliación, entonces el sistema calcula la diferencia física vs teórica, el porcentaje de desvío y el costo monetario.",
                "Dado que un insumo presenta una diferencia superior a la tolerancia permitida (5%), cuando se intenta cerrar la revisión, entonces el sistema exige un motivo justificado obligatorio.",
                "Dado que se aprueba la conciliación, cuando el supervisor confirma, entonces se genera un ajuste formal en stock y se registra en auditoría."
            ]
        },
        {
            "epic": None,
            "id": "HU-15B",
            "nombre": "Kardex y trazabilidad histórica por producto",
            "sp": 8,
            "prioridad": "Should",
            "etiquetas": "Inventario · Trazabilidad",
            "dependencias": "HU-05 y HU-08",
            "estado": "⏳ PENDIENTE DE DESARROLLO (FALTA HACER)",
            "descripcion": "Como auditor o encargado de compras, quiero consultar la ficha cronológica (Kardex) de un insumo para auditar cada entrada, salida, recepción y saldo resultante en un rango de fechas.",
            "valor": "Trazabilidad completa e inalterable de cada gramo o mililitro en almacén.",
            "base_funcional": "Módulo de Kardex Valorizado.",
            "criterios": [
                "Dado que se selecciona un producto y un rango de fechas, cuando se consulta, entonces se listan cronológicamente todas las operaciones que afectaron su existencia.",
                "Dado un registro del listado, cuando se revisa, entonces muestra fecha, documento de referencia, tipo de movimiento, cantidad entrante/saliente y saldo final resultante.",
                "Dado que el usuario hace clic sobre el documento origen (factura o guía), entonces el sistema abre el detalle del registro asociado."
            ]
        },

        # --- ÉPICA 4: ABASTECIMIENTO, COMPRAS Y RECEPCIONES ---
        {
            "epic": "ÉPICA 4: ABASTECIMIENTO, COMPRAS Y RECEPCIONES",
            "id": "HU-09",
            "nombre": "Obtener un pedido de compra sugerido",
            "sp": 5,
            "prioridad": "Should",
            "etiquetas": "Compras · Alta",
            "dependencias": "HU-05 y período de consumo aprobado",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como responsable de compras, quiero consultar cantidades sugeridas según consumo, stock y presentación para preparar la reposición con una base cuantitativa.",
            "valor": "Preparar la reposición con una base cuantitativa.",
            "base_funcional": "API /api/ordenes-compra/pedido-sugerido y PurchaseOrderPage.tsx.",
            "criterios": [
                "Dado que existe consumo calculable, cuando se solicita la sugerencia, entonces el sistema aplica un margen de 20 por ciento y resta el stock disponible.",
                "Dado que la necesidad neta es positiva, cuando se convierte a la presentación de compra, entonces la cantidad se redondea por paquetes usando 0.5 como umbral.",
                "Dado que el stock cubre la necesidad o no existe consumo positivo, cuando se genera la sugerencia, entonces el producto no aparece con una compra mayor que cero.",
                "Dado que un producto, categoría o proveedor está inactivo, cuando se genera el pedido sugerido, entonces dicho producto queda excluido."
            ]
        },
        {
            "epic": None,
            "id": "HU-10",
            "nombre": "Crear y enviar una orden de compra",
            "sp": 5,
            "prioridad": "Must",
            "etiquetas": "Compras · Crítica",
            "dependencias": "HU-03 y opcionalmente HU-09",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como responsable de compras, quiero seleccionar productos y registrar una orden como borrador o enviada para formalizar el abastecimiento y dar seguimiento a lo solicitado.",
            "valor": "Formalizar el abastecimiento y dar seguimiento a lo solicitado.",
            "base_funcional": "API /api/ordenes-compra y PurchaseOrderPage.tsx.",
            "criterios": [
                "Dado que el usuario abre el formulario, cuando carga los datos, entonces visualiza productos activos con categoría, proveedor, unidad, presentación, stock mínimo y stock actual.",
                "Dado que agrega al menos un producto activo, sin duplicados y con cantidad mayor que cero, cuando guarda, entonces se genera un código único de orden.",
                "Dado que selecciona GUARDAR_BORRADOR, cuando confirma, entonces la orden queda en BORRADOR; si selecciona ENVIAR, queda en ENVIADA con fecha de registro.",
                "Dado que la orden se crea, cuando finaliza la transacción, entonces se guardan todos los detalles y la actividad o se revierte todo si ocurre un error."
            ]
        },
        {
            "epic": None,
            "id": "HU-11",
            "nombre": "Registrar recepciones parciales o totales",
            "sp": 8,
            "prioridad": "Must",
            "etiquetas": "Recepciones · Crítica",
            "dependencias": "HU-10",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como receptor de mercadería, quiero registrar los productos recibidos contra una orden enviada para actualizar el abastecimiento y las cantidades pendientes.",
            "valor": "Actualizar el abastecimiento y las cantidades pendientes.",
            "base_funcional": "API /api/recepciones/pendientes y PendingReceiptsPage.tsx.",
            "criterios": [
                "Dado que una orden está ENVIADA o en RECEPCION_PARCIAL, cuando el usuario consulta pendientes, entonces visualiza productos, proveedores y cantidades solicitadas, recibidas y pendientes.",
                "Dado que ingresa proveedor, factura, fecha y al menos un producto, cuando registra cantidades positivas que no superan lo pendiente, entonces se crea la recepción.",
                "Dado que la misma factura ya existe para el proveedor, cuando se intenta guardar, entonces el sistema rechaza el duplicado y no modifica la orden.",
                "Dado que se registra una recepción, cuando se recalcula el avance total, entonces la orden queda ENVIADA, RECEPCION_PARCIAL o RECEPCIONADA según las cantidades acumuladas."
            ]
        },
        {
            "epic": None,
            "id": "HU-12",
            "nombre": "Anulación y cierre anticipado de órdenes de compra",
            "sp": 5,
            "prioridad": "Should",
            "etiquetas": "Compras · Control",
            "dependencias": "HU-10 y HU-11",
            "estado": "⏳ PENDIENTE DE DESARROLLO (FALTA HACER)",
            "descripcion": "Como responsable de compras, quiero anular órdenes erróneas o marcar como cerradas incompletas aquellas donde el proveedor no entregará el saldo restante para liberar compromisos y limpiar la bandeja de pendientes.",
            "valor": "Depuración de compromisos de compra y limpieza operativa de recepciones.",
            "base_funcional": "Bandeja de Historial de Órdenes de Compra.",
            "criterios": [
                "Dado que una orden está ENVIADA y no tiene recepciones, cuando el usuario confirma la anulación con motivo, entonces pasa a estado CANCELADA.",
                "Dado que una orden está en RECEPCION_PARCIAL y el proveedor confirma que no enviará el saldo, cuando se confirma el cierre, entonces pasa a CERRADA_INCOMPLETA.",
                "Dado que una orden pasa a CERRADA_INCOMPLETA, cuando se actualiza la bandeja de pendientes de recepción, entonces los ítems no recibidos se retiran automáticamente."
            ]
        },
        {
            "epic": None,
            "id": "HU-13",
            "nombre": "Consultar y corregir recepciones",
            "sp": 8,
            "prioridad": "Should",
            "etiquetas": "Recepciones · Alta",
            "dependencias": "HU-11 y permiso editar",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como responsable autorizado, quiero consultar facturas recibidas y corregir errores con trazabilidad para mantener consistentes la recepción, la orden y el stock.",
            "valor": "Mantener consistentes la recepción, la orden y el stock.",
            "base_funcional": "Historial y corrección de recepciones (ReceptionHistoryPage.tsx).",
            "criterios": [
                "Dado que se define un rango válido y opcionalmente un proveedor, cuando se consulta el historial, entonces se listan las recepciones coincidentes con su orden y estado.",
                "Dado que se abre una recepción, cuando se consulta su detalle, entonces se muestran factura, fecha, proveedor, productos y cantidades recibidas.",
                "Dado que se corrige una recepción permitida, cuando se indica motivo, observación y valores válidos, entonces se guarda la diferencia y se conserva la información anterior en el historial.",
                "Dado que una corrección cambia cantidades, cuando se confirma, entonces el sistema recalcula el estado de la orden y registra al responsable de la modificación."
            ]
        },
        {
            "epic": None,
            "id": "HU-17P",
            "nombre": "Exportación formal de orden de compra en PDF",
            "sp": 5,
            "prioridad": "Could",
            "etiquetas": "Compras · Reportes",
            "dependencias": "HU-10",
            "estado": "⏳ PENDIENTE DE DESARROLLO (FALTA HACER)",
            "descripcion": "Como responsable de compras, quiero descargar la orden de compra en formato PDF con membrete oficial y detalle de insumos para enviarla formalmente al proveedor por correo o WhatsApp.",
            "valor": "Formalización comercial del abastecimiento con proveedores.",
            "base_funcional": "Generador de documentos en PurchaseOrderHistoryPage.tsx.",
            "criterios": [
                "Dado que una orden está en estado ENVIADA, cuando se hace clic en 'Descargar PDF', entonces el sistema genera el documento formateado.",
                "Dado el PDF generado, cuando se visualiza, entonces incluye el logotipo de Barbarian, código de orden, datos del proveedor, tabla de insumos y espacio para firma.",
                "Dado que se descarga el archivo, cuando se guarda, entonces adopta un nombre estándar como OC-2026-0042.pdf."
            ]
        },

        # --- ÉPICA 5: MOVIMIENTOS Y LOGÍSTICA ---
        {
            "epic": "ÉPICA 5: MOVIMIENTOS EXTRAORDINARIOS Y LOGÍSTICA",
            "id": "HU-08",
            "nombre": "Registrar movimientos extraordinarios de inventario",
            "sp": 5,
            "prioridad": "Must",
            "etiquetas": "Movimientos · Crítica",
            "dependencias": "HU-03 y HU-05",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como encargado de almacén, quiero registrar entradas y salidas que no provienen de una recepción de compra para mantener el stock alineado con préstamos, mermas, devoluciones y reposiciones.",
            "valor": "Mantener el stock alineado con préstamos, mermas, devoluciones y reposiciones.",
            "base_funcional": "API /api/movimientos y RegisterMovementPage.tsx.",
            "criterios": [
                "Dado que se selecciona un motivo válido, cuando se registra el movimiento, entonces el sistema determina automáticamente si es ENTRADA o SALIDA.",
                "Dado que el motivo es préstamo recibido o entregado, cuando se guarda, entonces exige un local relacionado y rechaza un proveedor.",
                "Dado que el motivo es devolución o reposición de proveedor, cuando se guarda, entonces exige un proveedor activo; para merma no acepta local ni proveedor.",
                "Dado que se envían productos activos, únicos y con cantidades mayores que cero, cuando se confirma, entonces se genera un código, se guardan cabecera y detalle y se registra la actividad."
            ]
        },
        {
            "epic": None,
            "id": "HU-08B",
            "nombre": "Seguimiento de transferencias y préstamos entre sedes",
            "sp": 5,
            "prioridad": "Should",
            "etiquetas": "Movimientos · Logística",
            "dependencias": "HU-08",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como encargado de almacén, quiero hacer seguimiento a los préstamos de insumos enviados a otro local para confirmar su recepción en destino y controlar las devoluciones pendientes.",
            "valor": "Control de insumos en tránsito y consistencia de existencias entre sucursales.",
            "base_funcional": "API /api/movimientos y MovementTrackingPage.tsx.",
            "criterios": [
                "Dado que se registra un préstamo entregado, cuando se despacha, entonces el stock de origen se descuenta de inmediato y queda en estado PENDIENTE.",
                "Dado que el local de destino abre la pantalla de seguimiento, cuando pulsa 'Aceptar', entonces se registra la entrada en su inventario.",
                "Dado que se realiza la devolución de un préstamo, cuando se confirma, entonces permite registrar reintegros parciales o totales asociados a la transferencia original."
            ]
        },

        # --- ÉPICA 6: SALÓN Y VENTAS ---
        {
            "epic": "ÉPICA 6: SALÓN, COMANDAS Y VENTAS (PUNTO DE VENTA)",
            "id": "HU-18",
            "nombre": "Configuración visual del plano de mesas del salón",
            "sp": 5,
            "prioridad": "Should",
            "etiquetas": "Salón · Configuración",
            "dependencias": "HU-01 y perfil Gerente",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como gerente de tienda, quiero configurar la distribución de mesas y barra en un editor visual interactivo para que el mapa en pantalla refleje la distribución física real del restaurante.",
            "valor": "Flexibilidad operativa para adaptar el software a los cambios físicos del salón.",
            "base_funcional": "API /api/salon/layout y SalonLayoutPage.tsx.",
            "criterios": [
                "Dado un usuario con perfil Gerente, cuando ingresa a opciones de salón, entonces puede mover mesas y barra con arrastrar y soltar (drag & drop).",
                "Dado que se ajustan las posiciones y dimensiones, cuando se guarda, entonces se persiste la configuración en formato JSON por sede.",
                "Dado que una mesa mantiene comensales o pedidos activos, cuando se intenta eliminar del plano, entonces el sistema bloquea la acción."
            ]
        },
        {
            "epic": None,
            "id": "HU-16",
            "nombre": "Registro de comandas y pedidos por mesa",
            "sp": 8,
            "prioridad": "Must",
            "etiquetas": "Salón · Ventas",
            "dependencias": "HU-04 y HU-18",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como mesero, quiero seleccionar una mesa en el plano y registrar los platos, bebidas y salsas solicitadas para enviar la comanda a cocina y barra.",
            "valor": "Atención rápida y reducción de errores en la toma de pedidos.",
            "base_funcional": "API /api/salon/orders y SalonOrderPage.tsx.",
            "criterios": [
                "Dado que el mozo toca una mesa libre, cuando ingresa al pedido, entonces visualiza la carta con categorías y productos activos.",
                "Dado que se agrega un plato con salsas opcionales, cuando se selecciona, entonces el sistema valida las cantidades permitidas y comentarios de preparación.",
                "Dado que la mesa ya tiene comanda enviada, cuando los clientes piden otra ronda, entonces permite realizar envíos adicionales acumulativos sin sobrescribir lo previo."
            ]
        },
        {
            "epic": None,
            "id": "HU-17",
            "nombre": "Cobro de comanda y descarga automática de inventario por receta",
            "sp": 8,
            "prioridad": "Must",
            "etiquetas": "Salón · Cobros",
            "dependencias": "HU-16 y HU-05",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como cajero o administrador de salón, quiero cobrar una mesa (efectivo/tarjeta), emitir el comprobante y que el sistema descuente de almacén los insumos utilizados según sus recetas.",
            "valor": "Cierre de cuenta formal y descuento automático del stock en tiempo real.",
            "base_funcional": "API /api/salon/payments y SalonPaymentPage.tsx.",
            "criterios": [
                "Dado que se solicita pagar una mesa, cuando se ingresa el método de pago (efectivo o tarjeta), entonces se registra el cobro y se emite el comprobante visual en SVG.",
                "Dado que el cliente solicita Boleta o Factura, cuando se ingresa DNI o RUC, entonces se valida el formato y se asocia al comprobante emitido.",
                "Dado que se confirma el cobro, cuando finaliza la transacción, entonces el sistema ejecuta la explosión de recetas y descuenta de inmediato los insumos de inventario (VENTA_SALON)."
            ]
        },

        # --- ÉPICA 7: AUDITORÍA DEL SISTEMA ---
        {
            "epic": "ÉPICA 7: AUDITORÍA Y TRAZABILIDAD DE OPERACIONES",
            "id": "HU-14",
            "nombre": "Consultar la actividad de usuarios",
            "sp": 3,
            "prioridad": "Should",
            "etiquetas": "Auditoría · Alta",
            "dependencias": "HU-01 y permiso consultar auditoría",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA (HECHA)",
            "descripcion": "Como supervisor o auditor, quiero revisar las acciones relevantes ejecutadas en el sistema para investigar cambios y verificar responsabilidades.",
            "valor": "Investigar cambios y verificar responsabilidades.",
            "base_funcional": "API /api/actividades y ActivityPage.tsx.",
            "criterios": [
                "Dado que el usuario tiene permiso de auditoría, cuando solicita actividades, entonces recibe los eventos más recientes con usuario, módulo, acción, registro afectado, descripción y fecha.",
                "Dado que se indica un límite válido, cuando se consulta, entonces la respuesta respeta el máximo configurado por el servicio.",
                "Dado que ocurre una operación registrada como inicio de sesión, creación, edición, cierre, revisión o corrección, cuando la transacción finaliza, entonces se crea la actividad asociada al responsable.",
                "Dado que el perfil no tiene permiso, cuando intenta consultar actividades, entonces la API responde 403 y no expone eventos."
            ]
        }
    ]

    for hu in historias:
        card_elements = []
        if hu["epic"]:
            card_elements.append(Paragraph(f"<b>{hu['epic']}</b>", style_epic_hdr))
            card_elements.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor("#CBD5E1"), spaceBefore=0, spaceAfter=8))

        # Título
        title_p = Paragraph(f"<b>{hu['id']} {hu['nombre']}</b> &nbsp;&nbsp; <font color='{'#166534' if 'HECHA' in hu['estado'] else '#C2410C'}'><b>[{hu['estado']}]</b></font>", style_hu_title)
        card_elements.append(title_p)

        # Tabla
        tbl_data = [
            [Paragraph("<b>Título</b>", style_tbl_lbl), Paragraph(f"{hu['id']} | {hu['nombre']} | {hu['sp']} SP | {hu['prioridad'].upper()}", style_tbl_val)],
            [Paragraph("<b>Story Points</b>", style_tbl_lbl), Paragraph(str(hu['sp']), style_tbl_val)],
            [Paragraph("<b>Prioridad</b>", style_tbl_lbl), Paragraph(hu['prioridad'], style_tbl_val)],
            [Paragraph("<b>Etiquetas</b>", style_tbl_lbl), Paragraph(hu['etiquetas'], style_tbl_val)],
            [Paragraph("<b>Dependencias</b>", style_tbl_lbl), Paragraph(hu['dependencias'], style_tbl_val)]
        ]
        t_card = Table(tbl_data, colWidths=[120, 412])
        t_card.setStyle(TableStyle([
            ('BACKGROUND', (0,0), (0,-1), colors.HexColor("#F1F5F9")),
            ('BACKGROUND', (1,0), (1,-1), colors.HexColor("#FFFFFF")),
            ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
            ('TOPPADDING', (0,0), (-1,-1), 4),
            ('BOTTOMPADDING', (0,0), (-1,-1), 4),
            ('LEFTPADDING', (0,0), (-1,-1), 6),
            ('RIGHTPADDING', (0,0), (-1,-1), 6),
        ]))
        card_elements.append(t_card)
        card_elements.append(Spacer(1, 6))

        # Descripción
        card_elements.append(Paragraph("<b>Descripción</b>", style_tbl_lbl))
        card_elements.append(Paragraph(hu['descripcion'], style_p))
        card_elements.append(Paragraph(f"<b>Valor:</b> {hu['valor']}", style_p))
        card_elements.append(Paragraph(f"<b>Base funcional:</b> {hu['base_funcional']}", style_p))
        card_elements.append(Spacer(1, 4))

        # Checklist
        card_elements.append(Paragraph("<b>Checklist Criterios de aceptación</b>", style_tbl_lbl))
        for crit in hu['criterios']:
            card_elements.append(Paragraph(f"☐ {crit}", style_crit))
        
        card_elements.append(Spacer(1, 10))

        story.append(KeepTogether(card_elements))

    doc.build(story, canvasmaker=NumberedCanvas)
    print(f"PDF generado con exito: {filename}")

if __name__ == "__main__":
    build_pdf()
