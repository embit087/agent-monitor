import { create } from 'zustand'
import { invoke } from '@tauri-apps/api/core'
import type { ProjectGroup } from '../types/project.ts'

interface ProjectState {
  groups: ProjectGroup[]
  selectedGroupId: string | null
  isCreating: boolean
  editingGroupId: string | null

  fetchProjects: () => Promise<void>
  createProject: (name: string) => Promise<void>
  renameProject: (id: string, name: string) => Promise<void>
  deleteProject: (id: string) => Promise<void>
  setProjectColor: (id: string, hue: number) => Promise<void>
  toggleSessionInProject: (sessionKey: string, groupId: string) => Promise<void>
  setSelectedGroupId: (id: string | null) => void
  setIsCreating: (creating: boolean) => void
  setEditingGroupId: (id: string | null) => void
  groupsContaining: (sessionKey: string) => ProjectGroup[]
  matchesSelectedProject: (sessionKey: string) => boolean
}

export const useProjectStore = create<ProjectState>((set, get) => ({
  groups: [],
  selectedGroupId: null,
  isCreating: false,
  editingGroupId: null,

  fetchProjects: async () => {
    try {
      const groups = await invoke<ProjectGroup[]>('list_projects')
      set({ groups })
    } catch (e) {
      console.error('Failed to fetch projects:', e)
    }
  },

  createProject: async (name) => {
    try {
      const group = await invoke<ProjectGroup>('create_project', { name })
      set((s) => ({ groups: [...s.groups, group], isCreating: false }))
    } catch (e) {
      console.error('Failed to create project:', e)
    }
  },

  renameProject: async (id, name) => {
    try {
      await invoke('rename_project', { id, name })
      set((s) => ({
        groups: s.groups.map((g) => (g.id === id ? { ...g, name } : g)),
        editingGroupId: null,
      }))
    } catch (e) {
      console.error('Failed to rename project:', e)
    }
  },

  deleteProject: async (id) => {
    try {
      await invoke('delete_project', { id })
      set((s) => ({
        groups: s.groups.filter((g) => g.id !== id),
        selectedGroupId: s.selectedGroupId === id ? null : s.selectedGroupId,
      }))
    } catch (e) {
      console.error('Failed to delete project:', e)
    }
  },

  setProjectColor: async (id, hue) => {
    try {
      await invoke('set_project_color', { id, hue })
      set((s) => ({
        groups: s.groups.map((g) => (g.id === id ? { ...g, colorHue: hue } : g)),
      }))
    } catch (e) {
      console.error('Failed to set project color:', e)
    }
  },

  toggleSessionInProject: async (sessionKey, groupId) => {
    try {
      await invoke('toggle_session_in_project', { sessionKey, groupId })
      await get().fetchProjects()
    } catch (e) {
      console.error('Failed to toggle session:', e)
    }
  },

  setSelectedGroupId: (id) => set({ selectedGroupId: id }),
  setIsCreating: (creating) => set({ isCreating: creating }),
  setEditingGroupId: (id) => set({ editingGroupId: id }),

  groupsContaining: (sessionKey) => {
    return get().groups.filter((g) => g.sessionKeys.includes(sessionKey))
  },

  matchesSelectedProject: (sessionKey) => {
    const { selectedGroupId, groups } = get()
    if (!selectedGroupId) return true
    const group = groups.find((g) => g.id === selectedGroupId)
    return group?.sessionKeys.includes(sessionKey) ?? false
  },
}))
