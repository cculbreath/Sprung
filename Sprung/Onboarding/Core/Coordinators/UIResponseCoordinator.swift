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
    private let continuationManager: UIToolContinuationManager
    private let userActionQueue: UserActionQueue
    private let drainGate: DrainGate
    private let queueDrainCoordinator: QueueDrainCoordinator

    init(
        eventBus: EventCoordinator,
        toolRouter: ToolHandler,
        state: StateCoordinator,
        ui: OnboardingUIState,
        sessionUIState: SessionUIState,
        continuationManager: UIToolContinuationManager,
        userActionQueue: UserActionQueue,
        drainGate: DrainGate,
        queueDrainCoordinator: QueueDrainCoordinator
    ) {
        self.eventBus = eventBus
        self.toolRouter = toolRouter
        self.state = state
        self.ui = ui
        self.sessionUIState = sessionUIState
        self.continuationManager = continuationManager
        self.userActionQueue = userActionQueue
        self.drainGate = drainGate
        self.queueDrainCoordinator = queueDrainCoordinator
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
        await eventBus.publish(.toolpane(.choicePromptCleared))

        // Complete the UI tool continuation
        let result = buildCompletionResult(
            status: "completed",
            message: "User selected 'Other' and provided: \(otherText)",
            data: JSON(["otherResponse": otherText])
        )
        completeUITool(toolName: OnboardingToolName.getUserOption.rawValue, result: result)
        Logger.info("✅ Choice selection (Other) completed", category: .ai)
    }

    /// Cancel a choice selection - dismisses UI and completes tool with cancellation
    func cancelChoiceSelection() async {
        // Clear the choice prompt UI
        toolRouter.clearChoicePrompt()
        await eventBus.publish(.toolpane(.choicePromptCleared))

        // Complete the UI tool with cancellation
        let result = buildCompletionResult(
            status: "cancelled",
            message: "User cancelled the selection prompt"
        )
        completeUITool(toolName: OnboardingToolName.getUserOption.rawValue, result: result)
        Logger.info("✅ Choice selection cancelled", category: .ai)
    }

    private func submitChoiceSelectionInternal(selectionIds: [String], result: (payload: JSON, source: String?)) async {
        // Determine the tool name based on source
        let toolName: String
        if result.source == "skip_phase_approval" {
            toolName = OnboardingToolName.askUserSkipToNextPhase.rawValue
        } else {
            toolName = OnboardingToolName.getUserOption.rawValue
        }

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
        await eventBus.publish(.toolpane(.choicePromptCleared))

        // Build completion result
        let completionResult: UIToolCompletionResult
        if result.source == "skip_phase_approval" {
            let approved = selectionIds.contains("approve")
            completionResult = buildCompletionResult(
                status: approved ? "phase_advanced" : "rejected",
                message: approved
                    ? "User approved skip. Phase has been advanced. Begin new phase immediately."
                    : "User rejected skip request. Continue working on current phase objectives."
            )
        } else {
            completionResult = buildCompletionResult(
                status: "completed",
                message: "User selected option(s): \(selectionIds.joined(separator: ", "))",
                data: JSON(["selectedIds": selectionIds])
            )
        }

        completeUITool(toolName: toolName, result: completionResult)
        Logger.info("✅ Choice selection completed", category: .ai)
    }

    // MARK: - Forced Phase Transition

    /// Force an immediate phase transition without waiting for LLM to call next_phase.
    /// Used when user action should directly advance the phase (section toggle, skip approval, etc.)
    /// Direct transitions are more reliable and eliminate LLM round trips.
    private func forcePhaseTransition(reason: String = "User action triggered phase advance") async {
        let currentPhase = await state.phase
        guard let nextPhase = currentPhase.next() else {
            Logger.warning("⚠️ Cannot force phase transition: already at final phase", category: .ai)
            return
        }

        Logger.info("⚡ Forcing phase transition: \(currentPhase.rawValue) → \(nextPhase.rawValue)", category: .ai)

        // Emit phase transition request - StateCoordinator will handle the actual transition
        // This triggers: setPhase() → phaseTransitionApplied → handlePhaseTransition (sends intro prompt)
        await eventBus.publish(.phase(.transitionRequested(
            from: currentPhase.rawValue,
            to: nextPhase.rawValue,
            reason: reason
        )))
    }
    // MARK: - Upload Handling
    func completeUploadAndResume(id: UUID, fileURLs: [URL], coordinator: OnboardingInterviewCoordinator) async {
        guard await coordinator.completeUpload(id: id, fileURLs: fileURLs) != nil else { return }

        // Check if any uploaded files require async extraction (PDF, DOCX, HTML, etc.)
        let requiresAsyncExtraction = fileURLs.contains { url in
            let ext = url.pathExtension.lowercased()
            return ["pdf", "docx", "html", "htm"].contains(ext)
        }

        let filenames = fileURLs.map { $0.lastPathComponent }.joined(separator: ", ")
        let result: UIToolCompletionResult

        if requiresAsyncExtraction {
            // Complete the tool with extraction_in_progress status
            // DocumentArtifactMessenger will send the extracted content as a follow-up user message
            result = buildCompletionResult(
                status: "extraction_in_progress",
                message: "User uploaded \(fileURLs.count) file(s): \(filenames). Text extraction in progress - content will follow.",
                data: JSON(["filenames": filenames, "count": fileURLs.count, "async_extraction": true])
            )
            Logger.info("📄 Upload completed - async extraction in progress", category: .ai)
        } else {
            // For non-extractable files (images, text), complete immediately
            result = buildCompletionResult(
                status: "completed",
                message: "User uploaded \(fileURLs.count) file(s): \(filenames)",
                data: JSON(["filenames": filenames, "count": fileURLs.count])
            )
            Logger.info("✅ Upload completed (non-extractable files)", category: .ai)
        }

        completeUITool(toolName: OnboardingToolName.getUserUpload.rawValue, result: result)
    }
    func skipUploadAndResume(id: UUID, coordinator: OnboardingInterviewCoordinator) async {
        guard await coordinator.skipUpload(id: id) != nil else { return }

        // Complete the UI tool with skip status
        let result = buildCompletionResult(
            status: "completed",
            message: "User skipped the upload"
        )
        completeUITool(toolName: OnboardingToolName.getUserUpload.rawValue, result: result)
        Logger.info("✅ Upload skipped", category: .ai)
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

        // Build result message with next step guidance included
        var message = "Validation response: \(statusDescription)"
        if let notes = notes, !notes.isEmpty {
            message += ". Notes: \(notes)"
        }
        if statusDescription == "confirmed" {
            message += ". Next step: call configure_enabledSections to let the user choose which resume sections to include."
        }

        let result = buildCompletionResult(status: "completed", message: message)
        completeUITool(toolName: OnboardingToolName.submitForValidation.rawValue, result: result)
        Logger.info("✅ Validation response completed", category: .ai)
    }

    func clearValidationPromptAndNotifyLLM(message: String) async {
        // Clear the validation prompt
        toolRouter.clearValidationPrompt()
        await eventBus.publish(.toolpane(.validationPromptCleared))

        // Get current timeline state to include in the result
        let timelineInfo = await buildTimelineCardSummary()

        // Build the result with timeline info
        var resultData = JSON()
        resultData["timelineSummary"].string = timelineInfo.isEmpty ? "No timeline cards" : timelineInfo

        var resultMessage = message
        if !timelineInfo.isEmpty {
            resultMessage += "\n\nCurrent timeline cards (with IDs for programmatic editing):\n\(timelineInfo)"
        }

        let result = buildCompletionResult(
            status: "changes_submitted",
            message: resultMessage,
            data: resultData
        )
        completeUITool(toolName: OnboardingToolName.submitForValidation.rawValue, result: result)
        Logger.info("✅ Validation prompt cleared (including \(timelineInfo.isEmpty ? "no" : "current") card state)", category: .ai)
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
        await eventBus.publish(.state(.timelineEditorActiveChanged(false)))

        // Clear the validation/editor prompt (legacy, may not be set)
        toolRouter.clearValidationPrompt()
        await eventBus.publish(.toolpane(.validationPromptCleared))

        // Mark timeline enrichment objective as completed
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.timelineEnriched.rawValue,
            status: "completed",
            source: "user_done_with_timeline",
            notes: "User clicked Done with Timeline",
            details: nil
        )))

        // UNGATE: Allow submit_for_validation now that user clicked Done
        await sessionUIState.includeTool(OnboardingToolName.submitForValidation.rawValue)
        Logger.info("🔓 Ungated submit_for_validation after user clicked Done with Timeline", category: .ai)

        // Get current timeline info
        let timelineInfo = await buildTimelineCardSummary()

        // Send user message asking LLM to call submit_for_validation
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

        await eventBus.publish(.llm(.sendUserMessage(
            payload: payload,
            isSystemGenerated: true
        )))
        Logger.info("✅ Timeline editing complete - requesting submit_for_validation", category: .ai)
    }

    /// Called when user clicks "Done with Section Cards" in the timeline tab.
    /// Marks section cards complete and advances to Phase 3.
    func completeSectionCardsAndAdvancePhase() async {
        // Deactivate the section cards editor mode
        ui.isSectionCardsEditorActive = false

        // Mark section cards objective as completed
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.sectionCardsComplete.rawValue,
            status: "completed",
            source: "user_done_with_section_cards",
            notes: "User clicked Done with Section Cards",
            details: nil
        )))

        // Force phase transition to Phase 3
        await forcePhaseTransition(reason: "Section cards collection completed by user")

        Logger.info("✅ Section cards complete - advanced to Phase 3", category: .ai)
    }

    // MARK: - Applicant Profile Handling
    func confirmApplicantProfile(draft: ApplicantProfileDraft) async {
        guard let resolution = toolRouter.resolveApplicantProfile(with: draft) else { return }

        // Extract the actual profile data from the resolution
        let profileData = resolution["data"]
        let status = resolution["status"].stringValue
        // Store profile in StateCoordinator/ArtifactRepository (persists the data)
        await state.storeApplicantProfile(profileData)
        // Mark objective chain complete to trigger photo follow-up workflow
        // The objectives must be completed in dependency order
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.contactSourceSelected.rawValue,
            status: "completed",
            source: "ui_profile_confirmed",
            notes: "Profile confirmed via intake card",
            details: ["method": "intake_card"]
        )))
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.contactDataCollected.rawValue,
            status: "completed",
            source: "ui_profile_confirmed",
            notes: "Profile confirmed via intake card",
            details: ["method": "intake_card"]
        )))
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.contactDataValidated.rawValue,
            status: "completed",
            source: "ui_profile_confirmed",
            notes: "Profile confirmed via intake card",
            details: ["method": "intake_card"]
        )))
        // Mark the main applicantProfile_complete objective as complete
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.applicantProfileComplete.rawValue,
            status: "completed",
            source: "ui_profile_confirmed",
            notes: "Applicant profile validated and saved",
            details: ["method": "intake_card"]
        )))
        Logger.info("✅ applicantProfile_complete objective marked complete", category: .ai)

        // Build result with profile data for the LLM
        var resultData = JSON()
        resultData["profile"] = profileData
        resultData["validationStatus"].string = status

        // Format a human-readable summary
        var summaryParts: [String] = ["Profile confirmed:"]
        if let name = profileData["name"].string {
            summaryParts.append("- Name: \(name)")
        }
        if let email = profileData["email"].string {
            summaryParts.append("- Email: \(email)")
        }
        if let phone = profileData["phone"].string {
            summaryParts.append("- Phone: \(phone)")
        }
        if let location = profileData["location"].string {
            summaryParts.append("- Location: \(location)")
        }

        let result = buildCompletionResult(
            status: "completed",
            message: summaryParts.joined(separator: "\n"),
            data: resultData
        )
        completeUITool(toolName: OnboardingToolName.validateApplicantProfile.rawValue, result: result)
        Logger.info("✅ Applicant profile confirmed (\(status))", category: .ai)
    }
    func rejectApplicantProfile(reason: String) async {
        guard toolRouter.rejectApplicantProfile(reason: reason) != nil else { return }

        // Complete the UI tool with rejection
        let result = buildCompletionResult(
            status: "rejected",
            message: "Applicant profile rejected. Reason: \(reason)"
        )
        completeUITool(toolName: OnboardingToolName.validateApplicantProfile.rawValue, result: result)
        Logger.info("✅ Applicant profile rejected", category: .ai)
    }
    func submitProfileDraft(draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) async {
        // Close the profile intake UI via event
        await eventBus.publish(.toolpane(.applicantProfileIntakeCleared))
        // Store profile in StateCoordinator/ArtifactRepository (which will emit the event)
        let profileJSON = draft.toSafeJSON()
        await state.storeApplicantProfile(profileJSON)
        // Emit artifact record for traceability
        toolRouter.completeApplicantProfileDraft(draft, source: source)
        // Show the profile summary card in the tool pane
        toolRouter.profileHandler.showProfileSummary(profile: profileJSON)
        // Trigger webfetch for any URLs in the profile (website, LinkedIn, etc.)
        await toolRouter.profileHandler.triggerProfileURLFetch(draft: draft)
        // Store in UI state to persist until timeline loads
        ui.lastApplicantProfileSummary = profileJSON
        // Mark objectives complete
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.contactSourceSelected.rawValue,
            status: "completed",
            source: "ui_profile_draft",
            notes: "Profile submitted via \(source == .contacts ? "contacts" : "manual")",
            details: ["source": source == .contacts ? "contacts" : "manual"]
        )))
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.contactDataCollected.rawValue,
            status: "completed",
            source: "ui_profile_draft",
            notes: "Profile data collected",
            details: nil
        )))
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.contactDataValidated.rawValue,
            status: "completed",
            source: "ui_profile_draft",
            notes: "Profile validated via intake UI",
            details: nil
        )))
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.applicantProfileComplete.rawValue,
            status: "completed",
            source: "ui_profile_draft",
            notes: "Applicant profile validated and saved",
            details: nil
        )))
        Logger.info("✅ applicantProfile_complete objective marked complete via draft submission", category: .ai)

        // Build result with profile data for the LLM
        // Omit binary photo data to avoid token waste
        var llmSafeProfile = profileJSON
        if let image = llmSafeProfile["image"].string, !image.isEmpty {
            llmSafeProfile["image"].string = "[Image uploaded - binary data omitted]"
        }

        var resultData = JSON()
        resultData["applicantProfile"] = llmSafeProfile
        resultData["validationStatus"].string = "validated_by_user"

        // Include URLs available for fetching (website, social profiles)
        // This replaces the coordinator message that would otherwise be queued
        var urlsToFetch: [(label: String, url: String)] = []
        if !draft.website.isEmpty {
            urlsToFetch.append(("personal website", draft.website))
        }
        for socialProfile in draft.socialProfiles where !socialProfile.url.isEmpty {
            let network = socialProfile.network.isEmpty ? "profile" : socialProfile.network
            urlsToFetch.append((network, socialProfile.url))
        }
        if !urlsToFetch.isEmpty {
            var urlsJSON = JSON([])
            for (label, url) in urlsToFetch {
                urlsJSON.arrayObject?.append(["label": label, "url": url])
            }
            resultData["urlsAvailableForFetch"] = urlsJSON
            resultData["urlFetchSuggestion"].string = "Consider using web_fetch to learn more about the user from their \(urlsToFetch.map { $0.0 }.joined(separator: ", ")). This can provide valuable context for the interview."
        }

        // Build explicit next steps guidance since coordinator messages are now queued
        var nextSteps = "NEXT: Call get_user_upload with uploadType='photo' and target_key='basics.image' to request a profile photo."
        if !urlsToFetch.isEmpty {
            nextSteps += " Also consider fetching the user's \(urlsToFetch.map { $0.0 }.joined(separator: ", ")) to learn more about their background."
        }
        resultData["nextSteps"].string = nextSteps

        let result = buildCompletionResult(
            status: "completed",
            message: "Profile validated. \(nextSteps)",
            data: resultData
        )
        completeUITool(toolName: OnboardingToolName.getApplicantProfile.rawValue, result: result)
        Logger.info("✅ Profile submitted (source: \(source == .contacts ? "contacts" : "manual"))", category: .ai)
    }
    func submitProfileURL(_ urlString: String) async {
        // Process URL submission (creates artifact if needed)
        guard toolRouter.submitApplicantProfileURL(urlString) != nil else { return }
        // Send user message to LLM indicating URL submission
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Profile URL submitted: \(urlString). Processing for contact information extraction."
        await eventBus.publish(.llm(.enqueueUserMessage(payload: userMessage, isSystemGenerated: true)))
        Logger.info("✅ Profile URL submitted and user message sent to LLM", category: .ai)
    }
    // MARK: - Section Toggle Handling
    func confirmSectionToggle(config: SectionConfig) async {
        let enabled = Array(config.enabledSections)
        guard toolRouter.resolveSectionToggle(enabled: enabled) != nil else { return }

        // Emit event to unblock the DrainGate (GateBlockEventHandler listens for this)
        await eventBus.publish(.toolpane(.sectionToggleCleared))

        // Store section configuration in artifact repository
        await state.storeSectionConfig(config)
        Logger.info("📋 Stored section config: \(config.enabledSections.count) sections, \(config.customFields.count) custom fields", category: .ai)

        // Flag whether title set curation is required in Phase 4
        let hasJobTitles = config.customFields.contains { $0.key.lowercased() == "custom.jobtitles" }
        ui.shouldGenerateTitleSets = hasJobTitles
        Logger.info("🏷️ Title set curation \(hasJobTitles ? "enabled" : "disabled") via custom.jobTitles", category: .ai)

        // Mark enabledSections objective as complete
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.enabledSections.rawValue,
            status: "completed",
            source: "ui_section_toggle_confirmed",
            notes: "Section toggle confirmed by user",
            details: ["sections": enabled.joined(separator: ", ")]
        )))

        // NOTE: Phase transition removed - Phase 3 should come after section cards approval,
        // not after section configuration. The LLM should proceed with timeline collection.

        // Build result informing LLM of confirmed sections
        var message = "Section toggle confirmed. Enabled sections: \(enabled.joined(separator: ", "))"
        if !config.customFields.isEmpty {
            let customFieldsSummary = config.customFields.map { "\($0.key): \($0.description)" }.joined(separator: "; ")
            message += ". Custom fields: \(customFieldsSummary)"
        }
        message += ". Proceed with timeline collection - offer resume upload or conversational input."

        var resultData = JSON()
        resultData["enabledSections"] = JSON(enabled)
        if !config.customFields.isEmpty {
            resultData["customFields"] = JSON(config.customFields.map { ["key": $0.key, "description": $0.description] })
        }

        let result = buildCompletionResult(status: "confirmed", message: message, data: resultData)
        completeUITool(toolName: OnboardingToolName.configureEnabledSections.rawValue, result: result)

        Logger.info("✅ Section toggle confirmed, proceeding with Phase 2 timeline collection", category: .ai)
    }
    func rejectSectionToggle(reason: String) async {
        guard toolRouter.rejectSectionToggle(reason: reason) != nil else { return }

        // Emit event to unblock the DrainGate (GateBlockEventHandler listens for this)
        await eventBus.publish(.toolpane(.sectionToggleCleared))

        // Complete UI tool with rejection
        let result = buildCompletionResult(
            status: "rejected",
            message: "Section toggle rejected: \(reason)"
        )
        completeUITool(toolName: OnboardingToolName.configureEnabledSections.rawValue, result: result)
        Logger.info("✅ Section toggle rejected", category: .ai)
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

        // Dismiss any visible UI prompts - user sending a chatbox message means they want to proceed differently
        await dismissPendingUIPrompts()

        // NOTE: Document collection mode is NOT cleared by chatbox messages.
        // It should only be dismissed by "Done with Uploads" button or phase transitions.

        // CRITICAL: User chatbox messages are highest priority - clear ALL stale blocks
        // This prevents messages from being stuck in queue due to orphaned blocking states.
        // UI prompts have already been dismissed above, so all blocks should be stale.
        // If glow is off (not streaming), any remaining blocks are definitionally stale.
        drainGate.clearAllBlocks()

        // Add the message to chat transcript IMMEDIATELY so user sees it in the UI
        guard let messageId = await state.appendUserMessage(text, isSystemGenerated: false) else {
            Logger.error("❌ Chatbox message unexpectedly queued - this should never happen", category: .ai)
            return
        }

        // Emit event so coordinator can sync its messages array to UI
        await eventBus.publish(.llm(.chatboxUserMessageAdded(messageId: messageId.uuidString)))

        // Queue the message for sending at a safe boundary
        // This prevents race conditions with ongoing tool execution
        userActionQueue.enqueue(.chatboxMessage(text: text, id: messageId), priority: .normal)

        // Track this message as queued for UI display
        ui.queuedMessageIds.insert(messageId)

        // Update UI queue count for reactive display
        ui.queuedMessageCount = userActionQueue.pendingChatMessageIds().count

        // Attempt to drain the queue (will check gate before processing)
        await queueDrainCoordinator.checkAndDrain()
    }
    func requestCancelLLM() async {
        await eventBus.publish(.llm(.cancelRequested))
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
            await eventBus.publish(.artifact(.uploadCompleted(
                files: uploadInfos,
                requestKind: "artifact",
                callId: nil,
                metadata: metadata
            )))

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

    // MARK: - Writing Sample Upload
    /// Handles writing sample uploads with verbatim transcription
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
            metadata["verbatimTranscription"].bool = true  // Flag for verbatim mode

            // Convert to ProcessedUploadInfo for the event
            // Use item.filename (original name) not storageURL.lastPathComponent (UUID)
            let uploadInfos = processed.map { item in
                ProcessedUploadInfo(
                    storageURL: item.storageURL,
                    contentType: item.contentType,
                    filename: item.filename
                )
            }

            // Emit uploadCompleted event with writingSample type
            // DocumentArtifactHandler will process with verbatim transcription
            await eventBus.publish(.artifact(.uploadCompleted(
                files: uploadInfos,
                requestKind: "writingSample",
                callId: nil,
                metadata: metadata
            )))

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
        await eventBus.publish(.timeline(.skeletonReplaced(timeline: timelineJSON, diff: diff, meta: meta)))
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
        await eventBus.publish(.llm(.enqueueUserMessage(payload: userMessage, isSystemGenerated: true)))
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

    // MARK: - UI Tool Continuation Completion

    /// Complete a pending UI tool by resuming its continuation with the result.
    /// The tool will then return this result as its tool response (single API turn).
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool that presented the UI
    ///   - result: The result data from the user action
    private func completeUITool(toolName: String, result: UIToolCompletionResult) {
        let completed = continuationManager.complete(toolName: toolName, result: result)
        if completed {
            Logger.info("✅ UI tool continuation completed: \(toolName)", category: .ai)
        } else {
            // No pending continuation - tool may have timed out or been interrupted
            Logger.warning("⚠️ No pending continuation for \(toolName) - may have been interrupted", category: .ai)
        }
    }

    /// Build a completion result for UI action
    private func buildCompletionResult(status: String, message: String, data: JSON? = nil) -> UIToolCompletionResult {
        UIToolCompletionResult(status: status, message: message, data: data)
    }

    /// Dismiss any visible UI prompts (choice, validation, etc.)
    /// Called when auto-completing a pending tool via chatbox message
    private func dismissPendingUIPrompts() async {
        // Clear choice prompt if visible - complete tool with cancellation
        if toolRouter.pendingChoicePrompt != nil {
            toolRouter.clearChoicePrompt()
            await eventBus.publish(.toolpane(.choicePromptCleared))

            // Complete the UI tool with cancellation so tool result is filled
            let result = buildCompletionResult(
                status: "dismissed",
                message: "User sent a chatbox message instead of making a selection"
            )
            completeUITool(toolName: OnboardingToolName.getUserOption.rawValue, result: result)
            Logger.info("💬 Dismissed choice prompt via chatbox message (tool cancelled)", category: .ai)
        }

        // Clear validation prompt if visible - complete tool with cancellation
        if toolRouter.pendingValidationPrompt != nil {
            toolRouter.clearValidationPrompt()
            await eventBus.publish(.toolpane(.validationPromptCleared))

            // Complete the UI tool with cancellation
            let result = buildCompletionResult(
                status: "dismissed",
                message: "User sent a chatbox message instead of validating"
            )
            completeUITool(toolName: OnboardingToolName.submitForValidation.rawValue, result: result)
            Logger.info("💬 Dismissed validation prompt via chatbox message (tool cancelled)", category: .ai)
        }

        // Clear pending upload requests if visible - complete tools with cancellation
        if !toolRouter.pendingUploadRequests.isEmpty {
            // Complete each pending upload tool
            for request in toolRouter.pendingUploadRequests {
                let result = buildCompletionResult(
                    status: "dismissed",
                    message: "User sent a chatbox message instead of uploading"
                )
                completeUITool(toolName: OnboardingToolName.getUserUpload.rawValue, result: result)
                // Also emit the cancellation event for the specific request
                await eventBus.publish(.toolpane(.uploadRequestCancelled(id: request.id)))
            }
            toolRouter.clearPendingUploadRequests()
            Logger.info("💬 Dismissed upload request(s) via chatbox message (tool(s) cancelled)", category: .ai)
        }

        // Clear section toggle request if visible - complete tool with cancellation
        if toolRouter.pendingSectionToggleRequest != nil {
            toolRouter.clearSectionToggle()
            await eventBus.publish(.toolpane(.sectionToggleCleared))

            // Complete the UI tool with cancellation
            let result = buildCompletionResult(
                status: "dismissed",
                message: "User sent a chatbox message instead of configuring sections"
            )
            completeUITool(toolName: OnboardingToolName.configureEnabledSections.rawValue, result: result)
            Logger.info("💬 Dismissed section toggle via chatbox message (tool cancelled)", category: .ai)
        }
    }
}
