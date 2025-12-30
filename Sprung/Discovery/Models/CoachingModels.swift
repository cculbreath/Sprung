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
        let llmRecommendation: String?
        let llmRationale: String?
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
        var evaluating: Int = 0      // Deciding whether to attend
        var recommended: Int = 0     // AI recommended attending
        var planned: Int = 0         // User committed to attend (on calendar)
        var attended: Int = 0        // User attended
        var debriefed: Int = 0       // Captured contacts/notes after attending
        var skipped: Int = 0         // User decided not to attend
        var cancelled: Int = 0       // Event was cancelled
        var missed: Int = 0          // User missed it

        var total: Int {
            discovered + evaluating + recommended + planned + attended + debriefed + skipped + cancelled + missed
        }

        /// Events user has committed to (on calendar)
        var confirmedTotal: Int {
            planned + attended + debriefed
        }

        /// Events still being considered
        var pendingTotal: Int {
            discovered + evaluating + recommended
        }
    }

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
            if events.evaluating > 0 || events.recommended > 0 {
                parts.append("- Considering: \(events.evaluating + events.recommended)")
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
            if events.skipped > 0 || events.cancelled > 0 || events.missed > 0 {
                parts.append("- Skipped/cancelled/missed: \(events.skipped + events.cancelled + events.missed)")
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
                if let recommendation = event.llmRecommendation {
                    parts.append("- AI Recommendation: \(recommendation)")
                }
                if let rationale = event.llmRationale, !rationale.isEmpty {
                    let truncated = rationale.count > 200 ? String(rationale.prefix(200)) + "..." : rationale
                    parts.append("- Rationale: \(truncated)")
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

        // Time
        if totalActiveMinutesToday > 0 {
            parts.append("")
            let hours = totalActiveMinutesToday / 60
            let minutes = totalActiveMinutesToday % 60
            if hours > 0 {
                parts.append("Time spent in app today: \(hours)h \(minutes)m")
            } else {
                parts.append("Time spent in app today: \(minutes)m")
            }
        }

        // Pace
        if daysSinceLastOpen > 1 {
            parts.append("Days since last app usage: \(daysSinceLastOpen)")
        }

        if parts.isEmpty {
            return "No activity recorded in the context period."
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
    case followUp = "follow_up"

    var displayName: String {
        switch self {
        case .motivation: return "Motivation Check"
        case .challenge: return "Challenges"
        case .focus: return "Today's Focus"
        case .feedback: return "Feedback"
        case .followUp: return "Next Steps"
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

// MARK: - Follow-Up Actions

/// Actions the coach can offer after providing recommendations
enum CoachingFollowUpAction: String, Codable, CaseIterable {
    case chooseFocusJobs = "choose_focus_jobs"
    case generateTasks = "generate_tasks"
    case staleAppCheck = "stale_app_check"
    case networkingSuggestions = "networking_suggestions"
    case quickWins = "quick_wins"
    case done = "done"

    var displayName: String {
        switch self {
        case .chooseFocusJobs: return "Pick my focus jobs for today"
        case .generateTasks: return "View my task list"
        case .staleAppCheck: return "Check for stale applications"
        case .networkingSuggestions: return "Suggest networking actions"
        case .quickWins: return "Give me some quick wins"
        case .done: return "I'm good for now"
        }
    }
}

// MARK: - Coaching State

enum CoachingState: Equatable {
    case idle
    case generatingReport
    case askingQuestion(question: CoachingQuestion, index: Int, total: Int)
    case waitingForAnswer
    case generatingRecommendations
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

// MARK: - Task Regeneration Response

/// Response from task regeneration LLM call
struct TaskRegenerationResponse: Codable {
    let tasks: [TaskJSON]
}

/// JSON representation of a task from LLM response
struct TaskJSON: Codable {
    let taskType: String
    let title: String
    let description: String
    let priority: Int
    let estimatedMinutes: Int
    let relatedId: String?

    enum CodingKeys: String, CodingKey {
        case taskType = "task_type"
        case title
        case description
        case priority
        case estimatedMinutes = "estimated_minutes"
        case relatedId = "related_id"
    }
}
