//
//  DebugSettingsStore.swift
//  Sprung
//
import Foundation
import Observation
@Observable
final class DebugSettingsStore {

    /// Controls extended thinking depth for resume customization LLM calls.
    /// On Opus 4.6, adaptive thinking always activates when enabled (effort is ignored).
    /// On older/non-Anthropic models, effort maps to the provider's native reasoning param.
    /// `.off` disables reasoning entirely.
    enum ReasoningEffortLevel: Int, CaseIterable, Identifiable {
        case off = 0
        case low = 1
        case medium = 2
        case high = 3

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .off: return "Off"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            }
        }

        /// Returns the effort string for OpenRouter, or nil when off.
        var effortString: String? {
            switch self {
            case .off: return nil
            case .low: return "low"
            case .medium: return "medium"
            case .high: return "high"
            }
        }
    }

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
        var swiftOpenAILogLevel: SwiftOpenAIClientWrapper.LogLevel {
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
            SwiftOpenAIClientWrapper.setLogLevel(logLevelSetting.swiftOpenAILogLevel)
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
    var logLLMTranscripts: Bool {
        didSet {
            defaults.set(logLLMTranscripts, forKey: Keys.logLLMTranscripts)
        }
    }

    var customizationReasoningEffort: ReasoningEffortLevel {
        didSet {
            defaults.set(customizationReasoningEffort.rawValue, forKey: Keys.customizationReasoningEffort)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedLevel = LogLevelSetting(rawValue: defaults.integer(forKey: Keys.debugLogLevel)) ?? .info
        self.logLevelSetting = storedLevel
        self.saveDebugPrompts = defaults.bool(forKey: Keys.saveDebugPrompts)
        self.showOnboardingDebugButton = defaults.object(forKey: Keys.showOnboardingDebugButton) as? Bool ?? true
        self.logLLMTranscripts = defaults.bool(forKey: Keys.logLLMTranscripts)
        self.customizationReasoningEffort = ReasoningEffortLevel(rawValue: defaults.integer(forKey: Keys.customizationReasoningEffort)) ?? .off
        // Apply persisted settings to the logging facade on initialization.
        Logger.updateMinimumLevel(storedLevel.loggerLevel)
        Logger.updateFileLogging(isEnabled: saveDebugPrompts)
        SwiftOpenAIClientWrapper.setLogLevel(storedLevel.swiftOpenAILogLevel)
    }
    private enum Keys {
        static let debugLogLevel = "debugLogLevel"
        static let saveDebugPrompts = "saveDebugPrompts"
        static let showOnboardingDebugButton = "showOnboardingDebugButton"
        static let logLLMTranscripts = "logLLMTranscripts"
        static let customizationReasoningEffort = "customizationReasoningEffort"
    }
}
