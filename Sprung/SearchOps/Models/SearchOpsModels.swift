//
//  SearchOpsModels.swift
//  Sprung
//
//  Models for Job Search Operations module.
//  See sprung_job_search_ops_spec.md Section 3 for full definitions.
//

import Foundation
import SwiftData

// MARK: - Work Arrangement

enum WorkArrangement: String, Codable, CaseIterable {
    case remote = "Remote"
    case hybrid = "Hybrid"
    case onsite = "On-site"
    case flexible = "Flexible"
}

// MARK: - Company Size Preference

enum CompanySizePreference: String, Codable, CaseIterable {
    case startup = "Startup (< 50)"
    case small = "Small (50-200)"
    case mid = "Mid-size (200-1000)"
    case enterprise = "Enterprise (1000+)"
    case any = "Any size"
}

// MARK: - Search Preferences

@Model
class SearchPreferences {
    @Attribute(.unique) var id: UUID = UUID()

    var targetSectors: [String] = []
    var primaryLocation: String = ""
    var remoteAcceptable: Bool = false
    var willingToRelocate: Bool = false
    var relocationTargets: [String] = []
    var preferredArrangement: WorkArrangement = WorkArrangement.hybrid
    var companySizePreference: CompanySizePreference = CompanySizePreference.any
    var weeklyApplicationTarget: Int = 5
    var weeklyNetworkingTarget: Int = 2

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}
}

// MARK: - Search Ops Settings

@Model
class SearchOpsSettings {
    @Attribute(.unique) var id: UUID = UUID()

    // LLM Configuration
    var llmModelId: String = "anthropic/claude-3.5-sonnet"

    // Calendar Configuration
    var useJobSearchCalendar: Bool = false
    var jobSearchCalendarIdentifier: String?

    // Notification Configuration
    var notificationsEnabled: Bool = false
    var dailyBriefingEnabled: Bool = true
    var dailyBriefingHour: Int = 8
    var dailyBriefingMinute: Int = 0
    var followUpRemindersEnabled: Bool = true
    var weeklyReviewEnabled: Bool = true
    var weeklyReviewDay: Int = 6  // Friday (1 = Sunday, 6 = Friday)
    var weeklyReviewHour: Int = 16
    var weeklyReviewMinute: Int = 0

    // Fatigue Tracking
    var lastNotificationClickedAt: Date?
    var notificationFatiguePauseOffered: Bool = false
    var notificationsPausedAt: Date?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}
}

// MARK: - Source Category

enum SourceCategory: String, Codable, CaseIterable {
    case local = "Local Boards"
    case industry = "Industry-Specific"
    case companyDirect = "Company Careers"
    case aggregator = "Aggregators"
    case startup = "Startup Boards"
    case staffing = "Staffing Agencies"
    case networking = "Networking Events"

    var defaultCadenceDays: Int {
        switch self {
        case .local, .aggregator: return 3
        case .industry, .startup: return 4
        case .companyDirect: return 5
        case .staffing, .networking: return 7
        }
    }
}

// MARK: - Job Source

@Model
class JobSource: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()

    var name: String = ""
    var url: String = ""
    var category: SourceCategory = SourceCategory.aggregator
    var isActive: Bool = true

    var recommendedCadenceDays: Int = 3
    var lastVisitedAt: Date?

    var totalVisits: Int = 0
    var openingsCaptured: Int = 0

    var notes: String = ""
    var isLLMGenerated: Bool = true

    // URL Validation
    var urlLastVerified: Date?
    var urlValid: Bool = true
    var consecutiveFailures: Int = 0
    var firstFailureAt: Date?

    var createdAt: Date = Date()

    init() {}

    init(name: String, url: String, category: SourceCategory) {
        self.name = name
        self.url = url
        self.category = category
        self.recommendedCadenceDays = category.defaultCadenceDays
    }

    var daysSinceVisit: Int? {
        guard let last = lastVisitedAt else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }

    var isDue: Bool {
        guard let days = daysSinceVisit else { return true }
        return days >= recommendedCadenceDays
    }

    var effectiveness: Double? {
        guard totalVisits > 0 else { return nil }
        return Double(openingsCaptured) / Double(totalVisits)
    }

    var needsRevalidation: Bool {
        guard let lastCheck = urlLastVerified else { return true }
        let daysSinceCheck = Calendar.current.dateComponents([.day], from: lastCheck, to: Date()).day ?? 0
        return daysSinceCheck >= 7
    }

    var shouldSuggestRemoval: Bool {
        guard consecutiveFailures >= 2 else { return false }
        guard let firstFailure = firstFailureAt else { return false }
        let days = Calendar.current.dateComponents([.day], from: firstFailure, to: Date()).day ?? 0
        return days >= 14
    }
}

// MARK: - Daily Task

enum DailyTaskType: String, Codable, CaseIterable {
    case gatherLeads = "Gather"
    case customizeMaterials = "Customize"
    case submitApplication = "Apply"
    case followUp = "Follow Up"
    case networking = "Networking"
    case eventPrep = "Event Prep"
    case eventDebrief = "Debrief"

