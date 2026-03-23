import { useState, useRef, useEffect, useCallback } from 'react'
import { Radar, Trash2, LayoutGrid, Columns, Rows, PanelLeft, Grid2x2, CheckSquare, Plus, Bot, MousePointer, Zap, Check, X, Terminal, Ghost, Settings } from 'lucide-react'
import { invoke } from '@tauri-apps/api/core'
import { usePanelStore, type DiscoveredSession, type OrphanedSession } from '../../stores/panelStore.ts'
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
  const showLayoutPreview = usePanelStore((s) => s.showLayoutPreview)
  const hideLayoutPreview = usePanelStore((s) => s.hideLayoutPreview)
  const confirmLayout = usePanelStore((s) => s.confirmLayout)
  const overlayActive = usePanelStore((s) => s.overlayActive)
  const previewLayout = usePanelStore((s) => s.previewLayout)
  const monitorSlotPosition = usePanelStore((s) => s.monitorSlotPosition)
  const setMonitorSlotPosition = usePanelStore((s) => s.setMonitorSlotPosition)
  const draggingSessionKey = usePanelStore((s) => s.draggingSessionKey)
  const setDraggingSessionKey = usePanelStore((s) => s.setDraggingSessionKey)
  const selectedGroupId = useProjectStore((s) => s.selectedGroupId)
  const matchesSelectedProject = useProjectStore((s) => s.matchesSelectedProject)
  const groupsContaining = useProjectStore((s) => s.groupsContaining)
  const selectedProjectDirectory = useProjectStore((s) => s.selectedProjectDirectory)
  const moveSessionToProject = useProjectStore((s) => s.moveSessionToProject)

  const [pendingClose, setPendingClose] = useState<string | null>(null)
  const [scanning, setScanning] = useState(false)
  const [discovered, setDiscovered] = useState<DiscoveredSession[] | null>(null)
  const [orphaned, setOrphaned] = useState<OrphanedSession[]>([])
  const [selected, setSelected] = useState<Set<number>>(new Set())
  const [status, setStatus] = useState<string | null>(null)
  const [selectMode, setSelectMode] = useState(false)
  const [selectedTabs, setSelectedTabs] = useState<Set<string>>(new Set())
  const [showLauncher, setShowLauncher] = useState(false)
  const [autoMode, setAutoMode] = useState(false)
  const [terminalApp, setTerminalApp] = useState<'terminal' | 'ghostty'>('terminal')
  const [layoutSelectMode, setLayoutSelectMode] = useState(false)
  const [layoutSelectedTabs, setLayoutSelectedTabs] = useState<Set<string>>(new Set())
  const launchBtnRef = useRef<HTMLButtonElement>(null)
  const wasDraggingRef = useRef(false)

  const expanded = sidebarMode === 'tab'
  const isProject = sidebarMode === 'project'

  const showHighlightBorder = usePanelStore((s) => s.showHighlightBorder)

  const handleTabClick = async (sessionKey: string, active: boolean, color?: string) => {
    setSelectedSessionId(active ? null : sessionKey)
    if (!active) {
      if (sidebarMode === 'monitor') {
        await saveSelf()
      }
      // Fire highlight and window switch in parallel for responsiveness
      const highlightPromise = (sidebarMode === 'tab' && color)
        ? showHighlightBorder(sessionKey, color)
        : Promise.resolve()
      await Promise.all([openWinidSession(sessionKey), highlightPromise])
      if (sidebarMode === 'monitor') {
        setTimeout(async () => {
          await focusSelf()
          requestFocusInput()
        }, 400)
      }
    } else if (sidebarMode === 'tab') {
      // Clicking active tab — toggle highlight off
      showHighlightBorder(sessionKey, '')
    }
  }

  const handleDiscover = async () => {
    setScanning(true)
    setSelected(new Set())
    const result = await discoverSessions()
    setDiscovered(result.sessions)
    setOrphaned(result.orphaned)
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
    const addable = discovered.map((s, i) => ({ s, i })).filter(({ s }) => !s.alreadyAdded)
    if (selected.size === addable.length) {
      setSelected(new Set())
    } else {
      setSelected(new Set(addable.map(({ i }) => i)))
    }
  }

  const handleRegisterSelected = async () => {
    if (!discovered) return
    const toRegister = discovered.filter((s, i) => selected.has(i) && !s.alreadyAdded)
    for (const s of toRegister) {
      await registerDiscovered(s)
    }
    // Mark registered ones as already added
    setDiscovered((prev) =>
      prev?.map((s, i) => selected.has(i) ? { ...s, alreadyAdded: true } : s) ?? null
    )
    setSelected(new Set())
    showStatus(`Registered ${toRegister.length}`)
  }

  // --- Layout select mode ---
  const enterLayoutSelectMode = () => {
    // Pre-select all tabs
    setLayoutSelectedTabs(new Set(tabs.map((t) => t.sessionKey)))
    setLayoutSelectMode(true)
    // Exit batch-delete select mode if active
    if (selectMode) {
      setSelectMode(false)
      setSelectedTabs(new Set())
    }
  }

  const exitLayoutSelectMode = async () => {
    await hideLayoutPreview()
    setLayoutSelectMode(false)
    setLayoutSelectedTabs(new Set())
  }

  const toggleLayoutTab = (key: string) => {
    setLayoutSelectedTabs((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }

  const toggleLayoutSelectAll = () => {
    if (layoutSelectedTabs.size === tabs.length) {
      setLayoutSelectedTabs(new Set())
    } else {
      setLayoutSelectedTabs(new Set(tabs.map((t) => t.sessionKey)))
    }
  }

  const handleLayout = async (layout: string) => {
    const ids = tabs
      .filter((t) => layoutSelectedTabs.has(t.sessionKey))
      .map((t) => t.sessionKey)
    if (ids.length < 1) return
    await showLayoutPreview(ids, layout)
  }

  const handleConfirmLayout = async () => {
    const result = await confirmLayout()
    showStatus(result.message)
    setLayoutSelectMode(false)
    setLayoutSelectedTabs(new Set())
  }

  const handleCancelLayout = async () => {
    await exitLayoutSelectMode()
  }

  // Escape key cancels layout mode or preview
  useEffect(() => {
    if (!layoutSelectMode) return
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        handleCancelLayout()
      }
    }
    window.addEventListener('keydown', handleEsc)
    return () => window.removeEventListener('keydown', handleEsc)
  }, [layoutSelectMode])

  // Re-trigger preview when monitor slot position changes
  useEffect(() => {
    if (layoutSelectMode && previewLayout) {
      handleLayout(previewLayout)
    }
  }, [monitorSlotPosition])

  const fetchNotices = usePanelStore((s) => s.fetchNotices)

  const handleLaunch = async (kind: string) => {
    try {
      let monitorSlot: number | null = null
      let excludeSelf: boolean | null = null
      if (monitorSlotPosition === 'first') monitorSlot = 0
      else if (monitorSlotPosition === 'last') monitorSlot = tabs.length + 1
      else if (monitorSlotPosition === 'fixed') excludeSelf = true
      const cwd = selectedProjectDirectory() || undefined
      const sessionId = await invoke<string>('init_new_terminal', { kind, autoMode: autoMode, terminalApp: terminalApp, monitorSlot, excludeSelf, cwd })
      await fetchNotices()
      // Auto-assign to selected project
      if (selectedGroupId) {
        await moveSessionToProject(sessionId, selectedGroupId)
      }
      const appLabel = terminalApp === 'ghostty' ? 'Ghostty' : 'Terminal'
      showStatus(`Launched ${kind} (${appLabel})`)
      setShowLauncher(false)
    } catch (e) {
      showStatus(`Failed: ${e}`)
    }
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
          <button
            ref={launchBtnRef}
            className={`sidebar-tool-btn ${showLauncher ? 'active' : ''}`}
            onClick={() => setShowLauncher(!showLauncher)}
            title="Launch new agent"
          >
            <Plus size={12} />
          </button>
          <FixedDropdown show={showLauncher} onClose={() => setShowLauncher(false)} triggerRef={launchBtnRef}>
            <div className="launcher-toggles">
              <label className="launcher-auto-toggle" title="Auto mode: skip permissions (Claude) / force (Cursor)">
                <Zap size={10} />
                <span>Auto</span>
                <input
                  type="checkbox"
                  checked={autoMode}
                  onChange={() => setAutoMode(!autoMode)}
                />
              </label>
              <div className="launcher-app-toggle">
                <button
                  className={`launcher-app-btn ${terminalApp === 'terminal' ? 'active' : ''}`}
                  onClick={() => setTerminalApp('terminal')}
                  title="Use default Terminal.app"
                >
                  <Terminal size={10} />
                </button>
                <button
                  className={`launcher-app-btn ${terminalApp === 'ghostty' ? 'active' : ''}`}
                  onClick={() => setTerminalApp('ghostty')}
                  title="Use Ghostty (hidden title bar)"
                >
                  <Ghost size={10} />
                </button>
              </div>
            </div>
            {selectedProjectDirectory() && (
              <div className="launcher-cwd" title={`Working directory: ${selectedProjectDirectory()}`}>
                <span className="launcher-cwd-label">{selectedProjectDirectory()}</span>
              </div>
            )}
            <button className="layout-pick" onClick={() => handleLaunch('claude')} title="Launch Claude Code session">
              <Bot size={14} />
              <span>{autoMode ? 'Claude Code (auto)' : 'Claude Code'}</span>
            </button>
            <button className="layout-pick" onClick={() => handleLaunch('cursor')} title="Launch Cursor Agent session">
              <MousePointer size={14} />
              <span>{autoMode ? 'Cursor Agent (force)' : 'Cursor Agent'}</span>
            </button>
            <button className="layout-pick" onClick={() => handleLaunch('plain')} title="Launch plain terminal">
              <Plus size={14} />
              <span>Plain Terminal</span>
            </button>
          </FixedDropdown>
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
            <button
              className={`sidebar-tool-btn ${layoutSelectMode ? 'active' : ''}`}
              onClick={() => layoutSelectMode ? exitLayoutSelectMode() : enterLayoutSelectMode()}
              title="Arrange windows"
            >
              <Grid2x2 size={12} />
            </button>
          )}
        </div>

        {/* Select mode batch bar */}
        {selectMode && (
          <div className="sidebar-batch-bar">
            <label className="sidebar-batch-select-all" title="Select all sessions">
              <input
                type="checkbox"
                checked={selectedTabs.size === tabs.length && tabs.length > 0}
                onChange={selectAllTabs}
              />
              <span>All</span>
            </label>
            {selectedTabs.size > 0 && (
              <button className="sidebar-batch-delete" onClick={batchDelete} title="Close selected sessions">
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
              <button className="discover-close-btn" onClick={() => setDiscovered(null)} title="Close discover panel">×</button>
            </div>
            {discovered.length === 0 && orphaned.length === 0 ? (
              <span className="discover-empty">No agent sessions found</span>
            ) : (
              <>
                {discovered.length > 0 && (
                  <>
                    <div className="discover-actions">
                      <label className="discover-select-all" title="Select all discovered sessions">
                        <input
                          type="checkbox"
                          checked={selected.size === discovered.filter((s) => !s.alreadyAdded).length && discovered.some((s) => !s.alreadyAdded)}
                          onChange={toggleSelectAll}
                        />
                        Select all
                      </label>
                      {selected.size > 0 && (
                        <button className="discover-add-btn" onClick={handleRegisterSelected} title="Register selected sessions for monitoring">
                          Add {selected.size}
                        </button>
                      )}
                    </div>
                    <div className="discover-list">
                      {discovered.map((s, i) => (
                        <div
                          key={i}
                          className={`discover-row ${selected.has(i) ? 'selected' : ''} ${s.alreadyAdded ? 'added' : ''}`}
                          onClick={() => !s.alreadyAdded && toggleSelect(i)}
                        >
                          {s.alreadyAdded ? (
                            <span className="discover-added-badge">added</span>
                          ) : (
                            <input
                              type="checkbox"
                              checked={selected.has(i)}
                              onChange={() => toggleSelect(i)}
                              onClick={(e) => e.stopPropagation()}
                            />
                          )}
                          <span className="discover-row-title">{s.title}</span>
                        </div>
                      ))}
                    </div>
                  </>
                )}
                {orphaned.length > 0 && (
                  <div className="discover-orphaned">
                    <div className="discover-orphaned-header">
                      <span className="discover-orphaned-title">No terminal found</span>
                      <button
                        className="discover-orphaned-remove-all"
                        onClick={async () => {
                          for (const o of orphaned) {
                            await closeWinidSession(o.key)
                          }
                          setOrphaned([])
                          showStatus(`Removed ${orphaned.length} orphaned`)
                        }}
                        title="Remove all orphaned sessions"
                      >
                        Remove all
                      </button>
                    </div>
                    <div className="discover-list">
                      {orphaned.map((o) => (
                        <div key={o.key} className="discover-row orphaned">
                          <span className="discover-row-title">{o.title}</span>
                          <button
                            className="discover-orphaned-remove"
                            onClick={async (e) => {
                              e.stopPropagation()
                              await closeWinidSession(o.key)
                              setOrphaned((prev) => prev.filter((x) => x.key !== o.key))
                              showStatus('Removed orphaned session')
                            }}
                            title="Remove this orphaned session"
                          >
                            <Trash2 size={10} />
                          </button>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
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
              className={`sidebar-tab ${active ? 'active' : ''} ${dimmed ? 'dimmed' : ''} ${checked ? 'checked' : ''} ${draggingSessionKey === tab.sessionKey ? 'dragging' : ''}`}
              onMouseDown={(e) => {
                if (selectMode || e.button !== 0) return
                const startX = e.clientX
                const startY = e.clientY
                const key = tab.sessionKey
                let dragging = false
                wasDraggingRef.current = false

                const onMove = (ev: MouseEvent) => {
                  if (!dragging && Math.abs(ev.clientX - startX) + Math.abs(ev.clientY - startY) > 5) {
                    dragging = true
                    wasDraggingRef.current = true
                    setDraggingSessionKey(key)
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
              }}
              onClick={() => {
                if (wasDraggingRef.current) { wasDraggingRef.current = false; return }
                selectMode ? toggleTabSelection(tab.sessionKey) : handleTabClick(tab.sessionKey, active, color)
              }}
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
                {!selectMode && (
                  <span className="tab-count">
                    {tab.msgCount > 0 && <span className="tab-count-msg">{tab.msgCount}</span>}
                    {tab.toolCount > 0 && <span className="tab-count-tool">{tab.toolCount}</span>}
                  </span>
                )}
                <span className="sidebar-tab-id">{shortSessionId(tab.sessionKey)}</span>
                {projectGroups.length > 0 && (
                  <span className="project-labels">
                    {projectGroups.slice(0, 2).map((g) => (
                      <span
                        key={g.id}
                        className="project-label"
                        style={{ background: `${hueToColor(g.colorHue)}22`, color: hueToColor(g.colorHue) }}
                      >
                        <span className="pdot" style={{ background: hueToColor(g.colorHue) }} />
                        {g.name}
                      </span>
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
                title="Close session"
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

        {/* Settings */}
        <button
          className={`sidebar-settings-btn ${sidebarMode === 'settings' ? 'active' : ''}`}
          onClick={() => setSidebarMode(sidebarMode === 'settings' ? 'monitor' : 'settings')}
          title="Settings"
        >
          <Settings size={12} />
        </button>
      </div>

      {pendingClose && (
        <div className="confirm-overlay" onClick={() => setPendingClose(null)}>
          <div className="confirm-dialog" onClick={(e) => e.stopPropagation()}>
            <h3>Close this session?</h3>
            <p>
              All notifications for this session will be removed and its WINID unregistered.
            </p>
            <div className="confirm-actions">
              <button className="cancel-btn" onClick={() => setPendingClose(null)} title="Cancel and keep session">
                Cancel
              </button>
              <button
                className="danger-btn"
                onClick={() => {
                  closeWinidSession(pendingClose)
                  if (selectedSessionId === pendingClose) setSelectedSessionId(null)
                  setPendingClose(null)
                }}
                title="Close session and remove notifications"
              >
                Close Session
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Layout arrange modal */}
      {layoutSelectMode && (
        <div className="confirm-overlay" onClick={() => exitLayoutSelectMode()}>
          <div className="layout-modal" onClick={(e) => e.stopPropagation()}>
            <div className="layout-modal-header">
              <h3>Arrange Windows</h3>
              <button className="layout-modal-close" onClick={() => exitLayoutSelectMode()} title="Close layout picker">
                <X size={14} />
              </button>
            </div>

            {/* Session checklist */}
            <div className="layout-modal-section">
              <div className="layout-modal-section-head">
                <label className="layout-modal-select-all" title="Select or deselect all windows">
                  <input
                    type="checkbox"
                    checked={layoutSelectedTabs.size === tabs.length && tabs.length > 0}
                    onChange={toggleLayoutSelectAll}
                  />
                  <span>Select windows</span>
                </label>
                <span className="layout-modal-count">{layoutSelectedTabs.size} of {tabs.length}</span>
              </div>
              <div className="layout-modal-list">
                {tabs.map((tab) => {
                  const isChecked = layoutSelectedTabs.has(tab.sessionKey)
                  const color = SOURCE_COLORS[tab.sourceKind]
                  return (
                    <label
                      key={tab.sessionKey}
                      className={`layout-modal-item ${isChecked ? 'checked' : ''}`}
                    >
                      <input
                        type="checkbox"
                        checked={isChecked}
                        onChange={() => toggleLayoutTab(tab.sessionKey)}
                      />
                      <span className="layout-modal-item-dot" style={{ background: color }} />
                      <span className="layout-modal-item-label">#{tab.index} {tab.label}</span>
                    </label>
                  )
                })}
              </div>
            </div>

            {/* Monitor slot position */}
            <div className="layout-modal-section">
              <span className="layout-modal-section-title">Monitor slot</span>
              <div className="layout-modal-monitor-pos">
                {(['first', 'last', 'fixed', 'none'] as const).map((pos) => (
                  <button
                    key={pos}
                    className={`layout-modal-pos-btn ${monitorSlotPosition === pos ? 'active' : ''}`}
                    onClick={() => setMonitorSlotPosition(pos)}
                    title={
                      pos === 'first' ? 'Place monitor window first' :
                      pos === 'last' ? 'Place monitor window last' :
                      pos === 'fixed' ? 'Keep monitor in place, tile agents around it' :
                      'Exclude monitor from layout'
                    }
                  >
                    {pos === 'first' ? 'First' : pos === 'last' ? 'Last' : pos === 'fixed' ? 'Fixed' : 'None'}
                  </button>
                ))}
              </div>
            </div>

            {/* Layout options */}
            {layoutSelectedTabs.size >= 1 && (
              <div className="layout-modal-section">
                <span className="layout-modal-section-title">Layout</span>
                <div className="layout-modal-options">
                  {([
                    { key: 'grid', icon: <LayoutGrid size={18} />, label: 'Grid' },
                    { key: 'columns', icon: <Columns size={18} />, label: 'Columns' },
                    { key: 'rows', icon: <Rows size={18} />, label: 'Rows' },
                    { key: 'main-side', icon: <PanelLeft size={18} />, label: 'Main+Side' },
                  ] as const).map(({ key, icon, label }) => (
                    <button
                      key={key}
                      className={`layout-modal-opt ${previewLayout === key ? 'active' : ''}`}
                      onClick={() => handleLayout(key)}
                      title={`Arrange windows in ${label.toLowerCase()} layout`}
                    >
                      {icon}
                      <span>{label}</span>
                    </button>
                  ))}
                </div>
              </div>
            )}

            {/* Actions */}
            <div className="layout-modal-actions">
              <button className="cancel-btn" onClick={() => exitLayoutSelectMode()} title="Cancel layout arrangement">
                Cancel
              </button>
              {overlayActive && (
                <button className="layout-modal-apply" onClick={handleConfirmLayout} title="Apply the selected layout">
                  <Check size={14} /> Apply
                </button>
              )}
            </div>
          </div>
        </div>
      )}
    </>
  )
}

/** Fixed-position dropdown that computes placement from a trigger ref. */
function FixedDropdown({
  show,
  onClose,
  triggerRef,
  children,
}: {
  show: boolean
  onClose: () => void
  triggerRef: React.RefObject<HTMLButtonElement | null>
  children: React.ReactNode
}) {
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null)
  const dropRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!show || !triggerRef.current) return
    const rect = triggerRef.current.getBoundingClientRect()
    const dropH = dropRef.current?.offsetHeight || 200
    const viewH = window.innerHeight
    // Prefer below, flip above if not enough space
    let top = rect.bottom + 4
    if (top + dropH > viewH - 8) {
      top = rect.top - dropH - 4
    }
    // Align left edge to trigger, but clamp to viewport
    let left = rect.left
    const dropW = dropRef.current?.offsetWidth || 150
    if (left + dropW > window.innerWidth - 8) {
      left = window.innerWidth - dropW - 8
    }
    if (left < 4) left = 4
    setPos({ top, left })
  }, [show, triggerRef])

  // Close on outside click
  const handleClick = useCallback((e: MouseEvent) => {
    if (dropRef.current && !dropRef.current.contains(e.target as Node) &&
        triggerRef.current && !triggerRef.current.contains(e.target as Node)) {
      onClose()
    }
  }, [onClose, triggerRef])

  useEffect(() => {
    if (!show) return
    document.addEventListener('mousedown', handleClick)
    return () => document.removeEventListener('mousedown', handleClick)
  }, [show, handleClick])

  if (!show) return null

  return (
    <div
      ref={dropRef}
      className="layout-picker"
      style={pos ? { top: pos.top, left: pos.left } : { visibility: 'hidden' }}
    >
      {children}
    </div>
  )
}
