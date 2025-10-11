//
//  AppState+Settings.swift
//  Sprung
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation

/// Extension to AppState to provide access to application settings
extension AppState {
    /// Application settings manager
    class SettingsManager {
        /// Gets the selected models for batch cover letter generation
        var batchCoverLetterModels: Set<String> {
            get {
                if let array = UserDefaults.standard.array(forKey: "batchCoverLetterModels") as? [String] {
                    return Set(array)
                }
                return []
            }
            set {
                UserDefaults.standard.set(Array(newValue), forKey: "batchCoverLetterModels")
            }
        }
        
        /// Gets the selected models for multi-model cover letter selection
        var multiModelSelectedModels: Set<String> {
            get {
                if let array = UserDefaults.standard.array(forKey: "multiModelSelectedModels") as? [String] {
                    return Set(array)
                }
                return []
            }
            set {
                UserDefaults.standard.set(Array(newValue), forKey: "multiModelSelectedModels")
            }
        }
    }
    
    /// The settings manager for the application
    var settings: SettingsManager {
        return SettingsManager()
    }
}
