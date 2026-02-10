//
//  LLMTranscriptLogger.swift
//  Sprung
//
//  Appends human-readable LLM request/response transcripts to a date-stamped
//  file in ~/Downloads when transcript logging is enabled via Debug Settings.
//
import Foundation
enum LLMTranscriptLogger {
    private static let fileQueue = DispatchQueue(
        label: "com.sprung.llm-transcript",
        qos: .utility
    )
    static let defaultsKey = "logLLMTranscripts"
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }
    // MARK: - Public Logging API
    static func logTextCall(
        method: String,
        modelId: String,
        backend: String,
        prompt: String,
        response: String,
        durationMs: Int
    ) {
        guard isEnabled else { return }
        let entry = """
        METHOD: \(method)
        MODEL: \(modelId) | BACKEND: \(backend) | DURATION: \(durationMs)ms

        --- REQUEST ---
        \(prompt)

        --- RESPONSE ---
        \(response)
        """
        appendEntry(entry)
    }
    static func logStructuredCall(
        method: String,
        modelId: String,
        backend: String,
        prompt: String,
        responseType: String,
        responseJSON: String,
        durationMs: Int
    ) {
        guard isEnabled else { return }
        let entry = """
        METHOD: \(method)
        MODEL: \(modelId) | BACKEND: \(backend) | DURATION: \(durationMs)ms
        RESPONSE TYPE: \(responseType)

        --- REQUEST ---
        \(prompt)

        --- RESPONSE (JSON) ---
        \(responseJSON)
        """
        appendEntry(entry)
    }
    static func logStreamingRequest(
        method: String,
        modelId: String,
        backend: String,
        prompt: String
    ) {
        guard isEnabled else { return }
        let entry = """
        METHOD: \(method) [REQUEST ONLY — streaming]
        MODEL: \(modelId) | BACKEND: \(backend)

        --- REQUEST ---
        \(prompt)
        """
        appendEntry(entry)
    }
    static func logToolCall(
        method: String,
        modelId: String,
        backend: String,
        messageCount: Int,
        toolNames: [String],
        responseContent: String?,
        responseToolCalls: [String],
        durationMs: Int
    ) {
        guard isEnabled else { return }
        let toolList = toolNames.joined(separator: ", ")
        var entry = """
        METHOD: \(method)
        MODEL: \(modelId) | BACKEND: \(backend) | DURATION: \(durationMs)ms
        MESSAGES: \(messageCount) | TOOLS: [\(toolList)]

        --- RESPONSE CONTENT ---
        \(responseContent ?? "(none)")
        """
        if !responseToolCalls.isEmpty {
            entry += "\n\n--- TOOL CALLS ---"
            for (i, call) in responseToolCalls.enumerated() {
                entry += "\n\(i + 1). \(call)"
            }
        }
        appendEntry(entry)
    }
    static func logAnthropicCall(
        method: String,
        modelId: String,
        systemBlockCount: Int,
        userPrompt: String,
        response: String,
        durationMs: Int
    ) {
        guard isEnabled else { return }
        let entry = """
        METHOD: \(method)
        MODEL: \(modelId) | BACKEND: Anthropic | DURATION: \(durationMs)ms
        SYSTEM BLOCKS: \(systemBlockCount)

        --- REQUEST ---
        \(userPrompt)

        --- RESPONSE ---
        \(response)
        """
        appendEntry(entry)
    }
    static func logGeminiCall(
        method: String,
        modelId: String,
        prompt: String,
        attachmentInfo: String,
        response: String,
        durationMs: Int
    ) {
        guard isEnabled else { return }
        let entry = """
        METHOD: \(method)
        MODEL: \(modelId) | BACKEND: Gemini | DURATION: \(durationMs)ms
        ATTACHMENT: \(attachmentInfo)

        --- REQUEST ---
        \(prompt)

        --- RESPONSE ---
        \(response)
        """
        appendEntry(entry)
    }
    // MARK: - File I/O
    private static func transcriptFileURL() -> URL {
        let downloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        return downloads.appendingPathComponent("Sprung_\(dateString)_llm_transcript.txt")
    }
    private static func appendEntry(_ entry: String) {
        Logger.info("📝 LLMTranscriptLogger.appendEntry called (isEnabled=\(isEnabled))", category: .ai)
        fileQueue.async {
            let fileURL = transcriptFileURL()
            Logger.info("📝 Writing transcript to: \(fileURL.path)", category: .ai)
            let timestampFormatter = DateFormatter()
            timestampFormatter.dateFormat = "HH:mm:ss.SSS"
            let timestamp = timestampFormatter.string(from: Date())
            let separator = String(repeating: "=", count: 80)
            let formatted = """
            \(separator)
            [\(timestamp)] \(entry)
            \(separator)\n
            """
            guard let data = formatted.data(using: .utf8) else {
                Logger.error("📝 Failed to encode transcript entry as UTF-8", category: .ai)
                return
            }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    defer { try? handle.close() }
                    _ = try handle.seekToEnd()
                    handle.write(data)
                    Logger.info("📝 Appended \(data.count) bytes to transcript", category: .ai)
                } catch {
                    Logger.error("📝 Failed to append to transcript: \(error)", category: .ai)
                }
            } else {
                do {
                    try data.write(to: fileURL)
                    Logger.info("📝 Created transcript file: \(fileURL.lastPathComponent)", category: .ai)
                } catch {
                    Logger.error("📝 Failed to create transcript file: \(error)", category: .ai)
                }
            }
        }
    }
}
