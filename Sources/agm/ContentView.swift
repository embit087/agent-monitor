import AppKit
import Foundation
import MarkdownUI
import SwiftUI

private enum PanelLayout {
    static let windowPaddingH: CGFloat = 12
    static let windowPaddingTop: CGFloat = 8
    static let windowPaddingBottom: CGFloat = 10
    static let sectionGap: CGFloat = 10
    static let cardCorner: CGFloat = 10
    static let cardPadding: CGFloat = 8
    static let listRowGap: CGFloat = 6
}

private enum NoticeTitleFilter: String, CaseIterable, Identifiable {
    case cursor = "Cursor"
    case claudeCode = "Claude Code"
    case terminal = "Terminal"

    var id: String { rawValue }
}

private enum AgentSourceKind: Hashable {
    case cursor
    case claudeCode
    case terminal
    case other

    var tintColor: Color {
        switch self {
        case .cursor: return Color(hue: 0.75, saturation: 0.25, brightness: 0.65)
        case .claudeCode: return Color(hue: 0.45, saturation: 0.25, brightness: 0.6)
        case .terminal: return Color.orange.opacity(0.9)
        case .other: return .secondary
        }
    }

    var iconName: String {
        switch self {
        case .cursor: return "cursorarrow.rays"
        case .claudeCode: return "apple.terminal"
        case .terminal: return "apple.terminal"
        case .other: return "bolt.fill"
        }
    }

    var shortLabel: String {
        switch self {
        case .cursor: return "Cursor"
        case .claudeCode: return "CC"
        case .terminal: return "Term"
        case .other: return ""
        }
    }
}

private struct AgentSessionTab: Identifiable, Hashable {
    /// Normalized switch target key for selection + `ForEach` identity.
    let sessionKey: String
    /// Raw `notice.action` from the latest row for this target (trimmed) — same value space as the per-card control.
    let openAction: String
    let label: String
    let index: Int
    let sourceKind: AgentSourceKind
    var id: String { sessionKey }
}

