//
//  MCPWireParsingTests.swift
//  SprungTests
//
//  Covers Sprung/JobApplications/MCP/MCPStreamableHTTPClient.swift's transport
//  contract: SSE-framed ("event: message" / "data: {...}") vs plain-JSON
//  tool-call responses, JSON-RPC error-envelope surfacing, and malformed
//  payloads. The framer (`sseDataPayloads`) and id-matcher (`messageID`) are
//  `private static` to the actor, so there is no seam smaller than `callTool`
//  itself -- this drives it end-to-end through the `session:` initializer
//  parameter (already a DI seam, per the file's own doc comment about a
//  future OAuth header) wired to a stub `URLProtocol` instead of the network.
//  No production code is modified; the stub lives only in this test file.
//

import XCTest
@testable import Sprung

// MARK: - URLProtocol stub

/// Routes JSON-RPC requests by their `method` field to a canned response, so
/// a test can script the initialize handshake + a single `tools/call` round
/// trip without touching the network. Registered per-test via
/// `MCPMockURLProtocol.handlers` and consumed by a session built in
/// `MCPWireParsingTests.makeClient()`.
final class MCPMockURLProtocol: URLProtocol {
    struct StubResponse {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    /// Keyed by JSON-RPC `method`. Receives the request's `id` (nil for the
    /// fire-and-forget `notifications/initialized` notification, which never
    /// carries one).
    static var handlers: [String: (Int?) -> StubResponse] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let bodyData = Self.extractBody(from: request)
        let envelope = bodyData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let method = envelope?["method"] as? String ?? ""
        let id = envelope?["id"] as? Int
        let stub = Self.handlers[method]?(id) ?? StubResponse(statusCode: 500, headers: [:], body: Data())
        var headers = stub.headers
        if headers["Content-Type"] == nil { headers["Content-Type"] = "application/json" }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: MCPClientError.malformedResponse("stub could not build a response"))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// `URLProtocol` frequently receives `httpBodyStream` instead of
    /// `httpBody` once a request has passed through `URLSession` -- read
    /// whichever is present.
    private static func extractBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: bufferSize)
            guard bytesRead > 0 else { break }
            data.append(buffer, count: bytesRead)
        }
        return data
    }
}

final class MCPWireParsingTests: XCTestCase {

    private let endpoint = URL(string: "https://mock.mcp.test/mcp")!

    override func tearDown() {
        MCPMockURLProtocol.handlers = [:]
        super.tearDown()
    }

