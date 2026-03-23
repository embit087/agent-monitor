import { create } from 'zustand'
import { invoke } from '@tauri-apps/api/core'
import { getCurrentWindow, LogicalSize } from '@tauri-apps/api/window'
import type { Notice } from '../types/notice.ts'

const TAB_WIDTH = 200
const MONITOR_WIDTH = 560

export type SwitchStatus =
  | { kind: 'idle' }
  | { kind: 'switching'; id: string }
  | { kind: 'succeeded'; id: string }
  | { kind: 'failed'; id: string; error?: string }

export type TitleFilter = 'cursor' | 'claudeCode' | 'terminal' | null
export type SidebarMode = 'monitor' | 'tab' | 'project'

export interface DiscoveredSession {
  app: string
  title: string
  tty: string | null
  sourceKind: string
}

interface PanelState {
  notices: Notice[]
  serverRunning: boolean
  lastError: string | null
  switchStatus: SwitchStatus
  previewImage: string | null
  previewSessionId: string | null
  titleFilter: TitleFilter
  selectedSessionId: string | null
  hideResponses: boolean
  sidebarMode: SidebarMode
  focusInputAt: number
  draggingSessionKey: string | null

  // Actions
  fetchNotices: () => Promise<void>
  fetchServerStatus: () => Promise<void>
  prependNotice: (notice: Notice) => void
  clearNotices: () => Promise<void>
  setServerRunning: (running: boolean) => void
  setLastError: (error: string | null) => void
  setSwitchStatus: (status: SwitchStatus) => void
  setTitleFilter: (filter: TitleFilter) => void
  setSelectedSessionId: (id: string | null) => void
  toggleHideResponses: () => void
  setDraggingSessionKey: (key: string | null) => void
  setSidebarMode: (mode: SidebarMode) => Promise<void>
  saveSelf: () => Promise<void>
  focusSelf: () => Promise<void>
  requestFocusInput: () => void
  sendNotice: (body: string, sessionId?: string) => Promise<void>
  sendToSession: (sessionId: string, text: string, sourceKind?: string) => Promise<{ ok: boolean; message: string }>
  openWinidSession: (sessionId: string) => Promise<void>
  closeWinidSession: (sessionId: string) => Promise<void>
  upsertManualTerminal: (winid: string) => Promise<void>
  captureFrontmost: () => Promise<{ ok: boolean; message: string }>
  arrangeWindows: (sessionIds: string[], layout: string) => Promise<{ ok: boolean; message: string }>
  cleanupStaleSessions: () => Promise<{ ok: boolean; message: string }>
  discoverSessions: () => Promise<DiscoveredSession[]>
  registerDiscovered: (s: DiscoveredSession) => Promise<{ ok: boolean; message: string }>
  capturePreview: (sessionId: string) => Promise<void>
}

