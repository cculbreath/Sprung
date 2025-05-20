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
    
    // AI model service
    let modelService = ModelService()
}
