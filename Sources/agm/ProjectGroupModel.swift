import Foundation
import SwiftUI

// MARK: - Data

struct ProjectGroup: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var colorHue: Double          // 0…1
    var sessionKeys: Set<String>  // normalized notice.action values
    var createdAt: Date

    var color: Color { Color(hue: colorHue, saturation: 0.45, brightness: 0.65) }
}

// MARK: - Model

@MainActor
final class ProjectGroupModel: ObservableObject {
    @Published var groups: [ProjectGroup] = []
    @Published var selectedGroupId: UUID?
    @Published var isCreatingGroup = false

    private let storageURL: URL

    init() {
        let base: URL
        if let prefix = ProcessInfo.processInfo.environment["AGM_PREFIX"] {
            base = URL(fileURLWithPath: prefix, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agm")
        }
        storageURL = base.appendingPathComponent("projects.json")
        load()
    }

    // MARK: Palette

    /// Preset hues for quick color picking.
    static let huePresets: [(String, Double)] = [
        ("Red",     0.0),
        ("Orange",  0.08),
        ("Yellow",  0.13),
        ("Green",   0.35),
        ("Teal",    0.48),
        ("Blue",    0.6),
        ("Indigo",  0.7),
        ("Purple",  0.78),
        ("Pink",    0.92),
    ]

    /// Next hue that hasn't been used, or cycles through presets.
    private var nextHue: Double {
        let used = Set(groups.map { $0.colorHue })
        for (_, hue) in Self.huePresets where !used.contains(hue) {
            return hue
        }
        return Self.huePresets[groups.count % Self.huePresets.count].1
    }

    // MARK: CRUD

    func createGroup(name: String, hue: Double? = nil) {
        let group = ProjectGroup(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHue: hue ?? nextHue,
            sessionKeys: [],
            createdAt: .now
        )
        groups.append(group)
        save()
    }

    func deleteGroup(id: UUID) {
        if selectedGroupId == id { selectedGroupId = nil }
        groups.removeAll { $0.id == id }
        save()
    }

    func renameGroup(id: UUID, name: String) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func setGroupColor(id: UUID, hue: Double) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].colorHue = hue
        save()
    }

    // MARK: Session assignment

    func addSession(_ sessionKey: String, to groupId: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == groupId }) else { return }
        // Remove from any other project first — a session belongs to one project only.
        for i in groups.indices where groups[i].id != groupId {
            groups[i].sessionKeys.remove(sessionKey)
        }
        groups[idx].sessionKeys.insert(sessionKey)
        save()
    }

    func removeSession(_ sessionKey: String, from groupId: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[idx].sessionKeys.remove(sessionKey)
        save()
    }

    func toggleSession(_ sessionKey: String, in groupId: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == groupId }) else { return }
        if groups[idx].sessionKeys.contains(sessionKey) {
            groups[idx].sessionKeys.remove(sessionKey)
        } else {
            // Remove from any other project first — a session belongs to one project only.
            for i in groups.indices where groups[i].id != groupId {
                groups[i].sessionKeys.remove(sessionKey)
            }
            groups[idx].sessionKeys.insert(sessionKey)
        }
        save()
    }

    /// Returns groups that contain a given session key.
    func groupsContaining(session sessionKey: String) -> [ProjectGroup] {
        groups.filter { $0.sessionKeys.contains(sessionKey) }
    }

    // MARK: Filtering

    /// The currently selected group, if any.
    var selectedGroup: ProjectGroup? {
        guard let id = selectedGroupId else { return nil }
        return groups.first { $0.id == id }
    }

    /// Returns true if the notice belongs to the selected project (or no project is selected).
    func matchesSelectedProject(_ notice: Notice) -> Bool {
        guard let group = selectedGroup else { return true }
        guard let action = notice.action?.trimmingCharacters(in: .whitespacesAndNewlines),
              !action.isEmpty else { return false }
        return group.sessionKeys.contains(action)
    }

    // MARK: Persistence

    private func save() {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(groups)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[ProjectGroupModel] save failed: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            groups = try JSONDecoder().decode([ProjectGroup].self, from: data)
        } catch {
            print("[ProjectGroupModel] load failed: \(error)")
        }
    }
}
