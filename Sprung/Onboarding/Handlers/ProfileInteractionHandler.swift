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
    private(set) var lastSubmittedDraft: JSON?

    // MARK: - Private State

    private var applicantProfileContinuationId: UUID?
    private var applicantIntakeContinuationId: UUID?

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

    /// Presents a validation request for an applicant profile.
    func presentProfileRequest(_ request: OnboardingApplicantProfileRequest, continuationId: UUID) {
        pendingApplicantProfileRequest = request
        applicantProfileContinuationId = continuationId
        Logger.info("📋 Profile validation request presented", category: .ai)
    }

    /// Clears the current profile request if the continuation matches.
    func clearProfileRequest(continuationId: UUID) {
        guard applicantProfileContinuationId == continuationId else { return }
        clearProfileRequest()
    }

    /// Resolves an applicant profile validation with user-approved or modified draft.
    func resolveProfile(with draft: ApplicantProfileDraft) -> (continuationId: UUID, payload: JSON)? {
        guard let continuationId = applicantProfileContinuationId,
              let request = pendingApplicantProfileRequest else {
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
        return (continuationId, payload)
    }

    /// Rejects an applicant profile validation.
    func rejectProfile(reason: String) -> (continuationId: UUID, payload: JSON)? {
        guard let continuationId = applicantProfileContinuationId else {
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
        return (continuationId, payload)
    }

    // MARK: - Intake Flow (Collect Profile)

    /// Presents the profile intake UI (shows mode picker: manual/URL/upload/contacts).
    func presentProfileIntake(continuationId: UUID) {
        pendingApplicantProfileIntake = .options()
        applicantIntakeContinuationId = continuationId
        Logger.info("📝 Profile intake presented", category: .ai)
    }

    /// Resets intake state to show mode picker again.
    func resetIntakeToOptions() {
        guard applicantIntakeContinuationId != nil else { return }
        pendingApplicantProfileIntake = .options()
    }

    // MARK: - Intake Modes

    /// Begins manual entry mode.
    func beginManualEntry() {
        guard applicantIntakeContinuationId != nil else { return }
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
        guard applicantIntakeContinuationId != nil else { return }
        pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
            mode: .urlEntry,
            draft: ApplicantProfileDraft(),
            urlString: "",
            errorMessage: nil
        )
        Logger.info("🔗 URL entry mode activated", category: .ai)
    }

    /// Begins upload mode (returns an upload request for the router to present).
    func beginUpload() -> (request: OnboardingUploadRequest, continuationId: UUID)? {
        guard let continuationId = applicantIntakeContinuationId else { return nil }

        pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
            mode: .loading("Processing uploaded document…"),
            draft: ApplicantProfileDraft(),
            urlString: "",
            errorMessage: nil
        )

        let metadata = OnboardingUploadMetadata(
            title: "Upload Contact Information",
            instructions: "Please upload a document that contains your basic contact information.",
            accepts: ["pdf", "doc", "docx", "txt", "md"],
            allowMultiple: false,
            targetPhaseObjectives: ["1A"],
            targetDeliverable: "ApplicantProfile",
            userValidated: false
        )

        Logger.info("📤 Upload mode activated", category: .ai)
        return (
            OnboardingUploadRequest(kind: .resume, metadata: metadata),
            continuationId
        )
    }

    /// Begins contacts fetch mode (imports from macOS Contacts).
    func beginContactsFetch() {
        guard applicantIntakeContinuationId != nil else { return }

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
    func submitURL(_ urlString: String) -> (continuationId: UUID, payload: JSON)? {
        guard let continuationId = applicantIntakeContinuationId else { return nil }

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

        var payload = JSON()
        payload["mode"].string = "url"
        payload["status"].string = "provided"
        payload["url"].string = url.absoluteString

        Logger.info("🔗 URL submitted: \(url.absoluteString)", category: .ai)
        return completeIntake(continuationId: continuationId, payload: payload)
    }

    /// Completes profile intake with a user-filled draft.
    func completeDraft(_ draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) -> (continuationId: UUID, payload: JSON)? {
        guard let continuationId = applicantIntakeContinuationId else { return nil }

        let dataJSON = attachingValidationMetadata(
            to: draft.toSafeJSON(),
            via: source == .contacts ? "contacts" : "manual"
        )

        if dataJSON != .null {
            lastSubmittedDraft = dataJSON
        }

        // Emit artifact record for contacts and manual entry
        Task {
            await emitProfileArtifactRecord(profileJSON: dataJSON, source: source)
        }

        Logger.info("✅ Draft completed (source: \(source == .contacts ? "contacts" : "manual"))", category: .ai)

        // Return success payload
        var payload = JSON()
        payload["mode"].string = source == .contacts ? "contacts" : "manual"
        payload["status"].string = "completed"

        return completeIntake(continuationId: continuationId, payload: payload)
    }

    /// Cancels profile intake.
    func cancelIntake(reason: String) -> (continuationId: UUID, payload: JSON)? {
        guard let continuationId = applicantIntakeContinuationId else { return nil }

        Logger.info("❌ Profile intake cancelled: \(reason)", category: .ai)
        var payload = JSON()
        payload["cancelled"].boolValue = true

        return completeIntake(continuationId: continuationId, payload: payload)
    }

    /// Clears the applicant profile intake state without completing it.
    /// Used when extraction begins to allow spinner to show.
    func clearIntake() {
        pendingApplicantProfileIntake = nil
    }

    // MARK: - Private Helpers

    private func completeIntake(continuationId: UUID, payload: JSON) -> (continuationId: UUID, payload: JSON) {
        pendingApplicantProfileIntake = nil
        applicantIntakeContinuationId = nil
        return (continuationId, payload)
    }

    private func clearProfileRequest() {
        pendingApplicantProfileRequest = nil
        applicantProfileContinuationId = nil
    }

    // MARK: - Lifecycle

    /// Clears all pending profile state (for interview reset).
    func reset() {
        pendingApplicantProfileRequest = nil
        pendingApplicantProfileIntake = nil
        applicantProfileContinuationId = nil
        applicantIntakeContinuationId = nil
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

    // MARK: - Artifact Record Creation

    private func emitProfileArtifactRecord(
        profileJSON: JSON,
        source: OnboardingApplicantProfileIntakeState.Source
    ) async {
        let artifactId = UUID().uuidString

        // For contacts, use vCard text; for manual, use JSON
        let extractedText: String
        if source == .contacts {
            // Try to get vCard text representation
            if let vCardData = try? await contactsImportService.fetchMeCardAsVCard(),
               let vCardString = String(data: vCardData, encoding: .utf8) {
                extractedText = vCardString
            } else {
                // Fallback to JSON if vCard fetch fails
                extractedText = profileJSON.rawString() ?? "{}"
            }
        } else {
            extractedText = profileJSON.rawString() ?? "{}"
        }

        var artifactRecord = JSON()
        artifactRecord["id"].string = artifactId
        artifactRecord["filename"].string = source == .contacts ? "contact-card.vcf" : "manual-entry.json"
        artifactRecord["document_type"].string = "applicant_profile"
        artifactRecord["extracted_text"].string = extractedText
        artifactRecord["content_type"].string = source == .contacts ? "text/vcard" : "application/json"
        artifactRecord["created_at"].string = isoFormatter.string(from: Date())

        // Add metadata for LLM
        var metadata = JSON()
        metadata["target_phase_objectives"] = JSON(["applicant_profile.contact_intake"])  // Contact Information sub-objective
        metadata["target_deliverable"].string = "ApplicantProfile"
        metadata["user_validated"].bool = true
        artifactRecord["metadata"] = metadata

        // Emit artifact record produced event
        await eventBus.publish(.artifactRecordProduced(record: artifactRecord))

        Logger.info("📦 Profile artifact record emitted: \(artifactId) (source: \(source == .contacts ? "contacts" : "manual"))", category: .ai)
    }
}
