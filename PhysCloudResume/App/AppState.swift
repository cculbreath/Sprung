//
//  AppState.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

import Observation
import SwiftUI

@Observable
@MainActor
class AppState {
    var showNewAppSheet: Bool = false
    var showSlidingList: Bool = false
    var selectedTab: TabList = .listing
    var dragInfo = DragInfo()

    // AI job recommendation properties
    var recommendedJobId: UUID?
    var isLoadingRecommendation: Bool = false
    
    // Import job apps sheet
    var showImportJobAppsSheet: Bool = false
    
    // Selected job app and resume for template editor
    var selectedJobApp: JobApp?
    var selectedResume: Resume? {
        selectedJobApp?.selectedRes
    }
    
    // OpenRouter service
    let openRouterService = OpenRouterService.shared
    
    // Selected OpenRouter models storage
    var selectedOpenRouterModels: Set<String> = Set() {
        didSet {
            do {
                let data = try JSONEncoder().encode(selectedOpenRouterModels)
                UserDefaults.standard.set(data, forKey: "selectedOpenRouterModels")
            } catch {
                print("Failed to encode selected OpenRouter models: \(error)")
            }
        }
    }
    
    init() {
        loadSelectedOpenRouterModels()
        configureOpenRouterService()
    }
    
    private func loadSelectedOpenRouterModels() {
        let data = UserDefaults.standard.data(forKey: "selectedOpenRouterModels") ?? Data()
        if !data.isEmpty {
            do {
                selectedOpenRouterModels = try JSONDecoder().decode(Set<String>.self, from: data)
            } catch {
                print("Failed to decode selected OpenRouter models: \(error)")
                selectedOpenRouterModels = Set()
            }
        }
    }
    
    private func configureOpenRouterService() {
        let openRouterApiKey = UserDefaults.standard.string(forKey: "openRouterApiKey") ?? ""
        if !openRouterApiKey.isEmpty {
            openRouterService.configure(apiKey: openRouterApiKey)
        }
    }
    
    func reconfigureOpenRouterService() {
        configureOpenRouterService()
        // Also reconfigure LLMService to use the updated API key
        LLMService.shared.reconfigureClient()
    }
}
