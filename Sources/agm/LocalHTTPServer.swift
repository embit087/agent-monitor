import FlyingFox
import FlyingSocks
import Foundation

private func authOK(_ request: HTTPRequest, secret: String?) async -> Bool {
    guard let secret, !secret.isEmpty else { return true }
    let bearer = request.headers[.authorization] ?? ""
    let token: String = if bearer.hasPrefix("Bearer ") {
        String(bearer.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
        ""
    }
    let q = request.query.first { $0.name == "token" }?.value ?? ""
    return token == secret || q == secret
}

private struct WSAuthGate: HTTPHandler {
    let secret: String?
    let inner: WebSocketHTTPHandler

    func handleRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard await authOK(request, secret: secret) else {
            return HTTPResponse(statusCode: .unauthorized, body: Data("unauthorized".utf8))
        }
        return try await inner.handleRequest(request)
    }
}

private struct NotifyWSHandler: WSMessageHandler {
    let hub: BrowserHub
    let itemCount: @Sendable () async -> Int

    func makeMessages(for client: AsyncStream<WSMessage>) async throws -> AsyncStream<WSMessage> {
        AsyncStream { continuation in
            let reg = Task {
                let subID = await hub.subscribe { text in
                    continuation.yield(.text(text))
                }
                let count = await itemCount()
                continuation.yield(.text(NoticeCodec.encodeReady(count: count)))
                for await _ in client {}
                await hub.unsubscribe(subID)
                continuation.finish()
            }
            continuation.onTermination = { _ in reg.cancel() }
        }
    }
}

private struct NotepadPayload: Decodable {
    var id: String?
    var title: String?
    var content: String?
    var language: String?
}

private struct PadsEnvelope: Encodable {
    var pads: [Pad]
}

