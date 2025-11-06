//
//  Logger.swift
//  Sprung
//

import Foundation
import os

/// Backend protocol that funnels log events to the desired sink.
protocol Logging {
    func log(
        level: Logger.Level,
        category: Logger.Category,
        message: String,
        metadata: [String: String]
    )
}

/// Default backend that bridges to Apple's os.Logger.
final class OSLoggerBackend: Logging {
    private let subsystem: String
    private var cachedLoggers: [Logger.Category: os.Logger] = [:]
    private let lock = NSLock()
    
    init(subsystem: String = Bundle.main.bundleIdentifier ?? "Sprung") {
        self.subsystem = subsystem
    }
    
    func log(
        level: Logger.Level,
        category: Logger.Category,
        message: String,
        metadata: [String: String]
    ) {
        let osLogger = logger(for: category)
        let combinedMessage = OSLoggerBackend.composeMessage(message, metadata: metadata)
        osLogger.log(level: level.osLogType, "\(combinedMessage, privacy: .public)")
    }
    
    private func logger(for category: Logger.Category) -> os.Logger {
        lock.lock()
        defer { lock.unlock() }
        if let existing = cachedLoggers[category] {
            return existing
        }
        let newlyCreated = os.Logger(subsystem: subsystem, category: category.rawValue)
        cachedLoggers[category] = newlyCreated
        return newlyCreated
    }
    
    private static func composeMessage(_ message: String, metadata: [String: String]) -> String {
        guard !metadata.isEmpty else {
            return message
        }
        let sorted = metadata
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: " ")
        return "\(message) [\(sorted)]"
    }
}

/// Lightweight logging facade with configurable backends and debug settings.
final class Logger {
    // MARK: - Nested Types
    
    /// Defines available log levels in increasing order of severity.
    /// Lower raw values = more output, higher raw values = less output.
    enum Level: Int, CaseIterable {
        case debug = 0      // Most output
        case verbose = 1
        case info = 2
        case warning = 3
        case error = 4      // Least output (highest severity)
        
        /// Returns a string representation of the log level.
        var label: String {
            switch self {
                case .verbose:  return "VERBOSE"
                case .debug:    return "DEBUG"
                case .info:     return "INFO"
                case .warning:  return "WARNING"
                case .error:    return "ERROR"
            }
        }
        
        /// Emoji for quick visual scanning in debug logs.
        var emoji: String {
            switch self {
                case .verbose:  return "📋"
                case .debug:    return "🔍"
                case .info:     return "ℹ️"
                case .warning:  return "⚠️"
                case .error:    return "🚨"
            }
        }
    }
    
    /// High-level domains to keep log output organized.
    enum Category: String, CaseIterable {
        case general = "General"
        case appLifecycle = "AppLifecycle"
        case ai = "AI"
        case data = "Data"
        case diagnostics = "Diagnostics"
        case export = "Export"
        case migration = "Migration"
        case networking = "Networking"
        case storage = "Storage"
        case ui = "UI"
    }
    
    struct Configuration {
        var minimumLevel: Level
        var enableFileLogging: Bool
        var enableConsoleOutput: Bool
        var subsystem: String
    }
    
    // MARK: - Static State
    
    private static let configurationQueue = DispatchQueue(label: "Logger.configuration.queue", attributes: .concurrent)
    private static let backendLock = NSLock()
    private static var configuration: Configuration = Logger.makeDefaultConfiguration()
    private static var backend: Logging = OSLoggerBackend(subsystem: configuration.subsystem)
    private static let newlineStripper = CharacterSet.newlines
    
    // MARK: - Public Configuration Accessors
    
    static var minimumLevel: Level {
        configurationQueue.sync { configuration.minimumLevel }
    }
    
    static var isVerboseEnabled: Bool {
        // Verbose is enabled if minimum level is verbose (1) or debug (0)
        minimumLevel.rawValue <= Level.verbose.rawValue
    }
    
    static var shouldSaveDebugFiles: Bool {
#if DEBUG
        return configurationQueue.sync { configuration.enableFileLogging }
#else
        return false
#endif
    }
    
    static func updateMinimumLevel(_ level: Level) {
        configurationQueue.async(flags: .barrier) {
            configuration.minimumLevel = level
        }
    }
    
