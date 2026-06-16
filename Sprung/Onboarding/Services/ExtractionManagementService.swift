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
    let eventBus: EventBus
    private let state: StateCoordinator
    /// Buffer for extraction progress updates that arrive before extraction is set
    private var pendingExtractionProgressBuffer: [ExtractionProgressUpdate] = []
    // MARK: - Initialization
    init(
        eventBus: EventBus,
        state: StateCoordinator
    ) {
        self.eventBus = eventBus
        self.state = state
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
                await eventBus.publish(.processing(.pendingExtractionUpdated(extraction, statusMessage: statusMessage)))
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
            return update.detail ?? "Processing document..."
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
}
