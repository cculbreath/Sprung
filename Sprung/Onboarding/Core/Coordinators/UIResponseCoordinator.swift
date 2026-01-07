import Foundation
import SwiftyJSON
/// Coordinator responsible for handling UI-driven responses and generating corresponding LLM messages.
/// This extracts the "User Action -> LLM Message" logic from the main coordinator.
@MainActor
final class UIResponseCoordinator {
    private let eventBus: EventCoordinator
    private let toolRouter: ToolHandler
    private let state: StateCoordinator
    private let ui: OnboardingUIState
    private let sessionUIState: SessionUIState
    init(
        eventBus: EventCoordinator,
        toolRouter: ToolHandler,
        state: StateCoordinator,
        ui: OnboardingUIState,
        sessionUIState: SessionUIState
    ) {
        self.eventBus = eventBus
        self.toolRouter = toolRouter
        self.state = state
        self.ui = ui
        self.sessionUIState = sessionUIState
    }
    // MARK: - Choice Selection
    func submitChoiceSelection(_ selectionIds: [String]) async {
        guard let result = toolRouter.resolveChoice(selectionIds: selectionIds) else { return }
        await submitChoiceSelectionInternal(selectionIds: selectionIds, result: result)
    }

    /// Submit a choice selection with custom free-form text (for "Other" option)
    func submitChoiceSelectionWithOther(_ otherText: String) async {
        // Clear the choice prompt
        toolRouter.clearChoicePrompt()
        await eventBus.publish(.choicePromptCleared)

        // Complete pending UI tool call with the free-form response
        var output = JSON()
        output["message"].string = "User selected 'Other' and provided: \(otherText)"
        output["status"].string = "completed"
        output["other_response"].string = otherText
        await completePendingUIToolCall(output: output)
        Logger.info("✅ Choice selection (Other) - free-form response included in tool response", category: .ai)
    }

    /// Cancel a choice selection - dismisses UI and sends cancellation to LLM
    func cancelChoiceSelection() async {
        // Clear the choice prompt UI
        toolRouter.clearChoicePrompt()
        await eventBus.publish(.choicePromptCleared)

        // Complete pending UI tool call with cancelled status
        var output = JSON()
        output["message"].string = "User cancelled the selection prompt"
        output["status"].string = "cancelled"
        await completePendingUIToolCall(output: output)
        Logger.info("✅ Choice selection cancelled - info included in tool response", category: .ai)
    }

    private func submitChoiceSelectionInternal(selectionIds: [String], result: (payload: JSON, source: String?)) async {

        // Handle special skip phase approval
        if result.source == "skip_phase_approval" {
            let approved = selectionIds.contains("approve")
            await state.setUserApprovedKCSkip(approved)
            Logger.info("📋 Skip phase approval: \(approved ? "approved" : "rejected")", category: .ai)

            // FORCED PHASE TRANSITION: When user approves, execute immediately
            // This bypasses the LLM to prevent dead-end stalls where the LLM
            // acknowledges but fails to call next_phase
            if approved {
                await forcePhaseTransition(reason: "User approved skip to next phase")
                Logger.info("⚡ Forced phase transition executed after user approval", category: .ai)
            }
        }

        // Clear the choice prompt and waiting state
        await eventBus.publish(.choicePromptCleared)

        // Complete pending UI tool call (Codex paradigm)
        // No separate user message needed - tool response contains the selection info
        var output = JSON()
        // For skip phase approval, provide clear feedback on user decision
        if result.source == "skip_phase_approval" {
            let approved = selectionIds.contains("approve")
            output["status"].string = approved ? "phase_advanced" : "rejected"
            output["message"].string = approved
                ? "User approved skip. Phase has been advanced. Begin new phase immediately."
                : "User rejected skip request. Continue working on current phase objectives."
        } else {
            output["message"].string = "User selected option(s): \(selectionIds.joined(separator: ", "))"
            output["status"].string = "completed"
        }
        await completePendingUIToolCall(output: output)
        Logger.info("✅ Choice selection - info included in tool response", category: .ai)
    }

