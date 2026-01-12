import Foundation
import Observation
import SwiftyJSON
/// Observable state container for the Onboarding UI.
/// This class holds all state required by SwiftUI views, updated via events from the Coordinator.
@MainActor
@Observable
final class OnboardingUIState {
    // MARK: - Processing State
    var isProcessing: Bool = false
    var currentStatusMessage: String?
    var isActive: Bool = false

    // MARK: - Stop State
    /// When true, ALL incoming processing is silenced (tool calls discarded, messages ignored)
    /// Set by Stop button, cleared when user takes purposeful action
    var isStopped: Bool = false

    // MARK: - Streaming State (for chatbox glow)
    /// True only when LLM text is actively streaming (incoming or outgoing user-visible text).
    /// Does NOT activate for background tool execution or coordinator messages.
    var isStreaming: Bool = false

    // MARK: - Batch Upload State
    /// True when a batch of documents is being processed (extraction in progress)
    /// Used to prevent validation prompts from interrupting batch uploads
    var hasBatchUploadInProgress: Bool = false

    // MARK: - Extraction State (Non-Blocking)
    /// True when document extraction is in progress (PDF processing, git analysis)
    /// Unlike isProcessing, this does NOT block chat input - allows dossier questions during "dead time"
    var isExtractionInProgress: Bool = false
    /// Status message to display during extraction (e.g., "Extracting resume.pdf...")
    var extractionStatusMessage: String?
    // MARK: - Chat Queue State
    /// Number of messages waiting in the queue (for Queue button display)
    var queuedMessageCount: Int = 0
    /// IDs of messages that are queued but not yet sent to the LLM
    var queuedMessageIds: Set<UUID> = []

    // MARK: - Chat State
    var messages: [OnboardingMessage] = []
    var modelAvailabilityMessage: String?
    /// Stores the original text from a failed message send, to be restored to the input box
    var failedMessageText: String?
    /// Error message to display when a message send fails
    var failedMessageError: String?
    // MARK: - Timeline State
    var skeletonTimeline: JSON?
    /// UI-only counter for SwiftUI change detection when timeline updates occur
    var timelineUIChangeToken: Int = 0
    /// True when LLM has activated the timeline editor (via display_timeline_entries_for_review)
    var isTimelineEditorActive: Bool = false
    /// Flag set when a timeline CRUD tool is used (create, update, delete, reorder) to trigger tab auto-switch
    var timelineToolWasUsed: Bool = false
    /// ID of the currently expanded/editing timeline entry (nil = all collapsed)
    var editingTimelineEntryId: String?

    // MARK: - Section Cards State (Awards, Languages, References)
    /// Section cards for non-chronological resume sections
    var sectionCards: [AdditionalSectionEntry] = []
    /// UI-only counter for SwiftUI change detection when section cards update
    var sectionCardsUIChangeToken: Int = 0
    /// True when LLM has activated the section cards editor
    var isSectionCardsEditorActive: Bool = false
    /// Flag set when a section card CRUD tool is used to trigger tab auto-switch
    var sectionCardToolWasUsed: Bool = false

    // MARK: - Publication Cards State
    /// Publication cards for the publications section
    var publicationCards: [PublicationCard] = []
    /// UI-only counter for SwiftUI change detection when publication cards update
    var publicationCardsUIChangeToken: Int = 0

    // MARK: - Enabled Sections
    /// Set of section types that are enabled for this resume
    var enabledSectionTypes: Set<String> = []
    // MARK: - Wizard State
    var wizardStep: StateCoordinator.WizardStep = .voice
    var completedWizardSteps: Set<StateCoordinator.WizardStep> = []
    var phase: InterviewPhase = .phase1VoiceContext
    // MARK: - Tool Pane State (Mirrored from ToolHandler)
    // Note: ToolHandler (via ToolRouter) manages its own state, but we might want to mirror it here
    // or keep accessing it via the router. For now, we'll keep the pattern of accessing via router
    // to avoid duplication, but we can add computed properties if needed.
    // MARK: - Sync Caches (Mirrored from StateCoordinator)
    var pendingExtraction: OnboardingPendingExtraction?
    var pendingStreamingStatus: String?
    /// Stores last shown profile summary to display until skeleton timeline loads
    var lastApplicantProfileSummary: JSON?

    // MARK: - Document Collection Phase
    /// True when document collection UI should be displayed (Phase 2)
    /// Set by open_document_collection tool, cleared when user clicks "Assess Completeness"
    var isDocumentCollectionActive: Bool = false

    // MARK: - Artifact State
    /// UI-only counter for SwiftUI change detection when artifacts are added/removed.
    /// Views observing sessionWritingSamples should also access this token to trigger updates.
    var artifactUIChangeToken: Int = 0

    // MARK: - Multi-Agent Workflow State
    /// True when card assignments have been proposed and await user approval
    /// Set by .mergeComplete event, cleared when generation begins
    var cardAssignmentsReadyForApproval: Bool = false
    /// Number of card assignments proposed
    var proposedAssignmentCount: Int = 0
    /// Number of documentation gaps identified
    var identifiedGapCount: Int = 0
    /// True when card inventories are being merged (after Done with Uploads)
    var isMergingCards: Bool = false
    /// True when actively generating knowledge cards
    var isGeneratingCards: Bool = false

