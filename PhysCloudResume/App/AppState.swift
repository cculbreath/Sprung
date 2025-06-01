//
//  AppState.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

import Observation
import SwiftUI

@Observable
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
    
    // OpenRouter service - initialized lazily to avoid main actor issues
    private var _openRouterService: OpenRouterService?
    
    var openRouterService: OpenRouterService {
        if let service = _openRouterService {
            return service
        } else {
            // Initialize on main actor if needed
            if Thread.isMainThread {
                let service = OpenRouterService.shared
                _openRouterService = service
                return service
            } else {
                // For non-main thread access, we need to dispatch to main
                return DispatchQueue.main.sync {
                    let service = OpenRouterService.shared
                    _openRouterService = service
                    return service
                }
            }
        }
    }
    
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
        let apiKey = UserDefaults.standard.string(forKey: "openRouterApiKey") ?? ""
        if !apiKey.isEmpty {
            Task { @MainActor in
                openRouterService.configure(apiKey: apiKey)
            }
        }
    }
    
}
