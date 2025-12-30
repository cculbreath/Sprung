//
//  ProfileInteractionHandler.swift
//  Sprung
//
//  Handles applicant profile intake (manual/URL/upload/contacts) and validation.
//  Manages the profile intake state machine and produces JSON payloads for tool continuations.
//
import Foundation
import Observation
import SwiftyJSON
@MainActor
@Observable
final class ProfileInteractionHandler {
    // MARK: - Observable State
    private(set) var pendingApplicantProfileRequest: OnboardingApplicantProfileRequest?
    private(set) var pendingApplicantProfileIntake: OnboardingApplicantProfileIntakeState?
    private(set) var pendingApplicantProfileSummary: JSON?
    private(set) var lastSubmittedDraft: JSON?
    // MARK: - Private State
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    // MARK: - Dependencies
    private let contactsImportService: ContactsImportService
    private let eventBus: EventCoordinator
    // MARK: - Init
    init(
        contactsImportService: ContactsImportService,
        eventBus: EventCoordinator
    ) {
        self.contactsImportService = contactsImportService
        self.eventBus = eventBus
    }
    // MARK: - Validation Flow (Approve/Reject)
    /// Clears the current profile request.
    func clearProfileRequest() {
        pendingApplicantProfileRequest = nil
    }
    /// Resolves an applicant profile validation with user-approved or modified draft.
    func resolveProfile(with draft: ApplicantProfileDraft) -> JSON? {
        guard let request = pendingApplicantProfileRequest else {
            Logger.warning("⚠️ No pending profile request to resolve", category: .ai)
            return nil
        }
        let resolvedJSON = draft.toJSON()
        let status: String = resolvedJSON == request.proposedProfile ? "approved" : "modified"
        let enriched = attachingValidationMetadata(to: resolvedJSON, via: "validation_card")
        var payload = JSON()
        payload["status"].string = status
        payload["data"] = enriched
        clearProfileRequest()
        lastSubmittedDraft = enriched
        Logger.info("✅ Profile resolved (status: \(status))", category: .ai)
        // Show the profile summary card in the tool pane
        // @Observable will handle UI updates automatically
        showProfileSummary(profile: enriched)

        // Trigger automatic URL fetch for profile URLs
        Task {
            await triggerProfileURLFetch(draft: draft)
        }

        return payload
    }

