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

        // Handle special skip phase approval
        if result.source == "skip_phase_approval" {
            let approved = selectionIds.contains("approve")
            await state.setUserApprovedKCSkip(approved)
            Logger.info("📋 Skip phase approval: \(approved ? "approved" : "rejected")", category: .ai)
        }

        // Clear the choice prompt and waiting state
        await eventBus.publish(.choicePromptCleared)

        // Complete pending UI tool call (Codex paradigm)
        // No separate user message needed - tool response contains the selection info
        var output = JSON()
        // For skip phase approval, provide clear feedback on user decision
        if result.source == "skip_phase_approval" {
            let approved = selectionIds.contains("approve")
            output["status"].string = approved ? "approved" : "rejected"
            output["message"].string = approved
                ? "User approved skipping to next phase. You may now call next_phase."
                : "User rejected skip request. Continue working on current phase objectives."
        } else {
            output["message"].string = "User selected option(s): \(selectionIds.joined(separator: ", "))"
            output["status"].string = "completed"
        }
        await completePendingUIToolCall(output: output)
        Logger.info("✅ Choice selection - info included in tool response", category: .ai)
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
    func completeUploadAndResume(id: UUID, link: URL, coordinator: OnboardingInterviewCoordinator) async {
        guard await coordinator.toolRouter.completeUpload(id: id, link: link) != nil else { return }

        // Complete pending UI tool call with all info in tool response
        // No separate user message needed - tool response contains the completion info
        var output = JSON()
        output["message"].string = "User provided URL: \(link.absoluteString)"
        output["status"].string = "completed"
        await completePendingUIToolCall(output: output)
        Logger.info("✅ Upload from URL completed - info included in tool response", category: .ai)
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

        let isConfirmed = ["confirmed", "confirmed_with_changes", "approved", "modified"].contains(status.lowercased())

        // Check if this is KC auto-validation (no tool call to complete)
        let isAutoValidation = await sessionUIState.isAutoValidation

        if isAutoValidation {
            // KC Auto-Validation: Send developer message instead of tool response
            await handleKCAutoValidationResponse(
                isConfirmed: isConfirmed,
                notes: notes,
                coordinator: coordinator
            )
            return
        }

        // Standard tool-initiated validation: complete the pending tool call
        var message = "Validation response: \(statusDescription)"
        if let notes = notes, !notes.isEmpty {
            message += ". Notes: \(notes)"
        }

        var output = JSON()
        output["message"].string = message
        output["status"].string = "completed"
        await completePendingUIToolCall(output: output)

        // Check for pending knowledge card that needs auto-persist
        if isConfirmed && coordinator.hasPendingKnowledgeCard() {
            // Emit event for auto-persist - handler will respond with knowledgeCardAutoPersisted
            await eventBus.publish(.knowledgeCardAutoPersistRequested)
            Logger.info("📤 Emitted knowledgeCardAutoPersistRequested event", category: .ai)
            return
        }

        Logger.info("✅ Validation response - info included in tool response", category: .ai)
    }

    /// Handle KC auto-validation response (from agent completion, not tool call)
    /// Sends developer messages to LLM and triggers next card presentation
    private func handleKCAutoValidationResponse(
        isConfirmed: Bool,
        notes: String?,
        coordinator: OnboardingInterviewCoordinator
    ) async {
        if isConfirmed && coordinator.hasPendingKnowledgeCard() {
            // Emit auto-persist event - handler will:
            // 1. Persist the card
            // 2. Send developer message to LLM
            // 3. Present next card from queue
            await eventBus.publish(.kcAutoValidationApproved)
            Logger.info("✅ KC auto-validation approved - emitted kcAutoValidationApproved", category: .ai)
        } else {
            // Rejected - emit rejection event with reason
            let reason = notes ?? "No reason provided"
            await eventBus.publish(.kcAutoValidationRejected(reason: reason))
            Logger.info("❌ KC auto-validation rejected: \(reason)", category: .ai)
        }
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
    /// Clears the editor and forces the LLM to call submit_for_validation.
    func completeTimelineEditingAndRequestValidation() async {
        // Clear the validation/editor prompt
        toolRouter.clearValidationPrompt()
        await eventBus.publish(.validationPromptCleared)

        // Mark timeline_editor objective as completed - this gates submit_for_validation
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.skeletonTimelineTimelineEditor.rawValue,
            status: "completed",
            source: "user_done_with_timeline",
            notes: "User clicked Done with Timeline",
            details: nil
        ))

        // Get current timeline info
        let timelineInfo = await buildTimelineCardSummary()

        // Send developer message forcing submit_for_validation tool
        var payload = JSON()
        payload["title"].string = """
            User has completed timeline editing and clicked "Done with Timeline". \
            IMMEDIATELY call submit_for_validation with validation_type="skeleton_timeline" \
            to present the final approval prompt. The user is ready to confirm their timeline.
            """
        var details = JSON()
        details["action"].string = "call_submit_for_validation"
        details["validation_type"].string = "skeleton_timeline"
        details["user_action"].string = "done_with_timeline"
        if !timelineInfo.isEmpty {
            details["current_cards"].string = timelineInfo
        }
        payload["details"] = details
        payload["toolChoice"].string = OnboardingToolName.submitForValidation.rawValue

        await eventBus.publish(.llmSendDeveloperMessage(payload: payload))
        Logger.info("✅ Timeline editing complete - forcing submit_for_validation", category: .ai)
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
        // Mark the main applicant_profile objective as complete
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.applicantProfile.rawValue,
            status: "completed",
            source: "ui_profile_confirmed",
            notes: "Applicant profile validated and saved",
            details: ["method": "intake_card"]
        ))
        Logger.info("✅ applicant_profile objective marked complete", category: .ai)
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
            id: OnboardingObjectiveId.applicantProfile.rawValue,
            status: "completed",
            source: "ui_profile_draft",
            notes: "Applicant profile validated and saved",
            details: nil
        ))
        Logger.info("✅ applicant_profile objective marked complete via draft submission", category: .ai)

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
    func confirmSectionToggle(enabled: [String]) async {
        guard toolRouter.resolveSectionToggle(enabled: enabled) != nil else { return }

        // Complete pending UI tool call (Codex paradigm)
        // No separate user message needed - tool response contains the completion info
        var output = JSON()
        output["message"].string = "Section toggle confirmed. Enabled sections: \(enabled.joined(separator: ", "))"
        output["status"].string = "completed"
        await completePendingUIToolCall(output: output)

        // Mark enabled_sections objective as complete
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: "enabled_sections",
            status: "completed",
            source: "ui_section_toggle_confirmed",
            notes: "Section toggle confirmed by user",
            details: ["sections": enabled.joined(separator: ", ")]
        ))
        Logger.info("✅ Section toggle confirmed - info included in tool response", category: .ai)
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
    // MARK: - Model Availability
    func notifyInvalidModel(id: String) {
        // This method is called by OnboardingInterviewCoordinator when an invalid model is reported
        // We don't need to do anything here as the coordinator updates the UI state directly
        // via ui.modelAvailabilityMessage = ...
        // But if we wanted to send a message to the LLM or log it specifically here, we could.
        Logger.warning("⚠️ UIResponseCoordinator notified of invalid model: \(id)", category: .ai)
    }
    // MARK: - Chat & Control
    func sendChatMessage(_ text: String) async {
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
    func uploadFilesDirectly(_ fileURLs: [URL], extractionMethod: LargePDFExtractionMethod? = nil) async {
        guard !fileURLs.isEmpty else { return }

        let uploadStorage = OnboardingUploadStorage()
        var processed: [OnboardingProcessedUpload] = []

        do {
            processed = try fileURLs.map { try uploadStorage.processFile(at: $0) }

            // Build upload metadata for generic artifact upload
            var metadata = JSON()
            metadata["title"].string = "User uploaded document"
            metadata["instructions"].string = "Document uploaded via drag-and-drop"

            // Include extraction method preference for large PDFs
            if let method = extractionMethod {
                metadata["extraction_method"].string = method.rawValue
            }

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

            Logger.info("✅ Direct upload started: \(fileURLs.count) file(s), extractionMethod: \(extractionMethod?.rawValue ?? "default")", category: .ai)
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
    /// Note: Queued developer messages are automatically flushed when the subsequent user message is enqueued.
    private func completePendingUIToolCall(output: JSON) async {
        guard let pending = await state.getPendingUIToolCall() else {
            Logger.debug("⚠️ No pending UI tool call to complete", category: .ai)
            return
        }

        // Build and emit the tool response
        var payload = JSON()
        payload["callId"].string = pending.callId
        payload["output"] = output
        await eventBus.publish(.llmToolResponseMessage(payload: payload))
        Logger.info("📤 Pending tool output sent: \(pending.toolName) (callId: \(pending.callId.prefix(8)))", category: .ai)

        // Clear the pending tool call
        await state.clearPendingUIToolCall()
        // Note: Queued developer messages will be flushed by StateCoordinator
        // when the subsequent user message (llmEnqueueUserMessage) is processed
    }

    /// Build a standard "UI presented, awaiting input" output for pending tools
    private func buildUICompletedOutput(message: String? = nil) -> JSON {
        var output = JSON()
        output["message"].string = message ?? "UI presented. Awaiting user input."
        output["status"].string = "completed"
        return output
    }
}
