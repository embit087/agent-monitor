import { useState } from 'react'
import { useProjectStore } from '../../stores/projectStore.ts'
import { useSessionTabs } from '../../hooks/useSessionTabs.ts'
import { hueToColor, SOURCE_COLORS } from '../../utils/colors.ts'
import { shortSessionId } from '../../utils/formatting.ts'

export function ProjectManagePanel() {
  const groups = useProjectStore((s) => s.groups)
  const toggleSessionInProject = useProjectStore((s) => s.toggleSessionInProject)
  const createProject = useProjectStore((s) => s.createProject)
  const tabs = useSessionTabs()

  const [dragOverId, setDragOverId] = useState<string | null>(null)
  const [newName, setNewName] = useState('')

  // Sessions not in any project
  const allAssigned = new Set(groups.flatMap((g) => g.sessionKeys))
  const unassigned = tabs.filter((t) => !allAssigned.has(t.sessionKey))

  const handleDragEnter = (e: React.DragEvent, id: string) => {
    if (e.dataTransfer.types.includes('application/x-session-key') || e.dataTransfer.types.includes('text/plain')) {
      e.preventDefault()
      e.stopPropagation()
      setDragOverId(id)
    }
  }

  const handleDragOver = (e: React.DragEvent, id: string) => {
    if (e.dataTransfer.types.includes('application/x-session-key') || e.dataTransfer.types.includes('text/plain')) {
      e.preventDefault()
      e.stopPropagation()
      e.dataTransfer.dropEffect = 'link'
      setDragOverId(id)
    }
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

  const handleCreate = () => {
    if (newName.trim()) {
      createProject(newName.trim())
      setNewName('')
    }
  }

  return (
    <div className="project-manage-view">
      <div className="project-manage-view-header">
        <span className="project-manage-view-title">Drag agents to projects</span>
      </div>

      <div className="project-manage-view-list">
        {groups.map((g) => {
          const members = tabs.filter((t) => g.sessionKeys.includes(t.sessionKey))
          const isOver = dragOverId === g.id

          return (
            <div
              key={g.id}
              className={`project-zone ${isOver ? 'drag-over' : ''}`}
              onDragEnter={(e) => handleDragEnter(e, g.id)}
              onDragOver={(e) => handleDragOver(e, g.id)}
              onDragLeave={() => setDragOverId(null)}
              onDrop={(e) => handleDrop(e, g.id)}
              style={{ borderColor: isOver ? hueToColor(g.colorHue, 50, 60) : undefined }}
            >
              <div className="project-zone-header">
                <span className="dot" style={{ background: hueToColor(g.colorHue, 45, 55) }} />
                <span className="project-zone-name">{g.name}</span>
                <span className="project-zone-count">{members.length}</span>
              </div>
              {members.length > 0 ? (
                <div className="project-zone-members">
                  {members.map((t) => (
                    <div key={t.sessionKey} className="project-zone-member">
                      <span className="project-zone-member-dot" style={{ background: SOURCE_COLORS[t.sourceKind] }} />
                      <span className="project-zone-member-label">#{t.index} {t.label}</span>
                      <span className="project-zone-member-id">{shortSessionId(t.sessionKey)}</span>
                      <button
                        className="project-zone-remove"
                        onClick={() => toggleSessionInProject(t.sessionKey, g.id)}
                        title="Remove from project"
                      >
                        x
                      </button>
                    </div>
                  ))}
                </div>
              ) : (
                <span className="project-zone-empty">Drop agents here</span>
              )}
            </div>
          )
        })}

        {/* Unassigned */}
        {unassigned.length > 0 && (
          <div className="project-zone unassigned">
            <div className="project-zone-header">
              <span className="project-zone-name">Unassigned</span>
              <span className="project-zone-count">{unassigned.length}</span>
            </div>
            <div className="project-zone-members">
              {unassigned.map((t) => (
                <div key={t.sessionKey} className="project-zone-member">
                  <span className="project-zone-member-dot" style={{ background: SOURCE_COLORS[t.sourceKind] }} />
                  <span className="project-zone-member-label">#{t.index} {t.label}</span>
                  <span className="project-zone-member-id">{shortSessionId(t.sessionKey)}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Create new project */}
        <div className="project-zone-create">
          <input
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleCreate()}
            placeholder="New project name"
            className="project-zone-create-input"
          />
          <button
            className="project-zone-create-btn"
            onClick={handleCreate}
            disabled={!newName.trim()}
          >
            +
          </button>
        </div>
      </div>
    </div>
  )
}