    /// Extracts URLs from validated profile and instructs agent to visit them
    private func triggerProfileURLFetch(draft: ApplicantProfileDraft) async {
        var urlsToVisit: [String] = []

        // Check main website
        if !draft.website.isEmpty {
            urlsToVisit.append(draft.website)
        }

        // Check social profiles (LinkedIn, GitHub, etc.)
        for socialProfile in draft.socialProfiles {
            if !socialProfile.url.isEmpty {
                urlsToVisit.append(socialProfile.url)
            }
        }

        guard !urlsToVisit.isEmpty else { return }

        Logger.info("🌐 Profile contains \(urlsToVisit.count) URL(s) to visit", category: .ai)

        // Build developer message instructing agent to fetch these URLs
        let urlList = urlsToVisit.joined(separator: ", ")
        var payload = JSON()
        payload["text"].string = """
            The user's profile includes the following URLs: \(urlList).
            Use web_search to visit these sites and gather relevant information about the user's background.
            If you find valuable content (portfolio projects, LinkedIn achievements, GitHub contributions, etc.),
            use create_web_artifact to save it for later use in building their resume.
            """

        await eventBus.publish(.llmExecuteDeveloperMessage(payload: payload))
    }
    /// Rejects an applicant profile validation.
    func rejectProfile(reason: String) -> JSON? {
        guard pendingApplicantProfileRequest != nil else {
            Logger.warning("⚠️ No pending profile request to reject", category: .ai)
            return nil
        }
        var payload = JSON()
        payload["status"].string = "rejected"
        if !reason.isEmpty {
            payload["userNotes"].string = reason
        }
        clearProfileRequest()
        Logger.info("❌ Profile rejected", category: .ai)
        return payload
    }
    // MARK: - Intake Flow (Collect Profile)
    /// Presents the profile intake UI (shows mode picker: manual/URL/upload/contacts).
    func presentProfileIntake() {
        pendingApplicantProfileIntake = .options()
        Logger.info("📝 Profile intake presented", category: .ai)
    }
    /// Resets intake state to show mode picker again.
    func resetIntakeToOptions() {
        pendingApplicantProfileIntake = .options()
    }
    // MARK: - Intake Modes
    /// Begins manual entry mode.
    func beginManualEntry() {
        pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
            mode: .manual(source: .manual),
            draft: ApplicantProfileDraft(),
            urlString: "",
            errorMessage: nil
        )
        Logger.info("✏️ Manual entry mode activated", category: .ai)
    }
    /// Begins URL entry mode.
    func beginURLEntry() {
        pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
            mode: .urlEntry,
            draft: ApplicantProfileDraft(),
            urlString: "",
            errorMessage: nil
        )
        Logger.info("🔗 URL entry mode activated", category: .ai)
    }
    /// Begins upload mode (returns an upload request for the router to present).
    func beginUpload() -> OnboardingUploadRequest {
        pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
            mode: .loading("Processing uploaded document…"),
            draft: ApplicantProfileDraft(),
            urlString: "",
            errorMessage: nil
        )
        let metadata = OnboardingUploadMetadata(
            title: "Upload Contact Information",
            instructions: "Please upload a document that contains your basic contact information.",
            accepts: ["pdf", "docx", "txt", "md"],
            allowMultiple: false,
            targetPhaseObjectives: ["1A"],
            targetDeliverable: "ApplicantProfile",
            userValidated: false
        )
        Logger.info("📤 Upload mode activated", category: .ai)
        return OnboardingUploadRequest(kind: .resume, metadata: metadata)
    }
    /// Begins contacts fetch mode (imports from macOS Contacts).
    func beginContactsFetch() {
        pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
            mode: .loading("Fetching your contact card…"),
            draft: ApplicantProfileDraft(),
            urlString: "",
            errorMessage: nil
        )
        Task { @MainActor in
            do {
                let draft = try await contactsImportService.fetchMeCardAsDraft()
                pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
                    mode: .manual(source: .contacts),
                    draft: draft,
                    urlString: "",
                    errorMessage: nil
                )
                Logger.info("✅ Contacts imported successfully", category: .ai)
            } catch let error as ContactFetchError {
                pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
                    mode: .options,
                    draft: ApplicantProfileDraft(),
                    urlString: "",
                    errorMessage: error.message
                )
                Logger.warning("⚠️ Contacts import failed: \(error.message)", category: .ai)
            } catch {
                pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
                    mode: .options,
                    draft: ApplicantProfileDraft(),
                    urlString: "",
                    errorMessage: "Failed to access macOS contacts."
                )
                Logger.error("❌ Contacts import error: \(error)", category: .ai)
            }
        }
    }
    // MARK: - Intake Completion
    /// Submits a URL for profile intake.
    func submitURL(_ urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else {
            pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
                mode: .urlEntry,
                draft: ApplicantProfileDraft(),
                urlString: urlString,
                errorMessage: "Please enter a valid URL including the scheme (https://)."
            )
            Logger.warning("⚠️ Invalid URL: \(urlString)", category: .ai)
            return nil
        }
        Logger.info("🔗 URL submitted: \(url.absoluteString)", category: .ai)
        return url
    }
    /// Completes profile intake with a user-filled draft.
    /// Note: We no longer emit an artifact record here. The profile data is:
    /// 1. Persisted to ApplicantProfile via SwiftData (handled by caller)
    /// 2. Returned directly in the tool response via UIResponseCoordinator.submitProfileDraft()
    /// The contact card artifact was never used after the initial turn, and the summary-only
    /// artifact messages were confusing the LLM into making extra calls to retrieve data.
    func completeDraft(_ draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) {
        let dataJSON = attachingValidationMetadata(
            to: draft.toSafeJSON(),
            via: source == .contacts ? "contacts" : "manual"
        )
        if dataJSON != .null {
            lastSubmittedDraft = dataJSON
        }
        // Show the profile summary card
        showProfileSummary(profile: dataJSON)
        Logger.info("✅ Draft completed (source: \(source == .contacts ? "contacts" : "manual"))", category: .ai)
    }
    /// Clears the applicant profile intake state without completing it.
    /// Used when extraction begins to allow spinner to show.
    func clearIntake() {
        pendingApplicantProfileIntake = nil
    }
    // MARK: - Lifecycle
    /// Clears all pending profile state (for interview reset).
    func reset() {
        pendingApplicantProfileRequest = nil
        pendingApplicantProfileIntake = nil
        lastSubmittedDraft = nil
    }
    // MARK: - Metadata Helpers
    private func attachingValidationMetadata(to json: JSON, via channel: String) -> JSON {
        var enriched = json
        enriched["meta"]["validation_state"].string = "user_validated"
        enriched["meta"]["validated_via"].string = channel
        enriched["meta"]["validated_at"].string = isoFormatter.string(from: Date())
        return enriched
    }
    // MARK: - Profile Summary Management
    /// Shows the profile summary card in the tool pane.
    func showProfileSummary(profile: JSON) {
        pendingApplicantProfileSummary = profile
        Logger.info("📋 Profile summary shown", category: .ai)
    }
    /// Updates the profile summary with new data (e.g., when photo is added).
    func updateProfileSummary(profile: JSON) {
        pendingApplicantProfileSummary = profile
        Logger.info("📋 Profile summary updated", category: .ai)
    }
    /// Dismisses the profile summary card.
    func dismissProfileSummary() {
        pendingApplicantProfileSummary = nil
        Logger.info("📋 Profile summary dismissed", category: .ai)
    }
}