enum LocalHTTPServer {
    private static let padEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static func run(
        port: UInt16,
        secret: String?,
        hub: BrowserHub,
        viewModel: PanelModel,
        notepad: NotepadModel
    ) async throws {
        // Use IPv4 loopback so hooks using `127.0.0.1` (not just `localhost` / ::1) can connect.
        let server = HTTPServer(address: try sockaddr_in.inet(ip4: "127.0.0.1", port: port))

        let wsInner: WebSocketHTTPHandler = .webSocket(
            NotifyWSHandler(hub: hub, itemCount: {
                await MainActor.run { viewModel.snapshotItems().count }
            })
        )
        let wsGated = WSAuthGate(secret: secret, inner: wsInner)

        await server.appendRoute("GET /api/health") { _ in
            let count = await MainActor.run { viewModel.snapshotItems().count }
            let body = Data("{\"ok\":true,\"items\":\(count)}".utf8)
            return HTTPResponse(
                statusCode: .ok,
                headers: [.contentType: "application/json"],
                body: body
            )
        }

        await server.appendRoute("GET /api/notifications") { _ in
            let list = await MainActor.run { viewModel.snapshotItems() }
            let data = try NoticeCodec.encodeList(list)
            return HTTPResponse(
                statusCode: .ok,
                headers: [.contentType: "application/json"],
                body: data
            )
        }

        await server.appendRoute("DELETE /api/notifications") { req in
            guard await authOK(req, secret: secret) else {
                let body = Data(#"{"error":"unauthorized"}"#.utf8)
                return HTTPResponse(
                    statusCode: .unauthorized,
                    headers: [.contentType: "application/json"],
                    body: body
                )
            }
            await MainActor.run { viewModel.applyClear() }
            await hub.broadcast(#"{"type":"clear"}"#)
            return HTTPResponse(
                statusCode: .ok,
                headers: [.contentType: "application/json"],
                body: Data(#"{"ok":true}"#.utf8)
            )
        }

        await server.appendRoute("POST /api/notify") { req in
            guard await authOK(req, secret: secret) else {
                let body = Data(#"{"error":"unauthorized"}"#.utf8)
                return HTTPResponse(
                    statusCode: .unauthorized,
                    headers: [.contentType: "application/json"],
                    body: body
                )
            }
            let data = try await req.bodyData
            let notice: Notice
            do {
                notice = try NoticeCodec.decodeNotifyBody(from: data)
            } catch {
                let body = Data(#"{"error":"invalid json"}"#.utf8)
                return HTTPResponse(
                    statusCode: .badRequest,
                    headers: [.contentType: "application/json"],
                    body: body
                )
            }
            await MainActor.run {
                viewModel.applyAppend(notice)
            }
            if let json = try? NoticeCodec.encodeNoticeEvent(notice) {
                await hub.broadcast(json)
            }
            let out = try NoticeCodec.encoder.encode(notice)
            return HTTPResponse(
                statusCode: .created,
                headers: [.contentType: "application/json"],
                body: out
            )
        }

        await server.appendRoute("GET /api/ws", to: wsGated)

        // MARK: Notepad routes

        await server.appendRoute("POST /api/notepad") { req in
            guard await authOK(req, secret: secret) else {
                return HTTPResponse(
                    statusCode: .unauthorized,
                    headers: [.contentType: "application/json"],
                    body: Data(#"{"error":"unauthorized"}"#.utf8)
                )
            }
            let data = try await req.bodyData
            let payload: NotepadPayload
            do {
                payload = try JSONDecoder().decode(NotepadPayload.self, from: data)
            } catch {
                return HTTPResponse(
                    statusCode: .badRequest,
                    headers: [.contentType: "application/json"],
                    body: Data(#"{"error":"invalid json"}"#.utf8)
                )
            }
            let pad = await MainActor.run {
                notepad.createPadAndOpen(
                    title: payload.title ?? "Untitled",
                    content: payload.content ?? "",
                    language: payload.language ?? "markdown"
                )
            }
            let out = try padEncoder.encode(pad)
            return HTTPResponse(
                statusCode: .created,
                headers: [.contentType: "application/json"],
                body: out
            )
        }

        await server.appendRoute("GET /api/notepad") { req in
            let idParam = req.query.first { $0.name == "id" }?.value
            if let idStr = idParam, let uuid = UUID(uuidString: idStr) {
                guard let pad = await MainActor.run(body: { notepad.pad(by: uuid) }) else {
                    return HTTPResponse(
                        statusCode: .notFound,
                        headers: [.contentType: "application/json"],
                        body: Data(#"{"error":"not found"}"#.utf8)
                    )
                }
                let out = try padEncoder.encode(pad)
                return HTTPResponse(
                    statusCode: .ok,
                    headers: [.contentType: "application/json"],
                    body: out
                )
            } else {
                let pads = await MainActor.run { notepad.pads }
                let out = try padEncoder.encode(PadsEnvelope(pads: pads))
                return HTTPResponse(
                    statusCode: .ok,
                    headers: [.contentType: "application/json"],
                    body: out
                )
            }
        }

        await server.appendRoute("PUT /api/notepad") { req in
            guard await authOK(req, secret: secret) else {
                return HTTPResponse(
                    statusCode: .unauthorized,
                    headers: [.contentType: "application/json"],
                    body: Data(#"{"error":"unauthorized"}"#.utf8)
                )
            }
            let data = try await req.bodyData
            let payload: NotepadPayload
            do {
                payload = try JSONDecoder().decode(NotepadPayload.self, from: data)
            } catch {
                return HTTPResponse(
                    statusCode: .badRequest,
                    headers: [.contentType: "application/json"],
                    body: Data(#"{"error":"invalid json"}"#.utf8)
                )
            }
            let idStr = payload.id ?? req.query.first(where: { $0.name == "id" })?.value
            guard let idStr, let uuid = UUID(uuidString: idStr) else {
                return HTTPResponse(
                    statusCode: .badRequest,
                    headers: [.contentType: "application/json"],
                    body: Data(#"{"error":"id required"}"#.utf8)
                )
            }
            let found = await MainActor.run { () -> Bool in
                guard notepad.pad(by: uuid) != nil else { return false }
                if let c = payload.content { notepad.updateContent(c, padId: uuid) }
                if let l = payload.language { notepad.updateLanguage(l, padId: uuid) }
                if let t = payload.title { notepad.updateTitle(t, padId: uuid) }
                return true
            }
            guard found else {
                return HTTPResponse(
                    statusCode: .notFound,
                    headers: [.contentType: "application/json"],
                    body: Data(#"{"error":"not found"}"#.utf8)
                )
            }
            return HTTPResponse(
                statusCode: .ok,
                headers: [.contentType: "application/json"],
                body: Data(#"{"ok":true}"#.utf8)
            )
        }

        await server.appendRoute("DELETE /api/notepad") { req in
            guard await authOK(req, secret: secret) else {
                return HTTPResponse(
                    statusCode: .unauthorized,
                    headers: [.contentType: "application/json"],
                    body: Data(#"{"error":"unauthorized"}"#.utf8)
                )
            }
            let idStr = req.query.first(where: { $0.name == "id" })?.value
            guard let idStr, let uuid = UUID(uuidString: idStr) else {
                return HTTPResponse(
                    statusCode: .badRequest,
                    headers: [.contentType: "application/json"],
                    body: Data(#"{"error":"id required"}"#.utf8)
                )
            }
            await MainActor.run { notepad.deletePad(id: uuid) }
            return HTTPResponse(
                statusCode: .ok,
                headers: [.contentType: "application/json"],
                body: Data(#"{"ok":true}"#.utf8)
            )
        }

        await MainActor.run {
            viewModel.markServerListening()
        }
        fputs("notify-panel http://127.0.0.1:\(port)/\n", stderr)
        try await server.run()
    }
}
