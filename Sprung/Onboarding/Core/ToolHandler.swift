
import Foundation
import Observation
import SwiftyJSON

/// Identifiers for onboarding tools that surface through the capabilities manifest.
enum OnboardingToolIdentifier: String, CaseIterable {
    case getUserOption = "get_user_option"
    case getUserUpload = "get_user_upload"
    case getMacOSContactCard = "get_macos_contact_card"
    case getApplicantProfile = "get_applicant_profile"
    case submitForValidation = "submit_for_validation"
}

/// Canonical status values surfaced to the LLM runtime.
enum OnboardingToolStatus: String {
    case ready
    case waitingForUser = "waiting_for_user"
    case processing
    case locked
}

/// Consolidated snapshot of tool statuses for a single moment in time.
struct OnboardingToolStatusSnapshot: Equatable {
    let statuses: [OnboardingToolIdentifier: OnboardingToolStatus]

    init(statuses: [OnboardingToolIdentifier: OnboardingToolStatus]) {
        self.statuses = statuses
    }

    func status(for identifier: OnboardingToolIdentifier) -> OnboardingToolStatus {
        statuses[identifier] ?? .ready
    }

    var rawValueMap: [String: String] {
        statuses.reduce(into: [:]) { result, entry in
            result[entry.key.rawValue] = entry.value.rawValue
        }
    }

    static func == (lhs: OnboardingToolStatusSnapshot, rhs: OnboardingToolStatusSnapshot) -> Bool {
        lhs.statuses == rhs.statuses
    }
}

/// Central dispatch for tool-driven interactions. Delegates to specialized handlers while providing
/// a single surface for the coordinator and service to query state and construct continuation payloads.
@MainActor
@Observable
final class ToolHandler {
    // MARK: - Handlers

    let promptHandler: PromptInteractionHandler
    let uploadHandler: UploadInteractionHandler
    let profileHandler: ProfileInteractionHandler
    let sectionHandler: SectionToggleHandler
    private var statusResolvers: [OnboardingToolIdentifier: () -> OnboardingToolStatus] = [:]

    // Event subscription
    private weak var eventBus: EventCoordinator?

    // MARK: - Init

    init(
        promptHandler: PromptInteractionHandler,
        uploadHandler: UploadInteractionHandler,
        profileHandler: ProfileInteractionHandler,
        sectionHandler: SectionToggleHandler,
        eventBus: EventCoordinator? = nil
    ) {
        self.promptHandler = promptHandler
        self.uploadHandler = uploadHandler
        self.profileHandler = profileHandler
        self.sectionHandler = sectionHandler
        self.eventBus = eventBus
        configureStatusResolvers()
    }

    // MARK: - Event Subscriptions

    /// Start listening to tool UI events
    func startEventSubscriptions() async {
        guard let eventBus = eventBus else { return }

        Task {
            for await event in await eventBus.stream(topic: .toolpane) {
                await handleToolUIEvent(event)
            }
        }

        // Small delay to ensure stream is connected
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        Logger.info("📡 ToolHandler subscribed to toolpane events", category: .ai)
    }

    private func handleToolUIEvent(_ event: OnboardingEvent) {
        switch event {
        case .choicePromptRequested(let prompt, let continuationId):
            presentChoicePrompt(prompt, continuationId: continuationId)

        case .choicePromptCleared(let continuationId):
            clearChoicePrompt(continuationId: continuationId)

        case .uploadRequestPresented(let request, let continuationId):
            presentUploadRequest(request, continuationId: continuationId)

        case .validationPromptRequested(let prompt, let continuationId):
            presentValidationPrompt(prompt, continuationId: continuationId)

        case .validationPromptCleared(let continuationId):
            clearValidationPrompt(continuationId: continuationId)

        case .applicantProfileIntakeRequested(let continuationId):
            presentApplicantProfileIntake(continuationId: continuationId)

        case .applicantProfileIntakeCleared:
            clearApplicantProfileIntake()

        case .sectionToggleRequested(let request, let continuationId):
            presentSectionToggle(request, continuationId: continuationId)

        case .sectionToggleCleared(let continuationId):
            clearSectionToggle(continuationId: continuationId)

        default:
            break
        }
    }

