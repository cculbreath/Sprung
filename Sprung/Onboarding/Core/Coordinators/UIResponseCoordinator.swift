import Foundation
import SwiftyJSON
/// Coordinator responsible for handling UI-driven responses and generating corresponding LLM messages.
/// This extracts the "User Action -> LLM Message" logic from the main coordinator.
@MainActor
final class UIResponseCoordinator {
    private let eventBus: EventCoordinator
    private let toolRouter: ToolHandler
    private let state: StateCoordinator
    init(
        eventBus: EventCoordinator,
        toolRouter: ToolHandler,
        state: StateCoordinator
    ) {
        self.eventBus = eventBus
        self.toolRouter = toolRouter
        self.state = state
    }
    // MARK: - Choice Selection
    func submitChoiceSelection(_ selectionIds: [String]) async {
        guard toolRouter.resolveChoice(selectionIds: selectionIds) != nil else { return }
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Selected option(s): \(selectionIds.joined(separator: ", "))"
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Choice selection submitted and user message sent to LLM", category: .ai)
    }
    // MARK: - Upload Handling
    func completeUploadAndResume(id: UUID, fileURLs: [URL], coordinator: OnboardingInterviewCoordinator) async {
        guard await coordinator.completeUpload(id: id, fileURLs: fileURLs) != nil else { return }
        // Check if any uploaded files require async extraction (PDF, DOCX, HTML, etc.)
        // For these, skip sending immediate "upload successful" message - the DocumentArtifactMessenger
        // will send a more informative message with the extracted content once processing completes
        // Plain text formats (txt, md, rtf) are packaged immediately and don't need to wait
        // HTML requires extraction to remove scripts, CSS, and other noise
        let requiresAsyncExtraction = fileURLs.contains { url in
            let ext = url.pathExtension.lowercased()
            return ["pdf", "doc", "docx", "html", "htm"].contains(ext)
        }
        if requiresAsyncExtraction {
            Logger.info("📄 Upload completed - async document extraction in progress, skipping immediate message", category: .ai)
            return
        }
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Uploaded \(fileURLs.count) file(s) successfully."
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Upload completed and user message sent to LLM", category: .ai)
    }
    func completeUploadAndResume(id: UUID, link: URL, coordinator: OnboardingInterviewCoordinator) async {
        guard await coordinator.toolRouter.completeUpload(id: id, link: link) != nil else { return }
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Uploaded file from URL: \(link.absoluteString)"
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Upload from URL completed and user message sent to LLM", category: .ai)
    }
    func skipUploadAndResume(id: UUID, coordinator: OnboardingInterviewCoordinator) async {
        guard await coordinator.skipUpload(id: id) != nil else { return }
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Skipped upload."
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Upload skipped and user message sent to LLM", category: .ai)
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
        var userMessage = JSON()
        userMessage["role"].string = "user"
        // Map status values from UI buttons to LLM messages
        let statusDescription: String
        switch status.lowercased() {
        case "confirmed", "confirmed_with_changes", "approved", "modified":
            statusDescription = "confirmed"
        case "rejected":
            statusDescription = "rejected"
        default:
            statusDescription = status.lowercased()
        }
        userMessage["content"].string = "Validation response: \(statusDescription)"
        if let notes = notes, !notes.isEmpty {
            userMessage["content"].string = userMessage["content"].stringValue + ". Notes: \(notes)"
        }
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Validation response submitted and user message sent to LLM", category: .ai)
    }
    func clearValidationPromptAndNotifyLLM(message: String) async {
        // Clear the validation prompt
        toolRouter.clearValidationPrompt()
        await eventBus.publish(.validationPromptCleared)
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
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: "contact_source_selected",
            status: "completed",
            source: "ui_profile_confirmed",
            notes: "Profile confirmed via intake card",
            details: ["method": "intake_card"]
        ))
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: "contact_data_collected",
            status: "completed",
            source: "ui_profile_confirmed",
            notes: "Profile confirmed via intake card",
            details: ["method": "intake_card"]
        ))
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: "contact_data_validated",
            status: "completed",
            source: "ui_profile_confirmed",
            notes: "Profile confirmed via intake card",
            details: ["method": "intake_card"]
        ))
        // Mark the main applicant_profile objective as complete
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: "applicant_profile",
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
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Applicant profile rejected. Reason: \(reason)"
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Applicant profile rejected and user message sent to LLM", category: .ai)
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
        // Mark objectives complete
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: "contact_source_selected",
            status: "completed",
            source: "ui_profile_draft",
            notes: "Profile submitted via \(source == .contacts ? "contacts" : "manual")",
            details: ["source": source == .contacts ? "contacts" : "manual"]
        ))
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: "contact_data_collected",
            status: "completed",
            source: "ui_profile_draft",
            notes: "Profile data collected",
            details: nil
        ))
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: "contact_data_validated",
            status: "completed",
            source: "ui_profile_draft",
            notes: "Profile validated via intake UI",
            details: nil
        ))
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: "applicant_profile",
            status: "completed",
            source: "ui_profile_draft",
            notes: "Applicant profile validated and saved",
            details: nil
        ))
        Logger.info("✅ applicant_profile objective marked complete via draft submission", category: .ai)
        // Build user message with the full profile JSON wrapped with validation status
        var userMessage = JSON()
        userMessage["role"].string = "user"
        // Create message with full JSON data including validation_status hint
        let introText = "I have provided my contact information via \(source == .contacts ? "contacts import" : "manual entry"). This data has been validated by me through the UI and is ready to use."
        // Wrap profile data with validation_status
        var wrappedData = JSON()
        wrappedData["applicant_profile"] = profileJSON
        wrappedData["validation_status"].string = "validated_by_user"
        let jsonText = wrappedData.rawString() ?? "{}"
        userMessage["content"].string = """
        \(introText)
        Profile data (JSON):
        ```json
        \(jsonText)
        ```
        An artifact record has been created with this contact information. Do NOT call validate_applicant_profile - this data is already validated.
        """
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Profile submitted with detailed data sent to LLM (source: \(source == .contacts ? "contacts" : "manual"))", category: .ai)
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
        // Mark enabled_sections objective as complete
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: "enabled_sections",
            status: "completed",
            source: "ui_section_toggle_confirmed",
            notes: "Section toggle confirmed by user",
            details: ["sections": enabled.joined(separator: ", ")]
        ))
        Logger.info("✅ enabled_sections objective marked complete", category: .ai)
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Section toggle confirmed. Enabled sections: \(enabled.joined(separator: ", "))"
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Section toggle confirmed and user message sent to LLM", category: .ai)
    }
    func rejectSectionToggle(reason: String) async {
        guard toolRouter.rejectSectionToggle(reason: reason) != nil else { return }
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Section toggle rejected. Reason: \(reason)"
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Section toggle rejected and user message sent to LLM", category: .ai)
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
            let uploadInfos = processed.map { item in
                ProcessedUploadInfo(
                    storageURL: item.storageURL,
                    contentType: item.contentType,
                    filename: item.storageURL.lastPathComponent
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
            let title = card.title
            let org = card.organization
            let start = card.start
            let end = card.end.isEmpty ? "present" : card.end
            lines.append("- [\(id)] \(title) @ \(org) (\(start) - \(end))")
        }
        return lines.joined(separator: "\n")
    }
}