    var icon: String {
        switch self {
        case .gatherLeads: return "magnifyingglass"
        case .customizeMaterials: return "pencil"
        case .submitApplication: return "paperplane"
        case .followUp: return "arrow.uturn.right"
        case .networking: return "person.2"
        case .eventPrep: return "person.bubble"
        case .eventDebrief: return "doc.text"
        }
    }
}

enum TaskPriority: String, Codable, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

@Model
class DailyTask: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()

    var taskType: DailyTaskType = DailyTaskType.gatherLeads
    var title: String = ""
    var taskDescription: String?
    var isCompleted: Bool = false
    var completedAt: Date?

    // Relationships
    var relatedJobSourceId: UUID?
    var relatedJobAppId: UUID?
    var relatedContactId: UUID?
    var relatedEventId: UUID?

    // Metadata
    var isLLMGenerated: Bool = true
    var priority: Int = 0  // Higher = more important
    var estimatedMinutes: Int?

    var createdAt: Date = Date()
    var dueDate: Date?

    init() {}

    init(type: DailyTaskType, title: String, description: String? = nil) {
        self.taskType = type
        self.title = title
        self.taskDescription = description
    }
}

// MARK: - Time Entry

enum ActivityType: String, Codable, CaseIterable {
    case gathering = "Gathering Leads"
    case customizing = "Customizing Materials"
    case applying = "Submitting Applications"
    case researching = "Company Research"
    case interviewPrep = "Interview Prep"
    case networking = "Networking"
    case llmChat = "AI Assistance"
    case appActive = "Sprung Active"
    case other = "Other"

    var color: String {
        switch self {
        case .customizing: return "blue"
        case .gathering: return "green"
        case .applying: return "purple"
        case .networking: return "orange"
        case .interviewPrep: return "red"
        default: return "gray"
        }
    }
}

enum TrackingSource: String, Codable {
    case appForeground = "App Foreground"
    case viewActivity = "View Activity"
    case sourceVisit = "Source Visit"
    case calendarEvent = "Calendar Event"
    case manual = "Manual Entry"
}

@Model
class TimeEntry: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()

    var activityType: ActivityType = ActivityType.other
    var startTime: Date = Date()
    var endTime: Date?
    var durationSeconds: Int = 0

    var isAutomatic: Bool = true
    var trackingSource: TrackingSource = TrackingSource.appForeground
    var notes: String?

    var relatedJobAppId: UUID?
    var relatedTaskId: UUID?

    init() {}

    init(activityType: ActivityType, startTime: Date) {
        self.activityType = activityType
        self.startTime = startTime
    }

    var duration: TimeInterval {
        if let end = endTime {
            return end.timeIntervalSince(startTime)
        }
        return TimeInterval(durationSeconds)
    }

    var durationMinutes: Int {
        durationSeconds / 60
    }

    var formattedDuration: String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Weekly Goal

@Model
class WeeklyGoal: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()

    var weekStartDate: Date = Date()

    // Application targets
    var applicationTarget: Int = 5
    var applicationActual: Int = 0

    // Networking targets
    var eventsAttendedTarget: Int = 1
    var eventsAttendedActual: Int = 0
    var newContactsTarget: Int = 3
    var newContactsActual: Int = 0
    var followUpsSentTarget: Int = 5
    var followUpsSentActual: Int = 0

    // Time tracking
    var targetHours: Double = 20.0
    var actualMinutes: Int = 0

    // Reflection
    var llmReflection: String?
    var userNotes: String?

    var createdAt: Date = Date()
    var reflectionGeneratedAt: Date?

    init() {}

    init(weekStartDate: Date) {
        self.weekStartDate = weekStartDate
    }

    var weekEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
    }

    var applicationProgress: Double {
        guard applicationTarget > 0 else { return 0 }
        return min(1.0, Double(applicationActual) / Double(applicationTarget))
    }

    var networkingProgress: Double {
        let total = eventsAttendedTarget + newContactsTarget + followUpsSentTarget
        guard total > 0 else { return 0 }
        let actual = eventsAttendedActual + newContactsActual + followUpsSentActual
        return min(1.0, Double(actual) / Double(total))
    }

    var timeProgress: Double {
        guard targetHours > 0 else { return 0 }
        let actualHours = Double(actualMinutes) / 60.0
        return min(1.0, actualHours / targetHours)
    }

    // Convenience aliases for cleaner access
    var applicationsSubmitted: Int { applicationActual }
    var applicationsTarget: Int { applicationTarget }
    var eventsAttended: Int { eventsAttendedActual }
    var eventsTarget: Int { eventsAttendedTarget }
    var newContacts: Int { newContactsActual }
    var followUpsSent: Int { followUpsSentActual }
    var followUpsTarget: Int { followUpsSentTarget }

    /// Reflection notes (stored in userNotes)
    var reflectionNotes: String? {
        get { userNotes }
        set { userNotes = newValue }
    }
}
