//
//  GenerateExperienceDefaultsTool.swift
//  Sprung
//
//  Tool that triggers the ExperienceDefaults agent to generate resume content.
//  The agent runs with full context access (KCs, skills, timeline) and produces
//  structured experience defaults for the Experience Editor.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

struct GenerateExperienceDefaultsTool: InterviewTool {
    private weak var coordinator: OnboardingInterviewCoordinator?
    private let eventBus: EventCoordinator
    private let agentActivityTracker: AgentActivityTracker

    var name: String { OnboardingToolName.generateExperienceDefaults.rawValue }
    var description: String {
        """
        Triggers the ExperienceDefaults agent to generate resume content from knowledge cards.
        The agent has full access to all KCs, skills, and timeline data.
        It will generate:
        - Work experience highlights (3-4 bullets per entry)
        - Selected projects with summaries
        - Curated skills in 5 categories (25-35 total)
        - Content for other enabled sections

        Requires knowledge cards to exist. Ensure Phase 3 evidence collection is complete first.
        """
    }

    var parameters: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Triggers experience defaults generation agent",
            properties: [
                "notes": JSONSchema(
                    type: .string,
                    description: "Optional notes or special instructions for the agent"
                )
            ],
            required: []
        )
    }

    init(
        coordinator: OnboardingInterviewCoordinator,
        eventBus: EventCoordinator,
        agentActivityTracker: AgentActivityTracker
    ) {
        self.coordinator = coordinator
        self.eventBus = eventBus
        self.agentActivityTracker = agentActivityTracker
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }
        // Check prerequisites
        let (knowledgeCards, shouldGenerateTitleSets, titleSets, state) = await MainActor.run {
            (
                coordinator.getKnowledgeCardStore().onboardingCards,
                coordinator.ui.shouldGenerateTitleSets,
                coordinator.guidanceStore.titleSets(),
                coordinator.state
            )
        }

        if knowledgeCards.isEmpty {
            return .error(.executionFailed(
                "No knowledge cards found. The agent requires KCs to generate content. " +
                "Ensure Phase 3 evidence collection is complete and documents have been uploaded."
            ))
        }

        if shouldGenerateTitleSets {
            if titleSets.isEmpty {
                return .error(.executionFailed(
                    "Identity title sets have not been curated yet. " +
                    "Ask the user to select and save title sets before generating experience defaults."
                ))
            }
        }

        let enabledSections = await state.getEnabledSections()
        if enabledSections.isEmpty {
            return .error(.executionFailed(
                "No sections enabled. Call configure_enabled_sections first to specify which " +
                "resume sections to generate."
            ))
        }

        // Create and run the agent service
        // Note: Status tracking is handled by AgentActivityTracker
        let service = await MainActor.run {
            ExperienceDefaultsAgentService(
                coordinator: coordinator,
                tracker: agentActivityTracker
            )
        }

        // Run agent (this may take a while)
        Logger.info("🗂️ Starting ExperienceDefaults agent", category: .ai)

        do {
            let result = try await service.run()

            // Build success response
            var response = JSON()
            response["status"].string = "completed"
            response["sections_generated"].arrayObject = result.sectionsGenerated
            response["summary"].string = result.summary
            response["turns_used"].int = result.turnsUsed

            // The agent already persisted to ExperienceDefaultsStore and marked objective complete

            // Prompt user review
            var devPayload = JSON()
            devPayload["title"].string = "Experience Defaults Generated"
            var details = JSON()
            details["instruction"].string = """
                The agent has generated experience defaults. \
                Call submit_for_validation with validation_type="experience_defaults" to show the user \
                what was generated and get their approval.
                """
            devPayload["details"] = details
            await eventBus.publish(.llm(.sendCoordinatorMessage(payload: devPayload)))

            return .immediate(response)

        } catch {
            Logger.error("🗂️ ExperienceDefaults agent failed: \(error.localizedDescription)", category: .ai)
            return .error(.executionFailed(
                "Agent failed: \(error.localizedDescription). You can retry the operation."
            ))
        }
    }
}
