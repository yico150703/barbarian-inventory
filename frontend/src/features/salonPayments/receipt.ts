export interface ReceiptLine {
  nombre: string; cantidad: number; precio: number; enviada: boolean
  comentario: string; opciones: {nombre: string}[]; barra_nombre?: string | null; cantidad_reposiciones?: number
  id_barra_libre?: number | null; ids_lineas?: number[]
  selecciones_promocion?: {nombre: string; opciones: {nombre: string}[]}[]
}
export interface Receipt {
  id: number; numero: string; fecha: string; tipo: string; metodo: string
  documento: string; cliente: string; local: string; mesa: string
  usuario: string; total: number; fiscal: boolean; lineas: ReceiptLine[]
}
export const money = (value: number) => new Intl.NumberFormat('es-PE', {style:'currency', currency:'PEN'}).format(value)
export const documentNames: Record<string,string> = {BOLETA:'Boleta', BOLETA_ELECTRONICA:'Boleta electrónica', FACTURA:'Factura'}

export function resumenReposiciones(barra: ReceiptLine, lineas: ReceiptLine[]) {
  const identidad=barra.ids_lineas?.[0]
  if(!identidad)return ''
  const cantidades=new Map<string,number>()
  for(const linea of lineas.filter(linea => linea.id_barra_libre===identidad)) {
    const salsa=linea.opciones[0]?.nombre.replace(/^Salsa\s+/i,'') ?? 'Sin salsa'
    cantidades.set(salsa,(cantidades.get(salsa) ?? 0)+linea.cantidad)
  }
  return [...cantidades].map(([salsa,cantidad]) => `${cantidad} ${salsa}`).join(' · ')
}

// Imagen SVG generada exclusivamente con el comprobante persistido del servidor.
export function receiptImage(receipt: Receipt) {
  const escape = (value: string) => value.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]!))
  let y = 42
  const rows: string[] = []
  const line = (value: string, size = 15, bold = false) => {
    for (const part of value.match(/.{1,45}(?:\s|$)|.{1,45}/gu) ?? ['']) {
      rows.push(`<text x="28" y="${y}" font-size="${size}" font-weight="${bold ? 700 : 400}">${escape(part.trim())}</text>`)
      y += size + 10
    }
  }
  const rule = () => { y += 8; rows.push(`<path d="M28 ${y}H452" stroke="#d0ddd5" stroke-dasharray="4 4"/>`); y += 28 }
  line('BARBARIAN', 26, true)
  line(receipt.local)
  line('Comprobante interno · Sin validez tributaria', 13)
  rule()
  line(`${documentNames[receipt.tipo]} · ${receipt.numero}`, 17, true)
  line(new Date(receipt.fecha).toLocaleString('es-PE', {timeZone:'America/Lima'}))
  line(`Mesa ${receipt.mesa} · Cobrado por ${receipt.usuario}`)
  if (receipt.documento) {
    line(`${receipt.tipo === 'FACTURA' ? 'RUC' : 'DNI'}: ${receipt.documento}`)
    line(receipt.cliente)
  }
  rule()
  for (const item of receipt.lineas.filter(item => !item.id_barra_libre)) {
    line(`${item.cantidad} × ${item.nombre}`, 15, true)
    line(`${money(item.precio)} c/u                ${money(item.cantidad * item.precio)}`)
    if (item.opciones.length) line(`Opciones: ${item.opciones.map(o=>o.nombre).join(', ')}`, 13)
    for (const selection of item.selecciones_promocion ?? []) {
      line(`Incluye: ${selection.nombre}`, 13)
      if (selection.opciones.length) line(`Salsa: ${selection.opciones.map(o=>o.nombre).join(', ')}`, 13)
    }
    const reposiciones=resumenReposiciones(item,receipt.lineas)
    if (reposiciones) line(`Reposiciones: ${reposiciones}`, 13)
    if (item.barra_nombre) line(`Reposición para: ${item.barra_nombre}`, 13)
    if (item.comentario) line(`Comentario: ${item.comentario}`, 13)
    y += 8
  }
  rule()
  line(`TOTAL PAGADO: ${money(receipt.total)}`, 23, true)
  line(`Método: ${receipt.metodo === 'TARJETA' ? 'Tarjeta' : 'Efectivo'}`)
  rule()
  line('Gracias por tu visita', 17, true)
  line('Registro de cobro. No enviado a SUNAT.', 13)
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="480" height="${y+20}" viewBox="0 0 480 ${y+20}"><rect width="480" height="${y+20}" fill="white"/><g font-family="Arial,sans-serif" fill="#173d30">${rows.join('')}</g></svg>`)}`
}