    // MARK: - Forced Phase Transition

    /// Force an immediate phase transition without waiting for LLM to call next_phase.
    /// Used when user action should directly advance the phase (section toggle, skip approval, etc.)
    /// This is more reliable than forced toolChoice and eliminates LLM round trips.
    private func forcePhaseTransition(reason: String = "User action triggered phase advance") async {
        let currentPhase = await state.phase
        guard let nextPhase = currentPhase.next() else {
            Logger.warning("⚠️ Cannot force phase transition: already at final phase", category: .ai)
            return
        }

        Logger.info("⚡ Forcing phase transition: \(currentPhase.rawValue) → \(nextPhase.rawValue)", category: .ai)

        // Emit phase transition request - StateCoordinator will handle the actual transition
        // This triggers: setPhase() → phaseTransitionApplied → handlePhaseTransition (sends intro prompt)
        await eventBus.publish(.phaseTransitionRequested(
            from: currentPhase.rawValue,
            to: nextPhase.rawValue,
            reason: reason
        ))
    }
    // MARK: - Upload Handling
    func completeUploadAndResume(id: UUID, fileURLs: [URL], coordinator: OnboardingInterviewCoordinator) async {
        guard await coordinator.completeUpload(id: id, fileURLs: fileURLs) != nil else { return }

        // Check if any uploaded files require async extraction (PDF, DOCX, HTML, etc.)
        // For these, DON'T send a tool response yet - keep the tool call pending.
        // DocumentArtifactMessenger will complete the tool call with extracted content,
        // eliminating an unnecessary LLM round trip.
        let requiresAsyncExtraction = fileURLs.contains { url in
            let ext = url.pathExtension.lowercased()
            return ["pdf", "docx", "html", "htm"].contains(ext)
        }
        if requiresAsyncExtraction {
            // Don't complete the tool call yet - leave it pending
            // DocumentArtifactMessenger will complete it with extracted content
            Logger.info("📄 Upload completed - async extraction in progress, tool response deferred until extraction completes", category: .ai)
            return
        }

        // For non-extractable files (images, text), complete immediately with all info in tool response
        // No separate user message needed - tool response contains the completion info
        let filenames = fileURLs.map { $0.lastPathComponent }.joined(separator: ", ")
        var output = JSON()
        output["message"].string = "User uploaded \(fileURLs.count) file(s): \(filenames)"
        output["status"].string = "completed"
        await completePendingUIToolCall(output: output)
        Logger.info("✅ Upload completed (non-extractable files) - info included in tool response", category: .ai)
    }
    func skipUploadAndResume(id: UUID, coordinator: OnboardingInterviewCoordinator) async {
        guard await coordinator.skipUpload(id: id) != nil else { return }

        // Complete pending UI tool call with cancelled status
        // No separate user message needed - tool response contains the completion info
        var output = JSON()
        output["message"].string = "User skipped the upload"
        output["status"].string = "completed"
        await completePendingUIToolCall(output: output)
        Logger.info("✅ Upload skipped - info included in tool response", category: .ai)
    }
    // MARK: - Validation Handling
    func submitValidationAndResume(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?,
        coordinator: OnboardingInterviewCoordinator
    ) async {
        guard await coordinator.submitValidationResponse(status: status, updatedData: updatedData, changes: changes, notes: notes) != nil else { return }

        // Map status values from UI buttons to normalized status
        let statusDescription: String
        switch status.lowercased() {
        case "confirmed", "confirmed_with_changes", "approved", "modified":
            statusDescription = "confirmed"
        case "rejected":
            statusDescription = "rejected"
        default:
            statusDescription = status.lowercased()
        }

        // Complete the pending tool call with validation response
        var message = "Validation response: \(statusDescription)"
        if let notes = notes, !notes.isEmpty {
            message += ". Notes: \(notes)"
        }

        var output = JSON()
        output["message"].string = message
        output["status"].string = "completed"

        // Determine instruction based on validation type and status
        // Per Anthropic best practices, instruction text travels WITH the tool result
        let instruction: String?
        if statusDescription == "confirmed" {
            // Check if this is a timeline validation by looking at pending tool call
            let pendingTool = await state.getPendingUIToolCall()
            if pendingTool?.toolName == OnboardingToolName.submitForValidation.rawValue {
                // Timeline validated - guide to next step
                instruction = """
                    Timeline validation confirmed. Now call configure_enabled_sections \
                    to let the user choose which resume sections to include based on their timeline.
                    """
            } else {
                instruction = nil
            }
        } else {
            instruction = nil
        }

        await completePendingUIToolCall(output: output, instruction: instruction)

        Logger.info("✅ Validation response - info included in tool response", category: .ai)
    }

