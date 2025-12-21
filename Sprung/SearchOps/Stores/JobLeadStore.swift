//
//  JobLeadStore.swift
//  Sprung
//
//  Store for managing job leads in the application pipeline.
//  Provides CRUD operations and pipeline stage management.
//

import Foundation
import SwiftData

@Observable
@MainActor
final class JobLeadStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Queries

    var allLeads: [JobLead] {
        let descriptor = FetchDescriptor<JobLead>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    var activeLeads: [JobLead] {
        allLeads.filter { $0.isActive }
    }

    func leads(forStage stage: ApplicationStage) -> [JobLead] {
        allLeads.filter { $0.stage == stage }
    }

    func lead(byId id: UUID) -> JobLead? {
        allLeads.first { $0.id == id }
    }

    // MARK: - Pipeline Stats

    var pipelineStats: [ApplicationStage: Int] {
        Dictionary(grouping: allLeads) { $0.stage }
            .mapValues { $0.count }
    }

    var activeCount: Int {
        activeLeads.count
    }

    var thisWeeksApplications: Int {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()

        return allLeads.filter {
            guard let appliedDate = $0.appliedDate else { return false }
            return appliedDate >= weekStart
        }.count
    }

    // MARK: - CRUD

    func add(_ lead: JobLead) {
        context.insert(lead)
        try? context.save()
    }

    func addMultiple(_ leads: [JobLead]) {
        for lead in leads {
            context.insert(lead)
        }
        try? context.save()
    }

    func update(_ lead: JobLead) {
        try? context.save()
    }

    func delete(_ lead: JobLead) {
        context.delete(lead)
        try? context.save()
    }

    // MARK: - Stage Management

    func advanceStage(_ lead: JobLead) {
        guard let nextStage = lead.stage.next else { return }

        lead.stage = nextStage

        // Track dates
        switch nextStage {
        case .applied:
            lead.appliedDate = Date()
        case .interviewing:
            if lead.firstInterviewDate == nil {
                lead.firstInterviewDate = Date()
            }
            lead.lastInterviewDate = Date()
            lead.interviewCount += 1
        case .offer:
            lead.offerDate = Date()
        case .accepted, .rejected, .withdrawn:
            lead.closedDate = Date()
        default:
            break
        }

        try? context.save()
    }

    func setStage(_ lead: JobLead, to stage: ApplicationStage) {
        lead.stage = stage

        if stage == .accepted || stage == .rejected || stage == .withdrawn {
            lead.closedDate = Date()
        }

        try? context.save()
    }

    func reject(_ lead: JobLead, reason: String?) {
        lead.stage = .rejected
        lead.rejectionReason = reason
        lead.closedDate = Date()
        try? context.save()
    }

    func withdraw(_ lead: JobLead, reason: String?) {
        lead.stage = .withdrawn
        lead.withdrawalReason = reason
        lead.closedDate = Date()
        try? context.save()
    }

    func recordInterview(_ lead: JobLead, notes: String?) {
        lead.interviewCount += 1
        lead.lastInterviewDate = Date()
        if lead.firstInterviewDate == nil {
            lead.firstInterviewDate = Date()
        }
        if let notes = notes {
            lead.lastInterviewNotes = notes
        }
        try? context.save()
    }

    // MARK: - Priority Management

    func setPriority(_ lead: JobLead, to priority: JobLeadPriority) {
        lead.priority = priority
        try? context.save()
    }

    // MARK: - Filtering

    var highPriorityLeads: [JobLead] {
        activeLeads.filter { $0.priority == .high }
    }

    var needsAction: [JobLead] {
        activeLeads.filter { lead in
            // Leads that have been stale for too long
            switch lead.stage {
            case .identified:
                return (lead.daysSinceCreated ?? 0) > 3
            case .researching:
                return (lead.daysSinceCreated ?? 0) > 7
            case .applying:
                return (lead.daysSinceCreated ?? 0) > 2
            case .applied:
                return (lead.daysSinceApplied ?? 0) > 14
            case .interviewing:
                if let lastInterview = lead.lastInterviewDate {
                    let days = Calendar.current.dateComponents([.day], from: lastInterview, to: Date()).day ?? 0
                    return days > 7
                }
                return false
            default:
                return false
            }
        }
    }

    // MARK: - Source Tracking

    func leadsBySource() -> [String: Int] {
        Dictionary(grouping: allLeads) { $0.source ?? "Unknown" }
            .mapValues { $0.count }
    }

    func successfulLeadsBySource() -> [String: Int] {
        Dictionary(grouping: allLeads.filter { $0.stage == .accepted }) { $0.source ?? "Unknown" }
            .mapValues { $0.count }
    }
}
