//
//  MCPStreamableHTTPClient.swift
//  Sprung
//
//  Minimal JSON-RPC 2.0 client for MCP servers speaking the Streamable HTTP
//  transport: every message is a POST to a single endpoint, and responses may
//  come back either as plain JSON or SSE-framed ("event: message" / "data: {…}")
//  even for single JSON-RPC responses. No LLM is involved anywhere — tool calls
//  are deterministic queries. An optional Authorization header slot supports a
//  future OAuth-protected board; both Dice and ZipRecruiter's public servers
//  require none.
//

import Foundation

/// Errors surfaced by `MCPStreamableHTTPClient`, typed so callers can present
/// transport, protocol, and tool failures distinctly.
enum MCPClientError: LocalizedError {
    case httpError(statusCode: Int, body: String)
    case malformedResponse(String)
    case jsonRPCError(code: Int, message: String)
    case toolError(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let statusCode, let body):
            return "MCP server returned HTTP \(statusCode): \(body.prefix(200))"
        case .malformedResponse(let detail):
            return "Malformed MCP response: \(detail)"
        case .jsonRPCError(let code, let message):
            return "MCP error \(code): \(message)"
        case .toolError(let message):
            return "MCP tool failed: \(message)"
        }
    }
}

/// The decoded result of a `tools/call` request.
struct MCPToolResult {
    /// Text content blocks in order (`result.content[].text` where `type == "text"`).
    let textBlocks: [String]
    /// Optional structured mirror of the text content (`result.structuredContent`).
    let structuredContent: [String: Any]?

    var firstText: String? { textBlocks.first }
}

