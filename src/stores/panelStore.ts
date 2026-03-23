import { create } from 'zustand'
import { invoke } from '@tauri-apps/api/core'
import { getCurrentWindow, LogicalSize } from '@tauri-apps/api/window'
import { WebviewWindow } from '@tauri-apps/api/webviewWindow'
import type { Notice } from '../types/notice.ts'

const TAB_WIDTH = 200
const MONITOR_WIDTH = 560

/** Get Agent Monitor's window bounds in logical points for layout exclusion. */
async function getMonitorRect(): Promise<WindowRect> {
  const win = getCurrentWindow()
  const pos = await win.outerPosition()
  const size = await win.outerSize()
  const factor = await win.scaleFactor()
  return {
    x: Math.round(pos.x / factor),
    y: Math.round(pos.y / factor),
    width: Math.round(size.width / factor),
    height: Math.round(size.height / factor),
  }
}

export type SwitchStatus =
  | { kind: 'idle' }
  | { kind: 'switching'; id: string }
  | { kind: 'succeeded'; id: string }
  | { kind: 'failed'; id: string; error?: string }

export type TitleFilter = 'cursor' | 'claudeCode' | 'terminal' | null
export type SidebarMode = 'monitor' | 'tab' | 'project' | 'settings'
export type MonitorSlotPosition = 'first' | 'last' | 'fixed' | 'none'

export interface DiscoveredSession {
  app: string
  title: string
  tty: string | null
  pid: number | null
  sourceKind: string
  alreadyAdded: boolean
}

export interface OrphanedSession {
  key: string
  title: string
  sourceKind: string
}

export interface DiscoverResult {
  sessions: DiscoveredSession[]
  orphaned: OrphanedSession[]
}

export interface WindowRect {
  x: number
  y: number
  width: number
  height: number
}

export interface ScreenSize {
  width: number
  height: number
}

export interface LayoutPreview {
  screen: ScreenSize
  rects: WindowRect[]
  monitorIndex: number | null
  monitorRect: WindowRect | null
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
  overlayActive: boolean
  previewLayout: string | null
  previewSessionIds: string[] | null
  monitorSlotPosition: MonitorSlotPosition
  alwaysOnTop: boolean
  highlightSessionId: string | null

  // Actions
  setAlwaysOnTop: (on: boolean) => Promise<void>
  setMonitorSlotPosition: (pos: MonitorSlotPosition) => void
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
  showLayoutPreview: (sessionIds: string[], layout: string) => Promise<void>
  hideLayoutPreview: () => Promise<void>
  confirmLayout: () => Promise<{ ok: boolean; message: string }>
  cleanupStaleSessions: () => Promise<{ ok: boolean; message: string }>
  discoverSessions: () => Promise<DiscoverResult>
  registerDiscovered: (s: DiscoveredSession) => Promise<{ ok: boolean; message: string }>
  capturePreview: (sessionId: string) => Promise<void>
  showHighlightBorder: (sessionId: string, color: string) => Promise<void>
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
  overlayActive: false,
  previewLayout: null,
  previewSessionIds: null,
  monitorSlotPosition: 'last',
  alwaysOnTop: true,
  highlightSessionId: null,

  setAlwaysOnTop: async (on) => {
    try {
      const win = getCurrentWindow()
      await win.setAlwaysOnTop(on)
      set({ alwaysOnTop: on })
    } catch {
      // ignore
    }
  },

