//
//  ActivityReportService.swift
//  Sprung
//
//  Generates activity snapshots for the Job Search Coach feature.
//  Queries the last 24 hours of activity across job apps, resumes,
//  cover letters, networking events, and contacts.
//

import Foundation
import SwiftData

@Observable
@MainActor
final class ActivityReportService {
    private let modelContext: ModelContext
    private let jobAppStore: JobAppStore
    private let eventStore: NetworkingEventStore
    private let contactStore: NetworkingContactStore
    private let interactionStore: NetworkingInteractionStore
    private let timeEntryStore: TimeEntryStore

    init(
        modelContext: ModelContext,
        jobAppStore: JobAppStore,
        eventStore: NetworkingEventStore,
        contactStore: NetworkingContactStore,
        interactionStore: NetworkingInteractionStore,
        timeEntryStore: TimeEntryStore
    ) {
        self.modelContext = modelContext
        self.jobAppStore = jobAppStore
        self.eventStore = eventStore
        self.contactStore = contactStore
        self.interactionStore = interactionStore
        self.timeEntryStore = timeEntryStore
    }

    // MARK: - Snapshot Generation

    /// Generate an activity snapshot for coaching context
    func generateSnapshot(since: Date = Date().addingTimeInterval(-86400)) -> ActivitySnapshot {
        var snapshot = ActivitySnapshot()

        // Job Applications - recent activity
        let recentJobApps = getJobAppsCreatedSince(since)
        snapshot.newJobApps = recentJobApps.count
        snapshot.jobAppCompanies = recentJobApps.map { $0.companyName }
        snapshot.jobAppPositions = recentJobApps.map { $0.jobPosition }
        snapshot.stageChanges = getStageChangesSince(since)

        // Job Applications - overall pipeline breakdown
        snapshot.jobAppsByStage = getJobAppStageBreakdown()

        // Resumes and Cover Letters
        let resumeStats = getResumeStatsSince(since)
        snapshot.resumesCreated = resumeStats.created
        snapshot.resumesModified = resumeStats.modified
        snapshot.resumesWithLLMCustomization = resumeStats.llmCustomized

        let coverLetterStats = getCoverLetterStatsSince(since)
        snapshot.coverLettersCreated = coverLetterStats.created
        snapshot.coverLettersModified = coverLetterStats.modified
        snapshot.coverLetterDetails = getCoverLetterDetailsSince(since)

        // Networking Events - recent activity
        let eventStats = getEventStatsSince(since)
        snapshot.eventsAdded = eventStats.added
        snapshot.eventsAttended = eventStats.attended
        snapshot.eventsDebriefed = eventStats.debriefed

        // Networking Events - overall pipeline breakdown
        snapshot.eventsByStatus = getEventStatusBreakdown()

        // Networking Events - detailed info for upcoming and recently attended
        snapshot.eventDetails = getEventDetails(since: since)

        // Contacts and Interactions
        snapshot.contactsAdded = getContactsAddedSince(since)
        snapshot.interactionsLogged = getInteractionsLoggedSince(since)

        // Time and Pace
        snapshot.totalActiveMinutesToday = timeEntryStore.totalMinutesForDate(Date())
        snapshot.daysSinceLastOpen = calculateDaysSinceLastOpen()

        return snapshot
    }

    // MARK: - Job App Queries

    private func getJobAppsCreatedSince(_ since: Date) -> [JobApp] {
        jobAppStore.jobApps.filter { $0.createdAt >= since }
    }

    /// Get breakdown of all job apps by pipeline stage
    private func getJobAppStageBreakdown() -> ActivitySnapshot.JobAppStageBreakdown {
        var breakdown = ActivitySnapshot.JobAppStageBreakdown()

        for jobApp in jobAppStore.jobApps {
            switch jobApp.stage {
            case .identified:
                breakdown.identified += 1
            case .researching:
                breakdown.researching += 1
            case .applying:
                breakdown.applying += 1
            case .applied:
                breakdown.applied += 1
            case .interviewing:
                breakdown.interviewing += 1
            case .offer:
                breakdown.offer += 1
            case .accepted:
                breakdown.accepted += 1
            case .rejected:
                breakdown.rejected += 1
            case .withdrawn:
                breakdown.withdrawn += 1
            }
        }

        return breakdown
    }