actor MCPStreamableHTTPClient {
    private static let protocolVersion = "2025-03-26"

    private let endpoint: URL
    private let session: URLSession
    /// Sent verbatim as the `Authorization` header when present (e.g.
    /// "Bearer <token>" for a future OAuth-protected server). Neither Dice nor
    /// ZipRecruiter needs one.
    private let authorizationHeader: String?
    /// Per-request `timeoutInterval`. Dice/ZipRecruiter keep the 30 s default;
    /// the LinkedIn board passes 180 because its server drives a real browser
    /// per call (and a cold start is slower still).
    private let requestTimeout: TimeInterval

    private var nextRequestID = 1
    private var isInitialized = false
    /// Session id issued by stateful servers via the `Mcp-Session-Id` response
    /// header on initialize; echoed on subsequent requests when present.
    /// Stateless servers (Dice, ZipRecruiter) never issue one — absence is not
    /// an error.
    private var sessionID: String?

    init(
        endpoint: URL,
        authorizationHeader: String? = nil,
        session: URLSession = .shared,
        requestTimeout: TimeInterval = 30
    ) {
        self.endpoint = endpoint
        self.authorizationHeader = authorizationHeader
        self.session = session
        self.requestTimeout = requestTimeout
    }

    // MARK: - Public API

    /// Call an MCP tool, performing the initialize handshake first if needed.
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        try await ensureInitialized()
        let requestID = takeRequestID()
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": "tools/call",
            "params": ["name": name, "arguments": arguments]
        ]
        let (message, _) = try await postExpectingResponse(envelope, id: requestID)
        guard let result = message["result"] as? [String: Any] else {
            throw MCPClientError.malformedResponse("tools/call response has no result object")
        }
        let contentBlocks = result["content"] as? [[String: Any]] ?? []
        let textBlocks = contentBlocks.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }
        if result["isError"] as? Bool == true {
            throw MCPClientError.toolError(textBlocks.first ?? "tool \(name) reported an error")
        }
        return MCPToolResult(
            textBlocks: textBlocks,
            structuredContent: result["structuredContent"] as? [String: Any]
        )
    }

    // MARK: - Handshake

    private func ensureInitialized() async throws {
        guard !isInitialized else { return }
        let requestID = takeRequestID()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": "initialize",
            "params": [
                "protocolVersion": Self.protocolVersion,
                "capabilities": [String: Any](),
                "clientInfo": ["name": "Sprung", "version": appVersion ?? "unknown"]
            ]
        ]
        let (message, http) = try await postExpectingResponse(envelope, id: requestID)
        guard message["result"] is [String: Any] else {
            throw MCPClientError.malformedResponse("initialize response has no result object")
        }
        sessionID = http.value(forHTTPHeaderField: "Mcp-Session-Id")
        isInitialized = true
        await sendInitializedNotification()
    }

    /// Per spec the client follows initialize with a `notifications/initialized`
    /// notification. Fire-and-forget: a failure is logged, never fatal — the
    /// handshake itself already succeeded.
    private func sendInitializedNotification() async {
        let envelope: [String: Any] = ["jsonrpc": "2.0", "method": "notifications/initialized"]
        do {
            _ = try await post(envelope)
        } catch {
            Logger.warning("⚠️ [MCP] initialized notification failed: \(error.localizedDescription)", category: .networking)
        }
    }

    // MARK: - Transport

    private func takeRequestID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    /// POST a JSON-RPC envelope and return the raw response bytes + HTTP metadata.
    private func post(_ envelope: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: envelope)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MCPClientError.malformedResponse("non-HTTP response from \(endpoint.absoluteString)")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MCPClientError.httpError(statusCode: http.statusCode, body: body)
        }
        return (data, http)
    }

    /// POST a request envelope and extract the JSON-RPC response message whose
    /// `id` matches, unwrapping SSE framing when the server uses it. Throws a
    /// typed error when the message carries a JSON-RPC `error` object.
    private func postExpectingResponse(_ envelope: [String: Any], id: Int) async throws -> ([String: Any], HTTPURLResponse) {
        let (data, http) = try await post(envelope)
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        let candidatePayloads: [Data]
        if contentType.contains("text/event-stream") {
            candidatePayloads = Self.sseDataPayloads(in: data)
        } else {
            candidatePayloads = [data]
        }
        for payload in candidatePayloads {
            guard let message = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                  Self.messageID(of: message, matches: id) else {
                continue
            }
            if let errorObject = message["error"] as? [String: Any] {
                let code = errorObject["code"] as? Int ?? 0
                let text = errorObject["message"] as? String ?? "unknown JSON-RPC error"
                throw MCPClientError.jsonRPCError(code: code, message: text)
            }
            return (message, http)
        }
        throw MCPClientError.malformedResponse("no JSON-RPC response with id \(id) in body")
    }

    /// Match a response `id` whether the server echoes it as a number or string.
    private static func messageID(of message: [String: Any], matches id: Int) -> Bool {
        if let intID = message["id"] as? Int {
            return intID == id
        }
        if let stringID = message["id"] as? String {
            return stringID == String(id)
        }
        return false
    }

    /// Extract the `data:` payloads of every SSE event in `body`. Multi-line
    /// `data:` fields within one event are joined with newlines per the SSE spec;
    /// other fields (`event:`, `id:`, `retry:`, comments) carry no JSON-RPC payload.
    private static func sseDataPayloads(in body: Data) -> [Data] {
        guard let text = String(data: body, encoding: .utf8) else { return [] }
        var payloads: [String] = []
        var currentLines: [String] = []
        func flushEvent() {
            if !currentLines.isEmpty {
                payloads.append(currentLines.joined(separator: "\n"))
                currentLines = []
            }
        }
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : String(rawLine)
            if line.isEmpty {
                flushEvent() // blank line terminates an SSE event
            } else if line.hasPrefix("data:") {
                var value = String(line.dropFirst(5))
                if value.hasPrefix(" ") {
                    value = String(value.dropFirst())
                }
                currentLines.append(value)
            }
        }
        flushEvent()
        return payloads.compactMap { $0.data(using: .utf8) }
    }
}
