//
//  DiscoveryModels.swift
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

// MARK: - Search Preferences (UserDefaults-backed)

struct SearchPreferences: Codable {
    var targetSectors: [String] = []
    var primaryLocation: String = ""
    var remoteAcceptable: Bool = false
    var willingToRelocate: Bool = false
    var relocationTargets: [String] = []
    var preferredArrangement: WorkArrangement = .hybrid
    var companySizePreference: CompanySizePreference = .any
    var weeklyApplicationTarget: Int = 5
    var weeklyNetworkingTarget: Int = 2
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    static let userDefaultsKey = "searchPreferences"

    static func load() -> SearchPreferences {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let prefs = try? JSONDecoder().decode(SearchPreferences.self, from: data) else {
            return SearchPreferences()
        }
        return prefs
    }

    func save() {
        var copy = self
        copy.updatedAt = Date()
        if let data = try? JSONEncoder().encode(copy) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}

// MARK: - Search Ops Settings (UserDefaults-backed)

struct DiscoverySettings: Codable {
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    static let userDefaultsKey = "searchOpsSettings"

    static func load() -> DiscoverySettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(DiscoverySettings.self, from: data) else {
            return DiscoverySettings()
        }
        return settings
    }

    func save() {
        var copy = self
        copy.updatedAt = Date()
        if let data = try? JSONEncoder().encode(copy) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
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

// MARK: - Weekly Goal

@Model
class WeeklyGoal: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()

    var weekStartDate: Date = Date()

    // Application targets
    var applicationTarget: Int = 5

    // Networking targets
    var eventsAttendedTarget: Int = 1
    var eventsAttendedActual: Int = 0
    var newContactsTarget: Int = 3
    var newContactsActual: Int = 0

    // Reflection
    var llmReflection: String?
    var userNotes: String?

    var createdAt: Date = Date()
    var reflectionGeneratedAt: Date?

    init() {}

    init(weekStartDate: Date) {
        self.weekStartDate = weekStartDate
    }

    var networkingProgress: Double {
        let total = eventsAttendedTarget + newContactsTarget
        guard total > 0 else { return 0 }
        let actual = eventsAttendedActual + newContactsActual
        return min(1.0, Double(actual) / Double(total))
    }
}
