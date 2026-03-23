import { usePanelStore } from '../../stores/panelStore.ts'

export function SettingsPanel() {
  const alwaysOnTop = usePanelStore((s) => s.alwaysOnTop)
  const setAlwaysOnTop = usePanelStore((s) => s.setAlwaysOnTop)

  return (
    <div className="settings-panel">
      <div className="settings-panel-header">
        <span className="settings-panel-title">Settings</span>
      </div>
      <div className="settings-panel-body">
        <label className="settings-row" title="Keep Agent Monitor above all other windows">
          <span className="settings-row-label">Always on top</span>
          <input
            type="checkbox"
            className="settings-toggle"
            checked={alwaysOnTop}
            onChange={(e) => setAlwaysOnTop(e.target.checked)}
          />
        </label>
      </div>
    </div>
  )
}
