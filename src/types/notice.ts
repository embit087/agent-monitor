export interface Notice {
  id: string
  at: string
  title: string
  body: string
  source?: string
  action?: string
  summary?: string
  request?: string
  rawResponseJSON?: string
}
