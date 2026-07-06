//
//  LinkedInMCPServerService.swift
//  Sprung
//
//  Owns the lifecycle of the app-managed LinkedIn MCP server: a pinned
//  `mcp-server-linkedin` release run natively via uvx, bound to localhost,
//  speaking the same Streamable HTTP transport `MCPStreamableHTTPClient`
//  already implements for Dice/ZipRecruiter. `ensureRunning()` is the only
//  start affordance (idempotent, single in-flight start under concurrent
//  callers); `stop()` SIGTERMs the child and is wired to app termination.
//
//  Auth is entirely the server's AUTO_IMPORT_FROM_BROWSER behavior: on the
//  first tool call it imports the LinkedIn session from a locally logged-in
//  browser. This service deliberately implements no login flow, no cookie
//  export, and no endpoint override — auth failures surface loudly at the
//  call site as "sign in to linkedin.com in your browser, then search again".
//
//  Also holds the one-time risk-consent flag the LinkedIn board is gated on
//  (`LinkedInConsentDialog` sets it; the board reads it).
//

import Foundation
import Observation

enum LinkedInMCPServerError: LocalizedError {
    case uvNotInstalled
    case launchFailed(String)
    case startupFailed(String)

    var errorDescription: String? {
        switch self {
        case .uvNotInstalled:
            return "LinkedIn job search needs the uv package runner, which wasn't found "
                + "(checked /opt/homebrew/bin, /usr/local/bin, and PATH). "
                + "Install uv: brew install uv"
        case .launchFailed(let detail):
            return "Couldn't launch the LinkedIn job search server: \(detail)"
        case .startupFailed(let detail):
            return "The LinkedIn job search server failed to start: \(detail)"
        }
    }
}

@Observable
@MainActor
final class LinkedInMCPServerService {

    enum ServerStatus: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    /// Deliberately pinned: the server's result payloads are an internal wire
    /// format we decode; bumps are explicit events that re-run the spike checks
    /// (see plans/linkedin-mcp-design.md).
    static let pinnedVersion = "4.17.0"
    /// The Streamable HTTP endpoint the spawned server listens on. Must stay in
    /// sync with `launchArguments`' --host/--port/--path.
    static let endpoint = URL(string: "http://127.0.0.1:8090/mcp")!
    /// One-time risk-consent flag the LinkedIn board is gated on.
    static let consentDefaultsKey = "linkedInBoardConsentAccepted"

    /// Overall readiness bound. The first-ever run downloads a Chromium build
    /// (~200 MB) before the server can listen, so this is minutes, not seconds.
    /// It is a bounded readiness poll on a local child process — not a
    /// wall-clock timeout on agent work.
    static let readinessTimeout: TimeInterval = 600
    private static let pollInterval: TimeInterval = 1
    private static let progressLogInterval: TimeInterval = 15
    private static let stderrTailLineLimit = 40

    // MARK: - Observable state

    private(set) var status: ServerStatus = .stopped
    /// Mirrors the persisted consent flag so SwiftUI observation sees changes.
    private(set) var consentAccepted: Bool

    // MARK: - Private state

