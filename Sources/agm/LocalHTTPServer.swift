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

enum LocalHTTPServer {
    static func run(
        port: UInt16,
        secret: String?,
        hub: BrowserHub,
        viewModel: PanelModel
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

        await MainActor.run {
            viewModel.markServerListening()
        }
        fputs("notify-panel http://127.0.0.1:\(port)/\n", stderr)
        try await server.run()
    }
}
