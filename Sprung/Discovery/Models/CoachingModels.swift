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

    // Question categories the coach asked this session (JSON-encoded [String]).
    // Fed back into later sessions so categories aren't repeated.
    var askedCategoriesJSON: String?

    // Final coaching output
    var recommendations: String = ""

    // Pace tracking
    var daysSinceLastSession: Int = 0
    var daysSinceLastAppOpen: Int = 0

    // Session metadata
    var questionCount: Int = 0
    var generatedTaskCount: Int = 0
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

    var askedCategories: [String] {
        get {
            guard let json = askedCategoriesJSON else { return [] }
            return (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
        }
        set {
            askedCategoriesJSON = try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)
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
    // Job Applications - with stage breakdown
    var newJobApps: Int = 0
    var jobAppCompanies: [String] = []
    var jobAppPositions: [String] = []
    var stageChanges: [StageChange] = []

    /// Breakdown of all job apps by stage (for overall context)
    var jobAppsByStage: JobAppStageBreakdown = JobAppStageBreakdown()

    struct JobAppStageBreakdown: Codable {
        var identified: Int = 0      // Gathered, no action taken
        var queued: Int = 0          // On deck, ready to work on
        var inProgress: Int = 0      // Actively working on
        var applied: Int = 0         // Actually submitted
        var interviewing: Int = 0    // In interview process
        var offer: Int = 0           // Have an offer
        var accepted: Int = 0        // Accepted offer
        var rejected: Int = 0        // Rejected or ghosted
        var withdrawn: Int = 0       // User withdrew

        var total: Int {
            identified + queued + inProgress + applied + interviewing + offer + accepted + rejected + withdrawn
        }

        var activeTotal: Int {
            identified + queued + inProgress + applied + interviewing + offer
        }

        var submittedTotal: Int {
            applied + interviewing + offer + accepted
        }
    }

    // Materials
    var resumesCreated: Int = 0
    var resumesModified: Int = 0
    var resumesWithLLMCustomization: Int = 0  // Resumes that have been AI-revised
    var coverLettersCreated: Int = 0
    var coverLettersModified: Int = 0

    // Cover letter details for context (excludes empty/uncomposed letters)
    var coverLetterDetails: [CoverLetterDetail] = []

    struct CoverLetterDetail: Codable {
        let jobAppId: UUID
        let company: String
        let position: String
        let letterName: String
        let isSelected: Bool
        /// Full content for selected letter, nil for non-selected
        let content: String?
        let generationModel: String?
    }

    // Networking Events - with status breakdown
    var eventsAdded: Int = 0
    var eventsAttended: Int = 0
    var eventsDebriefed: Int = 0
    var contactsAdded: Int = 0
    var interactionsLogged: Int = 0

    /// Breakdown of all events by status (for overall context)
    var eventsByStatus: EventStatusBreakdown = EventStatusBreakdown()

    /// Detailed info for upcoming/planned events and recently attended events
    var eventDetails: [EventDetail] = []

    struct EventDetail: Codable {
        let eventId: UUID
        let name: String
        let date: Date
        let time: String?
        let location: String
        let isVirtual: Bool
        let eventType: String
        let status: String
        let organizer: String?
        let estimatedAttendance: String?
        let goal: String?
        let attended: Bool
        let contactCount: Int?
        let eventNotes: String?

        /// Whether this event is in the future
        var isFuture: Bool {
            date > Date()
        }
    }

    struct EventStatusBreakdown: Codable {
        var discovered: Int = 0      // Just found, not yet evaluated
        var planned: Int = 0         // User committed to attend (on calendar)
        var attended: Int = 0        // User attended
        var debriefed: Int = 0       // Captured contacts/notes after attending
        var skipped: Int = 0         // User decided not to attend
        var missed: Int = 0          // Planned but the date passed unattended

        var total: Int {
            discovered + planned + attended + debriefed + skipped + missed
        }

    }

    struct StageChange: Codable {
        let jobAppId: UUID
        let company: String
        let position: String
        let fromStage: String
        let toStage: String
    }

    /// Generate a human-readable summary for the LLM prompt
    func textSummary() -> String {
        var parts: [String] = []

        // Overall Job Application Pipeline Status
        let stages = jobAppsByStage
        if stages.total > 0 {
            parts.append("### Job Application Pipeline Status")
            parts.append("Total applications: \(stages.total)")
            if stages.identified > 0 {
                parts.append("- Identified (no action yet): \(stages.identified)")
            }
            if stages.queued > 0 {
                parts.append("- Queued (on deck): \(stages.queued)")
            }
            if stages.inProgress > 0 {
                parts.append("- In Progress: \(stages.inProgress)")
            }
            if stages.applied > 0 {
                parts.append("- Submitted: \(stages.applied)")
            }
            if stages.interviewing > 0 {
                parts.append("- In interviews: \(stages.interviewing)")
            }
            if stages.offer > 0 {
                parts.append("- Have offers: \(stages.offer)")
            }
            if stages.rejected > 0 || stages.withdrawn > 0 {
                parts.append("- Closed (rejected/withdrawn): \(stages.rejected + stages.withdrawn)")
            }
            parts.append("")  // Blank line
        }

        // Recent Job Application Activity
        if newJobApps > 0 {
            let companies = jobAppCompanies.prefix(3).joined(separator: ", ")
            parts.append("### Recent Activity (Context Period)")
            parts.append("- Gathered \(newJobApps) new job lead(s) at: \(companies)")
        }

        if !stageChanges.isEmpty {
            if newJobApps == 0 {
                parts.append("### Recent Activity (Context Period)")
            }
            for change in stageChanges.prefix(5) {
                parts.append("- \(change.position) at \(change.company): \(change.fromStage) → \(change.toStage)")
            }
        }

        // Materials
        if resumesCreated > 0 || resumesModified > 0 || resumesWithLLMCustomization > 0 {
            parts.append("")
            parts.append("### Resume Activity")
            if resumesCreated > 0 {
                parts.append("- Created \(resumesCreated) new resume(s)")
            }
            if resumesWithLLMCustomization > 0 {
                parts.append("- AI-customized \(resumesWithLLMCustomization) resume(s)")
            }
            if resumesModified > 0 {
                parts.append("- Manually edited \(resumesModified) resume(s)")
            }
        }

        if coverLettersCreated > 0 || coverLettersModified > 0 {
            parts.append("")
            parts.append("### Cover Letter Activity")
            if coverLettersCreated > 0 {
                parts.append("- Generated \(coverLettersCreated) new cover letter(s)")
            }
            if coverLettersModified > 0 {
                parts.append("- Edited \(coverLettersModified) cover letter(s)")
            }
        }

        // Cover letter content details
        if !coverLetterDetails.isEmpty {
            parts.append("")
            parts.append("### Recent Cover Letters")
            for detail in coverLetterDetails {
                let modelInfo = detail.generationModel.map { " (via \($0))" } ?? ""
                let selectedMarker = detail.isSelected ? " [SELECTED]" : ""
                parts.append("#### \(detail.company) - \(detail.position)\(selectedMarker)")
                parts.append("Letter: \(detail.letterName)\(modelInfo)")
                if let content = detail.content, !content.isEmpty {
                    // Include full content for selected letters (truncate if very long)
                    let truncated = content.count > 2000 ? String(content.prefix(2000)) + "..." : content
                    parts.append("Content:\n\(truncated)")
                }
            }
        }

        // Overall Networking Event Pipeline Status
        let events = eventsByStatus
        if events.total > 0 {
            parts.append("")
            parts.append("### Networking Event Pipeline Status")
            parts.append("Total events tracked: \(events.total)")
            if events.discovered > 0 {
                parts.append("- Discovered (not yet evaluated): \(events.discovered)")
            }
            if events.planned > 0 {
                parts.append("- Planned to attend (on calendar): \(events.planned)")
            }
            if events.attended > 0 {
                parts.append("- Attended (needs debrief): \(events.attended)")
            }
            if events.debriefed > 0 {
                parts.append("- Fully debriefed: \(events.debriefed)")
            }
            if events.skipped > 0 || events.missed > 0 {
                parts.append("- Skipped/missed: \(events.skipped + events.missed)")
            }
        }

        // Recent Networking Activity
        if eventsAdded > 0 || eventsAttended > 0 || eventsDebriefed > 0 ||
           contactsAdded > 0 || interactionsLogged > 0 {
            parts.append("")
            parts.append("### Recent Networking Activity")
        }

        if eventsAdded > 0 {
            parts.append("- Discovered \(eventsAdded) new networking event(s)")
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

        // Event Details (upcoming planned and recently attended)
        let upcomingEvents = eventDetails.filter { $0.isFuture }
        let attendedEvents = eventDetails.filter { !$0.isFuture }

        if !upcomingEvents.isEmpty {
            parts.append("")
            parts.append("### Upcoming Events (Planned/Recommended)")
            for event in upcomingEvents.prefix(5) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                let dateStr = dateFormatter.string(from: event.date)
                let timeStr = event.time.map { " at \($0)" } ?? ""
                let locationStr = event.isVirtual ? "(Virtual)" : event.location

                parts.append("#### \(event.name)")
                parts.append("- Date: \(dateStr)\(timeStr)")
                parts.append("- Location: \(locationStr)")
                parts.append("- Type: \(event.eventType)")
                parts.append("- Status: \(event.status)")
                if let organizer = event.organizer {
                    parts.append("- Organizer: \(organizer)")
                }
                if let goal = event.goal, !goal.isEmpty {
                    parts.append("- Goal: \(goal)")
                }
                parts.append("")
            }
        }

        if !attendedEvents.isEmpty {
            parts.append("")
            parts.append("### Recently Attended Events")
            for event in attendedEvents.prefix(3) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                let dateStr = dateFormatter.string(from: event.date)

                parts.append("#### \(event.name) (\(dateStr))")
                parts.append("- Type: \(event.eventType)")
                if let contactCount = event.contactCount, contactCount > 0 {
                    parts.append("- Contacts made: \(contactCount)")
                }
                if let notes = event.eventNotes, !notes.isEmpty {
                    let truncated = notes.count > 300 ? String(notes.prefix(300)) + "..." : notes
                    parts.append("- Notes: \(truncated)")
                }
                parts.append("")
            }
        }

        if parts.isEmpty {
            return "No activity recorded in the context period."
        }

        return parts.joined(separator: "\n")
    }
}

