export interface Pad {
  id: string
  title: string
  content: string
  language: string
  createdAt: string
  updatedAt: string
}

export interface EditorSettings {
  wordWrap: boolean
  minimap: boolean
  fontSize: number
  lineNumbers: boolean
}

export interface CursorInfo {
  line: number
  column: number
}