    // MARK: - Status Snapshot

    /// Returns the current status of each tool managed by the router. Used for
    /// capability manifests and analytics.
    var statusSnapshot: OnboardingToolStatusSnapshot {
        let statuses = statusResolvers.mapValues { $0() }
        return OnboardingToolStatusSnapshot(statuses: statuses)
    }

    // MARK: - Observable State Facades

    var pendingChoicePrompt: OnboardingChoicePrompt? {
        promptHandler.pendingChoicePrompt
    }

    var pendingValidationPrompt: OnboardingValidationPrompt? {
        promptHandler.pendingValidationPrompt
    }

    var pendingApplicantProfileRequest: OnboardingApplicantProfileRequest? {
        profileHandler.pendingApplicantProfileRequest
    }

    var pendingApplicantProfileIntake: OnboardingApplicantProfileIntakeState? {
        profileHandler.pendingApplicantProfileIntake
    }

    var pendingUploadRequests: [OnboardingUploadRequest] {
        uploadHandler.pendingUploadRequests
    }

    var uploadedItems: [OnboardingUploadedItem] {
        uploadHandler.uploadedItems
    }

    var pendingSectionToggleRequest: OnboardingSectionToggleRequest? {
        sectionHandler.pendingSectionToggleRequest
    }

    // MARK: - Choice Prompts

    func presentChoicePrompt(_ prompt: OnboardingChoicePrompt, continuationId: UUID) {
        promptHandler.presentChoicePrompt(prompt, continuationId: continuationId)
    }

    func clearChoicePrompt(continuationId: UUID) {
        promptHandler.clearChoicePrompt(continuationId: continuationId)
    }

    func resolveChoice(selectionIds: [String]) -> (UUID, JSON)? {
        promptHandler.resolveChoice(selectionIds: selectionIds)
    }

    func cancelChoicePrompt(reason: String) -> (UUID, JSON)? {
        promptHandler.cancelChoicePrompt(reason: reason)
    }

    // MARK: - Validation Prompts

    func presentValidationPrompt(_ prompt: OnboardingValidationPrompt, continuationId: UUID) {
        promptHandler.presentValidationPrompt(prompt, continuationId: continuationId)
    }

