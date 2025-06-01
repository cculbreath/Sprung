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
    
    // AI model service
    let modelService = ModelService()
    
    // Selected models storage - directly observable with @Observable
    var selectedModels: Set<String> = Set() {
        didSet {
            // Save to UserDefaults when changed
            do {
                let data = try JSONEncoder().encode(selectedModels)
                UserDefaults.standard.set(data, forKey: "selectedModelsData")
            } catch {
                print("Failed to encode selected models: \(error)")
            }
        }
    }
    
    init() {
        // Load saved models on init
        loadSelectedModels()
    }
    
    private func loadSelectedModels() {
        let data = UserDefaults.standard.data(forKey: "selectedModelsData") ?? Data()
        if !data.isEmpty {
            do {
                selectedModels = try JSONDecoder().decode(Set<String>.self, from: data)
            } catch {
                print("Failed to decode selected models: \(error)")
                selectedModels = Set()
            }
        }
    }
    
}
