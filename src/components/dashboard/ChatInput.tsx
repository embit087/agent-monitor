import { useState, useRef, useCallback, useEffect } from 'react'
import { Send, Eye, FolderPlus, X, Image } from 'lucide-react'
import { usePanelStore } from '../../stores/panelStore.ts'
import { useProjectStore } from '../../stores/projectStore.ts'
import { useSessionTabs, type SessionTab } from '../../hooks/useSessionTabs.ts'
import { shortSessionId } from '../../utils/formatting.ts'
import { hueToColor, SOURCE_COLORS } from '../../utils/colors.ts'

export function ChatInput() {
  const sendToSession = usePanelStore((s) => s.sendToSession)
  const selectedSessionId = usePanelStore((s) => s.selectedSessionId)
  const setSelectedSessionId = usePanelStore((s) => s.setSelectedSessionId)
  const openWinidSession = usePanelStore((s) => s.openWinidSession)
  const closeWinidSession = usePanelStore((s) => s.closeWinidSession)
  const capturePreview = usePanelStore((s) => s.capturePreview)
  const previewImage = usePanelStore((s) => s.previewImage)
  const previewSessionId = usePanelStore((s) => s.previewSessionId)

  const groups = useProjectStore((s) => s.groups)
  const groupsContaining = useProjectStore((s) => s.groupsContaining)
  const toggleSessionInProject = useProjectStore((s) => s.toggleSessionInProject)

  const tabs = useSessionTabs()

  const [text, setText] = useState('')
  const [sending, setSending] = useState(false)
  const [lastResult, setLastResult] = useState<{ ok: boolean; message: string } | null>(null)
  const [showProjectMenu, setShowProjectMenu] = useState(false)
  const [showPreview, setShowPreview] = useState(false)
  const [pendingClose, setPendingClose] = useState(false)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const projectMenuRef = useRef<HTMLDivElement>(null)

  const focusInputAt = usePanelStore((s) => s.focusInputAt)

  const effectiveSession = selectedSessionId || ''
  const activeTab = tabs.find((t) => t.sessionKey === effectiveSession)
  const sourceKind = activeTab?.sourceKind || 'terminal'
  const sessionProjects = effectiveSession ? groupsContaining(effectiveSession) : []

  // Focus textarea when requested
  useEffect(() => {
    if (focusInputAt && textareaRef.current) {
      textareaRef.current.focus()
    }
  }, [focusInputAt])

  // Close project menu on outside click
  useEffect(() => {
    if (!showProjectMenu) return
    const handler = (e: MouseEvent) => {
      if (projectMenuRef.current && !projectMenuRef.current.contains(e.target as Node)) {
        setShowProjectMenu(false)
      }
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [showProjectMenu])

  const handleSend = useCallback(async () => {
    const trimmed = text.trim()
    if (!trimmed || sending || !effectiveSession) return

    setSending(true)
    setLastResult(null)
    try {
      const result = await sendToSession(effectiveSession, trimmed, sourceKind)
      setLastResult(result)
      if (result.ok) {
        setText('')
        if (textareaRef.current) {
          textareaRef.current.style.height = 'auto'
        }
        setTimeout(() => setLastResult(null), 3000)
      }
    } finally {
      setSending(false)
    }
  }, [text, sending, effectiveSession, sourceKind, sendToSession])

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  const handleInput = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setText(e.target.value)
    const el = e.target
    el.style.height = 'auto'
    el.style.height = Math.min(el.scrollHeight, 120) + 'px'
  }

  return (
    <div className="chat-input-bar">
      {/* Session management strip */}
      {activeTab && (
        <SessionManageStrip
          tab={activeTab}
          sessionProjects={sessionProjects}
          groups={groups}
          showProjectMenu={showProjectMenu}
          setShowProjectMenu={setShowProjectMenu}
          projectMenuRef={projectMenuRef}
          toggleSessionInProject={toggleSessionInProject}
          onFocus={() => openWinidSession(activeTab.sessionKey)}
          onCapture={() => { capturePreview(activeTab.sessionKey); setShowPreview(true) }}
          onClose={() => setPendingClose(true)}
        />
      )}

      {/* Status */}
      {lastResult && (
        <span className={`chat-input-status ${lastResult.ok ? 'ok' : 'err'}`}>
          {lastResult.message}
        </span>
      )}

      {/* Preview overlay */}
      {showPreview && previewImage && previewSessionId === effectiveSession && (
        <div className="confirm-overlay" onClick={() => setShowPreview(false)}>
          <img
            src={`data:image/png;base64,${previewImage}`}
            className="session-preview-img"
            alt="Window preview"
            onClick={(e) => e.stopPropagation()}
          />
        </div>
      )}

      {/* Close confirmation */}
      {pendingClose && activeTab && (
        <div className="confirm-overlay" onClick={() => setPendingClose(false)}>
          <div className="confirm-dialog" onClick={(e) => e.stopPropagation()}>
            <h3>Close session #{activeTab.index}?</h3>
            <p>All notifications for this session will be removed and its WINID unregistered.</p>
            <div className="confirm-actions">
              <button className="cancel-btn" onClick={() => setPendingClose(false)}>Cancel</button>
              <button className="danger-btn" onClick={() => {
                closeWinidSession(activeTab.sessionKey)
                setSelectedSessionId(null)
                setPendingClose(false)
              }}>Close Session</button>
            </div>
          </div>
        </div>
      )}

      <div className="chat-input-field">
        <textarea
          ref={textareaRef}
          className="chat-input-textarea"
          value={text}
          onChange={handleInput}
          onKeyDown={handleKeyDown}
          placeholder={effectiveSession ? 'Send to terminal...' : 'Select a session first'}
          rows={1}
          disabled={sending || !effectiveSession}
        />
        <button
          className={`chat-send-btn ${text.trim() && effectiveSession ? 'ready' : ''}`}
          onClick={handleSend}
          disabled={!text.trim() || sending || !effectiveSession}
          title="Send (Enter)"
        >
          <Send size={14} />
        </button>
      </div>
    </div>
  )
}

function SessionManageStrip({
  tab,
  sessionProjects,
  groups,
  showProjectMenu,
  setShowProjectMenu,
  projectMenuRef,
  toggleSessionInProject,
  onFocus,
  onCapture,
  onClose,
}: {
  tab: SessionTab
  sessionProjects: { id: string; name: string; colorHue: number }[]
  groups: { id: string; name: string; colorHue: number }[]
  showProjectMenu: boolean
  setShowProjectMenu: (v: boolean) => void
  projectMenuRef: React.RefObject<HTMLDivElement | null>
  toggleSessionInProject: (sessionKey: string, groupId: string) => void
  onFocus: () => void
  onCapture: () => void
  onClose: () => void
}) {
  const color = SOURCE_COLORS[tab.sourceKind]

  return (
    <div className="session-manage-strip">
      <span className="session-manage-label" style={{ color }}>
        #{tab.index} {tab.label}
      </span>
      <span className="session-manage-id">{shortSessionId(tab.sessionKey)}</span>

      {sessionProjects.map((g) => (
        <span key={g.id} className="session-manage-dot" style={{ background: hueToColor(g.colorHue, 45, 55) }} title={g.name} />
      ))}

      <span className="session-manage-spacer" />

      <button className="session-manage-btn" onClick={onFocus} title="Focus window">
        <Eye size={12} />
      </button>
      <button className="session-manage-btn" onClick={onCapture} title="Capture preview">
        <Image size={12} />
      </button>
      <div style={{ position: 'relative' }}>
        <button
          className={`session-manage-btn ${showProjectMenu ? 'active' : ''}`}
          onClick={() => setShowProjectMenu(!showProjectMenu)}
          title="Assign to project"
        >
          <FolderPlus size={12} />
        </button>
        {showProjectMenu && (
          <div className="session-project-menu" ref={projectMenuRef}>
            {groups.length === 0 ? (
              <span className="discover-empty">No projects yet</span>
            ) : (
              groups.map((g) => {
                const assigned = sessionProjects.some((p) => p.id === g.id)
                return (
                  <label key={g.id} className="project-session-toggle">
                    <input
                      type="checkbox"
                      checked={assigned}
                      onChange={() => toggleSessionInProject(tab.sessionKey, g.id)}
                    />
                    <span className="session-manage-dot" style={{ background: hueToColor(g.colorHue, 45, 55) }} />
                    <span className="project-session-label">{g.name}</span>
                  </label>
                )
              })
            )}
          </div>
        )}
      </div>
      <button className="session-manage-btn danger" onClick={onClose} title="Close session">
        <X size={12} />
      </button>
    </div>
  )
}
