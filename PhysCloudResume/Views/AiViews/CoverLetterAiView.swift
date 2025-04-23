import Foundation
import SwiftUI
#if os(macOS)
    import AppKit
#endif

struct CoverLetterAiView: View {
    @AppStorage("openAiApiKey") var openAiApiKey: String = "none"
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = false
    @AppStorage("ttsVoice") var ttsVoice: String = "nova"
    @Binding var buttons: CoverLetterButtons
    @Binding var refresh: Bool

    var body: some View {
        // Create OpenAI client using our abstraction layer
        let openAIClient = OpenAIClientFactory.createClient(apiKey: openAiApiKey)

        // Initialize TTS provider
        let ttsProvider = OpenAITTSProvider(apiKey: openAiApiKey)

        return CoverLetterAiContentView(
            openAIClient: openAIClient,
            ttsProvider: ttsProvider,
            buttons: $buttons,
            refresh: $refresh,
            ttsEnabled: $ttsEnabled,
            ttsVoice: $ttsVoice
        )
        .onAppear { print("Ai Cover Letter") }
    }
}

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
                    // Generate New Cover Letter
                    if !buttons.runRequested {
                        Button(action: {
                            print("Generate cover letter")
                            if !cL.wrappedValue.generated {
                                cL.wrappedValue.currentMode = .generate
                            } else {
                                let newCL = coverLetterStore.createDuplicate(letter: cL.wrappedValue)
                                cL.wrappedValue = newCL
                                print("Duplicated for regeneration")
                            }
                            chatProvider.coverChatAction(
                                res: jobAppStore.selectedApp?.selectedRes,
                                jobAppStore: jobAppStore,
                                chatProvider: chatProvider,
                                buttons: $buttons
                            )
                        }) {
                            Image("ai-squiggle")
                                .font(.system(size: 20, weight: .regular))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .help("Generate new Cover Letter")
                    } else {
                        ProgressView()
                            .scaleEffect(0.75, anchor: .center)
                            .frame(width: 36, height: 36)
                    }

                    // Choose Best Cover Letter
                    if buttons.chooseBestRequested {
                        ProgressView()
                            .scaleEffect(0.75, anchor: .center)
                            .frame(width: 36, height: 36)
                    } else {
                        Button(action: {
                            chooseBestCoverLetter()
                        }) {
                            Image(systemName: "medal")
                                .font(.system(size: 20, weight: .regular))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            jobAppStore.selectedApp?.coverLetters.count ?? 0 <= 1
                                || cL.wrappedValue.writingSamplesString.isEmpty
                        )
                        .help(
                            (jobAppStore.selectedApp?.coverLetters.count ?? 0) <= 1
                                ? "At least two cover letters are required"
                                : cL.wrappedValue.writingSamplesString.isEmpty
                                ? "Add writing samples to enable choosing best cover letter"
                                : "Select the best cover letter based on style and voice"
                        )
                    }

                    // TTS Button - only show if TTS is enabled and we have content
                    if ttsEnabled && cL.wrappedValue.generated && !cL.wrappedValue.content.isEmpty {
                        Button(action: {
                            speakCoverLetter()
                        }) {
                            let iconFilled = isSpeaking || isBuffering
                            let iconName = iconFilled ? "speaker.wave.3.fill" : "speaker.wave.3"
                            Image(systemName: iconName)
                                .font(.system(size: 20, weight: .regular))
                                .frame(width: 36, height: 36)
                                .foregroundColor({ () -> Color in
                                    if isBuffering { return .yellow }
                                    else if isSpeaking { return .accentColor }
                                    if isPaused { return .accentColor }
                                    return .primary
                                }())
                                // Pulsing effect only while buffering
                                .symbolEffect(.pulse, value: isBuffering)
                        }
                        .buttonStyle(.plain)
                        .help({ () -> String in
                            if isBuffering { return "Cancel" }
                            if isSpeaking { return "Pause playback" }
                            if isPaused { return "Resume playback" }
                            return "Read cover letter aloud"
                        }())
                        .disabled(buttons.runRequested || buttons.chooseBestRequested)
                    }
                }
            }
        }
        // Stop playback if the user switches to another cover letter
        .onChange(of: cL.wrappedValue.id) { _ in
            hardStopPlayback()
        }
        .onChange(of: isBuffering) { old, new in
            print("buffering changed from \(old) to \(new)")
        }
        .onChange(of: isSpeaking) { old, new in
            print("speaking changed from \(old) to \(new)")
        }
        .onChange(of: isPaused) { old, new in
            print("paused changed from \(old) to \(new)")
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
            print("opt click stop req")
            hardStopPlayback() // clear buffer & reset UI; no automatic restart
            return
        }

        //  ————————  State machine for normal click  ————————

        // 1. Playing  →  Pause
        if isSpeaking {
            print("pause req")
            if ttsProvider.pause() {
                print("pause success")
                isSpeaking = false
                isPaused = true
            }
            return
        }

        // 2. Paused   →  Resume
        if isPaused {
            print("resume req")
            if ttsProvider.resume() {
                print("resume success")
                isSpeaking = true
                isPaused = false
            }
            return
        }

        // 3. Buffering → Cancel buffering (acts like a stop)
        if isBuffering {
            print("stop req")
            hardStopPlayback()
            return
        }

        // 4. Idle      →  Begin streaming & play
        print("start req")
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
                        print("TTS streaming error: \(error.localizedDescription)")
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
            print("[CoverLetterAiView] Initiating chooseBestCoverLetter for job: \(jobApp.jobPosition), letters: \(letters.map { $0.id.uuidString })")
            do {
                let provider = CoverLetterRecommendationProvider(
                    client: openAIClient,
                    jobApp: jobApp,
                    writingSamples: writingSamples
                )
                let result = try await provider.fetchBestCoverLetter()
                // Debug: log received BestCoverLetterResponse
                print("[CoverLetterAiView] Received BestCoverLetterResponse: \(result)")
                await MainActor.run {
                    // Debug: attempt to select best cover letter by UUID
                    let uuidString = result.bestLetterUuid
                    print("[CoverLetterAiView] Best letter UUID from response: \(uuidString)")
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
                        print("[CoverLetterAiView] No cover letter found matching UUID: \(uuidString)")
                        errorWrapper = ErrorMessageWrapper(
                            message: "No matching cover letter found for UUID: \(uuidString)"
                        )
                    }
                    buttons.chooseBestRequested = false
                }
            } catch {
                await MainActor.run {
                    print("Choose best error: \(error.localizedDescription)")
                    buttons.chooseBestRequested = false
                    errorWrapper = ErrorMessageWrapper(
                        message: "Error choosing best cover letter: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
}
