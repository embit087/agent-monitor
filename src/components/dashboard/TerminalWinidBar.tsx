import { useState } from 'react'
import { Plus, Zap, TerminalSquare, Bot, MousePointer } from 'lucide-react'
import { usePanelStore } from '../../stores/panelStore.ts'
import { invoke } from '@tauri-apps/api/core'
import { Tooltip } from './Tooltip.tsx'

export function TerminalWinidBar() {
  const titleFilter = usePanelStore((s) => s.titleFilter)
  const upsertManualTerminal = usePanelStore((s) => s.upsertManualTerminal)
  const [winid, setWinid] = useState('')
  const [autoMode, setAutoMode] = useState(false)

  if (titleFilter !== 'terminal') return null

  const handleAdd = () => {
    if (winid.trim()) {
      upsertManualTerminal(winid.trim())
      setWinid('')
    }
  }

  const handleNewTerminal = async (kind: 'plain' | 'claude' | 'cursor') => {
    let chainCommand: string | undefined
    if (kind === 'claude') {
      chainCommand = autoMode
        ? 'claude --dangerously-skip-permissions'
        : 'claude'
    } else if (kind === 'cursor') {
      chainCommand = autoMode ? 'cursor --force' : 'cursor'
    }
    try {
      await invoke('init_new_terminal', { chainCommand: chainCommand ?? null })
    } catch (e) {
      console.error('Failed to init terminal:', e)
    }
  }

  return (
    <div className="terminal-winid-bar">
      <div className="terminal-winid-row">
        <input
          value={winid}
          onChange={(e) => setWinid(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && handleAdd()}
          placeholder="Paste or type WINID"
        />
        <Tooltip text="Add WINID to monitor">
          <button className="icon-btn" onClick={handleAdd}>
            <Plus size={14} />
          </button>
        </Tooltip>
      </div>
      <div className="terminal-launch-row">
        <Tooltip text={autoMode ? 'Auto mode on — skip permissions' : 'Auto mode off'}>
          <button
            className={`icon-btn ${autoMode ? 'icon-btn-active' : ''}`}
            onClick={() => setAutoMode(!autoMode)}
          >
            <Zap size={14} />
          </button>
        </Tooltip>
        <Tooltip text="Open new plain terminal">
          <button className="icon-btn" onClick={() => handleNewTerminal('plain')}>
            <TerminalSquare size={14} />
          </button>
        </Tooltip>
        <Tooltip text="Open terminal with Claude Code">
          <button className="icon-btn" onClick={() => handleNewTerminal('claude')}>
            <Bot size={14} />
          </button>
        </Tooltip>
        <Tooltip text="Open terminal with Cursor">
          <button className="icon-btn" onClick={() => handleNewTerminal('cursor')}>
            <MousePointer size={14} />
          </button>
        </Tooltip>
      </div>
    </div>
  )
}
