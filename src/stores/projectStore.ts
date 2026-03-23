import { create } from 'zustand'
import { invoke } from '@tauri-apps/api/core'
import type { ProjectGroup, ProjectStatus } from '../types/project.ts'

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
  updateDescription: (id: string, description: string) => Promise<void>
  updateDirectory: (id: string, directory: string) => Promise<void>
  setStatus: (id: string, status: ProjectStatus) => Promise<void>
  toggleSessionInProject: (sessionKey: string, groupId: string) => Promise<void>
  moveSessionToProject: (sessionKey: string, projectId: string | null) => Promise<void>
  setSelectedGroupId: (id: string | null) => void
  setIsCreating: (creating: boolean) => void
  setEditingGroupId: (id: string | null) => void
  selectedProjectDirectory: () => string | null
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

  updateDescription: async (id, description) => {
    try {
      await invoke('update_project_description', { id, description })
      set((s) => ({
        groups: s.groups.map((g) =>
          g.id === id ? { ...g, description: description.trim() || null } : g
        ),
      }))
    } catch (e) {
      console.error('Failed to update description:', e)
    }
  },

  updateDirectory: async (id, directory) => {
    try {
      await invoke('update_project_directory', { id, directory })
      set((s) => ({
        groups: s.groups.map((g) =>
          g.id === id ? { ...g, directory: directory.trim() || null } : g
        ),
      }))
    } catch (e) {
      console.error('Failed to update directory:', e)
    }
  },

  setStatus: async (id, status) => {
    try {
      await invoke('set_project_status', { id, status })
      set((s) => ({
        groups: s.groups.map((g) => (g.id === id ? { ...g, status } : g)),
      }))
    } catch (e) {
      console.error('Failed to set status:', e)
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

  moveSessionToProject: async (sessionKey, projectId) => {
    try {
      await invoke('move_session_to_project', { sessionKey, projectId })
      await get().fetchProjects()
    } catch (e) {
      console.error('Failed to move session:', e)
    }
  },

  setSelectedGroupId: (id) => set({ selectedGroupId: id }),
  setIsCreating: (creating) => set({ isCreating: creating }),
  setEditingGroupId: (id) => set({ editingGroupId: id }),

  groupsContaining: (sessionKey) => {
    return get().groups.filter((g) => g.sessionKeys.includes(sessionKey))
  },

  selectedProjectDirectory: () => {
    const { selectedGroupId, groups } = get()
    if (!selectedGroupId) return null
    const group = groups.find((g) => g.id === selectedGroupId)
    return group?.directory ?? null
  },

  matchesSelectedProject: (sessionKey) => {
    const { selectedGroupId, groups } = get()
    if (!selectedGroupId) return true
    const group = groups.find((g) => g.id === selectedGroupId)
    return group?.sessionKeys.includes(sessionKey) ?? false
  },
}))
