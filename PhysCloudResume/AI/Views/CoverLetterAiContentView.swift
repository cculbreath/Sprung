import Foundation
import SwiftUI
#if os(macOS)
    import AppKit
#endif

// Note: CoverLetterAiView has been moved to its own file: CoverLetterAiView.swift

struct CoverLetterAiContentView: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

    @State var aiMode: CoverAiMode = .none
    @Binding var buttons: CoverLetterButtons
    @Binding var refresh: Bool

    // Abstraction layer for OpenAI
    let openAIClient: OpenAIClientProtocol
    // TTS provider for speech synthesis
    let ttsProvider: OpenAITTSProvider

    // TTS related state
    @Binding var ttsEnabled: Bool
    @Binding var ttsVoice: String
    @AppStorage("ttsInstructions") private var ttsInstructions: String = ""
    @State private var isSpeaking: Bool = false
    @State private var ttsError: String? = nil
    @State private var showTTSError: Bool = false
    // Buffering state for streaming TTS
    @State private var isBuffering: Bool = false
    // True when playback has been paused via the toolbar button
    @State private var isPaused: Bool = false
    // Accumulated audio data from stream
    @State private var pendingAudioData: Data = .init()
    // Wiggle animation toggle

    // Use @Bindable for chatProvider
    @Bindable var chatProvider: CoverChatProvider
    // Wrapper for displaying result notifications or errors
    @State private var errorWrapper: ErrorMessageWrapper? = nil

    init(
        openAIClient: OpenAIClientProtocol,
        ttsProvider: OpenAITTSProvider,
        buttons: Binding<CoverLetterButtons>,
        refresh: Binding<Bool>,
        ttsEnabled: Binding<Bool> = .constant(false),
        ttsVoice: Binding<String> = .constant("nova")
    ) {
        self.openAIClient = openAIClient
        self.ttsProvider = ttsProvider
        _buttons = buttons
        chatProvider = CoverChatProvider(client: openAIClient)
        _refresh = refresh
        _ttsEnabled = ttsEnabled
        _ttsVoice = ttsVoice
    }

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

    var body: some View {
        Group {
            if jobAppStore.selectedApp?.selectedCover != nil {
                HStack(spacing: 16) {
                    GenerateCoverLetterButton(
                        cL: cL,
                        buttons: $buttons,
                        chatProvider: chatProvider
                    )
                    ChooseBestCoverLetterButton(
                        cL: cL,
                        buttons: $buttons,
                        action: chooseBestCoverLetter
                    )
                    TTSCoverLetterButton(
                        cL: cL,
                        buttons: $buttons,
                        ttsEnabled: $ttsEnabled,
                        ttsVoice: $ttsVoice,
                        isSpeaking: $isSpeaking,
                        isPaused: $isPaused,
                        isBuffering: $isBuffering,
                        speakAction: speakCoverLetter
                    )
                }
            }
        }
        // Stop playback if the user switches to another cover letter
        .onChange(of: cL.wrappedValue.id) { _ in
            hardStopPlayback()
        }
        .onChange(of: isBuffering) { old, new in
        }
        .onChange(of: isSpeaking) { old, new in
        }
        .onChange(of: isPaused) { old, new in
        }
        .onAppear { print("AI content") }
        .alert(item: $errorWrapper) { wrapper in
            Alert(
                title: Text("Cover Letter Recommendation"),
                message: Text(wrapper.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("TTS Error", isPresented: $showTTSError) {
            Button("OK") { showTTSError = false }
        } message: {
            Text(ttsError ?? "An error occurred with text-to-speech")
        }
    }

    // MARK: - Actions

    /// Handle toolbar TTS button interaction following the state‑chart specification.
    ///
    /// Behaviour summary
    /// 1.  Default click cycles through: Idle → Buffering → Playing → Paused → Playing …
    /// 2.  ⌥‑click always restarts a fresh streaming request from the beginning.
    /// 3.  Cover‑letter change externally stops any ongoing playback (handled separately).
    private func speakCoverLetter() {
        let optionKeyPressed = NSEvent.modifierFlags.contains(.option)

        //  ————————  Option‑click acts as a hard STOP (returns to idle)  ————————
        if optionKeyPressed {
            hardStopPlayback() // clear buffer & reset UI; no automatic restart
            return
        }

        //  ————————  State machine for normal click  ————————

        // 1. Playing  →  Pause
        if isSpeaking {
            if ttsProvider.pause() {
                isSpeaking = false
                isPaused = true
            }
            return
        }

        // 2. Paused   →  Resume
        if isPaused {
            if ttsProvider.resume() {
                isSpeaking = true
                isPaused = false
            }
            return
        }

        // 3. Buffering → Cancel buffering (acts like a stop)
        if isBuffering {
            hardStopPlayback()
            return
        }

        // 4. Idle      →  Begin streaming & play
        startStreamingFromBeginning()
    }

    // MARK: - Helper utilities

    /// Resets every local and provider state.
    private func hardStopPlayback() {
        ttsProvider.stopSpeaking()
        isSpeaking = false
        isPaused = false
        isBuffering = false
        pendingAudioData = Data()
    }

    /// Begins a brand‑new streaming request for the currently‑selected cover letter.
    private func startStreamingFromBeginning() {
        // Reset first
        hardStopPlayback()

        // Ensure we have some text to speak
        let content = cL.wrappedValue.content
        guard !content.isEmpty else {
            ttsError = "No content to speak"
            showTTSError = true
            return
        }

        // Strip basic markdown characters – this is *very* naive but sufficient for our use‑case.
        let cleanContent = content
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")

        // Enter buffering state; UI will pulse yellow.
        isBuffering = true
        isSpeaking = false
        isPaused = false

        let voice = OpenAITTSProvider.Voice(rawValue: ttsVoice) ?? .nova
        let instructions = ttsInstructions.isEmpty ? nil : ttsInstructions

        // Kick off streaming request.  All provider callbacks trampoline
        // back onto MainActor so we can safely mutate view‑state.
        ttsProvider.streamAndPlayText(
            cleanContent,
            voice: voice,
            instructions: instructions,
            onStart: {
                // Buffer filled enough – actual audio is about to start.
                self.isBuffering = false
                self.isSpeaking = true
                self.isPaused = false
            },
            onComplete: { error in
                DispatchQueue.main.async {
                    self.isSpeaking = false
                    self.isPaused = false
                    self.isBuffering = false // ensure UI fully resets on completion or error
                    if let error = error {
                        self.ttsError = error.localizedDescription
                        self.showTTSError = true
                    }
                }
            }
        )
    }

    /// Initiates the choose‑best‑cover‑letter operation
    func chooseBestCoverLetter() {
        guard let jobApp = jobAppStore.selectedApp else { return }
        let letters = jobApp.coverLetters
        buttons.chooseBestRequested = true

        // Capture writing samples from any existing cover letter
        let writingSamples = letters.first?.writingSamplesString ?? ""
        Task {
            // Debug: log initiation of chooseBestCoverLetter
            do {
                let provider = CoverLetterRecommendationProvider(
                    client: openAIClient,
                    jobApp: jobApp,
                    writingSamples: writingSamples
                )
                let result = try await provider.fetchBestCoverLetter()
                // Debug: log received BestCoverLetterResponse
                await MainActor.run {
                    // Debug: attempt to select best cover letter by UUID
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
                        // Debug: no matching cover letter found
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
