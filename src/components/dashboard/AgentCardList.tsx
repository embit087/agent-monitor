import { useEffect, useMemo, useRef } from 'react'
import { Search, Inbox } from 'lucide-react'
import { useFilteredItems } from '../../hooks/useFilteredItems.ts'
import { usePanelStore } from '../../stores/panelStore.ts'
import { AgentCard } from './AgentCard.tsx'
import { AgentExploreCard } from './AgentExploreCard.tsx'
import type { Notice } from '../../types/notice.ts'

type CardGroup =
  | { kind: 'single'; notice: Notice }
  | { kind: 'explore'; notices: Notice[] }

/** Group consecutive PostToolUse notices into collapsible explore blocks. */
function groupNotices(items: Notice[]): CardGroup[] {
  const groups: CardGroup[] = []
  let run: Notice[] = []

  const flushRun = () => {
    if (run.length >= 3) {
      groups.push({ kind: 'explore', notices: run })
    } else {
      for (const n of run) {
        groups.push({ kind: 'single', notice: n })
      }
    }
    run = []
  }

  for (const n of items) {
    if (n.source === 'PostToolUse') {
      run.push(n)
    } else {
      flushRun()
      groups.push({ kind: 'single', notice: n })
    }
  }
  flushRun()
  return groups
}

export function AgentCardList() {
  const items = useFilteredItems()
  const titleFilter = usePanelStore((s) => s.titleFilter)
  const selectedSessionId = usePanelStore((s) => s.selectedSessionId)
  const threadRef = useRef<HTMLDivElement>(null)

  const groups = useMemo(() => groupNotices(items), [items])

  // Auto-scroll to the first (latest) highlighted message when session changes
  useEffect(() => {
    if (!selectedSessionId || !threadRef.current) return
    const el = threadRef.current.querySelector('.chat-message.highlighted')
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
    }
  }, [selectedSessionId])

  if (items.length === 0) {
    return (
      <div className="empty-state">
        {titleFilter ? (
          <>
            <Search size={24} />
            <span>No notifications match this filter.</span>
          </>
        ) : (
          <>
            <Inbox size={24} />
            <span>No notifications yet.</span>
            <span style={{ fontSize: 11 }}>
              POST to /api/notify to send notifications.
            </span>
          </>
        )}
      </div>
    )
  }

  return (
    <div className="chat-thread" ref={threadRef}>
      {groups.map((g) =>
        g.kind === 'explore' ? (
          <AgentExploreCard key={g.notices[0].id} notices={g.notices} />
        ) : (
          <AgentCard key={g.notice.id} notice={g.notice} />
        )
      )}
    </div>
  )
}
