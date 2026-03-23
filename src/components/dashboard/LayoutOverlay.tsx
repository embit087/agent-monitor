import { useEffect, useState } from 'react'

interface WindowRect {
  x: number
  y: number
  width: number
  height: number
}

interface ScreenSize {
  width: number
  height: number
}

export function LayoutOverlay() {
  const [rects, setRects] = useState<WindowRect[]>([])
  const [screen, setScreen] = useState<ScreenSize>({ width: 1, height: 1 })
  const [layoutName, setLayoutName] = useState('layout')
  const [monitorIndex, setMonitorIndex] = useState<number | null>(null)
  const [visible, setVisible] = useState(false)

  // Force all backgrounds transparent immediately on mount
  useEffect(() => {
    document.documentElement.style.background = 'transparent'
    document.body.style.background = 'transparent'
    const root = document.getElementById('root')
    if (root) root.style.background = 'transparent'
  }, [])

  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    const rectsParam = params.get('rects')
    const screenParam = params.get('screen')
    const layoutParam = params.get('layout')
    const monitorParam = params.get('monitorIndex')

    if (rectsParam) {
      try { setRects(JSON.parse(rectsParam)) } catch { /* ignore */ }
    }
    if (screenParam) {
      try { setScreen(JSON.parse(screenParam)) } catch { /* ignore */ }
    }
    if (layoutParam) {
      setLayoutName(layoutParam)
    }
    if (monitorParam != null && monitorParam !== '') {
      setMonitorIndex(parseInt(monitorParam, 10))
    }

    // Trigger fade-in after a frame
    requestAnimationFrame(() => {
      requestAnimationFrame(() => setVisible(true))
    })
  }, [])

  // Pre-compute labels: "M" for monitor, sequential numbers for agents
  const labels = (() => {
    let agentNum = 0
    return rects.map((_, i) => {
      if (i === monitorIndex) return 'M'
      agentNum++
      return String(agentNum)
    })
  })()

  const gap = 4

  return (
    <div className={`overlay-root ${visible ? 'visible' : ''}`}>
      {rects.map((rect, i) => {
        const left = (rect.x / screen.width) * 100
        const top = (rect.y / screen.height) * 100
        const width = (rect.width / screen.width) * 100
        const height = (rect.height / screen.height) * 100
        const isMonitor = i === monitorIndex

        return (
          <div
            key={i}
            className={`overlay-zone ${isMonitor ? 'overlay-zone-monitor' : ''}`}
            style={{
              left: `calc(${left}% + ${gap}px)`,
              top: `calc(${top}% + ${gap}px)`,
              width: `calc(${width}% - ${gap * 2}px)`,
              height: `calc(${height}% - ${gap * 2}px)`,
              animationDelay: `${i * 60}ms`,
            }}
          >
            <span className="overlay-zone-label">{labels[i]}</span>
          </div>
        )
      })}

      <div className="overlay-layout-badge">
        {layoutName}
      </div>
    </div>
  )
}
