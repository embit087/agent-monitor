import SwiftUI
import WebKit

// MARK: - Layout constants

private enum NotepadLayout {
    static let tabBarHeight: CGFloat = 34
    static let toolbarHeight: CGFloat = 32
    static let statusBarHeight: CGFloat = 24
    static let tabMaxWidth: CGFloat = 140
    static let tabCorner: CGFloat = 6
    static let tabHPad: CGFloat = 10
    static let tabVPad: CGFloat = 5
}

// MARK: - NotepadView

struct NotepadView: View {
    @EnvironmentObject private var notepad: NotepadModel

    private static let languages: [(String, String)] = [
        ("markdown", "Markdown"),
        ("json", "JSON"),
        ("swift", "Swift"),
        ("python", "Python"),
        ("javascript", "JavaScript"),
        ("typescript", "TypeScript"),
        ("html", "HTML"),
        ("css", "CSS"),
        ("shell", "Shell"),
        ("yaml", "YAML"),
        ("xml", "XML"),
        ("sql", "SQL"),
        ("rust", "Rust"),
        ("go", "Go"),
        ("cpp", "C++"),
        ("c", "C"),
        ("java", "Java"),
        ("plaintext", "Plain Text"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            if notepad.activePad != nil {
                padTabBar
                Divider()
                editorToolbar
                Divider()
                MonacoEditorView(
                    content: Binding(
                        get: { notepad.activePad?.content ?? "" },
                        set: { notepad.updateContent($0) }
                    ),
                    language: Binding(
                        get: { notepad.activePad?.language ?? "markdown" },
                        set: { notepad.updateLanguage($0) }
                    ),
                    notepad: notepad
                )
                Divider()
                statusBar
            } else {
                emptyState
            }
        }
        .frame(minWidth: 500, minHeight: 350)
        .background(Color(nsColor: .windowBackgroundColor))
        // Keyboard shortcuts
        .keyboardShortcut(for: .newTab) { notepad.openNewPad() }
        .keyboardShortcut(for: .closeTab) { notepad.closeActiveTab() }
        .keyboardShortcut(for: .nextTab) { notepad.selectNextTab() }
        .keyboardShortcut(for: .prevTab) { notepad.selectPreviousTab() }
        .keyboardShortcut(for: .increaseFontSize) { notepad.adjustFontSize(by: 1) }
        .keyboardShortcut(for: .decreaseFontSize) { notepad.adjustFontSize(by: -1) }
    }

    // MARK: - Tab Bar

    private var padTabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(notepad.pads) { pad in
                        padTab(for: pad)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            }

            Spacer(minLength: 4)

            // Pad count
            if notepad.pads.count > 1 {
                Text("\(notepad.pads.count)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.06))
                    )
                    .padding(.trailing, 4)
            }

