//
//  SwiftOpenAIClient.swift
//  Sprung
//
//  Adapter implementing LLMClient on top of existing LLMRequestExecutor.
//

import Foundation
import SwiftOpenAI

// MARK: - Sprung Logger Adapter for SwiftOpenAI
/// Implements OpenAILoggerProtocol to route SwiftOpenAI logs through Sprung's centralized Logger
private class SprungOpenAILogger: OpenAILoggerProtocol {
    func debug(_ message: String) {
        guard SwiftOpenAIClient.shouldEmitDebug(message) else { return }

        // All SwiftOpenAI debug messages should use Sprung's debug level
        // This ensures JSON payloads only appear when user explicitly wants debug detail
        Logger.debug(message, category: .ai)
    }

    func error(_ message: String) {
        Logger.error(message, category: .ai)
    }
}

final class SwiftOpenAIClient: LLMClient {
    // Reuse existing request executor and builders
    private let executor: LLMRequestExecutor
    private let defaultTemperature: Double = 1.0

    // Class-level flag to ensure logger is only injected once
    private static var loggerInjected = false
    private static let loggerInjectionLock = NSLock()
    private static let logLevelLock = NSLock()
    private static let defaultsKey = "swiftOpenAILogLevel"
    private static var _logLevel: LogLevel = .info

    enum LogLevel: Int, CaseIterable, CustomStringConvertible {
        case quiet
        case info
        case verbose
        case debug

        var description: String {
            switch self {
            case .quiet: return "Quiet"
            case .info: return "Info"
            case .verbose: return "Verbose"
            case .debug: return "Debug"
            }
        }

        var storageValue: String {
            switch self {
            case .quiet: return "quiet"
            case .info: return "info"
            case .verbose: return "verbose"
            case .debug: return "debug"
            }
        }

        init?(storageValue: String) {
            switch storageValue.lowercased() {
            case "quiet": self = .quiet
            case "info": self = .info
            case "verbose": self = .verbose
            case "debug": self = .debug
            default: return nil
            }
        }
    }

    /// Change the verbosity of SwiftOpenAI diagnostic logging at runtime.
    static func setLogLevel(_ level: LogLevel) {
        logLevelLock.lock()
        let previous = _logLevel
        _logLevel = level
        logLevelLock.unlock()
        UserDefaults.standard.set(level.storageValue, forKey: defaultsKey)
        guard previous != level else { return }
        Logger.info("SwiftOpenAI log level set to \(level)", category: .diagnostics)
    }

    static var currentLogLevel: LogLevel {
        logLevelLock.lock()
        let level = _logLevel
        logLevelLock.unlock()
        return level
    }

    fileprivate static func shouldEmitDebug(_ message: String) -> Bool {
        let level = currentLogLevel
        switch level {
        case .quiet:
            return false
        case .info:
            return isHighValue(message)
        case .verbose:
            return !isPerTokenDelta(message)
        case .debug:
            return true
        }
    }

    private static func isPerTokenDelta(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("delta") || lowered.contains("stream line")
    }

    private static func isHighValue(_ message: String) -> Bool {
        let lowered = message.lowercased()
        if lowered.contains("error") || lowered.contains("failed") {
            return true
        }
        // HTTP status codes are important, but exclude verbose curl statements
        if lowered.contains("http status code") {
            return true
        }
        // Exclude curl request logs - these contain full JSON payloads
        if lowered.contains("curl") {
            return false
        }
        if lowered.contains("response completed") || lowered.contains("usage") {
            return true
        }
        return false
    }

    static func logLevel(from storageValue: String) -> LogLevel {
        LogLevel(storageValue: storageValue) ?? .info
    }

    static func applyStoredLogLevel() {
        let stored = UserDefaults.standard.string(forKey: defaultsKey) ?? LogLevel.info.storageValue
        setLogLevel(logLevel(from: stored))
    }

    init(executor: LLMRequestExecutor = LLMRequestExecutor()) {
        self.executor = executor

        // Inject Sprung's Logger into SwiftOpenAI for unified logging with timestamps
        // Only inject once to avoid repeated initialization
        Self.loggerInjectionLock.lock()
        defer { Self.loggerInjectionLock.unlock() }

        if !Self.loggerInjected {
            setOpenAILogger(SprungOpenAILogger())
            Self.loggerInjected = true
            Logger.debug("Injected Sprung's Logger into SwiftOpenAI", category: .ai)
        }

        // Ensure client is configured
        Task {
            await self.executor.configureClient()
        }
    }

    func executeText(prompt: String, modelId: String, temperature: Double? = nil) async throws -> String {
        let params = LLMRequestBuilder.buildTextRequest(
            prompt: prompt,
            modelId: modelId,
            temperature: temperature ?? defaultTemperature
        )
        let response = try await executor.execute(parameters: params)
        let dto = LLMVendorMapper.responseDTO(from: response)
        guard let content = dto.choices.first?.message?.text else {
            throw LLMError.unexpectedResponseFormat
        }
        return content
    }

    func executeTextWithImages(prompt: String, modelId: String, images: [Data], temperature: Double? = nil) async throws -> String {
        let params = LLMRequestBuilder.buildVisionRequest(
            prompt: prompt,
            modelId: modelId,
            images: images,
            temperature: temperature ?? defaultTemperature
        )
        let response = try await executor.execute(parameters: params)
        let dto = LLMVendorMapper.responseDTO(from: response)
        guard let content = dto.choices.first?.message?.text else {
            throw LLMError.unexpectedResponseFormat
        }
        return content
    }

    func executeStructured<T: Codable & Sendable>(prompt: String, modelId: String, as: T.Type, temperature: Double? = nil) async throws -> T {
        let params = LLMRequestBuilder.buildStructuredRequest(
            prompt: prompt,
            modelId: modelId,
            responseType: T.self,
            temperature: temperature ?? defaultTemperature,
            jsonSchema: nil
        )
        let response = try await executor.execute(parameters: params)
        let dto = LLMVendorMapper.responseDTO(from: response)
        return try JSONResponseParser.parseStructured(dto, as: T.self)
    }

    func executeStructuredWithImages<T: Codable & Sendable>(prompt: String, modelId: String, images: [Data], as: T.Type, temperature: Double? = nil) async throws -> T {
        let params = LLMRequestBuilder.buildStructuredVisionRequest(
            prompt: prompt,
            modelId: modelId,
            images: images,
            responseType: T.self,
            temperature: temperature ?? defaultTemperature
        )
        let response = try await executor.execute(parameters: params)
        let dto = LLMVendorMapper.responseDTO(from: response)
        return try JSONResponseParser.parseStructured(dto, as: T.self)
    }

}
