import { create } from 'zustand'
import { invoke } from '@tauri-apps/api/core'
import type { Pad, EditorSettings, CursorInfo } from '../types/pad.ts'

interface NotepadState {
  pads: Pad[]
  activePadId: string | null
  cursor: CursorInfo
  wordCount: number
  charCount: number
  lineCount: number
  selectionLength: number
  settings: EditorSettings

  fetchPads: () => Promise<void>
  createPad: (title: string, content: string, language: string) => Promise<void>
  updatePad: (id: string, updates: { title?: string; content?: string; language?: string }) => Promise<void>
  deletePad: (id: string) => Promise<void>
  setActivePad: (id: string) => void
  updateCursor: (cursor: CursorInfo) => void
  updateStats: (stats: { wordCount: number; charCount: number; lineCount: number; selectionLength: number }) => void
  toggleWordWrap: () => void
  toggleMinimap: () => void
  toggleLineNumbers: () => void
  adjustFontSize: (delta: number) => void
}

export const useNotepadStore = create<NotepadState>((set, get) => ({
  pads: [],
  activePadId: null,
  cursor: { line: 1, column: 1 },
  wordCount: 0,
  charCount: 0,
  lineCount: 0,
  selectionLength: 0,
  settings: {
    wordWrap: true,
    minimap: false,
    fontSize: 13,
    lineNumbers: true,
  },

  fetchPads: async () => {
    try {
      const pads = await invoke<Pad[]>('list_pads')
      set({ pads, activePadId: pads.length > 0 ? pads[0].id : null })
    } catch (e) {
      console.error('Failed to fetch pads:', e)
    }
  },

  createPad: async (title, content, language) => {
    try {
      const pad = await invoke<Pad>('create_pad', { title, content, language })
      set((s) => ({ pads: [...s.pads, pad], activePadId: pad.id }))
    } catch (e) {
      console.error('Failed to create pad:', e)
    }
  },

  updatePad: async (id, updates) => {
    try {
      await invoke('update_pad', { id, ...updates })
      set((s) => ({
        pads: s.pads.map((p) =>
          p.id === id
            ? {
                ...p,
                ...(updates.title !== undefined && { title: updates.title }),
                ...(updates.content !== undefined && { content: updates.content }),
                ...(updates.language !== undefined && { language: updates.language }),
              }
            : p
        ),
      }))
    } catch (e) {
      console.error('Failed to update pad:', e)
    }
  },

  deletePad: async (id) => {
    try {
      await invoke('delete_pad', { id })
      set((s) => {
        const pads = s.pads.filter((p) => p.id !== id)
        return {
          pads,
          activePadId: s.activePadId === id ? (pads[0]?.id ?? null) : s.activePadId,
        }
      })
    } catch (e) {
      console.error('Failed to delete pad:', e)
    }
  },

  setActivePad: (id) => set({ activePadId: id }),
  updateCursor: (cursor) => set({ cursor }),
  updateStats: (stats) => set(stats),
  toggleWordWrap: () => set((s) => ({ settings: { ...s.settings, wordWrap: !s.settings.wordWrap } })),
  toggleMinimap: () => set((s) => ({ settings: { ...s.settings, minimap: !s.settings.minimap } })),
  toggleLineNumbers: () => set((s) => ({ settings: { ...s.settings, lineNumbers: !s.settings.lineNumbers } })),
  adjustFontSize: (delta) =>
    set((s) => ({
      settings: {
        ...s.settings,
        fontSize: Math.max(10, Math.min(24, s.settings.fontSize + delta)),
      },
    })),
}))
