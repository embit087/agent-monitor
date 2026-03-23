import { useState, useEffect } from 'react'
import { invoke } from '@tauri-apps/api/core'

interface InlineImageProps {
  filePath: string
}

export function InlineImage({ filePath }: InlineImageProps) {
  const [src, setSrc] = useState<string | null>(null)
  const [error, setError] = useState(false)

  useEffect(() => {
    let cancelled = false
    invoke<string>('read_file_base64', { path: filePath })
      .then((base64) => {
        if (!cancelled) {
          const ext = filePath.split('.').pop()?.toLowerCase() || 'png'
          const mime = ext === 'jpg' || ext === 'jpeg' ? 'image/jpeg'
            : ext === 'gif' ? 'image/gif'
            : ext === 'webp' ? 'image/webp'
            : 'image/png'
          setSrc(`data:${mime};base64,${base64}`)
        }
      })
      .catch(() => {
        if (!cancelled) setError(true)
      })
    return () => { cancelled = true }
  }, [filePath])

  if (error) {
    return <span className="inline-image-error">Image not found: {filePath}</span>
  }

  if (!src) {
    return <span className="inline-image-loading">Loading image...</span>
  }

  return (
    <img
      className="inline-image"
      src={src}
      alt={filePath.split('/').pop() || 'image'}
      onClick={() => window.open(src, '_blank')}
    />
  )
}
