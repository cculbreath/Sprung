//
//  ObjectiveWorkflowEngine.swift
//  Sprung
//
//  Phase 3: Automatic workflow execution when objectives complete
//  Subscribes to objective events and executes workflows defined in PhaseScript
//

import Foundation
import SwiftyJSON

/// Engine that automatically triggers workflows when objectives complete
actor ObjectiveWorkflowEngine: OnboardingEventEmitter {
    // MARK: - Properties

    let eventBus: EventCoordinator
    private let phaseRegistry: PhaseScriptRegistry
    private let state: StateCoordinator

    private var subscriptionTask: Task<Void, Never>?
    private var isActive = false

    // MARK: - Initialization

    init(
        eventBus: EventCoordinator,
        phaseRegistry: PhaseScriptRegistry,
        state: StateCoordinator
    ) {
        self.eventBus = eventBus
        self.phaseRegistry = phaseRegistry
        self.state = state
        Logger.info("🔄 ObjectiveWorkflowEngine initialized", category: .ai)
    }

    // MARK: - Lifecycle

    func start() {
        guard !isActive else { return }
        isActive = true

        subscriptionTask = Task { [weak self] in
            guard let self else { return }

            for await event in await self.eventBus.stream(topic: .objective) {
                if Task.isCancelled { break }
                await self.handleObjectiveEvent(event)
            }
        }

        Logger.info("▶️ ObjectiveWorkflowEngine started", category: .ai)
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        subscriptionTask?.cancel()
        subscriptionTask = nil
        Logger.info("⏹️ ObjectiveWorkflowEngine stopped", category: .ai)
    }

    // MARK: - Event Handling

    private func handleObjectiveEvent(_ event: OnboardingEvent) async {
        guard case .objectiveStatusChanged(
            let id,
            let oldStatusString,
            let newStatusString,
            let phaseString,
            let source,
            let notes
        ) = event else {
            return
        }

        guard let status = ObjectiveStatus(rawValue: newStatusString) else {
            Logger.warning("Invalid objective status: \(newStatusString)", category: .ai)
            return
        }

        // Only process completed objectives
        guard status == .completed else { return }

        let sourceInfo = source.map { " from \($0)" } ?? ""
        Logger.info("🎯 Processing workflow for completed objective: \(id)\(sourceInfo)", category: .ai)

        // Get the phase script
        guard let phase = InterviewPhase(rawValue: phaseString),
              let script = await MainActor.run(body: { phaseRegistry.script(for: phase) }) else {
            Logger.warning("No script found for phase: \(phaseString)", category: .ai)
            return
        }

        // Get the workflow for this objective
        guard let workflow = script.workflow(for: id) else {
            Logger.debug("No workflow defined for objective: \(id)", category: .ai)
            return
        }

        // Build the context
        let completedObjectives = await state.getAllObjectives()
            .filter { $0.status == .completed || $0.status == .skipped }
            .map { $0.id }

        let context = ObjectiveWorkflowContext(
            completedObjectives: Set(completedObjectives),
            status: status,
            details: [:]  // Future: could extract from objective notes
        )

        // Execute the workflow
        let outputs = workflow.outputs(for: status, context: context)

        for output in outputs {
            await processWorkflowOutput(output, objectiveId: id)
        }
    }

    // MARK: - Workflow Output Processing

    private func processWorkflowOutput(_ output: ObjectiveWorkflowOutput, objectiveId: String) async {
        switch output {
        case .developerMessage(let title, let details, let payload):
            await sendDeveloperMessage(title: title, details: details, payload: payload)

        case .triggerPhotoFollowUp(let extraDetails):
            await triggerPhotoFollowUp(extraDetails: extraDetails)
        }
    }

    /// Send a developer message to the LLM
    private func sendDeveloperMessage(title: String, details: [String: String], payload: JSON?) async {
        var messagePayload = JSON()
        messagePayload["text"].string = "Developer status: \(title)"

        if !details.isEmpty {
            var detailsJSON = JSON()
            for (key, value) in details {
                detailsJSON[key].string = value
            }
            messagePayload["details"] = detailsJSON
        }

        if let payload = payload {
            messagePayload["payload"] = payload
        }

        Logger.info("📤 Workflow sending developer message: \(title)", category: .ai)
        await emit(.llmSendDeveloperMessage(payload: messagePayload))
    }

    /// Trigger the photo follow-up workflow
    private func triggerPhotoFollowUp(extraDetails: [String: String]) async {
        // Build developer message that instructs LLM to request photo upload
        let title = "Contact data validated successfully. Now request a profile photo using get_user_upload with target_key=\"basics.image\". The user may provide or skip this step."

        var details = extraDetails
        details["next_objective"] = "contact_photo_collected"
        details["instruction"] = "Call get_user_upload tool to request photo"

        await sendDeveloperMessage(title: title, details: details, payload: nil)
    }
}
