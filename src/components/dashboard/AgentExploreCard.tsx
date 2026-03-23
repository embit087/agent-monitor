import { useState } from 'react'
import { ChevronRight } from 'lucide-react'
import type { Notice } from '../../types/notice.ts'
import { usePanelStore } from '../../stores/panelStore.ts'
import { formatDate } from '../../utils/formatting.ts'

/** Renders a collapsible group of consecutive PostToolUse notifications. */
export function AgentExploreCard({ notices }: { notices: Notice[] }) {
  const [expanded, setExpanded] = useState(false)
  const selectedSessionId = usePanelStore((s) => s.selectedSessionId)
  const setSelectedSessionId = usePanelStore((s) => s.setSelectedSessionId)

  if (notices.length === 0) return null

  const first = notices[0]
  const last = notices[notices.length - 1]
  const sessionKey = first.action?.trim() || null
  const highlighted = sessionKey === selectedSessionId

  const handleSessionClick = (e: React.MouseEvent) => {
    e.stopPropagation()
    if (!sessionKey) return
    setSelectedSessionId(selectedSessionId === sessionKey ? null : sessionKey)
  }

  // Extract tool name from body (e.g. "Read: /path" → "Read")
  const toolCounts = new Map<string, number>()
  for (const n of notices) {
    const colon = n.body.indexOf(':')
    const tool = colon > 0 ? n.body.slice(0, colon).trim() : n.body.trim()
    toolCounts.set(tool, (toolCounts.get(tool) || 0) + 1)
  }
  const toolSummary = Array.from(toolCounts.entries())
    .sort((a, b) => b[1] - a[1])
    .map(([tool, count]) => `${count} ${tool}`)
    .join(', ')

  return (
    <div
      className={`explore-card ${highlighted ? 'highlighted' : ''} ${sessionKey ? 'clickable' : ''}`}
      onClick={handleSessionClick}
    >
      <div className="explore-card-header" onClick={(e) => { e.stopPropagation(); setExpanded(!expanded) }}>
        <ChevronRight
          size={12}
          className={`explore-card-chevron ${expanded ? 'expanded' : ''}`}
        />
        <span className="explore-card-count">{notices.length} tool calls</span>
        <span className="explore-card-tools">{toolSummary}</span>
        <span className="explore-card-time">
          {formatDate(last.at)} &ndash; {formatDate(first.at)}
        </span>
      </div>

      {expanded && (
        <div className="explore-card-items">
          {notices.map((n) => (
            <div key={n.id} className="explore-card-item">
              <span className="explore-card-item-text">{n.body}</span>
              <span className="explore-card-item-time">{formatDate(n.at)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