    func clearValidationPromptAndNotifyLLM(message: String) async {
        // Clear the validation prompt
        toolRouter.clearValidationPrompt()
        await eventBus.publish(.validationPromptCleared)

        // Complete the pending UI tool call with "changes_submitted" status
        // This unblocks the LLM from waiting for the submit_for_validation response
        var output = JSON()
        output["message"].string = message
        output["status"].string = "changes_submitted"
        await completePendingUIToolCall(output: output)

        // Get current timeline state to include in the message
        let timelineInfo = await buildTimelineCardSummary()
        // Send user message to LLM with current card state
        var userMessage = JSON()
        userMessage["role"].string = "user"
        var content = message
        if !timelineInfo.isEmpty {
            content += "\n\nCurrent timeline cards (with IDs for programmatic editing):\n\(timelineInfo)"
        }
        userMessage["content"].string = content
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Validation prompt cleared and user message sent to LLM (including \(timelineInfo.isEmpty ? "no" : "current") card state)", category: .ai)
    }

    /// Build a summary of current timeline cards with their IDs for the LLM
    private func buildTimelineCardSummary() async -> String {
        let artifacts = await state.artifacts
        guard let timeline = artifacts.skeletonTimeline,
              let entries = timeline["experiences"].array,
              !entries.isEmpty else {
            return ""
        }
        var lines: [String] = []
        for entry in entries {
            let id = entry["id"].stringValue
            let title = entry["title"].stringValue
            let org = entry["organization"].stringValue
            let start = entry["start"].stringValue
            let end = entry["end"].stringValue.isEmpty ? "present" : entry["end"].stringValue
            lines.append("- [\(id)] \(title) @ \(org) (\(start) - \(end))")
        }
        return lines.joined(separator: "\n")
    }