    static func updateFileLogging(isEnabled: Bool) {
#if DEBUG
        configurationQueue.async(flags: .barrier) {
            configuration.enableFileLogging = isEnabled
        }
#endif
    }
    
    // MARK: - Logging Methods
    
    static func log(
        _ level: Level,
        _ message: String,
        category: Category = .general,
        metadata: [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        guard level.rawValue >= minimumLevel.rawValue else {
            return
        }
        
        let sanitizedMessage = sanitize(message)
        let fileName = (file as NSString).lastPathComponent
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = timeFormatter.string(from: Date())
        let formattedMessage = "[\(timestamp)] \(level.emoji) [\(level.label)] [\(category.rawValue)] [\(fileName):\(line)] \(function): \(sanitizedMessage)"
        
        
        let shouldPrint = configurationQueue.sync { configuration.enableConsoleOutput }
        if shouldPrint {
            print(formattedMessage)
        }
        
        let backend = currentBackend()
        backend.log(
            level: level,
            category: category,
            message: formattedMessage,
            metadata: metadata
        )
        
        if shouldSaveDebugFiles && (level == .error || level == .warning) {
            saveLogToFile(message: formattedMessage)
        }
    }
    
    static func verbose(
        _ message: String,
        category: Category = .general,
        metadata: [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(.verbose, message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    static func debug(
        _ message: String,
        category: Category = .general,
        metadata: [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(.debug, message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    static func info(
        _ message: String,
        category: Category = .general,
        metadata: [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(.info, message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    static func warning(
        _ message: String,
        category: Category = .general,
        metadata: [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(.warning, message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    static func error(
        _ message: String,
        category: Category = .general,
        metadata: [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(.error, message, category: category, metadata: metadata, file: file, function: function, line: line)
    }
    
    // MARK: - Helpers
    
    private static func currentBackend() -> Logging {
        backendLock.lock()
        defer { backendLock.unlock() }
        return backend
    }
    
    private static func sanitize(_ message: String) -> String {
        guard message.rangeOfCharacter(from: newlineStripper) != nil else {
            return message
        }
        return message.components(separatedBy: newlineStripper).filter { !$0.isEmpty }.joined(separator: " ⏎ ")
    }
    
    private static func makeDefaultConfiguration() -> Configuration {
#if DEBUG
        let defaults = UserDefaults.standard
        let storedLevel = defaults.integer(forKey: DefaultsKeys.debugLogLevel)
        let minimumLevel = mapStoredLevel(storedLevel)
        let fileLogging = defaults.bool(forKey: DefaultsKeys.saveDebugPrompts)
#else
        let minimumLevel: Level = .info
        let fileLogging = false
#endif
        let subsystem = Bundle.main.bundleIdentifier ?? "Sprung"
        return Configuration(
            minimumLevel: minimumLevel,
            enableFileLogging: fileLogging,
            enableConsoleOutput: true,
            subsystem: subsystem
        )
    }
    
    private static func mapStoredLevel(_ rawValue: Int) -> Level {
        // DebugSettingsStore.LogLevelSetting:
        // 0 = quiet, 1 = info, 2 = verbose, 3 = debug
        switch rawValue {
            case 0: return .error      // quiet (errors only)
            case 1: return .info       // info
            case 2: return .verbose    // verbose
            case 3: return .debug      // debug (most output)
            default: return .info      // fallback
        }
    }
    
    /// Saves important logs to file in Downloads (debug builds only).
    private static func saveLogToFile(message: String) {
#if DEBUG
        let fileManager = FileManager.default
        let downloadsURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        
        let logFileName = "Sprung_\(dateString)_log.txt"
        let fileURL = downloadsURL.appendingPathComponent(logFileName)
        
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())
        let entry = "[\(timestamp)] \(message)\n"
        
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                if let data = entry.data(using: .utf8) {
                    try handle.seekToEnd()
                    handle.write(data)
                }
            } else {
                try entry.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Logger: Failed to write log to file: \(error)")
        }
#endif
    }
    
    private enum DefaultsKeys {
        static let debugLogLevel = "debugLogLevel"
        static let saveDebugPrompts = "saveDebugPrompts"
    }
}

private extension Logger.Level {
    var osLogType: OSLogType {
        switch self {
            case .verbose, .debug:
                return .debug
            case .info:
                return .info
            case .warning:
                return .error
            case .error:
                return .fault
        }
    }
}
