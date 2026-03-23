import { useState } from 'react'
import { usePanelStore } from '../../stores/panelStore.ts'
import { useProjectStore } from '../../stores/projectStore.ts'
import { useSessionTabs } from '../../hooks/useSessionTabs.ts'
import { hueToColor, SOURCE_COLORS } from '../../utils/colors.ts'
import { shortSessionId } from '../../utils/formatting.ts'

export function ProjectDropOverlay() {
  const draggingSessionKey = usePanelStore((s) => s.draggingSessionKey)
  const groups = useProjectStore((s) => s.groups)
  const toggleSessionInProject = useProjectStore((s) => s.toggleSessionInProject)
  const tabs = useSessionTabs()
  const [dragOverId, setDragOverId] = useState<string | null>(null)

  if (!draggingSessionKey || groups.length === 0) return null

  const draggingTab = tabs.find((t) => t.sessionKey === draggingSessionKey)

  const handleDragEnter = (e: React.DragEvent, id: string) => {
    e.preventDefault()
    e.stopPropagation()
    setDragOverId(id)
  }

  const handleDragOver = (e: React.DragEvent, id: string) => {
    e.preventDefault()
    e.stopPropagation()
    e.dataTransfer.dropEffect = 'link'
    setDragOverId(id)
  }

  const handleDragLeave = (e: React.DragEvent) => {
    if (e.currentTarget.contains(e.relatedTarget as Node)) return
    setDragOverId(null)
  }

  const handleDrop = (e: React.DragEvent, groupId: string) => {
    e.preventDefault()
    e.stopPropagation()
    setDragOverId(null)
    const sessionKey = e.dataTransfer.getData('application/x-session-key')
      || e.dataTransfer.getData('text/plain')
    if (sessionKey) {
      toggleSessionInProject(sessionKey, groupId)
    }
  }

  return (
    <div className="project-drop-overlay">
      <div className="project-drop-header">
        Drop{draggingTab ? ` #${draggingTab.index} ` : ' '}into a project
      </div>
      <div className="project-drop-zones">
        {groups.map((g) => {
          const isOver = dragOverId === g.id
          const alreadyIn = g.sessionKeys.includes(draggingSessionKey)
          const color = hueToColor(g.colorHue, 45, 55)
          const members = tabs.filter((t) => g.sessionKeys.includes(t.sessionKey))

          return (
            <div
              key={g.id}
              className={`project-drop-zone ${isOver ? 'drag-over' : ''} ${alreadyIn ? 'already-in' : ''}`}
              onDragEnter={(e) => handleDragEnter(e, g.id)}
              onDragOver={(e) => handleDragOver(e, g.id)}
              onDragLeave={handleDragLeave}
              onDrop={(e) => handleDrop(e, g.id)}
              style={{
                borderColor: isOver ? color : undefined,
                background: isOver ? `${hueToColor(g.colorHue, 30, 20)}40` : undefined,
              }}
            >
              <div className="project-drop-zone-header">
                <span className="dot" style={{ background: color }} />
                <span className="project-drop-zone-name">{g.name}</span>
                {alreadyIn && <span className="project-drop-zone-badge">assigned</span>}
              </div>
              {members.length > 0 && (
                <div className="project-drop-zone-members">
                  {members.map((t) => (
                    <span key={t.sessionKey} className="project-drop-zone-member">
                      <span className="project-drop-zone-member-dot" style={{ background: SOURCE_COLORS[t.sourceKind] }} />
                      #{t.index} {shortSessionId(t.sessionKey)}
                    </span>
                  ))}
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