    private let defaults: UserDefaults
    private var process: Process?
    /// Single in-flight start: concurrent `ensureRunning()` callers await the
    /// same task instead of racing to spawn a second child on the same port.
    private var startTask: Task<Void, Error>?
    /// Ring buffer of recent stderr lines, surfaced when the child dies.
    private var recentStderrLines: [String] = []
    /// Per-stream throttle clocks so child output never spams the log
    /// (Chromium downloads emit progress chunks continuously).
    private var lastLogDateByStream: [String: Date] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.consentAccepted = defaults.bool(forKey: Self.consentDefaultsKey)
    }

    // MARK: - Consent

    /// Persist the one-time risk consent. Declining is simply not calling this.
    func acceptConsent() {
        consentAccepted = true
        defaults.set(true, forKey: Self.consentDefaultsKey)
    }

    // MARK: - Lifecycle

    /// The only public start affordance. Idempotent: returns immediately when
    /// the server is already running, joins an in-flight start when one exists,
    /// and otherwise spawns the pinned uvx process and polls the MCP initialize
    /// handshake until the endpoint answers (or throws with a descriptive error).
    func ensureRunning() async throws {
        if status == .running, process?.isRunning == true {
            return
        }
        if let inFlight = startTask {
            try await inFlight.value
            return
        }
        let task = Task { try await self.start() }
        startTask = task
        defer { startTask = nil }
        try await task.value
    }

    /// SIGTERM the child (reaped off-main) — called on app quit and when a
    /// startup attempt is abandoned. Safe to call in any state.
    func stop() {
        startTask?.cancel()
        if let process {
            Logger.info("🛑 [LinkedInMCP] stopping server", category: .networking)
            terminateAndReap(process)
            self.process = nil
        }
        status = .stopped
    }

    // MARK: - Start sequence

    private func start() async throws {
        status = .starting
        recentStderrLines = []
        Logger.info(
            "🔗 [LinkedInMCP] starting mcp-server-linkedin \(Self.pinnedVersion) at \(Self.endpoint.absoluteString)",
            category: .networking
        )

        guard let uvxPath = Self.locateUVX() else {
            let error = LinkedInMCPServerError.uvNotInstalled
            status = .failed(error.localizedDescription)
            Logger.error("❌ [LinkedInMCP] \(error.localizedDescription)", category: .networking)
            throw error
        }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: uvxPath)
        child.arguments = Self.launchArguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        child.standardOutput = stdoutPipe
        child.standardError = stderrPipe
        attachReader(to: stdoutPipe, stream: "stdout", captureForTail: false)
        attachReader(to: stderrPipe, stream: "stderr", captureForTail: true)
        // Fires only for UNEXPECTED exits: every intentional shutdown path
        // goes through terminateAndReap, which clears this handler first.
        child.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                self?.handleUnexpectedTermination(of: proc)
            }
        }

        do {
            try child.run()
        } catch {
            let detail = "uvx at \(uvxPath) failed to launch: \(error.localizedDescription)"
            status = .failed(detail)
            Logger.error("❌ [LinkedInMCP] \(detail)", category: .networking)
            throw LinkedInMCPServerError.launchFailed(detail)
        }
        process = child

        do {
            try await pollUntilReady(child: child)
            status = .running
            Logger.info("✅ [LinkedInMCP] server ready at \(Self.endpoint.absoluteString)", category: .networking)
        } catch is CancellationError {
            terminateAndReap(child)
            // Identity guard: only touch shared state if a newer start
            // sequence hasn't already replaced this child.
            if process === child {
                process = nil
                status = .stopped
            }
            throw CancellationError()
        } catch {
            terminateAndReap(child)
            let detail = error.localizedDescription
            if process === child {
                process = nil
                status = .failed(detail)
            }
            Logger.error("❌ [LinkedInMCP] startup failed: \(detail)", category: .networking)
            throw error
        }
    }

    /// Poll the endpoint with an MCP initialize handshake until it answers.
    /// Patient by design: the first run downloads a browser before listening.
    private func pollUntilReady(child: Process) async throws {
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(Self.readinessTimeout)
        var lastProgressLog = startedAt
        while true {
            try Task.checkCancellation()
            if !child.isRunning {
                throw LinkedInMCPServerError.startupFailed(
                    "server exited during startup (code \(child.terminationStatus)). \(stderrTail())"
                )
            }
            if await Self.probeInitialize(endpoint: Self.endpoint) {
                return
            }
            let now = Date()
            if now >= deadline {
                throw LinkedInMCPServerError.startupFailed(
                    "server did not become ready within \(Int(Self.readinessTimeout)) seconds. \(stderrTail())"
                )
            }
            if now.timeIntervalSince(lastProgressLog) >= Self.progressLogInterval {
                lastProgressLog = now
                let elapsed = Int(now.timeIntervalSince(startedAt))
                Logger.info(
                    "⏳ [LinkedInMCP] still starting (\(elapsed)s) — the first run downloads a browser and can take minutes",
                    category: .networking
                )
            }
            try await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
        }
    }

    /// One readiness probe: POST an MCP initialize JSON-RPC to the endpoint
    /// with a short per-attempt timeout. Any 2xx with a body means the server
    /// is up (SSE- or JSON-framed alike).
    private static func probeInitialize(endpoint: URL) async -> Bool {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 3
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        guard let body = try? JSONSerialization.data(withJSONObject: initializeEnvelope()) else {
            return false
        }
        request.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return false
        }
        return isReadyResponse(statusCode: http.statusCode, body: data)
    }

    // MARK: - Termination handling

    /// Reached only when the child dies on its own — intentional shutdowns
    /// clear the termination handler first (see `terminateAndReap`).
    private func handleUnexpectedTermination(of child: Process) {
        guard child === process else {
            // Stale notification from a child a newer start/stop already
            // replaced; that sequence owns the status.
            return
        }
        process = nil
        let detail = "LinkedIn MCP server exited unexpectedly (code \(child.terminationStatus)). \(stderrTail())"
        Logger.error("❌ [LinkedInMCP] \(detail)", category: .networking)
        status = .failed(detail)
    }

    /// Intentional shutdown: silence the unexpected-exit handler, SIGTERM,
    /// and reap off the main actor so quitting never blocks on the child.
    private func terminateAndReap(_ child: Process) {
        child.terminationHandler = nil
        guard child.isRunning else { return }
        child.terminate()
        DispatchQueue.global(qos: .utility).async {
            child.waitUntilExit()
        }
    }

    // MARK: - Child output

    private func attachReader(to pipe: Pipe, stream: String, captureForTail: Bool) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.ingestChildOutput(text, stream: stream, captureForTail: captureForTail)
            }
        }
    }

    private func ingestChildOutput(_ text: String, stream: String, captureForTail: Bool) {
        if captureForTail {
            recentStderrLines.append(contentsOf: text.split(separator: "\n").map(String.init))
            if recentStderrLines.count > Self.stderrTailLineLimit {
                recentStderrLines.removeFirst(recentStderrLines.count - Self.stderrTailLineLimit)
            }
        }
        // Throttle: at most one debug line per second per stream. The tail
        // buffer above still captures everything that matters for errors.
        let now = Date()
        if let last = lastLogDateByStream[stream], now.timeIntervalSince(last) < 1 {
            return
        }
        lastLogDateByStream[stream] = now
        let snippet = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)
        guard !snippet.isEmpty else { return }
        Logger.debug("🔗 [LinkedInMCP \(stream)] \(snippet)", category: .networking)
    }

    private func stderrTail() -> String {
        let tail = Self.tailText(of: recentStderrLines)
        return tail.isEmpty ? "" : "Server output:\n\(tail)"
    }

    // MARK: - Pure pieces (unit-tested)

    /// The pinned uvx invocation. --host/--port/--path must match `endpoint`.
    static var launchArguments: [String] {
        [
            "mcp-server-linkedin==\(pinnedVersion)",
            "--transport", "streamable-http",
            "--host", "127.0.0.1",
            "--port", "8090",
            "--path", "/mcp"
        ]
    }

    /// Locate the uvx binary: fixed Homebrew/local paths first, then every
    /// directory on PATH. Returns nil when uv isn't installed anywhere.
    static func locateUVX(
        fixedCandidates: [String] = ["/opt/homebrew/bin/uvx", "/usr/local/bin/uvx"],
        pathVariable: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        for candidate in fixedCandidates where isExecutable(candidate) {
            return candidate
        }
        guard let pathVariable else { return nil }
        for directory in pathVariable.split(separator: ":") {
            let candidate = "\(directory)/uvx"
            if isExecutable(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// The JSON-RPC initialize envelope the readiness probe POSTs.
    static func initializeEnvelope() -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-03-26",
                "capabilities": [String: Any](),
                "clientInfo": ["name": "Sprung", "version": "readiness-probe"]
            ]
        ]
    }

    /// A probe response counts as ready when it's a 2xx with a non-empty body
    /// (the server answers initialize as JSON or SSE — either way, bytes).
    static func isReadyResponse(statusCode: Int, body: Data) -> Bool {
        (200...299).contains(statusCode) && !body.isEmpty
    }

    /// Last `maxLines` of the child's stderr, for failure surfacing.
    static func tailText(of lines: [String], maxLines: Int = 8) -> String {
        lines.suffix(maxLines).joined(separator: "\n")
    }
}
