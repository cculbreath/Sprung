//
//  Logger.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/13/25.
//

import Foundation
import SwiftUI

/// Simple logging utility for PhysCloudResume
/// Integrates with app debug settings in UserDefaults
final class Logger {
    // MARK: - Log Levels
    
    /// Defines available log levels in increasing order of severity
    enum Level: Int, CaseIterable {
        case verbose = 0
        case debug = 1
        case info = 2
        case warning = 3
        case error = 4
        
        /// Returns a string representation of the log level
        var label: String {
            switch self {
            case .verbose:  return "VERBOSE"
            case .debug:    return "DEBUG"
            case .info:     return "INFO"
            case .warning:  return "WARNING"
            case .error:    return "ERROR"
            }
        }
        
        /// Returns an emoji for the log level for visual distinction
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
    
    // MARK: - Properties
    
    /// The minimum log level to display. 
    /// Defaults to UserDefaults setting or .info if not found
    static var minimumLevel: Level {
        // Map the UserDefaults integer to corresponding log level
        // 0=None, 1=Basic, 2=Verbose from DebugSettingsView
        let rawValue = UserDefaults.standard.integer(forKey: "debugLogLevel")
        switch rawValue {
        case 0:  return .error     // None = only errors
        case 1:  return .info      // Basic = info and above
        case 2:  return .verbose   // Verbose = all logs
        default: return .info      // Default to info
        }
    }
    
    /// Check if debug files should be saved
    static var shouldSaveDebugFiles: Bool {
        UserDefaults.standard.bool(forKey: "saveDebugPrompts")
    }
    
    // MARK: - Logging Methods
    
    /// Log a message at the specified level
    /// - Parameters:
    ///   - level: The log level
    ///   - message: The message to log
    ///   - file: The file where the log call originated
    ///   - function: The function where the log call originated
    ///   - line: The line where the log call originated
    static func log(
        _ level: Level,
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // Only log if the level is at or above the minimum
        guard level.rawValue >= minimumLevel.rawValue else {
            return
        }
        
        // Get file name from path
        let fileName = (file as NSString).lastPathComponent
        
        // Format the log message
        let formattedMessage = "\(level.emoji) [\(level.label)] [\(fileName):\(line)] \(function): \(message)"
        
        // Print to console
        print(formattedMessage)
        
        // Save to file if it's a high-priority log or if saveDebugFiles is enabled
        if shouldSaveDebugFiles && (level == .error || level == .warning) {
            saveLogToFile(level: level, message: formattedMessage)
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Log a verbose message
    static func verbose(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.verbose, message, file: file, function: function, line: line)
    }
    
    /// Log a debug message
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, file: file, function: function, line: line)
    }
    
    /// Log an info message
    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, file: file, function: function, line: line)
    }
    
    /// Log a warning message
    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message, file: file, function: function, line: line)
    }
    
    /// Log an error message
    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, file: file, function: function, line: line)
    }
    
    // MARK: - File Saving
    
    /// Saves important logs to file
    /// - Parameters:
    ///   - level: The log level
    ///   - message: The formatted message to save
    private static func saveLogToFile(level: Level, message: String) {
        let fileManager = FileManager.default
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
        let downloadsURL = homeDirectoryURL.appendingPathComponent("Downloads")
        
        // Create a timestamped filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        
        let logFileName = "PhysCloudResume_\(dateString)_log.txt"
        let fileURL = downloadsURL.appendingPathComponent(logFileName)
        
        // Create timestamp for this log entry
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())
        
        // Format the log entry with timestamp
        let logEntry = "[\(timestamp)] \(message)\n"
        
        do {
            // Check if file exists
            if fileManager.fileExists(atPath: fileURL.path) {
                // Append to existing file
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                fileHandle.seekToEndOfFile()
                if let data = logEntry.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                // Create new file
                try logEntry.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            // Just print to console if file operations fail
            Logger.debug("📝 Failed to write log to file: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Debug File Methods
    
    /// Saves debug content to a file in the Downloads folder if debug file saving is enabled
    /// - Parameters:
    ///   - content: The content to save
    ///   - fileName: The name of the file
    ///   - forceWrite: Whether to write even if debug file saving is disabled
    /// - Returns: Whether the write was successful
    @discardableResult
    static func saveDebugToFile(content: String, fileName: String, forceWrite: Bool = false) -> Bool {
        // Only save if debug file saving is enabled or forced
        guard shouldSaveDebugFiles || forceWrite else {
            verbose("Debug file saving disabled - not saving \(fileName)")
            return false
        }
        
        let fileManager = FileManager.default
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
        let downloadsURL = homeDirectoryURL.appendingPathComponent("Downloads")
        let fileURL = downloadsURL.appendingPathComponent(fileName)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            debug("Saved debug file: \(fileName)")
            return true
        } catch {
            warning("Failed to save debug file \(fileName): \(error.localizedDescription)")
            return false
        }
    }
    
    /// Logs API request details to console and optionally to file
    /// - Parameters:
    ///   - url: The request URL
    ///   - method: The HTTP method
    ///   - headers: The request headers
    ///   - body: The request body
    static func logAPIRequest(url: URL, method: String, headers: [String: String]?, body: Data?) {
        // Only log if debug level is sufficient
        guard minimumLevel.rawValue <= Level.debug.rawValue else {
            return
        }
        
        var message = "API Request: \(method) \(url.absoluteString)"
        
        if let headers = headers {
            message += "\nHeaders: \(headers)"
        }
        
        if let body = body, let bodyString = String(data: body, encoding: .utf8) {
            message += "\nBody: \(bodyString)"
        }
        
        debug(message)
        
        // Save to file if enabled
        if shouldSaveDebugFiles {
            // Create a unique filename based on timestamp
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            
            let fileName = "API_Request_\(timestamp).txt"
            saveDebugToFile(content: message, fileName: fileName)
        }
    }
    
    /// Logs API response details to console and optionally to file
    /// - Parameters:
    ///   - url: The request URL
    ///   - statusCode: The HTTP status code
    ///   - headers: The response headers
    ///   - data: The response data
    static func logAPIResponse(url: URL, statusCode: Int, headers: [AnyHashable: Any]?, data: Data?) {
        // Create appropriate log level based on status code
        let level: Level = (200..<300).contains(statusCode) ? .debug : .warning
        
        // Only log if log level is sufficient
        guard minimumLevel.rawValue <= level.rawValue else {
            return
        }
        
        var message = "API Response: \(statusCode) from \(url.absoluteString)"
        
        if let headers = headers {
            message += "\nHeaders: \(headers)"
        }
        
        if let data = data {
            let dataSize = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            message += "\nData size: \(dataSize)"
            
            if let responseString = String(data: data, encoding: .utf8) {
                message += "\nResponse: \(responseString)"
            }
        }
        
        log(level, message)
        
        // Save to file if enabled or if this is an error response
        if shouldSaveDebugFiles || statusCode >= 400 {
            // Create a unique filename based on timestamp
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            
            let fileName = "API_Response_\(statusCode)_\(timestamp).txt"
            saveDebugToFile(content: message, fileName: fileName, forceWrite: statusCode >= 400)
        }
    }
}
