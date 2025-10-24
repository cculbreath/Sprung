//
//  CheckpointActor.swift
//  Sprung
//
//  Provides lightweight persistence for interview session checkpoints.
//

import Foundation

struct InterviewCheckpoint: Codable {
    let timestamp: Date
    let phase: InterviewPhase
    let objectivesDone: [String]
    let applicantProfile: String?
    let skeletonTimeline: String?
}

actor Checkpoints {
    private var history: [InterviewCheckpoint] = []
    private let maxHistoryCount = 8
    private let url: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let directory = appSupport.appendingPathComponent("Onboarding", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            debugLog("Failed to create checkpoint directory: \(error)")
        }
        return directory.appendingPathComponent("Interview.checkpoints.json")
    }()

    func save(from session: InterviewSession, applicantProfile: JSON?, skeletonTimeline: JSON?) async {
        let profileString = applicantProfile?.rawString(options: .sortedKeys)
        let timelineString = skeletonTimeline?.rawString(options: .sortedKeys)
        history.append(
            InterviewCheckpoint(
                timestamp: Date(),
                phase: session.phase,
                objectivesDone: Array(session.objectivesDone),
                applicantProfile: profileString,
                skeletonTimeline: timelineString
            )
        )

        if history.count > maxHistoryCount {
            history.removeFirst(history.count - maxHistoryCount)
        }

        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: url, options: .atomic)
        } catch {
            debugLog("Checkpoint save failed: \(error)")
        }
    }

    func restoreLatest() async -> (InterviewSession, JSON?, JSON?)? {
        guard
            let data = try? Data(contentsOf: url),
            let checkpoints = try? JSONDecoder().decode([InterviewCheckpoint].self, from: data),
            let latest = checkpoints.max(by: { $0.timestamp < $1.timestamp })
        else {
            return nil
        }

        var session = InterviewSession()
        session.phase = latest.phase
        session.objectivesDone = Set(latest.objectivesDone)

        let profileJSON = latest.applicantProfile.flatMap { JSON(parseJSON: $0) }
        let timelineJSON = latest.skeletonTimeline.flatMap { JSON(parseJSON: $0) }
        return (session, profileJSON, timelineJSON)
    }
}