    private func getStageChangesSince(_ since: Date) -> [ActivitySnapshot.StageChange] {
        // We track stage changes by looking at jobs with recent date changes
        // For now, we look at jobs that have stage-related dates in the timeframe
        var changes: [ActivitySnapshot.StageChange] = []

        for jobApp in jobAppStore.jobApps {
            // Check for applied date changes
            if let appliedDate = jobApp.appliedDate, appliedDate >= since {
                changes.append(ActivitySnapshot.StageChange(
                    jobAppId: jobApp.id,
                    company: jobApp.companyName,
                    position: jobApp.jobPosition,
                    fromStage: ApplicationStage.applying.rawValue,
                    toStage: ApplicationStage.applied.rawValue
                ))
            }

            // Check for interview date changes
            if let interviewDate = jobApp.firstInterviewDate, interviewDate >= since {
                changes.append(ActivitySnapshot.StageChange(
                    jobAppId: jobApp.id,
                    company: jobApp.companyName,
                    position: jobApp.jobPosition,
                    fromStage: ApplicationStage.applied.rawValue,
                    toStage: ApplicationStage.interviewing.rawValue
                ))
            }

            // Check for offer date changes
            if let offerDate = jobApp.offerDate, offerDate >= since {
                changes.append(ActivitySnapshot.StageChange(
                    jobAppId: jobApp.id,
                    company: jobApp.companyName,
                    position: jobApp.jobPosition,
                    fromStage: ApplicationStage.interviewing.rawValue,
                    toStage: ApplicationStage.offer.rawValue
                ))
            }
        }

        return changes
    }

    // MARK: - Resume Queries

    private func getResumeStatsSince(_ since: Date) -> (created: Int, modified: Int, llmCustomized: Int) {
        // Query resumes directly from context
        let descriptor = FetchDescriptor<Resume>()
        guard let resumes = try? modelContext.fetch(descriptor) else {
            return (0, 0, 0)
        }

        var created = 0
        var llmCustomized = 0
        // Resume model doesn't track modification dates, so always 0 for now
        let modified = 0

        for resume in resumes {
            if resume.dateCreated >= since {
                created += 1
            }
            // Check if resume has any phase assignments (indicates LLM customization was configured)
            // or if any TreeNodes have been through AI revision (have bundled/enumerated attributes set)
            if !resume.phaseAssignments.isEmpty || hasLLMCustomizedNodes(resume) {
                llmCustomized += 1
            }
        }

        return (created, modified, llmCustomized)
    }

    /// Check if a resume has any TreeNodes that have been through LLM customization
    private func hasLLMCustomizedNodes(_ resume: Resume) -> Bool {
        guard let rootNode = resume.rootNode else { return false }
        return checkNodeForLLMCustomization(rootNode)
    }

    private func checkNodeForLLMCustomization(_ node: TreeNode) -> Bool {
        // A node has been through LLM customization if it has attribute review modes configured
        if node.hasAttributeReviewModes {
            return true
        }

        // Check children recursively
        for child in node.children ?? [] {
            if checkNodeForLLMCustomization(child) {
                return true
            }
        }

        return false
    }

    // MARK: - Cover Letter Queries

    private func getCoverLetterStatsSince(_ since: Date) -> (created: Int, modified: Int) {
        // Query cover letters directly from context
        let descriptor = FetchDescriptor<CoverLetter>()
        guard let coverLetters = try? modelContext.fetch(descriptor) else {
            return (0, 0)
        }

        var created = 0
        var modified = 0

        for coverLetter in coverLetters {
            // Skip empty/uncomposed letters
            guard coverLetter.generated && !coverLetter.content.isEmpty else { continue }

            if coverLetter.createdDate >= since {
                created += 1
            } else if coverLetter.moddedDate >= since {
                modified += 1
            }
        }

        return (created, modified)
    }

    /// Get detailed cover letter info for coaching context
    /// Excludes empty/uncomposed letters, includes full content for selected letters
    private func getCoverLetterDetailsSince(_ since: Date) -> [ActivitySnapshot.CoverLetterDetail] {
        let descriptor = FetchDescriptor<CoverLetter>()
        guard let coverLetters = try? modelContext.fetch(descriptor) else {
            return []
        }

        var details: [ActivitySnapshot.CoverLetterDetail] = []

        for coverLetter in coverLetters {
            // Skip empty/uncomposed letters
            guard coverLetter.generated && !coverLetter.content.isEmpty else { continue }

            // Only include letters created or modified within the time window
            let isRecent = coverLetter.createdDate >= since || coverLetter.moddedDate >= since
            guard isRecent else { continue }

            guard let jobApp = coverLetter.jobApp else { continue }

            let isSelected = jobApp.selectedCoverId == coverLetter.id

            details.append(ActivitySnapshot.CoverLetterDetail(
                jobAppId: jobApp.id,
                company: jobApp.companyName,
                position: jobApp.jobPosition,
                letterName: coverLetter.sequencedName,
                isSelected: isSelected,
                // Include full content only for selected letters
                content: isSelected ? coverLetter.content : nil,
                generationModel: coverLetter.generationModel
            ))
        }

        return details
    }

