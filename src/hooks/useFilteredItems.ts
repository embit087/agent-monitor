import { useMemo } from 'react'
import { usePanelStore } from '../stores/panelStore.ts'
import { useProjectStore } from '../stores/projectStore.ts'
import type { Notice } from '../types/notice.ts'
import { matchesCursor, matchesClaudeCode, matchesTerminal } from '../utils/titleFilters.ts'

export function useFilteredItems(): Notice[] {
  const notices = usePanelStore((s) => s.notices)
  const titleFilter = usePanelStore((s) => s.titleFilter)
  const selectedGroupId = useProjectStore((s) => s.selectedGroupId)
  const groups = useProjectStore((s) => s.groups)

  return useMemo(() => {
    let filtered = notices

    // Title filter
    if (titleFilter === 'cursor') {
      filtered = filtered.filter((n) => matchesCursor(n.title))
    } else if (titleFilter === 'claudeCode') {
      filtered = filtered.filter((n) => matchesClaudeCode(n.title))
    } else if (titleFilter === 'terminal') {
      filtered = filtered.filter((n) => matchesTerminal(n.title))
    }

    // Project filter
    if (selectedGroupId) {
      const group = groups.find((g) => g.id === selectedGroupId)
      if (group) {
        filtered = filtered.filter((n) => {
          const key = n.action?.trim()
          return key ? group.sessionKeys.includes(key) : false
        })
      }
    }

    return filtered
  }, [notices, titleFilter, selectedGroupId, groups])
}
