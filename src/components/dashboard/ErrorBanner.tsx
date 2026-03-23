import { AlertTriangle } from 'lucide-react'

export function ErrorBanner({ message }: { message: string }) {
  return (
    <div className="error-banner">
      <AlertTriangle size={14} />
      {message}
    </div>
  )
}
