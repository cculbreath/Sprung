//
//  JobLead.swift
//  Sprung
//
//  ⚠️ DEPRECATED: This model has been superseded by JobApp.
//
//  This file is kept for backward compatibility with existing SwiftData records.
//  All new code should use JobApp instead, which unifies job tracking across
//  the Resume/CoverLetter creation workflow and the SearchOps Kanban pipeline.
//
//  Migration Path:
//  - JobApp now includes all SearchOps properties (stage, priority, dates, etc.)
//  - JobLeadStore has been updated to use JobApp
//  - PipelineView has been updated to use JobApp
//  - Existing JobLead records will remain in the database for backward compatibility
//  - New records should be created as JobApp instances
//  - Use `JobApp(from: jobLead)` to convert existing JobLead instances
//
//  DO NOT ADD NEW FEATURES TO THIS MODEL.
//  DO NOT CREATE NEW INSTANCES OF JobLead.
//

import Foundation
import SwiftData

// Note: JobLeadPriority and ApplicationStage are now defined in JobApp.swift
// This file references those enums to maintain compatibility with existing records.

@available(*, deprecated, message: "Use JobApp instead. JobApp now includes all SearchOps pipeline properties.")
@Model
final class JobLead {
    var id: UUID
    var company: String
    var role: String?
    var source: String?
    var url: String?
    var applicationUrl: String?
    var priority: JobLeadPriority
    var stage: ApplicationStage
    var notes: String?

    // Dates
    var createdAt: Date
    var identifiedDate: Date?
    var appliedDate: Date?
    var firstInterviewDate: Date?
    var lastInterviewDate: Date?
    var offerDate: Date?
    var closedDate: Date?

    // Interview tracking
    var interviewCount: Int
    var lastInterviewNotes: String?

    // Outcome details
    var rejectionReason: String?
    var withdrawalReason: String?
    var offerDetails: String?

    // Resume tracking
    var resumeId: UUID?
    var coverLetterId: UUID?

    // Scoring
    var fitScore: Double?
    var llmAssessment: String?

    init(
        company: String,
        role: String? = nil,
        source: String? = nil,
        url: String? = nil,
        priority: JobLeadPriority = .medium
    ) {
        self.id = UUID()
        self.company = company
        self.role = role
        self.source = source
        self.url = url
        self.priority = priority
        self.stage = .identified
        self.createdAt = Date()
        self.identifiedDate = Date()
        self.interviewCount = 0
    }

    // MARK: - Computed Properties

    var daysSinceCreated: Int? {
        Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day
    }

    var daysSinceApplied: Int? {
        guard let appliedDate = appliedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: appliedDate, to: Date()).day
    }

    var isActive: Bool {
        switch stage {
        case .accepted, .rejected, .withdrawn: return false
        default: return true
        }
    }

    var displayTitle: String {
        if let role = role {
            return "\(role) at \(company)"
        }
        return company
    }
}