            Button {
                notepad.openNewPad()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New pad (⌘T)")
            .padding(.trailing, 8)
        }
        .frame(height: NotepadLayout.tabBarHeight)
        .background(.bar)
    }

    private func padTab(for pad: Pad) -> some View {
        let isActive = notepad.activePadId == pad.id
        return HStack(spacing: 4) {
            // Language icon
            languageIcon(for: pad.language)
                .font(.system(size: 9))
                .foregroundStyle(isActive ? .primary : .tertiary)

            Text(pad.title)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: NotepadLayout.tabMaxWidth)

            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    notepad.deletePad(id: pad.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isActive ? 1 : 0)
            .animation(.easeInOut(duration: 0.1), value: isActive)
        }
        .padding(.horizontal, NotepadLayout.tabHPad)
        .padding(.vertical, NotepadLayout.tabVPad)
        .background(
            RoundedRectangle(cornerRadius: NotepadLayout.tabCorner, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotepadLayout.tabCorner, style: .continuous)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.2) : Color.clear, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            notepad.selectPad(id: pad.id)
        }
    }

    // MARK: - Toolbar

    private var editorToolbar: some View {
        HStack(spacing: 6) {
            if let pad = notepad.activePad {
                // Title field
                TextField("Title", text: Binding(
                    get: { pad.title },
                    set: { notepad.updateTitle($0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .frame(maxWidth: 240)

                Spacer()

                // Editor toggles
                toolbarToggle(
                    icon: "text.word.spacing",
                    label: "Word Wrap",
                    isOn: notepad.editorSettings.wordWrap
                ) {
                    notepad.toggleWordWrap()
                }

                toolbarToggle(
                    icon: "sidebar.right",
                    label: "Minimap",
                    isOn: notepad.editorSettings.minimap
                ) {
                    notepad.toggleMinimap()
                }

                toolbarToggle(
                    icon: "list.number",
                    label: "Line Numbers",
                    isOn: notepad.editorSettings.showLineNumbers
                ) {
                    notepad.toggleLineNumbers()
                }

                Divider().frame(height: 16)

                // Font size controls
                HStack(spacing: 2) {
                    Button {
                        notepad.adjustFontSize(by: -1)
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                            .font(.system(size: 10))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Decrease font size (⌘-)")
                    .disabled(notepad.editorSettings.fontSize <= EditorSettings.fontSizeRange.lowerBound)

                    Text("\(notepad.editorSettings.fontSize)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    Button {
                        notepad.adjustFontSize(by: 1)
                    } label: {
                        Image(systemName: "textformat.size.larger")
                            .font(.system(size: 10))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Increase font size (⌘+)")
                    .disabled(notepad.editorSettings.fontSize >= EditorSettings.fontSizeRange.upperBound)
                }

                Divider().frame(height: 16)

                // Language picker
                Picker("", selection: Binding(
                    get: { pad.language },
                    set: { notepad.updateLanguage($0) }
                )) {
                    ForEach(Self.languages, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                // Copy all
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pad.content, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Copy all content")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: NotepadLayout.toolbarHeight)
        .background(Color.primary.opacity(0.02))
    }

    private func toolbarToggle(icon: String, label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isOn ? Color.accentColor.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 0) {
            // Cursor position
            HStack(spacing: 3) {
                Text("Ln \(notepad.cursor.line)")
                    .help("Line number")
                Text(":")
                    .foregroundStyle(.quaternary)
                Text("Col \(notepad.cursor.column)")
                    .help("Column number")
            }

            statusSeparator

            // Selection info (show only when there's a selection)
            if notepad.selectionLength > 0 {
                Text("\(notepad.selectionLength) selected")
                    .foregroundStyle(.secondary)
                statusSeparator
            }

            // Line count
            Text("\(notepad.lineCount) lines")
                .help("Total lines")

            statusSeparator

            // Word count
            Text("\(notepad.wordCount) words")
                .help("Word count")

            statusSeparator

            // Char count
            Text("\(notepad.charCount) chars")
                .help("Character count")

            Spacer()

            // Language badge
            if let pad = notepad.activePad {
                let langLabel = Self.languages.first(where: { $0.0 == pad.language })?.1 ?? pad.language
                Text(langLabel)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.accentColor.opacity(0.08))
                    )

                statusSeparator

                Text("UTF-8")
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: NotepadLayout.statusBarHeight)
        .background(.bar)
    }

    private var statusSeparator: some View {
        Text("·")
            .foregroundStyle(.quaternary)
            .padding(.horizontal, 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.quaternary)

            VStack(spacing: 6) {
                Text("No pads open")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Create a new pad to start writing")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            Button("New Pad") {
                notepad.openNewPad()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            // Quick-start language grid
            VStack(spacing: 8) {
                Text("Quick start")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                HStack(spacing: 8) {
                    quickStartButton("Swift", icon: "swift", lang: "swift")
                    quickStartButton("Python", icon: "chevron.left.forwardslash.chevron.right", lang: "python")
                    quickStartButton("JSON", icon: "curlybraces", lang: "json")
                    quickStartButton("Shell", icon: "terminal", lang: "shell")
                    quickStartButton("Markdown", icon: "doc.richtext", lang: "markdown")
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func quickStartButton(_ label: String, icon: String, lang: String) -> some View {
        Button {
            notepad.openNewPad(title: label, language: lang)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .light))
                    .frame(height: 20)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .frame(width: 64, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func languageIcon(for lang: String) -> Image {
        switch lang {
        case "swift": return Image(systemName: "swift")
        case "python": return Image(systemName: "chevron.left.forwardslash.chevron.right")
        case "javascript", "typescript": return Image(systemName: "j.square")
        case "html", "xml": return Image(systemName: "chevron.left.slash.chevron.right")
        case "css": return Image(systemName: "paintbrush")
        case "json": return Image(systemName: "curlybraces")
        case "shell": return Image(systemName: "terminal")
        case "sql": return Image(systemName: "tablecells")
        case "markdown": return Image(systemName: "doc.richtext")
        case "yaml": return Image(systemName: "list.bullet.indent")
        case "rust": return Image(systemName: "gearshape.2")
        case "go": return Image(systemName: "arrow.right")
        case "c", "cpp": return Image(systemName: "c.square")
        case "java": return Image(systemName: "cup.and.saucer")
        default: return Image(systemName: "doc.text")
        }
    }
}

// MARK: - Keyboard Shortcut Helper

private enum NotepadShortcut {
    case newTab, closeTab, nextTab, prevTab, increaseFontSize, decreaseFontSize
}

private extension View {
    func keyboardShortcut(for shortcut: NotepadShortcut, action: @escaping () -> Void) -> some View {
        switch shortcut {
        case .newTab:
            return AnyView(self.background(
                Button("") { action() }
                    .keyboardShortcut("t", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
            ))
        case .closeTab:
            return AnyView(self.background(
                Button("") { action() }
                    .keyboardShortcut("w", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
            ))
        case .nextTab:
            return AnyView(self.background(
                Button("") { action() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .frame(width: 0, height: 0)
                    .opacity(0)
            ))
        case .prevTab:
            return AnyView(self.background(
                Button("") { action() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .frame(width: 0, height: 0)
                    .opacity(0)
            ))
        case .increaseFontSize:
            return AnyView(self.background(
                Button("") { action() }
                    .keyboardShortcut("+", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
            ))
        case .decreaseFontSize:
            return AnyView(self.background(
                Button("") { action() }
                    .keyboardShortcut("-", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
            ))
        }
    }
}

// MARK: - Monaco Editor (WKWebView)

struct MonacoEditorView: NSViewRepresentable {
    @Binding var content: String
    @Binding var language: String
    @ObservedObject var notepad: NotepadModel
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let uc = config.userContentController
        uc.add(context.coordinator, name: "ready")
        uc.add(context.coordinator, name: "contentChanged")
        uc.add(context.coordinator, name: "cursorChanged")
        uc.add(context.coordinator, name: "statsChanged")

        let prefs = config.preferences
        prefs.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView

        webView.loadHTMLString(Self.monacoHTML, baseURL: URL(string: "https://cdn.jsdelivr.net"))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let c = context.coordinator
        c.parent = self
        let theme = colorScheme == .dark ? "vs-dark" : "vs"

        guard c.isEditorReady else {
            c.pendingContent = content
            c.pendingLanguage = language
            c.pendingTheme = theme
            c.pendingSettings = notepad.editorSettings
            return
        }

        if content != c.lastSentContent {
            c.lastSentContent = content
            webView.evaluateJavaScript("setContent(\(Self.jsLiteral(content)))")
        }
        if language != c.lastSentLanguage {
            c.lastSentLanguage = language
            webView.evaluateJavaScript("setLanguage(\(Self.jsLiteral(language)))")
        }
        if theme != c.lastSentTheme {
            c.lastSentTheme = theme
            webView.evaluateJavaScript("setTheme(\(Self.jsLiteral(theme)))")
        }

        // Push editor settings when they change
        let s = notepad.editorSettings
        if s != c.lastSentSettings {
            c.lastSentSettings = s
            let js = "applySettings({wordWrap:\(s.wordWrap ? "'on'" : "'off'"),minimap:\(s.minimap),fontSize:\(s.fontSize),lineNumbers:\(s.showLineNumbers ? "'on'" : "'off'")})"
            webView.evaluateJavaScript(js)
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: MonacoEditorView
        weak var webView: WKWebView?
        var isEditorReady = false
        var lastSentContent = ""
        var lastSentLanguage = ""
        var lastSentTheme = ""
        var lastSentSettings = EditorSettings()
        var pendingContent: String?
        var pendingLanguage: String?
        var pendingTheme: String?
        var pendingSettings: EditorSettings?

        init(parent: MonacoEditorView) { self.parent = parent }

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "ready":
                isEditorReady = true
                applyPending()
            case "contentChanged":
                guard let text = message.body as? String else { return }
                lastSentContent = text
                parent.content = text
            case "cursorChanged":
                guard let dict = message.body as? [String: Any],
                      let line = dict["line"] as? Int,
                      let col = dict["column"] as? Int else { return }
                Task { @MainActor in
                    parent.notepad.updateCursor(line: line, column: col)
                }
            case "statsChanged":
                guard let dict = message.body as? [String: Any],
                      let words = dict["words"] as? Int,
                      let chars = dict["chars"] as? Int,
                      let lines = dict["lines"] as? Int,
                      let sel = dict["selection"] as? Int else { return }
                Task { @MainActor in
                    parent.notepad.updateStats(words: words, chars: chars, lines: lines, selection: sel)
                }
            default:
                break
            }
        }

        private func applyPending() {
            if let c = pendingContent {
                lastSentContent = c
                webView?.evaluateJavaScript("setContent(\(MonacoEditorView.jsLiteral(c)))")
                pendingContent = nil
            }
            if let l = pendingLanguage {
                lastSentLanguage = l
                webView?.evaluateJavaScript("setLanguage(\(MonacoEditorView.jsLiteral(l)))")
                pendingLanguage = nil
            }
            if let t = pendingTheme {
                lastSentTheme = t
                webView?.evaluateJavaScript("setTheme(\(MonacoEditorView.jsLiteral(t)))")
                pendingTheme = nil
            }
            if let s = pendingSettings {
                lastSentSettings = s
                let js = "applySettings({wordWrap:\(s.wordWrap ? "'on'" : "'off'"),minimap:\(s.minimap),fontSize:\(s.fontSize),lineNumbers:\(s.showLineNumbers ? "'on'" : "'off'")})"
                webView?.evaluateJavaScript(js)
                pendingSettings = nil
            }
        }
    }

    // MARK: Helpers

    static func jsLiteral(_ str: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: str, options: .fragmentsAllowed),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json
    }

    // MARK: Monaco HTML

    static let monacoHTML: String = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
    *{margin:0;padding:0;box-sizing:border-box}
    html,body{width:100vw;height:100vh;overflow:hidden;background:transparent}
    #editor{position:absolute;top:0;left:0;right:0;bottom:0}
    .monaco-editor .line-numbers{font-size:11px !important;opacity:0.45}
    #loading{position:absolute;top:0;left:0;right:0;bottom:0;
             display:flex;align-items:center;justify-content:center;
             color:#888;font:13px/1.4 -apple-system,system-ui,sans-serif;
             flex-direction:column;gap:8px}
    .spinner{width:20px;height:20px;border:2px solid #555;border-top-color:#aaa;
             border-radius:50%;animation:spin .7s linear infinite}
    @keyframes spin{to{transform:rotate(360deg)}}
    </style>
    </head>
    <body>
    <div id="loading"><div class="spinner"></div>Loading editor…</div>
    <div id="editor" style="display:none"></div>
    <script src="https://cdn.jsdelivr.net/npm/monaco-editor@0.52.2/min/vs/loader.js"></script>
    <script>
    require.config({paths:{vs:'https://cdn.jsdelivr.net/npm/monaco-editor@0.52.2/min/vs'}});

    var editor=null,suppressChange=false,statsTimer=null;

    function countWords(text){
      if(!text||!text.trim())return 0;
      return text.trim().split(/\\s+/).length;
    }

    function reportStats(){
      if(!editor)return;
      var m=editor.getModel();
      if(!m)return;
      var text=m.getValue();
      var sel=editor.getSelection();
      var selLen=0;
      if(sel&&!sel.isEmpty()){selLen=m.getValueInRange(sel).length;}
      window.webkit.messageHandlers.statsChanged.postMessage({
        words:countWords(text),
        chars:text.length,
        lines:m.getLineCount(),
        selection:selLen
      });
    }

    function scheduleStats(){
      if(statsTimer)clearTimeout(statsTimer);
      statsTimer=setTimeout(reportStats,120);
    }

    require(['vs/editor/editor.main'],function(){
      document.getElementById('loading').style.display='none';
      var el=document.getElementById('editor');
      el.style.display='block';

      editor=monaco.editor.create(el,{
        value:'',
        language:'markdown',
        theme:window.matchMedia('(prefers-color-scheme:dark)').matches?'vs-dark':'vs',
        minimap:{enabled:false},
        automaticLayout:true,
        fontSize:13,
        lineHeight:20,
        wordWrap:'on',
        renderWhitespace:'selection',
        scrollBeyondLastLine:false,
        scrollBeyondLastColumn:5,
        padding:{top:8,bottom:8},
        bracketPairColorization:{enabled:true},
        tabSize:2,
        smoothScrolling:true,
        cursorBlinking:'smooth',
        cursorSmoothCaretAnimation:'on',
        formatOnPaste:true,
        suggestOnTriggerCharacters:true,
        lineNumbers:'on',
        lineNumbersMinChars:3,
        lineDecorationsWidth:2,
        renderLineHighlight:'none',
        roundedSelection:true,
        links:true,
        colorDecorators:true,
        guides:{bracketPairs:true,indentation:true},
        stickyScroll:{enabled:false},
        overviewRulerBorder:false,
        overviewRulerLanes:0,
        hideCursorInOverviewRuler:true,
        scrollbar:{vertical:'auto',horizontal:'auto',
                   verticalScrollbarSize:10,horizontalScrollbarSize:10,
                   verticalSliderSize:6,horizontalSliderSize:6,
                   useShadows:false,
                   alwaysConsumeMouseWheel:false},
      });

      // Cursor position reporting
      editor.onDidChangeCursorPosition(function(e){
        window.webkit.messageHandlers.cursorChanged.postMessage({
          line:e.position.lineNumber,
          column:e.position.column
        });
      });

      // Content change reporting
      editor.onDidChangeModelContent(function(){
        if(suppressChange)return;
        window.webkit.messageHandlers.contentChanged.postMessage(editor.getValue());
        scheduleStats();
      });

      // Selection change reporting
      editor.onDidChangeCursorSelection(function(){
        scheduleStats();
      });

      window.webkit.messageHandlers.ready.postMessage('ok');

      // Initial stats after a beat
      setTimeout(reportStats,200);
    });

    function setContent(text){
      if(!editor)return;
      suppressChange=true;
      editor.setValue(text);
      suppressChange=false;
      setTimeout(reportStats,50);
    }
    function setLanguage(lang){
      if(!editor)return;
      monaco.editor.setModelLanguage(editor.getModel(),lang);
    }
    function setTheme(t){
      if(!editor)return;
      monaco.editor.setTheme(t);
    }
    function getContent(){return editor?editor.getValue():'';}

    function applySettings(s){
      if(!editor)return;
      var opts={};
      if(s.wordWrap!==undefined)opts.wordWrap=s.wordWrap;
      if(s.minimap!==undefined)opts.minimap={enabled:s.minimap};
      if(s.fontSize!==undefined)opts.fontSize=s.fontSize;
      if(s.lineNumbers!==undefined)opts.lineNumbers=s.lineNumbers;
      editor.updateOptions(opts);
    }
    </script>
    </body>
    </html>
    """
}
