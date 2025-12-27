//
//  SearchOpsSettingsStore.swift
//  Sprung
//
//  Store for managing SearchOps module settings (UserDefaults-backed).
//

import Foundation

@Observable
@MainActor
final class SearchOpsSettingsStore {
    private var cached: SearchOpsSettings?

    init() {}

    func current() -> SearchOpsSettings {
        if let cached {
            return cached
        }
        let settings = SearchOpsSettings.load()
        cached = settings
        return settings
    }

    func update(_ settings: SearchOpsSettings) {
        settings.save()
        cached = settings
    }

    /// Update notification fatigue tracking
    func recordNotificationClicked() {
        var settings = current()
        settings.lastNotificationClickedAt = Date()
        settings.notificationFatiguePauseOffered = false
        settings.save()
        cached = settings
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
        var settings = current()
        settings.notificationFatiguePauseOffered = true
        settings.save()
        cached = settings
    }

    func pauseNotifications() {
        var settings = current()
        settings.notificationsEnabled = false
        settings.notificationsPausedAt = Date()
        settings.save()
        cached = settings
    }
}
