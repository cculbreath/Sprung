import SwiftUI
import SwiftOpenAI

// MARK: - Refine Response Type

private struct RefineResponse: Codable {
    struct Refinement: Codable {
        let skillId: String
        let newName: String
    }
    let refinements: [Refinement]
}

// MARK: - LLM Processing Actions

extension SkillsBankBrowser {
    func consolidateDuplicates() {
        guard let skillStore = skillStore, let facade = llmFacade else { return }

        isProcessing = true
        currentOperation = .deduplication
        processingMessage = "Analyzing skills for duplicates..."
        processingProgress = 0

        Task {
            do {
                let service = SkillsProcessingService(skillStore: skillStore, facade: facade)
                processingService = service

                // Monitor progress
                let progressTask = Task {
                    while !Task.isCancelled {
                        await MainActor.run {
                            if case .processing(let msg) = service.status {
                                processingMessage = msg
                            }
                            processingProgress = service.progress
                        }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }

                let result = try await service.consolidateDuplicates()
                progressTask.cancel()

                await MainActor.run {
                    lastResult = result
                    isProcessing = false
                    currentOperation = nil
                    showResultAlert = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                    currentOperation = nil
                    showResultAlert = true
                }
            }
        }
    }

    func expandATSVariants() {
        guard let skillStore = skillStore, let facade = llmFacade else { return }

        isProcessing = true
        currentOperation = .atsExpansion
        processingMessage = "Generating ATS synonyms..."
        processingProgress = 0

        Task {
            do {
                let service = SkillsProcessingService(skillStore: skillStore, facade: facade)
                processingService = service

                // Monitor progress
                let progressTask = Task {
                    while !Task.isCancelled {
                        await MainActor.run {
                            if case .processing(let msg) = service.status {
                                processingMessage = msg
                            }
                            processingProgress = service.progress
                        }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }

                let result = try await service.expandATSSynonyms()
                progressTask.cancel()

                await MainActor.run {
                    lastResult = result
                    isProcessing = false
                    currentOperation = nil
                    showResultAlert = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                    currentOperation = nil
                    showResultAlert = true
                }
            }
        }
    }

    func refineSkills() {
        guard let skillStore = skillStore, let facade = llmFacade else { return }
        let instruction = refineInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }

        isProcessing = true
        currentOperation = .refine
        processingMessage = "Refining skill names..."
        processingProgress = 0

        Task {
            do {
                let allSkills = skillStore.skills
                let totalSkills = allSkills.count

                let skillList = allSkills.enumerated().map { index, skill in
                    "\(index + 1). \(skill.id.uuidString): \(skill.canonical)"
                }.joined(separator: "\n")

                let systemPrompt = """
                    You are a professional resume skills editor. You refine skill names according to \
                    user instructions. Return a JSON object with a "refinements" array containing \
                    objects with "skillId" and "newName" fields. Only include skills whose names should change.
                    """

                let userMessage = """
                    **Instruction:** \(instruction)

                    **Skills to refine:**
                    \(skillList)
                    """

                let schema: [String: Any] = [
                    "type": "object",
                    "properties": [
                        "refinements": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "skillId": ["type": "string"],
                                    "newName": ["type": "string"]
                                ],
                                "required": ["skillId", "newName"]
                            ]
                        ]
                    ],
                    "required": ["refinements"]
                ]

                guard let modelId = UserDefaults.standard.string(forKey: "skillsProcessingModelId"), !modelId.isEmpty else {
                    throw SkillsProcessingError.llmNotConfigured
                }

                processingMessage = "AI is refining \(totalSkills) skills..."

                let jsonSchema = try JSONSchema.from(dictionary: schema)
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(effort: userEffort, includeReasoning: true)

                reasoningStreamManager.clear()
                reasoningStreamManager.startReasoning(modelName: modelId)

                let handle = try await facade.startConversationStreaming(
                    systemPrompt: systemPrompt,
                    userMessage: userMessage,
                    modelId: modelId,
                    reasoning: reasoning,
                    jsonSchema: jsonSchema
                )

                // Process stream with reasoning display
                var fullResponse = ""
                var collectingJSON = false
                var jsonResponse = ""

                for try await chunk in handle.stream {
                    if let reasoningContent = chunk.allReasoningText {
                        reasoningStreamManager.reasoningText += reasoningContent
                    }
                    if let content = chunk.content {
                        fullResponse += content
                        if content.contains("{") || collectingJSON {
                            collectingJSON = true
                            jsonResponse += content
                        }
                    }
                    if chunk.isFinished {
                        reasoningStreamManager.isStreaming = false
                        reasoningStreamManager.isVisible = false
                    }
                }

                let responseText = jsonResponse.isEmpty ? fullResponse : jsonResponse
                let response: RefineResponse = try LLMResponseParser.parseJSON(responseText, as: RefineResponse.self)

                // Apply refinements
                var modifiedCount = 0
                for refinement in response.refinements {
                    if let skillUUID = UUID(uuidString: refinement.skillId),
                       let skill = skillStore.skill(withId: skillUUID) {
                        let newName = refinement.newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !newName.isEmpty && newName != skill.canonical {
                            skill.canonical = newName
                            skillStore.update(skill)
                            modifiedCount += 1
                        }
                    }
                }

                await MainActor.run {
                    lastResult = SkillsProcessingResult(
                        operation: "Refine",
                        skillsProcessed: totalSkills,
                        skillsModified: modifiedCount,
                        details: "Refined \(modifiedCount) of \(totalSkills) skill names"
                    )
                    isProcessing = false
                    currentOperation = nil
                    refineInstruction = ""
                    showResultAlert = true
                }
            } catch {
                reasoningStreamManager.isStreaming = false
                reasoningStreamManager.isVisible = false
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                    currentOperation = nil
                    showResultAlert = true
                }
            }
        }
    }

    // MARK: - Curation

    func curateSkills() {
        guard let skillStore = skillStore, let facade = llmFacade else { return }

        isProcessing = true
        currentOperation = .curation
        processingMessage = "Analyzing skills for curation..."
        processingProgress = 0

        Task {
            do {
                let service = SkillBankCurationService(skillStore: skillStore, llmFacade: facade)
                let plan = try await service.generateCurationPlan()

                await MainActor.run {
                    self.curationPlan = plan
                    isProcessing = false
                    currentOperation = nil

                    if plan.isEmpty {
                        lastResult = SkillsProcessingResult(
                            operation: "Curation",
                            skillsProcessed: skillStore.skills.count,
                            skillsModified: 0,
                            details: "No curation changes suggested"
                        )
                        showResultAlert = true
                    } else {
                        showCurationReview = true
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                    currentOperation = nil
                    showResultAlert = true
                }
            }
        }
    }
}
