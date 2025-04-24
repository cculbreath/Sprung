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

    // MARK: - State

    @State var aiMode: CoverAiMode = .none
    @Binding var buttons: CoverLetterButtons
    @Binding var refresh: Bool

    // MARK: - Bindings

    @Binding var ttsEnabled: Bool
    @Binding var ttsVoice: String
    @AppStorage("ttsInstructions") private var ttsInstructions: String = ""

    // MARK: - View Models

    @StateObject private var ttsViewModel: TTSViewModel
    private let recommendationService: CoverLetterRecommendationService

    // MARK: - UI State

    @State private var showTTSError: Bool = false
    @State private var errorWrapper: ErrorMessageWrapper? = nil

    // MARK: - Dependencies

    private let openAIClient: OpenAIClientProtocol
    private let chatProvider: CoverChatProvider

    // MARK: - Initialization

    init(
        openAIClient: OpenAIClientProtocol,
        ttsProvider: OpenAITTSProvider,
        buttons: Binding<CoverLetterButtons>,
        refresh: Binding<Bool>,
        ttsEnabled: Binding<Bool> = .constant(false),
        ttsVoice: Binding<String> = .constant("nova")
    ) {
        self.openAIClient = openAIClient
        chatProvider = CoverChatProvider(client: openAIClient)
        recommendationService = CoverLetterRecommendationService(client: openAIClient)

        _buttons = buttons
        _refresh = refresh
        _ttsEnabled = ttsEnabled
        _ttsVoice = ttsVoice

        // Initialize the TTS view model
        _ttsViewModel = StateObject(wrappedValue: TTSViewModel(ttsProvider: ttsProvider))
    }

    // MARK: - Computed Properties

    /// Binding to the currently selected cover letter
    var cL: Binding<CoverLetter> {
        guard let selectedApp = jobAppStore.selectedApp else {
            fatalError("No selected app")
        }
        return Binding(get: {
            selectedApp.selectedCover!
        }, set: {
            selectedApp.selectedCover = $0
        })
    }

    // MARK: - Body

    var body: some View {
        CoverLetterActionButtonsView(
            coverLetter: cL,
            buttons: $buttons,
            chatProvider: chatProvider,
            chooseBestAction: chooseBestCoverLetter,
            speakAction: speakCoverLetter,
            ttsEnabled: $ttsEnabled,
            ttsVoice: $ttsVoice,
            isSpeaking: $ttsViewModel.isSpeaking,
            isPaused: $ttsViewModel.isPaused,
            isBuffering: $ttsViewModel.isBuffering
        )
        // Stop playback if the user switches to another cover letter
        .onChange(of: cL.wrappedValue.id) { _ in
            ttsViewModel.stop()
        }
        // Show error alert when TTS errors occur
        .onChange(of: ttsViewModel.ttsError) { _, newValue in
            if newValue != nil {
                showTTSError = true
            }
        }
        .onAppear {
            print("CoverLetterAiManager appeared")
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
                ttsViewModel.ttsError = nil
            }
        } message: {
            Text(ttsViewModel.ttsError ?? "An error occurred with text-to-speech")
        }
    }

    // MARK: - TTS Actions

    /// Handle toolbar TTS button interaction following the state‑chart specification.
    ///
    /// Behaviour summary
    /// 1.  Default click cycles through: Idle → Buffering → Playing → Paused → Playing …
    /// 2.  ⌥‑click always restarts a fresh streaming request from the beginning.
    /// 3.  Cover‑letter change externally stops any ongoing playback (handled separately).
    private func speakCoverLetter() {
        let optionKeyPressed = NSEvent.modifierFlags.contains(.option)

        //  ————————  Option‑click acts as a hard STOP (returns to idle)  ————————
        if optionKeyPressed {
            ttsViewModel.stop()
            return
        }

        //  ————————  State machine for normal click  ————————

        // 1. Playing  →  Pause
        if ttsViewModel.isSpeaking {
            ttsViewModel.pause()
            return
        }

        // 2. Paused   →  Resume
        if ttsViewModel.isPaused {
            ttsViewModel.resume()
            return
        }

        // 3. Buffering → Cancel buffering (acts like a stop)
        if ttsViewModel.isBuffering {
            print("CoverLetterAiManager: Canceling buffering")
            ttsViewModel.stop()
            // Force buffering state to false (double-check)
            ttsViewModel.isBuffering = false
            return
        }

        // 4. Idle      →  Begin streaming & play
        let content = cL.wrappedValue.content
        guard !content.isEmpty else {
            ttsViewModel.ttsError = "No content to speak"
            showTTSError = true
            return
        }

        let voice = OpenAITTSProvider.Voice(rawValue: ttsVoice) ?? .nova
        let instructions = ttsInstructions.isEmpty ? nil : ttsInstructions

        ttsViewModel.speakContent(content, voice: voice, instructions: instructions)
    }

    // MARK: - AI Recommendation Actions

    /// Initiates the choose‑best‑cover‑letter operation
    func chooseBestCoverLetter() {
        guard let jobApp = jobAppStore.selectedApp else { return }
        let letters = jobApp.coverLetters
        buttons.chooseBestRequested = true

        // Capture writing samples from any existing cover letter
        let writingSamples = letters.first?.writingSamplesString ?? ""

        Task {
            do {
                let result = try await recommendationService.chooseBestCoverLetter(
                    jobApp: jobApp,
                    writingSamples: writingSamples
                )

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
                    } else {
                        errorWrapper = ErrorMessageWrapper(
                            message: "No matching cover letter found for UUID: \(uuidString)"
                        )
                    }
                    buttons.chooseBestRequested = false
                }
            } catch {
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
