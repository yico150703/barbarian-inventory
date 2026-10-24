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

def add_hu_card(doc, hu):
    title_p = doc.add_paragraph()
    title_p.paragraph_format.space_before = Pt(14)
    title_p.paragraph_format.space_after = Pt(4)
    title_p.paragraph_format.keep_with_next = True
    
    r_hu = title_p.add_run(f"{hu['id']} {hu['nombre']}")
    r_hu.font.name = "Arial"
    r_hu.font.size = Pt(13)
    r_hu.font.bold = True
    r_hu.font.color.rgb = RGBColor(15, 23, 42)

    r_estado = title_p.add_run(f"   [{hu['estado']}]")
    r_estado.font.name = "Arial"
    r_estado.font.size = Pt(10)
    r_estado.font.bold = True
    if "IMPLEMENTADA" in hu['estado']:
        r_estado.font.color.rgb = RGBColor(22, 101, 52)  # Verde
    else:
        r_estado.font.color.rgb = RGBColor(194, 65, 12)  # Naranja

    table = doc.add_table(rows=5, cols=2)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False

    meta_rows = [
        ("Título", f"{hu['id']} | {hu['nombre']} | {hu['sp']} SP | {hu['prioridad'].upper()}"),
        ("Story Points", str(hu['sp'])),
        ("Prioridad", hu['prioridad']),
        ("Etiquetas", hu['etiquetas']),
        ("Dependencias", hu['dependencias'])
    ]

    for idx, (lbl, val) in enumerate(meta_rows):
        row = table.rows[idx]
        cell_lbl, cell_val = row.cells[0], row.cells[1]
        
        cell_lbl.width = Inches(1.8)
        cell_val.width = Inches(4.7)

        p_lbl = cell_lbl.paragraphs[0]
        p_lbl.paragraph_format.space_after = Pt(0)
        r_lbl = p_lbl.add_run(lbl)
        r_lbl.font.name = "Arial"
        r_lbl.font.size = Pt(9.5)
        r_lbl.font.bold = True
        r_lbl.font.color.rgb = RGBColor(30, 41, 59)

        p_val = cell_val.paragraphs[0]
        p_val.paragraph_format.space_after = Pt(0)
        r_val = p_val.add_run(val)
        r_val.font.name = "Arial"
        r_val.font.size = Pt(9.5)
        r_val.font.color.rgb = RGBColor(15, 23, 42)

        set_cell_background(cell_lbl, "F1F5F9")
        set_cell_background(cell_val, "FFFFFF")
        set_cell_margins(cell_lbl, 60, 60, 100, 100)
        set_cell_margins(cell_val, 60, 60, 100, 100)

    p_desc_hdr = doc.add_paragraph()
    p_desc_hdr.paragraph_format.space_before = Pt(8)
    p_desc_hdr.paragraph_format.space_after = Pt(2)
    r_dh = p_desc_hdr.add_run("Descripción")
    r_dh.font.name = "Arial"
    r_dh.font.size = Pt(10.5)
    r_dh.font.bold = True

    p_desc = doc.add_paragraph()
    p_desc.paragraph_format.space_after = Pt(2)
    p_desc.add_run(hu['descripcion']).font.size = Pt(9.5)

    p_valor = doc.add_paragraph()
    p_valor.paragraph_format.space_after = Pt(2)
    r_vh = p_valor.add_run("Valor: ")
    r_vh.bold = True
    p_valor.add_run(hu['valor']).font.size = Pt(9.5)

    p_base = doc.add_paragraph()
    p_base.paragraph_format.space_after = Pt(6)
    r_bh = p_base.add_run("Base funcional: ")
    r_bh.bold = True
    p_base.add_run(hu['base_funcional']).font.size = Pt(9.5)

    p_crit_hdr = doc.add_paragraph()
    p_crit_hdr.paragraph_format.space_before = Pt(4)
    p_crit_hdr.paragraph_format.space_after = Pt(3)
    r_ch = p_crit_hdr.add_run("Checklist Criterios de aceptación")
    r_ch.font.name = "Arial"
    r_ch.font.size = Pt(10.5)
    r_ch.font.bold = True

    for crit in hu['criterios']:
        p_c = doc.add_paragraph()
        p_c.paragraph_format.space_after = Pt(2)
        p_c.paragraph_format.left_indent = Inches(0.15)
        r_box = p_c.add_run("☐ ")
        r_box.bold = True
        p_c.add_run(crit).font.size = Pt(9.5)

    doc.add_paragraph().paragraph_format.space_after = Pt(8)

