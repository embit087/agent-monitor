import { usePanelStore } from '../../stores/panelStore.ts'

export function WindowPreview({ sessionId }: { sessionId: string }) {
  const previewImage = usePanelStore((s) => s.previewImage)
  const previewSessionId = usePanelStore((s) => s.previewSessionId)
  const capturePreview = usePanelStore((s) => s.capturePreview)

  if (previewSessionId !== sessionId || !previewImage) return null

  return (
    <img
      className="window-preview"
      src={`data:image/png;base64,${previewImage}`}
      alt="Window preview"
      onClick={() => capturePreview(sessionId)}
      title="Click to refresh preview"
    />
  )
}
