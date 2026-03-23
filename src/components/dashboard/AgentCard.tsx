import type { Notice } from '../../types/notice.ts'
import { usePanelStore } from '../../stores/panelStore.ts'
import { CopyButton } from './CopyButton.tsx'
import { InlineImage } from './InlineImage.tsx'
import { formatDate, formatResponseAsMarkdown } from '../../utils/formatting.ts'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'

const IMAGE_PATTERN = /\[Image:\s*source:\s*(.+?)\]/g

function renderWithImages(text: string) {
  const parts: (string | { type: 'image'; path: string })[] = []
  let lastIndex = 0
  let match: RegExpExecArray | null

  const regex = new RegExp(IMAGE_PATTERN)
  while ((match = regex.exec(text)) !== null) {
    if (match.index > lastIndex) {
      parts.push(text.slice(lastIndex, match.index))
    }
    parts.push({ type: 'image', path: match[1].trim() })
    lastIndex = regex.lastIndex
  }
  if (lastIndex < text.length) {
    parts.push(text.slice(lastIndex))
  }

  return parts
}

export function AgentCard({ notice }: { notice: Notice }) {
  const selectedSessionId = usePanelStore((s) => s.selectedSessionId)
  const setSelectedSessionId = usePanelStore((s) => s.setSelectedSessionId)
  const hideResponses = usePanelStore((s) => s.hideResponses)

  const sessionKey = notice.action?.trim() || null
  const highlighted = sessionKey === selectedSessionId

  const handleClick = () => {
    if (!sessionKey) return
    setSelectedSessionId(selectedSessionId === sessionKey ? null : sessionKey)
  }
  const displayResponse = notice.summary || notice.body
  const showRequest = notice.request && notice.request !== displayResponse

  // Compact event-style rendering for short, single-line system notifications
  const isCompact = !showRequest && displayResponse &&
    !displayResponse.includes('\n') && displayResponse.length < 250

  if (isCompact) {
    return (
      <div className={`chat-event ${highlighted ? 'highlighted' : ''} ${sessionKey ? 'clickable' : ''}`} onClick={handleClick}>
        <span className="chat-event-text">{displayResponse}</span>
        <span className="chat-event-time">{formatDate(notice.at)}</span>
      </div>
    )
  }

  const messageClass = [
    'chat-message',
    highlighted ? 'highlighted' : '',
    hideResponses ? 'user-only' : '',
  ].filter(Boolean).join(' ')

  return (
    <div className={messageClass} onClick={handleClick} style={sessionKey ? { cursor: 'pointer' } : undefined}>
      <div className="chat-message-header">
        <span className="chat-timestamp">{formatDate(notice.at)}</span>
        {displayResponse && (
          <CopyButton text={displayResponse} className="copy-btn chat-header-copy" label="Copy" />
        )}
      </div>

      {showRequest ? (
        <div className="chat-request">
          <div className="chat-request-text">{notice.request}</div>
        </div>
      ) : (
        <div className="chat-spacer" />
      )}

      {!hideResponses && displayResponse && (
        <div className="chat-response">
          {renderWithImages(displayResponse).map((part, i) =>
            typeof part === 'string' ? (
              <ReactMarkdown key={i} remarkPlugins={[remarkGfm]}>
                {formatResponseAsMarkdown(part)}
              </ReactMarkdown>
            ) : (
              <InlineImage key={i} filePath={part.path} />
            )
          )}
        </div>
      )}
    </div>
  )
}
