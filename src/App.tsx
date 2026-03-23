import { useEffect } from 'react'
import { usePanelStore } from './stores/panelStore.ts'
import { useProjectStore } from './stores/projectStore.ts'
import { useTauriEvents } from './hooks/useTauriEvents.ts'
import { ProjectBar } from './components/dashboard/ProjectBar.tsx'
import { TerminalWinidBar } from './components/dashboard/TerminalWinidBar.tsx'
import { AgentSessionTabBar } from './components/dashboard/AgentSessionTabBar.tsx'
import { SwitchStatusBar } from './components/dashboard/SwitchStatusBar.tsx'
import { ErrorBanner } from './components/dashboard/ErrorBanner.tsx'
import { AgentCardList } from './components/dashboard/AgentCardList.tsx'
import { ChatInput } from './components/dashboard/ChatInput.tsx'
import { ProjectManagePanel } from './components/dashboard/ProjectManagePanel.tsx'
import { SettingsPanel } from './components/dashboard/SettingsPanel.tsx'
import { ProjectDropOverlay } from './components/dashboard/ProjectDropOverlay.tsx'
import { LayoutOverlay } from './components/dashboard/LayoutOverlay.tsx'
import { HighlightOverlay } from './components/dashboard/HighlightOverlay.tsx'
import './App.css'

function Dashboard() {
  const fetchNotices = usePanelStore(s => s.fetchNotices)
  const fetchServerStatus = usePanelStore(s => s.fetchServerStatus)
  const saveSelf = usePanelStore(s => s.saveSelf)
  const sidebarMode = usePanelStore(s => s.sidebarMode)
  const lastError = usePanelStore(s => s.lastError)
  const fetchProjects = useProjectStore(s => s.fetchProjects)
  const draggingSessionKey = usePanelStore(s => s.draggingSessionKey)

  useTauriEvents()

  useEffect(() => {
    fetchNotices()
    fetchServerStatus()
    fetchProjects()
    setTimeout(() => saveSelf(), 1000)
  }, [fetchNotices, fetchServerStatus, fetchProjects, saveSelf])

  const isTab = sidebarMode === 'tab'
  const isProject = sidebarMode === 'project'
  const isSettings = sidebarMode === 'settings'

  return (
    <div className={`dashboard ${isTab ? 'tab-mode' : ''}`}>
      <div className="titlebar-drag" data-tauri-drag-region style={draggingSessionKey ? { pointerEvents: 'none' } : undefined} />
      <AgentSessionTabBar />
      <div className="dashboard-right">
        <SwitchStatusBar />
        {!isTab && !isProject && !isSettings && (
          <div className="dashboard-topbar">
            <ProjectBar />
            <TerminalWinidBar />
          </div>
        )}
        {!isTab && lastError && <ErrorBanner message={lastError} />}
        {sidebarMode === 'monitor' && (
          <div className="dashboard-content">
            <ProjectDropOverlay />
            <AgentCardList />
            <ChatInput />
          </div>
        )}
        {isProject && <ProjectManagePanel />}
        {sidebarMode === 'settings' && <SettingsPanel />}
      </div>
    </div>
  )
}

function NotepadWindow() {
  return (
    <div className="notepad-window">
      <p style={{ padding: 20, color: 'var(--text-secondary)' }}>
        Notepad window — Monaco editor will be integrated here.
      </p>
    </div>
  )
}

function App() {
  const path = window.location.pathname
  if (path === '/notepad') {
    return <NotepadWindow />
  }
  if (path === '/overlay') {
    return <LayoutOverlay />
  }
  if (path === '/highlight') {
    return <HighlightOverlay />
  }
  return <Dashboard />
}

export default App
