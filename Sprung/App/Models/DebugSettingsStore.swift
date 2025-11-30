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
        var swiftOpenAILogLevel: _SwiftOpenAIClient.LogLevel {
            switch self {
            case .quiet:
                return .quiet
            case .info:
                return .info
            case .verbose:
                // Verbose mode should suppress noisy network debug logs
                // Only enable full SwiftOpenAI debug output when in Debug mode
                return .info
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
            _SwiftOpenAIClient.setLogLevel(logLevelSetting.swiftOpenAILogLevel)
        }
    }
    var saveDebugPrompts: Bool {
        didSet {
            defaults.set(saveDebugPrompts, forKey: Keys.saveDebugPrompts)
            Logger.updateFileLogging(isEnabled: saveDebugPrompts)
        }
    }
    var showOnboardingDebugButton: Bool {
        didSet {
            defaults.set(showOnboardingDebugButton, forKey: Keys.showOnboardingDebugButton)
        }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedLevel = LogLevelSetting(rawValue: defaults.integer(forKey: Keys.debugLogLevel)) ?? .info
        self.logLevelSetting = storedLevel
        self.saveDebugPrompts = defaults.bool(forKey: Keys.saveDebugPrompts)
        self.showOnboardingDebugButton = defaults.object(forKey: Keys.showOnboardingDebugButton) as? Bool ?? true
        // Apply persisted settings to the logging facade on initialization.
        Logger.updateMinimumLevel(storedLevel.loggerLevel)
        Logger.updateFileLogging(isEnabled: saveDebugPrompts)
        _SwiftOpenAIClient.setLogLevel(storedLevel.swiftOpenAILogLevel)
    }
    private enum Keys {
        static let debugLogLevel = "debugLogLevel"
        static let saveDebugPrompts = "saveDebugPrompts"
        static let showOnboardingDebugButton = "showOnboardingDebugButton"
    }
}
