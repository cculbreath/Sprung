//
//  LinkedInMCPServerServiceTests.swift
//  SprungTests
//
//  Pure pieces of the LinkedIn MCP server lifecycle service: uvx discovery,
//  the pinned launch invocation, readiness-probe envelope/predicate, stderr
//  tail extraction, and the one-time consent flag (via TestDefaults — never
//  UserDefaults.standard). No test here spawns a process or touches the
//  network: `ensureRunning()` is exercised only at runtime.
//

import XCTest
@testable import Sprung

@MainActor
final class LinkedInMCPServerServiceTests: XCTestCase {

    // MARK: - uvx discovery

    func testLocateUVXPrefersFirstExistingFixedCandidate() {
        let path = LinkedInMCPServerService.locateUVX(
            fixedCandidates: ["/opt/homebrew/bin/uvx", "/usr/local/bin/uvx"],
            pathVariable: "/somewhere/bin",
            isExecutable: { $0 == "/usr/local/bin/uvx" || $0 == "/somewhere/bin/uvx" }
        )
        XCTAssertEqual(path, "/usr/local/bin/uvx", "fixed candidates outrank PATH entries")
    }

    func testLocateUVXFallsBackToPathSearchInOrder() {
        let path = LinkedInMCPServerService.locateUVX(
            fixedCandidates: ["/opt/homebrew/bin/uvx", "/usr/local/bin/uvx"],
            pathVariable: "/a/bin:/b/bin:/c/bin",
            isExecutable: { $0 == "/b/bin/uvx" || $0 == "/c/bin/uvx" }
        )
        XCTAssertEqual(path, "/b/bin/uvx", "first PATH directory containing uvx wins")
    }

    func testLocateUVXReturnsNilWhenNothingExists() {
        XCTAssertNil(LinkedInMCPServerService.locateUVX(
            fixedCandidates: ["/opt/homebrew/bin/uvx"],
            pathVariable: "/a/bin:/b/bin",
            isExecutable: { _ in false }
        ))
        XCTAssertNil(LinkedInMCPServerService.locateUVX(
            fixedCandidates: [],
            pathVariable: nil,
            isExecutable: { _ in true }
        ), "no candidates and no PATH means not installed, even if the checker would pass")
    }

    func testLocateUVXSkipsEmptyPathComponents() {
        // "::" in PATH denotes the current directory; splitting must not
        // produce a bare "/uvx" probe from the empty component.
        var probed: [String] = []
        _ = LinkedInMCPServerService.locateUVX(
            fixedCandidates: [],
            pathVariable: "/a/bin::/b/bin",
            isExecutable: { probed.append($0); return false }
        )
        XCTAssertEqual(probed, ["/a/bin/uvx", "/b/bin/uvx"])
    }

    // MARK: - Launch invocation

    func testLaunchArgumentsPinVersionAndMatchEndpoint() {
        let args = LinkedInMCPServerService.launchArguments
        XCTAssertEqual(
            args.first,
            "mcp-server-linkedin==\(LinkedInMCPServerService.pinnedVersion)",
            "the uvx spec must carry the pinned version"
        )
        XCTAssertEqual(Array(args[1...2]), ["--transport", "streamable-http"])

        // --host/--port/--path must agree with the endpoint the client dials.
        let endpoint = LinkedInMCPServerService.endpoint
        func value(after flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        XCTAssertEqual(value(after: "--host"), endpoint.host)
        XCTAssertEqual(value(after: "--port"), endpoint.port.map(String.init))
        XCTAssertEqual(value(after: "--path"), endpoint.path)
        XCTAssertEqual(endpoint.host, "127.0.0.1", "server must stay bound to localhost")
    }

    // MARK: - Readiness probe pieces

    func testInitializeEnvelopeShape() throws {
        let envelope = LinkedInMCPServerService.initializeEnvelope()
        XCTAssertEqual(envelope["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(envelope["method"] as? String, "initialize")
        XCTAssertNotNil(envelope["id"], "initialize is a request, not a notification — it needs an id")
        let params = try XCTUnwrap(envelope["params"] as? [String: Any])
        XCTAssertNotNil(params["protocolVersion"] as? String)
        XCTAssertNotNil(params["capabilities"])
        XCTAssertNotNil(params["clientInfo"])
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: envelope))
    }

    func testIsReadyResponsePredicate() {
        let body = Data("event: message\ndata: {}\n\n".utf8)
        XCTAssertTrue(LinkedInMCPServerService.isReadyResponse(statusCode: 200, body: body))
        XCTAssertTrue(LinkedInMCPServerService.isReadyResponse(statusCode: 202, body: Data("{}".utf8)))
        XCTAssertFalse(LinkedInMCPServerService.isReadyResponse(statusCode: 200, body: Data()),
                       "an empty 200 is not a handshake answer")
        XCTAssertFalse(LinkedInMCPServerService.isReadyResponse(statusCode: 404, body: body))
        XCTAssertFalse(LinkedInMCPServerService.isReadyResponse(statusCode: 500, body: body))
    }

    // MARK: - stderr tail

    func testTailTextKeepsOnlyLastLines() {
        let lines = (1...12).map { "line \($0)" }
        let tail = LinkedInMCPServerService.tailText(of: lines, maxLines: 3)
        XCTAssertEqual(tail, "line 10\nline 11\nline 12")
        XCTAssertEqual(LinkedInMCPServerService.tailText(of: [], maxLines: 3), "")
        XCTAssertEqual(LinkedInMCPServerService.tailText(of: ["only"], maxLines: 3), "only")
    }

    // MARK: - Consent flag

    func testConsentFlagRoundTrip() {
        let defaults = TestDefaults()
        let service = LinkedInMCPServerService(defaults: defaults.store)
        XCTAssertFalse(service.consentAccepted, "consent starts unaccepted")
        XCTAssertFalse(defaults.store.bool(forKey: LinkedInMCPServerService.consentDefaultsKey))

        service.acceptConsent()
        XCTAssertTrue(service.consentAccepted)
        XCTAssertTrue(defaults.store.bool(forKey: LinkedInMCPServerService.consentDefaultsKey))

        // A fresh instance (new app launch) reads the persisted flag back.
        let relaunched = LinkedInMCPServerService(defaults: defaults.store)
        XCTAssertTrue(relaunched.consentAccepted)
    }

    // MARK: - Initial state & errors

    func testInitialStatusIsStoppedAndInitSpawnsNothing() {
        let service = LinkedInMCPServerService(defaults: TestDefaults().store)
        XCTAssertEqual(service.status, .stopped)
    }

    func testUVNotInstalledErrorCarriesBrewRemedy() throws {
        let message = try XCTUnwrap(LinkedInMCPServerError.uvNotInstalled.errorDescription)
        XCTAssertTrue(message.contains("Install uv: brew install uv"),
                      "the uv-missing error must tell the user the exact remedy")
    }
}
