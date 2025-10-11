//
//  AppState+APIKeys.swift
//  Sprung
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation

extension AppState {
    var hasValidOpenRouterKey: Bool {
        let apiKey = APIKeyManager.get(.openRouter) ?? ""
        return !apiKey.isEmpty
    }
    
    var hasValidOpenAiKey: Bool {
        let apiKey = APIKeyManager.get(.openAI) ?? ""
        return !apiKey.isEmpty
    }
}