struct ContentView: View {
    @EnvironmentObject private var model: PanelModel
    @EnvironmentObject private var notepad: NotepadModel
    @EnvironmentObject private var projects: ProjectGroupModel
    @Environment(\.openWindow) private var openWindow
    @State private var showClearConfirmation = false
    @State private var titleFilter: NoticeTitleFilter?
    @State private var selectedAgentSessionId: String?
    @State private var manualTerminalWinid = ""
    @State private var initTerminalAutoMode = false
    @State private var hideResponses = false
    @State private var sessionPendingClose: AgentSessionTab?
    @State private var newProjectName = ""
    @State private var editingProjectId: UUID?
    @State private var editingProjectName = ""
    @State private var dropTargetGroupId: UUID?
    @State private var showPreviewPopover = false
    @State private var showTypeFilters = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectBar
            filterBar
            terminalWinidEntryBar
            agentSessionTabBar
            switchStatusBar
            if let err = model.lastError {
                errorBanner(err)
            }
            agentCardList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 480, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: titleFilter) { _, _ in
            selectedAgentSessionId = nil
            showPreviewPopover = false
            model.clearPreview()
        }
        .onChange(of: projects.selectedGroupId) { _, _ in
            selectedAgentSessionId = nil
            showPreviewPopover = false
            model.clearPreview()
        }
        .onChange(of: agentSessionTabSignature) { _, _ in
            if let s = selectedAgentSessionId,
               !Set(titleFilteredItems.compactMap { Self.normalizedSessionId($0.action) }).contains(s) {
                selectedAgentSessionId = nil
                showPreviewPopover = false
                model.clearPreview()
            }
        }
        .onChange(of: notepad.openTrigger) { _, _ in
            openWindow(id: "notepad")
        }
        .alert("Clear all notifications?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task { await model.clearListFromUI() }
            }
        } message: {
            Text("All items will be removed from the list. This can’t be undone.")
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                titleBarTitleRow
                    .padding(.horizontal, 8)
            }
        }
    }

    /// Unified titlebar: app name, status dot, and version — clean inline layout.
    private var titleBarTitleRow: some View {
        HStack(alignment: .center, spacing: 5) {
            Spacer()

            titleBarStatusDot

            Text(AppVersion.string)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 2)
        .help(model.serverRunning ? "Server is ready" : "Starting…")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("agm, \(model.serverRunning ? "ready" : "starting"), version \(AppVersion.string)")
    }

    private var titleBarStatusDot: some View {
        Circle()
            .fill(model.serverRunning ? Color.mint : Color.orange.opacity(0.92))
            .frame(width: 5, height: 5)
            .shadow(color: (model.serverRunning ? Color.mint : Color.orange).opacity(0.3), radius: 1.5, y: 0.5)
            .animation(.easeInOut(duration: 0.22), value: model.serverRunning)
            .accessibilityHidden(true)
    }

    private var backgroundGradient: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.mint.opacity(0.06),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Project Bar

    private var projectBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // Session type filter toggle
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showTypeFilters.toggle()
                                if !showTypeFilters {
                                    titleFilter = nil
                                }
                            }
                        } label: {
                            Image(systemName: showTypeFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(showTypeFilters ? Color.primary : Color.secondary.opacity(0.7))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help(showTypeFilters ? "Hide session type filters" : "Show session type filters")
                        .accessibilityLabel(showTypeFilters ? "Collapse filters" : "Expand filters")

                        // "All Projects" chip
                        projectChip(name: "All", color: .secondary, isSelected: projects.selectedGroupId == nil) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                projects.selectedGroupId = nil
                            }
                        }

                        ForEach(projects.groups) { group in
                            let isSelected = projects.selectedGroupId == group.id
                            let isDropTarget = dropTargetGroupId == group.id
                            projectChip(
                                name: group.name,
                                color: group.color,
                                isSelected: isSelected,
                                count: activeSessionCount(for: group)
                            ) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    projects.selectedGroupId = isSelected ? nil : group.id
                                }
                            }
                            .overlay(
                                Capsule()
                                    .strokeBorder(group.color, lineWidth: isDropTarget ? 2 : 0)
                                    .animation(.easeInOut(duration: 0.12), value: isDropTarget)
                            )
                            .scaleEffect(isDropTarget ? 1.08 : 1.0)
                            .animation(.easeInOut(duration: 0.12), value: isDropTarget)
                            .dropDestination(for: String.self) { sessionKeys, _ in
                                for key in sessionKeys {
                                    projects.addSession(key, to: group.id)
                                }
                                return !sessionKeys.isEmpty
                            } isTargeted: { targeted in
                                dropTargetGroupId = targeted ? group.id : nil
                            }
                            .contextMenu { projectContextMenu(for: group) }
                        }
                    }
                    .padding(.horizontal, PanelLayout.windowPaddingH)
                    .padding(.vertical, 5)
                }

                // Create new project
                if projects.isCreatingGroup {
                    HStack(spacing: 4) {
                        TextField("Name", text: $newProjectName)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 100)
                            .onSubmit { commitNewProject() }

                        Button {
                            commitNewProject()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            projects.isCreatingGroup = false
                            newProjectName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 8)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            projects.isCreatingGroup = true
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("New project group")
                }

                actionButtons
                    .padding(.trailing, 8)
            }
            Divider().opacity(0.5)
        }
        .background(.bar.opacity(0.6))
        // Inline rename alert
        .alert("Rename Project", isPresented: Binding(
            get: { editingProjectId != nil },
            set: { if !$0 { editingProjectId = nil } }
        )) {
            TextField("Project name", text: $editingProjectName)
            Button("Cancel", role: .cancel) { editingProjectId = nil }
            Button("Rename") {
                if let id = editingProjectId {
                    projects.renameGroup(id: id, name: editingProjectName)
                }
                editingProjectId = nil
            }
        } message: {
            Text("Enter a new name for the project.")
        }
    }

    private func projectChip(name: String, color: Color, isSelected: Bool, count: Int? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(name)
                    .font(.caption.weight(isSelected ? .bold : .medium))
                    .lineLimit(1)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? color : .secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(color.opacity(isSelected ? 0.18 : 0.08)))
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isSelected ? color.opacity(0.14) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }

    @ViewBuilder
    private func projectContextMenu(for group: ProjectGroup) -> some View {
        Button {
            editingProjectName = group.name
            editingProjectId = group.id
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Menu("Color") {
            ForEach(ProjectGroupModel.huePresets, id: \.1) { name, hue in
                Button {
                    projects.setGroupColor(id: group.id, hue: hue)
                } label: {
                    Label(name, systemImage: group.colorHue == hue ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            projects.deleteGroup(id: group.id)
        } label: {
            Label("Delete Project", systemImage: "trash")
        }
    }

    private func commitNewProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        projects.createGroup(name: name)
        newProjectName = ""
        projects.isCreatingGroup = false
    }

    /// Main title filters row with actions on the right.
    private var actionButtons: some View {
        HStack(spacing: 2) {
            Button {
                if notepad.pads.isEmpty {
                    notepad.openNewPad()
                }
                openWindow(id: "notepad")
            } label: {
                Image(systemName: "note.text")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .frame(minWidth: 24, minHeight: 24)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help("Open notepad")
            .accessibilityLabel("Open notepad")

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    hideResponses.toggle()
                }
            } label: {
                Image(systemName: hideResponses ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hideResponses ? .orange.opacity(0.9) : .secondary.opacity(0.7))
                    .frame(minWidth: 24, minHeight: 24)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help(hideResponses ? "Show agent responses" : "Hide agent responses — request only")
            .accessibilityLabel(hideResponses ? "Show responses" : "Hide responses")

            Button {
                showClearConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.8))
                    .frame(minWidth: 24, minHeight: 24)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.delete, modifiers: [.command])
            .help("Clear all notifications")
            .accessibilityLabel("Clear all notifications")
        }
    }

    private var filterBar: some View {
        HStack(alignment: .center, spacing: 6) {
            if showTypeFilters {
                ForEach(NoticeTitleFilter.allCases) { option in
                    filterChip(for: option)
                }
            } else if !agentSessionTabs.isEmpty {
                inlineSessionTabs
            }
        }
        .padding(.horizontal, PanelLayout.windowPaddingH)
        .padding(.top, PanelLayout.windowPaddingTop)
        .padding(.bottom, filterBarBottomPadding)
    }

    /// Extra space under chips when the Terminal tools row is shown so it doesn’t crowd the WINID controls.
    private var filterBarBottomPadding: CGFloat {
        if titleFilter == .terminal { return PanelLayout.sectionGap }
        return agentSessionTabs.isEmpty ? 6 : 2
    }

    private var trimmedManualTerminalWinid: String {
        manualTerminalWinid.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var terminalWinidEntryBar: some View {
        Group {
            if titleFilter == .terminal {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Manual WINID", systemImage: "apple.terminal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)

                    HStack(alignment: .center, spacing: 8) {
                        ManualWinidTextField(
                            text: $manualTerminalWinid,
                            placeholder: "Paste or type WINID",
                            onSubmit: addTerminalTrigger
                        )
                        .frame(minHeight: 26)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ViewThatFits(in: .horizontal) {
                            Button("Add Switch Trigger", action: addTerminalTrigger)
                            Button("Add trigger", action: addTerminalTrigger)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.regular)
                        .disabled(trimmedManualTerminalWinid.isEmpty)
                        .fixedSize(horizontal: true, vertical: false)
                    }

                    Divider()
                        .opacity(0.5)

                    HStack(alignment: .center, spacing: 8) {
                        Label("New Terminal", systemImage: "plus.rectangle.on.rectangle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Toggle("Auto", isOn: $initTerminalAutoMode)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                            .help("Auto-accept: claude uses --dangerously-skip-permissions, cursor uses --force.")

                        Spacer()

                        Button {
                            Task { await model.initNewTerminal() }
                        } label: {
                            Label("Terminal", systemImage: "terminal")
                        }
                        .help("Open a plain Terminal window.")

                        Button {
                            let cmd = initTerminalAutoMode
                                ? "claude --dangerously-skip-permissions"
                                : "claude"
                            Task { await model.initNewTerminal(chainCommand: cmd) }
                        } label: {
                            Label("Claude Code", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        .help(initTerminalAutoMode
                            ? "Open Terminal and start Claude Code with --dangerously-skip-permissions."
                            : "Open Terminal and start a Claude Code session.")

                        Button {
                            let cmd = initTerminalAutoMode
                                ? "cursor agent --force"
                                : "cursor agent"
                            Task { await model.initNewTerminal(chainCommand: cmd) }
                        } label: {
                            Label("Cursor Agent", systemImage: "cursorarrow.rays")
                        }
                        .help(initTerminalAutoMode
                            ? "Open Terminal and start Cursor agent with --force."
                            : "Open Terminal and start a Cursor agent session.")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, PanelLayout.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: PanelLayout.cardCorner, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PanelLayout.cardCorner, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.22), lineWidth: 1)
                )
                .padding(.horizontal, PanelLayout.windowPaddingH)
                .padding(.bottom, agentSessionTabs.isEmpty ? 6 : 2)
                .zIndex(1)
            }
        }
    }

    /// Session tab capsules — reused inline (collapsed) and standalone (expanded).
    private var sessionTabsContent: some View {
        ForEach(agentSessionTabs) { tab in
            let isSelected = selectedAgentSessionId == tab.sessionKey
            let color = tab.sourceKind.tintColor
            HStack(spacing: 0) {
                Button {
                    selectedAgentSessionId = tab.sessionKey
                    model.openWinidSession(tab.openAction)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.sourceKind.iconName)
                            .font(.caption2)
                        Text("#\(tab.index)")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                        Text(tab.label)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        sessionProjectDots(for: tab.sessionKey)
                    }
                    .foregroundStyle(isSelected ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help("Switch agent — focus Terminal for this target.")
                .accessibilityLabel("Switch agent #\(tab.index): \(tab.label)")

                Button {
                    sessionPendingClose = tab
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .frame(width: 16, height: 16)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close session — remove from monitor")
                .accessibilityLabel("Close session #\(tab.index)")
            }
            .padding(.leading, 7)
            .padding(.trailing, 3)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isSelected ? color.opacity(0.14) : Color.primary.opacity(0.04))
            )
            .contentShape(Capsule())
            .opacity(sessionTabOpacity(tab: tab, isSelected: isSelected))
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .draggable(tab.sessionKey)
            .contextMenu { sessionProjectMenu(for: tab) }
        }
    }

    /// Inline session tabs shown in the filter bar when type filters are collapsed.
    private var inlineSessionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 8) {
                sessionTabsContent
            }
            .animation(.easeInOut(duration: 0.12), value: selectedAgentSessionId)
        }
    }

    /// Agent/session switch tabs row — only shown when type filters are expanded.
    private var agentSessionTabBar: some View {
        Group {
            if showTypeFilters && !agentSessionTabs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: 8) {
                        sessionTabsContent
                    }
                    .animation(.easeInOut(duration: 0.12), value: selectedAgentSessionId)
                    .padding(.vertical, 2)
                    .padding(.horizontal, PanelLayout.windowPaddingH)
                }
                .frame(minHeight: 28)
                .padding(.bottom, 4)
            }
        }
        .alert("Close this session?", isPresented: Binding(
            get: { sessionPendingClose != nil },
            set: { if !$0 { sessionPendingClose = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                sessionPendingClose = nil
            }
            Button("Close", role: .destructive) {
                if let tab = sessionPendingClose {
                    if selectedAgentSessionId == tab.sessionKey {
                        selectedAgentSessionId = nil
                    }
                    model.closeWinidSession(tab.openAction)
                }
                sessionPendingClose = nil
            }
        } message: {
            if let tab = sessionPendingClose {
                Text("All notifications for session #\(tab.index) (\(tab.label)) will be removed and its WINID unregistered.")
            }
        }
    }

    @ViewBuilder
    private var switchStatusBar: some View {
        switch model.switchStatus {
        case .idle:
            EmptyView()
        case .switching(let id):
            switchStatusLabel(
                icon: "arrow.triangle.2.circlepath",
                text: "Switching to \(id)…",
                color: .secondary,
                spinning: true
            )
        case .succeeded(let id):
            switchStatusLabel(
                icon: "checkmark.circle.fill",
                text: "Switched to \(id)",
                color: .green,
                spinning: false
            )
        case .failed(let msg):
            switchStatusLabel(
                icon: "exclamationmark.triangle.fill",
                text: msg,
                color: .orange,
                spinning: false
            )
        }
    }

    private func switchStatusLabel(icon: String, text: String, color: Color, spinning: Bool) -> some View {
        HStack(spacing: 5) {
            if spinning {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            } else {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
            }
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, PanelLayout.windowPaddingH)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: model.switchStatus)
    }


    private static func shortSessionId(_ id: String) -> String {
        if id.count > 14 {
            return String(id.prefix(8)) + "\u{2026}" + String(id.suffix(4))
        }
        return id
    }

    private func filterChip(for option: NoticeTitleFilter) -> some View {
        let isActive = titleFilter == option
        let count = distinctSessionCount(for: option)
        let chipColor: Color = {
            switch option {
            case .cursor: return .purple
            case .claudeCode: return .mint
            case .terminal: return .orange
            }
        }()

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                titleFilter = isActive ? nil : option
            }
        } label: {
            HStack(spacing: 5) {
                Text(option.rawValue)
                    .font(.caption.weight(isActive ? .bold : .medium))

                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(isActive ? chipColor : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isActive ? chipColor.opacity(0.18) : Color.primary.opacity(0.06))
                    )
            }
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isActive ? chipColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityLabel("\(option.rawValue) filter, \(count) sessions")
    }

    /// Count only sessions assigned to this project that still have agent cards in the current items.
    private func activeSessionCount(for group: ProjectGroup) -> Int {
        let currentSessionKeys = Set(model.items.compactMap { Self.normalizedSessionId($0.action) })
        return group.sessionKeys.filter { currentSessionKeys.contains($0) }.count
    }

    private func distinctSessionCount(for filter: NoticeTitleFilter?) -> Int {
        let items = model.items.filter { notice in
            Self.matchesTitleFilter(notice, filter) && projects.matchesSelectedProject(notice)
        }
        let ids = items.compactMap { Self.normalizedSessionId($0.action) }
        return Set(ids).count
    }

    /// Items filtered by title only (no project filter) — used for session tabs so they're always visible for drag-and-drop.
    private var titleFilteredItems: [Notice] {
        model.items.filter { Self.matchesTitleFilter($0, titleFilter) }
    }

    /// Session tabs built from title-filtered items (ignoring project filter) so all sessions
    /// remain visible and draggable even when a project is selected.
    private var agentSessionTabs: [AgentSessionTab] {
        var latest: [String: Notice] = [:]
        for n in titleFilteredItems {
            guard let sid = Self.normalizedSessionId(n.action) else { continue }
            if let ex = latest[sid] {
                if n.at > ex.at { latest[sid] = n }
            } else {
                latest[sid] = n
            }
        }
        let pairs = latest.map { ($0.key, $0.value) }.sorted { $0.1.at > $1.1.at }
        return pairs.enumerated().map { idx, pair in
            let (sid, notice) = pair
            let open = notice.action?.trimmingCharacters(in: .whitespacesAndNewlines) ?? sid
            return AgentSessionTab(
                sessionKey: sid,
                openAction: open,
                label: Self.agentTabLabel(for: notice, sessionId: sid),
                index: idx + 1,
                sourceKind: Self.sourceKind(for: notice)
            )
        }
    }

    private static func sourceKind(for notice: Notice) -> AgentSourceKind {
        if titleMatchesCursor(notice.title) { return .cursor }
        if titleMatchesClaudeCode(notice.title) { return .claudeCode }
        if titleMatchesTerminal(notice.title) { return .terminal }
        return .other
    }

    /// Changes when filtered rows or their sessions change so tab selection can be validated.
    private var agentSessionTabSignature: String {
        let parts = titleFilteredItems.map { row -> String in
            let sid = Self.normalizedSessionId(row.action) ?? "-"
            return "\(sid):\(row.id.uuidString):\(row.at.timeIntervalSince1970)"
        }
        return parts.sorted().joined(separator: "|")
    }

    private static func agentTabLabel(for notice: Notice, sessionId: String) -> String {
        let t = notice.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty {
            return t.count > 30 ? String(t.prefix(27)) + "…" : t
        }
        if sessionId.count > 14 {
            return String(sessionId.prefix(8)) + "…" + String(sessionId.suffix(4))
        }
        return sessionId
    }

    private var filteredItems: [Notice] {
        model.items.filter { notice in
            Self.matchesTitleFilter(notice, titleFilter) && projects.matchesSelectedProject(notice)
        }
    }

    private static func normalizedSessionId(_ action: String?) -> String? {
        guard let a = action?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty else { return nil }
        return a
    }

    private static func matchesTitleFilter(_ notice: Notice, _ filter: NoticeTitleFilter?) -> Bool {
        guard let filter else { return true }
        switch filter {
        case .cursor:
            return titleMatchesCursor(notice.title)
        case .claudeCode:
            return titleMatchesClaudeCode(notice.title)
        case .terminal:
            return titleMatchesTerminal(notice.title)
        }
    }

    /// Title is treated as Cursor when it includes “cursor” (case- and diacritic-insensitive).
    private static func titleMatchesCursor(_ title: String) -> Bool {
        title.localizedStandardContains("cursor")
    }

    /// Title is treated as Claude Code when it includes “claude code”, or compact “claudecode”.
    private static func titleMatchesClaudeCode(_ title: String) -> Bool {
        if title.localizedStandardContains("claude code") { return true }
        let compact = title.replacingOccurrences(of: " ", with: "")
        return compact.localizedStandardContains("claudecode")
    }

    private static func titleMatchesTerminal(_ title: String) -> Bool {
        title.localizedStandardContains("terminal")
    }

    private func addTerminalTrigger() {
        let winid = trimmedManualTerminalWinid
        guard !winid.isEmpty else { return }
        manualTerminalWinid = ""
        Task {
            await model.upsertManualTerminalTrigger(winid)
        }
    }

    /// Dims session tabs that don't belong to the selected project, helping the user see which ones to drag.
    private func sessionTabOpacity(tab: AgentSessionTab, isSelected: Bool) -> Double {
        if selectedAgentSessionId != nil && !isSelected { return 0.6 }
        guard let group = projects.selectedGroup else { return 1.0 }
        return group.sessionKeys.contains(tab.sessionKey) ? 1.0 : 0.5
    }

    @ViewBuilder
    private func sessionProjectMenu(for tab: AgentSessionTab) -> some View {
        if !projects.groups.isEmpty {
            Menu("Assign to Project") {
                ForEach(projects.groups) { group in
                    let isMember = group.sessionKeys.contains(tab.sessionKey)
                    Button {
                        projects.toggleSession(tab.sessionKey, in: group.id)
                    } label: {
                        Label(group.name, systemImage: isMember ? "checkmark.circle.fill" : "circle")
                    }
                }
            }

            let memberGroups = projects.groupsContaining(session: tab.sessionKey)
            if !memberGroups.isEmpty {
                Menu("Remove from Project") {
                    ForEach(memberGroups) { group in
                        Button {
                            projects.removeSession(tab.sessionKey, from: group.id)
                        } label: {
                            Label(group.name, systemImage: "minus.circle")
                        }
                    }
                }
            }
        }
    }

    /// Small colored dots next to session tabs showing which projects they belong to.
    @ViewBuilder
    private func sessionProjectDots(for sessionKey: String) -> some View {
        let memberGroups = projects.groupsContaining(session: sessionKey)
        if !memberGroups.isEmpty {
            HStack(spacing: 1) {
                ForEach(memberGroups.prefix(3)) { group in
                    Circle()
                        .fill(group.color)
                        .frame(width: 5, height: 5)
                }
            }
        }
    }

    private var subtitleLine: String {
        model.serverRunning
            ? "Hook and API events show up here as they arrive."
            : "Starting…"
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.medium)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .padding(.horizontal, PanelLayout.windowPaddingH)
        .padding(.bottom, 4)
    }

    private var agentCardList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PanelLayout.listRowGap) {
                    if filteredItems.isEmpty {
                        if titleFilter == nil && projects.selectedGroupId == nil && model.items.isEmpty {
                            emptyState
                        } else {
                            filterEmptyState
                        }
                    } else {
                        ForEach(filteredItems) { item in
                            AgentCard(notice: item, selectedSessionId: selectedAgentSessionId, hideResponse: hideResponses, showPreviewPopover: $showPreviewPopover)
                        }
                    }
                }
                .padding(.horizontal, PanelLayout.windowPaddingH)
                .padding(.bottom, PanelLayout.windowPaddingBottom)
            }
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("No notifications yet")
                    .font(.headline)
                Text("When something sends you an update, it will show up in this list.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: PanelLayout.cardCorner, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [7, 5]))
                .foregroundStyle(.quaternary.opacity(0.9))
        )
        .background(
            RoundedRectangle(cornerRadius: PanelLayout.cardCorner, style: .continuous)
                .fill(Color.primary.opacity(0.02))
        )
    }

    private var filterEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text(filterEmptyTitle)
                .font(.headline)
            Text(filterEmptySubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }

    private var filterEmptyTitle: String {
        if projects.selectedGroupId != nil && titleFilter == nil {
            return "No sessions in this project"
        }
        switch titleFilter {
        case .none: return ""
        case .cursor: return "No Cursor titles"
        case .claudeCode: return "No Claude Code titles"
        case .terminal: return "No Terminal switch targets"
        }
    }

    private var filterEmptySubtitle: String {
        if let group = projects.selectedGroup, titleFilter == nil {
            return "Drag session tabs onto the \"\(group.name)\" project chip above to assign them."
        }
        switch titleFilter {
        case .none: return ""
        case .cursor:
            return "No row’s title contains Cursor. Choose All or Claude Code, or wait for new events."
        case .claudeCode:
            return "No row’s title contains Claude Code. Choose All or Cursor, or wait for new events."
        case .terminal:
            return "Add a WINID above to create a manual Terminal switch trigger."
        }
    }
}