    // MARK: - Objective Status (for Phase 3 subphase tracking)
    var objectiveStatuses: [String: String] = [:]

    // MARK: - Guidance Flags
    /// True when custom.jobTitles was enabled during section configuration
    var shouldGenerateTitleSets: Bool = false
    /// True when user has completed title set curation (selected and saved their choices)
    var titleSetsCurated: Bool = false

    // MARK: - Interview Completion State
    /// Set to true when interview transitions to .complete phase
    /// View observes this to close the window automatically
    var interviewJustCompleted: Bool = false

    // MARK: - Preferences
    var preferences: OnboardingPreferences
    init(preferences: OnboardingPreferences) {
        self.preferences = preferences
    }
    // MARK: - Update Methods
    func updateProcessing(isProcessing: Bool, statusMessage: String?) {
        self.isProcessing = isProcessing
        if let statusMessage = statusMessage {
            self.currentStatusMessage = statusMessage
        } else if !isProcessing {
            self.currentStatusMessage = nil
        }
    }

    /// Update streaming state (for chatbox glow - only during actual text streaming)
    func updateStreaming(_ streaming: Bool) {
        self.isStreaming = streaming
    }

    func updateTimeline(_ timeline: JSON?) {
        let oldToken = self.timelineUIChangeToken
        self.skeletonTimeline = timeline
        self.timelineUIChangeToken += 1
        let cardCount = timeline?["experiences"].array?.count ?? 0
        Logger.info("📊 OnboardingUIState.updateTimeline: token \(oldToken) → \(self.timelineUIChangeToken), cards=\(cardCount)", category: .ai)
    }
    func updateWizardProgress(step: StateCoordinator.WizardStep, completed: Set<StateCoordinator.WizardStep>) {
        self.wizardStep = step
        self.completedWizardSteps = completed
    }

    /// Update extraction state (non-blocking - chat remains enabled)
    func updateExtraction(inProgress: Bool, statusMessage: String? = nil) {
        self.isExtractionInProgress = inProgress
        self.extractionStatusMessage = statusMessage
        if !inProgress {
            self.extractionStatusMessage = nil
        }
    }

    /// Handle a failed message send by removing it from transcript and storing for input restoration
    func handleMessageFailure(messageId: String, originalText: String, error: String) {
        // Remove the failed message from the transcript
        if let uuid = UUID(uuidString: messageId) {
            messages.removeAll { $0.id == uuid }
        }
        // Store the original text and error for UI to restore
        failedMessageText = originalText
        failedMessageError = error
        Logger.info("💬 Message failure handled: removed from transcript, text ready for restoration", category: .ai)
    }

    /// Clear the failed message state after the UI has restored the text
    func clearFailedMessage() {
        failedMessageText = nil
        failedMessageError = nil
    }

    // MARK: - Section Cards Methods

    /// Update section cards and trigger UI refresh
    func updateSectionCards(_ cards: [AdditionalSectionEntry]) {
        self.sectionCards = cards
        self.sectionCardsUIChangeToken += 1
    }

    /// Update publication cards and trigger UI refresh
    func updatePublicationCards(_ cards: [PublicationCard]) {
        self.publicationCards = cards
        self.publicationCardsUIChangeToken += 1
    }

    /// Get the section type for a section card by ID
    func getSectionCardType(id: String) -> String? {
        sectionCards.first(where: { $0.id == id })?.sectionType.rawValue
    }

    /// Check if a publication card exists with the given ID
    func publicationCardExists(id: String) -> Bool {
        publicationCards.contains(where: { $0.id == id })
    }

    /// Add a new section card
    func addSectionCard(_ card: AdditionalSectionEntry) {
        sectionCards.append(card)
        sectionCardsUIChangeToken += 1
    }

    /// Update an existing section card
    func updateSectionCard(id: String, with updatedCard: AdditionalSectionEntry) {
        if let index = sectionCards.firstIndex(where: { $0.id == id }) {
            sectionCards[index] = updatedCard
            sectionCardsUIChangeToken += 1
        }
    }

    /// Delete a section card by ID
    func deleteSectionCard(id: String) {
        sectionCards.removeAll(where: { $0.id == id })
        sectionCardsUIChangeToken += 1
    }

    /// Add a new publication card
    func addPublicationCard(_ card: PublicationCard) {
        publicationCards.append(card)
        publicationCardsUIChangeToken += 1
    }

    /// Update an existing publication card
    func updatePublicationCard(id: String, with updatedCard: PublicationCard) {
        if let index = publicationCards.firstIndex(where: { $0.id == id }) {
            publicationCards[index] = updatedCard
            publicationCardsUIChangeToken += 1
        }
    }

    /// Delete a publication card by ID
    func deletePublicationCard(id: String) {
        publicationCards.removeAll(where: { $0.id == id })
        publicationCardsUIChangeToken += 1
    }
}
