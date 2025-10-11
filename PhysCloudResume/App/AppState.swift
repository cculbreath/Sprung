//
//  AppState.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

import Observation
import SwiftUI
import SwiftData

@Observable
@MainActor
class AppState {
    init(openRouterService: OpenRouterService, modelValidationService: ModelValidationService) {
        self.openRouterService = openRouterService
        self.modelValidationService = modelValidationService
        configureOpenRouterService()
    }
    var isReadOnlyMode = false
    
    // OpenRouter service
    let openRouterService: OpenRouterService
    
    let modelValidationService: ModelValidationService

    // Debug/diagnostics settings
    var debugSettingsStore: DebugSettingsStore?

    private func configureOpenRouterService() {
        // Ensure migration from UserDefaults to Keychain (one-time, idempotent)
        APIKeyManager.migrateFromUserDefaults()
        let openRouterApiKey = APIKeyManager.get(.openRouter) ?? ""
        if !openRouterApiKey.isEmpty {
            openRouterService.configure(apiKey: openRouterApiKey)
        }
    }
    
    func reconfigureOpenRouterService(using llmService: LLMService) {
        configureOpenRouterService()
        // Also reconfigure LLMService to use the updated API key
        llmService.reconfigureClient()
    }
}