private struct ManualWinidTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.isBordered = true
        field.drawsBackground = true
        field.focusRingType = .default
        field.lineBreakMode = .byTruncatingMiddle
        field.maximumNumberOfLines = 1
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        context.coordinator.text = $text
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        let onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
            let movement = notification.userInfo?["NSTextMovement"] as? Int
            if movement == NSTextMovement.return.rawValue {
                onSubmit()
            }
        }
    }
}

// MARK: - MarkdownUI Theme

extension MarkdownUI.Theme {
    static let agmPanel = Theme()
        .text {
            FontSize(13)
            ForegroundColor(.primary)
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(16)
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(14)
                }
                .markdownMargin(top: 6, bottom: 3)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(13)
                }
                .markdownMargin(top: 4, bottom: 2)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(11.5)
                    }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .markdownMargin(top: 4, bottom: 4)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(12)
            BackgroundColor(.primary.opacity(0.06))
        }
        .blockquote { configuration in
            configuration.label
                .markdownTextStyle {
                    ForegroundColor(.secondary)
                    FontSize(12.5)
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 3)
                }
                .markdownMargin(top: 4, bottom: 4)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
        .paragraph { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
}

private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.easeInOut(duration: 0.15)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 0.15)) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(copied ? .green : .secondary.opacity(0.6))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy to clipboard")
    }
}

