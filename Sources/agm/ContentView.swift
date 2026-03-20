import AppKit
import Foundation
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
    case all = "All"
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
    @State private var showClearConfirmation = false
    @State private var titleFilter: NoticeTitleFilter = .all
    @State private var selectedAgentSessionId: String?
    @State private var manualTerminalWinid = ""
    @State private var hideResponses = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterBar
            terminalWinidEntryBar
            agentSessionTabBar
            if let err = model.lastError {
                errorBanner(err)
            }
            listSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 480, minHeight: 520)
        .background(backgroundGradient)
        .onChange(of: titleFilter) { _, _ in
            selectedAgentSessionId = nil
        }
        .onChange(of: agentSessionTabSignature) { _, _ in
            if let s = selectedAgentSessionId,
               !Set(filteredItems.compactMap { Self.normalizedSessionId($0.action) }).contains(s) {
                selectedAgentSessionId = nil
            }
        }
        .alert("Clear all notifications?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task { await model.clearListFromUI() }
            }
        } message: {
            Text("All items will be removed from the list. This can’t be undone.")
        }
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

    /// Main title filters row with status dot and clear button on the right.
    private var filterBar: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(NoticeTitleFilter.allCases) { option in
                filterChip(for: option)
            }

            Spacer(minLength: 8)

            statusDot

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

    /// Agent/session switch tabs row.
    private var agentSessionTabBar: some View {
        Group {
            if !agentSessionTabs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: 8) {
                        ForEach(agentSessionTabs) { tab in
                            let isSelected = selectedAgentSessionId == tab.sessionKey
                            let color = tab.sourceKind.tintColor
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
                                }
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? color.opacity(0.14) : Color.primary.opacity(0.04))
                                )
                            }
                            .buttonStyle(.plain)
                            .opacity(selectedAgentSessionId == nil || isSelected ? 1.0 : 0.6)
                            .animation(.easeInOut(duration: 0.15), value: isSelected)
                            .help("Switch agent — focus Terminal for this target.")
                            .accessibilityLabel("Switch agent #\(tab.index): \(tab.label)")
                            .contentShape(Capsule())
                        }
                    }
                    .animation(.easeInOut(duration: 0.12), value: selectedAgentSessionId)
                    .padding(.vertical, 2)
                    .padding(.horizontal, PanelLayout.windowPaddingH)
                }
                .frame(minHeight: 28)
                .padding(.bottom, 4)
            }
        }
    }

    private func filterChip(for option: NoticeTitleFilter) -> some View {
        let isActive = titleFilter == option
        let count = distinctSessionCount(for: option)
        let chipColor: Color = {
            switch option {
            case .all: return .mint
            case .cursor: return .purple
            case .claudeCode: return .mint
            case .terminal: return .orange
            }
        }()

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                titleFilter = option
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

    private func distinctSessionCount(for filter: NoticeTitleFilter) -> Int {
        let items = model.items.filter { Self.matchesTitleFilter($0, filter) }
        let ids = items.compactMap { Self.normalizedSessionId($0.action) }
        return Set(ids).count
    }

    private var agentSessionTabs: [AgentSessionTab] {
        var latest: [String: Notice] = [:]
        for n in filteredItems {
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
        let parts = filteredItems.map { row -> String in
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
        model.items.filter { Self.matchesTitleFilter($0, titleFilter) }
    }

    private static func normalizedSessionId(_ action: String?) -> String? {
        guard let a = action?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty else { return nil }
        return a
    }

    private static func matchesTitleFilter(_ notice: Notice, _ filter: NoticeTitleFilter) -> Bool {
        switch filter {
        case .all:
            return true
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

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PanelLayout.listRowGap) {
                    if filteredItems.isEmpty {
                        if titleFilter == .all && model.items.isEmpty {
                            emptyState
                        } else {
                            filterEmptyState
                        }
                    } else {
                        ForEach(filteredItems) { item in
                            NoticeRow(notice: item, selectedSessionId: selectedAgentSessionId, hideResponse: hideResponses)
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
        switch titleFilter {
        case .all: return ""
        case .cursor: return "No Cursor titles"
        case .claudeCode: return "No Claude Code titles"
        case .terminal: return "No Terminal switch targets"
        }
    }

    private var filterEmptySubtitle: String {
        switch titleFilter {
        case .all: return ""
        case .cursor:
            return "No row’s title contains Cursor. Choose All or Claude Code, or wait for new events."
        case .claudeCode:
            return "No row’s title contains Claude Code. Choose All or Cursor, or wait for new events."
        case .terminal:
            return "Add a WINID above to create a manual Terminal switch trigger."
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(model.serverRunning ? Color.mint : Color.orange.opacity(0.9))
            .frame(width: 7, height: 7)
            .shadow(color: (model.serverRunning ? Color.mint : Color.orange).opacity(0.45), radius: 2)
            .accessibilityLabel(model.serverRunning ? "Ready" : "Starting")
            .help(model.serverRunning ? "Server is ready" : "Starting…")
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

private struct NoticeRow: View {
    @EnvironmentObject private var model: PanelModel
    let notice: Notice
    let selectedSessionId: String?
    var hideResponse: Bool = false

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

                if let action = switchAction {
                    Text(action)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 4)

                Text(Self.format(notice.at))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.quaternary)
            }

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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.035))
                        )
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
        .onTapGesture {
            guard let action = switchAction else { return }
            model.openWinidSession(action)
        }
        .help(switchAction == nil ? "" : "Click the card to switch agent and focus Terminal.")
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
        Text(Self.attributedMarkdown(Self.formatResponseForDisplay(responseText)))
            .font(.callout)
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
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

    private static func attributedMarkdown(_ string: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible
        if let parsed = try? AttributedString(markdown: string, options: options) {
            return parsed
        }
        return AttributedString(string)
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
}