    func clearValidationPrompt(continuationId: UUID) {
        promptHandler.clearValidationPrompt(continuationId: continuationId)
    }

    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) -> (UUID, JSON)? {
        promptHandler.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )
    }

    func cancelValidation(reason: String) -> (UUID, JSON)? {
        promptHandler.cancelValidation(reason: reason)
    }

    // MARK: - Applicant Profile Validation

    func presentApplicantProfileRequest(_ request: OnboardingApplicantProfileRequest, continuationId: UUID) {
        profileHandler.presentProfileRequest(request, continuationId: continuationId)
    }

    func clearApplicantProfileRequest(continuationId: UUID) {
        profileHandler.clearProfileRequest(continuationId: continuationId)
    }

    func resolveApplicantProfile(with draft: ApplicantProfileDraft) -> (UUID, JSON)? {
        profileHandler.resolveProfile(with: draft)
    }

    func rejectApplicantProfile(reason: String) -> (UUID, JSON)? {
        profileHandler.rejectProfile(reason: reason)
    }

    // MARK: - Applicant Profile Intake

    func presentApplicantProfileIntake(continuationId: UUID) {
        profileHandler.presentProfileIntake(continuationId: continuationId)
    }

    func resetApplicantProfileIntakeToOptions() {
        profileHandler.resetIntakeToOptions()
    }

    func beginApplicantProfileManualEntry() {
        profileHandler.beginManualEntry()
    }

    func beginApplicantProfileURL() {
        profileHandler.beginURLEntry()
    }

    func beginApplicantProfileUpload() -> (request: OnboardingUploadRequest, continuationId: UUID)? {
        profileHandler.beginUpload()
    }

    func beginApplicantProfileContactsFetch() {
        profileHandler.beginContactsFetch()
    }

    func submitApplicantProfileURL(_ urlString: String) -> (UUID, JSON)? {
        profileHandler.submitURL(urlString)
    }

    func completeApplicantProfileDraft(_ draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) -> (UUID, JSON)? {
        profileHandler.completeDraft(draft, source: source)
    }

    func cancelApplicantProfileIntake(reason: String) -> (UUID, JSON)? {
        profileHandler.cancelIntake(reason: reason)
    }

    func clearApplicantProfileIntake() {
        profileHandler.clearIntake()
    }

    // MARK: - Upload Handling

    func presentUploadRequest(_ request: OnboardingUploadRequest, continuationId: UUID) {
        uploadHandler.presentUploadRequest(request, continuationId: continuationId)
    }

    func completeUpload(id: UUID, fileURLs: [URL]) async -> (UUID, JSON)? {
        await uploadHandler.completeUpload(id: id, fileURLs: fileURLs)
    }

    func completeUpload(id: UUID, link: URL) async -> (UUID, JSON)? {
        await uploadHandler.completeUpload(id: id, link: link)
    }

    func skipUpload(id: UUID) async -> (UUID, JSON)? {
        await uploadHandler.skipUpload(id: id)
    }

    func cancelUpload(id: UUID, reason: String?) async -> (UUID, JSON)? {
        await uploadHandler.cancelUpload(id: id, reason: reason)
    }

    func cancelPendingUpload(reason: String?) async -> (UUID, JSON)? {
        await uploadHandler.cancelPendingUpload(reason: reason)
    }

    // MARK: - Section Toggle Handling

    func presentSectionToggle(_ request: OnboardingSectionToggleRequest, continuationId: UUID) {
        sectionHandler.presentToggleRequest(request, continuationId: continuationId)
    }

    func clearSectionToggle(continuationId: UUID) {
        // Clear the section toggle if the continuation ID matches
        if sectionHandler.pendingSectionToggleRequest?.id == continuationId {
            sectionHandler.reset()
        }
    }

    func resolveSectionToggle(enabled: [String]) -> (UUID, JSON)? {
        sectionHandler.resolveToggle(enabled: enabled)
    }

    func rejectSectionToggle(reason: String) -> (UUID, JSON)? {
        sectionHandler.rejectToggle(reason: reason)
    }

    // MARK: - Lifecycle

    func reset() {
        promptHandler.reset()
        uploadHandler.reset()
        profileHandler.reset()
        sectionHandler.reset()
    }

    private func configureStatusResolvers() {
        statusResolvers = [
            .getUserOption: { [unowned self] in
                promptHandler.pendingChoicePrompt == nil ? .ready : .waitingForUser
            },
            .getUserUpload: { [unowned self] in
                uploadHandler.pendingUploadRequests.isEmpty ? .ready : .waitingForUser
            },
            .getMacOSContactCard: { [unowned self] in
                guard let intake = profileHandler.pendingApplicantProfileIntake else { return .ready }
                if case .loading = intake.mode { return .processing }
                return .ready
            },
            .getApplicantProfile: { [unowned self] in
    if let intake = profileHandler.pendingApplicantProfileIntake {
        if case .loading = intake.mode { return .processing }
        return .waitingForUser
    }
    if profileHandler.pendingApplicantProfileRequest != nil {
        return .waitingForUser
    }
    return .ready
    },
            .submitForValidation: { [unowned self] in
                promptHandler.pendingValidationPrompt == nil ? .ready : .waitingForUser
            }
        ]
    }
}