def main():
    doc = Document()
    
    for section in doc.sections:
        section.top_margin = Inches(0.9)
        section.bottom_margin = Inches(0.9)
        section.left_margin = Inches(0.9)
        section.right_margin = Inches(0.9)

    p_main = doc.add_paragraph()
    p_main.paragraph_format.space_before = Pt(10)
    p_main.paragraph_format.space_after = Pt(2)
    r_main = p_main.add_run("PRODUCT BACKLOG: TARJETAS DE HISTORIAS DE USUARIO")
    r_main.font.name = "Arial"
    r_main.font.size = Pt(18)
    r_main.font.bold = True
    r_main.font.color.rgb = RGBColor(26, 54, 93)

    p_sub = doc.add_paragraph()
    p_sub.paragraph_format.space_after = Pt(10)
    r_sub = p_sub.add_run("Barbarian Inventory — Clasificación de Historias Hechas vs Faltantes")
    r_sub.font.name = "Arial"
    r_sub.font.size = Pt(11)
    r_sub.font.color.rgb = RGBColor(194, 65, 12)

    p_intro = doc.add_paragraph(
        "A continuación se presenta el catálogo completo de Historias de Usuario estructuradas en orden lógico de negocio: "
        "Seguridad y Accesos, Catálogos y Recetas, Stock e Inventarios, Compras y Recepciones, Movimientos y Logística, "
        "Salón y Ventas, y Auditoría. "
        "Cada tarjeta incluye la indicación explícita de si ya se encuentra IMPLEMENTADA EN EL SISTEMA (Hecha) "
        "o si corresponde a una historia PENDIENTE DE DESARROLLO (Falta hacer)."
    )
    p_intro.paragraph_format.space_after = Pt(10)

    # TABLA RESUMEN
    t_res = doc.add_table(rows=3, cols=3)
    t_res.alignment = WD_TABLE_ALIGNMENT.CENTER
    r0 = t_res.rows[0].cells
    r0[0].paragraphs[0].add_run("Estado").bold = True
    r0[1].paragraphs[0].add_run("Cantidad de Historias").bold = True
    r0[2].paragraphs[0].add_run("Story Points").bold = True
    set_cell_background(r0[0], "1E3A8A"); set_cell_background(r0[1], "1E3A8A"); set_cell_background(r0[2], "1E3A8A")
    for cell in r0:
        cell.paragraphs[0].runs[0].font.color.rgb = RGBColor(255, 255, 255)
        set_cell_margins(cell, 60, 60, 80, 80)

    row1 = t_res.rows[1].cells
    row1[0].paragraphs[0].add_run("✅ IMPLEMENTADAS EN EL SISTEMA (HECHAS)")
    row1[1].paragraphs[0].add_run("19 Historias de Usuario")
    row1[2].paragraphs[0].add_run("112 SP")
    set_cell_background(row1[0], "F0FDF4"); set_cell_background(row1[1], "F0FDF4"); set_cell_background(row1[2], "F0FDF4")
    for cell in row1: set_cell_margins(cell, 50, 50, 80, 80)

    row2 = t_res.rows[2].cells
    row2[0].paragraphs[0].add_run("⏳ PENDIENTES DE DESARROLLO (FALTA HACER)")
    row2[1].paragraphs[0].add_run("4 Historias de Usuario")
    row2[2].paragraphs[0].add_run("26 SP")
    set_cell_background(row2[0], "FFF7ED"); set_cell_background(row2[1], "FFF7ED"); set_cell_background(row2[2], "FFF7ED")
    for cell in row2: set_cell_margins(cell, 50, 50, 80, 80)

    doc.add_paragraph().paragraph_format.space_after = Pt(12)

    historias = [
        # --- MÓDULO 1: SEGURIDAD Y ACCESOS ---
        {
            "id": "HU-01",
            "nombre": "Iniciar sesión y cargar el menú autorizado",
            "sp": 5,
            "prioridad": "Must",
            "etiquetas": "Seguridad · Crítica",
            "dependencias": "Usuarios activos, perfiles, permisos y opciones de menú configurados",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
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
            "id": "HU-02",
            "nombre": "Gestionar usuarios operativos",
            "sp": 8,
            "prioridad": "Should",
            "etiquetas": "Seguridad · Alta",
            "dependencias": "HU-01 y matriz de perfiles gestionables",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
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
            "id": "HU-02B",
            "nombre": "Acceso rápido al salón mediante PIN operativo",
            "sp": 5,
            "prioridad": "Must",
            "etiquetas": "Salón · Seguridad",
            "dependencias": "HU-01 y asignación de perfil Mesero/Bartender",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
            "descripcion": "Como mesero o bartender, quiero iniciar sesión en el salón mediante un PIN numérico de 4 dígitos para acceder rápidamente a la atención de mesas sin escribir contraseñas largas en la pantalla del bar.",
            "valor": "Agilidad y rapidez en la toma de pedidos durante la atención al cliente.",
            "base_funcional": "API /api/salon/login, SalonAccess.tsx y SalonPinDialog.tsx.",
            "criterios": [
                "Dado un usuario con puesto Mesero o Bartender y PIN asignado, cuando ingresa su sede y PIN correcto, entonces el sistema genera una sesión de salón temporal de 2 horas.",
                "Dado que se ingresa un PIN erróneo más de 3 veces consecutivas, entonces la API bloquea temporalmente los intentos por seguridad.",
                "Dado que el administrador edita un usuario, cuando ingresa un nuevo PIN de 4 dígitos, entonces se actualiza y encripta en base de datos sin guardarse en texto plano."
            ]
        },

        # --- MÓDULO 2: CATÁLOGOS, PRODUCTOS Y RECETAS ---
        {
            "id": "HU-03",
            "nombre": "Mantener categorías proveedores y productos",
            "sp": 8,
            "prioridad": "Must",
            "etiquetas": "Catálogos · Crítica",
            "dependencias": "HU-01 y permisos de catálogo",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
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
            "id": "HU-04",
            "nombre": "Consultar catálogos de carta y producción",
            "sp": 3,
            "prioridad": "Could",
            "etiquetas": "Carta y producción · Media",
            "dependencias": "HU-01 y datos maestros cargados",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
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
            "id": "HU-04B",
            "nombre": "Formulación de subproductos de producción",
            "sp": 5,
            "prioridad": "Should",
            "etiquetas": "Producción · Media",
            "dependencias": "HU-03 y HU-04",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
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
            "id": "HU-04C",
            "nombre": "Configuración de límites de stock por tienda",
            "sp": 5,
            "prioridad": "Must",
            "etiquetas": "Catálogos · Alta",
            "dependencias": "HU-03 y perfil Gerente",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
            "descripcion": "Como gerente de tienda, quiero configurar el stock mínimo y máximo de cada producto exclusivamente para mi local para adaptar el abastecimiento al volumen de ventas de mi sede.",
            "valor": "Gestión descentralizada y precisa de niveles de inventario por sede.",
            "base_funcional": "API /api/catalogos/limites-stock y StockLimitsPage.tsx.",
            "criterios": [
                "Dado un usuario con perfil Gerente (ID 2), cuando accede a límites de stock, entonces puede editar el mínimo y máximo de su sede activa.",
                "Dado que se ingresan valores de stock, cuando se confirma, entonces el sistema valida que el stock máximo sea mayor o igual al mínimo.",
                "Dado que se guardan los límites, cuando finaliza la transacción, entonces se actualiza la tabla producto_stock_local sin alterar los límites de otras tiendas."
            ]
        },

        # --- MÓDULO 3: STOCK E INVENTARIOS ---
        {
            "id": "HU-05",
            "nombre": "Consultar el stock actual",
            "sp": 5,
            "prioridad": "Must",
            "etiquetas": "Inventario · Crítica",
            "dependencias": "HU-03 y al menos un inventario cerrado para stock calculable",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
            "descripcion": "Como encargado de almacén, quiero consultar existencias y su estado por producto para detectar faltantes y tomar decisiones de reposición.",
            "valor": "Detectar faltantes y tomar decisiones de reposición.",
            "base_funcional": "API /api/inventarios/stock y StockPage.tsx.",
            "criterios": [
                "Dado que existe un último conteo cerrado, cuando se consulta el stock, entonces el sistema calcula stock actual como conteo más recepciones y entradas posteriores menos salidas posteriores.",
                "Dado que un producto no tiene conteo cerrado, cuando se consulta el stock, entonces se muestra como SIN_CONTEO y no se inventa una existencia igual a cero.",
                "Dado que el stock calculado se compara con el stock mínimo, cuando se carga la lista, entonces cada producto aparece como DISPONIBLE, STOCK_BAJO o AGOTADO según corresponda.",
                "Dado que hay varios productos, cuando el usuario busca o filtra por categoría en la pantalla, entonces la lista y el resumen reflejan el subconjunto visible sin alterar los datos."
            ]
        },
        {
            "id": "HU-06",
            "nombre": "Realizar el inventario diario",
            "sp": 8,
            "prioridad": "Must",
            "etiquetas": "Inventario · Crítica",
            "dependencias": "HU-03 y HU-01",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
            "descripcion": "Como encargado de almacén, quiero iniciar, guardar y cerrar el conteo físico diario para establecer una base confiable para el stock del restaurante.",
            "valor": "Establecer una base confiable para el stock del restaurante.",
            "base_funcional": "API /api/inventarios/actual e InventoryPage.tsx.",
            "criterios": [
                "Dado que no existe otro inventario abierto, cuando el usuario elige hoy o ayer antes de las 9:00 a. m. hora de Lima, entonces el sistema inicia un único inventario para esa fecha.",
                "Dado que el inventario está abierto, cuando se guardan conteos no negativos de productos activos y sin duplicados, entonces el progreso queda en BORRADOR o INCOMPLETO y se actualiza el porcentaje de avance.",
                "Dado que el borrador alcanza las 9:00 a. m. del día siguiente, cuando el usuario intenta recuperarlo o guardarlo, entonces el sistema elimina el progreso vencido e informa la expiración.",
                "Dado que el inventario permanece abierto, cuando el usuario lo cierra, entonces se registra el estado CERRADO, la cantidad contada, los pendientes y la actividad del responsable."
            ]
        },
        {
            "id": "HU-06B",
            "nombre": "Control de jornadas operativas y mix de ventas nocturno",
            "sp": 8,
            "prioridad": "Must",
            "etiquetas": "Inventario · Operativo",
            "dependencias": "HU-05 y ventas de salón",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
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
            "id": "HU-06C",
            "nombre": "Asignación y conteo físico por puesto de trabajo",
            "sp": 8,
            "prioridad": "Must",
            "etiquetas": "Inventario · Operativo",
            "dependencias": "HU-06B",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
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

        # --- MÓDULO 4: COMPRAS Y RECEPCIONES ---
        {
            "id": "HU-09",
            "nombre": "Obtener un pedido de compra sugerido",
            "sp": 5,
            "prioridad": "Should",
            "etiquetas": "Compras · Alta",
            "dependencias": "HU-05 y definición aprobada del período de consumo",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
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
            "id": "HU-10",
            "nombre": "Crear y enviar una orden de compra",
            "sp": 5,
            "prioridad": "Must",
            "etiquetas": "Compras · Crítica",
            "dependencias": "HU-03 y opcionalmente HU-09",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
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
            "id": "HU-11",
            "nombre": "Registrar recepciones parciales o totales",
            "sp": 8,
            "prioridad": "Must",
            "etiquetas": "Recepciones · Crítica",
            "dependencias": "HU-10",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
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
            "id": "HU-13",
            "nombre": "Consultar y corregir recepciones",
            "sp": 8,
            "prioridad": "Should",
            "etiquetas": "Recepciones · Alta",
            "dependencias": "HU-11 y permiso editar",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
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

        # --- MÓDULO 5: MOVIMIENTOS Y LOGÍSTICA ---
        {
            "id": "HU-08",
            "nombre": "Registrar movimientos extraordinarios de inventario",
            "sp": 5,
            "prioridad": "Must",
            "etiquetas": "Movimientos · Crítica",
            "dependencias": "HU-03 y HU-05",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
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
            "id": "HU-08B",
            "nombre": "Seguimiento de transferencias y préstamos entre sedes",
            "sp": 5,
            "prioridad": "Should",
            "etiquetas": "Movimientos · Logística",
            "dependencias": "HU-08",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
            "descripcion": "Como encargado de almacén, quiero hacer seguimiento a los préstamos de insumos enviados a otro local para confirmar su recepción en destino y controlar las devoluciones pendientes.",
            "valor": "Control de insumos en tránsito y consistencia de existencias entre sucursales.",
            "base_funcional": "API /api/movimientos y MovementTrackingPage.tsx.",
            "criterios": [
                "Dado que se registra un préstamo entregado, cuando se despacha, entonces el stock de origen se descuenta de inmediato y queda en estado PENDIENTE.",
                "Dado que el local de destino abre la pantalla de seguimiento, cuando pulsa 'Aceptar', entonces se registra la entrada en su inventario.",
                "Dado que se realiza la devolución de un préstamo, cuando se confirma, entonces permite registrar reintegros parciales o totales asociados a la transferencia original."
            ]
        },

        # --- MÓDULO 6: SALÓN, MESAS Y VENTAS ---
        {
            "id": "HU-18",
            "nombre": "Configuración visual del plano de mesas del salón",
            "sp": 5,
            "prioridad": "Should",
            "etiquetas": "Salón · Configuración",
            "dependencias": "HU-01 y perfil Gerente",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
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
            "id": "HU-16",
            "nombre": "Registro de comandas y pedidos por mesa",
            "sp": 8,
            "prioridad": "Must",
            "etiquetas": "Salón · Ventas",
            "dependencias": "HU-04 y HU-18",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
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
            "id": "HU-17",
            "nombre": "Cobro de comanda y descarga automática de inventario por receta",
            "sp": 8,
            "prioridad": "Must",
            "etiquetas": "Salón · Cobros",
            "dependencias": "HU-16 y HU-05",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
            "descripcion": "Como cajero o administrador de salón, quiero cobrar una mesa (efectivo/tarjeta), emitir el comprobante y que el sistema descuente de almacén los insumos utilizados según sus recetas.",
            "valor": "Cierre de cuenta formal y descuento automático del stock en tiempo real.",
            "base_funcional": "API /api/salon/payments y SalonPaymentPage.tsx.",
            "criterios": [
                "Dado que se solicita pagar una mesa, cuando se ingresa el método de pago (efectivo o tarjeta), entonces se registra el cobro y se emite el comprobante visual en SVG.",
                "Dado que el cliente solicita Boleta o Factura, cuando se ingresa DNI o RUC, entonces se valida el formato y se asocia al comprobante emitido.",
                "Dado que se confirma el cobro, cuando finaliza la transacción, entonces el sistema ejecuta la explosión de recetas y descuenta de inmediato los insumos de inventario (VENTA_SALON)."
            ]
        },

        # --- MÓDULO 7: AUDITORÍA DEL SISTEMA ---
        {
            "id": "HU-14",
            "nombre": "Consultar la actividad de usuarios",
            "sp": 3,
            "prioridad": "Should",
            "etiquetas": "Auditoría · Alta",
            "dependencias": "HU-01 y permiso consultar auditoría",
            "estado": "✅ IMPLEMENTADA EN EL SISTEMA",
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
        add_hu_card(doc, hu)

    output_path = os.path.abspath("HISTORIAS_DE_USUARIO_BARBARIAN.docx")
    doc.save(output_path)
    print(f"Documento generado exitosamente en: {output_path}")

if __name__ == "__main__":
    main()
