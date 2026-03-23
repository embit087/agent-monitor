import { useState, useRef, useCallback, type ReactNode } from 'react'

interface TooltipProps {
  text: string
  children: ReactNode
  position?: 'top' | 'bottom'
}

export function Tooltip({ text, children, position = 'top' }: TooltipProps) {
  const [visible, setVisible] = useState(false)
  const timeoutRef = useRef<number | null>(null)

  const show = useCallback(() => {
    timeoutRef.current = window.setTimeout(() => setVisible(true), 400)
  }, [])

  const hide = useCallback(() => {
    if (timeoutRef.current) clearTimeout(timeoutRef.current)
    setVisible(false)
  }, [])

  return (
    <span className="tooltip-wrapper" onMouseEnter={show} onMouseLeave={hide}>
      {children}
      {visible && (
        <span className={`tooltip-bubble tooltip-${position}`}>{text}</span>
      )}
    </span>
  )
}
