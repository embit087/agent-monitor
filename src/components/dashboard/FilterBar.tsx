import { usePanelStore } from '../../stores/panelStore.ts'
import { Tooltip } from './Tooltip.tsx'

export function FilterBar() {
  const serverRunning = usePanelStore((s) => s.serverRunning)
  const notices = usePanelStore((s) => s.notices)
  const clearNotices = usePanelStore((s) => s.clearNotices)
  const hideResponses = usePanelStore((s) => s.hideResponses)
  const toggleHideResponses = usePanelStore((s) => s.toggleHideResponses)

  return (
    <div className="filter-bar">
      <span className={`status-dot ${serverRunning ? 'running' : 'starting'}`} />

      <div style={{ flex: 1 }} />

      <Tooltip text="Show only user prompts; hide AI responses" position="bottom">
        <button
          type="button"
          className={`text-btn ${hideResponses ? 'active' : ''}`}
          onClick={() => toggleHideResponses()}
        >
          User only
        </button>
      </Tooltip>

      {notices.length > 0 && (
        <button
          className="text-btn"
          onClick={() => {
            if (confirm('Clear all notifications?')) clearNotices()
          }}
        >
          Clear
        </button>
      )}

      <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>v0.1.0</span>
    </div>
  )
}