// MARK: - Coaching Question

struct CoachingQuestion: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let questionText: String
    let options: [QuestionOption]
    /// Free-form question category named by the coach (e.g. "motivation",
    /// "interview_prep", "search_strategy"). Persisted per session so later
    /// sessions avoid repeating recently-asked categories.
    let category: String

    init(questionText: String, options: [QuestionOption], category: String) {
        self.questionText = questionText
        self.options = options
        self.category = category
    }

    /// Human-readable form of the category for UI badges.
    var categoryDisplayName: String {
        category
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    /// A next-step action prompt (options carry action identifiers) rather than
    /// a data-gathering question.
    var isActionPrompt: Bool {
        options.contains { $0.actionId != nil }
    }
}

struct QuestionOption: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let value: Int
    let label: String
    let emoji: String?
    /// For next-step action prompts: the `CoachingFollowUpAction` rawValue this
    /// option maps to. Nil for regular data-gathering questions.
    let actionId: String?

    init(value: Int, label: String, emoji: String? = nil, actionId: String? = nil) {
        self.value = value
        self.label = label
        self.emoji = emoji
        self.actionId = actionId
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

// MARK: - Follow-Up Actions

/// Actions the coach can offer after providing recommendations
enum CoachingFollowUpAction: String, Codable, CaseIterable {
    case generateTasks = "generate_tasks"
    case done = "done"

    var displayName: String {
        switch self {
        case .generateTasks: return "View my task list"
        case .done: return "I'm good for now"
        }
    }
}

// MARK: - Coaching State

enum CoachingState: Equatable {
    case idle
    case generatingReport
    case askingQuestion(question: CoachingQuestion)
    case waitingForAnswer
    case showingRecommendations(recommendations: String)
    case askingFollowUp(question: CoachingQuestion)
    case executingFollowUp(action: CoachingFollowUpAction)
    case complete(sessionId: UUID)
    case error(String)

    var isActive: Bool {
        switch self {
        case .idle, .complete, .error:
            return false
        default:
            return true
        }
    }
}
