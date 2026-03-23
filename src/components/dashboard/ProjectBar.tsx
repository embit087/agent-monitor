import { useState, useRef, useEffect } from 'react'
import { usePanelStore } from '../../stores/panelStore.ts'
import { useProjectStore } from '../../stores/projectStore.ts'
import { useSessionTabs } from '../../hooks/useSessionTabs.ts'
import { hueToColor, HUE_PALETTE } from '../../utils/colors.ts'

export function ProjectBar() {
  const groups = useProjectStore((s) => s.groups)
  const selectedGroupId = useProjectStore((s) => s.selectedGroupId)
  const setSelectedGroupId = useProjectStore((s) => s.setSelectedGroupId)
  const deleteProject = useProjectStore((s) => s.deleteProject)
  const renameProject = useProjectStore((s) => s.renameProject)
  const setProjectColor = useProjectStore((s) => s.setProjectColor)
  const moveSessionToProject = useProjectStore((s) => s.moveSessionToProject)
  const toggleSessionInProject = useProjectStore((s) => s.toggleSessionInProject)
  const serverRunning = usePanelStore((s) => s.serverRunning)
  const setSelectedSessionId = usePanelStore((s) => s.setSelectedSessionId)
  const draggingSessionKey = usePanelStore((s) => s.draggingSessionKey)
  const setDraggingSessionKey = usePanelStore((s) => s.setDraggingSessionKey)
  const sidebarMode = usePanelStore((s) => s.sidebarMode)
  const setSidebarMode = usePanelStore((s) => s.setSidebarMode)
  const tabs = useSessionTabs()

  const [editingId, setEditingId] = useState<string | null>(null)
  const [editName, setEditName] = useState('')
  const [pendingDeleteId, setPendingDeleteId] = useState<string | null>(null)
  const [dragOver, setDragOver] = useState<string | null>(null)
  const [managingId, setManagingId] = useState<string | null>(null)
  const panelRef = useRef<HTMLDivElement>(null)
  const renameInputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (editingId && renameInputRef.current) renameInputRef.current.focus()
  }, [editingId])

  // Close manage panel on outside click
  useEffect(() => {
    if (!managingId) return
    const handler = (e: MouseEvent) => {
      if (panelRef.current && !panelRef.current.contains(e.target as Node)) {
        setManagingId(null)
      }
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [managingId])

  const sessionCountForGroup = (group: typeof groups[0]) => {
    return tabs.filter((t) => group.sessionKeys.includes(t.sessionKey)).length
  }

  const handleRename = (id: string) => {
    if (editName.trim() && editName.trim() !== groups.find((g) => g.id === id)?.name) {
      renameProject(id, editName.trim())
    }
    setEditingId(null)
  }

  const startRename = (id: string, currentName: string) => {
    setEditingId(id)
    setEditName(currentName)
    setManagingId(null)
  }

  // Clear drag-over highlight when drag ends
  useEffect(() => {
    if (!draggingSessionKey) setDragOver(null)
  }, [draggingSessionKey])

  const pendingGroup = pendingDeleteId ? groups.find((g) => g.id === pendingDeleteId) : null
  const managingGroup = managingId ? groups.find((g) => g.id === managingId) : null

  return (
    <>
      <div className="project-bar">
        <div
          className={`project-chip ${!selectedGroupId ? 'active' : ''}`}
          onClick={() => {
            setSelectedGroupId(null)
            setSelectedSessionId(null)
          }}
          title="Show all sessions"
        >
          All
        </div>

        {groups.map((g) => {
          const count = sessionCountForGroup(g)
          const isDragOver = dragOver === g.id

          return (
            <div
              key={g.id}
              className={`project-chip ${selectedGroupId === g.id ? 'active' : ''} ${isDragOver ? 'drag-over' : ''}`}
              onClick={() => {
                if (!editingId) setSelectedGroupId(selectedGroupId === g.id ? null : g.id)
              }}
              title="Click to filter · Double-click to rename · Right-click to manage"
              onDoubleClick={(e) => {
                e.stopPropagation()
                startRename(g.id, g.name)
              }}
              onContextMenu={(e) => {
                e.preventDefault()
                setManagingId(managingId === g.id ? null : g.id)
              }}
              data-drop-project-id={g.id}
              onMouseEnter={() => { if (draggingSessionKey) setDragOver(g.id) }}
              onMouseLeave={() => { if (draggingSessionKey) setDragOver(null) }}
              onMouseUp={() => {
                if (draggingSessionKey) {
                  moveSessionToProject(draggingSessionKey, g.id)
                  setDragOver(null)
                  setDraggingSessionKey(null)
                  document.body.classList.remove('is-session-drag')
                }
              }}
              style={
                isDragOver
                  ? { borderColor: hueToColor(g.colorHue, 50, 60), background: `${hueToColor(g.colorHue, 30, 20)}33` }
                  : selectedGroupId === g.id
                    ? { borderColor: hueToColor(g.colorHue, 45, 55) }
                    : undefined
              }
            >
              <span className="dot" style={{ background: hueToColor(g.colorHue, 45, 55) }} />

              <span className="project-chip-name">{g.name}</span>

              {count > 0 && (
                <span className="count" style={{ background: hueToColor(g.colorHue, 30, 25) }}>
                  {count}
                </span>
              )}

              <button
                className="project-delete-btn"
                onClick={(e) => {
                  e.stopPropagation()
                  setPendingDeleteId(g.id)
                }}
                title="Delete project"
              >
                ×
              </button>
            </div>
          )
        })}

        <button className="create-btn" onClick={() => setSidebarMode(sidebarMode === 'project' ? 'monitor' : 'project')} title="New project">
          +
        </button>

        <div style={{ flex: 1 }} />

        <span className={`status-dot ${serverRunning ? 'running' : 'starting'}`} title={serverRunning ? 'Server running' : 'Server starting...'} />

        <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>v0.1.0</span>
      </div>

      {/* Manage panel (context menu) */}
      {managingGroup && (
        <div className="project-manage-panel" ref={panelRef}>
          <div className="project-manage-header">
            <span className="dot" style={{ background: hueToColor(managingGroup.colorHue, 45, 55) }} />
            <span className="project-manage-name">{managingGroup.name}</span>
          </div>

          <button
            className="project-manage-action"
            onClick={() => startRename(managingGroup.id, managingGroup.name)}
            title="Rename this project"
          >
            Rename
          </button>

          <div className="project-manage-colors">
            {HUE_PALETTE.map((hue) => (
              <button
                key={hue}
                className={`color-swatch ${managingGroup.colorHue === hue ? 'active' : ''}`}
                style={{ background: hueToColor(hue, 45, 55) }}
                onClick={() => setProjectColor(managingGroup.id, hue)}
                title={`Set color`}
              />
            ))}
          </div>

          <div className="project-manage-sessions">
            <span className="project-manage-label">Sessions</span>
            {tabs.length === 0 && (
              <span className="project-manage-empty">No sessions available</span>
            )}
            {tabs.map((tab) => {
              const assigned = managingGroup.sessionKeys.includes(tab.sessionKey)
              return (
                <label key={tab.sessionKey} className="project-session-toggle">
                  <input
                    type="checkbox"
                    checked={assigned}
                    onChange={() => toggleSessionInProject(tab.sessionKey, managingGroup.id)}
                  />
                  <span className="project-session-label">
                    #{tab.index} {tab.label}
                  </span>
                </label>
              )
            })}
          </div>

          <button
            className="project-manage-action danger"
            onClick={() => {
              setPendingDeleteId(managingGroup.id)
              setManagingId(null)
            }}
            title="Delete this project permanently"
          >
            Delete Project
          </button>
        </div>
      )}

      {/* Delete confirmation dialog */}
      {/* Rename modal */}
      {editingId && (
        <div className="confirm-overlay" onClick={() => setEditingId(null)}>
          <div className="confirm-dialog" onClick={(e) => e.stopPropagation()}>
            <h3>Rename project</h3>
            <input
              ref={renameInputRef}
              className="rename-modal-input"
              value={editName}
              onChange={(e) => setEditName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') handleRename(editingId)
                if (e.key === 'Escape') setEditingId(null)
              }}
              placeholder="Project name"
            />
            <div className="confirm-actions">
              <button className="cancel-btn" onClick={() => setEditingId(null)} title="Cancel rename">
                Cancel
              </button>
              <button
                className="confirm-btn"
                onClick={() => handleRename(editingId)}
                disabled={!editName.trim()}
                title="Confirm rename"
              >
                Rename
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Delete confirmation dialog */}
      {pendingGroup && (
        <div className="confirm-overlay" onClick={() => setPendingDeleteId(null)}>
          <div className="confirm-dialog" onClick={(e) => e.stopPropagation()}>
            <h3>Delete project "{pendingGroup.name}"?</h3>
            <p>
              Sessions assigned to this project will be unlinked but not removed.
            </p>
            <div className="confirm-actions">
              <button className="cancel-btn" onClick={() => setPendingDeleteId(null)} title="Cancel deletion">
                Cancel
              </button>
              <button
                className="danger-btn"
                onClick={() => {
                  deleteProject(pendingDeleteId!)
                  if (selectedGroupId === pendingDeleteId) setSelectedGroupId(null)
                  setPendingDeleteId(null)
                }}
                title="Delete project permanently"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