  setMonitorSlotPosition: (pos) => set({ monitorSlotPosition: pos }),

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
      const { monitorSlotPosition } = get()
      let monitorSlot: number | null = null
      let excludeSelf: boolean | null = null
      if (monitorSlotPosition === 'first') monitorSlot = 0
      else if (monitorSlotPosition === 'last') monitorSlot = sessionIds.length
      else if (monitorSlotPosition === 'fixed') excludeSelf = true
      return await invoke<{ ok: boolean; message: string }>(
        'arrange_windows',
        { sessionIds, layout, monitorSlot, excludeSelf }
      )
    } catch (e) {
      return { ok: false, message: String(e) }
    }
  },

  showLayoutPreview: async (sessionIds, layout) => {
    // Close existing overlay if any
    try {
      const existing = await WebviewWindow.getByLabel('overlay')
      if (existing) await existing.close()
    } catch { /* ignore */ }

    try {
      const { monitorSlotPosition } = get()
      let monitorSlot: number | null = null
      let excludeSelf: boolean | null = null
      if (monitorSlotPosition === 'first') monitorSlot = 0
      else if (monitorSlotPosition === 'last') monitorSlot = sessionIds.length
      else if (monitorSlotPosition === 'fixed') excludeSelf = true

      const preview = await invoke<LayoutPreview>(
        'preview_layout',
        { sessionIds, layout, monitorSlot, excludeSelf }
      )

      const params = new URLSearchParams({
        rects: JSON.stringify(preview.rects),
        screen: JSON.stringify(preview.screen),
        layout,
        ...(preview.monitorIndex != null ? { monitorIndex: String(preview.monitorIndex) } : {}),
      })

      // Screen size from Rust is in logical points (Quartz reports logical on macOS).
      // Tauri window x/y/width/height are also in logical points.
      const overlay = new WebviewWindow('overlay', {
        url: `/overlay?${params}`,
        x: 0,
        y: 0,
        width: preview.screen.width,
        height: preview.screen.height,
        transparent: true,
        decorations: false,
        alwaysOnTop: true,
        visible: true,
        focus: false,
        shadow: false,
        skipTaskbar: true,
        resizable: false,
      })

      overlay.once('tauri://created', async () => {
        try {
          await overlay.setIgnoreCursorEvents(true)
        } catch (e) {
          console.error('Failed to set ignore cursor events:', e)
        }
      })

      overlay.once('tauri://error', (e) => {
        console.error('Overlay window error:', e)
        set({ overlayActive: false, previewLayout: null, previewSessionIds: null })
      })

      set({
        overlayActive: true,
        previewLayout: layout,
        previewSessionIds: sessionIds,
      })
    } catch (e) {
      console.error('Failed to show layout preview:', e)
      set({ overlayActive: false, previewLayout: null, previewSessionIds: null })
    }
  },

  hideLayoutPreview: async () => {
    try {
      const overlay = await WebviewWindow.getByLabel('overlay')
      if (overlay) await overlay.close()
    } catch { /* ignore */ }
    set({ overlayActive: false, previewLayout: null, previewSessionIds: null })
  },

  confirmLayout: async () => {
    const { previewSessionIds, previewLayout, monitorSlotPosition } = get()
    if (!previewSessionIds || !previewLayout) {
      return { ok: false, message: 'No preview active' }
    }

    let monitorSlot: number | null = null
    let excludeSelf: boolean | null = null
    if (monitorSlotPosition === 'first') monitorSlot = 0
    else if (monitorSlotPosition === 'last') monitorSlot = previewSessionIds.length
    else if (monitorSlotPosition === 'fixed') excludeSelf = true

    // Close the overlay first
    try {
      const overlay = await WebviewWindow.getByLabel('overlay')
      if (overlay) await overlay.close()
    } catch { /* ignore */ }

    try {
      const result = await invoke<{ ok: boolean; message: string }>(
        'arrange_windows',
        { sessionIds: previewSessionIds, layout: previewLayout, monitorSlot, excludeSelf }
      )
      set({ overlayActive: false, previewLayout: null, previewSessionIds: null })
      return result
    } catch (e) {
      set({ overlayActive: false, previewLayout: null, previewSessionIds: null })
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
      return await invoke<DiscoverResult>('discover_sessions')
    } catch (e) {
      console.error('Failed to discover sessions:', e)
      return { sessions: [], orphaned: [] }
    }
  },

  registerDiscovered: async (s) => {
    try {
      const result = await invoke<{ ok: boolean; message: string }>(
        'register_discovered_session',
        { app: s.app, title: s.title, tty: s.tty, pid: s.pid, sourceKind: s.sourceKind }
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

  showHighlightBorder: async (sessionId, color) => {
    // Close existing highlight — acts as toggle when re-clicking same session
    try {
      const existing = await WebviewWindow.getByLabel('highlight')
      if (existing) {
        await existing.close()
        // If same session, just toggle off
        const prev = get().highlightSessionId
        if (prev === sessionId) {
          set({ highlightSessionId: null })
          return
        }
      }
    } catch { /* ignore */ }

    try {
      const rect = await invoke<{ x: number; y: number; width: number; height: number }>(
        'get_session_bounds',
        { sessionId }
      )

      const pad = 4
      const params = new URLSearchParams({
        color,
      })

      const highlight = new WebviewWindow('highlight', {
        url: `/highlight?${params}`,
        x: rect.x - pad,
        y: rect.y - pad,
        width: rect.width + pad * 2,
        height: rect.height + pad * 2,
        transparent: true,
        decorations: false,
        alwaysOnTop: true,
        visible: true,
        focus: false,
        shadow: false,
        skipTaskbar: true,
        resizable: false,
      })

      highlight.once('tauri://created', async () => {
        try {
          await highlight.setIgnoreCursorEvents(true)
        } catch { /* ignore */ }
      })

      set({ highlightSessionId: sessionId })
    } catch {
      // Silently fail highlight
    }
  },
}))
