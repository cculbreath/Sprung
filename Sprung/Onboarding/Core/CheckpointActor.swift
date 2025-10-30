//
//  CheckpointActor.swift
//  Sprung
//
//  Provides lightweight persistence for interview session checkpoints.
//

import Foundation
import SwiftyJSON

struct InterviewCheckpoint: Codable {
    let timestamp: Date
    let phase: InterviewPhase
    let objectivesDone: [String]
    let applicantProfile: String?
    let skeletonTimeline: String?
    let enabledSections: [String]?
    let objectiveLedger: [ObjectiveEntry]

    enum CodingKeys: String, CodingKey {
        case timestamp
        case phase
        case objectivesDone
        case applicantProfile
        case skeletonTimeline
        case enabledSections
        case objectiveLedger
    }

    init(
        timestamp: Date,
        phase: InterviewPhase,
        objectivesDone: [String],
        applicantProfile: String?,
        skeletonTimeline: String?,
        enabledSections: [String]?,
        objectiveLedger: [ObjectiveEntry] = []
    ) {
        self.timestamp = timestamp
        self.phase = phase
        self.objectivesDone = objectivesDone
        self.applicantProfile = applicantProfile
        self.skeletonTimeline = skeletonTimeline
        self.enabledSections = enabledSections
        self.objectiveLedger = objectiveLedger
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        phase = try container.decode(InterviewPhase.self, forKey: .phase)
        objectivesDone = try container.decode([String].self, forKey: .objectivesDone)
        applicantProfile = try container.decodeIfPresent(String.self, forKey: .applicantProfile)
        skeletonTimeline = try container.decodeIfPresent(String.self, forKey: .skeletonTimeline)
        enabledSections = try container.decodeIfPresent([String].self, forKey: .enabledSections)
        objectiveLedger = try container.decodeIfPresent([ObjectiveEntry].self, forKey: .objectiveLedger) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(phase, forKey: .phase)
        try container.encode(objectivesDone, forKey: .objectivesDone)
        try container.encodeIfPresent(applicantProfile, forKey: .applicantProfile)
        try container.encodeIfPresent(skeletonTimeline, forKey: .skeletonTimeline)
        try container.encodeIfPresent(enabledSections, forKey: .enabledSections)
        try container.encode(objectiveLedger, forKey: .objectiveLedger)
    }
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
            Logger.debug("Failed to create checkpoint directory: \(error)")
        }
        return directory.appendingPathComponent("Interview.checkpoints.json")
    }()

    init() {
        history = Self.loadHistory(from: url, limit: maxHistoryCount)
    }

    func save(
        from session: InterviewSession,
        applicantProfile: JSON?,
        skeletonTimeline: JSON?,
        enabledSections: [String]?
    ) async {
        let profileString = applicantProfile?.rawString(options: .sortedKeys)
        let timelineString = skeletonTimeline?.rawString(options: .sortedKeys)
        let sections = enabledSections?.isEmpty == false ? enabledSections : nil
        history.append(
            InterviewCheckpoint(
                timestamp: Date(),
                phase: session.phase,
                objectivesDone: Array(session.objectivesDone),
                applicantProfile: profileString,
                skeletonTimeline: timelineString,
                enabledSections: sections,
                objectiveLedger: session.objectiveLedger
            )
        )

        if history.count > maxHistoryCount {
            history.removeFirst(history.count - maxHistoryCount)
        }

        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.debug("Checkpoint save failed: \(error)")
        }
    }

    func restoreLatest() async -> (InterviewSession, JSON?, JSON?, [String]?, [ObjectiveEntry])? {
        history = Self.loadHistory(from: url, limit: maxHistoryCount)
        guard let latest = history.max(by: { $0.timestamp < $1.timestamp }) else {
            return nil
        }

        var session = InterviewSession()
        session.phase = latest.phase
        session.objectivesDone = Set(latest.objectivesDone)
        session.objectiveLedger = latest.objectiveLedger

        let profileJSON = latest.applicantProfile.flatMap { JSON(parseJSON: $0) }
        let timelineJSON = latest.skeletonTimeline.flatMap { JSON(parseJSON: $0) }
        return (session, profileJSON, timelineJSON, latest.enabledSections, latest.objectiveLedger)
    }

    func hasCheckpoint() async -> Bool {
        history = Self.loadHistory(from: url, limit: maxHistoryCount)
        return history.last != nil
    }

    func clear() async {
        history.removeAll()
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            Logger.debug("Failed to clear checkpoints: \(error)")
        }
    }

    private static func loadHistory(from url: URL, limit: Int) -> [InterviewCheckpoint] {
        guard
            let data = try? Data(contentsOf: url),
            let checkpoints = try? JSONDecoder().decode([InterviewCheckpoint].self, from: data)
        else {
            return []
        }

        if checkpoints.count > limit {
            return Array(checkpoints.suffix(limit))
        }

        return checkpoints
    }
}
