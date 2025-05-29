//
//  CoverLetterAiManager.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/24/25.
//

//
//  CoverLetterAiManager.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/24/25.
//

import Foundation
import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// Main coordinator for cover letter AI features including TTS and recommendations
/// Renamed from CoverLetterController to better reflect its comprehensive role
struct CoverLetterAiManager: View {
    // MARK: - Environment

    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(\.appState) private var appState

    // MARK: - AppStorage

    @AppStorage("preferredLLMModel") private var preferredLLMModel: String = AIModels.gpt4o_latest

    // MARK: - State

    @Binding var buttons: CoverLetterButtons
    @Binding var refresh: Bool

    // Flags to track previous state for comparison
    @State private var previousModel: String = ""
    @State private var previousIncludeResumeBG: Bool = false

    // MARK: - Bindings

    @Binding var ttsEnabled: Bool
    @Binding var ttsVoice: String
    @AppStorage("ttsInstructions") private var ttsInstructions: String = ""

    // MARK: - View Models

    @State private var ttsViewModel: TTSViewModel?
    private let recommendationService: CoverLetterRecommendationService

    // MARK: - UI State

    @State private var showTTSError: Bool = false
    @State private var errorWrapper: ErrorMessageWrapper? = nil
    @State private var showMultiModelSheet: Bool = false

    // MARK: - Dependencies

    private let client: AppLLMClientProtocol
    private let chatProvider: CoverChatProvider
    private let ttsProvider: OpenAITTSProvider?

    // MARK: - Initialization

    init(
        client: AppLLMClientProtocol,
        ttsProvider: OpenAITTSProvider?,
        buttons: Binding<CoverLetterButtons>,
        refresh: Binding<Bool>,
        ttsEnabled: Binding<Bool> = .constant(false),
        ttsVoice: Binding<String> = .constant("nova"),
        isNewConversation: Bool = true
    ) {
        self.client = client
        self.ttsProvider = ttsProvider // Store the passed provider
        chatProvider = CoverChatProvider(client: client)
        recommendationService = CoverLetterRecommendationService(client: client)

        _buttons = buttons
        _refresh = refresh
        _ttsEnabled = ttsEnabled // Store the binding
        _ttsVoice = ttsVoice

        // Initialize the TTS view model only if provider is available AND ttsEnabled is true
        // Accessing _ttsEnabled.wrappedValue directly in init can be problematic if it's not fully set up.
        // It's safer to check ttsProvider first.
        if let provider = ttsProvider { // Check if a provider was passed
            // We'll further check ttsEnabled.wrappedValue inside speakCoverLetter
            // or ensure ttsViewModel is updated if ttsEnabled changes.
            _ttsViewModel = State(initialValue: TTSViewModel(ttsProvider: provider))
//            Logger.debug("[CoverLetterAiManager] TTSViewModel INITIALIZED in init.")
        } else {
            _ttsViewModel = State(initialValue: nil) // Explicitly nil
//            Logger.debug("[CoverLetterAiManager] TTSViewModel IS NIL in init (ttsProvider was nil).")
        }

        // Handle new conversation state for toolbar button presses -
        // we'll handle this in onAppear instead of during initialization
        // to avoid escaping closure capturing mutable self issues
        handleNewConversation = isNewConversation
    }

    // Flag to track if this is a new conversation
    @State private var handleNewConversation: Bool = false

    // MARK: - Computed Properties

    /// Binding to the currently selected cover letter
    var cL: Binding<CoverLetter> {
        guard let selectedApp = jobAppStore.selectedApp else {
            // This case should ideally not happen if the view is shown correctly.
            // Return a dummy binding or handle error appropriately.
            // For now, let's print an error and return a constant dummy.
            Logger.debug("[CoverLetterAiManager] ERROR: jobAppStore.selectedApp is nil when accessing cL.")
            // Create a dummy CoverLetter to satisfy the binding requirement.
            // This part needs careful handling based on your app's logic for when cL is nil.
            let dummyCoverLetter = CoverLetter(enabledRefs: [], jobApp: nil) // Or fetch a default/placeholder
            return .constant(dummyCoverLetter)
        }
        return Binding(get: {
            // Handle the case where selectedCover might be nil
            if let selectedCover = selectedApp.selectedCover {
                return selectedCover
            } else {
                // Create a new blank cover letter if none is selected
                Logger.debug("[CoverLetterAiManager] No selected cover letter, creating a new one")
                coverLetterStore.createBlank(jobApp: selectedApp)
                // Return the newly created cover letter (should be selected automatically)
                return selectedApp.selectedCover ?? CoverLetter(enabledRefs: [], jobApp: selectedApp)
            }
        }, set: {
            selectedApp.selectedCover = $0
        })
    }

