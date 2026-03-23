import { useState, useCallback } from 'react'
import { Check, Copy } from 'lucide-react'

interface CopyButtonProps {
  text: string
  className?: string
  label?: string
}

export function CopyButton({ text, className = 'copy-btn', label }: CopyButtonProps) {
  const [copied, setCopied] = useState(false)

  const handleCopy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(text)
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    } catch {
      const ta = document.createElement('textarea')
      ta.value = text
      document.body.appendChild(ta)
      ta.select()
      document.execCommand('copy')
      document.body.removeChild(ta)
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    }
  }, [text])

  return (
    <button
      className={`${className} ${copied ? 'copied' : ''}`}
      onClick={(e) => {
        e.stopPropagation()
        handleCopy()
      }}
      title={copied ? 'Copied!' : 'Copy'}
    >
      {copied ? <Check size={12} /> : <Copy size={12} />}
      {label && <span className="copy-btn-label">{copied ? 'Copied' : label}</span>}
    </button>
  )
}