export const usePanelStore = create<PanelState>((set, get) => ({
  notices: [],
  serverRunning: false,
  lastError: null,
  switchStatus: { kind: 'idle' },
  previewImage: null,
  previewSessionId: null,
  titleFilter: null,
  selectedSessionId: null,
  hideResponses: false,
  sidebarMode: 'monitor',
  focusInputAt: 0,
  draggingSessionKey: null,

  fetchNotices: async () => {
    try {
      const notices = await invoke<Notice[]>('get_notices')
      set({ notices })
    } catch (e) {
      console.error('Failed to fetch notices:', e)
    }
  },

  fetchServerStatus: async () => {
    try {
      const status = await invoke<{ running: boolean; port: number; items: number }>('get_server_status')
      set({ serverRunning: status.running })
    } catch (e) {
      console.error('Failed to fetch server status:', e)
    }
  },

  prependNotice: (notice) => {
    set((state) => ({
      notices: [notice, ...state.notices],
    }))
  },

  clearNotices: async () => {
    try {
      await invoke('clear_notices')
      set({ notices: [] })
    } catch (e) {
      console.error('Failed to clear notices:', e)
    }
  },

  setServerRunning: (running) => set({ serverRunning: running }),
  setLastError: (error) => set({ lastError: error }),
  setSwitchStatus: (status) => set({ switchStatus: status }),
  setTitleFilter: (filter) => set({ titleFilter: filter }),
  setSelectedSessionId: (id) => set({ selectedSessionId: id }),
  toggleHideResponses: () => set((s) => ({ hideResponses: !s.hideResponses })),
  setDraggingSessionKey: (key) => set({ draggingSessionKey: key }),
  setSidebarMode: async (mode) => {
    set({ sidebarMode: mode })
    try {
      const win = getCurrentWindow()
      const factor = await win.scaleFactor()
      const phys = await win.innerSize()
      const logicalH = Math.round(phys.height / factor)
      const newWidth = mode === 'tab' ? TAB_WIDTH : MONITOR_WIDTH
      await win.setSize(new LogicalSize(newWidth, logicalH))
    } catch {
      // ignore resize errors
    }
  },

  saveSelf: async () => {
    try {
      await invoke('save_self')
    } catch {
      // ignore
    }
  },

  focusSelf: async () => {
    try {
      await invoke('focus_self')
    } catch {
      // ignore
    }
  },

  requestFocusInput: () => set({ focusInputAt: Date.now() }),

  sendNotice: async (body, sessionId) => {
    try {
      await invoke('send_notice', {
        body,
        sessionId: sessionId || null,
      })
      await get().fetchNotices()
    } catch (e) {
      console.error('Failed to send notice:', e)
    }
  },

  sendToSession: async (sessionId, text, sourceKind) => {
    try {
      const result = await invoke<{ ok: boolean; message: string; tty: string | null }>(
        'send_to_session',
        { sessionId, text, sourceKind: sourceKind || 'terminal' }
      )
      return { ok: result.ok, message: result.message }
    } catch (e) {
      return { ok: false, message: String(e) }
    }
  },

  openWinidSession: async (sessionId) => {
    set({ switchStatus: { kind: 'switching', id: sessionId } })
    try {
      const result = await invoke<{ ok: boolean; message: string }>('open_winid_session', { sessionId })
      if (result.ok) {
        set({ switchStatus: { kind: 'succeeded', id: sessionId } })
        // Auto-clear after 3s
        setTimeout(() => {
          if (get().switchStatus.kind === 'succeeded') {
            set({ switchStatus: { kind: 'idle' } })
          }
        }, 3000)
        // Capture preview after switch
        setTimeout(() => get().capturePreview(sessionId), 500)
      } else {
        set({ switchStatus: { kind: 'failed', id: sessionId, error: result.message } })
        setTimeout(() => {
          if (get().switchStatus.kind === 'failed') {
            set({ switchStatus: { kind: 'idle' } })
          }
        }, 5000)
      }
    } catch (e) {
      set({ switchStatus: { kind: 'failed', id: sessionId, error: String(e) } })
    }
  },

  closeWinidSession: async (sessionId) => {
    try {
      await invoke('close_winid_session', { sessionId })
      set((state) => ({
        notices: state.notices.filter(
          (n) => n.action?.trim() !== sessionId.trim()
        ),
      }))
    } catch (e) {
      console.error('Failed to close session:', e)
    }
  },

  upsertManualTerminal: async (winid) => {
    try {
      await invoke('upsert_manual_terminal', { winid })
      await get().fetchNotices()
    } catch (e) {
      console.error('Failed to upsert manual terminal:', e)
    }
  },

  captureFrontmost: async () => {
    try {
      const result = await invoke<{ ok: boolean; message: string }>('capture_frontmost_session')
      if (result.ok) {
        await get().fetchNotices()
      }
      return result
    } catch (e) {
      return { ok: false, message: String(e) }
    }
  },

  arrangeWindows: async (sessionIds, layout) => {
    try {
      return await invoke<{ ok: boolean; message: string }>('arrange_windows', { sessionIds, layout })
    } catch (e) {
      return { ok: false, message: String(e) }
    }
  },

  cleanupStaleSessions: async () => {
    try {
      const result = await invoke<{ ok: boolean; message: string }>('cleanup_stale_sessions')
      if (result.ok) {
        await get().fetchNotices()
      }
      return result
    } catch (e) {
      return { ok: false, message: String(e) }
    }
  },

  discoverSessions: async () => {
    try {
      return await invoke<DiscoveredSession[]>('discover_sessions')
    } catch (e) {
      console.error('Failed to discover sessions:', e)
      return []
    }
  },

  registerDiscovered: async (s) => {
    try {
      const result = await invoke<{ ok: boolean; message: string }>(
        'register_discovered_session',
        { app: s.app, title: s.title, tty: s.tty, sourceKind: s.sourceKind }
      )
      if (result.ok) {
        await get().fetchNotices()
      }
      return result
    } catch (e) {
      return { ok: false, message: String(e) }
    }
  },

  capturePreview: async (sessionId) => {
    try {
      const result = await invoke<{ ok: boolean; image?: string; error?: string }>('capture_window_preview', { sessionId })
      if (result.ok && result.image) {
        set({ previewImage: result.image, previewSessionId: sessionId })
      }
    } catch {
      // Silently fail preview capture
    }
  },
}))
