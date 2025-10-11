//
//  DebugSettingsStore.swift
//  Sprung
//

import Foundation
import Observation

@Observable
final class DebugSettingsStore {
    enum LogLevelSetting: Int, CaseIterable, Identifiable {
        case none = 0
        case basic = 1
        case verbose = 2

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .none: return "None"
            case .basic: return "Basic"
            case .verbose: return "Verbose"
            }
        }

        var loggerLevel: Logger.Level {
            switch self {
            case .none: return .error
            case .basic: return .info
            case .verbose: return .verbose
            }
        }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    var logLevelSetting: LogLevelSetting {
        didSet {
            defaults.set(logLevelSetting.rawValue, forKey: Keys.debugLogLevel)
            Logger.updateMinimumLevel(logLevelSetting.loggerLevel)
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
        let storedLevel = LogLevelSetting(rawValue: defaults.integer(forKey: Keys.debugLogLevel)) ?? .basic
        self.logLevelSetting = storedLevel
        self.saveDebugPrompts = defaults.bool(forKey: Keys.saveDebugPrompts)

        // Apply persisted settings to the logging facade on initialization.
        Logger.updateMinimumLevel(storedLevel.loggerLevel)
        Logger.updateFileLogging(isEnabled: saveDebugPrompts)
    }

    private enum Keys {
        static let debugLogLevel = "debugLogLevel"
        static let saveDebugPrompts = "saveDebugPrompts"
    }
}
