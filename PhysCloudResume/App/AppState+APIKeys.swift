//
//  AppState+APIKeys.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation

extension AppState {
    var openRouterApiKey: String {
        get { UserDefaults.standard.string(forKey: "openRouterApiKey") ?? "" }
        set { 
            UserDefaults.standard.set(newValue, forKey: "openRouterApiKey")
            Task { @MainActor in
                openRouterService.configure(apiKey: newValue)
            }
        }
    }
    
    var openAiApiKey: String {
        get { UserDefaults.standard.string(forKey: "openAiApiKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "openAiApiKey") }
    }
    
    var hasValidOpenRouterKey: Bool {
        !openRouterApiKey.isEmpty
    }
    
    var hasValidOpenAiKey: Bool {
        !openAiApiKey.isEmpty
    }
}
