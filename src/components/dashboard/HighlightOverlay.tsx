import { useEffect, useState } from 'react'

export function HighlightOverlay() {
  const [color, setColor] = useState('rgba(0, 255, 200, 0.8)')

  useEffect(() => {
    document.documentElement.style.background = 'transparent'
    document.body.style.background = 'transparent'
    const root = document.getElementById('root')
    if (root) root.style.background = 'transparent'
  }, [])

  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    const c = params.get('color')
    if (c) setColor(c)
  }, [])

  return (
    <div className="highlight-root visible">
      <div
        className="highlight-border"
        style={{ borderColor: color, boxShadow: `0 0 18px 2px ${color}, inset 0 0 18px 2px ${color}` }}
      />
    </div>
  )
}