    // MARK: - Event Queries

    private func getEventStatsSince(_ since: Date) -> (added: Int, attended: Int, debriefed: Int) {
        let events = eventStore.allEvents

        let added = events.filter { $0.discoveredAt >= since }.count
        let attended = events.filter {
            $0.attended && ($0.attendedAt ?? Date.distantPast) >= since
        }.count
        let debriefed = events.filter {
            $0.status == .debriefed && ($0.attendedAt ?? Date.distantPast) >= since
        }.count

        return (added, attended, debriefed)
    }

    /// Get breakdown of all events by pipeline status
    private func getEventStatusBreakdown() -> ActivitySnapshot.EventStatusBreakdown {
        var breakdown = ActivitySnapshot.EventStatusBreakdown()

        for event in eventStore.allEvents {
            switch event.status {
            case .discovered:
                breakdown.discovered += 1
            case .evaluating:
                breakdown.evaluating += 1
            case .recommended:
                breakdown.recommended += 1
            case .planned:
                breakdown.planned += 1
            case .attended:
                breakdown.attended += 1
            case .debriefed:
                breakdown.debriefed += 1
            case .skipped:
                breakdown.skipped += 1
            case .cancelled:
                breakdown.cancelled += 1
            case .missed:
                breakdown.missed += 1
            }
        }

        return breakdown
    }

    /// Get detailed info for upcoming events (planned/recommended) and events attended in context period
    private func getEventDetails(since: Date) -> [ActivitySnapshot.EventDetail] {
        var details: [ActivitySnapshot.EventDetail] = []
        let now = Date()

        for event in eventStore.allEvents {
            // Include: future events that are planned/recommended, OR attended within context period
            let isFuture = event.date > now
            let isPlannedOrRecommended = event.status == .planned || event.status == .recommended || event.status == .evaluating
            let wasRecentlyAttended = event.attended && (event.attendedAt ?? Date.distantPast) >= since

            guard (isFuture && isPlannedOrRecommended) || wasRecentlyAttended else { continue }

            details.append(ActivitySnapshot.EventDetail(
                eventId: event.id,
                name: event.name,
                date: event.date,
                time: event.time,
                location: event.location,
                isVirtual: event.isVirtual,
                eventType: event.eventType.rawValue,
                status: event.status.rawValue,
                organizer: event.organizer,
                estimatedAttendance: event.estimatedAttendance.rawValue,
                llmRecommendation: event.llmRecommendation?.rawValue,
                llmRationale: event.llmRationale,
                goal: event.goal,
                attended: event.attended,
                contactCount: event.attended ? event.contactCount : nil,
                eventNotes: event.attended ? event.eventNotes : nil
            ))
        }

        // Sort: future events first (by date ascending), then past events (by date descending)
        return details.sorted { a, b in
            if a.isFuture && !b.isFuture { return true }
            if !a.isFuture && b.isFuture { return false }
            if a.isFuture { return a.date < b.date }
            return a.date > b.date
        }
    }

    // MARK: - Contact Queries

    private func getContactsAddedSince(_ since: Date) -> Int {
        contactStore.allContacts.filter { $0.createdAt >= since }.count
    }

    private func getInteractionsLoggedSince(_ since: Date) -> Int {
        interactionStore.allInteractions.filter { $0.date >= since }.count
    }

    // MARK: - Time & Pace Queries

    private func calculateDaysSinceLastOpen() -> Int {
        // Find the most recent time entry before today
        let today = Calendar.current.startOfDay(for: Date())
        let entries = timeEntryStore.allEntries.filter {
            $0.startTime < today
        }.sorted { $0.startTime > $1.startTime }

        guard let lastEntry = entries.first else {
            return 0
        }

        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: lastEntry.startTime, to: today).day ?? 0
    }
}