    /// Called when user clicks "Done with Timeline" in the editor.
    /// Clears the editor, ungates submit_for_validation, and forces the LLM to call it.
    func completeTimelineEditingAndRequestValidation() async {
        // Deactivate the timeline editor mode
        ui.isTimelineEditorActive = false
        // Emit event for session persistence
        await eventBus.publish(.timelineEditorActiveChanged(false))

        // Clear the validation/editor prompt (legacy, may not be set)
        toolRouter.clearValidationPrompt()
        await eventBus.publish(.validationPromptCleared)

        // Mark timeline enrichment objective as completed
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.timelineEnriched.rawValue,
            status: "completed",
            source: "user_done_with_timeline",
            notes: "User clicked Done with Timeline",
            details: nil
        ))

        // UNGATE: Allow submit_for_validation now that user clicked Done
        await sessionUIState.includeTool(OnboardingToolName.submitForValidation.rawValue)
        Logger.info("🔓 Ungated submit_for_validation after user clicked Done with Timeline", category: .ai)

        // Get current timeline info
        let timelineInfo = await buildTimelineCardSummary()

        // Send user message with mandatory toolChoice - LLM must call submit_for_validation
        var payload = JSON()
        var messageText = """
            I've completed editing my timeline and clicked "Done with Timeline". \
            Please call submit_for_validation with validation_type="skeleton_timeline" \
            to show me the final approval prompt so I can confirm my timeline.
            """
        if !timelineInfo.isEmpty {
            messageText += "\n\nCurrent timeline cards:\n\(timelineInfo)"
        }
        payload["text"].string = messageText

        await eventBus.publish(.llmSendUserMessage(
            payload: payload,
            isSystemGenerated: true,
            toolChoice: OnboardingToolName.submitForValidation.rawValue
        ))
        Logger.info("✅ Timeline editing complete - mandating submit_for_validation via toolChoice", category: .ai)
    }
    // MARK: - Applicant Profile Handling
    func confirmApplicantProfile(draft: ApplicantProfileDraft) async {
        guard let resolution = toolRouter.resolveApplicantProfile(with: draft) else { return }

        // Complete pending UI tool call (Codex paradigm)
        await completePendingUIToolCall(output: buildUICompletedOutput(message: "Profile confirmed via validation"))

        // Extract the actual profile data from the resolution
        let profileData = resolution["data"]
        let status = resolution["status"].stringValue
        // Store profile in StateCoordinator/ArtifactRepository (persists the data)
        await state.storeApplicantProfile(profileData)
        // Mark objective chain complete to trigger photo follow-up workflow
        // The objectives must be completed in dependency order
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.contactSourceSelected.rawValue,
            status: "completed",
            source: "ui_profile_confirmed",
            notes: "Profile confirmed via intake card",
            details: ["method": "intake_card"]
        ))
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.contactDataCollected.rawValue,
            status: "completed",
            source: "ui_profile_confirmed",
            notes: "Profile confirmed via intake card",
            details: ["method": "intake_card"]
        ))
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.contactDataValidated.rawValue,
            status: "completed",
            source: "ui_profile_confirmed",
            notes: "Profile confirmed via intake card",
            details: ["method": "intake_card"]
        ))
        // Mark the main applicant_profile_complete objective as complete
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.applicantProfileComplete.rawValue,
            status: "completed",
            source: "ui_profile_confirmed",
            notes: "Applicant profile validated and saved",
            details: ["method": "intake_card"]
        ))
        Logger.info("✅ applicant_profile_complete objective marked complete", category: .ai)
        // Build user message with the validated profile information
        var userMessage = JSON()
        userMessage["role"].string = "user"
        // Format profile data for the LLM
        var contentParts: [String] = ["I have provided my contact information:"]
        if let name = profileData["name"].string {
            contentParts.append("- Name: \(name)")
        }
        if let email = profileData["email"].string {
            contentParts.append("- Email: \(email)")
        }
        if let phone = profileData["phone"].string {
            contentParts.append("- Phone: \(phone)")
        }
        if let location = profileData["location"].string {
            contentParts.append("- Location: \(location)")
        }
        if let personalURL = profileData["personal_url"].string {
            contentParts.append("- Website: \(personalURL)")
        }
        // Add social profiles if present
        if let social = profileData["social_profiles"].array, !social.isEmpty {
            contentParts.append("- Social profiles: \(social.count) profile(s)")
        }
        contentParts.append("\nThis information has been validated and is ready for use.")
        userMessage["content"].string = contentParts.joined(separator: "\n")
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Applicant profile confirmed (\(status)) and data sent to LLM", category: .ai)
    }
    func rejectApplicantProfile(reason: String) async {
        guard toolRouter.rejectApplicantProfile(reason: reason) != nil else { return }

        // Complete pending UI tool call with rejection (Codex paradigm)
        // No separate user message needed - tool response contains the rejection info
        var output = JSON()
        output["message"].string = "Applicant profile rejected. Reason: \(reason)"
        output["status"].string = "rejected"
        await completePendingUIToolCall(output: output)
        Logger.info("✅ Applicant profile rejected - info included in tool response", category: .ai)
    }
    func submitProfileDraft(draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) async {
        // Close the profile intake UI via event
        await eventBus.publish(.applicantProfileIntakeCleared)
        // Store profile in StateCoordinator/ArtifactRepository (which will emit the event)
        let profileJSON = draft.toSafeJSON()
        await state.storeApplicantProfile(profileJSON)
        // Emit artifact record for traceability
        toolRouter.completeApplicantProfileDraft(draft, source: source)
        // Show the profile summary card in the tool pane
        toolRouter.profileHandler.showProfileSummary(profile: profileJSON)
        // Store in UI state to persist until timeline loads
        ui.lastApplicantProfileSummary = profileJSON
        // Mark objectives complete
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.contactSourceSelected.rawValue,
            status: "completed",
            source: "ui_profile_draft",
            notes: "Profile submitted via \(source == .contacts ? "contacts" : "manual")",
            details: ["source": source == .contacts ? "contacts" : "manual"]
        ))
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.contactDataCollected.rawValue,
            status: "completed",
            source: "ui_profile_draft",
            notes: "Profile data collected",
            details: nil
        ))
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.contactDataValidated.rawValue,
            status: "completed",
            source: "ui_profile_draft",
            notes: "Profile validated via intake UI",
            details: nil
        ))
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.applicantProfileComplete.rawValue,
            status: "completed",
            source: "ui_profile_draft",
            notes: "Applicant profile validated and saved",
            details: nil
        ))
        Logger.info("✅ applicant_profile_complete objective marked complete via draft submission", category: .ai)

        // Build comprehensive tool output that includes profile data
        // This eliminates the need for a separate user message, reducing LLM round trips
        // Tool response is visible to the LLM; omit binary photo data to avoid token waste.
        var llmSafeProfile = profileJSON
        if let image = llmSafeProfile["image"].string, !image.isEmpty {
            llmSafeProfile["image"].string = "[Image uploaded - binary data omitted]"
        }

        var wrappedData = JSON()
        wrappedData["applicant_profile"] = llmSafeProfile
        wrappedData["validation_status"].string = "validated_by_user"

        var output = JSON()
        output["message"].string = "Profile submitted via \(source == .contacts ? "contacts import" : "manual entry") and validated by user. Proceed to photo step."
        output["status"].string = "completed"
        output["profile_data"] = wrappedData

        // Complete pending UI tool call with full profile data (Codex paradigm)
        await completePendingUIToolCall(output: output)
        Logger.info("✅ Profile submitted with data included in tool response (source: \(source == .contacts ? "contacts" : "manual"))", category: .ai)
    }
    func submitProfileURL(_ urlString: String) async {
        // Process URL submission (creates artifact if needed)
        guard toolRouter.submitApplicantProfileURL(urlString) != nil else { return }
        // Send user message to LLM indicating URL submission
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Profile URL submitted: \(urlString). Processing for contact information extraction."
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Profile URL submitted and user message sent to LLM", category: .ai)
    }
    // MARK: - Section Toggle Handling
    func confirmSectionToggle(enabled: [String], customFields: [CustomFieldDefinition] = []) async {
        guard toolRouter.resolveSectionToggle(enabled: enabled) != nil else { return }

        // Store enabled sections in artifact repository
        await state.restoreEnabledSections(Set(enabled))

        // Store custom field definitions (including empty to clear prior state)
        await state.storeCustomFieldDefinitions(customFields)
        Logger.info("📋 Stored \(customFields.count) custom field definitions", category: .ai)

        // Flag whether title set curation is required in Phase 4
        let hasJobTitles = customFields.contains { $0.key.lowercased() == "custom.jobtitles" }
        ui.shouldGenerateTitleSets = hasJobTitles
        Logger.info("🏷️ Title set curation \(hasJobTitles ? "enabled" : "disabled") via custom.jobTitles", category: .ai)

        // Mark enabled_sections objective as complete
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.enabledSections.rawValue,
            status: "completed",
            source: "ui_section_toggle_confirmed",
            notes: "Section toggle confirmed by user",
            details: ["sections": enabled.joined(separator: ", ")]
        ))

        // Execute phase transition directly - no need to ask LLM to call next_phase
        // This is more reliable than forced toolChoice and eliminates a round trip
        await forcePhaseTransition(reason: "Section configuration confirmed by user")

        // Build tool output informing LLM that phase has advanced
        var output = JSON()
        var message = "Section toggle confirmed. Enabled sections: \(enabled.joined(separator: ", "))"
        if !customFields.isEmpty {
            let customFieldsSummary = customFields.map { "\($0.key): \($0.description)" }.joined(separator: "; ")
            message += ". Custom fields: \(customFieldsSummary)"
        }
        message += ". Phase has been advanced to Phase 3 (Evidence Collection)."
        output["message"].string = message
        output["status"].string = "phase_advanced"

        // Complete pending UI tool call - LLM receives confirmation that phase changed
        await completePendingUIToolCall(output: output)

        Logger.info("✅ Section toggle confirmed - phase advanced directly to Phase 3", category: .ai)
    }
    func rejectSectionToggle(reason: String) async {
        guard toolRouter.rejectSectionToggle(reason: reason) != nil else { return }

        // Complete pending UI tool call with rejection (Codex paradigm)
        // No separate user message needed - tool response contains the rejection info
        var output = JSON()
        output["message"].string = "Section toggle rejected: \(reason)"
        output["status"].string = "rejected"
        await completePendingUIToolCall(output: output)
        Logger.info("✅ Section toggle rejected - info included in tool response", category: .ai)
    }
    // MARK: - Chat & Control
    func sendChatMessage(_ text: String) async {
        // Clear any waiting state that blocks tools - user sending a message signals readiness to proceed
        // This handles stuck states where uploads completed but waiting state wasn't cleared
        let previousWaitingState = await sessionUIState.getWaitingState()
        if previousWaitingState != nil {
            await sessionUIState.setWaitingState(nil)
            Logger.info("💬 Chatbox message cleared waiting state: \(previousWaitingState?.rawValue ?? "none")", category: .ai)
        }

        // Auto-complete any pending UI tool call - user sending a message means they're ready to proceed
        // This prevents conversation sync errors where a tool call is left hanging
        if let pendingTool = await state.getPendingUIToolCall() {
            Logger.info("💬 Chatbox message auto-completing pending UI tool: \(pendingTool.toolName) (callId: \(pendingTool.callId.prefix(8)))", category: .ai)

            // Dismiss any visible UI associated with the pending tool
            await dismissPendingUIPrompts()

            var autoCompleteOutput = JSON()
            autoCompleteOutput["status"].string = "completed"
            autoCompleteOutput["message"].string = "User proceeded via chatbox message"
            await completePendingUIToolCall(output: autoCompleteOutput)
        }

        // NOTE: Document collection mode is NOT cleared by chatbox messages.
        // It should only be dismissed by "Done with Uploads" button or phase transitions.

        // Add the message to chat transcript IMMEDIATELY so user sees it in the UI
        let messageId = await state.appendUserMessage(text, isSystemGenerated: false)
        // Emit event so coordinator can sync its messages array to UI
        await eventBus.publish(.chatboxUserMessageAdded(messageId: messageId.uuidString))
        // Wrap user chatbox messages in <chatbox> tags for LLM context
        var payload = JSON()
        payload["text"].string = "<chatbox>\(text)</chatbox>"
        // Emit processing state change for UI feedback
        await eventBus.publish(.processingStateChanged(true, statusMessage: "Processing your message..."))
        // Emit event for LLMMessenger to handle, including messageId and original text for error recovery
        await eventBus.publish(.llmSendUserMessage(
            payload: payload,
            isSystemGenerated: false,
            chatboxMessageId: messageId.uuidString,
            originalText: text
        ))
    }
    func requestCancelLLM() async {
        await eventBus.publish(.llmCancelRequested)
    }

    // MARK: - Direct File Upload (Persistent Drop Zone)
    /// Handles file uploads from the persistent drop zone (no pending request required)
    func uploadFilesDirectly(_ fileURLs: [URL]) async {
        guard !fileURLs.isEmpty else { return }

        let uploadStorage = OnboardingUploadStorage()
        var processed: [OnboardingProcessedUpload] = []

        do {
            processed = try fileURLs.map { try uploadStorage.processFile(at: $0) }

            // Build upload metadata for generic artifact upload
            var metadata = JSON()
            metadata["title"].string = "User uploaded document"
            metadata["instructions"].string = "Document uploaded via drag-and-drop"

            // Convert to ProcessedUploadInfo for the event
            // Use item.filename (original name) not storageURL.lastPathComponent (UUID)
            let uploadInfos = processed.map { item in
                ProcessedUploadInfo(
                    storageURL: item.storageURL,
                    contentType: item.contentType,
                    filename: item.filename
                )
            }

            // Emit uploadCompleted event - DocumentArtifactHandler will process
            // DocumentArtifactMessenger will batch artifacts and send a consolidated message to LLM
            await eventBus.publish(.uploadCompleted(
                files: uploadInfos,
                requestKind: "artifact",
                callId: nil,
                metadata: metadata
            ))

            // Note: We no longer send an immediate "I've uploaded..." message here
            // DocumentArtifactMessenger handles batching and sends a consolidated message
            // with all extracted content once processing completes

            Logger.info("✅ Direct upload started: \(fileURLs.count) file(s)", category: .ai)
        } catch {
            Logger.error("❌ Direct upload failed: \(error.localizedDescription)", category: .ai)
            // Clean up any processed files on error
            for item in processed {
                uploadStorage.removeFile(at: item.storageURL)
            }
        }
    }

    // MARK: - Writing Sample Upload (Phase 3)
    /// Handles writing sample uploads with verbatim transcription for Phase 3
    func uploadWritingSamples(_ fileURLs: [URL]) async {
        guard !fileURLs.isEmpty else { return }

        let uploadStorage = OnboardingUploadStorage()
        var processed: [OnboardingProcessedUpload] = []

        do {
            processed = try fileURLs.map { try uploadStorage.processFile(at: $0) }

            // Build upload metadata for writing sample
            var metadata = JSON()
            metadata["title"].string = "Writing sample"
            metadata["instructions"].string = "Transcribe this writing sample verbatim"
            metadata["verbatim_transcription"].bool = true  // Flag for verbatim mode

            // Convert to ProcessedUploadInfo for the event
            // Use item.filename (original name) not storageURL.lastPathComponent (UUID)
            let uploadInfos = processed.map { item in
                ProcessedUploadInfo(
                    storageURL: item.storageURL,
                    contentType: item.contentType,
                    filename: item.filename
                )
            }

            // Emit uploadCompleted event with writing_sample type
            // DocumentArtifactHandler will process with verbatim transcription
            await eventBus.publish(.uploadCompleted(
                files: uploadInfos,
                requestKind: "writing_sample",
                callId: nil,
                metadata: metadata
            ))

            Logger.info("📝 Writing sample upload started: \(fileURLs.count) file(s)", category: .ai)
        } catch {
            Logger.error("❌ Writing sample upload failed: \(error.localizedDescription)", category: .ai)
            // Clean up any processed files on error
            for item in processed {
                uploadStorage.removeFile(at: item.storageURL)
            }
        }
    }

    // MARK: - Timeline Handling
    func applyUserTimelineUpdate(cards: [TimelineCard], meta: JSON?, diff: TimelineDiff) async {
        // Reconstruct the full JSON
        var timelineJSON = JSON()
        timelineJSON["experiences"] = JSON(cards.map { $0.json })
        if let meta = meta {
            timelineJSON["meta"] = meta
        }
        // Publish replacement event which will update state and persistence
        await eventBus.publish(.skeletonTimelineReplaced(timeline: timelineJSON, diff: diff, meta: meta))
        // Build card summary with IDs for LLM
        let cardSummary = buildTimelineCardSummarySync(cards: cards)
        // Notify LLM of the changes with current card state
        var userMessage = JSON()
        userMessage["role"].string = "user"
        var content = "I have updated the timeline. Changes:\n\(diff.summary)"
        if !cardSummary.isEmpty {
            content += "\n\nCurrent timeline cards (with IDs for programmatic editing):\n\(cardSummary)"
        }
        userMessage["content"].string = content
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ User timeline update applied and notified LLM (including card IDs)", category: .ai)
    }

    /// Build a summary of timeline cards with their IDs (synchronous version for use with TimelineCard array)
    private func buildTimelineCardSummarySync(cards: [TimelineCard]) -> String {
        guard !cards.isEmpty else { return "" }
        var lines: [String] = []
        for card in cards {
            let id = card.id
            let type = card.experienceType.rawValue
            let title = card.title
            let org = card.organization
            let start = card.start
            let end = card.end.isEmpty ? "present" : card.end
            lines.append("- [\(id)] [\(type)] \(title) @ \(org) (\(start) - \(end))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Codex Paradigm: Pending Tool Output Management

    /// Complete a pending UI tool call by sending the tool output.
    /// This implements the Codex CLI paradigm where UI tools defer their response until user action.
    ///
    /// - Parameters:
    ///   - output: The tool output JSON
    ///   - instruction: Optional instruction text to include after the tool_result.
    ///     Per Anthropic best practices, this text travels WITH the tool result
    ///     to provide immediate guidance for the next action.
    private func completePendingUIToolCall(output: JSON, instruction: String? = nil) async {
        guard let pending = await state.getPendingUIToolCall() else {
            Logger.debug("⚠️ No pending UI tool call to complete", category: .ai)
            return
        }

        // Build and emit the tool response
        var payload = JSON()
        payload["callId"].string = pending.callId
        payload["output"] = output
        if let instruction = instruction {
            payload["instruction"].string = instruction
        }
        await eventBus.publish(.llmToolResponseMessage(payload: payload))

        let instructionInfo = instruction != nil ? " + instruction" : ""
        Logger.info("📤 Pending tool output sent: \(pending.toolName) (callId: \(pending.callId.prefix(8)))\(instructionInfo)", category: .ai)

        // Clear the pending tool call
        await state.clearPendingUIToolCall()
    }

    /// Build a standard "UI presented, awaiting input" output for pending tools
    private func buildUICompletedOutput(message: String? = nil) -> JSON {
        var output = JSON()
        output["message"].string = message ?? "UI presented. Awaiting user input."
        output["status"].string = "completed"
        return output
    }

    /// Dismiss any visible UI prompts (choice, validation, etc.)
    /// Called when auto-completing a pending tool via chatbox message
    private func dismissPendingUIPrompts() async {
        // Clear choice prompt if visible
        if toolRouter.pendingChoicePrompt != nil {
            toolRouter.clearChoicePrompt()
            await eventBus.publish(.choicePromptCleared)
            Logger.info("💬 Dismissed choice prompt via chatbox message", category: .ai)
        }

        // Clear validation prompt if visible
        if toolRouter.pendingValidationPrompt != nil {
            toolRouter.clearValidationPrompt()
            await eventBus.publish(.validationPromptCleared)
            Logger.info("💬 Dismissed validation prompt via chatbox message", category: .ai)
        }

        // Clear pending upload requests if visible
        if !toolRouter.pendingUploadRequests.isEmpty {
            toolRouter.clearPendingUploadRequests()
            Logger.info("💬 Dismissed upload request(s) via chatbox message", category: .ai)
        }

        // Clear section toggle request if visible
        if toolRouter.pendingSectionToggleRequest != nil {
            toolRouter.clearSectionToggle()
            await eventBus.publish(.sectionToggleCleared)
            Logger.info("💬 Dismissed section toggle via chatbox message", category: .ai)
        }
    }
}
