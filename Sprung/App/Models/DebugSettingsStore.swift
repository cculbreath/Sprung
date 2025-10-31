//
//  DebugSettingsStore.swift
//  Sprung
//

import Foundation
import Observation

@Observable
final class DebugSettingsStore {
    enum LogLevelSetting: Int, CaseIterable, Identifiable {
        case quiet = 0
        case info = 1
        case verbose = 2
        case debug = 3

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .quiet:
                return "Quiet"
            case .info:
                return "Info"
            case .verbose:
                return "Verbose"
            case .debug:
                return "Debug"
            }
        }

        var loggerLevel: Logger.Level {
            switch self {
            case .quiet:
                return .error
            case .info:
                return .info
            case .verbose:
                return .verbose
            case .debug:
                return .debug
            }
        }

        var swiftOpenAILogLevel: SwiftOpenAIClient.LogLevel {
            switch self {
            case .quiet:
                return .quiet
            case .info:
                return .info
            case .verbose:
                return .verbose
            case .debug:
                return .debug
            }
        }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    var logLevelSetting: LogLevelSetting {
        didSet {
            defaults.set(logLevelSetting.rawValue, forKey: Keys.debugLogLevel)
            Logger.updateMinimumLevel(logLevelSetting.loggerLevel)
            SwiftOpenAIClient.setLogLevel(logLevelSetting.swiftOpenAILogLevel)
        }
    }

    var saveDebugPrompts: Bool {
        didSet {
            defaults.set(saveDebugPrompts, forKey: Keys.saveDebugPrompts)
            Logger.updateFileLogging(isEnabled: saveDebugPrompts)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedLevel = LogLevelSetting(rawValue: defaults.integer(forKey: Keys.debugLogLevel)) ?? .info
        self.logLevelSetting = storedLevel
        self.saveDebugPrompts = defaults.bool(forKey: Keys.saveDebugPrompts)

        // Apply persisted settings to the logging facade on initialization.
        Logger.updateMinimumLevel(storedLevel.loggerLevel)
        Logger.updateFileLogging(isEnabled: saveDebugPrompts)
        SwiftOpenAIClient.setLogLevel(storedLevel.swiftOpenAILogLevel)
    }

    private enum Keys {
        static let debugLogLevel = "debugLogLevel"
        static let saveDebugPrompts = "saveDebugPrompts"
    }
}
