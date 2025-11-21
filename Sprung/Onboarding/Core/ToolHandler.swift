
import Foundation
import Observation
import SwiftyJSON

/// Identifiers for onboarding tools that surface through the capabilities manifest.
enum OnboardingToolIdentifier: String, CaseIterable {
    case getUserOption = "get_user_option"
    case getUserUpload = "get_user_upload"
    case getMacOSContactCard = "get_macos_contact_card"
    case getApplicantProfile = "get_applicant_profile"
    case extractDocument = "extract_document"
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
                handleToolUIEvent(event)
            }
        }

        // Small delay to ensure stream is connected
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        Logger.info("📡 ToolHandler subscribed to toolpane events", category: .ai)
    }

    private func handleToolUIEvent(_ event: OnboardingEvent) {
        switch event {
        case .choicePromptRequested(let prompt):
            presentChoicePrompt(prompt)

        case .choicePromptCleared:
            clearChoicePrompt()

        case .uploadRequestPresented(let request):
            presentUploadRequest(request)

        case .validationPromptRequested(let prompt):
            presentValidationPrompt(prompt)

        case .validationPromptCleared:
            clearValidationPrompt()

        case .applicantProfileIntakeRequested:
            presentApplicantProfileIntake()

        case .applicantProfileIntakeCleared:
            clearApplicantProfileIntake()

        case .sectionToggleRequested(let request):
            presentSectionToggle(request)

        case .sectionToggleCleared:
            clearSectionToggle()

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

    var pendingApplicantProfileSummary: JSON? {
        profileHandler.pendingApplicantProfileSummary
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
    func presentChoicePrompt(_ prompt: OnboardingChoicePrompt) {
        promptHandler.presentChoicePrompt(prompt)
    }

    func clearChoicePrompt() {
        promptHandler.clearChoicePrompt()
    }

    func resolveChoice(selectionIds: [String]) -> JSON? {
        promptHandler.resolveChoice(selectionIds: selectionIds)
    }

    func cancelChoicePrompt(reason: String) -> JSON? {
        promptHandler.cancelChoicePrompt(reason: reason)
    }

    // MARK: - Validation Prompts
    func presentValidationPrompt(_ prompt: OnboardingValidationPrompt) {
        promptHandler.presentValidationPrompt(prompt)
    }

    func clearValidationPrompt() {
        promptHandler.clearValidationPrompt()
    }

    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) -> JSON? {
        promptHandler.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )
    }

    func cancelValidation(reason: String) -> JSON? {
        promptHandler.cancelValidation(reason: reason)
    }

    // MARK: - Applicant Profile Validation
    func presentApplicantProfileRequest(_ request: OnboardingApplicantProfileRequest) {
        profileHandler.presentProfileRequest(request)
    }

    func clearApplicantProfileRequest() {
        profileHandler.clearProfileRequest()
    }

    func resolveApplicantProfile(with draft: ApplicantProfileDraft) -> JSON? {
        profileHandler.resolveProfile(with: draft)
    }

    func rejectApplicantProfile(reason: String) -> JSON? {
        profileHandler.rejectProfile(reason: reason)
    }

    // MARK: - Applicant Profile Intake
    func presentApplicantProfileIntake() {
        profileHandler.presentProfileIntake()
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

    func beginApplicantProfileUpload() -> OnboardingUploadRequest {
        profileHandler.beginUpload()
    }

    func beginApplicantProfileContactsFetch() {
        profileHandler.beginContactsFetch()
    }

    func submitApplicantProfileURL(_ urlString: String) -> URL? {
        profileHandler.submitURL(urlString)
    }

    func completeApplicantProfileDraft(_ draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) {
        profileHandler.completeDraft(draft, source: source)
    }

    func cancelApplicantProfileIntake(reason: String) -> JSON? {
        profileHandler.cancelIntake(reason: reason)
    }

    func clearApplicantProfileIntake() {
        profileHandler.clearIntake()
    }

    // MARK: - Upload Handling
    func presentUploadRequest(_ request: OnboardingUploadRequest) {
        uploadHandler.presentUploadRequest(request)
    }

    func completeUpload(id: UUID, fileURLs: [URL]) async -> JSON? {
        await uploadHandler.completeUpload(id: id, fileURLs: fileURLs)
    }

    func completeUpload(id: UUID, link: URL) async -> JSON? {
        await uploadHandler.completeUpload(id: id, link: link)
    }

    func skipUpload(id: UUID) async -> JSON? {
        await uploadHandler.skipUpload(id: id)
    }

    func cancelUpload(id: UUID, reason: String?) async -> JSON? {
        await uploadHandler.cancelUpload(id: id, reason: reason)
    }

    func cancelPendingUpload(reason: String?) async -> JSON? {
        await uploadHandler.cancelPendingUpload(reason: reason)
    }

    // MARK: - Section Toggle Handling
    func presentSectionToggle(_ request: OnboardingSectionToggleRequest) {
        sectionHandler.presentToggleRequest(request)
    }

    func clearSectionToggle() {
        sectionHandler.reset()
    }

    func resolveSectionToggle(enabled: [String]) -> JSON? {
        sectionHandler.resolveToggle(enabled: enabled)
    }

    func rejectSectionToggle(reason: String) -> JSON? {
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

