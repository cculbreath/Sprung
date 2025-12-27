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

    /// Generate a 24-hour activity snapshot
    func generateSnapshot(since: Date = Date().addingTimeInterval(-86400)) -> ActivitySnapshot {
        var snapshot = ActivitySnapshot()

        // Job Applications
        let recentJobApps = getJobAppsCreatedSince(since)
        snapshot.newJobApps = recentJobApps.count
        snapshot.jobAppCompanies = recentJobApps.map { $0.companyName }
        snapshot.jobAppPositions = recentJobApps.map { $0.jobPosition }
        snapshot.stageChanges = getStageChangesSince(since)

        // Resumes and Cover Letters
        let resumeStats = getResumeStatsSince(since)
        snapshot.resumesCreated = resumeStats.created
        snapshot.resumesModified = resumeStats.modified

        let coverLetterStats = getCoverLetterStatsSince(since)
        snapshot.coverLettersCreated = coverLetterStats.created
        snapshot.coverLettersModified = coverLetterStats.modified
        snapshot.coverLetterDetails = getCoverLetterDetailsSince(since)

        // Networking Events
        let eventStats = getEventStatsSince(since)
        snapshot.eventsAdded = eventStats.added
        snapshot.eventsAttended = eventStats.attended
        snapshot.eventsDebriefed = eventStats.debriefed

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

    private func getResumeStatsSince(_ since: Date) -> (created: Int, modified: Int) {
        // Query resumes directly from context
        let descriptor = FetchDescriptor<Resume>()
        guard let resumes = try? modelContext.fetch(descriptor) else {
            return (0, 0)
        }

        var created = 0
        // Resume model doesn't track modification dates, so always 0 for now
        let modified = 0

        for resume in resumes {
            if resume.dateCreated >= since {
                created += 1
            }
        }

        return (created, modified)
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
