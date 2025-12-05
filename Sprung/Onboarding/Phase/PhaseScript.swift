//
//  PhaseScript.swift
//  Sprung
//
//  Strategy protocol for onboarding interview phases.
//  Each phase defines its own objectives, introductory prompt, and validation logic.
//
import Foundation
import SwiftyJSON
/// Context passed to workflow closures when objectives change state.
struct ObjectiveWorkflowContext {
    let completedObjectives: Set<String>
    let status: ObjectiveStatus  // From InterviewPhase.swift file
    let details: [String: String]
}
/// Actions a workflow may request when an objective transitions.
enum ObjectiveWorkflowOutput {
    /// Send a developer message to the LLM. Optional toolChoice forces a specific tool call.
    case developerMessage(title: String, details: [String: String], payload: JSON?, toolChoice: String? = nil)
    case triggerPhotoFollowUp(extraDetails: [String: String])
}
/// Declarative workflow metadata for a specific objective.
struct ObjectiveWorkflow {
    let id: String
    let dependsOn: [String]
    let autoStartWhenReady: Bool
    private let onBeginHandler: ((ObjectiveWorkflowContext) -> [ObjectiveWorkflowOutput])?
    private let onCompleteHandler: ((ObjectiveWorkflowContext) -> [ObjectiveWorkflowOutput])?
    init(
        id: String,
        dependsOn: [String] = [],
        autoStartWhenReady: Bool = false,
        onBegin: ((ObjectiveWorkflowContext) -> [ObjectiveWorkflowOutput])? = nil,
        onComplete: ((ObjectiveWorkflowContext) -> [ObjectiveWorkflowOutput])? = nil
    ) {
        self.id = id
        self.dependsOn = dependsOn
        self.autoStartWhenReady = autoStartWhenReady
        self.onBeginHandler = onBegin
        self.onCompleteHandler = onComplete
    }
    func outputs(for status: ObjectiveStatus, context: ObjectiveWorkflowContext) -> [ObjectiveWorkflowOutput] {
        switch status {
        case .inProgress:
            return onBeginHandler?(context) ?? []
        case .completed:
            return onCompleteHandler?(context) ?? []
        case .pending, .skipped:
            return []
        }
    }
}
/// Defines the behavior and configuration for a specific interview phase.
protocol PhaseScript {
    /// The phase this script represents.
    var phase: InterviewPhase { get }
    /// Introductory prompt sent as a developer message when this phase begins, describing this phase's goals and tools.
    var introductoryPrompt: String { get }
    /// Required objectives that must be completed before advancing.
    var requiredObjectives: [String] { get }
    /// Tools that are allowed in this phase.
    var allowedTools: [String] { get }
    /// Declarative workflows for objectives in this phase.
    var objectiveWorkflows: [String: ObjectiveWorkflow] { get }
    /// Convenience lookup for a single workflow.
    func workflow(for objectiveId: String) -> ObjectiveWorkflow?
    /// Validates whether this phase can advance based on completed objectives.
    func canAdvance(completedObjectives: Set<String>) -> Bool
    /// Returns missing objectives for this phase.
    func missingObjectives(completedObjectives: Set<String>) -> [String]
}
// MARK: - Default Implementations
extension PhaseScript {
    var objectiveWorkflows: [String: ObjectiveWorkflow] { [:] }
    func workflow(for objectiveId: String) -> ObjectiveWorkflow? {
        objectiveWorkflows[objectiveId]
    }
    func canAdvance(completedObjectives: Set<String>) -> Bool {
        requiredObjectives.allSatisfy { completedObjectives.contains($0) }
    }
    func missingObjectives(completedObjectives: Set<String>) -> [String] {
        requiredObjectives.filter { !completedObjectives.contains($0) }
    }
}
