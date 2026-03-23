import { matchesCursor, matchesClaudeCode, matchesTerminal } from './titleFilters.ts'

export type SourceKind = 'cursor' | 'claudeCode' | 'terminal' | 'other'

export function getSourceKind(title: string): SourceKind {
  if (matchesCursor(title)) return 'cursor'
  if (matchesClaudeCode(title)) return 'claudeCode'
  if (matchesTerminal(title)) return 'terminal'
  return 'other'
}

export const SOURCE_COLORS: Record<SourceKind, string> = {
  cursor: 'hsl(270, 25%, 65%)',
  claudeCode: 'hsl(162, 25%, 60%)',
  terminal: 'hsl(30, 90%, 55%)',
  other: 'hsl(0, 0%, 55%)',
}

export const HUE_PALETTE = [
  0.0,    // red
  0.08,   // orange
  0.15,   // yellow
  0.33,   // green
  0.5,    // teal
  0.6,    // blue
  0.72,   // indigo
  0.8,    // purple
  0.9,    // pink
]

export function hueToColor(hue: number, saturation = 45, lightness = 55): string {
  return `hsl(${Math.round(hue * 360)}, ${saturation}%, ${lightness}%)`
}
