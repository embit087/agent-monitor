export function matchesCursor(title: string): boolean {
  return title.toLowerCase().includes('cursor')
}

export function matchesClaudeCode(title: string): boolean {
  const lower = title.toLowerCase()
  return lower.includes('claude code') || lower.includes('claudecode')
}

export function matchesTerminal(title: string): boolean {
  return title.toLowerCase().includes('terminal')
}
