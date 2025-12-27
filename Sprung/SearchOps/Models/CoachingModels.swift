//
//  CoachingModels.swift
//  Sprung
//
//  Models for the Job Search Coach feature.
//  Stores coaching session history including activity snapshots,
//  multiple-choice Q&A, and LLM recommendations.
//

import Foundation
import SwiftData

// MARK: - Coaching Session Model

@Model
class CoachingSession: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()

    var sessionDate: Date = Date()

    // Activity snapshot (JSON encoded)
    var activitySummaryJSON: String?

    // Q&A history (JSON encoded arrays)
    var questionsJSON: String?
    var answersJSON: String?

    // Final coaching output
    var recommendations: String = ""

    // Pace tracking
    var daysSinceLastSession: Int = 0
    var daysSinceLastAppOpen: Int = 0

    // Session metadata
    var questionCount: Int = 0
    var completedAt: Date?
    var llmModel: String?

    var createdAt: Date = Date()

    init() {}

    // MARK: - JSON Decode Helpers

    var activitySummary: ActivitySnapshot? {
        get {
            guard let json = activitySummaryJSON else { return nil }
            return try? JSONDecoder().decode(ActivitySnapshot.self, from: Data(json.utf8))
        }
        set {
            activitySummaryJSON = newValue.flatMap {
                try? String(data: JSONEncoder().encode($0), encoding: .utf8)
            }
        }
    }

    var questions: [CoachingQuestion] {
        get {
            guard let json = questionsJSON else { return [] }
            return (try? JSONDecoder().decode([CoachingQuestion].self, from: Data(json.utf8))) ?? []
        }
        set {
            questionsJSON = try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)
        }
    }

    var answers: [CoachingAnswer] {
        get {
            guard let json = answersJSON else { return [] }
            return (try? JSONDecoder().decode([CoachingAnswer].self, from: Data(json.utf8))) ?? []
        }
        set {
            answersJSON = try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)
        }
    }

    /// Check if this session is for today
    var isToday: Bool {
        Calendar.current.isDateInToday(sessionDate)
    }

    /// Check if session is complete (has recommendations)
    var isComplete: Bool {
        !recommendations.isEmpty && completedAt != nil
    }
}

// MARK: - Activity Snapshot

struct ActivitySnapshot: Codable {
    // Job Applications
    var newJobApps: Int = 0
    var jobAppCompanies: [String] = []
    var jobAppPositions: [String] = []
    var stageChanges: [StageChange] = []

    // Materials
    var resumesCreated: Int = 0
    var resumesModified: Int = 0
    var coverLettersCreated: Int = 0
    var coverLettersModified: Int = 0

    // Networking
    var eventsAdded: Int = 0
    var eventsAttended: Int = 0
    var eventsDebriefed: Int = 0
    var contactsAdded: Int = 0
    var interactionsLogged: Int = 0

    // Pace
    var daysSinceLastOpen: Int = 0
    var totalActiveMinutesToday: Int = 0

    struct StageChange: Codable {
        let jobAppId: UUID
        let company: String
        let position: String
        let fromStage: String
        let toStage: String
    }

    /// Check if there was any activity
    var hasActivity: Bool {
        newJobApps > 0 ||
        !stageChanges.isEmpty ||
        resumesCreated > 0 ||
        resumesModified > 0 ||
        coverLettersCreated > 0 ||
        coverLettersModified > 0 ||
        eventsAdded > 0 ||
        eventsAttended > 0 ||
        eventsDebriefed > 0 ||
        contactsAdded > 0 ||
        interactionsLogged > 0
    }

    /// Generate a human-readable summary for the LLM prompt
    func textSummary() -> String {
        var parts: [String] = []

        // Job applications
        if newJobApps > 0 {
            let companies = jobAppCompanies.prefix(3).joined(separator: ", ")
            parts.append("- Added \(newJobApps) new job application(s) at: \(companies)")
        }

        if !stageChanges.isEmpty {
            for change in stageChanges.prefix(5) {
                parts.append("- \(change.position) at \(change.company): \(change.fromStage) -> \(change.toStage)")
            }
        }

        // Materials
        if resumesCreated > 0 {
            parts.append("- Created \(resumesCreated) new resume(s)")
        }
        if resumesModified > 0 {
            parts.append("- Modified \(resumesModified) resume(s)")
        }
        if coverLettersCreated > 0 {
            parts.append("- Drafted \(coverLettersCreated) new cover letter(s)")
        }
        if coverLettersModified > 0 {
            parts.append("- Edited \(coverLettersModified) cover letter(s)")
        }

        // Networking
        if eventsAdded > 0 {
            parts.append("- Added \(eventsAdded) networking event(s) to calendar")
        }
        if eventsAttended > 0 {
            parts.append("- Attended \(eventsAttended) networking event(s)")
        }
        if eventsDebriefed > 0 {
            parts.append("- Completed debrief for \(eventsDebriefed) event(s)")
        }
        if contactsAdded > 0 {
            parts.append("- Added \(contactsAdded) new networking contact(s)")
        }
        if interactionsLogged > 0 {
            parts.append("- Logged \(interactionsLogged) networking interaction(s)")
        }

        // Time
        if totalActiveMinutesToday > 0 {
            let hours = totalActiveMinutesToday / 60
            let minutes = totalActiveMinutesToday % 60
            if hours > 0 {
                parts.append("- Time spent today: \(hours)h \(minutes)m")
            } else {
                parts.append("- Time spent today: \(minutes)m")
            }
        }

        // Pace
        if daysSinceLastOpen > 1 {
            parts.append("- Days since last app usage: \(daysSinceLastOpen)")
        }

        if parts.isEmpty {
            return "No activity recorded in the last 24 hours."
        }

        return parts.joined(separator: "\n")
    }
}

// MARK: - Coaching Question

enum CoachingQuestionType: String, Codable, CaseIterable, Equatable {
    case motivation = "motivation"
    case challenge = "challenge"
    case focus = "focus"
    case feedback = "feedback"

    var displayName: String {
        switch self {
        case .motivation: return "Motivation Check"
        case .challenge: return "Challenges"
        case .focus: return "Today's Focus"
        case .feedback: return "Feedback"
        }
    }
}

struct CoachingQuestion: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let questionText: String
    let options: [QuestionOption]
    let questionType: CoachingQuestionType

    init(questionText: String, options: [QuestionOption], questionType: CoachingQuestionType) {
        self.questionText = questionText
        self.options = options
        self.questionType = questionType
    }
}

struct QuestionOption: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let value: Int
    let label: String
    let emoji: String?

    init(value: Int, label: String, emoji: String? = nil) {
        self.value = value
        self.label = label
        self.emoji = emoji
    }
}

// MARK: - Coaching Answer

struct CoachingAnswer: Codable {
    let questionId: UUID
    let selectedValue: Int
    let selectedLabel: String
    let timestamp: Date

    init(questionId: UUID, selectedValue: Int, selectedLabel: String) {
        self.questionId = questionId
        self.selectedValue = selectedValue
        self.selectedLabel = selectedLabel
        self.timestamp = Date()
    }
}

// MARK: - Coaching State

enum CoachingState: Equatable {
    case idle
    case generatingReport
    case askingQuestion(question: CoachingQuestion, index: Int, total: Int)
    case waitingForAnswer
    case generatingRecommendations
    case complete(sessionId: UUID)
    case error(String)

    var isLoading: Bool {
        switch self {
        case .generatingReport, .generatingRecommendations:
            return true
        default:
            return false
        }
    }

    var isActive: Bool {
        switch self {
        case .idle, .complete, .error:
            return false
        default:
            return true
        }
    }
}
