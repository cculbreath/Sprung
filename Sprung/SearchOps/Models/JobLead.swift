//
//  JobLead.swift
//  Sprung
//
//  Model for tracking job leads through the application pipeline.
//  Represents a potential job opportunity from discovery to outcome.
//

import Foundation
import SwiftData

/// Priority level for a job lead
enum JobLeadPriority: String, Codable, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

/// Stage in the application pipeline
enum ApplicationStage: String, Codable, CaseIterable {
    case identified = "Identified"
    case researching = "Researching"
    case applying = "Applying"
    case applied = "Applied"
    case interviewing = "Interviewing"
    case offer = "Offer"
    case accepted = "Accepted"
    case rejected = "Rejected"
    case withdrawn = "Withdrawn"

    /// Next stage in the progression
    var next: ApplicationStage? {
        switch self {
        case .identified: return .researching
        case .researching: return .applying
        case .applying: return .applied
        case .applied: return .interviewing
        case .interviewing: return .offer
        case .offer: return .accepted
        case .accepted, .rejected, .withdrawn: return nil
        }
    }
}

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
