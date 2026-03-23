import { useEffect, useRef } from 'react'
import { Search, Inbox } from 'lucide-react'
import { useFilteredItems } from '../../hooks/useFilteredItems.ts'
import { usePanelStore } from '../../stores/panelStore.ts'
import { AgentCard } from './AgentCard.tsx'

export function AgentCardList() {
  const items = useFilteredItems()
  const titleFilter = usePanelStore((s) => s.titleFilter)
  const selectedSessionId = usePanelStore((s) => s.selectedSessionId)
  const threadRef = useRef<HTMLDivElement>(null)

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
      {items.map((notice) => (
        <AgentCard key={notice.id} notice={notice} />
      ))}
    </div>
  )
}
