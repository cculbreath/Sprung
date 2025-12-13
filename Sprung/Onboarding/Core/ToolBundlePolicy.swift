//
//  ToolBundlePolicy.swift
//  Sprung
//
//  Dynamic tool bundling policy to minimize tools sent per request.
//  Part of Milestone 3: Dynamic tool bundling
//

import Foundation
import SwiftOpenAI

/// Policy for selecting minimal tool sets per request
struct ToolBundlePolicy {

    // MARK: - Tool Bundle Contexts

    enum BundleContext {
        case noTools                        // toolChoice == .none
        case forcedTool(String)             // Specific tool forced via toolChoice
        case awaitingUserUpload             // Document collection UI open, waiting for uploads
        case awaitingUserApproval           // Validation/approval UI open
        case phaseTransition                // Between phases
        case normalOperation(InterviewPhase) // Standard operation within a phase
    }

    // MARK: - Safe Escape Tools

    /// Minimal set of tools that should always be available (for error recovery)
    static let safeEscapeTools: Set<String> = [
        OnboardingToolName.getUserOption.rawValue  // Allow user to cancel/escape
    ]

    // MARK: - Phase-Specific Minimal Tool Sets

    /// Minimal tools for Phase 1 core operations
    static let phase1MinimalTools: Set<String> = [
        OnboardingToolName.getApplicantProfile.rawValue,
        OnboardingToolName.getUserUpload.rawValue,
        OnboardingToolName.displayTimelineEntriesForReview.rawValue,
        OnboardingToolName.createTimelineCard.rawValue,
        OnboardingToolName.submitForValidation.rawValue,
        OnboardingToolName.configureEnabledSections.rawValue,
        OnboardingToolName.nextPhase.rawValue
    ]

    /// Minimal tools for Phase 2 core operations
    static let phase2MinimalTools: Set<String> = [
        OnboardingToolName.startPhaseTwo.rawValue,
        OnboardingToolName.openDocumentCollection.rawValue,
        OnboardingToolName.proposeCardAssignments.rawValue,
        OnboardingToolName.dispatchKCAgents.rawValue,
        OnboardingToolName.submitKnowledgeCard.rawValue,
        OnboardingToolName.nextPhase.rawValue
    ]

    /// Minimal tools for Phase 3 core operations
    static let phase3MinimalTools: Set<String> = [
        OnboardingToolName.startPhaseThree.rawValue,
        OnboardingToolName.ingestWritingSample.rawValue,
        OnboardingToolName.nextPhase.rawValue
    ]

    // MARK: - Bundle Selection

    /// Select minimal tool bundle based on context
    /// - Parameters:
    ///   - context: The current bundle context
    ///   - allowedTools: The full set of allowed tools for this phase
    /// - Returns: Filtered set of tool names to include
    static func selectBundle(
        for context: BundleContext,
        from allowedTools: Set<String>
    ) -> Set<String> {
        switch context {
        case .noTools:
            // No tools when toolChoice is none
            return []

        case .forcedTool(let toolName):
            // Only the forced tool plus safe escape tools
            var bundle = safeEscapeTools
            bundle.insert(toolName)
            return bundle.intersection(allowedTools)

        case .awaitingUserUpload:
            // Minimal tools while waiting for uploads
            let uploadTools: Set<String> = [
                OnboardingToolName.getUserUpload.rawValue,
                OnboardingToolName.cancelUserUpload.rawValue,
                OnboardingToolName.scanGitRepo.rawValue,
                OnboardingToolName.listArtifacts.rawValue
            ]
            return uploadTools.union(safeEscapeTools).intersection(allowedTools)

        case .awaitingUserApproval:
            // Minimal tools while waiting for approval
            let approvalTools: Set<String> = [
                OnboardingToolName.submitForValidation.rawValue
            ]
            return approvalTools.union(safeEscapeTools).intersection(allowedTools)

        case .phaseTransition:
            // Only phase advancement tools
            let transitionTools: Set<String> = [
                OnboardingToolName.nextPhase.rawValue,
                OnboardingToolName.setObjectiveStatus.rawValue
            ]
            return transitionTools.union(safeEscapeTools).intersection(allowedTools)

        case .normalOperation(let phase):
            // Phase-specific minimal set
            let phaseTools: Set<String>
            switch phase {
            case .phase1CoreFacts:
                phaseTools = phase1MinimalTools
            case .phase2DeepDive:
                phaseTools = phase2MinimalTools
            case .phase3WritingCorpus:
                phaseTools = phase3MinimalTools
            default:
                // For other phases, use all allowed tools
                return allowedTools
            }
            return phaseTools.union(safeEscapeTools).intersection(allowedTools)
        }
    }

    /// Determine the bundle context from current state
    /// - Parameters:
    ///   - toolChoice: The tool choice mode for this request
    ///   - isUploadUIActive: Whether upload UI is currently displayed
    ///   - isValidationUIActive: Whether validation UI is currently displayed
    ///   - phase: Current interview phase
    /// - Returns: The appropriate bundle context
    static func determineContext(
        toolChoice: ToolChoiceMode,
        isUploadUIActive: Bool,
        isValidationUIActive: Bool,
        phase: InterviewPhase
    ) -> BundleContext {
        // Check toolChoice first
        switch toolChoice {
        case .none:
            return .noTools
        case .functionTool(let ft):
            return .forcedTool(ft.name)
        case .customTool(let ct):
            return .forcedTool(ct.name)
        default:
            break
        }

        // Check UI state
        if isUploadUIActive {
            return .awaitingUserUpload
        }
        if isValidationUIActive {
            return .awaitingUserApproval
        }

        // Default to normal operation
        return .normalOperation(phase)
    }
}
