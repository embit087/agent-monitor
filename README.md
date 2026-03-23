<p align="center">
  <img src="icon.png" width="120" alt="Agent Monitor" />
</p>

<h1 align="center">Agent Monitor</h1>

<p align="center">
  <em>One panel to rule them all.</em><br/>
  <strong>The air traffic control tower for your AI terminal agents.</strong>
</p>

---

<p align="center">
  <img src="demo.gif" width="600" alt="Agent Monitor Demo" />
</p>

---

## The Problem

You opened one terminal with Claude Code. Cool, manageable, life is good.

Then you opened a second one. Still fine. You're a power user.

Then a third. Fourth. A Cursor instance. Another Claude. Maybe a terminal running something you forgot about three hours ago.

Now you're playing **alt-tab roulette**, squinting at identical terminal windows, wondering which one is the agent that's rewriting your auth module and which one is the one you accidentally told to "refactor everything."

> "I have 6 terminals open and I've lost control of my life." -- You, probably

## The Solution

**Agent Monitor** is a lightweight Tauri app that gives you a single, unified panel to manage all your terminal-based AI agents. Think of it as Mission Control for the age of vibe coding.

### What It Does

- **See all your agents in one sidebar.** Claude Code, Cursor, plain terminals -- they all show up as tabs. No more window-hunting.

- **Switch between agents with one click.** Click a tab, the terminal comes to the front. Click another tab, that one comes up. Revolutionary? No. Life-changing? Absolutely.

- **Auto-arrange your windows.** Grid, columns, rows, main+side -- pick a layout and all your terminal windows snap into place. No more manual dragging.

- **Read the conversation without switching.** The chat view shows you what each agent is saying and doing, right in the panel. Inline image previews included.

- **Group agents by project.** Working on three repos at once? Drag agents into project groups. Color-code them. Feel organized for once.

- **Discover running agents automatically.** Hit the radar button and it finds all the agent sessions running on your machine. No manual setup required.

- **Send messages to agents from the panel.** Type in the input bar, hit enter, it goes straight to the terminal. You never have to leave the panel.

- **Monitor mode vs Tab mode.** Monitor mode gives you the full dashboard with chat view. Tab mode gives you just the sidebar for quick switching.

### The Workflow

```
1. Open Agent Monitor
2. It discovers your running agents
3. Click tabs to switch between them
4. Read their output in the chat view
5. Arrange windows with one click
6. Group agents by project
7. Feel like you have your life together
```

## Getting Started

### Prerequisites

- macOS (uses native window management APIs)
- [Rust](https://rustup.rs/) and [Node.js](https://nodejs.org/)

### Install & Run

```bash
npm install
npm run tauri dev
```

### Build

```bash
npm run tauri build
```

## How It Works

Agent Monitor runs a local HTTP server that receives notifications from your terminal agents. When Claude Code or Cursor runs, it posts updates to the monitor. The Tauri app displays everything in a native window with a sidebar for navigation and a chat view for reading agent output.

The app uses AppleScript under the hood to discover terminal windows, switch focus, capture previews, and arrange layouts.

## Architecture

```
src/                    # React frontend
  components/dashboard/ # UI components (sidebar, chat, project management)
  stores/               # Zustand state management
  hooks/                # Custom React hooks
  utils/                # Formatting, colors, filters

src-tauri/              # Rust backend
  src/commands/         # Tauri IPC commands
  src/services/         # Window management, cloud sync
  src/server/           # HTTP notification server + WebSocket
  src/models/           # Data models
```

## License

MIT