    // MARK: - Body

    var body: some View {
        // Debug: Check ttsViewModel status when body is evaluated
        // let _ = Logger.debug("[CoverLetterAiManager Body] ttsViewModel is \(ttsViewModel == nil ? "nil" : "NOT nil"), ttsEnabled is \(ttsEnabled)")

        if let vm = ttsViewModel, ttsEnabled { // Ensure vm exists and TTS is enabled for the full view
            // Full version with TTS functionality
            CoverLetterActionButtonsView(
                coverLetter: cL,
                buttons: $buttons,
                chatProvider: chatProvider,
                chooseBestAction: chooseBestCoverLetter,
                multiModelChooseBestAction: { showMultiModelSheet = true },
                speakAction: speakCoverLetter,
                ttsEnabled: $ttsEnabled,
                ttsVoice: $ttsVoice,
                isSpeaking: Binding(get: { vm.isSpeaking }, set: { vm.isSpeaking = $0 }),
                isPaused: Binding(get: { vm.isPaused }, set: { vm.isPaused = $0 }),
                isBuffering: Binding(get: { vm.isBuffering }, set: { vm.isBuffering = $0 })
            )
            // Stop playback if the user switches to another cover letter
            .onChange(of: cL.wrappedValue.id) {
                Logger.debug("[CoverLetterAiManager] Cover letter ID changed, stopping TTS.")
                vm.stop()
            }
            // Show error alert when TTS errors occur
            .onChange(of: vm.ttsError) { _, newValue in
                if newValue != nil {
                    showTTSError = true
                }
            }
            .onAppear {
                Logger.debug("[CoverLetterAiManager] Appeared (with TTSViewModel). ttsEnabled: \(ttsEnabled)")
                // Ensure TTSViewModel is correctly initialized if ttsEnabled changes after initial init
                if self.ttsViewModel == nil && self.ttsEnabled && self.ttsProvider != nil {
//                    Logger.debug("[CoverLetterAiManager] Re-initializing TTSViewModel in onAppear because ttsEnabled is true and viewModel was nil.")
                    self.ttsViewModel = TTSViewModel(ttsProvider: self.ttsProvider!)
                }
                handleNewConversationOnAppear()
                initializeStateTracking()
            }
            // Add observers for settings changes
            .onChange(of: jobAppStore.selectedApp?.selectedCover?.includeResumeRefs) {
                checkForSettingsChange()
            }
            // Watch for AI model changes
            .onChange(of: preferredLLMModel) {
                checkForSettingsChange()
            }
            .onChange(of: ttsEnabled) { _, newTtsEnabledState in
                Logger.debug("[CoverLetterAiManager] ttsEnabled changed to: \(newTtsEnabledState)")
                if newTtsEnabledState {
                    if self.ttsViewModel == nil, let provider = self.ttsProvider {
                        Logger.debug("[CoverLetterAiManager] Initializing TTSViewModel because ttsEnabled is now true.")
                        self.ttsViewModel = TTSViewModel(ttsProvider: provider)
                    }
                } else {
//                    Logger.debug("[CoverLetterAiManager] ttsEnabled is now false. Stopping TTS and clearing ViewModel.")
                    self.ttsViewModel?.stop()
                    // self.ttsViewModel = nil // Consider if you want to nil it out or just stop
                }
            }
            // Alert for recommendation results
            .alert(item: $errorWrapper) { wrapper in
                Alert(
                    title: Text("Cover Letter Recommendation"),
                    message: Text(wrapper.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            // Alert for TTS errors
            .alert("TTS Error", isPresented: $showTTSError) {
                Button("OK") {
                    showTTSError = false
                    vm.ttsError = nil
                }
            } message: {
                Text(vm.ttsError ?? "An error occurred with text-to-speech")
            }
            // Sheet for multi-model selection
            .sheet(isPresented: $showMultiModelSheet) {
                MultiModelChooseBestCoverLetterSheet(coverLetter: cL)
                    .environmentObject(ModelService())
            }
        } else {
            // Simplified version without TTS
            CoverLetterActionButtonsView(
                coverLetter: cL,
                buttons: $buttons,
                chatProvider: chatProvider,
                chooseBestAction: chooseBestCoverLetter,
                multiModelChooseBestAction: { showMultiModelSheet = true },
                speakAction: {
//                    Logger.debug("[CoverLetterAiManager] SpeakAction called but TTS is disabled or ViewModel is nil.")
                },
                ttsEnabled: $ttsEnabled,
                ttsVoice: $ttsVoice,
                isSpeaking: .constant(false),
                isPaused: .constant(false),
                isBuffering: .constant(false)
            )
            .onAppear {
//                Logger.debug("[CoverLetterAiManager] Appeared (TTS DISABLED or ViewModel nil). ttsEnabled: \(ttsEnabled)")
                handleNewConversationOnAppear()
                initializeStateTracking()
            }
            // Add observers for settings changes
            .onChange(of: jobAppStore.selectedApp?.selectedCover?.includeResumeRefs) {
                checkForSettingsChange()
            }
            // Watch for AI model changes
            .onChange(of: preferredLLMModel) {
                checkForSettingsChange()
            }
            .onChange(of: ttsEnabled) { _, newTtsEnabledState in
//                Logger.debug("[CoverLetterAiManager] ttsEnabled changed to: \(newTtsEnabledState) (in non-TTS branch)")
                // Logic to potentially re-evaluate if TTS should be enabled
                if newTtsEnabledState && self.ttsProvider != nil {
                    // This might trigger a view update if `body` re-evaluates and `ttsViewModel` becomes non-nil
//                    Logger.debug("[CoverLetterAiManager] TTS was enabled, attempting to re-initialize ViewModel if provider exists.")
                    self.ttsViewModel = TTSViewModel(ttsProvider: self.ttsProvider!)
                }
            }
            // Alert for recommendation results
            .alert(item: $errorWrapper) { wrapper in
                Alert(
                    title: Text("Cover Letter Recommendation"),
                    message: Text(wrapper.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            // Sheet for multi-model selection
            .sheet(isPresented: $showMultiModelSheet) {
                MultiModelChooseBestCoverLetterSheet(coverLetter: cL)
                    .environmentObject(ModelService())
            }
        }
    }

    private func handleNewConversationOnAppear() {
        if handleNewConversation {
            if let jobApp = jobAppStore.selectedApp,
               let letter = jobApp.selectedCover
            {
                // Clear conversation context to start a new conversation
                Logger.debug("[CoverLetterAiManager] Starting new conversation, clearing context for letter ID: \(letter.id)")
                letter.clearConversationContext()
                // Reset flag
                handleNewConversation = false
            }
        }
    }

    private func initializeStateTracking() {
        // Initialize state tracking with current model value from AppStorage
        previousModel = preferredLLMModel
        if let letter = jobAppStore.selectedApp?.selectedCover {
            previousIncludeResumeBG = letter.includeResumeRefs
        }
        Logger.debug("[CoverLetterAiManager] Initialized state tracking: previousModel=\(previousModel), previousIncludeResumeBG=\(previousIncludeResumeBG)")
        // Check for settings changes immediately
        checkForSettingsChange()
    }

    // MARK: - TTS Actions

    /// Handle toolbar TTS button interaction following the state‑chart specification.
    private func speakCoverLetter() {
//        Logger.debug("[CoverLetterAiManager] speakCoverLetter called. ttsEnabled: \(ttsEnabled). TTSViewModel is \(ttsViewModel == nil ? "nil" : "NOT nil").")

        guard let currentTTSViewModel = ttsViewModel, ttsEnabled else {
//            Logger.debug("[CoverLetterAiManager] speakCoverLetter: Bailing out. TTSViewModel is \(ttsViewModel == nil ? "nil" : "not nil"), ttsEnabled is \(ttsEnabled)")
            return
        }
//        Logger.debug("[CoverLetterAiManager] speakCoverLetter: Proceeding with TTS.")

        let optionKeyPressed = NSEvent.modifierFlags.contains(.option)

        if optionKeyPressed {
            Logger.debug("[CoverLetterAiManager] Option key pressed, stopping TTS.")
            currentTTSViewModel.stop()
            return
        }

        if currentTTSViewModel.isSpeaking {
//            Logger.debug("[CoverLetterAiManager] TTS is speaking, pausing.")
            currentTTSViewModel.pause()
            return
        }

        if currentTTSViewModel.isPaused {
//            Logger.debug("[CoverLetterAiManager] TTS is paused, resuming.")
            currentTTSViewModel.resume()
            return
        }

        if currentTTSViewModel.isBuffering {
//            Logger.debug("[CoverLetterAiManager] TTS is buffering, stopping.")
            currentTTSViewModel.stop()
            return
        }

        let content = cL.wrappedValue.content
        guard !content.isEmpty else {
//            Logger.debug("[CoverLetterAiManager] No content to speak.")
            currentTTSViewModel.ttsError = "No content to speak"
            showTTSError = true // Assuming showTTSError is observed by an alert
            return
        }

        Logger.debug("[CoverLetterAiManager] Content to speak: \(String(content.prefix(50)))...")
        let voice = OpenAITTSProvider.Voice(rawValue: ttsVoice) ?? .nova
        let instructions = ttsInstructions.isEmpty ? nil : ttsInstructions
//        Logger.debug("[CoverLetterAiManager] Using voice: \(voice.rawValue), instructions: \(instructions ?? "none")")

        currentTTSViewModel.speakContent(content, voice: voice, instructions: instructions)
    }

    // MARK: - Settings Change Detection

    /// Checks if AI settings have changed and creates a new ungenerated draft if needed
    private func checkForSettingsChange() {
        // Only create/switch drafts when on the cover letter tab
        guard appState.selectedTab == .coverLetter else {
            // Still update previous state to track changes
            previousModel = preferredLLMModel
            if let letter = jobAppStore.selectedApp?.selectedCover {
                previousIncludeResumeBG = letter.includeResumeRefs
            }
            return
        }
        
        if let jobApp = jobAppStore.selectedApp,
           let letter = jobApp.selectedCover
        {
            let modelChanged = preferredLLMModel != previousModel
            let includeBGChanged = letter.includeResumeRefs != previousIncludeResumeBG

            if (modelChanged || includeBGChanged) && letter.generated {
                Logger.debug("[CoverLetterAiManager] Settings changed for a generated letter. Model changed: \(modelChanged), BG changed: \(includeBGChanged).")

                // Check if an ungenerated draft already exists
                if let existingUngenerated = jobApp.coverLetters.first(where: { !$0.generated }) {
                    Logger.debug("[CoverLetterAiManager] Ungenerated draft already exists, selecting it.")
                    jobApp.selectedCover = existingUngenerated
                } else {
                    Logger.debug("[CoverLetterAiManager] No ungenerated draft found. Creating a new one.")
                    let newLetter = coverLetterStore.createDuplicate(letter: letter)
                    newLetter.generated = false // Mark as ungenerated
                    // The new letter should inherit includeResumeRefs from the current settings
                    newLetter.includeResumeRefs = letter.includeResumeRefs // This ensures the new draft reflects the current setting
                    jobApp.selectedCover = newLetter // Select the new ungenerated draft
                }
            }

            // Update previous state for next check
            previousModel = preferredLLMModel
            previousIncludeResumeBG = letter.includeResumeRefs
        }
    }

    // MARK: - AI Recommendation Actions

    /// Initiates the choose‑best‑cover‑letter operation
    func chooseBestCoverLetter() {
        guard let jobApp = jobAppStore.selectedApp else { return }
        let letters = jobApp.coverLetters
        buttons.chooseBestRequested = true
        Logger.debug("[CoverLetterAiManager] Choosing best cover letter.")

        // Capture writing samples from any existing cover letter
        let writingSamples = letters.first?.writingSamplesString ?? ""

        Task {
            do {
                let result = try await recommendationService.chooseBestCoverLetter(
                    jobApp: jobApp,
                    writingSamples: writingSamples
                )
                Logger.debug("[CoverLetterAiManager] Recommendation received: \(result.bestLetterUuid)")

                await MainActor.run {
                    // Attempt to select best cover letter by UUID
                    let uuidString = result.bestLetterUuid
                    if let uuid = UUID(uuidString: uuidString),
                       let best = jobApp.coverLetters.first(where: { $0.id == uuid })
                    {
                        jobAppStore.selectedApp?.selectedCover = best
                        let message = """
                        Selected "\(best.sequencedName)" as best cover letter.

                        Analysis:
                        \(result.strengthAndVoiceAnalysis)

                        Reason:
                        \(result.verdict)
                        """
                        errorWrapper = ErrorMessageWrapper(message: message)
                        Logger.debug("[CoverLetterAiManager] Best letter selected: \(best.sequencedName)")
                    } else {
                        errorWrapper = ErrorMessageWrapper(
                            message: "No matching cover letter found for UUID: \(uuidString)"
                        )
                        Logger.debug("[CoverLetterAiManager] Error: No matching cover letter for UUID \(uuidString)")
                    }
                    buttons.chooseBestRequested = false
                }
            } catch {
                Logger.debug("[CoverLetterAiManager] Error choosing best cover letter: \(error.localizedDescription)")
                await MainActor.run {
                    buttons.chooseBestRequested = false
                    errorWrapper = ErrorMessageWrapper(
                        message: "Error choosing best cover letter: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
}
