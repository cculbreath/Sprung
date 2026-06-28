//
//  SwiftDataStore.swift
//  Sprung
//
//  A protocol that provides a shared `saveContext()` helper for stores
//  that hold a SwiftData `ModelContext`. Uses weak reference to avoid
//  crashes during container teardown.
//
import Foundation
import SwiftData

@MainActor
protocol SwiftDataStore: AnyObject {
    /// The model context for SwiftData persistence.
    var modelContext: ModelContext { get }
}

extension SwiftDataStore {
    /// Attempts to `save()`. On failure it logs (in *all* builds, so release
    /// installs at least leave a Console trace) and surfaces a throttled error
    /// toast so the user knows their latest edit may not have persisted.
    /// Returns false if save fails — callers that can roll back should.
    @discardableResult
    func saveContext(file: StaticString = #fileID, line: UInt = #line) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            Logger.error(
                "SwiftData save failed: \(error.localizedDescription)",
                category: .storage,
                metadata: [
                    "file": String(describing: file),
                    "line": String(line)
                ]
            )
            SaveFailureToastThrottle.showIfNeeded()
            return false
        }
    }
}

/// Throttles SwiftData save-failure toasts so a persistently-failing context
/// doesn't spam the user with one toast per mutation. A single failure surfaces
/// immediately; repeats inside the window are suppressed (the first toast still
/// stands).
@MainActor
enum SaveFailureToastThrottle {
    private static var lastShown: Date?
    private static let interval: TimeInterval = 10

    static func showIfNeeded() {
        let now = Date()
        if let last = lastShown, now.timeIntervalSince(last) < interval {
            return
        }
        lastShown = now
        ToastCenter.shared.show(
            .error("Couldn't save your changes — your latest edit may not persist.")
        )
    }
}
