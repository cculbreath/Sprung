//
//  Checkpoints.swift
//  Sprung
//
//  Provides lightweight persistence for interview session checkpoints.
//  Works with the centralized StateCoordinator system.
//

import Foundation
import SwiftyJSON

/// Represents a saved checkpoint of the interview state
struct OnboardingCheckpoint: Codable {
    let timestamp: Date
    let snapshot: StateCoordinator.StateSnapshot
    let profileJSON: String?
    let timelineJSON: String?
    let enabledSections: Set<String>
}

/// Manages checkpoint persistence for the onboarding interview
@MainActor
final class Checkpoints {
    private var history: [OnboardingCheckpoint] = []
    private let maxHistoryCount = 8

    private let url: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let directory = appSupport.appendingPathComponent("Onboarding", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            Logger.debug("Failed to create checkpoint directory: \(error)")
        }
        return directory.appendingPathComponent("Interview.checkpoints.json")
    }()

    init() {
        loadHistory()
    }

    /// Saves a checkpoint with the current state
    func save(
        snapshot: StateCoordinator.StateSnapshot,
        profileJSON: JSON?,
        timelineJSON: JSON?,
        enabledSections: Set<String>
    ) {
        let checkpoint = OnboardingCheckpoint(
            timestamp: Date(),
            snapshot: snapshot,
            profileJSON: profileJSON?.rawString(options: .sortedKeys),
            timelineJSON: timelineJSON?.rawString(options: .sortedKeys),
            enabledSections: enabledSections
        )

        history.append(checkpoint)

        // Trim history to max count
        if history.count > maxHistoryCount {
            history.removeFirst(history.count - maxHistoryCount)
        }

        persistHistory()
    }

    /// Restores the most recent checkpoint
    func restore() -> (
        snapshot: StateCoordinator.StateSnapshot,
        profileJSON: JSON?,
        timelineJSON: JSON?,
        enabledSections: Set<String>
    )? {
        guard let latest = history.max(by: { $0.timestamp < $1.timestamp }) else {
            return nil
        }

        let profileJSON = latest.profileJSON.flatMap { JSON(parseJSON: $0) }
        let timelineJSON = latest.timelineJSON.flatMap { JSON(parseJSON: $0) }

        return (
            snapshot: latest.snapshot,
            profileJSON: profileJSON,
            timelineJSON: timelineJSON,
            enabledSections: latest.enabledSections
        )
    }

    /// Checks if any checkpoints exist
    func hasCheckpoint() -> Bool {
        !history.isEmpty
    }

    /// Clears all checkpoints
    func clear() {
        history.removeAll()
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            Logger.debug("Failed to clear checkpoints: \(error)")
        }
    }

    // MARK: - Private Methods

    private func loadHistory() {
        guard
            let data = try? Data(contentsOf: url),
            let checkpoints = try? JSONDecoder().decode([OnboardingCheckpoint].self, from: data)
        else {
            history = []
            return
        }

        history = checkpoints.suffix(maxHistoryCount)
    }

    private func persistHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.debug("Checkpoint save failed: \(error)")
        }
    }
}