private struct AgentCard: View {
    @EnvironmentObject private var model: PanelModel
    let notice: Notice
    let selectedSessionId: String?
    var hideResponse: Bool = false
    @Binding var showPreviewPopover: Bool

    private var isCurrentAgent: Bool {
        guard let selected = selectedSessionId,
              let action = notice.action?.trimmingCharacters(in: .whitespacesAndNewlines),
              !action.isEmpty else { return false }
        return action == selected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if switchAction != nil {
                    Button {
                        if let action = switchAction {
                            model.openWinidSession(action)
                        }
                    } label: {
                        Image(systemName: "arrow.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let action = switchAction {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(action, forType: .string)
                    } label: {
                        Text(String(action.prefix(8)))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help("Copy session ID")
                }

                Spacer(minLength: 4)

                if isCurrentAgent {
                    cardPreview
                }
            }

                Text(Self.format(notice.at))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.quaternary)

            if let s = Self.displayableSource(notice.source) {
                Text(s)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.mint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.mint.opacity(0.12), in: Capsule())
            }

            if hideResponse {
                if let request = requestOnlyText {
                    Text(request)
                        .font(.callout)
                        .lineSpacing(3)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .padding(.trailing, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.035))
                        )
                        .overlay(alignment: .topTrailing) {
                            CopyButton(text: request)
                                .padding(4)
                        }
                }
            } else {
                if let request = requestText {
                    Text(request)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(6)
                        .padding(.trailing, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            CopyButton(text: request)
                                .padding(2)
                        }
                }

                responseSection
            }
        }
        .padding(PanelLayout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: PanelLayout.cardCorner, style: .continuous)
                .fill(.quaternary.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PanelLayout.cardCorner, style: .continuous)
                .strokeBorder(
                    isCurrentAgent ? Color.mint.opacity(0.72) : Color.clear,
                    lineWidth: 1.35
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: PanelLayout.cardCorner, style: .continuous))
    }

    @ViewBuilder
    private var cardPreview: some View {
        switch model.previewStatus {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.7)
        case .loaded(_):
            if let image = model.previewImage {
                Button {
                    showPreviewPopover.toggle()
                } label: {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .help("Show window preview")
                .popover(isPresented: $showPreviewPopover, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Window Preview")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                if let action = switchAction {
                                    model.captureWindowPreview(sessionId: action)
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Refresh preview")
                        }
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 420, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                    }
                    .padding(10)
                }

                Button {
                    showPreviewPopover = false
                    model.clearPreview()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Dismiss preview")
            }
        case .notFound(_):
            Image(systemName: "eye.slash")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help("Window not found")
        case .permissionNeeded:
            Image(systemName: "lock.shield")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help("Screen Recording permission required")
        }
    }

    /// Hook-internal labels like "Stop" are omitted — they clutter the list without helping the user.
    private static func displayableSource(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.compare("Stop", options: .caseInsensitive) == .orderedSame { return nil }
        return s
    }

    private var responseText: String {
        Self.displayableText(notice.summary) ?? notice.body
    }

    private var switchAction: String? {
        Self.displayableText(notice.action)
    }

    private var responseSection: some View {
        Markdown(Self.formatResponseForDisplay(responseText))
            .markdownTheme(.agmPanel)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(alignment: .topTrailing) {
                CopyButton(text: responseText)
                    .padding(4)
            }
    }

    private var requestText: String? {
        guard let request = Self.displayableText(notice.request) else { return nil }
        if request == responseText { return nil }
        return request
    }

    /// Request text without the duplicate-suppression against response (used when response is hidden).
    private var requestOnlyText: String? {
        Self.displayableText(notice.request)
    }

    private static func displayableText(_ raw: String?) -> String? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// Normalizes line endings / blank lines; if the payload is JSON, pretty-prints inside a ```json fence for markdown rendering.
    private static func formatResponseForDisplay(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return raw }

        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        let leading = text
        if let fenced = prettyJSONAsMarkdownFence(leading) {
            return fenced
        }

        if Self.looksLikeLooseJSONLines(leading) {
            return wrapLooseJSONLinesAsMarkdownList(leading)
        }

        return leading
    }

    private static func prettyJSONAsMarkdownFence(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = t.first, c == "{" || c == "[" else { return nil }
        guard let data = t.data(using: .utf8) else { return nil }
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            return nil
        }
        let out: Data
        do {
            out = try JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            return nil
        }
        guard let s = String(data: out, encoding: .utf8) else { return nil }
        return "```json\n" + s + "\n```"
    }

    /// Heuristic: several lines that each parse as JSON objects (e.g. NDJSON-ish hook dumps).
    private static func looksLikeLooseJSONLines(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return false }
        var jsonLines = 0
        for line in lines {
            guard let d = line.data(using: .utf8) else { continue }
            if (try? JSONSerialization.jsonObject(with: d)) != nil {
                jsonLines += 1
            }
        }
        return jsonLines >= max(2, lines.count / 2)
    }

    private static func wrapLooseJSONLinesAsMarkdownList(_ text: String) -> String {
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var blocks: [String] = []
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            }
            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
                  let s = String(data: pretty, encoding: .utf8)
            else {
                blocks.append(trimmed)
                continue
            }
            blocks.append("```json\n" + s + "\n```")
        }
        return blocks.joined(separator: "\n\n")
    }

    private static func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}

#Preview {
    ContentView()
        .environmentObject(PanelModel())
        .environmentObject(NotepadModel())
        .environmentObject(ProjectGroupModel())
}
