//
//  NavigationStateService.swift
//  Sprung
//
import Foundation
import Observation
import SwiftData
@MainActor
@Observable
final class NavigationStateService {
    private enum StorageKeys {
        static let selectedTab = "selectedTab"
        static let selectedJobAppId = "selectedJobAppId"
    }
    var selectedTab: TabList {
        didSet {
            UserDefaults.standard.set(selectedTab.rawValue, forKey: StorageKeys.selectedTab)
        }
    }
    var selectedJobApp: JobApp? {
        didSet {
            if let jobApp = selectedJobApp {
                pendingSelectedJobAppId = jobApp.id
                UserDefaults.standard.set(jobApp.id.uuidString, forKey: StorageKeys.selectedJobAppId)
            } else {
                pendingSelectedJobAppId = nil
                UserDefaults.standard.removeObject(forKey: StorageKeys.selectedJobAppId)
            }
        }
    }
    var selectedResume: Resume? {
        selectedJobApp?.selectedRes
    }
    private var pendingSelectedJobAppId: UUID?
    init(defaultTab: TabList = .listing) {
        if let storedValue = UserDefaults.standard.string(forKey: StorageKeys.selectedTab),
           let storedTab = TabList(rawValue: storedValue) {
            selectedTab = storedTab
        } else {
            selectedTab = defaultTab
        }
        if let storedId = UserDefaults.standard.string(forKey: StorageKeys.selectedJobAppId),
           let uuid = UUID(uuidString: storedId) {
            pendingSelectedJobAppId = uuid
        }
    }
    func restoreSelectedJobApp(from jobAppStore: JobAppStore) {
        guard let identifier = pendingSelectedJobAppId ?? savedJobAppIdentifier() else {
            return
        }
        if let jobApp = jobAppStore.jobApps.first(where: { $0.id == identifier }) {
            jobAppStore.selectedApp = jobApp
            selectedJobApp = jobApp
            Logger.debug("✅ Restored selected job app: \(jobApp.jobPosition)")
        } else {
            pendingSelectedJobAppId = nil
            UserDefaults.standard.removeObject(forKey: StorageKeys.selectedJobAppId)
            Logger.debug("⚠️ Could not restore job app with ID: \(identifier.uuidString)")
        }
    }
    func saveSelectedJobApp(_ jobApp: JobApp?) {
        selectedJobApp = jobApp
    }
    private func savedJobAppIdentifier() -> UUID? {
        guard let storedId = UserDefaults.standard.string(forKey: StorageKeys.selectedJobAppId) else {
            return nil
        }
        return UUID(uuidString: storedId)
    }
}
