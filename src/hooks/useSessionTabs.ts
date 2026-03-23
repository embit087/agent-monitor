import { useMemo } from 'react'
import { usePanelStore } from '../stores/panelStore.ts'
import type { Notice } from '../types/notice.ts'
import { getSourceKind, type SourceKind } from '../utils/colors.ts'

export interface SessionTab {
  sessionKey: string
  openAction: string
  label: string
  index: number
  count: number
  msgCount: number
  toolCount: number
  latestAt: string
  sourceKind: SourceKind
}

export function useSessionTabs(): SessionTab[] {
  const notices = usePanelStore((s) => s.notices)

  return useMemo(() => {
    // Build one tab per unique session key (no title filter — always show all)
    const seen = new Map<string, { notice: Notice; count: number; msgCount: number; toolCount: number; latestAt: string }>()
    for (const n of notices) {
      const key = n.action?.trim()
      if (!key) continue
      const isTool = n.source === 'PostToolUse'
      const existing = seen.get(key)
      if (existing) {
        existing.count++
        if (isTool) existing.toolCount++
        else existing.msgCount++
        if (n.at > existing.latestAt) existing.latestAt = n.at
      } else {
        seen.set(key, { notice: n, count: 1, msgCount: isTool ? 0 : 1, toolCount: isTool ? 1 : 0, latestAt: n.at })
      }
    }

    // Sort by latest message (most recent first)
    const sorted = [...seen.entries()].sort((a, b) =>
      b[1].latestAt.localeCompare(a[1].latestAt)
    )

    const tabs: SessionTab[] = []
    let index = 1
    for (const [key, { notice, count, msgCount, toolCount, latestAt }] of sorted) {
      tabs.push({
        sessionKey: key,
        openAction: key,
        label: notice.title || key.slice(0, 8),
        index: index++,
        count,
        msgCount,
        toolCount,
        latestAt,
        sourceKind: getSourceKind(notice.title),
      })
    }

    return tabs
  }, [notices])
}
