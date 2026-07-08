//
//  DocumentIngestionKernel.swift
//  Sprung
//
//  Kernel for document ingestion via the Anthropic document-analysis pipeline.
//  Wraps DocumentProcessingService with the unified ingestion protocol.
//
import Foundation
import SwiftyJSON

/// Document ingestion kernel wrapping DocumentProcessingService
actor DocumentIngestionKernel {

    private let documentProcessingService: DocumentProcessingService
    private let eventBus: EventBus
    private weak var ingestionCoordinator: ArtifactIngestionCoordinator?

    /// Active ingestion tasks by pending ID
    private var activeTasks: [String: Task<Void, Never>] = [:]

    init(
        documentProcessingService: DocumentProcessingService,
        eventBus: EventBus
    ) {
        self.documentProcessingService = documentProcessingService
        self.eventBus = eventBus
    }

    func setIngestionCoordinator(_ coordinator: ArtifactIngestionCoordinator) {
        self.ingestionCoordinator = coordinator
    }

    // MARK: - Private

    /// Cancel all active document extraction tasks
    func cancelAllTasks() async {
        Logger.info("🛑 DocumentIngestionKernel: Cancelling \(activeTasks.count) active task(s)", category: .ai)
        for (pendingId, task) in activeTasks {
            task.cancel()
            Logger.debug("Cancelled document extraction task: \(pendingId)", category: .ai)
        }
        activeTasks.removeAll()
    }
}
