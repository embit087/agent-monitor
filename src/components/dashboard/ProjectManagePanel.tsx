import { useState, useEffect, useRef } from 'react'
import { Archive, RotateCcw, Trash2, FolderOpen } from 'lucide-react'
import { usePanelStore } from '../../stores/panelStore.ts'
import { useProjectStore } from '../../stores/projectStore.ts'
import { useSessionTabs } from '../../hooks/useSessionTabs.ts'
import { hueToColor, SOURCE_COLORS, HUE_PALETTE } from '../../utils/colors.ts'
import { shortSessionId } from '../../utils/formatting.ts'
import type { ProjectStatus } from '../../types/project.ts'

export function ProjectManagePanel() {
  const groups = useProjectStore((s) => s.groups)
  const toggleSessionInProject = useProjectStore((s) => s.toggleSessionInProject)
  const moveSessionToProject = useProjectStore((s) => s.moveSessionToProject)
  const createProject = useProjectStore((s) => s.createProject)
  const deleteProject = useProjectStore((s) => s.deleteProject)
  const renameProject = useProjectStore((s) => s.renameProject)
  const setProjectColor = useProjectStore((s) => s.setProjectColor)
  const updateDescription = useProjectStore((s) => s.updateDescription)
  const updateDirectory = useProjectStore((s) => s.updateDirectory)
  const setStatus = useProjectStore((s) => s.setStatus)
  const draggingSessionKey = usePanelStore((s) => s.draggingSessionKey)
  const setDraggingSessionKey = usePanelStore((s) => s.setDraggingSessionKey)
  const tabs = useSessionTabs()

  const [dragOverId, setDragOverId] = useState<string | null>(null)
  const [newName, setNewName] = useState('')
  const wasDraggingRef = useRef(false)
  const [editingDescId, setEditingDescId] = useState<string | null>(null)
  const [descDraft, setDescDraft] = useState('')
  const [editingNameId, setEditingNameId] = useState<string | null>(null)
  const [nameDraft, setNameDraft] = useState('')
  const [pendingDeleteId, setPendingDeleteId] = useState<string | null>(null)
  const [colorPickerId, setColorPickerId] = useState<string | null>(null)
  const [showArchived, setShowArchived] = useState(false)
  const [editingDirId, setEditingDirId] = useState<string | null>(null)
  const [dirDraft, setDirDraft] = useState('')

  const activeGroups = groups.filter((g) => g.status === 'active')
  const archivedGroups = groups.filter((g) => g.status === 'archived')
  const allAssigned = new Set(groups.flatMap((g) => g.sessionKeys))
  const unassigned = tabs.filter((t) => !allAssigned.has(t.sessionKey))

  // Track which session is being dragged (from sidebar or from member)
  const activeDragKey = draggingSessionKey

  // Clear hover when drag ends
  useEffect(() => {
    if (!activeDragKey) setDragOverId(null)
  }, [activeDragKey])

  const handleZoneMouseUp = (groupId: string) => {
    if (!activeDragKey) return
    if (groupId === '__unassigned__') {
      moveSessionToProject(activeDragKey, null)
    } else {
      const target = groups.find((g) => g.id === groupId)
      if (target?.sessionKeys.includes(activeDragKey)) return
      moveSessionToProject(activeDragKey, groupId)
    }
    setDragOverId(null)
    setDraggingSessionKey(null)
    document.body.classList.remove('is-session-drag')
  }

  const startMemberDrag = (e: React.MouseEvent, sessionKey: string) => {
    if (e.button !== 0) return
    const startX = e.clientX
    const startY = e.clientY
    let dragging = false
    wasDraggingRef.current = false

    const onMove = (ev: MouseEvent) => {
      if (!dragging && Math.abs(ev.clientX - startX) + Math.abs(ev.clientY - startY) > 5) {
        dragging = true
        wasDraggingRef.current = true
        setDraggingSessionKey(sessionKey)
        document.body.classList.add('is-session-drag')
      }
    }

    const onUp = () => {
      document.removeEventListener('mousemove', onMove)
      document.removeEventListener('mouseup', onUp)
      if (dragging) {
        requestAnimationFrame(() => {
          setDraggingSessionKey(null)
          document.body.classList.remove('is-session-drag')
        })
      }
    }

    document.addEventListener('mousemove', onMove)
    document.addEventListener('mouseup', onUp)
  }

  const handleCreate = () => {
    if (newName.trim()) {
      createProject(newName.trim())
      setNewName('')
    }
  }

  const startEditDesc = (id: string, current: string | null) => {
    setEditingDescId(id)
    setDescDraft(current || '')
  }

  const saveDesc = (id: string) => {
    updateDescription(id, descDraft)
    setEditingDescId(null)
  }

  const startEditDir = (id: string, current: string | null) => {
    setEditingDirId(id)
    setDirDraft(current || '')
  }

  const saveDir = (id: string) => {
    updateDirectory(id, dirDraft)
    setEditingDirId(null)
  }

  const startEditName = (id: string, current: string) => {
    setEditingNameId(id)
    setNameDraft(current)
  }

  const saveName = (id: string) => {
    if (nameDraft.trim()) {
      renameProject(id, nameDraft.trim())
    }
    setEditingNameId(null)
  }

  const pendingGroup = pendingDeleteId ? groups.find((g) => g.id === pendingDeleteId) : null

  const renderZone = (g: typeof groups[0]) => {
    const members = tabs.filter((t) => g.sessionKeys.includes(t.sessionKey))
    const isOver = dragOverId === g.id
    const color = hueToColor(g.colorHue, 45, 55)
    const isArchived = g.status === 'archived'

    return (
      <div
        key={g.id}
        className={`project-zone ${isOver ? 'drag-over' : ''} ${isArchived ? 'archived' : ''}`}
        data-drop-project-id={g.id}
        onMouseEnter={() => { if (activeDragKey) setDragOverId(g.id) }}
        onMouseLeave={() => { if (activeDragKey) setDragOverId(null) }}
        onMouseUp={() => handleZoneMouseUp(g.id)}
        style={{ borderColor: isOver ? color : undefined }}
      >
        {/* Header */}
        <div className="project-zone-header">
          <span
            className="dot project-zone-color-trigger"
            style={{ background: color }}
            onClick={(e) => {
              e.stopPropagation()
              setColorPickerId(colorPickerId === g.id ? null : g.id)
            }}
            title="Change color"
          />
          <span
            className="project-zone-name"
            onDoubleClick={() => startEditName(g.id, g.name)}
            title="Double-click to rename"
          >
            {g.name}
          </span>
          {isArchived && <span className="project-zone-status-badge archived">archived</span>}
          <span className="project-zone-count">{members.length} agents</span>
        </div>

        {/* Color picker (shown on dot click) */}
        {colorPickerId === g.id && (
          <div className="project-zone-colors">
            {HUE_PALETTE.map((hue) => (
              <button
                key={hue}
                className={`color-dot ${g.colorHue === hue ? 'active' : ''}`}
                style={{ background: hueToColor(hue, 45, 55) }}
                onClick={() => {
                  setProjectColor(g.id, hue)
                  setColorPickerId(null)
                }}
                title="Select this color"
              />
            ))}
          </div>
        )}

        {/* Description */}
        <div className="project-zone-desc">
          {editingDescId === g.id ? (
            <textarea
              className="project-zone-desc-input"
              value={descDraft}
              onChange={(e) => setDescDraft(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); saveDesc(g.id) }
                if (e.key === 'Escape') setEditingDescId(null)
              }}
              onBlur={() => saveDesc(g.id)}
              placeholder="Add a description..."
              rows={2}
              autoFocus
            />
          ) : (
            <span
              className={`project-zone-desc-text ${!g.description ? 'empty' : ''}`}
              onClick={() => startEditDesc(g.id, g.description)}
              title="Click to edit description"
            >
              {g.description || 'Add description...'}
            </span>
          )}
        </div>

        {/* Directory */}
        <div className="project-zone-dir">
          <FolderOpen size={11} className="project-zone-dir-icon" />
          {editingDirId === g.id ? (
            <input
              className="project-zone-dir-input"
              value={dirDraft}
              onChange={(e) => setDirDraft(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') { e.preventDefault(); saveDir(g.id) }
                if (e.key === 'Escape') setEditingDirId(null)
              }}
              onBlur={() => saveDir(g.id)}
              placeholder="/path/to/project"
              autoFocus
            />
          ) : (
            <span
              className={`project-zone-dir-text ${!g.directory ? 'empty' : ''}`}
              onClick={() => startEditDir(g.id, g.directory)}
              title="Click to set working directory for new agents"
            >
              {g.directory || 'Set directory...'}
            </span>
          )}
        </div>

        {/* Members */}
        {members.length > 0 ? (
          <div className="project-zone-members">
            {members.map((t) => (
              <div
                key={t.sessionKey}
                className={`project-zone-member ${activeDragKey === t.sessionKey ? 'dragging' : ''}`}
                onMouseDown={(e) => startMemberDrag(e, t.sessionKey)}
              >
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

        {/* Actions */}
        <div className="project-zone-actions">
          <button
            className="project-zone-action-btn"
            onClick={() => setStatus(g.id, isArchived ? 'active' : 'archived')}
            title={isArchived ? 'Restore project' : 'Archive project'}
          >
            {isArchived ? <RotateCcw size={11} /> : <Archive size={11} />}
            <span>{isArchived ? 'Restore' : 'Archive'}</span>
          </button>
          <button
            className="project-zone-action-btn danger"
            onClick={() => setPendingDeleteId(g.id)}
            title="Delete project"
          >
            <Trash2 size={11} />
            <span>Delete</span>
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="project-manage-view">
      <div className="project-manage-view-header">
        <span className="project-manage-view-title">Projects</span>
        <span className="project-manage-view-subtitle">Drag agents between projects to assign</span>
      </div>

      <div className="project-manage-view-list">
        {activeGroups.map(renderZone)}

        {/* Unassigned */}
        <div
          className={`project-zone unassigned ${dragOverId === '__unassigned__' ? 'drag-over' : ''}`}
          data-drop-project-id="__unassigned__"
          onMouseEnter={() => { if (activeDragKey) setDragOverId('__unassigned__') }}
          onMouseLeave={() => { if (activeDragKey) setDragOverId(null) }}
          onMouseUp={() => handleZoneMouseUp('__unassigned__')}
        >
          <div className="project-zone-header">
            <span className="project-zone-name">Unassigned</span>
            <span className="project-zone-count">{unassigned.length} agents</span>
          </div>
          {unassigned.length > 0 ? (
            <div className="project-zone-members">
              {unassigned.map((t) => (
                <div
                  key={t.sessionKey}
                  className={`project-zone-member ${activeDragKey === t.sessionKey ? 'dragging' : ''}`}
                  onMouseDown={(e) => startMemberDrag(e, t.sessionKey)}
                >
                  <span className="project-zone-member-dot" style={{ background: SOURCE_COLORS[t.sourceKind] }} />
                  <span className="project-zone-member-label">#{t.index} {t.label}</span>
                  <span className="project-zone-member-id">{shortSessionId(t.sessionKey)}</span>
                </div>
              ))}
            </div>
          ) : (
            <span className="project-zone-empty">Drop agents here to unassign</span>
          )}
        </div>

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
            title="Create new project"
          >
            +
          </button>
        </div>

        {/* Archived section */}
        {archivedGroups.length > 0 && (
          <>
            <button
              className="project-zone-archive-toggle"
              onClick={() => setShowArchived(!showArchived)}
              title={showArchived ? 'Hide archived projects' : 'Show archived projects'}
            >
              {showArchived ? 'Hide' : 'Show'} archived ({archivedGroups.length})
            </button>
            {showArchived && archivedGroups.map(renderZone)}
          </>
        )}
      </div>

      {/* Rename modal */}
      {editingNameId && (
        <div className="confirm-overlay" onClick={() => setEditingNameId(null)}>
          <div className="confirm-dialog" onClick={(e) => e.stopPropagation()}>
            <h3>Rename project</h3>
            <input
              className="rename-modal-input"
              value={nameDraft}
              onChange={(e) => setNameDraft(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') saveName(editingNameId)
                if (e.key === 'Escape') setEditingNameId(null)
              }}
              placeholder="Project name"
              autoFocus
            />
            <div className="confirm-actions">
              <button className="cancel-btn" onClick={() => setEditingNameId(null)} title="Cancel rename">Cancel</button>
              <button
                className="confirm-btn"
                onClick={() => saveName(editingNameId)}
                disabled={!nameDraft.trim()}
                title="Confirm rename"
              >
                Rename
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Delete confirmation */}
      {pendingGroup && (
        <div className="confirm-overlay" onClick={() => setPendingDeleteId(null)}>
          <div className="confirm-dialog" onClick={(e) => e.stopPropagation()}>
            <h3>Delete project "{pendingGroup.name}"?</h3>
            <p>Sessions assigned to this project will be unlinked but not removed.</p>
            <div className="confirm-actions">
              <button className="cancel-btn" onClick={() => setPendingDeleteId(null)} title="Cancel deletion">Cancel</button>
              <button className="danger-btn" onClick={() => {
                deleteProject(pendingDeleteId!)
                setPendingDeleteId(null)
              }} title="Delete project permanently">Delete</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
