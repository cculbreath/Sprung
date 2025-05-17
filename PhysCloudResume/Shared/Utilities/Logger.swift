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
            saveLogToFile(message: formattedMessage)
        }
    }
    
    // MARK: - Convenience Methods
    
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
    
    /// Saves important logs to file
    /// - Parameters:
    ///   - message: The formatted message to save
    private static func saveLogToFile(message: String) {
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
}
