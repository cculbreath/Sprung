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
    // MARK: - Event Handling
    private func handleObjectiveEvent(_ event: OnboardingEvent) async {
        guard case .objective(.statusChanged(
            let id,
            let oldStatusString,
            let newStatusString,
            let phaseString,
            let source,
            let notes,
            let eventDetails
        )) = event else {
            return
        }
        guard let newStatus = ObjectiveStatus(rawValue: newStatusString) else {
            Logger.warning("Invalid objective status: \(newStatusString)", category: .ai)
            return
        }
        // Process workflows for inProgress (onBegin) and completed (onComplete)
        guard newStatus == .inProgress || newStatus == .completed else { return }
        // For onBegin callbacks, only fire on first transition to inProgress (from pending)
        if newStatus == .inProgress {
            let oldStatus = oldStatusString.flatMap { ObjectiveStatus(rawValue: $0) }
            guard oldStatus == .pending || oldStatus == nil else {
                Logger.debug("Skipping onBegin for \(id): not a fresh start (was: \(oldStatusString ?? "nil"))", category: .ai)
                return
            }
        }
        let sourceInfo = source.map { " from \($0)" } ?? ""
        let statusLabel = newStatus == .inProgress ? "in-progress" : "completed"
        Logger.info("🎯 Processing workflow for \(statusLabel) objective: \(id)\(sourceInfo)", category: .ai)
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
        // Build the context with source, notes, and details from the event
        let completedObjectives = await state.getAllObjectives()
            .filter { $0.status == .completed || $0.status == .skipped }
            .map { $0.id }
        // Merge all metadata: start with event details, then add source and notes
        var details: [String: String] = eventDetails ?? [:]
        if let source = source {
            details["source"] = source
        }
        if let notes = notes {
            details["notes"] = notes
        }
        let context = ObjectiveWorkflowContext(
            completedObjectives: Set(completedObjectives),
            status: newStatus,
            details: details
        )
        // Execute the workflow callbacks
        let outputs = workflow.outputs(for: newStatus, context: context)
        for output in outputs {
            await processWorkflowOutput(output)
        }
        // If objective completed, check for dependent objectives to auto-start
        if newStatus == .completed {
            await checkAndAutoStartDependents(
                completedObjectiveId: id,
                phase: phase,
                script: script,
                completedObjectives: Set(completedObjectives)
            )
        }
    }
    // MARK: - Auto-Start Logic
    /// Check if any dependent objectives can be auto-started after an objective completes
    private func checkAndAutoStartDependents(
        completedObjectiveId: String,
        phase: InterviewPhase,
        script: PhaseScript,
        completedObjectives: Set<String>
    ) async {
        // Get all objectives for this phase
        let allObjectives = await state.getObjectivesForPhase(phase)
        // Find objectives that depend on the completed one
        for objective in allObjectives {
            // Skip if not pending
            guard objective.status == .pending else { continue }
            // Get workflow definition
            guard let workflow = script.workflow(for: objective.id) else { continue }
            // Skip if doesn't depend on completed objective
            guard workflow.dependsOn.contains(completedObjectiveId) else { continue }
            // Skip if auto-start not enabled
            guard workflow.autoStartWhenReady else {
                Logger.debug("⏸️ Objective \(objective.id) depends on \(completedObjectiveId) but autoStartWhenReady=false", category: .ai)
                continue
            }
            // Check if ALL dependencies are met
            let allDependenciesMet = workflow.dependsOn.allSatisfy { completedObjectives.contains($0) }
            if allDependenciesMet {
                Logger.info("🚀 Auto-starting objective: \(objective.id) (dependencies met: \(workflow.dependsOn.joined(separator: ", ")))", category: .ai)
                // Emit event to transition to inProgress
                // This will trigger the onBegin callback via the normal event flow
                await emit(.objective(.statusUpdateRequested(
                    id: objective.id,
                    status: ObjectiveStatus.inProgress.rawValue,
                    source: "workflow_auto_start",
                    notes: "Auto-started after dependencies completed: \(workflow.dependsOn.joined(separator: ", "))",
                    details: nil
                )))
            } else {
                let missingDeps = workflow.dependsOn.filter { !completedObjectives.contains($0) }
                Logger.debug("⏳ Objective \(objective.id) still waiting for: \(missingDeps.joined(separator: ", "))", category: .ai)
            }
        }
    }
    // MARK: - Workflow Output Processing
    private func processWorkflowOutput(_ output: ObjectiveWorkflowOutput) async {
        switch output {
        case .coordinatorMessage(let title, let details, let payload):
            await sendCoordinatorMessage(title: title, details: details, payload: payload)
        case .triggerPhotoFollowUp(let extraDetails):
            await triggerPhotoFollowUp(extraDetails: extraDetails)
        }
    }
    /// Send a coordinator message to the LLM
    private func sendCoordinatorMessage(title: String, details: [String: String], payload: JSON?) async {
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
        await emit(.llm(.sendCoordinatorMessage(payload: messagePayload)))
    }
    /// Trigger the photo follow-up workflow
    private func triggerPhotoFollowUp(extraDetails: [String: String]) async {
        // Build developer message that instructs LLM to request photo upload
        let title = "Contact data validated successfully. Now request a profile photo using get_user_upload with target_key=\"basics.image\". The user may provide or skip this step."
        var details = extraDetails
        details["next_objective"] = OnboardingObjectiveId.contactPhotoCollected.rawValue
        details["instruction"] = "Call get_user_upload tool to request photo"
        await sendCoordinatorMessage(title: title, details: details, payload: nil)
    }
}
