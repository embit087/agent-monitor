import { Hourglass, Check, AlertTriangle } from 'lucide-react'
import { usePanelStore } from '../../stores/panelStore.ts'
import { shortSessionId } from '../../utils/formatting.ts'

export function SwitchStatusBar() {
  const switchStatus = usePanelStore((s) => s.switchStatus)

  if (switchStatus.kind === 'idle') return null

  const className = `switch-status-bar ${switchStatus.kind}`

  return (
    <div className={className}>
      {switchStatus.kind === 'switching' && (
        <>
          <Hourglass size={14} />
          Switching to {shortSessionId(switchStatus.id)}...
        </>
      )}
      {switchStatus.kind === 'succeeded' && (
        <>
          <Check size={14} />
          Switched to {shortSessionId(switchStatus.id)}
        </>
      )}
      {switchStatus.kind === 'failed' && (
        <>
          <AlertTriangle size={14} />
          Failed: {switchStatus.error || shortSessionId(switchStatus.id)}
        </>
      )}
    </div>
  )
}
