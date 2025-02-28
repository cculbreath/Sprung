//
//  AppState.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/30/25.
//

import Observation
import SwiftUI

@Observable
class AppState {
    var showNewAppSheet: Bool = false
    var showSlidingList: Bool = false
    var selectedTab: TabList = .listing
    var dragInfo = DragInfo()
}
