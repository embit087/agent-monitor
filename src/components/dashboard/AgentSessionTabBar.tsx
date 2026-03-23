import { useState } from 'react'
import { Radar, Trash2, LayoutGrid, Columns, Rows, PanelLeft, Grid2x2, CheckSquare } from 'lucide-react'
import { usePanelStore, type DiscoveredSession } from '../../stores/panelStore.ts'
import { useProjectStore } from '../../stores/projectStore.ts'
import { useSessionTabs } from '../../hooks/useSessionTabs.ts'
import { SOURCE_COLORS } from '../../utils/colors.ts'
import { shortSessionId, truncateLabel } from '../../utils/formatting.ts'
import { hueToColor } from '../../utils/colors.ts'

export function AgentSessionTabBar() {
  const tabs = useSessionTabs()
  const selectedSessionId = usePanelStore((s) => s.selectedSessionId)
  const setSelectedSessionId = usePanelStore((s) => s.setSelectedSessionId)
  const openWinidSession = usePanelStore((s) => s.openWinidSession)
  const closeWinidSession = usePanelStore((s) => s.closeWinidSession)
  const saveSelf = usePanelStore((s) => s.saveSelf)
  const focusSelf = usePanelStore((s) => s.focusSelf)
  const requestFocusInput = usePanelStore((s) => s.requestFocusInput)
  const sidebarMode = usePanelStore((s) => s.sidebarMode)
  const setSidebarMode = usePanelStore((s) => s.setSidebarMode)
  const discoverSessions = usePanelStore((s) => s.discoverSessions)
  const registerDiscovered = usePanelStore((s) => s.registerDiscovered)
  const cleanupStaleSessions = usePanelStore((s) => s.cleanupStaleSessions)
  const arrangeWindows = usePanelStore((s) => s.arrangeWindows)
  const setDraggingSessionKey = usePanelStore((s) => s.setDraggingSessionKey)
  const matchesSelectedProject = useProjectStore((s) => s.matchesSelectedProject)
  const groupsContaining = useProjectStore((s) => s.groupsContaining)

  const [pendingClose, setPendingClose] = useState<string | null>(null)
  const [scanning, setScanning] = useState(false)
  const [discovered, setDiscovered] = useState<DiscoveredSession[] | null>(null)
  const [selected, setSelected] = useState<Set<number>>(new Set())
  const [status, setStatus] = useState<string | null>(null)
  const [showLayoutPicker, setShowLayoutPicker] = useState(false)
  const [selectMode, setSelectMode] = useState(false)
  const [selectedTabs, setSelectedTabs] = useState<Set<string>>(new Set())

  const expanded = sidebarMode === 'tab'
  const isProject = sidebarMode === 'project'

  const handleTabClick = async (sessionKey: string, active: boolean) => {
    setSelectedSessionId(active ? null : sessionKey)
    if (!active) {
      if (sidebarMode === 'monitor') {
        await saveSelf()
      }
      await openWinidSession(sessionKey)
      if (sidebarMode === 'monitor') {
        setTimeout(async () => {
          await focusSelf()
          requestFocusInput()
        }, 400)
      }
    }
  }

  const handleDiscover = async () => {
    setScanning(true)
    setSelected(new Set())
    const sessions = await discoverSessions()
    setDiscovered(sessions)
    setScanning(false)
  }

  const toggleSelect = (i: number) => {
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(i)) next.delete(i)
      else next.add(i)
      return next
    })
  }

  const toggleSelectAll = () => {
    if (!discovered) return
    if (selected.size === discovered.length) {
      setSelected(new Set())
    } else {
      setSelected(new Set(discovered.map((_, i) => i)))
    }
  }

  const handleRegisterSelected = async () => {
    if (!discovered) return
    const toRegister = discovered.filter((_, i) => selected.has(i))
    for (const s of toRegister) {
      await registerDiscovered(s)
    }
    const remaining = discovered.filter((_, i) => !selected.has(i))
    setSelected(new Set())
    if (remaining.length === 0) {
      setDiscovered(null)
    } else {
      setDiscovered(remaining)
    }
    showStatus(`Registered ${toRegister.length}`)
  }

  const handleLayout = async (layout: string) => {
    const ids = tabs.map((t) => t.sessionKey)
    const result = await arrangeWindows(ids, layout)
    showStatus(result.message)
  }

  const toggleSelectMode = () => {
    if (selectMode) {
      setSelectMode(false)
      setSelectedTabs(new Set())
    } else {
      setSelectMode(true)
    }
  }

  const toggleTabSelection = (key: string) => {
    setSelectedTabs((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }

  const selectAllTabs = () => {
    if (selectedTabs.size === tabs.length) {
      setSelectedTabs(new Set())
    } else {
      setSelectedTabs(new Set(tabs.map((t) => t.sessionKey)))
    }
  }

  const batchDelete = async () => {
    for (const key of selectedTabs) {
      await closeWinidSession(key)
    }
    if (selectedSessionId && selectedTabs.has(selectedSessionId)) {
      setSelectedSessionId(null)
    }
    setSelectedTabs(new Set())
    setSelectMode(false)
    showStatus(`Closed ${selectedTabs.size} session${selectedTabs.size > 1 ? 's' : ''}`)
  }

  const handleCleanup = async () => {
    const result = await cleanupStaleSessions()
    showStatus(result.message)
  }

  const showStatus = (msg: string) => {
    setStatus(msg)
    setTimeout(() => setStatus(null), 3000)
  }


  return (
    <>
      <div className={`session-sidebar ${expanded ? 'expanded' : ''}`}>
        {/* Mode toggle */}
        <div className="sidebar-mode-toggle">
          <button
            className={`mode-btn ${sidebarMode === 'monitor' ? 'active' : ''}`}
            onClick={() => setSidebarMode('monitor')}
            title="Monitor: switch & return to Agent Monitor"
          >
            monitor
          </button>
          <button
            className={`mode-btn ${sidebarMode === 'tab' ? 'active' : ''}`}
            onClick={() => setSidebarMode('tab')}
            title="Tab: switch to terminal and stay"
          >
            tab
          </button>
        </div>
        <button
          className={`mode-btn-full ${sidebarMode === 'project' ? 'active' : ''}`}
          onClick={() => setSidebarMode(sidebarMode === 'project' ? 'monitor' : 'project')}
          title="Project: drag agents to assign projects"
        >
          project
        </button>



        {/* Toolbar */}
        <div className="sidebar-toolbar">
          <button
            className={`sidebar-tool-btn ${scanning ? 'scanning' : ''}`}
            onClick={handleDiscover}
            disabled={scanning}
            title="Discover agents"
          >
            <Radar size={12} />
          </button>
          {tabs.length > 0 && (
            <button
              className={`sidebar-tool-btn ${selectMode ? 'active' : ''}`}
              onClick={toggleSelectMode}
              title={selectMode ? 'Exit select mode' : 'Select sessions'}
            >
              <CheckSquare size={11} />
            </button>
          )}
          {tabs.length > 0 && (
            <button className="sidebar-tool-btn danger" onClick={handleCleanup} title="Remove stale">
              <Trash2 size={11} />
            </button>
          )}
          <span className="sidebar-toolbar-spacer" />
          {tabs.length > 1 && (
            <div style={{ position: 'relative' }}>
              <button
                className={`sidebar-tool-btn ${showLayoutPicker ? 'active' : ''}`}
                onClick={() => setShowLayoutPicker(!showLayoutPicker)}
                title="Arrange windows"
              >
                <Grid2x2 size={12} />
              </button>
              {showLayoutPicker && (
                <div className="layout-picker">
                  <button className="layout-pick" onClick={() => { handleLayout('grid'); setShowLayoutPicker(false) }}>
                    <LayoutGrid size={16} /> <span>Grid</span>
                  </button>
                  <button className="layout-pick" onClick={() => { handleLayout('columns'); setShowLayoutPicker(false) }}>
                    <Columns size={16} /> <span>Columns</span>
                  </button>
                  <button className="layout-pick" onClick={() => { handleLayout('rows'); setShowLayoutPicker(false) }}>
                    <Rows size={16} /> <span>Rows</span>
                  </button>
                  <button className="layout-pick" onClick={() => { handleLayout('main-side'); setShowLayoutPicker(false) }}>
                    <PanelLeft size={16} /> <span>Main + Side</span>
                  </button>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Select mode batch bar */}
        {selectMode && (
          <div className="sidebar-batch-bar">
            <label className="sidebar-batch-select-all">
              <input
                type="checkbox"
                checked={selectedTabs.size === tabs.length && tabs.length > 0}
                onChange={selectAllTabs}
              />
              <span>All</span>
            </label>
            {selectedTabs.size > 0 && (
              <button className="sidebar-batch-delete" onClick={batchDelete}>
                <Trash2 size={10} />
                Close {selectedTabs.size}
              </button>
            )}
          </div>
        )}

        {/* Status */}
        {status && <span className="sidebar-status">{status}</span>}

        {/* Discover panel */}
        {discovered && (
          <>
          <div className="discover-backdrop" onClick={() => setDiscovered(null)} />
          <div className="discover-panel">
            <div className="discover-header">
              <span className="discover-header-title">Discover agents</span>
              <button className="discover-close-btn" onClick={() => setDiscovered(null)}>×</button>
            </div>
            {discovered.length === 0 ? (
              <span className="discover-empty">No agent sessions found</span>
            ) : (
              <>
                <div className="discover-actions">
                  <label className="discover-select-all">
                    <input
                      type="checkbox"
                      checked={selected.size === discovered.length}
                      onChange={toggleSelectAll}
                    />
                    Select all
                  </label>
                  {selected.size > 0 && (
                    <button className="discover-add-btn" onClick={handleRegisterSelected}>
                      Add {selected.size}
                    </button>
                  )}
                </div>
                <div className="discover-list">
                  {discovered.map((s, i) => (
                    <div
                      key={i}
                      className={`discover-row ${selected.has(i) ? 'selected' : ''}`}
                      onClick={() => toggleSelect(i)}
                    >
                      <input
                        type="checkbox"
                        checked={selected.has(i)}
                        onChange={() => toggleSelect(i)}
                        onClick={(e) => e.stopPropagation()}
                      />
                      <div className="discover-row-content">
                        <span className="discover-app">{s.app}</span>
                        <span className="discover-title">{s.title}</span>
                      </div>
                    </div>
                  ))}
                </div>
              </>
            )}
          </div>
          </>
        )}

        {/* Tab list */}
        <div className="sidebar-tab-list">
        {tabs.map((tab) => {
          const active = selectedSessionId === tab.sessionKey
          const dimmed = !matchesSelectedProject(tab.sessionKey)
          const projectGroups = groupsContaining(tab.sessionKey)
          const color = SOURCE_COLORS[tab.sourceKind]

          const checked = selectedTabs.has(tab.sessionKey)

          return (
            <div
              key={tab.sessionKey}
              className={`sidebar-tab ${active ? 'active' : ''} ${dimmed ? 'dimmed' : ''} ${checked ? 'checked' : ''}`}
              draggable={!selectMode || isProject}
              onDragStart={(e) => {
                if (selectMode) return
                e.dataTransfer.setData('application/x-session-key', tab.sessionKey)
                e.dataTransfer.setData('text/plain', tab.sessionKey)
                e.dataTransfer.effectAllowed = 'linkMove'
                e.currentTarget.classList.add('dragging')
                setDraggingSessionKey(tab.sessionKey)
              }}
              onDragEnd={(e) => {
                e.currentTarget.classList.remove('dragging')
                setDraggingSessionKey(null)
              }}
              onClick={() => selectMode ? toggleTabSelection(tab.sessionKey) : handleTabClick(tab.sessionKey, active)}
              style={active && !selectMode ? { borderColor: color } : undefined}
            >
              <div className="sidebar-tab-header">
                {selectMode && (
                  <input
                    type="checkbox"
                    className="sidebar-tab-checkbox"
                    checked={checked}
                    onChange={() => toggleTabSelection(tab.sessionKey)}
                    onClick={(e) => e.stopPropagation()}
                  />
                )}
                <span className="sidebar-tab-index" style={{ color }}>
                  #{tab.index}
                </span>
                <span className="sidebar-tab-label">{truncateLabel(tab.label, selectMode ? 10 : 14)}</span>
              </div>
              <div className="sidebar-tab-meta">
                {!selectMode && <span className="tab-count">{tab.count}</span>}
                <span className="sidebar-tab-id">{shortSessionId(tab.sessionKey)}</span>
                {projectGroups.length > 0 && (
                  <span className="project-dots">
                    {projectGroups.slice(0, 3).map((g) => (
                      <span
                        key={g.id}
                        className="pdot"
                        style={{ background: hueToColor(g.colorHue) }}
                      />
                    ))}
                  </span>
                )}
              </div>
              <button
                className="tab-close-btn"
                onClick={(e) => {
                  e.stopPropagation()
                  setPendingClose(tab.sessionKey)
                }}
              >
                ×
              </button>
            </div>
          )
        })}

        {tabs.length === 0 && (
          <div className="sidebar-empty">No sessions</div>
        )}
        </div>
      </div>

      {pendingClose && (
        <div className="confirm-overlay" onClick={() => setPendingClose(null)}>
          <div className="confirm-dialog" onClick={(e) => e.stopPropagation()}>
            <h3>Close this session?</h3>
            <p>
              All notifications for this session will be removed and its WINID unregistered.
            </p>
            <div className="confirm-actions">
              <button className="cancel-btn" onClick={() => setPendingClose(null)}>
                Cancel
              </button>
              <button
                className="danger-btn"
                onClick={() => {
                  closeWinidSession(pendingClose)
                  if (selectedSessionId === pendingClose) setSelectedSessionId(null)
                  setPendingClose(null)
                }}
              >
                Close Session
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
