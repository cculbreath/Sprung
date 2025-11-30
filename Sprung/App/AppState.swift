//
//  AppState.swift
//  Sprung
//
//  Created by Christopher Culbreath on 1/31/25.
//
import Foundation
import Observation
import SwiftUI
import SwiftData
@Observable
@MainActor
class AppState {
    init(openRouterService: OpenRouterService, modelValidationService: ModelValidationService) {
        self.openRouterService = openRouterService
        self.modelValidationService = modelValidationService
        updateOpenRouterConfiguration(configureClient: true)
        refreshOpenAiKeyState()
        observeAPIKeyChanges()
    }
    var isReadOnlyMode = false
    // OpenRouter service
    let openRouterService: OpenRouterService
    let modelValidationService: ModelValidationService
    // Debug/diagnostics settings
    var debugSettingsStore: DebugSettingsStore?
    // Cached API key state for SwiftUI bindings
    var openRouterApiKey: String = ""
    var openAiApiKey: String = ""
    @ObservationIgnored
    private var apiKeysObserver: NSObjectProtocol?
    deinit {
        if let apiKeysObserver {
            NotificationCenter.default.removeObserver(apiKeysObserver)
        }
    }
    private func updateOpenRouterConfiguration(configureClient: Bool) {
        let key = normalizedKey(for: .openRouter)
        openRouterApiKey = key
        guard configureClient, !key.isEmpty else {
            return
        }
        openRouterService.configure(apiKey: key)
    }
    private func refreshOpenAiKeyState() {
        openAiApiKey = normalizedKey(for: .openAI)
    }
    private func observeAPIKeyChanges() {
        apiKeysObserver = NotificationCenter.default.addObserver(
            forName: .apiKeysChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleAPIKeysChanged()
            }
        }
    }
    func reconfigureOpenRouterService(using llmService: _LLMService) {
        updateOpenRouterConfiguration(configureClient: true)
        refreshOpenAiKeyState()
        // Also reconfigure LLMService to use the updated API key
        llmService.reconfigureClient()
    }
    private func normalizedKey(for type: APIKeyType) -> String {
        guard let raw = APIKeyManager.get(type)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return ""
        }
        if raw.caseInsensitiveCompare("none") == .orderedSame {
            return ""
        }
        return raw.components(separatedBy: .newlines).joined()
    }
    @MainActor
    private func handleAPIKeysChanged() {
        updateOpenRouterConfiguration(configureClient: false)
        refreshOpenAiKeyState()
    }
}
