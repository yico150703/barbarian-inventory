import type { ReactNode } from 'react'

// Render a small, safe Markdown subset as React elements. Never interpret HTML.
function inline(text: string): ReactNode[] {
  return text.split(/(\*\*[^*]+\*\*|__[^_]+__|`[^`]+`|\*[^*\n]+\*)/g).map((part, i) => {
    if (part.startsWith('**') || part.startsWith('__')) return <strong key={i}>{part.slice(2, -2)}</strong>
    if (part.startsWith('`')) return <code key={i}>{part.slice(1, -1)}</code>
    if (part.startsWith('*') && part.endsWith('*')) return <em key={i}>{part.slice(1, -1)}</em>
    return part
  })
}

const cells = (line: string) => line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map(v => v.trim())
const listItem = /^\s*(?:[-*+] |\d+[.)] )/
const separator = (line: string) => cells(line).every(c => /^:?-{3,}:?$/.test(c))

export function FormattedAnswer({ text }: { text: string }) {
  const lines = text.replace(/\r\n/g, '\n').split('\n')
  const blocks: ReactNode[] = []
  let i = 0
  while (i < lines.length) {
    const line = lines[i].trim()
    const key = i
    if (!line) { i++; continue }
    if (line.includes('|') && i + 1 < lines.length && separator(lines[i + 1])) {
      const headings = cells(line)
      i += 2
      const rows: string[][] = []
      while (i < lines.length && lines[i].includes('|') && lines[i].trim()) rows.push(cells(lines[i++]))
      blocks.push(<div className="assistant-table-wrap" key={key} tabIndex={0} role="region" aria-label="Tabla de respuesta">
        <table className="assistant-data-table"><thead><tr>{headings.map((h, n) => <th scope="col" key={n}>{inline(h)}</th>)}</tr></thead>
          <tbody>{rows.map((r, n) => <tr key={n}>{headings.map((_, col) => <td key={col}>{inline(r[col] ?? '')}</td>)}</tr>)}</tbody></table></div>)
    } else if (/^#{1,6}\s/.test(line)) {
      blocks.push(<h3 key={key}>{inline(line.replace(/^#{1,6}\s+/, ''))}</h3>); i++
    } else if (listItem.test(line)) {
      const ordered = /^\d/.test(line)
      const items: ReactNode[] = []
      while (i < lines.length && listItem.test(lines[i])) {
        items.push(<li key={i}>{inline(lines[i++].replace(listItem, ''))}</li>)
        // Blank lines between list items should not create separate lists.
        if (!lines[i]?.trim() && listItem.test(lines[i + 1] ?? '')) i++
      }
      blocks.push(ordered ? <ol key={key}>{items}</ol> : <ul key={key}>{items}</ul>)
    } else if (/^(-{3,}|\*{3,}|_{3,})$/.test(line)) {
      blocks.push(<hr key={key} />); i++
    } else {
      const paragraph = [lines[i++]]
      while (i < lines.length && lines[i].trim() && !listItem.test(lines[i]) && !/^#{1,6}\s/.test(lines[i]) &&
        !(lines[i].includes('|') && separator(lines[i + 1] ?? ''))) paragraph.push(lines[i++])
      blocks.push(<p key={key}>{inline(paragraph.join('\n'))}</p>)
    }
  }
  return <div className="assistant-formatted-answer">{blocks}</div>
}
