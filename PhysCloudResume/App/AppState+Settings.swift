//
//  AppState+Settings.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation

/// Extension to AppState to provide access to application settings
extension AppState {
    /// Application settings manager
    class SettingsManager {
        /// Gets the preferred LLM provider from UserDefaults
        var preferredLLMProvider: String {
            get {
                UserDefaults.standard.string(forKey: "preferredLLMProvider") ?? AIModels.Provider.openai
            }
            set {
                UserDefaults.standard.set(newValue, forKey: "preferredLLMProvider")
            }
        }
    }
    
    /// The settings manager for the application
    var settings: SettingsManager {
        return SettingsManager()
    }
}