    private func makeClient() -> MCPStreamableHTTPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MCPMockURLProtocol.self]
        let session = URLSession(configuration: config)
        return MCPStreamableHTTPClient(endpoint: endpoint, session: session)
    }

    /// Wires a generic successful `initialize` handshake (echoing whatever id
    /// the client sent) plus the fire-and-forget notification response; only
    /// `tools/call` is scripted per test.
    private func installHandshake() {
        MCPMockURLProtocol.handlers["initialize"] = { id in
            let body = "{\"jsonrpc\":\"2.0\",\"id\":\(id ?? 1),\"result\":{}}".data(using: .utf8)!
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        MCPMockURLProtocol.handlers["notifications/initialized"] = { _ in
            .init(statusCode: 200, headers: [:], body: Data())
        }
    }

    // MARK: - SSE framing

    func testSSEFramedSingleLineDataDecodesToolResult() async throws {
        installHandshake()
        MCPMockURLProtocol.handlers["tools/call"] = { id in
            let sse = [
                "event: message",
                "data: {\"jsonrpc\":\"2.0\",\"id\":\(id ?? 0),\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"hello world\"}]}}",
                ""
            ].joined(separator: "\n")
            return .init(statusCode: 200, headers: ["Content-Type": "text/event-stream"], body: sse.data(using: .utf8)!)
        }
        let client = makeClient()
        let result = try await client.callTool(name: "search_jobs", arguments: [:])
        XCTAssertEqual(result.textBlocks, ["hello world"])
        XCTAssertEqual(result.firstText, "hello world")
        XCTAssertNil(result.structuredContent)
    }

    func testSSEFramedMultiLineDataJoinsWithNewline() async throws {
        installHandshake()
        MCPMockURLProtocol.handlers["tools/call"] = { id in
            // The JSON payload is split across two `data:` lines at a token
            // boundary (never inside a string literal -- a raw newline inside
            // a JSON string is illegal); joining with "\n" must reconstitute
            // valid JSON.
            let sse = [
                "event: message",
                "data: {\"jsonrpc\":\"2.0\",\"id\":\(id ?? 0),\"result\":{\"content\":[{\"type\":\"text\",",
                "data: \"text\":\"combined value\"}]}}",
                ""
            ].joined(separator: "\n")
            return .init(statusCode: 200, headers: ["Content-Type": "text/event-stream"], body: sse.data(using: .utf8)!)
        }
        let client = makeClient()
        let result = try await client.callTool(name: "search_jobs", arguments: [:])
        XCTAssertEqual(result.textBlocks, ["combined value"],
                       "multi-line `data:` fields within one SSE event must join with \\n before JSON parsing")
    }

    func testSSEMultipleEventsPicksPayloadMatchingRequestId() async throws {
        installHandshake()
        MCPMockURLProtocol.handlers["tools/call"] = { id in
            // An unrelated event (mismatched id) precedes the real response;
            // the client must scan every SSE-framed payload for the match,
            // not just take the first.
            let sse = [
                "event: ping",
                "data: {\"jsonrpc\":\"2.0\",\"id\":999,\"result\":{}}",
                "",
                "event: message",
                "data: {\"jsonrpc\":\"2.0\",\"id\":\(id ?? 0),\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"final\"}]}}",
                ""
            ].joined(separator: "\n")
            return .init(statusCode: 200, headers: ["Content-Type": "text/event-stream"], body: sse.data(using: .utf8)!)
        }
        let client = makeClient()
        let result = try await client.callTool(name: "search_jobs", arguments: [:])
        XCTAssertEqual(result.textBlocks, ["final"])
    }

    // MARK: - Plain JSON (non-SSE) responses

    func testPlainJSONResponseDecodesToolResultAndStructuredContent() async throws {
        installHandshake()
        MCPMockURLProtocol.handlers["tools/call"] = { id in
            let json = "{\"jsonrpc\":\"2.0\",\"id\":\(id ?? 0),\"result\":{\"content\":[],\"structuredContent\":{\"foo\":\"bar\"}}}"
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: json.data(using: .utf8)!)
        }
        let client = makeClient()
        let result = try await client.callTool(name: "search_jobs", arguments: [:])
        XCTAssertEqual(result.textBlocks, [])
        XCTAssertNil(result.firstText)
        XCTAssertEqual(result.structuredContent?["foo"] as? String, "bar")
    }

    // MARK: - JSON-RPC error envelope

    func testJSONRPCErrorEnvelopeSurfacesAsTypedError() async throws {
        installHandshake()
        MCPMockURLProtocol.handlers["tools/call"] = { id in
            let sse = [
                "event: message",
                "data: {\"jsonrpc\":\"2.0\",\"id\":\(id ?? 0),\"error\":{\"code\":-32602,\"message\":\"invalid params\"}}",
                ""
            ].joined(separator: "\n")
            return .init(statusCode: 200, headers: ["Content-Type": "text/event-stream"], body: sse.data(using: .utf8)!)
        }
        let client = makeClient()
        do {
            _ = try await client.callTool(name: "search_jobs", arguments: [:])
            XCTFail("expected MCPClientError.jsonRPCError to be thrown")
        } catch MCPClientError.jsonRPCError(let code, let message) {
            XCTAssertEqual(code, -32602)
            XCTAssertEqual(message, "invalid params")
        } catch {
            XCTFail("expected jsonRPCError, got \(error)")
        }
    }

    // MARK: - Malformed payloads / tool-level errors

    func testMissingResultObjectThrowsMalformedResponse() async throws {
        installHandshake()
        MCPMockURLProtocol.handlers["tools/call"] = { id in
            let json = "{\"jsonrpc\":\"2.0\",\"id\":\(id ?? 0)}"
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: json.data(using: .utf8)!)
        }
        let client = makeClient()
        do {
            _ = try await client.callTool(name: "search_jobs", arguments: [:])
            XCTFail("expected MCPClientError.malformedResponse to be thrown")
        } catch MCPClientError.malformedResponse(let detail) {
            XCTAssertTrue(detail.contains("no result object"), "unexpected detail: \(detail)")
        } catch {
            XCTFail("expected malformedResponse, got \(error)")
        }
    }

    func testNoResponseMatchingRequestIdThrowsMalformedResponse() async throws {
        installHandshake()
        MCPMockURLProtocol.handlers["tools/call"] = { _ in
            // Body carries a well-formed message, but its id (999) can never
            // match the client's actual request id.
            let json = "{\"jsonrpc\":\"2.0\",\"id\":999,\"result\":{}}"
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: json.data(using: .utf8)!)
        }
        let client = makeClient()
        do {
            _ = try await client.callTool(name: "search_jobs", arguments: [:])
            XCTFail("expected MCPClientError.malformedResponse to be thrown")
        } catch MCPClientError.malformedResponse(let detail) {
            XCTAssertTrue(detail.contains("no JSON-RPC response with id"), "unexpected detail: \(detail)")
        } catch {
            XCTFail("expected malformedResponse, got \(error)")
        }
    }

    func testToolErrorFlagThrowsToolErrorWithFirstTextBlock() async throws {
        installHandshake()
        MCPMockURLProtocol.handlers["tools/call"] = { id in
            let json = "{\"jsonrpc\":\"2.0\",\"id\":\(id ?? 0),\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"boom\"}],\"isError\":true}}"
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: json.data(using: .utf8)!)
        }
        let client = makeClient()
        do {
            _ = try await client.callTool(name: "search_jobs", arguments: [:])
            XCTFail("expected MCPClientError.toolError to be thrown")
        } catch MCPClientError.toolError(let message) {
            XCTAssertEqual(message, "boom")
        } catch {
            XCTFail("expected toolError, got \(error)")
        }
    }
}
