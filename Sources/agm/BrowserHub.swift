import Foundation

/// Fan-out for WebSocket clients (e.g. custom HTML dashboards).
actor BrowserHub {
    private var subscribers: [UUID: @Sendable (String) -> Void] = [:]

    @discardableResult
    func subscribe(_ push: @escaping @Sendable (String) -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = push
        return id
    }

    func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    func broadcast(_ text: String) {
        for send in subscribers.values {
            send(text)
        }
    }
}
