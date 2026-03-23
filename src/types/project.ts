export type ProjectStatus = 'active' | 'archived'

export interface ProjectGroup {
  id: string
  name: string
  colorHue: number
  sessionKeys: string[]
  description: string | null
  directory: string | null
  status: ProjectStatus
  createdAt: string
  updatedAt: string
}
