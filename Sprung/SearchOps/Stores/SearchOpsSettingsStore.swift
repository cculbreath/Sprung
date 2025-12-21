//
//  SearchOpsSettingsStore.swift
//  Sprung
//
//  Store for managing SearchOps module settings (singleton pattern).
//

import SwiftData
import Foundation

@Observable
@MainActor
final class SearchOpsSettingsStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    init(context: ModelContext) {
        modelContext = context
    }

    func current() -> SearchOpsSettings {
        let existing = try? modelContext.fetch(FetchDescriptor<SearchOpsSettings>())
        if let settings = existing?.first {
            return settings
        }
        let newSettings = SearchOpsSettings()
        modelContext.insert(newSettings)
        saveContext()
        return newSettings
    }

    func update(_ settings: SearchOpsSettings) {
        settings.updatedAt = Date()
        saveContext()
    }

    /// Update notification fatigue tracking
    func recordNotificationClicked() {
        let settings = current()
        settings.lastNotificationClickedAt = Date()
        settings.notificationFatiguePauseOffered = false
        saveContext()
    }

    /// Check if we should offer a notification pause due to fatigue
    func shouldOfferNotificationPause() -> Bool {
        let settings = current()
        guard settings.notificationsEnabled else { return false }
        guard !settings.notificationFatiguePauseOffered else { return false }

        guard let lastClicked = settings.lastNotificationClickedAt else {
            // Never clicked - check if enabled for 7+ days
            let daysSinceCreation = Calendar.current.dateComponents(
                [.day], from: settings.createdAt, to: Date()
            ).day ?? 0
            return daysSinceCreation >= 7
        }

        let daysSinceClick = Calendar.current.dateComponents(
            [.day], from: lastClicked, to: Date()
        ).day ?? 0
        return daysSinceClick >= 7
    }

    func markFatiguePauseOffered() {
        let settings = current()
        settings.notificationFatiguePauseOffered = true
        saveContext()
    }

    func pauseNotifications() {
        let settings = current()
        settings.notificationsEnabled = false
        settings.notificationsPausedAt = Date()
        saveContext()
    }
}
