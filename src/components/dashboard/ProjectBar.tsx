import { useState, useRef, useEffect } from 'react'
import { usePanelStore } from '../../stores/panelStore.ts'
import { useProjectStore } from '../../stores/projectStore.ts'
import { useSessionTabs } from '../../hooks/useSessionTabs.ts'
import { hueToColor, HUE_PALETTE } from '../../utils/colors.ts'
import { Tooltip } from './Tooltip.tsx'

export function ProjectBar() {
  const groups = useProjectStore((s) => s.groups)
  const selectedGroupId = useProjectStore((s) => s.selectedGroupId)
  const setSelectedGroupId = useProjectStore((s) => s.setSelectedGroupId)
  const isCreating = useProjectStore((s) => s.isCreating)
  const setIsCreating = useProjectStore((s) => s.setIsCreating)
  const createProject = useProjectStore((s) => s.createProject)
  const deleteProject = useProjectStore((s) => s.deleteProject)
  const renameProject = useProjectStore((s) => s.renameProject)
  const setProjectColor = useProjectStore((s) => s.setProjectColor)
  const toggleSessionInProject = useProjectStore((s) => s.toggleSessionInProject)
  const serverRunning = usePanelStore((s) => s.serverRunning)
  const notices = usePanelStore((s) => s.notices)
  const clearNotices = usePanelStore((s) => s.clearNotices)
  const hideResponses = usePanelStore((s) => s.hideResponses)
  const toggleHideResponses = usePanelStore((s) => s.toggleHideResponses)
  const tabs = useSessionTabs()

  const [newName, setNewName] = useState('')
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editName, setEditName] = useState('')
  const [pendingDeleteId, setPendingDeleteId] = useState<string | null>(null)
  const [dragOver, setDragOver] = useState<string | null>(null)
  const [managingId, setManagingId] = useState<string | null>(null)
  const renameRef = useRef<HTMLInputElement>(null)
  const panelRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (editingId && renameRef.current) renameRef.current.focus()
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

  const handleCreate = () => {
    if (newName.trim()) {
      createProject(newName.trim())
      setNewName('')
    }
    setIsCreating(false)
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

  // Drag-and-drop handlers
  const handleDragEnter = (e: React.DragEvent, groupId: string) => {
    if (e.dataTransfer.types.includes('application/x-session-key')) {
      e.preventDefault()
      e.stopPropagation()
      setDragOver(groupId)
    }
  }

  const handleDragOver = (e: React.DragEvent, groupId: string) => {
    if (e.dataTransfer.types.includes('application/x-session-key')) {
      e.preventDefault()
      e.stopPropagation()
      e.dataTransfer.dropEffect = 'link'
      setDragOver(groupId)
    }
  }

  const handleDragLeave = (e: React.DragEvent) => {
    // Only clear if leaving the chip itself, not a child
    if (e.currentTarget.contains(e.relatedTarget as Node)) return
    setDragOver(null)
  }

  const handleDrop = (e: React.DragEvent, groupId: string) => {
    e.preventDefault()
    e.stopPropagation()
    setDragOver(null)
    const sessionKey = e.dataTransfer.getData('application/x-session-key')
      || e.dataTransfer.getData('text/plain')
    if (sessionKey) {
      toggleSessionInProject(sessionKey, groupId)
    }
  }

  const pendingGroup = pendingDeleteId ? groups.find((g) => g.id === pendingDeleteId) : null
  const managingGroup = managingId ? groups.find((g) => g.id === managingId) : null

  return (
    <>
      <div className="project-bar">
        <div
          className={`project-chip ${!selectedGroupId ? 'active' : ''}`}
          onClick={() => setSelectedGroupId(null)}
        >
          All
        </div>

        {groups.map((g) => {
          const count = sessionCountForGroup(g)
          const isEditing = editingId === g.id
          const isDragOver = dragOver === g.id

          return (
            <div
              key={g.id}
              className={`project-chip ${selectedGroupId === g.id ? 'active' : ''} ${isDragOver ? 'drag-over' : ''}`}
              onClick={() => {
                if (!isEditing) setSelectedGroupId(selectedGroupId === g.id ? null : g.id)
              }}
              onDoubleClick={(e) => {
                e.stopPropagation()
                startRename(g.id, g.name)
              }}
              onContextMenu={(e) => {
                e.preventDefault()
                setManagingId(managingId === g.id ? null : g.id)
              }}
              onDragEnter={(e) => handleDragEnter(e, g.id)}
              onDragOver={(e) => handleDragOver(e, g.id)}
              onDragLeave={handleDragLeave}
              onDrop={(e) => handleDrop(e, g.id)}
              style={
                isDragOver
                  ? { borderColor: hueToColor(g.colorHue, 50, 60), background: `${hueToColor(g.colorHue, 30, 20)}33` }
                  : selectedGroupId === g.id
                    ? { borderColor: hueToColor(g.colorHue, 45, 55) }
                    : undefined
              }
            >
              <span className="dot" style={{ background: hueToColor(g.colorHue, 45, 55) }} />

              {isEditing ? (
                <input
                  ref={renameRef}
                  className="project-rename-input"
                  value={editName}
                  onChange={(e) => setEditName(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') handleRename(g.id)
                    if (e.key === 'Escape') setEditingId(null)
                    e.stopPropagation()
                  }}
                  onClick={(e) => e.stopPropagation()}
                  onBlur={() => handleRename(g.id)}
                />
              ) : (
                <span className="project-chip-name">{g.name}</span>
              )}

              {count > 0 && !isEditing && (
                <span className="count" style={{ background: hueToColor(g.colorHue, 30, 25) }}>
                  {count}
                </span>
              )}

              {!isEditing && (
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
              )}
            </div>
          )
        })}

        {isCreating ? (
          <div className="project-create-input">
            <input
              autoFocus
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') handleCreate()
                if (e.key === 'Escape') { setIsCreating(false); setNewName('') }
              }}
              placeholder="Project name"
            />
            <button className="icon-btn" onClick={handleCreate} title="Create">
              +
            </button>
          </div>
        ) : (
          <button className="create-btn" onClick={() => setIsCreating(true)} title="New project">
            +
          </button>
        )}

        <div style={{ flex: 1 }} />

        <span className={`status-dot ${serverRunning ? 'running' : 'starting'}`} />

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
          >
            Delete Project
          </button>
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
              <button className="cancel-btn" onClick={() => setPendingDeleteId(null)}>
                Cancel
              </button>
              <button
                className="danger-btn"
                onClick={() => {
                  deleteProject(pendingDeleteId!)
                  if (selectedGroupId === pendingDeleteId) setSelectedGroupId(null)
                  setPendingDeleteId(null)
                }}
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
