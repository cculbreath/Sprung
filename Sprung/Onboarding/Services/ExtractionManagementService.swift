//
//  ExtractionManagementService.swift
//  Sprung
//
//  Service for managing document extraction and validation processes.
//  Extracted from OnboardingInterviewCoordinator to reduce complexity.
//
import Foundation
import SwiftyJSON
/// Service that handles document extraction management
@MainActor
final class ExtractionManagementService: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventCoordinator
    private let state: StateCoordinator
    private let toolRouter: ToolHandler
    private let wizardTracker: WizardProgressTracker
    /// Buffer for extraction progress updates that arrive before extraction is set
    private var pendingExtractionProgressBuffer: [ExtractionProgressUpdate] = []
    // MARK: - Initialization
    init(
        eventBus: EventCoordinator,
        state: StateCoordinator,
        toolRouter: ToolHandler,
        wizardTracker: WizardProgressTracker
    ) {
        self.eventBus = eventBus
        self.state = state
        self.toolRouter = toolRouter
        self.wizardTracker = wizardTracker
    }
    // MARK: - Extraction Status Management
    func setExtractionStatus(_ extraction: OnboardingPendingExtraction?) {
        Task {
            // Publish event instead of direct state mutation
            let statusMessage = extraction.map {
                $0.title.lowercased().contains("pdf") || $0.title.lowercased().contains("resume")
                    ? "Processing PDF with Gemini AI..."
                    : "Extracting content from \($0.title)..."
            }
            await eventBus.publish(.pendingExtractionUpdated(extraction, statusMessage: statusMessage))
            // StateCoordinator maintains sync cache
            guard let extraction else { return }
            if shouldClearApplicantProfileIntake(for: extraction) {
                await MainActor.run {
                    toolRouter.clearApplicantProfileIntake()
                }
                Logger.debug(
                    "🧹 Cleared applicant profile intake for extraction",
                    category: .ai,
                    metadata: [
                        "title": extraction.title,
                        "summary": extraction.summary
                    ]
                )
            }
        }
    }
    private func shouldClearApplicantProfileIntake(for extraction: OnboardingPendingExtraction) -> Bool {
        // If the extraction already contains an applicant profile, clear the intake immediately.
        if extraction.rawExtraction["derived"]["applicant_profile"] != .null {
            return true
        }
        let metadata = extraction.rawExtraction["metadata"]
        var candidateStrings: [String] = []
        if let purpose = metadata["purpose"].string { candidateStrings.append(purpose) }
        if let documentKind = metadata["document_kind"].string { candidateStrings.append(documentKind) }
        if let sourceFilename = metadata["source_filename"].string { candidateStrings.append(sourceFilename) }
        candidateStrings.append(extraction.title)
        candidateStrings.append(extraction.summary)
        let resumeKeywords = ["resume", "curriculum vitae", "curriculum", "cv", "applicant profile"]
        for value in candidateStrings {
            let lowercased = value.lowercased()
            if resumeKeywords.contains(where: { lowercased.contains($0) }) {
                return true
            }
        }
        let tags = metadata["tags"].arrayValue.compactMap { $0.string?.lowercased() }
        if tags.contains(where: { tag in resumeKeywords.contains(where: { tag.contains($0) }) }) {
            return true
        }
        return false
    }
    // MARK: - Progress Updates
    func updateExtractionProgress(with update: ExtractionProgressUpdate) {
        Logger.info("📊 [TRACE] updateExtractionProgress called: stage=\(update.stage), state=\(update.state)", category: .ai)
        Task {
            Logger.info("📊 [TRACE] Inside Task, about to check pendingExtraction", category: .ai)
            if var extraction = await state.pendingExtraction {
                Logger.info("📊 [TRACE] pendingExtraction exists, applying update", category: .ai)
                extraction.applyProgressUpdate(update)
                // Create status message based on the update
                let statusMessage = createStatusMessage(for: update)
                // Publish event with status message
                await eventBus.publish(.pendingExtractionUpdated(extraction, statusMessage: statusMessage))
                // StateCoordinator maintains sync cache
            } else {
                pendingExtractionProgressBuffer.append(update)
            }
        }
    }
    private func createStatusMessage(for update: ExtractionProgressUpdate) -> String? {
        switch (update.stage, update.state) {
        case (.fileAnalysis, .active):
            return update.detail ?? "Analyzing document..."
        case (.aiExtraction, .active):
            return update.detail ?? "Processing with Gemini AI..."
        case (.artifactSave, .active):
            return "Saving extracted content..."
        case (.assistantHandoff, .active):
            return "Preparing for interview..."
        case (_, .completed):
            return nil // Clear message when stage completes
        case (_, .failed):
            return "Processing failed: \(update.detail ?? "Unknown error")"
        default:
            return nil
        }
    }
    // MARK: - Streaming Status
    func setStreamingStatus(_ status: String?) async {
        // Publish event instead of direct state mutation
        await eventBus.publish(.streamingStatusUpdated(status))
        // StateCoordinator maintains sync cache
    }
    // MARK: - Wizard Synchronization
    func synchronizeWizardTracker(
        currentStep: StateCoordinator.WizardStep,
        completedSteps: Set<StateCoordinator.WizardStep>
    ) {
        let mappedCurrent = OnboardingWizardStep(rawValue: currentStep.rawValue) ?? .introduction
        let mappedCompleted = Set(
            completedSteps.compactMap { OnboardingWizardStep(rawValue: $0.rawValue) }
        )
        wizardTracker.synchronize(currentStep: mappedCurrent, completedSteps: mappedCompleted)
    }
}
