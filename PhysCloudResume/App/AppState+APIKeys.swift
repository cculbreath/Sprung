//
//  AppState+APIKeys.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation

extension AppState {
    var hasValidOpenRouterKey: Bool {
        let apiKey = UserDefaults.standard.string(forKey: "openRouterApiKey") ?? ""
        return !apiKey.isEmpty
    }
    
    var hasValidOpenAiKey: Bool {
        let apiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? ""
        return !apiKey.isEmpty
    }
}
