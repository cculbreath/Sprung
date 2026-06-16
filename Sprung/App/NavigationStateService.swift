//
//  NavigationStateService.swift
//  Sprung
//
//  Owns the editor tab selection only. The "current job" is owned solely by
//  JobAppStore.selectedApp (with UnifiedJobFocusState.focusedJob as its cross-module
//  focus mirror + single persistence key); this service no longer shadows it.
//
import Foundation
import Observation
@MainActor
@Observable
final class NavigationStateService {
    private enum StorageKeys {
        static let selectedTab = "selectedTab"
    }
    var selectedTab: TabList {
        didSet {
            UserDefaults.standard.set(selectedTab.rawValue, forKey: StorageKeys.selectedTab)
        }
    }
    init(defaultTab: TabList = .listing) {
        if let storedValue = UserDefaults.standard.string(forKey: StorageKeys.selectedTab),
           let storedTab = TabList(rawValue: storedValue) {
            selectedTab = storedTab
        } else {
            selectedTab = defaultTab
        }
    }
}
