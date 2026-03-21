import Foundation

struct Pad: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var content: String
    var language: String
    var createdAt: Date
    var updatedAt: Date

    static func make(
        title: String = "Untitled",
        content: String = "",
        language: String = "markdown"
    ) -> Pad {
        let now = Date()
        return Pad(
            id: UUID(),
            title: title.isEmpty ? "Untitled" : String(title.prefix(200)),
            content: String(content.prefix(500_000)),
            language: language.isEmpty ? "plaintext" : language,
            createdAt: now,
            updatedAt: now
        )
    }
}

/// Cursor position reported by the Monaco editor.
struct CursorInfo: Equatable {
    var line: Int = 1
    var column: Int = 1
}

/// Editor-level settings that apply to the Monaco instance.
struct EditorSettings: Equatable {
    var wordWrap: Bool = true
    var minimap: Bool = false
    var fontSize: Int = 13
    var showLineNumbers: Bool = true

    static let fontSizeRange = 10...24
}

@MainActor
final class NotepadModel: ObservableObject {
    @Published var pads: [Pad] = []
    @Published var activePadId: UUID?
    /// Incremented to signal that the notepad window should open (used by API triggers).
    @Published var openTrigger: Int = 0

    // MARK: - Status bar state (updated by Monaco bridge)
    @Published var cursor: CursorInfo = CursorInfo()
    @Published var wordCount: Int = 0
    @Published var charCount: Int = 0
    @Published var lineCount: Int = 1
    @Published var selectionLength: Int = 0

    // MARK: - Editor settings
    @Published var editorSettings: EditorSettings = EditorSettings()
    /// Incremented when settings change so the Monaco bridge can react.
    @Published var settingsRevision: Int = 0

    var activePad: Pad? {
        guard let id = activePadId else { return nil }
        return pads.first { $0.id == id }
    }

    /// Creates a new pad and makes it active. Does NOT trigger window open.
    @discardableResult
    func openNewPad(title: String = "Untitled", content: String = "", language: String = "markdown") -> Pad {
        let pad = Pad.make(title: title, content: content, language: language)
        pads.insert(pad, at: 0)
        activePadId = pad.id
        return pad
    }

    /// Creates a new pad AND signals the window to open (for API / hook triggers).
    @discardableResult
    func createPadAndOpen(title: String = "Untitled", content: String = "", language: String = "markdown") -> Pad {
        let pad = openNewPad(title: title, content: content, language: language)
        openTrigger += 1
        return pad
    }

    func selectPad(id: UUID) {
        guard pads.contains(where: { $0.id == id }) else { return }
        activePadId = id
    }

    func updateContent(_ content: String, padId: UUID? = nil) {
        let targetId = padId ?? activePadId
        guard let idx = pads.firstIndex(where: { $0.id == targetId }) else { return }
        pads[idx].content = String(content.prefix(500_000))
        pads[idx].updatedAt = Date()
    }

    func updateLanguage(_ language: String, padId: UUID? = nil) {
        let targetId = padId ?? activePadId
        guard let idx = pads.firstIndex(where: { $0.id == targetId }) else { return }
        pads[idx].language = language
        pads[idx].updatedAt = Date()
    }

    func updateTitle(_ title: String, padId: UUID? = nil) {
        let targetId = padId ?? activePadId
        guard let idx = pads.firstIndex(where: { $0.id == targetId }) else { return }
        pads[idx].title = title.isEmpty ? "Untitled" : String(title.prefix(200))
        pads[idx].updatedAt = Date()
    }

    func deletePad(id: UUID) {
        pads.removeAll { $0.id == id }
        if activePadId == id {
            activePadId = pads.first?.id
        }
    }

    func pad(by id: UUID) -> Pad? {
        pads.first { $0.id == id }
    }

    // MARK: - Status updates from Monaco

    func updateCursor(line: Int, column: Int) {
        cursor = CursorInfo(line: line, column: column)
    }

    func updateStats(words: Int, chars: Int, lines: Int, selection: Int) {
        wordCount = words
        charCount = chars
        lineCount = lines
        selectionLength = selection
    }

    // MARK: - Editor setting toggles

    func toggleWordWrap() {
        editorSettings.wordWrap.toggle()
        settingsRevision += 1
    }

    func toggleMinimap() {
        editorSettings.minimap.toggle()
        settingsRevision += 1
    }

    func toggleLineNumbers() {
        editorSettings.showLineNumbers.toggle()
        settingsRevision += 1
    }

    func adjustFontSize(by delta: Int) {
        let newSize = editorSettings.fontSize + delta
        editorSettings.fontSize = min(max(newSize, EditorSettings.fontSizeRange.lowerBound),
                                       EditorSettings.fontSizeRange.upperBound)
        settingsRevision += 1
    }

    // MARK: - Tab navigation

    func selectNextTab() {
        guard let id = activePadId,
              let idx = pads.firstIndex(where: { $0.id == id }),
              !pads.isEmpty else { return }
        let next = (idx + 1) % pads.count
        activePadId = pads[next].id
    }

    func selectPreviousTab() {
        guard let id = activePadId,
              let idx = pads.firstIndex(where: { $0.id == id }),
              !pads.isEmpty else { return }
        let prev = (idx - 1 + pads.count) % pads.count
        activePadId = pads[prev].id
    }

    func closeActiveTab() {
        guard let id = activePadId else { return }
        deletePad(id: id)
    }
}
