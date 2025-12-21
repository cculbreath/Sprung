//
//  TimeTrackingService.swift
//  Sprung
//
//  Passive time tracking service for job search activities.
//  Tracks time spent in the app using NSApplication notifications.
//

import Foundation
import AppKit
import Combine

/// Service for tracking time spent on job search activities
@Observable
@MainActor
final class TimeTrackingService {

    // MARK: - Dependencies

    private let timeEntryStore: TimeEntryStore
    private let weeklyGoalStore: WeeklyGoalStore

    // MARK: - State

    private(set) var currentEntry: TimeEntry?
    private(set) var isTracking: Bool = false
    private(set) var currentActivity: ActivityType = .other

    /// Total time tracked today in minutes
    var todayMinutes: Int {
        timeEntryStore.totalMinutesForDate(Date())
    }

    /// Current session duration in seconds
    var currentSessionSeconds: Int {
        guard let entry = currentEntry else { return 0 }
        return Int(Date().timeIntervalSince(entry.startTime))
    }

    // MARK: - Private State

    private var appStateObservers: [NSObjectProtocol] = []
    private var idleTimer: Timer?
    private var lastActivityTime: Date = Date()
    private let idleThresholdSeconds: TimeInterval = 300 // 5 minutes

    // MARK: - Initialization

    init(timeEntryStore: TimeEntryStore, weeklyGoalStore: WeeklyGoalStore) {
        self.timeEntryStore = timeEntryStore
        self.weeklyGoalStore = weeklyGoalStore
    }

    nonisolated func cleanup() {
        Task { @MainActor in
            self.stopObserving()
        }
    }

    // MARK: - Public API

    /// Start observing app state for automatic time tracking
    func startObserving() {
        guard appStateObservers.isEmpty else { return }

        // App became active
        let activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppBecameActive()
            }
        }

        // App resigned active
        let resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppResignedActive()
            }
        }

        // App will terminate
        let terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopTracking()
            }
        }

        appStateObservers = [activeObserver, resignObserver, terminateObserver]

        // Start idle detection timer
        startIdleTimer()

        Logger.info("⏱️ TimeTrackingService started observing", category: .appLifecycle)
    }

    /// Stop observing app state
    func stopObserving() {
        for observer in appStateObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        appStateObservers.removeAll()
        stopIdleTimer()

        // End any active tracking
        stopTracking()

        Logger.info("⏱️ TimeTrackingService stopped observing", category: .appLifecycle)
    }

    /// Start tracking a specific activity
    func startTracking(activity: ActivityType) {
        // End any existing entry
        stopTracking()

        let entry = TimeEntry(activityType: activity, startTime: Date())
        entry.isAutomatic = false
        entry.trackingSource = .manual
        timeEntryStore.add(entry)

        currentEntry = entry
        currentActivity = activity
        isTracking = true
        lastActivityTime = Date()

        Logger.info("⏱️ Started tracking: \(activity.rawValue)", category: .ai)
    }

    /// Stop current tracking session
    func stopTracking() {
        guard let entry = currentEntry else { return }

        entry.endTime = Date()
        entry.durationSeconds = Int(entry.endTime!.timeIntervalSince(entry.startTime))

        // Only save if duration is meaningful (> 30 seconds)
        if entry.durationSeconds > 30 {
            timeEntryStore.update(entry)

            // Add to weekly goal
            weeklyGoalStore.addTimeMinutes(entry.durationMinutes)

            Logger.info("⏱️ Stopped tracking: \(entry.durationMinutes) minutes", category: .ai)
        } else {
            // Delete short entries
            timeEntryStore.delete(entry)
        }

        currentEntry = nil
        isTracking = false
    }

    /// Switch to a different activity type
    func switchActivity(to activity: ActivityType) {
        stopTracking()
        startTracking(activity: activity)
    }

    /// Record user activity (resets idle timer)
    func recordActivity() {
        lastActivityTime = Date()
    }

    // MARK: - Private Methods

    private func handleAppBecameActive() {
        // Resume or start tracking
        if currentEntry == nil {
            // Start automatic tracking
            let entry = TimeEntry(activityType: .other, startTime: Date())
            entry.isAutomatic = true
            entry.trackingSource = .appForeground
            timeEntryStore.add(entry)

            currentEntry = entry
            currentActivity = .other
            isTracking = true
        }

        lastActivityTime = Date()
        startIdleTimer()

        Logger.debug("⏱️ App became active - tracking resumed", category: .appLifecycle)
    }

    private func handleAppResignedActive() {
        // Pause tracking when app loses focus
        stopTracking()
        stopIdleTimer()

        Logger.debug("⏱️ App resigned active - tracking paused", category: .appLifecycle)
    }

    private func startIdleTimer() {
        stopIdleTimer()

        idleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdleState()
            }
        }
    }

    private func stopIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func checkIdleState() {
        let idleTime = Date().timeIntervalSince(lastActivityTime)

        if idleTime >= idleThresholdSeconds && isTracking {
            // User has been idle - stop tracking
            Logger.info("⏱️ User idle for \(Int(idleTime))s - stopping tracking", category: .ai)
            stopTracking()
        }
    }
}
