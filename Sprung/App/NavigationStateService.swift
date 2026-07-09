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
            guard selectedTab != oldValue else { return }
            // Keep the toolbar phase segmented control in sync with phase changes
            // driven from elsewhere (ReadinessCards, navigate-then-act commands).
            NotificationCenter.default.post(name: .selectedTabChanged, object: nil)
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
