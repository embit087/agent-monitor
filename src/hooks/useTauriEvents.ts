import { useEffect } from 'react'
import { listen } from '@tauri-apps/api/event'
import { usePanelStore } from '../stores/panelStore.ts'

export function useTauriEvents() {
  const setServerRunning = usePanelStore((s) => s.setServerRunning)
  const setLastError = usePanelStore((s) => s.setLastError)
  const setSwitchStatus = usePanelStore((s) => s.setSwitchStatus)
  const fetchNotices = usePanelStore((s) => s.fetchNotices)

  useEffect(() => {
    const unlisten: Array<() => void> = []

    listen<Notice>('notice:new', () => {
      fetchNotices()
    }).then((u) => unlisten.push(u))

    listen('notice:clear', () => {
      fetchNotices()
    }).then((u) => unlisten.push(u))

    listen<number>('server:listening', () => {
      setServerRunning(true)
      setLastError(null)
    }).then((u) => unlisten.push(u))

    listen<string>('server:error', (event) => {
      setLastError(event.payload)
      setServerRunning(false)
    }).then((u) => unlisten.push(u))

    listen<{ status: string; id: string; error?: string }>('winid:status', (event) => {
      const { status, id, error } = event.payload
      switch (status) {
        case 'switching':
          setSwitchStatus({ kind: 'switching', id })
          break
        case 'succeeded':
          setSwitchStatus({ kind: 'succeeded', id })
          break
        case 'failed':
          setSwitchStatus({ kind: 'failed', id, error })
          break
      }
    }).then((u) => unlisten.push(u))

    return () => {
      unlisten.forEach((u) => u())
    }
  }, [setServerRunning, setLastError, setSwitchStatus, fetchNotices])
}
