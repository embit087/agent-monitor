import AppKit
import CoreGraphics

/// Captures a preview screenshot of a window identified by a saved winid session.
/// Reads `~/.winids/<id>` metadata, matches it to a live CGWindowID, and captures the image.
enum WindowPreviewCapture {

    struct WinidMetadata {
        let appName: String
        let bundleId: String
        let winName: String
        let tty: String?
    }

    enum CaptureResult {
        case image(NSImage)
        case windowNotFound
        case permissionDenied
        case noMetadata
    }

    // MARK: - Public API

    static func capturePreview(sessionId: String) -> CaptureResult {
        guard let metadata = readWinidFile(sessionId: sessionId) else {
            return .noMetadata
        }
        guard let windowNumber = findWindowNumber(for: metadata) else {
            return .windowNotFound
        }
        return captureWindow(windowNumber: windowNumber)
    }

    // MARK: - Winid file parsing

    static func readWinidFile(sessionId: String) -> WinidMetadata? {
        let path = NSHomeDirectory() + "/.winids/" + sessionId
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        var fields: [String: String] = [:]
        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let str = String(line)
            guard let eqIdx = str.firstIndex(of: "=") else { continue }
            let key = String(str[str.startIndex..<eqIdx])
            let val = String(str[str.index(after: eqIdx)...])
            fields[key] = val
        }
        guard let appName = fields["app_name"], !appName.isEmpty,
              let bundleId = fields["bundle_id"],
              let winName = fields["win_name"]
        else { return nil }

        return WinidMetadata(
            appName: appName,
            bundleId: bundleId,
            winName: winName,
            tty: fields["tty"]
        )
    }

    // MARK: - Window matching via CGWindowListCopyWindowInfo

    static func findWindowNumber(for metadata: WinidMetadata) -> CGWindowID? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let candidates = buildTitleCandidates(metadata.winName)

        // First pass: exact owner match + title contains candidate
        for candidate in candidates {
            for entry in windowList {
                guard let ownerName = entry[kCGWindowOwnerName as String] as? String,
                      ownerName == metadata.appName,
                      let windowName = entry[kCGWindowName as String] as? String,
                      let windowNum = entry[kCGWindowNumber as String] as? CGWindowID
                else { continue }

                if windowName.localizedStandardContains(candidate) {
                    return windowNum
                }
            }
        }

        // Fallback: any normal-layer window from the same owner app
        for entry in windowList {
            guard let ownerName = entry[kCGWindowOwnerName as String] as? String,
                  ownerName == metadata.appName,
                  let windowNum = entry[kCGWindowNumber as String] as? CGWindowID,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer == 0
            else { continue }
            return windowNum
        }

        return nil
    }

    /// Progressively shorter title candidates for fuzzy matching.
    /// Strips trailing dimension suffixes (e.g. "122x44") and em-dash segments.
    private static func buildTitleCandidates(_ fullTitle: String) -> [String] {
        var results: [String] = []
        func add(_ s: String) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !results.contains(trimmed) else { return }
            results.append(trimmed)
        }

        add(fullTitle)

        // em dash = \u{2014}
        let parts = fullTitle.components(separatedBy: " \u{2014} ")

        // Strip trailing dimension like "122\u{00d7}44" or "122x44"
        if let last = parts.last,
           last.range(of: #"^\d+[×x]\d+$"#, options: .regularExpression) != nil {
            let withoutDim = Array(parts.dropLast())
            add(withoutDim.joined(separator: " \u{2014} "))
            if withoutDim.count >= 2 {
                add(Array(withoutDim.dropLast()).joined(separator: " \u{2014} "))
            }
        }

        if parts.count >= 2 {
            add(parts[0..<min(2, parts.count)].joined(separator: " \u{2014} "))
        }
        if parts.count >= 1 {
            add(parts[0])
        }

        return results
    }

    // MARK: - Image capture

    private static func captureWindow(windowNumber: CGWindowID) -> CaptureResult {
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowNumber,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return .permissionDenied
        }

        if isBlankImage(cgImage) {
            return .permissionDenied
        }

        let fullSize = NSSize(
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        )
        let nsImage = NSImage(cgImage: cgImage, size: fullSize)
        return .image(nsImage)
    }

    /// Heuristic: sample pixels; if all alpha == 0, the image is blank (permission denied).
    private static func isBlankImage(_ image: CGImage) -> Bool {
        guard image.width > 0, image.height > 0 else { return true }
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              CFDataGetLength(data) > 0
        else { return true }
        let ptr = CFDataGetBytePtr(data)!
        let bytesPerPixel = image.bitsPerPixel / 8
        guard bytesPerPixel >= 4 else { return false }
        let totalPixels = image.width * image.height
        let step = max(1, totalPixels / 20)
        for i in stride(from: 0, to: totalPixels, by: step) {
            let offset = i * bytesPerPixel
            let alphaOffset = (image.alphaInfo == .premultipliedFirst || image.alphaInfo == .first) ? 0 : 3
            if ptr[offset + alphaOffset] > 0 { return false }
        }
        return true
    }
}
