export function formatDate(isoString: string): string {
  const date = new Date(isoString)
  return date.toLocaleDateString('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}

export function shortSessionId(id: string): string {
  return id.trim().slice(0, 8)
}

export function truncateLabel(label: string, max = 30): string {
  if (label.length <= max) return label
  return label.slice(0, max) + '\u2026'
}

export function formatResponseForDisplay(text: string): string {
  // Normalize line endings
  let result = text.replace(/\r\n/g, '\n')
  // Collapse excessive blank lines
  result = result.replace(/\n{3,}/g, '\n\n')
  return result.trim()
}

export function looksLikeJSON(text: string): boolean {
  const trimmed = text.trim()
  return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
    (trimmed.startsWith('[') && trimmed.endsWith(']'))
}

export function prettyPrintJSON(text: string): string {
  try {
    const parsed = JSON.parse(text)
    return JSON.stringify(parsed, null, 2)
  } catch {
    return text
  }
}

export function formatResponseAsMarkdown(text: string): string {
  const normalized = formatResponseForDisplay(text)

  if (looksLikeJSON(normalized)) {
    return '```json\n' + prettyPrintJSON(normalized) + '\n```'
  }

  // Check for NDJSON (multiple JSON lines)
  const lines = normalized.split('\n').filter((l) => l.trim())
  if (lines.length > 1 && lines.every((l) => looksLikeJSON(l))) {
    return lines
      .map((l) => '```json\n' + prettyPrintJSON(l) + '\n```')
      .join('\n\n')
  }

  return normalized
}
